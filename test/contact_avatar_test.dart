import 'package:bluebubbles/models/conversation.dart';
import 'package:bluebubbles/widgets/contact_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conversation({required bool? isKnownContact}) => Conversation(
      id: 'unknown-contact-test',
      title: 'Alice Brown',
      preview: '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      avatarColors: const [CupertinoColors.systemBlue],
      messages: const [],
      isKnownContact: isKnownContact,
    );

void main() {
  testWidgets('unknown contacts use the generic silhouette', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ContactAvatar(
          conversation: _conversation(isKnownContact: false),
        ),
      ),
    );

    expect(find.text('AB'), findsNothing);
    expect(find.byKey(const ValueKey('unknown-contact-avatar')), findsOneWidget);
  });

  testWidgets('known contacts without a photo keep their initials',
      (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ContactAvatar(
          conversation: _conversation(isKnownContact: true),
        ),
      ),
    );

    expect(find.text('AB'), findsOneWidget);
  });
}
