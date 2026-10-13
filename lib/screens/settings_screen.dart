import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../services/message_transfer_service.dart';
import '../settings/app_settings.dart';
import '../theme/messages_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.conversations,
    required this.onImported,
  });

  final List<Conversation> conversations;
  final ValueChanged<List<Conversation>> onImported;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _transferService = MessageTransferService();
  bool _transferring = false;

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
              header: const Text('APPEARANCE'),
              footer: const Text(
                'Turning transparency down also disables most of the blur '
                'work, which can improve performance on older phones.',
              ),
              children: [
                _SliderSetting(
                  key: const ValueKey('header-transparency-setting'),
                  title: 'Header Transparency',
                  value: settings.headerTransparency,
                  min: 0,
                  max: 1,
                  leading: CupertinoIcons.drop,
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
                  title: 'Emoji Style',
                  value: _emojiLabel(settings.emojiStyle),
                  icon: CupertinoIcons.smiley,
                  onPressed: () async {
                    final value = await _pick<EmojiStyle>(
                      title: 'Emoji Style',
                      current: settings.emojiStyle,
                      options: const [
                        (EmojiStyle.apple, 'Apple (requires asset pack)'),
                        (EmojiStyle.android, 'Android'),
                      ],
                    );
                    if (value == EmojiStyle.apple &&
                        !AppSettingsController.appleEmojiAssetsAvailable &&
                        context.mounted) {
                      await showCupertinoDialog<void>(
                        context: context,
                        builder: (context) => CupertinoAlertDialog(
                          title: const Text('Apple Emoji Pack Required'),
                          content: const Text(
                            'SF Pro does not include emoji artwork. Add an '
                            'Apple-compatible emoji font or image pack before '
                            'this style can be enabled.',
                          ),
                          actions: [
                            CupertinoDialogAction(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    } else if (value != null) {
                      await settings.setEmojiStyle(value);
                    }
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
                'model is ready to receive Android SMS/MMS data later.',
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
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.leading,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final IconData leading;
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
              Text(title),
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
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
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
      title: Text(title),
      additionalInfo: Text(value),
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
