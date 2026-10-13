# Android SMS/MMS migration

The current conversations are temporary demo data. The UI now reads them
through `MessageRepository`, so the visual screens do not depend on
`demo_data.dart`.

The production migration should replace `DemoMessageRepository` with an
Android implementation that:

1. requests the Android default SMS role (`ROLE_SMS`);
2. reads conversation threads and messages through Android's SMS/MMS content
   providers;
3. maps native thread, participant, timestamp, direction, status, and media
   fields to `Conversation` and `ChatMessage`;
4. observes content-provider changes and refreshes only affected threads;
5. sends SMS/MMS through the native Android telephony APIs;
6. stores attachment references instead of loading full media into memory;
7. removes `demo_data.dart` and `DemoMessageRepository` after the native
   repository becomes the default source.

JSON import/export already uses the same Flutter conversation model. It is a
portable BlueBubbles backup format, not an Android system SMS database dump.
Importing currently replaces the temporary in-app list after confirmation.

RCS is not exposed through the public Android SMS provider and must be treated
as a separate integration from SMS/MMS.
