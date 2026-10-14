# Android SMS/MMS migration

BlueBubbles now has a first native Android SMS bridge. Preview Mode still uses
`DemoMessageRepository`; real SMS mode replaces the visible list with data from
Android's SMS provider only after the user grants the default-SMS role and the
required permissions.

## Implemented

1. Android `ROLE_SMS` eligibility components and the system role request;
2. runtime SMS, contacts, MMS-receive, and notification permission requests;
3. native SMS provider reads mapped to `Conversation` and `ChatMessage`;
4. a content observer that refreshes Flutter when SMS data changes;
5. text-SMS sending, multipart text support, receiving, read-state updates,
   thread deletion, and incoming-message notifications;
6. Preview Mode without changing the phone's current default SMS app.

The generated Android wrapper is intentionally not committed. On each machine,
`tool/setup_android.sh` copies the tracked manifest and Kotlin sources from
`tool/android_sms/` into the wrapper created by Flutter.

## Remaining before daily-driver use

1. parse, store, display, and send MMS attachments instead of only preserving
   incoming raw MMS payloads;
2. support group threads and a complete new-conversation flow;
3. persist pin/mute UI metadata independently of Android's SMS provider;
4. add delivery broadcasts, SIM selection, failure recovery, and background
   migration tests;
5. remove demo data only when Preview Mode is intentionally retired.

JSON import/export is a portable BlueBubbles backup format, not an Android
system SMS database dump. RCS is not exposed through the public Android SMS
provider and remains outside this bridge.
