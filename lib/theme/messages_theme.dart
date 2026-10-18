import 'package:flutter/cupertino.dart';

abstract final class MessagesPalette {
  static const blue = Color(0xFF007AFF);
  static const headerActionBlue = Color(0xFF3478F6);
  static const darkBlue = Color(0xFF0A84FF);
  static const green = Color(0xFF34C759);
  static const darkGreen = Color(0xFF30D158);
  static const customBubbleGreen = Color(0xFF00DD5B);
  static const secondary = Color(0xFF8E8E93);
  static const separator = Color(0xFFC6C6C8);

  static bool isDark(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;

  static Color background(BuildContext context) =>
      isDark(context) ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

  static Color elevatedBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);

  static Color label(BuildContext context) =>
      isDark(context) ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

  static Color secondaryLabel(BuildContext context) =>
      isDark(context) ? const Color(0xFF98989D) : secondary;

  static Color fill(BuildContext context) =>
      isDark(context) ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

  static Color receivedBubble(BuildContext context) =>
      isDark(context) ? const Color(0xFF2C2C2E) : const Color(0xFFE9E9EB);

  static Color sentBubble(BuildContext context) =>
      isDark(context) ? darkBlue : blue;

  static Color hairline(BuildContext context) =>
      isDark(context) ? const Color(0xFF38383A) : separator;
}
abstract final class MessagesText {
  static TextStyle largeTitle(BuildContext context) => TextStyle(
        fontFamily: 'SF Pro Text',
        color: MessagesPalette.label(context),
        fontSize: 34,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      );

  static TextStyle headline(BuildContext context) => TextStyle(
        fontFamily: 'SF Pro Text',
        color: MessagesPalette.label(context),
        fontSize: 16.5,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      );

  static TextStyle body(BuildContext context) => TextStyle(
        fontFamily: 'SF Pro Text',
        color: MessagesPalette.label(context),
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
      );

  static TextStyle secondary(BuildContext context) => TextStyle(
        fontFamily: 'SF Pro Text',
        color: MessagesPalette.secondaryLabel(context),
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.2,
      );
}
