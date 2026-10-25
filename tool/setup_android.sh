#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
manifest="$project_root/android/app/src/main/AndroidManifest.xml"
launcher_overlay_source="$script_dir/android_sms/AndroidManifest.launcher-overlay.xml"
native_source="$script_dir/android_sms"
kotlin_target="$project_root/android/app/src/main/kotlin/io/github/bluebubblesapp/bluebubbles"
icon_source="$project_root/assets/icon/app-icons"
icon_adaptive_source="$script_dir/android_sms/app_icons"
icon_drawable_target="$project_root/android/app/src/main/res/drawable-nodpi"
icon_legacy_target="$project_root/android/app/src/main/res/mipmap-nodpi"
icon_adaptive_target="$project_root/android/app/src/main/res/mipmap-anydpi-v26"
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
for variant in debug profile release; do
  variant_manifest_dir="$project_root/android/app/src/$variant"
  mkdir -p "$variant_manifest_dir"
  cp "$launcher_overlay_source" "$variant_manifest_dir/AndroidManifest.xml"
done
cp "$native_source/MainActivity.kt" "$kotlin_target/MainActivity.kt"
cp "$native_source/SmsReceiver.kt" "$kotlin_target/SmsReceiver.kt"
cp "$native_source/MmsReceiver.kt" "$kotlin_target/MmsReceiver.kt"
cp "$native_source/BlueBubblesMmsSentReceiver.kt" \
  "$kotlin_target/BlueBubblesMmsSentReceiver.kt"
cp "$native_source/RespondViaMessageService.kt" \
  "$kotlin_target/RespondViaMessageService.kt"
cp "$native_source/SmsSendCompat.kt" "$kotlin_target/SmsSendCompat.kt"

# Install each supplied square as the full-bleed background of a real
# adaptive icon. Using the complete artwork as a legacy drawable makes modern
# launchers shrink it into an extra white circle.
find "$project_root/android/app/src/main/res" -type f \
  \( -name 'app_icon_*.png' -o -name 'app_icon_*.xml' \) \
  -delete
mkdir -p "$icon_drawable_target" "$icon_legacy_target" "$icon_adaptive_target"
for icon in modern_blue modern_green classic_blue classic_green; do
  cp "$icon_source/$icon.png" "$icon_drawable_target/app_icon_${icon}_art.png"
  cp "$icon_source/$icon.png" "$icon_legacy_target/app_icon_$icon.png"
  cp "$icon_adaptive_source/$icon.xml" "$icon_adaptive_target/app_icon_$icon.xml"
done

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
