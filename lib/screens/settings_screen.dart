import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../services/android_sms_service.dart';
import '../services/message_transfer_service.dart';
import '../settings/app_settings.dart';
import '../theme/messages_theme.dart';

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
    return CupertinoPageScaffold(
      backgroundColor: MessagesPalette.fill(context),
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Settings'),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              header: const Text('MESSAGING MODE'),
              footer: const Text(
                'Preview Mode keeps your current SMS app unchanged. The first '
                'native build handles SMS and carrier MMS. RCS is not '
                'available through Android’s public SMS interface.',
              ),
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
            CupertinoListSection.insetGrouped(
              header: const Text('APPEARANCE'),
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
                _SliderSetting(
                  key: const ValueKey('header-transparency-setting'),
                  title: 'Header Transparency',
                  value: settings.headerTransparency,
                  min: 0,
                  max: 1,
                  leading: CupertinoIcons.drop,
                  note: 'Higher levels require more graphics processing and '
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
            CupertinoListSection.insetGrouped(
              header: const Text('REGION'),
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
            CupertinoListSection.insetGrouped(
              header: const Text('MESSAGES'),
              footer: const Text(
                'Backups use a portable JSON model. The same conversation '
                'model stores imported data and Android SMS/MMS data.',
              ),
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
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(leading, color: MessagesPalette.blue, size: 21),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(color: MessagesPalette.label(context)),
              ),
              const Spacer(),
              Text(
                '${((value - min) / (max - min) * 100).round()}%',
                style: TextStyle(
                  color: MessagesPalette.secondaryLabel(context),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          CupertinoSlider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(33, 0, 8, 4),
              child: Text(
                note!,
                style: TextStyle(
                  color: MessagesPalette.secondaryLabel(context),
                  fontSize: 12,
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
    return CupertinoListTile(
      leading: Icon(icon, color: MessagesPalette.blue, size: 21),
      title: Text(
        title,
        style: TextStyle(color: MessagesPalette.label(context)),
      ),
      additionalInfo: Text(
        value,
        style: TextStyle(color: MessagesPalette.secondaryLabel(context)),
      ),
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
    return CupertinoListTile(
      leading: Icon(icon, color: MessagesPalette.blue, size: 21),
      title: Text(
        title,
        style: TextStyle(color: MessagesPalette.label(context)),
      ),
      additionalInfo: Text(
        value,
        style: TextStyle(color: MessagesPalette.secondaryLabel(context)),
      ),
      trailing: const CupertinoListTileChevron(),
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
    return CupertinoListTile(
      leading: Icon(icon, color: MessagesPalette.blue, size: 21),
      title: Text(
        title,
        style: TextStyle(
          color: onPressed == null
              ? MessagesPalette.secondaryLabel(context)
              : MessagesPalette.blue,
        ),
      ),
      onTap: onPressed,
    );
  }
}
