import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../services/android_sms_service.dart';
import '../services/message_transfer_service.dart';
import '../settings/app_settings.dart';
import '../theme/messages_theme.dart';
import '../widgets/ios3_navigation_chrome.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.conversations,
    required this.onImported,
    required this.smsController,
    required this.onEnableSmsMode,
    required this.onReloadPhoneMessages,
  });

  final List<Conversation> conversations;
  final ValueChanged<List<Conversation>> onImported;
  final AndroidSmsController smsController;
  final Future<bool> Function() onEnableSmsMode;
  final Future<void> Function() onReloadPhoneMessages;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _transferService = MessageTransferService();
  bool _transferring = false;
  bool _smsChanging = false;
  bool _diagnosing = false;
  bool _changingAppIcon = false;

  Future<void> _changeSmsMode() async {
    if (_smsChanging) return;
    setState(() => _smsChanging = true);
    try {
      final enabled = await widget.onEnableSmsMode();
      if (!enabled &&
          mounted &&
          widget.smsController.lastError != null) {
        await _showError(
          'SMS Setup Failed',
          widget.smsController.lastError!,
        );
      }
    } catch (error) {
      if (mounted) {
        await _showError(
          'SMS Setup Failed',
          widget.smsController.lastError ?? error,
        );
      }
    } finally {
      if (mounted) setState(() => _smsChanging = false);
    }
  }

  Future<void> _reloadPhoneMessages() async {
    if (_smsChanging) return;
    setState(() => _smsChanging = true);
    try {
      await widget.onReloadPhoneMessages();
      if (mounted &&
          widget.smsController.isActive &&
          widget.conversations.isEmpty) {
        await _showSmsDiagnostics();
      }
    } catch (error) {
      if (mounted) {
        await _showError(
          'Reload Failed',
          widget.smsController.lastError ?? error,
        );
      }
    } finally {
      if (mounted) setState(() => _smsChanging = false);
    }
  }

  Future<void> _showSmsDiagnostics() async {
    if (_diagnosing) return;
    setState(() => _diagnosing = true);
    try {
      final diagnostics = await widget.smsController.getDiagnostics();
      if (!mounted) return;
      final report = diagnostics.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('SMS Diagnostics'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Text(
                  report,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Text',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copy'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        await _showError(
          'Diagnostics Failed',
          widget.smsController.lastError ?? error,
        );
      }
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  Future<void> _changeAppIcon() async {
    if (_changingAppIcon) return;
    final settings = AppSettingsScope.of(context);
    final selected = await showCupertinoModalPopup<AppIconStyle>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('App Icon'),
        message: const Text(
          'Choose the icon shown on your Home Screen. The launcher may take '
          'a few seconds to refresh.',
        ),
        actions: AppIconStyle.values
            .map(
              (style) => CupertinoActionSheetAction(
                isDefaultAction: style == settings.appIconStyle,
                onPressed: () => Navigator.of(context).pop(style),
                child: Row(
                  children: [
                    _AppIconPreview(style: style, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        style.label,
                        textAlign: TextAlign.left,
                      ),
                    ),
                    if (style == settings.appIconStyle)
                      const Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        size: 22,
                      ),
                  ],
                ),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (selected == null || selected == settings.appIconStyle || !mounted) {
      return;
    }

    final previous = settings.appIconStyle;
    setState(() => _changingAppIcon = true);
    try {
      await settings.setAppIconStyle(selected);
      await widget.smsController.setLauncherIcon(selected.name);
      await HapticFeedback.mediumImpact();
    } catch (error) {
      await settings.setAppIconStyle(previous);
      if (mounted) await _showError('Icon Change Failed', error);
    } finally {
      if (mounted) setState(() => _changingAppIcon = false);
    }
  }

  Future<void> _exportMessages() async {
    if (_transferring) return;
    setState(() => _transferring = true);
    try {
      await _transferService.exportMessages(widget.conversations);
    } catch (error) {
      if (mounted) await _showError('Export Failed', error);
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _importMessages() async {
    if (_transferring) return;
    setState(() => _transferring = true);
    try {
      final imported = await _transferService.importMessages();
      if (imported == null || !mounted) return;
      final shouldReplace = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Import Messages?'),
          content: Text(
            'This will replace the current conversation list with '
            '${imported.length} imported conversations.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (shouldReplace == true && mounted) {
        widget.onImported(imported);
        HapticFeedback.mediumImpact();
        await showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Import Complete'),
            content: Text('${imported.length} conversations were imported.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) await _showError('Import Failed', error);
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _showError(String title, Object error) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(error.toString()),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<T?> _pick<T>({
    required String title,
    required T current,
    required List<(T, String)> options,
  }) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(title),
        actions: options
            .map(
              (option) => CupertinoActionSheetAction(
                isDefaultAction: option.$1 == current,
                onPressed: () => Navigator.of(context).pop(option.$1),
                child: Text(option.$2),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final useIos3 = settings.interfaceStyle == InterfaceStyle.ios3;
    final content = ListView(
      padding: useIos3
          ? const EdgeInsets.fromLTRB(10, 14, 10, 28)
          : EdgeInsets.zero,
      children: [
        _SettingsSection(
          useIos3: useIos3,
          header: 'MESSAGING MODE',
          footer:
              'Preview Mode keeps your current SMS app unchanged. The first '
              'native build handles SMS and carrier MMS. RCS is not '
              'available through Android’s public SMS interface.',
          children: [
                _StatusRow(
                  title: 'BlueBubbles',
                  value: widget.smsController.statusLabel,
                  icon: CupertinoIcons.chat_bubble,
                ),
                _ActionRow(
                  key: const ValueKey('sms-mode-action'),
                  title: !widget.smsController.isActive
                      ? 'Use as Default SMS App'
                      : !widget.smsController.contactsGranted
                          ? 'Allow Contact Photos'
                          : !widget.smsController.notificationsGranted
                              ? 'Allow Notifications'
                              : 'Reload Phone Messages',
                  icon: !widget.smsController.isActive
                      ? CupertinoIcons.checkmark_circle
                      : !widget.smsController.contactsGranted
                          ? CupertinoIcons.person_crop_circle
                          : !widget.smsController.notificationsGranted
                              ? CupertinoIcons.bell
                              : CupertinoIcons.refresh,
                  onPressed: _smsChanging || !widget.smsController.supported
                      ? null
                      : widget.smsController.isActive &&
                              widget.smsController.contactsGranted &&
                              widget.smsController.notificationsGranted
                          ? _reloadPhoneMessages
                          : _changeSmsMode,
                ),
                _ActionRow(
                  key: const ValueKey('sms-diagnostics-action'),
                  title: 'SMS Diagnostics',
                  icon: CupertinoIcons.info_circle,
                  onPressed: _diagnosing || !widget.smsController.supported
                      ? null
                      : _showSmsDiagnostics,
                ),
          ],
        ),
        _SettingsSection(
          useIos3: useIos3,
          header: 'APPEARANCE',
          children: [
                _ChoiceRow(
                  key: const ValueKey('interface-style-setting'),
                  title: 'Interface',
                  value: switch (settings.interfaceStyle) {
                    InterfaceStyle.ios3 => 'iOS 3.0',
                    InterfaceStyle.ios17 => 'iOS 17',
                    InterfaceStyle.ios26 => 'iOS 26',
                  },
                  icon: CupertinoIcons.paintbrush,
                  onPressed: () async {
                    final value = await _pick<InterfaceStyle>(
                      title: 'Interface',
                      current: settings.interfaceStyle,
                      options: const [
                        (InterfaceStyle.ios3, 'iOS 3.0'),
                        (InterfaceStyle.ios17, 'iOS 17'),
                        (InterfaceStyle.ios26, 'iOS 26'),
                      ],
                    );
                    if (value != null) {
                      await settings.setInterfaceStyle(value);
                    }
                  },
                ),
                _AppIconChoiceRow(
                  style: settings.appIconStyle,
                  changing: _changingAppIcon,
                  onPressed: _changeAppIcon,
                ),
                if (!useIos3)
                  _SliderSetting(
                    key: const ValueKey('header-transparency-setting'),
                    title: 'Header Transparency',
                    value: settings.headerTransparency,
                    min: 0,
                    max: 1,
                    leading: CupertinoIcons.drop,
                    note:
                        'Higher levels require more graphics processing and '
                        'may affect responsiveness on older devices.',
                    onChanged: settings.setHeaderTransparency,
                  ),
                _SliderSetting(
                  key: const ValueKey('font-size-setting'),
                  title: 'Text Size',
                  value: settings.fontScale,
                  min: .85,
                  max: 1.3,
                  leading: CupertinoIcons.textformat_size,
                  onChanged: settings.setFontScale,
                ),
                _ChoiceRow(
                  title: 'Sent Bubble Color',
                  value: _bubbleColorLabel(settings.sentBubbleColor),
                  icon: CupertinoIcons.chat_bubble_fill,
                  onPressed: () async {
                    final value = await _pick<SentBubbleColor>(
                      title: 'Sent Bubble Color',
                      current: settings.sentBubbleColor,
                      options: const [
                        (SentBubbleColor.blue, 'Blue'),
                        (SentBubbleColor.green, 'Green'),
                      ],
                    );
                    if (value != null) {
                      await settings.setSentBubbleColor(value);
                    }
                  },
                ),
                _ChoiceRow(
                  title: 'Emoji Style',
                  value: _emojiLabel(settings.emojiStyle),
                  icon: CupertinoIcons.smiley,
                  onPressed: () async {
                    final value = await _pick<EmojiStyle>(
                      title: 'Emoji Style',
                      current: settings.emojiStyle,
                      options: const [
                        (EmojiStyle.apple, 'Apple'),
                        (EmojiStyle.android, 'Android'),
                      ],
                    );
                    if (value != null) await settings.setEmojiStyle(value);
                  },
                ),
          ],
        ),
        _SettingsSection(
          useIos3: useIos3,
          header: 'REGION',
          children: [
                _ChoiceRow(
                  title: 'Language',
                  value: _languageLabel(settings.language),
                  icon: CupertinoIcons.globe,
                  onPressed: () async {
                    final value = await _pick<AppLanguage>(
                      title: 'Language',
                      current: settings.language,
                      options: const [
                        (AppLanguage.system, 'System Default'),
                        (AppLanguage.english, 'English'),
                        (AppLanguage.french, 'French'),
                      ],
                    );
                    if (value != null) await settings.setLanguage(value);
                  },
                ),
                _ChoiceRow(
                  title: 'Date Format',
                  value: _dateLabel(settings.dateOrder),
                  icon: CupertinoIcons.calendar,
                  onPressed: () async {
                    final value = await _pick<DateOrder>(
                      title: 'Date Format',
                      current: settings.dateOrder,
                      options: const [
                        (DateOrder.system, 'System Default'),
                        (DateOrder.dayMonthYear, 'DD/MM/YYYY'),
                        (DateOrder.monthDayYear, 'MM/DD/YYYY'),
                        (DateOrder.yearMonthDay, 'YYYY-MM-DD'),
                      ],
                    );
                    if (value != null) await settings.setDateOrder(value);
                  },
                ),
                _ChoiceRow(
                  title: 'Time Format',
                  value: _clockLabel(settings.clockFormat),
                  icon: CupertinoIcons.clock,
                  onPressed: () async {
                    final value = await _pick<ClockFormat>(
                      title: 'Time Format',
                      current: settings.clockFormat,
                      options: const [
                        (ClockFormat.system, 'System Default'),
                        (ClockFormat.hour12, '12-hour'),
                        (ClockFormat.hour24, '24-hour'),
                      ],
                    );
                    if (value != null) await settings.setClockFormat(value);
                  },
                ),
          ],
        ),
        _SettingsSection(
          useIos3: useIos3,
          header: 'MESSAGES',
          footer: 'Backups use a portable JSON model. The same conversation '
              'model stores imported data and Android SMS/MMS data.',
          children: [
                _ActionRow(
                  key: const ValueKey('import-messages-setting'),
                  title: 'Import Messages',
                  icon: CupertinoIcons.square_arrow_down,
                  onPressed: _transferring ? null : _importMessages,
                ),
                _ActionRow(
                  key: const ValueKey('export-messages-setting'),
                  title: 'Export Messages',
                  icon: CupertinoIcons.square_arrow_up,
                  onPressed: _transferring ? null : _exportMessages,
                ),
          ],
        ),
        if (_transferring)
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Center(child: CupertinoActivityIndicator()),
          ),
      ],
    );

    if (useIos3) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: CupertinoPageScaffold(
          backgroundColor: const Color(0xFFDCE1EC),
          child: SafeArea(
            child: Column(
              children: [
                _Ios3SettingsHeader(
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(
                          painter: _Ios3SettingsBackgroundPainter(),
                        ),
                      ),
                      content,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: MessagesPalette.fill(context),
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Settings'),
      ),
      child: SafeArea(child: content),
    );
  }

  String _languageLabel(AppLanguage value) => switch (value) {
        AppLanguage.system => 'System Default',
        AppLanguage.english => 'English',
        AppLanguage.french => 'French',
      };

  String _dateLabel(DateOrder value) => switch (value) {
        DateOrder.system => 'System Default',
        DateOrder.dayMonthYear => 'DD/MM/YYYY',
        DateOrder.monthDayYear => 'MM/DD/YYYY',
        DateOrder.yearMonthDay => 'YYYY-MM-DD',
      };

  String _clockLabel(ClockFormat value) => switch (value) {
        ClockFormat.system => 'System Default',
        ClockFormat.hour12 => '12-hour',
        ClockFormat.hour24 => '24-hour',
      };

  String _emojiLabel(EmojiStyle value) => switch (value) {
        EmojiStyle.apple => 'Apple',
        EmojiStyle.android => 'Android',
      };

  String _bubbleColorLabel(SentBubbleColor value) => switch (value) {
        SentBubbleColor.blue => 'Blue',
        SentBubbleColor.green => 'Green',
      };
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.useIos3,
    required this.header,
    required this.children,
    this.footer,
  });

  final bool useIos3;
  final String header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!useIos3) {
      return CupertinoListSection.insetGrouped(
        header: Text(header),
        footer: footer == null ? null : Text(footer!),
        children: children,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 5),
            child: Text(
              header,
              style: const TextStyle(
                color: Color(0xFF636B78),
                fontFamily: 'SF Pro Text',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .35,
                shadows: [
                  Shadow(color: Color(0xE6FFFFFF), offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFF0F0F0)],
                stops: [0, .78],
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFF9A9A9A)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    children[index],
                    if (index != children.length - 1)
                      const SizedBox(
                        height: 1,
                        width: double.infinity,
                        child: ColoredBox(color: Color(0xFFB4B4B4)),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                footer!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF747B88),
                  fontFamily: 'SF Pro Text',
                  fontSize: 11,
                  height: 1.18,
                  shadows: [
                    Shadow(color: Color(0xE6FFFFFF), offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Ios3SettingsHeader extends StatelessWidget {
  const _Ios3SettingsHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: ios3TopBarHeight,
        decoration: ios3TopBarDecoration,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: const Offset(0, ios3TopBarVerticalOffset),
              child: const Text(
                'Settings',
                style: ios3TopBarTitleStyle,
              ),
            ),
            Positioned(
              left: 6,
              top: ios3TopBarControlCenterY -
                  (ios3TopBarButtonHeight / 2),
              child: CupertinoButton(
                minSize: ios3TopBarButtonHeight,
                padding: EdgeInsets.zero,
                onPressed: onBack,
                child: SizedBox(
                  width: 92,
                  height: ios3TopBarButtonHeight,
                  child: CustomPaint(
                    painter: const _Ios3SettingsBackButtonPainter(),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Center(
                        child: Text(
                          'Messages',
                          maxLines: 1,
                          style: ios3TopBarButtonTextStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Ios3TopBarGloss(),
          ],
        ),
      );
}

class _Ios3SettingsBackButtonPainter extends CustomPainter {
  const _Ios3SettingsBackButtonPainter();

  Path _path(Size size) => Path()
    ..moveTo(13, 1)
    ..lineTo(size.width - 7, 1)
    ..quadraticBezierTo(size.width - 1, 1, size.width - 1, 7)
    ..lineTo(size.width - 1, size.height - 7)
    ..quadraticBezierTo(
      size.width - 1,
      size.height - 1,
      size.width - 7,
      size.height - 1,
    )
    ..lineTo(13, size.height - 1)
    ..lineTo(1, size.height / 2)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ios3TopBarButtonGradient.createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x80000000),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = const Color(0x33FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_Ios3SettingsBackButtonPainter oldDelegate) => false;
}

class _Ios3SettingsBackgroundPainter extends CustomPainter {
  const _Ios3SettingsBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFDCE2EC),
    );
    final light = Paint()
      ..color = const Color(0x30FFFFFF)
      ..strokeWidth = 1;
    final shade = Paint()
      ..color = const Color(0x10000000)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), light);
      canvas.drawLine(Offset(x + 1, 0), Offset(x + 1, size.height), shade);
    }
  }

  @override
  bool shouldRepaint(_Ios3SettingsBackgroundPainter oldDelegate) => false;
}

extension on AppIconStyle {
  String get label => switch (this) {
        AppIconStyle.modernBlue => 'Modern Blue',
        AppIconStyle.modernGreen => 'Modern Green',
        AppIconStyle.classicBlue => 'Classic Blue',
        AppIconStyle.classicGreen => 'Classic Green',
      };

  String get assetPath => switch (this) {
        AppIconStyle.modernBlue => 'assets/icon/app-icons/modern_blue.png',
        AppIconStyle.modernGreen => 'assets/icon/app-icons/modern_green.png',
        AppIconStyle.classicBlue => 'assets/icon/app-icons/classic_blue.png',
        AppIconStyle.classicGreen => 'assets/icon/app-icons/classic_green.png',
      };
}

class _AppIconPreview extends StatelessWidget {
  const _AppIconPreview({required this.style, required this.size});

  final AppIconStyle style;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .2237),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .2237),
          child: Image.asset(
            style.assetPath,
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            cacheWidth:
                (size * MediaQuery.devicePixelRatioOf(context)).round(),
            cacheHeight:
                (size * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
        ),
      );
}

class _AppIconChoiceRow extends StatelessWidget {
  const _AppIconChoiceRow({
    required this.style,
    required this.changing,
    required this.onPressed,
  });

  final AppIconStyle style;
  final bool changing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final useIos3 = AppSettingsScope.of(context).interfaceStyle ==
        InterfaceStyle.ios3;
    return CupertinoListTile(
      key: const ValueKey('app-icon-setting'),
      leading: useIos3 ? null : _AppIconPreview(style: style, size: 32),
      padding: useIos3
          ? const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0)
          : null,
      title: Text(
        'App Icon',
        style: TextStyle(
          color: useIos3
              ? CupertinoColors.black
              : MessagesPalette.label(context),
          fontFamily: useIos3 ? 'SF Pro Text' : null,
          fontSize: useIos3 ? 15 : null,
          fontWeight: useIos3 ? FontWeight.w700 : null,
        ),
      ),
      additionalInfo: changing
          ? const CupertinoActivityIndicator(radius: 8)
          : Text(
              style.label,
              style: TextStyle(
                color: useIos3
                    ? const Color(0xFF666B73)
                    : MessagesPalette.secondaryLabel(context),
                fontFamily: useIos3 ? 'SF Pro Text' : null,
                fontSize: useIos3 ? 13 : null,
              ),
            ),
      trailing: useIos3
          ? const Icon(
              CupertinoIcons.chevron_forward,
              color: Color(0xFF777C84),
              size: 17,
            )
          : const CupertinoListTileChevron(),
      backgroundColor: useIos3 ? CupertinoColors.transparent : null,
      onTap: changing ? null : onPressed,
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.leading,
    this.note,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final IconData leading;
  final String? note;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final useIos3 = AppSettingsScope.of(context).interfaceStyle ==
        InterfaceStyle.ios3;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        useIos3 ? 8 : 11,
        useIos3 ? 34 : 12,
        useIos3 ? 5 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!useIos3) ...[
                Icon(leading, color: MessagesPalette.blue, size: 21),
                const SizedBox(width: 12),
              ],
              Text(
                title,
                style: TextStyle(
                  color: useIos3
                      ? CupertinoColors.black
                      : MessagesPalette.label(context),
                  fontFamily: useIos3 ? 'SF Pro Text' : null,
                  fontSize: useIos3 ? 15 : null,
                  fontWeight: useIos3 ? FontWeight.w700 : null,
                ),
              ),
              const Spacer(),
              Text(
                '${((value - min) / (max - min) * 100).round()}%',
                style: TextStyle(
                  color: useIos3
                      ? const Color(0xFF666B73)
                      : MessagesPalette.secondaryLabel(context),
                  fontFamily: useIos3 ? 'SF Pro Text' : null,
                  fontSize: useIos3 ? 13 : 14,
                ),
              ),
            ],
          ),
          CupertinoSlider(
            value: value,
            min: min,
            max: max,
            activeColor: useIos3 ? const Color(0xFF2F7CC2) : null,
            onChanged: onChanged,
          ),
          if (note != null)
            Padding(
              padding: EdgeInsets.fromLTRB(useIos3 ? 2 : 33, 0, 8, 4),
              child: Text(
                note!,
                style: TextStyle(
                  color: useIos3
                      ? const Color(0xFF747B88)
                      : MessagesPalette.secondaryLabel(context),
                  fontFamily: useIos3 ? 'SF Pro Text' : null,
                  fontSize: useIos3 ? 11 : 12,
                  height: 1.25,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final useIos3 = AppSettingsScope.of(context).interfaceStyle ==
        InterfaceStyle.ios3;
    return CupertinoListTile(
      leading:
          useIos3 ? null : Icon(icon, color: MessagesPalette.blue, size: 21),
      padding: useIos3
          ? const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0)
          : null,
      title: Text(
        title,
        style: TextStyle(
          color: useIos3
              ? CupertinoColors.black
              : MessagesPalette.label(context),
          fontFamily: useIos3 ? 'SF Pro Text' : null,
          fontSize: useIos3 ? 15 : null,
          fontWeight: useIos3 ? FontWeight.w700 : null,
        ),
      ),
      additionalInfo: Text(
        value,
        style: TextStyle(
          color: useIos3
              ? const Color(0xFF666B73)
              : MessagesPalette.secondaryLabel(context),
          fontFamily: useIos3 ? 'SF Pro Text' : null,
          fontSize: useIos3 ? 13 : null,
        ),
      ),
      trailing: useIos3 ? const SizedBox(width: 17) : null,
      backgroundColor: useIos3 ? CupertinoColors.transparent : null,
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final useIos3 = AppSettingsScope.of(context).interfaceStyle ==
        InterfaceStyle.ios3;
    return CupertinoListTile(
      leading:
          useIos3 ? null : Icon(icon, color: MessagesPalette.blue, size: 21),
      padding: useIos3
          ? const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0)
          : null,
      title: Text(
        title,
        style: TextStyle(
          color: useIos3
              ? CupertinoColors.black
              : MessagesPalette.label(context),
          fontFamily: useIos3 ? 'SF Pro Text' : null,
          fontSize: useIos3 ? 15 : null,
          fontWeight: useIos3 ? FontWeight.w700 : null,
        ),
      ),
      additionalInfo: Text(
        value,
        style: TextStyle(
          color: useIos3
              ? const Color(0xFF666B73)
              : MessagesPalette.secondaryLabel(context),
          fontFamily: useIos3 ? 'SF Pro Text' : null,
          fontSize: useIos3 ? 13 : null,
        ),
      ),
      trailing: useIos3
          ? const Icon(
              CupertinoIcons.chevron_forward,
              color: Color(0xFF777C84),
              size: 17,
            )
          : const CupertinoListTileChevron(),
      backgroundColor: useIos3 ? CupertinoColors.transparent : null,
      onTap: onPressed,
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.title,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final useIos3 = AppSettingsScope.of(context).interfaceStyle ==
        InterfaceStyle.ios3;
    return CupertinoListTile(
      leading:
          useIos3 ? null : Icon(icon, color: MessagesPalette.blue, size: 21),
      padding: useIos3
          ? const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0)
          : null,
      title: Text(
        title,
        style: TextStyle(
          color: onPressed == null
              ? (useIos3
                  ? const Color(0xFF8A8A8A)
                  : MessagesPalette.secondaryLabel(context))
              : (useIos3
                  ? CupertinoColors.black
                  : MessagesPalette.blue),
          fontSize: useIos3 ? 15 : null,
          fontFamily: useIos3 ? 'SF Pro Text' : null,
          fontWeight: useIos3 ? FontWeight.w700 : null,
        ),
      ),
      trailing: useIos3
          ? const Icon(
              CupertinoIcons.chevron_forward,
              color: Color(0xFF777C84),
              size: 17,
            )
          : null,
      backgroundColor: useIos3 ? CupertinoColors.transparent : null,
      onTap: onPressed,
    );
  }
}
