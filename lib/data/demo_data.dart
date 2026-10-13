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
      title: 'Lyndsey',
      preview: 'Perfect, see you later!',
      updatedAt: now.subtract(const Duration(minutes: 8)),
      avatarColors: const [Color(0xFFFF9A9E), Color(0xFFFAD0C4)],
      avatarAsset: 'assets/avatars/lyndsey.jpg',
      isPinned: true,
      messages: [
        message('c1', 'Are you free tonight?', 55, fromMe: false),
        message('c2', 'Yes, around 7 PM?', 51, fromMe: true),
        message('c3', 'Perfect, see you later!', 8, fromMe: false),
      ],
    ),
    Conversation(
      id: 'famille',
      title: 'Mom',
      preview: 'Mom: I’ll bring dessert 🍰',
      updatedAt: now.subtract(const Duration(minutes: 32)),
      avatarColors: const [Color(0xFF84FAB0), Color(0xFF8FD3F4)],
      avatarAsset: 'assets/avatars/mom.jpg',
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
      title: 'Elliott',
      preview: 'The photo looks great',
      updatedAt: now.subtract(const Duration(hours: 1, minutes: 4)),
      avatarColors: const [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
      avatarAsset: 'assets/avatars/elliott.jpg',
      isPinned: true,
      messages: [
        message('t1', 'Did you get there safely?', 180, fromMe: true),
        message('t2', 'Yes, thanks! The photo looks great', 64, fromMe: false),
      ],
    ),
    Conversation(
      id: 'lauren',
      title: 'Lauren',
      preview: 'See you there!',
      updatedAt: now.subtract(const Duration(hours: 1, minutes: 12)),
      avatarColors: const [Color(0xFFE8D5FF), Color(0xFFB9A0FF)],
      avatarAsset: 'assets/avatars/lauren.jpg',
      isPinned: true,
      messages: [
        message('la1', 'See you there!', 72, fromMe: false),
      ],
    ),
    Conversation(
      id: 'iddris',
      title: 'Iddris',
      preview: 'That was amazing',
      updatedAt: now.subtract(const Duration(hours: 1, minutes: 20)),
      avatarColors: const [Color(0xFF69D2E7), Color(0xFF3A7CA5)],
      avatarAsset: 'assets/avatars/iddris.jpg',
      isPinned: true,
      messages: [
        message('id1', 'That was amazing', 80, fromMe: false),
      ],
    ),
    Conversation(
      id: 'neighborhood',
      title: 'The NBHD',
      preview: 'RIP to my youth',
      updatedAt: now.subtract(const Duration(hours: 1, minutes: 28)),
      avatarColors: const [Color(0xFFDCCBFF), Color(0xFFB79CFF)],
      avatarAsset: 'assets/avatars/neighborhood.jpg',
      isPinned: true,
      unreadCount: 1,
      messages: [
        message('nb1', 'RIP to my youth', 88, fromMe: false),
      ],
    ),
    Conversation(
      id: 'canyon',
      title: 'Canyon Club',
      preview: 'Next hike is Saturday',
      updatedAt: now.subtract(const Duration(hours: 1, minutes: 34)),
      avatarColors: const [Color(0xFFDADDE2), Color(0xFF8A95A5)],
      avatarAsset: 'assets/avatars/canyon.jpg',
      isPinned: true,
      messages: [
        message('ca1', 'Next hike is Saturday', 94, fromMe: false),
      ],
    ),
    Conversation(
      id: 'tobias',
      title: 'Tobias',
      preview: 'Hahaha. Anytime!',
      updatedAt: now.subtract(const Duration(hours: 1, minutes: 41)),
      avatarColors: const [Color(0xFFFFE69A), Color(0xFFFFBD59)],
      avatarAsset: 'assets/avatars/tobias.jpg',
      isPinned: true,
      isMuted: true,
      messages: [
        message('to1', 'Strong agree! Thanks for the surgery Doc!', 110,
            fromMe: false),
        message('to2', 'Hahaha. Anytime!', 101, fromMe: true),
      ],
    ),
    Conversation(
      id: 'karla',
      title: 'Karla',
      preview: 'Talk soon 💕',
      updatedAt: now.subtract(const Duration(hours: 1, minutes: 48)),
      avatarColors: const [Color(0xFFFFA8C5), Color(0xFFFF5B8E)],
      avatarAsset: 'assets/avatars/karla.jpg',
      isPinned: true,
      unreadCount: 1,
      messages: [
        message('ka1', 'Talk soon 💕', 108, fromMe: false),
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
