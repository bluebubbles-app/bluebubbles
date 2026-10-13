import '../models/conversation.dart';

/// The UI depends on this contract instead of Android SMS APIs directly.
/// The demo implementation can be replaced by an Android SMS/MMS repository
/// without changing the conversation screens.
abstract interface class MessageRepository {
  List<Conversation> get conversations;

  void sendMessage(Conversation conversation, String text);

  void replaceAll(Iterable<Conversation> conversations);
}

class DemoMessageRepository implements MessageRepository {
  DemoMessageRepository(Iterable<Conversation> seed)
      : _conversations = List<Conversation>.of(seed);

  final List<Conversation> _conversations;

  @override
  List<Conversation> get conversations => _conversations;

  @override
  void sendMessage(Conversation conversation, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now();
    conversation.messages.add(
      ChatMessage(
        id: now.microsecondsSinceEpoch.toString(),
        text: trimmed,
        sentAt: now,
        isFromMe: true,
        deliveryState: DeliveryState.delivered,
      ),
    );
    conversation.preview = trimmed;
    conversation.updatedAt = now;
    conversation.unreadCount = 0;
  }

  @override
  void replaceAll(Iterable<Conversation> conversations) {
    _conversations
      ..clear()
      ..addAll(conversations);
  }
}
