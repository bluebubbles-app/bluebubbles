import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { system, english, french }

enum DateOrder { system, dayMonthYear, monthDayYear, yearMonthDay }

enum ClockFormat { system, hour12, hour24 }

enum EmojiStyle { apple, android }

class AppSettingsController extends ChangeNotifier {
  static const appleEmojiAssetsAvailable = false;
  static const _headerTransparencyKey = 'header_transparency';
  static const _fontScaleKey = 'font_scale';
  static const _languageKey = 'language';
  static const _dateOrderKey = 'date_order';
  static const _clockFormatKey = 'clock_format';
  static const _emojiStyleKey = 'emoji_style';

  double headerTransparency = .28;
  double fontScale = 1;
  AppLanguage language = AppLanguage.system;
  DateOrder dateOrder = DateOrder.system;
  ClockFormat clockFormat = ClockFormat.system;
  EmojiStyle emojiStyle = EmojiStyle.android;
  bool _disposed = false;
  Timer? _headerSaveDebounce;
  Timer? _fontScaleSaveDebounce;

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      headerTransparency =
          preferences.getDouble(_headerTransparencyKey) ?? headerTransparency;
      fontScale = preferences.getDouble(_fontScaleKey) ?? fontScale;
      language = _enumValue(
        AppLanguage.values,
        preferences.getString(_languageKey),
        language,
      );
      dateOrder = _enumValue(
        DateOrder.values,
        preferences.getString(_dateOrderKey),
        dateOrder,
      );
      clockFormat = _enumValue(
        ClockFormat.values,
        preferences.getString(_clockFormatKey),
        clockFormat,
      );
      emojiStyle = _enumValue(
        EmojiStyle.values,
        preferences.getString(_emojiStyleKey),
        emojiStyle,
      );
      if (!appleEmojiAssetsAvailable && emojiStyle == EmojiStyle.apple) {
        emojiStyle = EmojiStyle.android;
      }
    } on Exception {
      // Widget tests and preview hosts may not expose a preferences backend.
    }
    _notifyIfActive();
  }

  void setHeaderTransparency(double value) {
    headerTransparency = value.clamp(0, 1).toDouble();
    _notifyIfActive();
    _headerSaveDebounce?.cancel();
    _headerSaveDebounce = Timer(const Duration(milliseconds: 250), () {
      _persist(
        (preferences) => preferences.setDouble(
          _headerTransparencyKey,
          headerTransparency,
        ),
      );
    });
  }

  void setFontScale(double value) {
    fontScale = value.clamp(.85, 1.3).toDouble();
    _notifyIfActive();
    _fontScaleSaveDebounce?.cancel();
    _fontScaleSaveDebounce = Timer(const Duration(milliseconds: 250), () {
      _persist(
        (preferences) => preferences.setDouble(_fontScaleKey, fontScale),
      );
    });
  }

  Future<void> setLanguage(AppLanguage value) async {
    language = value;
    _notifyIfActive();
    await _persist(
      (preferences) => preferences.setString(_languageKey, value.name),
    );
  }

  Future<void> setDateOrder(DateOrder value) async {
    dateOrder = value;
    _notifyIfActive();
    await _persist(
      (preferences) => preferences.setString(_dateOrderKey, value.name),
    );
  }

  Future<void> setClockFormat(ClockFormat value) async {
    clockFormat = value;
    _notifyIfActive();
    await _persist(
      (preferences) => preferences.setString(_clockFormatKey, value.name),
    );
  }

  Future<void> setEmojiStyle(EmojiStyle value) async {
    if (value == EmojiStyle.apple && !appleEmojiAssetsAvailable) return;
    emojiStyle = value;
    _notifyIfActive();
    await _persist(
      (preferences) => preferences.setString(_emojiStyleKey, value.name),
    );
  }

  Locale? get locale => switch (language) {
        AppLanguage.system => null,
        AppLanguage.english => const Locale('en'),
        AppLanguage.french => const Locale('fr'),
      };

  double get headerTintOpacity => lerpDouble(1, .45, headerTransparency)!;

  double get headerBlurSigma => lerpDouble(0, 24, headerTransparency)!;

  String formatTime(DateTime value, {bool platformUses24Hour = false}) {
    final use24Hour = switch (clockFormat) {
      ClockFormat.system => platformUses24Hour,
      ClockFormat.hour12 => false,
      ClockFormat.hour24 => true,
    };
    final minute = value.minute.toString().padLeft(2, '0');
    if (use24Hour) {
      return '${value.hour.toString().padLeft(2, '0')}:$minute';
    }
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String formatDate(DateTime value, {String? localeCode}) {
    final resolvedOrder = dateOrder == DateOrder.system
        ? (localeCode == 'en' ? DateOrder.monthDayYear : DateOrder.dayMonthYear)
        : dateOrder;
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return switch (resolvedOrder) {
      DateOrder.system => '$day/$month/${value.year}',
      DateOrder.dayMonthYear => '$day/$month/${value.year}',
      DateOrder.monthDayYear => '$month/$day/${value.year}',
      DateOrder.yearMonthDay => '${value.year}-$month-$day',
    };
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    if (name == null) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  Future<void> _persist(
    Future<bool> Function(SharedPreferences preferences) write,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await write(preferences);
    } on Exception {
      // Keep the live setting even if persistence is unavailable.
    }
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _headerSaveDebounce?.cancel();
    _fontScaleSaveDebounce?.cancel();
    super.dispose();
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  const AppSettingsScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSettingsController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'AppSettingsScope is missing above this context.');
    return scope!.notifier!;
  }
}
