import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../models/notification_open_request.dart';
import '../models/sms_sync_progress.dart';
import '../models/sms_search_hit.dart';
import '../settings/app_settings.dart';
import '../services/android_sms_service.dart';
import '../theme/messages_theme.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/ios_search_field.dart';
import 'conversation_screen.dart';
import 'settings_screen.dart';

const maxPinnedConversations = 9;

bool hasAvailablePinSlot(Iterable<Conversation> conversations) =>
    conversations.where((conversation) => conversation.isPinned).length <
    maxPinnedConversations;

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({
    super.key,
    required this.conversations,
    required this.loadingConversations,
    required this.loadError,
    required this.onSend,
    required this.onReplaceConversations,
    required this.smsController,
    required this.onEnableSmsMode,
    required this.onReloadPhoneMessages,
    required this.onDeleteConversation,
    required this.onLoadConversation,
    this.onLoadMessageContext,
    required this.onLoadOlderConversation,
    required this.onCallConversation,
    required this.onOpenConversationContact,
    required this.onConversationVisibilityChanged,
    required this.syncProgress,
    required this.onSearchMessages,
    this.notificationOpenRequest,
  });

  final List<Conversation> conversations;
  final bool loadingConversations;
  final String? loadError;
  final void Function(Conversation conversation, String text) onSend;
  final ValueChanged<List<Conversation>> onReplaceConversations;
  final AndroidSmsController smsController;
  final Future<bool> Function() onEnableSmsMode;
  final Future<void> Function() onReloadPhoneMessages;
  final Future<void> Function(Conversation) onDeleteConversation;
  final Future<int> Function(Conversation) onLoadConversation;
  final Future<int> Function(Conversation, String)? onLoadMessageContext;
  final Future<int> Function(Conversation) onLoadOlderConversation;
  final ValueChanged<Conversation> onCallConversation;
  final ValueChanged<Conversation> onOpenConversationContact;
  final ValueChanged<bool> onConversationVisibilityChanged;
  final ValueListenable<SmsSyncProgress> syncProgress;
  final Future<List<SmsSearchHit>> Function(String query) onSearchMessages;
  final ValueListenable<NotificationOpenRequest?>? notificationOpenRequest;

  @override
  State<ConversationListScreen> createState() =>
      _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _editingFavorites = false;
  bool _searchingMessages = false;
  List<SmsSearchHit> _messageSearchResults = const <SmsSearchHit>[];
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  late bool _syncWasActive;
  int _lastNotificationOpenSequence = -1;
  String? _activeConversationId;
  bool _openingNotificationConversation = false;

  @override
  void initState() {
    super.initState();
    _syncWasActive = widget.syncProgress.value.active;
    widget.syncProgress.addListener(_handleSyncProgress);
    widget.notificationOpenRequest?.addListener(
      _handleNotificationOpenRequest,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleNotificationOpenRequest();
    });
  }

  @override
  void didUpdateWidget(ConversationListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncProgress != widget.syncProgress) {
      oldWidget.syncProgress.removeListener(_handleSyncProgress);
      _syncWasActive = widget.syncProgress.value.active;
      widget.syncProgress.addListener(_handleSyncProgress);
    }
    if (oldWidget.notificationOpenRequest != widget.notificationOpenRequest) {
      oldWidget.notificationOpenRequest?.removeListener(
        _handleNotificationOpenRequest,
      );
      widget.notificationOpenRequest?.addListener(
        _handleNotificationOpenRequest,
      );
      _handleNotificationOpenRequest();
    }
  }

  void _handleNotificationOpenRequest() {
    final request = widget.notificationOpenRequest?.value;
    if (request == null ||
        request.sequence == _lastNotificationOpenSequence) {
      return;
    }
    _lastNotificationOpenSequence = request.sequence;
    if (_activeConversationId == request.threadId) return;
    unawaited(_openNotificationConversation(request.threadId));
  }

  Future<void> _openNotificationConversation(String threadId) async {
    if (_openingNotificationConversation) return;
    _openingNotificationConversation = true;
    try {
      var conversation = _conversationForThread(threadId);
      if (conversation == null) {
        try {
          await widget.onReloadPhoneMessages();
        } catch (_) {
          return;
        }
        if (!mounted) return;
        conversation = _conversationForThread(threadId);
      }
      if (conversation == null || !mounted) return;
      unawaited(_openConversation(conversation, forceReload: true));
    } finally {
      _openingNotificationConversation = false;
    }
  }

  List<Conversation> get _filtered {
    final conversations = [...widget.conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _query.trim().isEmpty ? conversations : const <Conversation>[];
  }

  void _handleSyncProgress() {
    final active = widget.syncProgress.value.active;
    if (_syncWasActive && !active && _query.trim().isNotEmpty) {
      _scheduleMessageSearch(_query, immediately: true);
    }
    _syncWasActive = active;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      if (value.trim().isEmpty) {
        _messageSearchResults = const <SmsSearchHit>[];
        _searchingMessages = false;
      } else {
        _messageSearchResults = const <SmsSearchHit>[];
        _searchingMessages = true;
      }
    });
    _scheduleMessageSearch(value);
  }

  void _scheduleMessageSearch(
    String value, {
    bool immediately = false,
  }) {
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    final query = value.trim();
    if (query.isEmpty) return;
    _searchDebounce = Timer(
      immediately ? Duration.zero : const Duration(milliseconds: 220),
      () async {
        try {
          final matches = await widget.onSearchMessages(query);
          if (!mounted || generation != _searchGeneration) return;
          setState(() {
            _messageSearchResults = matches;
            _searchingMessages = false;
          });
        } catch (_) {
          if (!mounted || generation != _searchGeneration) return;
          setState(() => _searchingMessages = false);
        }
      },
    );
  }

  Conversation? _conversationForThread(String threadId) {
    for (final conversation in widget.conversations) {
      if (conversation.id == threadId) return conversation;
    }
    return null;
  }

  Future<void> _openConversation(
    Conversation conversation, {
    String? initialMessageId,
    bool forceReload = false,
  }) async {
    final targetMessageId = initialMessageId;
    _activeConversationId = conversation.id;
    widget.onConversationVisibilityChanged(true);
    try {
      setState(() => conversation.unreadCount = 0);
      unawaited(_markConversationRead(conversation));
      if (!mounted) return;
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => ConversationScreen(
            conversation: conversation,
            allConversations: widget.conversations,
            messagesPreloaded:
                !forceReload &&
                targetMessageId == null &&
                conversation.messages.isNotEmpty,
            initialMessageId: targetMessageId,
            notificationOpenRequest: widget.notificationOpenRequest,
            onLoad: () => targetMessageId == null
                ? widget.onLoadConversation(conversation)
                : widget.onLoadMessageContext?.call(
                      conversation,
                      targetMessageId,
                    ) ??
                    widget.onLoadConversation(conversation),
            onLoadOlder: () => widget.onLoadOlderConversation(conversation),
            onSend: (text) {
              widget.onSend(conversation, text);
              setState(() {});
            },
            onCall: () => widget.onCallConversation(conversation),
            onOpenContact: () =>
                widget.onOpenConversationContact(conversation),
          ),
        ),
      );
      if (targetMessageId != null) {
        await widget.onLoadConversation(conversation);
      }
      await _markConversationRead(conversation);
      if (!mounted) return;
      setState(() => conversation.unreadCount = 0);
    } finally {
      if (_activeConversationId == conversation.id) {
        _activeConversationId = null;
      }
      widget.onConversationVisibilityChanged(false);
    }
  }

  Future<void> _markConversationRead(Conversation conversation) async {
    try {
      await widget.smsController.markThreadRead(conversation.id);
    } catch (_) {
      // Keep navigation responsive if the provider changes state mid-route.
    }
  }

  Future<void> _openSettings() async {
    HapticFeedback.selectionClick();
    await widget.smsController.refreshState();
    if (!mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => SettingsScreen(
          conversations: widget.conversations,
          onImported: widget.onReplaceConversations,
          smsController: widget.smsController,
          onEnableSmsMode: widget.onEnableSmsMode,
          onReloadPhoneMessages: widget.onReloadPhoneMessages,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _retryPhoneMessages() async {
    try {
      await widget.onReloadPhoneMessages();
    } catch (_) {
      // The parent keeps the error text visible and offers another retry.
    }
  }

  Future<void> _pinConversation(Conversation conversation) async {
    if (conversation.isPinned) return;
    if (!hasAvailablePinSlot(widget.conversations)) {
      HapticFeedback.heavyImpact();
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Pin Limit Reached'),
          content: const Text('You can pin up to 9 conversations.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => conversation.isPinned = true);
  }

  void _unpinConversation(Conversation conversation) {
    HapticFeedback.mediumImpact();
    setState(() {
      conversation.isPinned = false;
      if (!widget.conversations.any((item) => item.isPinned)) {
        _editingFavorites = false;
      }
    });
  }

  Future<void> _showConversationActions(Conversation conversation) async {
    HapticFeedback.mediumImpact();
    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close conversation actions',
      barrierColor: CupertinoColors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) =>
          _ConversationContextOverlay(
        conversation: conversation,
        onAction: (value) => Navigator.of(context).pop(value),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pin':
        if (conversation.isPinned) {
          _unpinConversation(conversation);
        } else {
          await _pinConversation(conversation);
        }
        break;
      case 'mute':
        _toggleMute(conversation);
        break;
      case 'delete':
        await _confirmDelete(conversation);
        break;
    }
  }

  void _toggleMute(Conversation conversation) {
    HapticFeedback.mediumImpact();
    setState(() => conversation.isMuted = !conversation.isMuted);
  }

  Future<void> _confirmDelete(Conversation conversation) async {
    final shouldDelete = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('Delete “${conversation.title}”?'),
        message: const Text('This conversation will be removed from the list.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Conversation'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (shouldDelete == true && mounted) {
      HapticFeedback.mediumImpact();
      await widget.onDeleteConversation(conversation);
      if (!mounted) return;
      setState(() => widget.conversations.remove(conversation));
    }
  }

  @override
  void dispose() {
    widget.syncProgress.removeListener(_handleSyncProgress);
    widget.notificationOpenRequest?.removeListener(
      _handleNotificationOpenRequest,
    );
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchActive = _query.trim().isNotEmpty;
    final filtered = _filtered;
    final pinned =
        filtered.where((conversation) => conversation.isPinned).toList();
    final regular =
        filtered.where((conversation) => !conversation.isPinned).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: MessagesPalette.isDark(context)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: CupertinoPageScaffold(
        backgroundColor: MessagesPalette.background(context),
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: IosSearchField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                  ),
                ),
              ),
              if (!searchActive && pinned.isNotEmpty)
                SliverToBoxAdapter(
                  child: _PinnedGrid(
                    conversations: pinned,
                    onTap: _openConversation,
                    editing: _editingFavorites,
                    onUnpin: _unpinConversation,
                    onLongPress: _showConversationActions,
                  ),
                ),
              if (searchActive && _searchingMessages)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CupertinoActivityIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          'Searching Messages…',
                          style: MessagesText.secondary(context),
                        ),
                      ],
                    ),
                  ),
                )
              else if (searchActive && _messageSearchResults.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No Results',
                      style: MessagesText.secondary(context),
                    ),
                  ),
                )
              else if (searchActive)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final result = _messageSearchResults[index];
                      final conversation =
                          _conversationForThread(result.threadId);
                      if (conversation == null) {
                        return const SizedBox.shrink();
                      }
                      return _MessageSearchResultRow(
                        conversation: conversation,
                        result: result,
                        query: _query.trim(),
                        onTap: () => _openConversation(
                          conversation,
                          initialMessageId: result.messageId,
                        ),
                      );
                    },
                    childCount: _messageSearchResults.length,
                  ),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.loadingConversations) ...[
                            const CupertinoActivityIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              'Loading Messages…',
                              style: MessagesText.secondary(context),
                            ),
                          ] else ...[
                            Text(
                              widget.loadError == null
                                  ? 'No Conversations'
                                  : 'Messages could not be loaded.',
                              textAlign: TextAlign.center,
                              style: MessagesText.secondary(context),
                            ),
                            if (widget.loadError != null) ...[
                              const SizedBox(height: 8),
                              CupertinoButton(
                                onPressed: _retryPhoneMessages,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => SwipeableConversationRow(
                      conversation: regular[index],
                      onTap: () => _openConversation(regular[index]),
                      onPin: () => _pinConversation(regular[index]),
                      onToggleMute: () => _toggleMute(regular[index]),
                      onDelete: () => _confirmDelete(regular[index]),
                      onLongPress: () =>
                          _showConversationActions(regular[index]),
                    ),
                    childCount: regular.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
            ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              child: ValueListenableBuilder<SmsSyncProgress>(
                valueListenable: widget.syncProgress,
                builder: (context, progress, _) => IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: progress.active
                        ? _SmsSyncProgressPill(
                            key: const ValueKey('sms-sync-progress'),
                            progress: progress,
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('sms-sync-idle'),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topCompensation =
        (44.0 - MediaQuery.paddingOf(context).top)
            .clamp(0.0, 44.0)
            .toDouble();
    return SizedBox(
      height: 44 + topCompensation,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                'Messages',
                key: const ValueKey('messages-title'),
                style: TextStyle(
                  color: MessagesPalette.label(context),
                  fontFamily: 'SF Pro Text',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.25,
                ),
              ),
              Positioned(
                left: 8,
                child: CupertinoButton(
                  minSize: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _editingFavorites = !_editingFavorites);
                  },
                  child: Text(
                    _editingFavorites ? 'Done' : 'Edit',
                    style: const TextStyle(
                      color: MessagesPalette.blue,
                      fontFamily: 'SF Pro Text',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 54,
                child: CupertinoButton(
                  key: const ValueKey('open-settings-button'),
                  minSize: 44,
                  padding: EdgeInsets.zero,
                  onPressed: _openSettings,
                  child: const Icon(CupertinoIcons.ellipsis_circle, size: 20),
                ),
              ),
              Positioned(
                right: 8,
                child: CupertinoButton(
                  minSize: 44,
                  padding: EdgeInsets.zero,
                  onPressed: () => HapticFeedback.selectionClick(),
                  child: const Icon(CupertinoIcons.square_pencil, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageSearchResultRow extends StatelessWidget {
  const _MessageSearchResultRow({
    required this.conversation,
    required this.result,
    required this.query,
    required this.onTap,
  });

  final Conversation conversation;
  final SmsSearchHit result;
  final String query;
  final VoidCallback onTap;

  String _snippet() {
    final text = result.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final matchIndex = text.toLowerCase().indexOf(query.toLowerCase());
    if (matchIndex < 0 || text.length <= 120) return text;
    var start = matchIndex > 42 ? matchIndex - 42 : 0;
    var end = start + 120;
    if (end > text.length) {
      end = text.length;
      start = (end - 120).clamp(0, end).toInt();
    }
    return '${start > 0 ? '…' : ''}${text.substring(start, end)}'
        '${end < text.length ? '…' : ''}';
  }

  List<InlineSpan> _highlightedSpans(String text) {
    final spans = <InlineSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var cursor = 0;
    while (cursor < text.length) {
      final match = lowerText.indexOf(lowerQuery, cursor);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (match > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match, match + query.length),
          style: const TextStyle(
            color: MessagesPalette.blue,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = match + query.length;
    }
    return spans;
  }

  String _time(BuildContext context) {
    final difference = DateTime.now().difference(result.sentAt);
    if (difference.inDays == 0) {
      return AppSettingsScope.of(context).formatTime(
        result.sentAt,
        platformUses24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
      );
    }
    if (difference.inDays == 1) return 'Yesterday';
    return AppSettingsScope.of(context).formatDate(
      result.sentAt,
      localeCode: Localizations.localeOf(context).languageCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final snippet = _snippet();
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: .55,
      onPressed: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 10, 13, 10),
            child: ContactAvatar(conversation: conversation, size: 44),
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 78),
              padding: const EdgeInsets.fromLTRB(0, 9, 14, 9),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: MessagesPalette.hairline(context)
                        .withValues(alpha: .55),
                    width: .45,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MessagesText.headline(context).copyWith(
                            fontSize: 17,
                            height: 1.08,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _time(context),
                        style: MessagesText.secondary(context).copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      style: MessagesText.secondary(context).copyWith(
                        fontSize: 15,
                        height: 1.18,
                      ),
                      children: _highlightedSpans(snippet),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmsSyncProgressPill extends StatelessWidget {
  const _SmsSyncProgressPill({
    super.key,
    required this.progress,
  });

  final SmsSyncProgress progress;

  String _count(int value) {
    final digits = value.toString();
    final output = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) output.write(',');
      output.write(digits[index]);
    }
    return output.toString();
  }

  @override
  Widget build(BuildContext context) {
    final fraction = progress.fraction;
    final percent = (fraction * 100).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          const CupertinoDynamicColor.withBrightness(
            color: Color(0xF2FFFFFF),
            darkColor: Color(0xF21C1C1E),
          ),
          context,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CustomPaint(
                painter: _SyncRingPainter(
                  fraction: fraction,
                  trackColor: MessagesPalette.separator,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Indexing Messages  $percent%',
                    style: MessagesText.body(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_count(progress.cachedMessages)} of '
                    '${_count(progress.totalMessages)} · Search results '
                    'will become complete',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MessagesText.secondary(context).copyWith(
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncRingPainter extends CustomPainter {
  const _SyncRingPainter({
    required this.fraction,
    required this.trackColor,
  });

  final double fraction;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 4) / 2;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final progress = Paint()
      ..color = MessagesPalette.blue
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5707963267948966,
      6.283185307179586 * fraction,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(_SyncRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.trackColor != trackColor;
}

class _PinnedGrid extends StatelessWidget {
  const _PinnedGrid({
    required this.conversations,
    required this.onTap,
    required this.editing,
    required this.onUnpin,
    required this.onLongPress,
  });

  final List<Conversation> conversations;
  final ValueChanged<Conversation> onTap;
  final bool editing;
  final ValueChanged<Conversation> onUnpin;
  final ValueChanged<Conversation> onLongPress;

  @override
  Widget build(BuildContext context) {
    final itemWidth = (MediaQuery.sizeOf(context).width - 20) / 3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Wrap(
        alignment: WrapAlignment.start,
        runSpacing: 16,
        children: conversations.map((conversation) {
          return SizedBox(
            width: itemWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: editing ? null : () => onLongPress(conversation),
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: editing ? () {} : () => onTap(conversation),
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ContactAvatar(
                          key: ValueKey('pinned-avatar-${conversation.id}'),
                          conversation: conversation,
                          size: 95,
                        ),
                        if (editing)
                          Positioned(
                            left: -3,
                            top: -3,
                            child: CupertinoButton(
                              key: ValueKey(
                                'unpin-favorite-${conversation.id}',
                              ),
                              minSize: 28,
                              padding: EdgeInsets.zero,
                              onPressed: () => onUnpin(conversation),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemGrey,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: MessagesPalette.background(context),
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  CupertinoIcons.minus,
                                  size: 15,
                                  color: CupertinoColors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (conversation.unreadCount > 0) ...[
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              color: MessagesPalette.blue,
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox(width: 10, height: 10),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MessagesText.secondary(context).copyWith(
                              color: MessagesPalette.secondaryLabel(context),
                              fontSize: 12.5,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ConversationContextOverlay extends StatelessWidget {
  const _ConversationContextOverlay({
    required this.conversation,
    required this.onAction,
  });

  final Conversation conversation;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final previewWidth =
        (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 360.0).toDouble();
    final previewHeight = (MediaQuery.sizeOf(context).height * .46)
        .clamp(280.0, 390.0)
        .toDouble();
    final messages = conversation.messages.length > 5
        ? conversation.messages.sublist(conversation.messages.length - 5)
        : conversation.messages;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: ColoredBox(
                color: CupertinoColors.black.withValues(alpha: .24),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: const ValueKey('conversation-context-preview'),
                    width: previewWidth,
                    height: previewHeight,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: MessagesPalette.background(context),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withValues(alpha: .2),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 58,
                          decoration: BoxDecoration(
                            color: MessagesPalette.isDark(context)
                                ? const Color(0xFF1C1C1E)
                                : const Color(0xFFF1F1F2),
                            border: Border(
                              bottom: BorderSide(
                                color: MessagesPalette.hairline(context)
                                    .withValues(alpha: .55),
                                width: .5,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ContactAvatar(
                                conversation: conversation,
                                size: 34,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  conversation.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: MessagesPalette.label(context),
                                    fontFamily: 'SF Pro Text',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            reverse: true,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message =
                                  messages[messages.length - 1 - index];
                              return _ConversationPreviewBubble(
                                message: message,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: const ValueKey('conversation-context-actions'),
                    width: previewWidth,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: MessagesPalette.elevatedBackground(context)
                          .withValues(alpha: .96),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ConversationContextAction(
                          icon: CupertinoIcons.pin_fill,
                          label: conversation.isPinned ? 'Unpin' : 'Pin',
                          onPressed: () => onAction('pin'),
                        ),
                        _ConversationContextAction(
                          icon: conversation.isMuted
                              ? CupertinoIcons.bell_fill
                              : CupertinoIcons.bell_slash_fill,
                          label: conversation.isMuted
                              ? 'Show Alerts'
                              : 'Hide Alerts',
                          onPressed: () => onAction('mute'),
                        ),
                        _ConversationContextAction(
                          icon: CupertinoIcons.delete_solid,
                          label: 'Delete',
                          destructive: true,
                          onPressed: () => onAction('delete'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationPreviewBubble extends StatelessWidget {
  const _ConversationPreviewBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final sent = message.isFromMe;
    return Align(
      alignment: sent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .62,
        ),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: sent
              ? MessagesPalette.blue
              : MessagesPalette.receivedBubble(context),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: sent
                ? CupertinoColors.white
                : MessagesPalette.label(context),
            fontFamily: 'SF Pro Text',
            fontSize: 14,
            height: 1.15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ConversationContextAction extends StatelessWidget {
  const _ConversationContextAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? CupertinoColors.systemRed
        : MessagesPalette.label(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: MessagesPalette.hairline(context).withValues(alpha: .45),
            width: .5,
          ),
        ),
      ),
      child: CupertinoButton(
        pressedOpacity: .55,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        onPressed: onPressed,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'SF Pro Text',
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              Icon(icon, color: color, size: 21),
            ],
          ),
        ),
      ),
    );
  }
}

class SwipeableConversationRow extends StatefulWidget {
  const SwipeableConversationRow({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.onPin,
    required this.onToggleMute,
    required this.onDelete,
    required this.onLongPress,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onToggleMute;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  @override
  State<SwipeableConversationRow> createState() =>
      _SwipeableConversationRowState();
}

class _SwipeableConversationRowState extends State<SwipeableConversationRow>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 78.0;
  static const _rightActionsWidth = _actionWidth * 2;
  late final AnimationController _offsetController =
      AnimationController.unbounded(vsync: this);

  void _animateTo(double target) {
    _offsetController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _offsetController.value = (_offsetController.value + details.delta.dx)
        .clamp(-_rightActionsWidth, _actionWidth)
        .toDouble();
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 700 || _offsetController.value > _actionWidth * .48) {
      _animateTo(_actionWidth);
    } else if (velocity < -700 ||
        _offsetController.value < -_rightActionsWidth * .3) {
      _animateTo(-_rightActionsWidth);
    } else {
      _animateTo(0);
    }
  }

  void _perform(VoidCallback action) {
    _offsetController.value = 0;
    action();
  }

  @override
  void dispose() {
    _offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetController,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        onLongPress: widget.onLongPress,
        child: ConversationRow(
          conversation: widget.conversation,
          onTap: widget.onTap,
        ),
      ),
      builder: (context, child) {
        final offset = _offsetController.value;
        if (offset.abs() < .01) return child!;
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: _buildSwipeActions(context)),
              Transform.translate(
                key: ValueKey('swipe-content-${widget.conversation.id}'),
                offset: Offset(offset, 0),
                child: child,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSwipeActions(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _actionWidth,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            color: MessagesPalette.blue,
            borderRadius: BorderRadius.zero,
            onPressed: () => _perform(widget.onPin),
            child: const _SwipeActionContent(
              icon: CupertinoIcons.pin_fill,
              label: 'Pin',
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: _actionWidth,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            color: const Color(0xFFFF9F0A),
            borderRadius: BorderRadius.zero,
            onPressed: () => _perform(widget.onToggleMute),
            child: _SwipeActionContent(
              icon: widget.conversation.isMuted
                  ? CupertinoIcons.bell_fill
                  : CupertinoIcons.bell_slash_fill,
              label: widget.conversation.isMuted ? 'Unmute' : 'Mute',
            ),
          ),
        ),
        SizedBox(
          width: _actionWidth,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            color: CupertinoColors.systemRed,
            borderRadius: BorderRadius.zero,
            onPressed: () => _perform(widget.onDelete),
            child: const _SwipeActionContent(
              icon: CupertinoIcons.delete_solid,
              label: 'Delete',
            ),
          ),
        ),
      ],
    );
  }
}

class _SwipeActionContent extends StatelessWidget {
  const _SwipeActionContent({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: CupertinoColors.white, size: 23),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: CupertinoColors.white,
            fontFamily: 'SF Pro Text',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class ConversationRow extends StatelessWidget {
  const ConversationRow({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlighted = conversation.unreadCount > 0;
    return ColoredBox(
      color: MessagesPalette.background(context),
      child: CupertinoButton(
        pressedOpacity: .55,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 10, 13, 10),
              child: ContactAvatar(conversation: conversation, size: 44),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 78),
                padding: const EdgeInsets.fromLTRB(0, 9, 10, 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: MessagesPalette.hairline(context)
                          .withValues(alpha: .55),
                      width: .45,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (highlighted)
                      const Padding(
                        padding: EdgeInsets.only(top: 8, right: 7),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: MessagesPalette.blue,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(width: 9, height: 9),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MessagesText.headline(context).copyWith(
                              fontSize: 18,
                              height: 1.08,
                              fontWeight: highlighted
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (conversation.isMuted)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    CupertinoIcons.bell_slash_fill,
                                    size: 12,
                                    color: MessagesPalette.secondaryLabel(
                                      context,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  conversation.preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      MessagesText.secondary(context).copyWith(
                                    fontSize: 15,
                                    height: 1.15,
                                    fontWeight: highlighted
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Row(
                        children: [
                          Text(
                            _relativeTime(context, conversation.updatedAt),
                            style: MessagesText.secondary(context).copyWith(
                              fontSize: 13,
                              fontWeight: highlighted
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            CupertinoIcons.chevron_right,
                            size: 13,
                            color: MessagesPalette.secondaryLabel(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(BuildContext context, DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 60) return '${difference.inMinutes} min';
    if (difference.inHours < 24) {
      return AppSettingsScope.of(context).formatTime(
        value,
        platformUses24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
      );
    }
    if (difference.inDays == 1) return 'Yesterday';
    return AppSettingsScope.of(context).formatDate(
      value,
      localeCode: Localizations.localeOf(context).languageCode,
    );
  }
}
