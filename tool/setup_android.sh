#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
manifest="$project_root/android/app/src/main/AndroidManifest.xml"
native_source="$script_dir/android_sms"
kotlin_target="$project_root/android/app/src/main/kotlin/io/github/bluebubblesapp/bluebubbles"
app_gradle="$project_root/android/app/build.gradle.kts"
settings_gradle="$project_root/android/settings.gradle.kts"
vendor_source="$script_dir/vendor/android-smsmms"
vendor_target="$project_root/android/android-smsmms"

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
cp "$native_source/BlueBubblesMmsSentReceiver.kt" \
  "$kotlin_target/BlueBubblesMmsSentReceiver.kt"
cp "$native_source/RespondViaMessageService.kt" \
  "$kotlin_target/RespondViaMessageService.kt"
cp "$native_source/SmsSendCompat.kt" "$kotlin_target/SmsSendCompat.kt"

# Android does not expose a high-level MMS composer. Bundle the modernized
# transport used by QUIK for carrier-aware image and audio sending.
mkdir -p "$vendor_target"
cp -R "$vendor_source/." "$vendor_target/"

if [[ -f "$settings_gradle" ]] && \
   ! grep -q 'include(":android-smsmms")' "$settings_gradle"; then
  printf '\n%s\n' \
    'include(":android-smsmms")' \
    'project(":android-smsmms").projectDir = file("android-smsmms")' \
    >> "$settings_gradle"
fi

if [[ -f "$app_gradle" ]] && \
   ! grep -q 'implementation(project(":android-smsmms"))' "$app_gradle"; then
  printf '\n%s\n' \
    'dependencies {' \
    '    implementation(project(":android-smsmms"))' \
    '}' >> "$app_gradle"
fi

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
