import 'package:bluebubbles/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('new message screen follows the compact iOS compose flow',
      (tester) async {
    await tester.pumpWidget(const MessagesUiApp());

    await tester.tap(find.byKey(const ValueKey('new-message-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('new-message-header')), findsOneWidget);
    expect(find.text('New Message'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      tester.getRect(find.text('New Message')).right,
      lessThanOrEqualTo(tester.getRect(find.text('Cancel')).left),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('new-message-header'))).height,
      44,
    );
    expect(
      find.byKey(const ValueKey('new-message-recipient-row')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('new-message-recipient-row')))
          .height,
      47,
    );
    expect(
      find.byKey(const ValueKey('new-message-add-recipient-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('new-message-composer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('new-message-attachment-button')),
      findsOneWidget,
    );
    expect(find.byIcon(CupertinoIcons.camera_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.photo_on_rectangle), findsNothing);
    expect(find.text('Mia Parker'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('new-message-recipient-field')),
      'Mia',
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Mia Parker'), findsOneWidget);

    await tester.tap(find.text('Mia Parker'));
    await tester.pump();
    expect(find.text('Mia Parker'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('new-message-composer')),
        matching: find.byType(CupertinoTextField),
      ),
      'Hi Rocky!',
    );
    await tester.pump();
    expect(
      find.byIcon(CupertinoIcons.arrow_up_circle_fill),
      findsOneWidget,
    );
  });
}
