import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'data/demo_data.dart';
import 'data/local_sms_store.dart';
import 'data/message_repository.dart';
import 'models/conversation.dart';
import 'models/sms_sync_progress.dart';
import 'models/sms_search_hit.dart';
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
  final LocalSmsStore _localSmsStore = LocalSmsStore();
  final ValueNotifier<SmsSyncProgress> _smsSyncProgress =
      ValueNotifier(SmsSyncProgress.idle);
  bool _usingPhoneMessages = false;
  bool _loadingPhoneMessages = false;
  String? _phoneLoadError;
  Future<void>? _phoneLoadFuture;
  Future<void> _backgroundSyncTail = Future<void>.value();
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  int _backgroundSyncGeneration = 0;
  int _foregroundThreadLoads = 0;
  bool _conversationRouteVisible = false;
  final Map<String, ConversationEnrichment> _pendingEnrichments = {};
  Timer? _enrichmentTimer;
  DateTime _lastSyncProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

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
    _backgroundSyncGeneration++;
    unawaited(_localSmsStore.close());
    _smsSyncProgress.dispose();
    _smsController.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSmsMode());
    } else {
      _backgroundSyncGeneration++;
    }
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
      if (!_usingPhoneMessages || _messageRepository.conversations.isEmpty) {
        await _restoreLocalConversations();
      }
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
    if (activeLoad != null) return activeLoad;

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
    if (mounted) {
      setState(() {
        _loadingPhoneMessages = true;
        _phoneLoadError = null;
        if (!_usingPhoneMessages) {
          _usingPhoneMessages = true;
          _messageRepository.replaceAll(const []);
        }
      });
    }
    try {
      final loaded = await _smsController.loadConversations();
      if (!mounted || !_smsController.isActive) return;
      final existing = {
        for (final conversation in _messageRepository.conversations)
          conversation.id: conversation,
      };
      final merged = loaded.map((incoming) {
        final current = existing[incoming.id];
        if (current == null) return incoming;
        if (incoming.address?.isNotEmpty == true) {
          current.address = incoming.address;
        }
        if (incoming.title != 'Conversation') {
          current.title = incoming.title;
        }
        current
          ..preview = incoming.preview
          ..updatedAt = incoming.updatedAt
          ..unreadCount = incoming.unreadCount;
        return current;
      }).toList();
      setState(() {
        _phoneLoadError = null;
        _messageRepository.replaceAll(merged);
      });
      unawaited(_cacheHeadersAndScheduleSync(merged));
    } catch (error) {
      if (mounted) {
        setState(() {
          _phoneLoadError = _smsController.lastError ?? error.toString();
        });
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _loadingPhoneMessages = false);
    }
  }

  Future<void> _restoreLocalConversations() async {
    try {
      final cached = await _localSmsStore.loadConversations();
      if (cached.isEmpty || !mounted) return;
      setState(() {
        _usingPhoneMessages = true;
        _messageRepository.replaceAll(cached);
      });
    } catch (error) {
      debugPrint('Local SMS cache restore failed: $error');
    }
  }

  Future<void> _cacheHeadersAndScheduleSync(
    List<Conversation> conversations,
  ) async {
    try {
      await _localSmsStore.replaceConversationHeaders(conversations);
      _scheduleBackgroundMessageSync(conversations);
    } catch (error) {
      debugPrint('Local SMS cache save failed: $error');
    }
  }

  void _scheduleBackgroundMessageSync(
    Iterable<Conversation> conversations,
  ) {
    if (!_smsController.isActive) return;
    final generation = ++_backgroundSyncGeneration;
    final snapshot = conversations.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _backgroundSyncTail = _backgroundSyncTail
        .catchError((Object _) {})
        .then((_) async {
      if (generation != _backgroundSyncGeneration) return;
      await _syncMessagesInBackground(snapshot, generation);
    });
  }

  Future<void> _syncMessagesInBackground(
    List<Conversation> conversations,
    int generation,
  ) async {
    const pageSize = 200;
    var totalMessages = 0;
    try {
      totalMessages = await _smsController.getSmsMessageCount();
      await _publishSyncProgress(
        totalMessages: totalMessages,
        active: true,
        force: true,
      );
      for (final conversation in conversations) {
        if (!await _canContinueBackgroundSync(generation)) return;
        try {
          final needsSync = await _localSmsStore.threadNeedsSync(
            conversation.id,
            conversation.updatedAt,
          );
          if (!needsSync) continue;
          final latest = await _smsController.loadThreadMessages(
            conversation.id,
            limit: pageSize,
            background: true,
          );
          await _localSmsStore.storeMessagePage(
            conversation.id,
            latest,
            reachedBeginning: latest.length < pageSize,
          );
          await _publishSyncProgress(totalMessages: totalMessages);
          if (latest.length < pageSize ||
              await _localSmsStore.isThreadFullySynced(conversation.id)) {
            await Future<void>.delayed(const Duration(milliseconds: 35));
            continue;
          }

          var oldest = await _localSmsStore.oldestMessage(conversation.id);
          while (oldest != null) {
            if (!await _canContinueBackgroundSync(generation)) return;
            final page = await _smsController.loadThreadMessages(
              conversation.id,
              before: oldest.sentAt,
              beforeMessageId: oldest.id,
              limit: pageSize,
              background: true,
            );
            await _localSmsStore.storeMessagePage(
              conversation.id,
              page,
              reachedBeginning: page.length < pageSize,
            );
            await _publishSyncProgress(totalMessages: totalMessages);
            if (page.length < pageSize) break;
            oldest = page.first;
            await Future<void>.delayed(const Duration(milliseconds: 35));
          }
        } catch (error) {
          debugPrint(
            'Background SMS sync failed for ${conversation.id}: $error',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } catch (error) {
      debugPrint('Background SMS sync could not start: $error');
    } finally {
      await _publishSyncProgress(
        totalMessages: totalMessages,
        active: false,
        force: true,
      );
    }
  }

  Future<void> _publishSyncProgress({
    required int totalMessages,
    bool active = true,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastSyncProgressUpdate) <
            const Duration(milliseconds: 350)) {
      return;
    }
    _lastSyncProgressUpdate = now;
    int cachedMessages;
    try {
      cachedMessages = await _localSmsStore.countMessages();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _smsSyncProgress.value = SmsSyncProgress(
      active: active &&
          totalMessages > 0 &&
          cachedMessages < totalMessages,
      cachedMessages: cachedMessages,
      totalMessages: totalMessages,
    );
  }

  Future<List<SmsSearchHit>> _searchCachedMessages(String query) =>
      _localSmsStore.searchMessages(query);

  Future<bool> _canContinueBackgroundSync(int generation) async {
    if (generation != _backgroundSyncGeneration ||
        !_smsController.isActive ||
        _lifecycleState != AppLifecycleState.resumed ||
        _conversationRouteVisible) {
      return false;
    }
    while (_foregroundThreadLoads > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (generation != _backgroundSyncGeneration ||
          _lifecycleState != AppLifecycleState.resumed ||
          _conversationRouteVisible) {
        return false;
      }
    }
    return true;
  }

  Future<int> _loadConversationMessages(Conversation conversation) async {
    if (!_smsController.isActive) return conversation.messages.length;
    _foregroundThreadLoads++;
    try {
      await _localSmsStore.updateConversation(conversation);
      await _localSmsStore.markConversationRead(conversation.id);
      final cached = await _localSmsStore.loadRecentMessages(conversation.id);
      if (cached.isNotEmpty) {
        if (!mounted) return 0;
        conversation.messages
          ..clear()
          ..addAll(cached);
        unawaited(_refreshThreadHeadInCache(conversation.id));
        return cached.length;
      }

      final messages = await _smsController.loadThreadMessages(
        conversation.id,
      );
      await _localSmsStore.storeMessagePage(
        conversation.id,
        messages,
        reachedBeginning: messages.length < 40,
      );
      if (!mounted) return 0;
      conversation.messages
        ..clear()
        ..addAll(messages);
      return messages.length;
    } finally {
      _foregroundThreadLoads--;
    }
  }

  Future<int> _loadOlderConversationMessages(
    Conversation conversation,
  ) async {
    if (!_smsController.isActive || conversation.messages.isEmpty) return 0;
    _foregroundThreadLoads++;
    try {
      final visibleOldest = conversation.messages.first;
      var older = await _localSmsStore.loadMessagesBefore(
        conversation.id,
        visibleOldest,
        limit: 120,
      );
      if (older.isEmpty &&
          !await _localSmsStore.isThreadFullySynced(conversation.id)) {
        final cachedOldest =
            await _localSmsStore.oldestMessage(conversation.id) ??
                visibleOldest;
        final providerPage = await _smsController.loadThreadMessages(
          conversation.id,
          before: cachedOldest.sentAt,
          beforeMessageId: cachedOldest.id,
          limit: 120,
        );
        await _localSmsStore.storeMessagePage(
          conversation.id,
          providerPage,
          reachedBeginning: providerPage.length < 40,
        );
        older = await _localSmsStore.loadMessagesBefore(
          conversation.id,
          visibleOldest,
          limit: 120,
        );
      }
      if (!mounted || older.isEmpty) return 0;
      final existingIds = conversation.messages
          .map((message) => message.id)
          .toSet();
      final unique = older
          .where((message) => existingIds.add(message.id))
          .toList();
      if (unique.isEmpty) return 0;
      conversation.messages.insertAll(0, unique);
      return unique.length;
    } finally {
      _foregroundThreadLoads--;
    }
  }

  Future<void> _refreshThreadHeadInCache(String threadId) async {
    try {
      final latest = await _smsController.loadThreadMessages(threadId);
      await _localSmsStore.storeMessagePage(
        threadId,
        latest,
        reachedBeginning: latest.length < 40,
      );
    } catch (error) {
      debugPrint('Thread cache refresh failed for $threadId: $error');
    }
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
        unawaited(
          _cacheConversationEnrichment(enrichment),
        );
      }
    });
  }

  Future<void> _cacheConversationEnrichment(
    ConversationEnrichment enrichment,
  ) async {
    try {
      await _localSmsStore.updateEnrichment(
        threadId: enrichment.id,
        address: enrichment.address,
        title: enrichment.title,
        avatarBytes: enrichment.avatarBytes,
      );
    } catch (error) {
      debugPrint('Contact cache update failed: $error');
    }
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
      _cacheOptimisticMessage(conversation, conversation.messages.last),
    );
    unawaited(
      _sendPhoneMessage(conversation, address, trimmed, pendingId),
    );
  }

  Future<void> _cacheOptimisticMessage(
    Conversation conversation,
    ChatMessage message,
  ) async {
    try {
      await _localSmsStore.updateConversation(conversation);
      await _localSmsStore.storeMessagePage(
        conversation.id,
        [message],
        reachedBeginning: false,
      );
    } catch (error) {
      debugPrint('Optimistic message cache failed: $error');
    }
  }

  Future<void> _sendPhoneMessage(
    Conversation conversation,
    String address,
    String text,
    String pendingId,
  ) async {
    try {
      await _smsController.sendText(address, text);
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
        unawaited(
          _cacheFailedMessage(conversation, pendingId, failedMessage),
        );
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      final pendingIndex = conversation.messages.indexWhere(
        (message) => message.id == pendingId,
      );
      if (pendingIndex != -1) {
        final pending = conversation.messages[pendingIndex];
        conversation.messages[pendingIndex] = ChatMessage(
          id: pending.id,
          text: pending.text,
          sentAt: pending.sentAt,
          isFromMe: true,
          deliveryState: DeliveryState.delivered,
        );
      }
    });
    try {
      await _localSmsStore.deleteMessage(conversation.id, pendingId);
    } catch (error) {
      debugPrint('Sent message cache cleanup failed: $error');
    }
    unawaited(_refreshThreadHeadInCache(conversation.id));
    // Reload only thread summaries here. Replacing the open AnimatedList
    // would desynchronize its item count from the optimistic message row.
    try {
      await _loadPhoneMessages();
    } catch (error) {
      debugPrint('Conversation header refresh after send failed: $error');
    }
  }

  Future<void> _cacheFailedMessage(
    Conversation conversation,
    String pendingId,
    ChatMessage failedMessage,
  ) async {
    try {
      await _localSmsStore.deleteMessage(conversation.id, pendingId);
      await _cacheOptimisticMessage(conversation, failedMessage);
    } catch (error) {
      debugPrint('Failed message cache update failed: $error');
    }
  }

  void _replaceConversations(List<Conversation> conversations) {
    setState(() => _messageRepository.replaceAll(conversations));
    if (_smsController.isActive) {
      unawaited(_persistConversationHeaders(conversations));
    }
  }

  Future<void> _persistConversationHeaders(
    List<Conversation> conversations,
  ) async {
    try {
      await _localSmsStore.replaceConversationHeaders(conversations);
    } catch (error) {
      debugPrint('Conversation preference cache failed: $error');
    }
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    if (_smsController.isActive) {
      await _smsController.deleteThread(conversation.id);
      await _localSmsStore.deleteConversation(conversation.id);
    }
  }

  void _callConversation(Conversation conversation) {
    final address = conversation.address;
    if (address == null || address.isEmpty) return;
    unawaited(_smsController.dialNumber(address));
  }

  void _openConversationContact(Conversation conversation) {
    final address = conversation.address;
    if (address == null || address.isEmpty) return;
    unawaited(_openContact(address));
  }

  Future<void> _openContact(String address) async {
    try {
      await _smsController.openContact(address);
    } catch (error) {
      debugPrint('Contact could not be opened: $error');
    }
  }

  void _setConversationRouteVisible(bool visible) {
    _conversationRouteVisible = visible;
    if (visible) {
      _backgroundSyncGeneration++;
    } else if (_smsController.isActive) {
      _scheduleBackgroundMessageSync(_messageRepository.conversations);
    }
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
            loadingConversations: _loadingPhoneMessages,
            loadError: _phoneLoadError,
            onSend: _sendMessage,
            onReplaceConversations: _replaceConversations,
            smsController: _smsController,
            onEnableSmsMode: _enableSmsMode,
            onReloadPhoneMessages: _loadPhoneMessages,
            onDeleteConversation: _deleteConversation,
            onLoadConversation: _loadConversationMessages,
            onLoadOlderConversation: _loadOlderConversationMessages,
            onCallConversation: _callConversation,
            onOpenConversationContact: _openConversationContact,
            onConversationVisibilityChanged: _setConversationRouteVisible,
            syncProgress: _smsSyncProgress,
            onSearchMessages: _searchCachedMessages,
          ),
        ),
      ),
    );
  }
}
