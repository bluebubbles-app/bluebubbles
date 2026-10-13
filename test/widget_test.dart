import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbubbles_ui_only/main.dart';

void main() {
  testWidgets('shows the list and opens a conversation', (tester) async {
    await tester.pumpWidget(const MessagesUiApp());
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Mia Parker'), findsOneWidget);

    await tester.tap(find.text('Mia Parker'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.text('Let me know when you leave'), findsOneWidget);
  });
}
