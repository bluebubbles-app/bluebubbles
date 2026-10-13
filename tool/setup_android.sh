#!/usr/bin/env bash

set -euo pipefail

manifest="android/app/src/main/AndroidManifest.xml"

if [[ ! -f "$manifest" ]]; then
  echo "Android project files are missing." >&2
  echo "Run 'flutter create --platforms=android --project-name bluebubbles --org io.github.bluebubblesapp .' first." >&2
  exit 1
fi

perl -0pi -e 's/android:label="[^"]*"/android:label="BlueBubbles"/' "$manifest"

flutter pub get
dart run flutter_launcher_icons

echo "Android branding configured: BlueBubbles"
