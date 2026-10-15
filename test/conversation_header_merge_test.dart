import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluebubbles/data/conversation_header_merge.dart';
import 'package:bluebubbles/models/conversation.dart';

Conversation conversation({
  required String title,
  String? address,
  String preview = 'Old preview',
}) =>
    Conversation(
      id: '42',
      title: title,
      preview: preview,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      avatarColors: const [CupertinoColors.systemGrey],
      messages: const [],
      address: address,
      unreadCount: 1,
    );

void main() {
  test('keeps a resolved contact name during provider refresh', () {
    final cached = conversation(title: 'Alice Martin', address: '+331234');
    final provider = conversation(
      title: '+331234',
      address: '+331234',
      preview: 'Fresh preview',
    )
      ..updatedAt = DateTime.fromMillisecondsSinceEpoch(2)
      ..unreadCount = 0;

    final merged = mergeConversationHeaders(
      current: [cached],
      incoming: [provider],
    ).single;

    expect(merged, same(cached));
    expect(merged.title, 'Alice Martin');
    expect(merged.preview, 'Fresh preview');
    expect(merged.unreadCount, 0);
  });

  test('uses the provider title when no resolved title is cached', () {
    final cached = conversation(title: 'Conversation');
    final provider = conversation(title: '+331234', address: '+331234');

    final merged = mergeConversationHeaders(
      current: [cached],
      incoming: [provider],
    ).single;

    expect(merged.title, '+331234');
  });
}
