import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

enum DeliveryState { sending, sent, delivered, read, failed }

enum MessageAttachmentKind { image, audio }

class MessageAttachment {
  const MessageAttachment({
    required this.kind,
    required this.uri,
    required this.mimeType,
    this.name,
    this.localPath,
    this.thumbnailBytes,
    this.durationMilliseconds,
  });

  final MessageAttachmentKind kind;
  final String uri;
  final String mimeType;
  final String? name;
  final String? localPath;
  final Uint8List? thumbnailBytes;
  final int? durationMilliseconds;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'uri': uri,
        'mimeType': mimeType,
        'name': name,
        'localPath': localPath,
        'durationMilliseconds': durationMilliseconds,
      };

  factory MessageAttachment.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'] as String?;
    return MessageAttachment(
      kind: MessageAttachmentKind.values.firstWhere(
        (value) => value.name == kindName,
        orElse: () => MessageAttachmentKind.image,
      ),
      uri: json['uri'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      name: json['name'] as String?,
      localPath: json['localPath'] as String?,
      durationMilliseconds:
          (json['durationMilliseconds'] as num?)?.toInt(),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    required this.sentAt,
    required this.isFromMe,
    this.deliveryState = DeliveryState.delivered,
    this.attachment,
  });

  final String id;
  final String text;
  final DateTime sentAt;
  final bool isFromMe;
  final DeliveryState deliveryState;
  final MessageAttachment? attachment;

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'sentAt': sentAt.toIso8601String(),
        'isFromMe': isFromMe,
        'deliveryState': deliveryState.name,
        'attachment': attachment?.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, Object?> json) {
    final stateName = json['deliveryState'] as String?;
    final deliveryState = DeliveryState.values.firstWhere(
      (value) => value.name == stateName,
      orElse: () => DeliveryState.delivered,
    );
    return ChatMessage(
      id: json['id'] as String,
      text: json['text'] as String,
      sentAt: DateTime.parse(json['sentAt'] as String),
      isFromMe: json['isFromMe'] as bool,
      deliveryState: deliveryState,
      attachment: json['attachment'] is Map
          ? MessageAttachment.fromJson(
              Map<String, Object?>.from(json['attachment'] as Map),
            )
          : null,
    );
  }
}

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.preview,
    required this.updatedAt,
    required this.avatarColors,
    required this.messages,
    this.address,
    this.avatarBytes,
    this.avatarAsset,
    this.subtitle,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
  });

  final String id;
  String title;
  String preview;
  DateTime updatedAt;
  final List<Color> avatarColors;
  final List<ChatMessage> messages;
  String? address;
  Uint8List? avatarBytes;
  final String? avatarAsset;
  final String? subtitle;
  int unreadCount;
  bool isPinned;
  bool isMuted;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'preview': preview,
        'updatedAt': updatedAt.toIso8601String(),
        'avatarColors': avatarColors.map((color) => color.value).toList(),
        'messages': messages.map((message) => message.toJson()).toList(),
        'address': address,
        'subtitle': subtitle,
        'unreadCount': unreadCount,
        'isPinned': isPinned,
        'isMuted': isMuted,
      };

  factory Conversation.fromJson(Map<String, Object?> json) {
    final colors = (json['avatarColors'] as List<Object?>? ?? const [])
        .whereType<int>()
        .map(Color.new)
        .toList();
    final messages = (json['messages'] as List<Object?>? ?? const [])
        .whereType<Map>()
        .map(
          (value) => ChatMessage.fromJson(
            Map<String, Object?>.from(value),
          ),
        )
        .toList();
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String,
      preview: json['preview'] as String? ??
          (messages.isEmpty ? '' : messages.last.text),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      avatarColors: colors.isEmpty
          ? const [Color(0xFF8E8E93), Color(0xFF636366)]
          : colors,
      messages: messages,
      address: json['address'] as String?,
      subtitle: json['subtitle'] as String?,
      unreadCount: json['unreadCount'] as int? ?? 0,
      isPinned: json['isPinned'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
    );
  }

  String get initials {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || title.isEmpty) return '?';
    String firstCharacter(String value) =>
        String.fromCharCode(value.runes.first).toUpperCase();
    if (words.length == 1) return firstCharacter(words.first);
    return '${firstCharacter(words.first)}${firstCharacter(words.last)}';
  }
}
