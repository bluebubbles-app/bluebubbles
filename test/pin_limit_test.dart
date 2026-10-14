import 'package:bluebubbles/models/conversation.dart';
import 'package:bluebubbles/screens/conversation_list_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conversation(int index, {required bool isPinned}) => Conversation(
      id: 'conversation-$index',
      title: 'Contact $index',
      preview: 'Message $index',
      updatedAt: DateTime(2026, 1, index + 1),
      avatarColors: const [CupertinoColors.systemBlue],
      messages: const [],
      isPinned: isPinned,
    );

void main() {
  test('allows no more than nine pinned conversations', () {
    final eightPinned = List.generate(
      8,
      (index) => _conversation(index, isPinned: true),
    );
    final ninePinned = List.generate(
      9,
      (index) => _conversation(index, isPinned: true),
    );

    expect(maxPinnedConversations, 9);
    expect(hasAvailablePinSlot(eightPinned), isTrue);
    expect(hasAvailablePinSlot(ninePinned), isFalse);
  });
}
