import 'package:bluebubbles/models/conversation.dart';
import 'package:bluebubbles/widgets/message_bubble.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a short message bubble shrink-wraps its text', (tester) async {
    final message = ChatMessage(
      id: 'layout-test',
      text: 'Hi',
      sentAt: DateTime(2026),
      isFromMe: true,
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: MessageBubble(
              message: message,
              showTail: true,
              compactTop: false,
            ),
          ),
        ),
      ),
    );

    final text = find.text('Hi');
    final bubble = find
        .ancestor(of: text, matching: find.byType(CustomPaint))
        .first;

    expect(tester.widget<Text>(text).textAlign, TextAlign.left);
    expect(tester.getSize(bubble).width, lessThan(80));
  });
}
