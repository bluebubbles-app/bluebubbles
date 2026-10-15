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

# flutter_launcher_icons keeps custom-named resources from earlier runs.
# Remove only generated BlueBubbles launcher resources so Android and the
# launcher cannot resolve a stale icon after an incremental installation.
find "$project_root/android/app/src/main/res" -type f \
  \( -name 'launcher_icon*.png' -o -name 'launcher_icon*.xml' \) \
  -delete

dart run flutter_launcher_icons

# Restore the canonical manifest so the launcher resolves to the complete
# supplied artwork, with no additional inner mask or reconstruction.
cp "$native_source/AndroidManifest.xml" "$manifest"

generated_icon="$(find "$project_root/android/app/src/main/res" -type f \
  -name 'launcher_icon_v8*' -print -quit)"
if [[ -z "$generated_icon" ]]; then
  echo "BlueBubbles launcher icon generation failed." >&2
  exit 1
fi

echo "Android SMS role and branding configured: BlueBubbles"
