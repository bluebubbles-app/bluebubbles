import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'data/demo_data.dart';
import 'data/message_repository.dart';
import 'models/conversation.dart';
import 'screens/conversation_list_screen.dart';
import 'services/android_sms_service.dart';
import 'settings/app_settings.dart';
import 'theme/messages_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MessagesUiApp());
}

class MessagesUiApp extends StatefulWidget {
  const MessagesUiApp({super.key});

  @override
  State<MessagesUiApp> createState() => _MessagesUiAppState();
}

class _MessagesUiAppState extends State<MessagesUiApp>
    with WidgetsBindingObserver {
  late final MessageRepository _messageRepository =
      DemoMessageRepository(demoConversations());
  final AppSettingsController _settings = AppSettingsController();
  final AndroidSmsController _smsController = AndroidSmsController();
  bool _usingPhoneMessages = false;
  Future<void>? _phoneLoadFuture;
  bool _phoneReloadRequested = false;
  final Map<String, ConversationEnrichment> _pendingEnrichments = {};
  Timer? _enrichmentTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _smsController.onMessagesChanged = () =>
        unawaited(_reloadPhoneMessagesSilently());
    _smsController.onConversationEnriched = _applyConversationEnrichment;
    unawaited(_initializeApp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _enrichmentTimer?.cancel();
    _smsController.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshSmsMode());
  }

  Future<void> _initializeApp() async {
    await _settings.load();
    await _refreshSmsMode();
    if (!mounted ||
        !_smsController.supported ||
        _settings.permissionsOnboardingShown) {
      return;
    }
    final needsSetup = !_smsController.isDefaultSmsApp ||
        !_smsController.contactsGranted ||
        !_smsController.notificationsGranted;
    if (!needsSetup) {
      await _settings.markPermissionsOnboardingShown();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showPermissionsOnboarding());
    });
  }

  Future<void> _showPermissionsOnboarding() async {
    final shouldContinue = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Set Up BlueBubbles'),
        content: const Text(
          'To use your real conversations, BlueBubbles needs to become your '
          'default SMS app and access messages, contacts, MMS, and '
          'notifications. You can stay in Preview Mode and enable this later '
          'from Settings.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    await _settings.markPermissionsOnboardingShown();
    if (shouldContinue == true && mounted) await _enableSmsMode();
  }

  Future<void> _refreshSmsMode() async {
    await _smsController.refreshState();
    if (!mounted) return;
    if (_smsController.isActive) {
      await _reloadPhoneMessagesSilently();
    } else if (_smsController.isDefaultSmsApp && !_usingPhoneMessages) {
      setState(() {
        _usingPhoneMessages = true;
        _messageRepository.replaceAll(const []);
      });
    } else if (!_smsController.isDefaultSmsApp && _usingPhoneMessages) {
      setState(() {
        _usingPhoneMessages = false;
        _messageRepository.replaceAll(demoConversations());
      });
    }
  }

  Future<bool> _enableSmsMode() async {
    final enabled = await _smsController.requestDefaultAndPermissions();
    if (enabled) await _loadPhoneMessages();
    return enabled;
  }

  Future<void> _reloadPhoneMessagesSilently() async {
    try {
      await _loadPhoneMessages();
    } catch (error) {
      debugPrint('Phone message reload failed: $error');
    }
  }

  Future<void> _loadPhoneMessages() {
    if (!_smsController.isActive) return Future<void>.value();
    final activeLoad = _phoneLoadFuture;
    if (activeLoad != null) {
      _phoneReloadRequested = true;
      return activeLoad;
    }

    late final Future<void> trackedLoad;
    trackedLoad = _performPhoneMessageLoad().whenComplete(() {
      if (identical(_phoneLoadFuture, trackedLoad)) {
        _phoneLoadFuture = null;
      }
    });
    _phoneLoadFuture = trackedLoad;
    return trackedLoad;
  }

  Future<void> _performPhoneMessageLoad() async {
    try {
      do {
        _phoneReloadRequested = false;
        if (!_usingPhoneMessages && mounted) {
          setState(() {
            _usingPhoneMessages = true;
            _messageRepository.replaceAll(const []);
          });
        }
        final loaded = await _smsController.loadConversations();
        if (!mounted || !_smsController.isActive) return;
        final existing = {
          for (final conversation in _messageRepository.conversations)
            conversation.id: conversation,
        };
        final merged = loaded.map((incoming) {
          final current = existing[incoming.id];
          if (current == null) return incoming;
          current
            ..preview = incoming.preview
            ..updatedAt = incoming.updatedAt
            ..unreadCount = incoming.unreadCount;
          return current;
        }).toList();
        setState(() => _messageRepository.replaceAll(merged));
      } while (_phoneReloadRequested && _smsController.isActive);
    } finally {
      _phoneReloadRequested = false;
    }
  }

  Future<void> _loadConversationMessages(Conversation conversation) async {
    if (!_smsController.isActive) return;
    final messages = await _smsController.loadThreadMessages(conversation.id);
    if (!mounted) return;
    setState(() {
      conversation.messages
        ..clear()
        ..addAll(messages);
    });
  }

  void _applyConversationEnrichment(ConversationEnrichment enrichment) {
    if (!mounted || enrichment.id.isEmpty) return;
    _pendingEnrichments[enrichment.id] = enrichment;
    _enrichmentTimer ??= Timer(
      const Duration(milliseconds: 150),
      _flushConversationEnrichments,
    );
  }

  void _flushConversationEnrichments() {
    _enrichmentTimer = null;
    if (!mounted || _pendingEnrichments.isEmpty) return;
    final enrichments = Map<String, ConversationEnrichment>.from(
      _pendingEnrichments,
    );
    _pendingEnrichments.clear();
    setState(() {
      for (final conversation in _messageRepository.conversations) {
        final enrichment = enrichments[conversation.id];
        if (enrichment == null) continue;
        if (enrichment.address.isNotEmpty) {
          conversation.address = enrichment.address;
        }
        if (enrichment.title.isNotEmpty) {
          conversation.title = enrichment.title;
        }
        if (enrichment.avatarBytes != null) {
          conversation.avatarBytes = enrichment.avatarBytes;
        }
      }
    });
  }

  void _sendMessage(Conversation conversation, String text) {
    if (!_smsController.isActive) {
      setState(() => _messageRepository.sendMessage(conversation, text));
      return;
    }
    final address = conversation.address;
    final trimmed = text.trim();
    if (address == null || address.isEmpty || trimmed.isEmpty) return;
    final now = DateTime.now();
    final pendingId = 'sending-${now.microsecondsSinceEpoch}';
    setState(() {
      conversation.messages.add(
        ChatMessage(
          id: pendingId,
          text: trimmed,
          sentAt: now,
          isFromMe: true,
          deliveryState: DeliveryState.sending,
        ),
      );
      conversation
        ..preview = trimmed
        ..updatedAt = now;
    });
    unawaited(
      _sendPhoneMessage(conversation, address, trimmed, pendingId),
    );
  }

  Future<void> _sendPhoneMessage(
    Conversation conversation,
    String address,
    String text,
    String pendingId,
  ) async {
    try {
      await _smsController.sendText(address, text);
      await _loadConversationMessages(conversation);
      await _loadPhoneMessages();
    } catch (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        final pendingIndex = conversation.messages.indexWhere(
          (message) => message.id == pendingId,
        );
        final failedMessage = ChatMessage(
          id: 'failed-${now.microsecondsSinceEpoch}',
          text: text,
          sentAt: now,
          isFromMe: true,
          deliveryState: DeliveryState.failed,
        );
        if (pendingIndex == -1) {
          conversation.messages.add(failedMessage);
        } else {
          conversation.messages[pendingIndex] = failedMessage;
        }
        conversation
          ..preview = text
          ..updatedAt = now;
      });
    }
  }

  void _replaceConversations(List<Conversation> conversations) {
    setState(() => _messageRepository.replaceAll(conversations));
  }

  void _markConversationRead(Conversation conversation) {
    if (_smsController.isActive) {
      unawaited(_smsController.markThreadRead(conversation.id));
    }
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    if (_smsController.isActive) {
      await _smsController.deleteThread(conversation.id);
    }
  }

  void _callConversation(Conversation conversation) {
    final address = conversation.address;
    if (address == null || address.isEmpty) return;
    unawaited(_smsController.dialNumber(address));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => AppSettingsScope(
        controller: _settings,
        child: CupertinoApp(
          title: 'BlueBubbles',
          debugShowCheckedModeBanner: false,
          locale: _settings.locale,
          supportedLocales: const [Locale('en'), Locale('fr')],
          localizationsDelegates: const [
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(_settings.fontScale),
              ),
              child: child!,
            );
          },
          theme: CupertinoThemeData(
            primaryColor: MessagesPalette.blue,
            textTheme: CupertinoTextThemeData(
              textStyle: TextStyle(
                fontFamily: 'SF Pro Text',
                color: const CupertinoDynamicColor.withBrightness(
                  color: CupertinoColors.black,
                  darkColor: CupertinoColors.white,
                ),
                fontFamilyFallback: _settings.emojiStyle == EmojiStyle.apple
                    ? const ['Apple Color Emoji', 'Noto Color Emoji']
                    : const ['Noto Color Emoji'],
              ),
            ),
            applyThemeToAll: true,
          ),
          home: ConversationListScreen(
            conversations: _messageRepository.conversations,
            onSend: _sendMessage,
            onReplaceConversations: _replaceConversations,
            smsController: _smsController,
            onEnableSmsMode: _enableSmsMode,
            onReloadPhoneMessages: _loadPhoneMessages,
            onMarkConversationRead: _markConversationRead,
            onDeleteConversation: _deleteConversation,
            onLoadConversation: _loadConversationMessages,
            onCallConversation: _callConversation,
          ),
        ),
      ),
    );
  }
}
