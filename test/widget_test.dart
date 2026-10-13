import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/screens/conversation_list_screen.dart';

void main() {
  testWidgets('shows the list and opens a conversation', (tester) async {
    await tester.pumpWidget(const MessagesUiApp());
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byKey(const ValueKey('messages-title')), findsOneWidget);
    expect(find.text('Mia Parker'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('pinned-avatar-camille'))),
      const Size(95, 95),
    );

    await tester.tap(find.text('Mia Parker'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.text('Let me know when you leave'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.mic), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.phone), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.video_camera), findsNothing);

    final headerFinder = find.byKey(const ValueKey('conversation-header'));
    final header = tester.getSize(
      headerFinder,
    );
    final headerCenter = tester.getCenter(headerFinder);
    final avatarCenter = tester.getCenter(
      find.byKey(const ValueKey('conversation-contact-avatar')),
    );
    final backCenter = tester.getCenter(
      find.byKey(const ValueKey('conversation-back-button')),
    );
    final callCenter = tester.getCenter(
      find.byKey(const ValueKey('conversation-call-button')),
    );
    final nameCenter = tester.getCenter(
      find.byKey(const ValueKey('conversation-contact-name')),
    );
    expect(header.height, inInclusiveRange(72, 116));
    expect(avatarCenter.dx, moreOrLessEquals(headerCenter.dx));
    expect(nameCenter.dx, moreOrLessEquals(headerCenter.dx));
    expect(backCenter.dy, moreOrLessEquals(avatarCenter.dy));
    expect(callCenter.dy, moreOrLessEquals(avatarCenter.dy));
    expect(nameCenter.dx, moreOrLessEquals(avatarCenter.dx));

    final messageText = tester.widget<Text>(
      find.text('Let me know when you leave'),
    );
    expect(messageText.textAlign, TextAlign.center);

    final contactName = tester.widget<Text>(find.text('Mia Parker'));
    expect(contactName.style?.fontSize, 11);

    await tester.enterText(find.byType(CupertinoTextField), 'Hello');
    await tester.pump();
    expect(find.byIcon(CupertinoIcons.arrow_up_circle_fill), findsOneWidget);
  });

  testWidgets('favorites can be unpinned from edit mode', (tester) async {
    await tester.pumpWidget(const MessagesUiApp());

    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('unpin-favorite-camille')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('pinned-avatar-camille')),
      findsNothing,
    );
    expect(find.text('Lyndsey'), findsOneWidget);
  });

  testWidgets('shows the SVG reference media and silenced state',
      (tester) async {
    await tester.pumpWidget(const MessagesUiApp());
    await tester.tap(find.text('Tobias'));
    await tester.pumpAndSettle();

    expect(find.text('5 photos'), findsOneWidget);
    expect(find.text('Tobias has notifications silenced'), findsOneWidget);
    expect(find.text('Notify Anyway'), findsOneWidget);
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
    await tester.pump(const Duration(milliseconds: 690));
    expect(find.text('Copy'), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
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
