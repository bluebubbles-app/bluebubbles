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
- local sample data with no backend.
- BlueBubbles launcher icon and application name.

## Not included

- SMS, MMS, or RCS access;
- iMessage, Apple account, or OpenBubbles connectivity;
- database, synchronization, notifications, or contacts access;

## Run the prototype

Flutter 3.24 or later is recommended.

```text
flutter create --platforms=android .
bash tool/setup_android.sh
flutter run
```

The `flutter create` command adds the missing Android wrapper while preserving
the prototype files under `lib/`. The setup script then sets the visible app
name to `BlueBubbles` and generates all required Android launcher icon sizes
from `assets/icon/bluebubbles-circle.png`, including Android adaptive icons.

The square and circular source variants are also preserved under `assets/icon/`.

## Connect a backend later

Sample data is stored in `lib/data/demo_data.dart` and is exposed through a
temporary `DemoMessageRepository`. Replace that repository with an Android SMS
implementation while keeping the models in `lib/models/` as the interface
contract. The screens no longer need to know whether their messages came from
demo data, a JSON import, or Android's SMS/MMS provider.

To become the default Android SMS application, the native components required
by `ROLE_SMS` must be added later. That functionality is intentionally outside
the scope of this UI-only deliverable. See `SMS_MIGRATION.md` for the migration
boundary and the steps required to remove the mockups completely.

## License and attribution

This prototype preserves the OpenBubbles Apache 2.0 license for adapted
portions. See `LICENSE` and `NOTICE`. It is not affiliated with Apple and does
not contain assets extracted from Apple software.
