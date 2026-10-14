#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
manifest="$project_root/android/app/src/main/AndroidManifest.xml"
native_source="$script_dir/android_sms"
kotlin_target="$project_root/android/app/src/main/kotlin/io/github/bluebubblesapp/bluebubbles"

if [[ ! -f "$manifest" ]]; then
  echo "Android project files are missing." >&2
  echo "Run 'flutter create --platforms=android --project-name bluebubbles --org io.github.bluebubblesapp .' first." >&2
  exit 1
fi

mkdir -p "$kotlin_target"
cp "$native_source/AndroidManifest.xml" "$manifest"
cp "$native_source/MainActivity.kt" "$kotlin_target/MainActivity.kt"
cp "$native_source/SmsReceiver.kt" "$kotlin_target/SmsReceiver.kt"
cp "$native_source/MmsReceiver.kt" "$kotlin_target/MmsReceiver.kt"
cp "$native_source/RespondViaMessageService.kt" \
  "$kotlin_target/RespondViaMessageService.kt"

cd "$project_root"
flutter pub get
dart run flutter_launcher_icons

echo "Android SMS role and branding configured: BlueBubbles"
