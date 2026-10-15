import '../models/conversation.dart';

/// Applies fresh provider metadata without replacing a resolved contact name
/// with the provider's temporary raw phone number.
List<Conversation> mergeConversationHeaders({
  required Iterable<Conversation> current,
  required Iterable<Conversation> incoming,
}) {
  final existing = {
    for (final conversation in current) conversation.id: conversation,
  };

  return incoming.map((fresh) {
    final conversation = existing[fresh.id];
    if (conversation == null) return fresh;

    if (fresh.address?.isNotEmpty == true) {
      conversation.address = fresh.address;
    }
    final currentTitle = conversation.title.trim();
    final freshTitle = fresh.title.trim();
    if ((currentTitle.isEmpty || currentTitle == 'Conversation') &&
        freshTitle.isNotEmpty &&
        freshTitle != 'Conversation') {
      conversation.title = freshTitle;
    }
    if (!fresh.updatedAt.isBefore(conversation.updatedAt)) {
      conversation
        ..preview = fresh.preview
        ..updatedAt = fresh.updatedAt;
    }
    conversation.unreadCount = fresh.unreadCount;
    return conversation;
  }).toList();
}
