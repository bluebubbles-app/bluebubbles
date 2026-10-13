# Supplied APK analysis

- Analyzed file: `OpenBubbles.apk`
- Size: 83,027,775 bytes
- SHA-256: `EA6C9B86A48E5074E8BBDCE81ABE0BF2626534552D7D5DE4DA418183E758E97D`
- Detected technology: Flutter

## Visual resources found

The APK contains the Inter, Alegreya, Nunito, and Roboto Condensed fonts,
Flutter's Cupertino icon font, reaction symbols, OpenBubbles branding, and a
small set of functional images. It does not contain Apple's San Francisco font.

Production Dart code is compiled inside the APK. The public OpenBubbles source
was therefore used as the reliable reference for separating the interface from
the backend instead of attempting to reconstruct compiled code.

## Interface elements reviewed

- Cupertino conversation list and header;
- conversation rows and pinned contacts;
- conversation header;
- message bubbles and tail geometry;
- message composer and send button;
- colors, spacing, and light/dark states.

## Excluded content

- `.env` and any sensitive configuration;
- Apple authentication and setup scripts;
- Rust code, network services, synchronization, and notifications;
- database and iMessage-specific models;
- OpenBubbles branding and assets not required by the prototype;
- proprietary Apple assets.

The result is a standalone front-end implementation. Bubble-tail geometry is
the only directly adapted algorithm. It is identified in the source and is
covered by the included Apache License 2.0.
