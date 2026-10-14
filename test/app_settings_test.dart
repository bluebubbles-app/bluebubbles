import 'package:bluebubbles/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('shows permission onboarding only once', () async {
    SharedPreferences.setMockInitialValues({});
    final initial = AppSettingsController();
    await initial.load();
    expect(initial.permissionsOnboardingShown, isFalse);

    await initial.markPermissionsOnboardingShown();
    initial.dispose();

    final restored = AppSettingsController();
    await restored.load();
    expect(restored.permissionsOnboardingShown, isTrue);
    restored.dispose();
  });
}
