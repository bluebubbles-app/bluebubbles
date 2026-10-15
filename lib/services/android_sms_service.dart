import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';

class ConversationEnrichment {
  const ConversationEnrichment({
    required this.id,
    required this.address,
    required this.title,
    this.avatarBytes,
  });

  final String id;
  final String address;
  final String title;
  final Uint8List? avatarBytes;
}

class AndroidSmsController extends ChangeNotifier {
  AndroidSmsController() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const _channel = MethodChannel('bluebubbles/sms');
  static const _providerTimeout = Duration(seconds: 35);
  static const _diagnosticsTimeout = Duration(seconds: 6);

  bool supported = false;
  bool isDefaultSmsApp = false;
  bool permissionsGranted = false;
  bool contactsGranted = false;
  bool notificationsGranted = false;
  bool busy = false;
  String? lastError;
  VoidCallback? onMessagesChanged;
  ValueChanged<ConversationEnrichment>? onConversationEnriched;

  bool get isActive => supported && isDefaultSmsApp && permissionsGranted;

  String get statusLabel {
    if (!supported) return 'Preview';
    if (!isDefaultSmsApp) return 'Preview';
    if (!permissionsGranted) return 'Permissions Needed';
    return 'Default SMS App';
  }

  Future<void> initialize() => refreshState();

