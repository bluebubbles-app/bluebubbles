import 'package:bluebubbles/models/conversation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves an SMS address in portable conversation data', () {
    final conversation = Conversation(
      id: '42',
      address: '+15551234567',
      title: 'Alex',
      preview: 'Hello',
      updatedAt: DateTime.utc(2026, 10, 14, 12),
      avatarColors: const [CupertinoColors.systemBlue],
      messages: [
        ChatMessage(
          id: '7',
          text: 'Hello',
          sentAt: DateTime.utc(2026, 10, 14, 12),
          isFromMe: false,
        ),
      ],
    );

    final restored = Conversation.fromJson(conversation.toJson());

    expect(restored.address, '+15551234567');
    expect(restored.messages.single.text, 'Hello');
  });
}
