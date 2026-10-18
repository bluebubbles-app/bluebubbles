# BlueBubbles

BlueBubbles is a standalone Flutter messaging interface for Android, inspired
by the OpenBubbles Cupertino appearance and the iPhone Messages experience.

## Included

- conversation list and pinned conversations;
- local search;
- conversation screen with a contact header;
- incoming and outgoing message bubbles with tails;
- visual message grouping;
- delivery status;
- centered message text and stable bubble geometry;
- animated local message insertion and automatic scrolling;
- swipe actions for pinning, muting, and deleting conversations;
- message composer with a visible send button;
- bundled SF Pro typography and sent/received message sounds;
- light and dark modes based on the Android system setting;
- adjustable translucent/blurred conversation header;
- settings for language, date/time formats, text size, and emoji fallback;
- portable JSON message import/export;
- preview mode with local sample data and no backend;
- Android default-SMS role request from Settings;
- native reading, receiving, sending, deleting, and read-state updates for
  text SMS;
- carrier MMS image/audio sending, receiving, storage, and display;
- BlueBubbles launcher icon and application name.

## Current native limitations

- complete group-MMS composition and carrier-independent delivery receipts;
- RCS access, because Android does not expose a general public RCS API to
  third-party SMS applications;
- group-message composition and full delivery/read receipts;
- iMessage, Apple account, or OpenBubbles connectivity;
- cloud synchronization.

## Run the prototype

Flutter 3.24 or later is recommended.

```text
flutter create --platforms=android --project-name bluebubbles --org io.github.bluebubblesapp .
bash tool/setup_android.sh
flutter run
```

The `flutter create` command adds the missing Android wrapper while preserving
the prototype files under `lib/`. The setup script then sets the visible app
name to `BlueBubbles`, installs the native SMS-role components, and generates
all required Android launcher icon sizes from
`assets/icon/bluebubbles-circle.png`, including Android adaptive icons. Run the
setup script again after each pull that changes files under `tool/android_sms/`.

The square and circular source variants are also preserved under `assets/icon/`.

## Preview mode and SMS mode

The app starts in Preview Mode, so installing it does not replace the phone's
current SMS app. On first launch, an explanation offers to start Android's
default-SMS, messages, contacts, MMS-receive, and notification permission flow;
choosing **Not Now** preserves Preview Mode. The same flow remains available
from the three-dot menu under Settings. Android shows its own confirmation
dialog and BlueBubbles asks for SMS permissions only after the role is granted.
You can switch back to the previous SMS app at any time in Android's
default-app settings.

The conversation call button opens Android's dialer with the recipient filled
in, which does not require direct-call permission. Photos use Android's media
picker and voice recordings are sent as carrier MMS audio attachments.

Sample data remains in `lib/data/demo_data.dart` for Preview Mode. Once the SMS
role and permissions are active, the UI reloads lightweight conversation
summaries from Android's combined SMS/MMS thread provider, with an SMS-only
fallback. Message history is loaded on demand when a conversation is opened,
and contact thumbnails are read from Android Contacts when permission is
granted. RCS-only history remains private to its provider and cannot be read
through Android's public SMS/MMS database.
See `SMS_MIGRATION.md` for the completed bridge and the remaining work before
the demo data can be removed completely.

## License and attribution

This prototype preserves the OpenBubbles Apache 2.0 license for adapted
portions. See `LICENSE` and `NOTICE`. It is not affiliated with Apple and does
not contain assets extracted from Apple software.
