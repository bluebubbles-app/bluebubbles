# Android SMS/MMS migration

BlueBubbles now has a first native Android SMS bridge. Preview Mode still uses
`DemoMessageRepository`; real SMS mode replaces the visible list with data from
Android's SMS provider only after the user grants the default-SMS role and the
required permissions.

## Implemented

1. Android `ROLE_SMS` eligibility components and the system role request;
2. runtime SMS, contacts, MMS-receive, and notification permission requests;
3. lightweight combined SMS/MMS conversation summaries, an SMS-only fallback,
   and message history loaded only when a thread is opened;
4. Android contact-name and thumbnail lookup, plus a content observer that
   refreshes Flutter when SMS data changes;
5. text-SMS sending, multipart text support, receiving, read-state updates,
   thread deletion, and incoming-message notifications;
6. Preview Mode without changing the phone's current default SMS app.
7. first-launch permission onboarding with a Preview Mode escape hatch, plus
   permissionless handoff to Android's phone dialer.
8. carrier MMS image/audio sending and incoming MMS download, persistence,
   conversation display, and contact-aware notifications.

The generated Android wrapper is intentionally not committed. On each machine,
`tool/setup_android.sh` copies the tracked manifest and Kotlin sources from
`tool/android_sms/` into the wrapper created by Flutter.

## Remaining before daily-driver use

1. support complete group-MMS composition and a complete new-conversation flow;
2. persist pin/mute UI metadata independently of Android's SMS provider;
3. add complete delivery receipts, SIM selection, failure recovery, and background
   migration tests;
4. remove demo data only when Preview Mode is intentionally retired.

JSON import/export is a portable BlueBubbles backup format, not an Android
system SMS database dump. RCS is not exposed through the public Android SMS
provider and remains outside this bridge.
