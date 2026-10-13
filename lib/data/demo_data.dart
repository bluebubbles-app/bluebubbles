import 'package:flutter/cupertino.dart';

import '../models/conversation.dart';

List<Conversation> demoConversations() {
  final now = DateTime.now();

  ChatMessage message(
    String id,
    String text,
    int minutesAgo, {
    required bool fromMe,
    DeliveryState state = DeliveryState.delivered,
  }) {
    return ChatMessage(
      id: id,
      text: text,
      sentAt: now.subtract(Duration(minutes: minutesAgo)),
      isFromMe: fromMe,
      deliveryState: state,
    );
  }

  return [
    Conversation(
      id: 'camille',
      title: 'Alice',
      preview: 'Perfect, see you later!',
      updatedAt: now.subtract(const Duration(minutes: 8)),
      avatarColors: const [Color(0xFFFF9A9E), Color(0xFFFAD0C4)],
      isPinned: true,
      messages: [
        message('c1', 'Are you free tonight?', 55, fromMe: false),
        message('c2', 'Yes, around 7 PM?', 51, fromMe: true),
        message('c3', 'Perfect, see you later!', 8, fromMe: false),
      ],
    ),
    Conversation(
      id: 'famille',
      title: 'Family',
      preview: 'Mom: I’ll bring dessert 🍰',
      updatedAt: now.subtract(const Duration(minutes: 32)),
      avatarColors: const [Color(0xFF84FAB0), Color(0xFF8FD3F4)],
      isPinned: true,
      unreadCount: 2,
      messages: [
        message('f1', 'Lunch together on Sunday?', 120, fromMe: false),
        message('f2', 'Great idea!', 98, fromMe: true),
        message('f3', 'I’ll bring dessert 🍰', 32, fromMe: false),
      ],
    ),
    Conversation(
      id: 'thomas',
      title: 'Noah',
      preview: 'The photo looks great',
      updatedAt: now.subtract(const Duration(hours: 1, minutes: 4)),
      avatarColors: const [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
      isPinned: true,
      messages: [
        message('t1', 'Did you get there safely?', 180, fromMe: true),
        message('t2', 'Yes, thanks! The photo looks great', 64, fromMe: false),
      ],
    ),
    Conversation(
      id: 'lea',
      title: 'Mia Parker',
      preview: 'Let me know when you leave',
      updatedAt: now.subtract(const Duration(hours: 2)),
      avatarColors: const [Color(0xFFF6D365), Color(0xFFFDA085)],
      unreadCount: 1,
      messages: [
        message('l1', 'Let me know when you leave', 120, fromMe: false),
      ],
    ),
    Conversation(
      id: 'julien',
      title: 'Liam',
      preview: 'Thank you!',
      updatedAt: now.subtract(const Duration(hours: 4)),
      avatarColors: const [Color(0xFF4FACFE), Color(0xFF00F2FE)],
      messages: [
        message('j1', 'I sent you the document.', 245, fromMe: true),
        message('j2', 'Thank you!', 240, fromMe: false),
      ],
    ),
    Conversation(
      id: 'club',
      title: 'Hiking Club',
      preview: 'We leave Saturday at 8 AM',
      updatedAt: now.subtract(const Duration(days: 1)),
      avatarColors: const [Color(0xFF43E97B), Color(0xFF38F9D7)],
      isMuted: true,
      messages: [
        message('r1', 'We leave Saturday at 8 AM', 1440, fromMe: false),
      ],
    ),
    Conversation(
      id: 'sarah',
      title: 'Sarah',
      preview: 'See you tomorrow 😊',
      updatedAt: now.subtract(const Duration(days: 2)),
      avatarColors: const [Color(0xFFFA709A), Color(0xFFFEE140)],
      messages: [
        message('s1', 'See you tomorrow 😊', 2880, fromMe: false),
      ],
    ),
  ];
}
