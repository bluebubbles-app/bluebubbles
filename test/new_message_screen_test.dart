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
      tester.getSize(find.byKey(const ValueKey('new-message-header'))).height,
      77,
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
      find.byKey(const ValueKey('new-message-composer-field')),
      'Hi Rocky!',
    );
    await tester.pump();
    expect(
      find.byIcon(CupertinoIcons.arrow_up_circle_fill),
      findsOneWidget,
    );
  });
}
