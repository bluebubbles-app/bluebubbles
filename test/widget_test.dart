import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/screens/conversation_list_screen.dart';

void main() {
  testWidgets('shows the list and opens a conversation', (tester) async {
    await tester.pumpWidget(const MessagesUiApp());
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Mia Parker'), findsOneWidget);

    await tester.tap(find.text('Mia Parker'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.text('Let me know when you leave'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.arrow_up_circle_fill), findsOneWidget);

    final messageText = tester.widget<Text>(
      find.text('Let me know when you leave'),
    );
    expect(messageText.textAlign, TextAlign.center);

    final contactName = tester.widget<Text>(find.text('Mia Parker'));
    expect(contactName.style?.fontSize, 17);
  });

  testWidgets('reveals mute and delete actions by swiping left',
      (tester) async {
    await tester.pumpWidget(const MessagesUiApp());

    await tester.drag(find.text('Mia Parker'), const Offset(-220, 0));
    await tester.pumpAndSettle();

    final miaRow = find.ancestor(
      of: find.text('Mia Parker'),
      matching: find.byType(SwipeableConversationRow),
    );
    expect(
      find.descendant(of: miaRow, matching: find.text('Mute')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: miaRow, matching: find.text('Delete')),
      findsOneWidget,
    );

    final transformedContent = tester.widget<Transform>(
      find.byKey(const ValueKey('swipe-content-lea')),
    );
    expect(
      transformedContent.transform.getTranslation().x,
      moreOrLessEquals(-156),
    );
  });

  testWidgets('opens message actions and enters multi-select after a hold',
      (tester) async {
    await tester.pumpWidget(const MessagesUiApp());
    await tester.tap(find.text('Mia Parker'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Let me know when you leave')),
    );
    await tester.pump(const Duration(milliseconds: 1510));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    await gesture.up();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('1 Selected'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
  });
}
