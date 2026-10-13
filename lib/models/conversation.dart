import 'package:flutter/cupertino.dart';

enum DeliveryState { sending, delivered, read, failed }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    required this.sentAt,
    required this.isFromMe,
    this.deliveryState = DeliveryState.delivered,
  });

  final String id;
  final String text;
  final DateTime sentAt;
  final bool isFromMe;
  final DeliveryState deliveryState;
}

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.preview,
    required this.updatedAt,
    required this.avatarColors,
    required this.messages,
    this.avatarAsset,
    this.subtitle,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
  });

  final String id;
  final String title;
  String preview;
  DateTime updatedAt;
  final List<Color> avatarColors;
  final List<ChatMessage> messages;
  final String? avatarAsset;
  final String? subtitle;
  int unreadCount;
  bool isPinned;
  bool isMuted;

  String get initials {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || title.isEmpty) return '?';
    String firstCharacter(String value) =>
        String.fromCharCode(value.runes.first).toUpperCase();
    if (words.length == 1) return firstCharacter(words.first);
    return '${firstCharacter(words.first)}${firstCharacter(words.last)}';
  }
}
