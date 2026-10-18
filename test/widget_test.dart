import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bluebubbles/data/demo_data.dart';
import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/models/conversation.dart';
import 'package:bluebubbles/screens/conversation_list_screen.dart';
import 'package:bluebubbles/widgets/message_bubble.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('conversation models survive a JSON round trip', () {
    final original = demoConversations().first;
    final encoded = jsonEncode(original.toJson());
    final restored = Conversation.fromJson(
      Map<String, Object?>.from(jsonDecode(encoded) as Map),
    );

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.messages.length, original.messages.length);
    expect(restored.messages.last.text, original.messages.last.text);
  });

  test('scales emoji-only messages by their emoji count', () {
    expect(emojiOnlyTextScale('😀'), 2);
    expect(emojiOnlyTextScale('👨‍👩‍👧‍👦'), 2);
    expect(emojiOnlyTextScale('😀 ❤️ 🎉'), 1.5);
    expect(emojiOnlyTextScale('😀😁😂🤣😃😄'), 1);
    expect(emojiOnlyTextScale('Hello 😀'), 1);
  });

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
    expect(
      find.byKey(const ValueKey('voice-message-button')),
      findsOneWidget,
    );
    expect(find.byIcon(CupertinoIcons.phone), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.video_camera), findsNothing);

    final headerFinder = find.byKey(const ValueKey('conversation-header'));
    expect(
      find.byKey(const ValueKey('conversation-header-glass')),
      findsOneWidget,
    );
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
    expect(header.height, inInclusiveRange(80, 124));
    expect(avatarCenter.dx, moreOrLessEquals(headerCenter.dx));
    expect(nameCenter.dx, moreOrLessEquals(headerCenter.dx));
    expect(backCenter.dy, moreOrLessEquals(avatarCenter.dy));
    expect(callCenter.dy, moreOrLessEquals(avatarCenter.dy));
    expect(nameCenter.dx, moreOrLessEquals(avatarCenter.dx));

    final messageText = tester.widget<Text>(
      find.text('Let me know when you leave'),
    );
    expect(messageText.textAlign, TextAlign.left);

    final contactName = tester.widget<Text>(find.text('Mia Parker'));
    expect(contactName.style?.fontSize, 12);

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

  testWidgets('opens settings from the ellipsis button', (tester) async {
    await tester.pumpWidget(const MessagesUiApp());

    await tester.tap(find.byKey(const ValueKey('open-settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Header Transparency'), findsOneWidget);
    expect(find.text('Emoji Style'), findsOneWidget);
    await tester.tap(find.text('Emoji Style'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    expect(find.text('Apple'), findsOneWidget);
    final app = tester.widget<CupertinoApp>(find.byType(CupertinoApp));
    expect(
      app.theme?.textTheme.textStyle.fontFamilyFallback?.first,
      'Apple Color Emoji',
    );
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Date Format'), findsOneWidget);
    expect(find.text('Time Format'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Import Messages'), findsOneWidget);
    expect(find.text('Export Messages'), findsOneWidget);
  });

  testWidgets('shows the SVG reference media and silenced state',
      (tester) async {
    await tester.pumpWidget(const MessagesUiApp());
    await tester.tap(find.text('Tobias'));
    await tester.pumpAndSettle();

    expect(find.text('5 photos'), findsOneWidget);
    expect(find.text('Tobias has notifications silenced'), findsOneWidget);
    expect(find.text('Notify Anyway'), findsOneWidget);

    final photoStack = find.byKey(const ValueKey('photo-message-stack'));
    await tester.ensureVisible(photoStack);
    await tester.tap(photoStack);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('full-screen-photo-viewer')),
      findsOneWidget,
    );
    expect(find.text('1 of 5'), findsOneWidget);
    final firstPhoto = find.byKey(const ValueKey('full-screen-photo-0'));
    final photoRotation = tester.widget<RotatedBox>(
      find.ancestor(
        of: firstPhoto,
        matching: find.byType(RotatedBox),
      ).first,
    );
    expect(photoRotation.quarterTurns, 1);
  });

  testWidgets('shows a conversation preview and its three actions',
      (tester) async {
    await tester.pumpWidget(const MessagesUiApp());

    await tester.longPress(find.text('Mia Parker'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('conversation-context-preview')),
      findsOneWidget,
    );
    final actions = find.byKey(
      const ValueKey('conversation-context-actions'),
    );
    expect(
      find.descendant(of: actions, matching: find.text('Pin')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: actions, matching: find.text('Hide Alerts')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: actions, matching: find.text('Delete')),
      findsOneWidget,
    );
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
