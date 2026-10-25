#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
manifest="$project_root/android/app/src/main/AndroidManifest.xml"
native_source="$script_dir/android_sms"
kotlin_target="$project_root/android/app/src/main/kotlin/io/github/bluebubblesapp/bluebubbles"
icon_source="$project_root/assets/icon/app-icons"
icon_target="$project_root/android/app/src/main/res/drawable-nodpi"
vendor_source="$script_dir/vendor/android-smsmms"
vendor_target="$project_root/android/android-smsmms"

# Gradle prefers the Groovy file when both variants are present. Configure the
# same file that Gradle will actually read instead of assuming a recent Flutter
# template always uses Kotlin DSL.
if [[ -f "$project_root/android/app/build.gradle" ]]; then
  app_gradle="$project_root/android/app/build.gradle"
  app_gradle_dsl="groovy"
elif [[ -f "$project_root/android/app/build.gradle.kts" ]]; then
  app_gradle="$project_root/android/app/build.gradle.kts"
  app_gradle_dsl="kotlin"
else
  echo "Android app Gradle file is missing." >&2
  exit 1
fi

if [[ -f "$project_root/android/settings.gradle" ]]; then
  settings_gradle="$project_root/android/settings.gradle"
  settings_gradle_dsl="groovy"
elif [[ -f "$project_root/android/settings.gradle.kts" ]]; then
  settings_gradle="$project_root/android/settings.gradle.kts"
  settings_gradle_dsl="kotlin"
else
  echo "Android settings Gradle file is missing." >&2
  exit 1
fi

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

# Keep each user-selectable launcher icon as the exact supplied square
# artwork. Android applies the device launcher mask; Flutter uses the same
# files for the iOS-shaped previews in Settings.
mkdir -p "$icon_target"
cp "$icon_source/modern_blue.png" "$icon_target/app_icon_modern_blue.png"
cp "$icon_source/modern_green.png" "$icon_target/app_icon_modern_green.png"
cp "$icon_source/classic_blue.png" "$icon_target/app_icon_classic_blue.png"
cp "$icon_source/classic_green.png" "$icon_target/app_icon_classic_green.png"

# Android does not expose a high-level MMS composer. Bundle the modernized
# transport used by QUIK for carrier-aware image and audio sending.
mkdir -p "$vendor_target"
cp -R "$vendor_source/." "$vendor_target/"

if ! grep -q 'android-smsmms' "$settings_gradle"; then
  if [[ "$settings_gradle_dsl" == "groovy" ]]; then
    printf '\n%s\n' \
      "include ':android-smsmms'" \
      "project(':android-smsmms').projectDir = file('android-smsmms')" \
      >> "$settings_gradle"
  else
    printf '\n%s\n' \
      'include(":android-smsmms")' \
      'project(":android-smsmms").projectDir = file("android-smsmms")' \
      >> "$settings_gradle"
  fi
fi

if ! grep -q 'android-smsmms' "$app_gradle"; then
  if [[ "$app_gradle_dsl" == "groovy" ]]; then
    printf '\n%s\n' \
      'dependencies {' \
      "    implementation project(':android-smsmms')" \
      '}' >> "$app_gradle"
  else
    printf '\n%s\n' \
      'dependencies {' \
      '    implementation(project(":android-smsmms"))' \
      '}' >> "$app_gradle"
  fi
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
