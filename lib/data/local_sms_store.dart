import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/conversation.dart';
import '../models/sms_search_hit.dart';
import '../theme/contact_avatar_palette.dart';

/// Local read model for the Android SMS provider.
///
/// Android remains the source of truth. The UI reads this database so route
/// transitions and scrolling never wait for a ContentProvider query.
class LocalSmsStore {
  static const _databaseName = 'bluebubbles_sms_cache.db';
  static const _databaseVersion = 1;

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    final opening = _opening;
    if (opening != null) return opening;
    final future = _open();
    _opening = future;
    try {
      final database = await future;
      _database = database;
      return database;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _open() async {
    final databasePath = path.join(
      await getDatabasesPath(),
      _databaseName,
    );
    return openDatabase(
      databasePath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=NORMAL');
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            address TEXT,
            title TEXT NOT NULL,
            preview TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            unread_count INTEGER NOT NULL DEFAULT 0,
            avatar_bytes BLOB,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            is_muted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            thread_id TEXT NOT NULL,
            id TEXT NOT NULL,
            text TEXT NOT NULL,
            sent_at INTEGER NOT NULL,
            order_id INTEGER NOT NULL,
            is_from_me INTEGER NOT NULL,
            delivery_state TEXT NOT NULL,
            PRIMARY KEY (thread_id, id),
            FOREIGN KEY (thread_id) REFERENCES conversations(id)
              ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE INDEX messages_thread_date
          ON messages(thread_id, sent_at DESC, order_id DESC)
        ''');
        await db.execute('''
          CREATE TABLE thread_sync (
            thread_id TEXT PRIMARY KEY,
            fully_synced INTEGER NOT NULL DEFAULT 0,
            synced_at INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (thread_id) REFERENCES conversations(id)
              ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<List<Conversation>> loadConversations() async {
    final db = await _db;
    final rows = await db.query(
      'conversations',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_conversationFromRow).toList();
  }

  Future<int> countMessages() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COUNT(*) FROM messages');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<SmsSearchHit>> searchMessages(
    String searchText, {
    int limit = 250,
  }) async {
    final query = searchText.trim();
    if (query.isEmpty) return const <SmsSearchHit>[];
    final db = await _db;
    final rows = await db.rawQuery(
      '''
        SELECT thread_id, id, text, sent_at, is_from_me
        FROM messages
        WHERE text LIKE ? COLLATE NOCASE
        ORDER BY sent_at DESC, order_id DESC
        LIMIT ?
      ''',
      ['%$query%', limit],
    );
    return rows
        .map(
          (row) => SmsSearchHit(
            threadId: row['thread_id'] as String,
            messageId: row['id'] as String,
            text: row['text'] as String,
            sentAt: DateTime.fromMillisecondsSinceEpoch(row['sent_at'] as int),
            isFromMe: row['is_from_me'] == 1,
          ),
        )
        .toList();
  }

  Future<void> replaceConversationHeaders(
    Iterable<Conversation> conversations,
  ) async {
    final db = await _db;
    final incoming = conversations.toList();
    await db.transaction((transaction) async {
      final existingRows = await transaction.query(
        'conversations',
        columns: const ['id'],
      );
      final incomingIds = incoming.map((item) => item.id).toSet();
      final batch = transaction.batch();
      for (final conversation in incoming) {
        final values = _conversationRow(conversation);
        batch.update(
          'conversations',
          values,
          where: 'id = ?',
          whereArgs: [conversation.id],
        );
        batch.insert(
          'conversations',
          values,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final row in existingRows) {
        final id = row['id'] as String;
        if (!incomingIds.contains(id)) {
          batch.delete('conversations', where: 'id = ?', whereArgs: [id]);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateConversation(Conversation conversation) async {
    final db = await _db;
    final values = _conversationRow(conversation);
    final updated = await db.update(
      'conversations',
      values,
      where: 'id = ?',
      whereArgs: [conversation.id],
    );
    if (updated == 0) {
      await db.insert(
        'conversations',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> updateEnrichment({
    required String threadId,
    required String address,
    required String title,
    Uint8List? avatarBytes,
  }) async {
    final values = <String, Object?>{};
    if (address.isNotEmpty) values['address'] = address;
    if (title.isNotEmpty) values['title'] = title;
    if (avatarBytes != null) values['avatar_bytes'] = avatarBytes;
    if (values.isEmpty) return;
    final db = await _db;
    await db.update(
      'conversations',
      values,
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<List<ChatMessage>> loadRecentMessages(
    String threadId, {
    int limit = 40,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'sent_at DESC, order_id DESC',
      limit: limit,
    );
    return rows.reversed.map(_messageFromRow).toList();
  }

  Future<List<ChatMessage>> loadMessageWindow(
    String threadId,
    String messageId, {
    int radius = 40,
  }) async {
    final db = await _db;
    final targetRows = await db.query(
      'messages',
      where: 'thread_id = ? AND id = ?',
      whereArgs: [threadId, messageId],
      limit: 1,
    );
    if (targetRows.isEmpty) return const <ChatMessage>[];

    final target = targetRows.first;
    final sentAt = target['sent_at'] as int;
    final orderId = target['order_id'] as int;
    final olderRows = await db.query(
      'messages',
      where: 'thread_id = ? AND '
          '(sent_at < ? OR (sent_at = ? AND order_id < ?))',
      whereArgs: [threadId, sentAt, sentAt, orderId],
      orderBy: 'sent_at DESC, order_id DESC',
      limit: radius,
    );
    final newerRows = await db.query(
      'messages',
      where: 'thread_id = ? AND '
          '(sent_at > ? OR (sent_at = ? AND order_id > ?))',
      whereArgs: [threadId, sentAt, sentAt, orderId],
      orderBy: 'sent_at ASC, order_id ASC',
      limit: radius,
    );
    return [
      ...olderRows.reversed.map(_messageFromRow),
      _messageFromRow(target),
      ...newerRows.map(_messageFromRow),
    ];
  }

  Future<List<ChatMessage>> loadMessagesBefore(
    String threadId,
    ChatMessage before, {
    int limit = 40,
  }) async {
    final db = await _db;
    final beforeOrder = _messageOrder(before.id);
    final rows = await db.query(
      'messages',
      where: 'thread_id = ? AND '
          '(sent_at < ? OR (sent_at = ? AND order_id < ?))',
      whereArgs: [
        threadId,
        before.sentAt.millisecondsSinceEpoch,
        before.sentAt.millisecondsSinceEpoch,
        beforeOrder,
      ],
      orderBy: 'sent_at DESC, order_id DESC',
      limit: limit,
    );
    return rows.reversed.map(_messageFromRow).toList();
  }

  Future<ChatMessage?> oldestMessage(String threadId) async {
    final db = await _db;
    final rows = await db.query(
      'messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'sent_at ASC, order_id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : _messageFromRow(rows.first);
  }

  Future<void> storeMessagePage(
    String threadId,
    Iterable<ChatMessage> messages, {
    required bool reachedBeginning,
  }) async {
    final db = await _db;
    final page = messages.toList();
    await db.transaction((transaction) async {
      final batch = transaction.batch();
      for (final message in page) {
        batch.insert(
          'messages',
          _messageRow(threadId, message),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      final now = DateTime.now().millisecondsSinceEpoch;
      await transaction.insert(
        'thread_sync',
        {
          'thread_id': threadId,
          'fully_synced': reachedBeginning ? 1 : 0,
          'synced_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await transaction.update(
        'thread_sync',
        {
          if (reachedBeginning) 'fully_synced': 1,
          'synced_at': now,
        },
        where: 'thread_id = ?',
        whereArgs: [threadId],
      );
    });
  }

  Future<bool> isThreadFullySynced(String threadId) async {
    final db = await _db;
    final rows = await db.query(
      'thread_sync',
      columns: const ['fully_synced'],
      where: 'thread_id = ?',
      whereArgs: [threadId],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['fully_synced'] == 1;
  }

  Future<bool> threadNeedsSync(
    String threadId,
    DateTime providerUpdatedAt,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'thread_sync',
      columns: const ['fully_synced', 'synced_at'],
      where: 'thread_id = ?',
      whereArgs: [threadId],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    final row = rows.first;
    if (row['fully_synced'] != 1) return true;
    return providerUpdatedAt.millisecondsSinceEpoch > (row['synced_at'] as int);
  }

  Future<void> deleteMessage(String threadId, String messageId) async {
    final db = await _db;
    await db.delete(
      'messages',
      where: 'thread_id = ? AND id = ?',
      whereArgs: [threadId, messageId],
    );
  }

  Future<void> deleteConversation(String threadId) async {
    final db = await _db;
    await db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> markConversationRead(String threadId) async {
    final db = await _db;
    await db.update(
      'conversations',
      const {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Map<String, Object?> _conversationRow(Conversation conversation) => {
        'id': conversation.id,
        'address': conversation.address,
        'title': conversation.title,
        'preview': conversation.preview,
        'updated_at': conversation.updatedAt.millisecondsSinceEpoch,
        'unread_count': conversation.unreadCount,
        'avatar_bytes': conversation.avatarBytes,
        'is_pinned': conversation.isPinned ? 1 : 0,
        'is_muted': conversation.isMuted ? 1 : 0,
      };

  Conversation _conversationFromRow(Map<String, Object?> row) {
    final id = row['id'] as String;
    final rawAvatar = row['avatar_bytes'];
    final avatarBytes = switch (rawAvatar) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => null,
    };
    return Conversation(
      id: id,
      address: row['address'] as String?,
      title: row['title'] as String,
      preview: row['preview'] as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      avatarColors: contactAvatarColors(id),
      avatarBytes: avatarBytes,
      unreadCount: row['unread_count'] as int,
      isPinned: row['is_pinned'] == 1,
      isMuted: row['is_muted'] == 1,
      messages: [],
    );
  }

  Map<String, Object?> _messageRow(
    String threadId,
    ChatMessage message,
  ) => {
        'thread_id': threadId,
        'id': message.id,
        'text': message.text,
        'sent_at': message.sentAt.millisecondsSinceEpoch,
        'order_id': _messageOrder(message.id),
        'is_from_me': message.isFromMe ? 1 : 0,
        'delivery_state': message.deliveryState.name,
      };

  ChatMessage _messageFromRow(Map<String, Object?> row) => ChatMessage(
        id: row['id'] as String,
        text: row['text'] as String,
        sentAt: DateTime.fromMillisecondsSinceEpoch(row['sent_at'] as int),
        isFromMe: row['is_from_me'] == 1,
        deliveryState: DeliveryState.values.firstWhere(
          (state) => state.name == row['delivery_state'],
          orElse: () => DeliveryState.delivered,
        ),
      );

  int _messageOrder(String id) {
    final numeric = id.startsWith('mms-') ? id.substring(4) : id;
    return int.tryParse(numeric) ?? id.hashCode;
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }
}