  Future<void> refreshState() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('getState');
      supported = raw?['supported'] == true;
      isDefaultSmsApp = raw?['isDefaultSmsApp'] == true;
      permissionsGranted = raw?['permissionsGranted'] == true;
      contactsGranted = raw?['contactsGranted'] == true;
      notificationsGranted = raw?['notificationsGranted'] == true;
      lastError = null;
    } on MissingPluginException {
      supported = false;
    } on PlatformException catch (error) {
      lastError = error.message ?? error.code;
    }
    notifyListeners();
  }

  Future<bool> requestDefaultAndPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      if (!isDefaultSmsApp) {
        await _channel.invokeMethod<bool>('requestDefaultSmsRole');
        await refreshState();
      }
      if (isDefaultSmsApp) {
        await _channel.invokeMethod<bool>('requestSmsPermissions');
        await refreshState();
      }
      return isActive;
    } on PlatformException catch (error) {
      lastError = error.message ?? error.code;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<List<Conversation>> loadConversations() async {
    if (!isActive) return const [];
    try {
      final raw = await _channel
          .invokeListMethod<Object?>('loadConversations')
          .timeout(_providerTimeout);
      lastError = null;
      return (raw ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                _conversationFromNative(Map<Object?, Object?>.from(item)),
          )
          .toList();
    } on TimeoutException {
      lastError = 'Android did not answer the SMS provider query within '
          '${_providerTimeout.inSeconds} seconds.';
      notifyListeners();
      rethrow;
    } on PlatformException catch (error) {
      lastError = error.message ?? error.code;
      notifyListeners();
      rethrow;
    }
  }

  Future<List<ChatMessage>> loadThreadMessages(
    String threadId, {
    DateTime? before,
    String? beforeMessageId,
    int limit = 40,
    bool background = false,
  }) async {
    if (!isActive) return const [];
    try {
      final arguments = <String, Object?>{
        'threadId': threadId,
        'limit': limit,
        'background': background,
      };
      if (before != null) {
        arguments['beforeTimestamp'] = before.millisecondsSinceEpoch;
        arguments['beforeMessageId'] = beforeMessageId;
      }
      final raw = await _channel.invokeListMethod<Object?>(
        'loadThreadMessages',
        arguments,
      ).timeout(_providerTimeout);
      lastError = null;
      return (raw ?? const [])
          .whereType<Map>()
          .map((item) => _messageFromNative(Map<Object?, Object?>.from(item)))
          .toList();
    } on TimeoutException {
      lastError = 'Android did not answer the message query within '
          '${_providerTimeout.inSeconds} seconds.';
      notifyListeners();
      rethrow;
    } on PlatformException catch (error) {
      lastError = error.message ?? error.code;
      notifyListeners();
      rethrow;
    }
  }

  Future<int> getSmsMessageCount() async {
    if (!isActive) return 0;
    final count = await _channel
        .invokeMethod<num>('getSmsMessageCount')
        .timeout(_providerTimeout);
    return count?.toInt() ?? 0;
  }

  Future<void> sendText(String address, String text) async {
    if (!isActive) {
      throw StateError('BlueBubbles is not the default SMS app.');
    }
    await _channel.invokeMethod<void>('sendSms', {
      'address': address,
      'text': text,
    });
  }

  Future<void> markThreadRead(String threadId) async {
    if (!isActive) return;
    await _channel.invokeMethod<void>('markThreadRead', {
      'threadId': threadId,
    });
  }

  Future<void> deleteThread(String threadId) async {
    if (!isActive) return;
    await _channel.invokeMethod<void>('deleteThread', {
      'threadId': threadId,
    });
  }

  Future<void> openDefaultSmsSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openDefaultSmsSettings');
  }

  Future<void> dialNumber(String address) async {
    if (kIsWeb || !Platform.isAndroid || address.trim().isEmpty) return;
    await _channel.invokeMethod<void>('dialNumber', {'address': address});
  }

  Future<void> openContact(String address) async {
    if (kIsWeb || !Platform.isAndroid || address.trim().isEmpty) return;
    await _channel.invokeMethod<void>('openContact', {'address': address});
  }

  Future<Map<String, Object?>> getDiagnostics() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const {'Platform': 'Android diagnostics unavailable'};
    }
    try {
      final raw = await _channel
          .invokeMapMethod<Object?, Object?>('getDiagnostics')
          .timeout(_diagnosticsTimeout);
      lastError = null;
      return {
        for (final entry in (raw ?? const {}).entries)
          entry.key.toString(): entry.value,
      };
    } on TimeoutException {
      lastError = 'Android did not answer the diagnostics request within '
          '${_diagnosticsTimeout.inSeconds} seconds.';
      notifyListeners();
      rethrow;
    } on PlatformException catch (error) {
      lastError = error.message ?? error.code;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'messagesChanged') {
      onMessagesChanged?.call();
      return;
    }
    if (call.method == 'conversationEnriched' && call.arguments is Map) {
      final raw = Map<Object?, Object?>.from(call.arguments as Map);
      onConversationEnriched?.call(
        ConversationEnrichment(
          id: (raw['id'] ?? '').toString(),
          address: (raw['address'] ?? '').toString(),
          title: (raw['title'] ?? '').toString(),
          avatarBytes: raw['avatarBytes'] is Uint8List
              ? raw['avatarBytes'] as Uint8List
              : null,
        ),
      );
    }
  }

  Conversation _conversationFromNative(Map<Object?, Object?> raw) {
    final id = (raw['id'] ?? '').toString();
    final address = (raw['address'] ?? '').toString();
    final title = (raw['title'] ?? address).toString();
    final messageItems = raw['messages'];
    final messages = messageItems is List
        ? messageItems
            .whereType<Map>()
            .map(
              (item) => _messageFromNative(
                Map<Object?, Object?>.from(item),
              ),
            )
            .toList()
        : <ChatMessage>[];
    final updatedAtMillis = (raw['updatedAt'] as num?)?.toInt() ??
        (messages.isEmpty
            ? DateTime.now().millisecondsSinceEpoch
            : messages.last.sentAt.millisecondsSinceEpoch);
    return Conversation(
      id: id,
      address: address,
      title: title.isEmpty ? address : title,
      preview: (raw['preview'] ?? '').toString(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMillis),
      avatarColors: _avatarColors(id),
      messages: messages,
      avatarBytes: raw['avatarBytes'] is Uint8List
          ? raw['avatarBytes'] as Uint8List
          : null,
      unreadCount: (raw['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  ChatMessage _messageFromNative(Map<Object?, Object?> raw) {
    final state = switch ((raw['deliveryState'] ?? '').toString()) {
      'sending' => DeliveryState.sending,
      'read' => DeliveryState.read,
      'failed' => DeliveryState.failed,
      _ => DeliveryState.delivered,
    };
    return ChatMessage(
      id: (raw['id'] ?? '').toString(),
      text: (raw['text'] ?? '').toString(),
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['sentAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      isFromMe: raw['isFromMe'] == true,
      deliveryState: state,
    );
  }

  List<Color> _avatarColors(String id) {
    const palettes = [
      [Color(0xFF5AC8FA), Color(0xFF007AFF)],
      [Color(0xFFAF52DE), Color(0xFF5856D6)],
      [Color(0xFFFF9F0A), Color(0xFFFF375F)],
      [Color(0xFF30D158), Color(0xFF00A7A5)],
      [Color(0xFFFF6482), Color(0xFFFF2D55)],
    ];
    var hash = 0;
    for (final codeUnit in id.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7FFFFFFF;
    }
    return palettes[hash % palettes.length];
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
