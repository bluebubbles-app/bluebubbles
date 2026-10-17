import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
    required this.onRetrySend,
    required this.onReplaceConversations,
    required this.smsController,
    required this.onEnableSmsMode,
    required this.onReloadPhoneMessages,
    required this.onDeleteConversation,
    this.onResolveConversation,
    required this.onLoadConversation,
    this.onLoadMessageContext,
    required this.onLoadOlderConversation,
    required this.onCallConversation,
    required this.onOpenConversationContact,
    required this.onConversationVisibilityChanged,
    required this.openConversationMessagesRevision,
    required this.syncProgress,
    required this.onSearchMessages,
    this.notificationOpenRequest,
  });

  final List<Conversation> conversations;
  final bool loadingConversations;
  final String? loadError;
  final void Function(Conversation conversation, String text) onSend;
  final void Function(Conversation conversation, ChatMessage message)
      onRetrySend;
  final ValueChanged<List<Conversation>> onReplaceConversations;
  final AndroidSmsController smsController;
  final Future<bool> Function() onEnableSmsMode;
  final Future<void> Function() onReloadPhoneMessages;
  final Future<void> Function(Conversation) onDeleteConversation;
  final Future<Conversation> Function(String address)? onResolveConversation;
  final Future<int> Function(Conversation) onLoadConversation;
  final Future<int> Function(Conversation, String)? onLoadMessageContext;
  final Future<int> Function(Conversation) onLoadOlderConversation;
  final ValueChanged<Conversation> onCallConversation;
  final ValueChanged<Conversation> onOpenConversationContact;
  final void Function(bool visible, Conversation? conversation)
      onConversationVisibilityChanged;
  final ValueListenable<int> openConversationMessagesRevision;
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
  bool _selectingConversations = false;
  bool _deletingSelection = false;
  final Set<String> _selectedConversationIds = <String>{};
  bool _searchingMessages = false;
  List<SmsSearchHit> _messageSearchResults = const <SmsSearchHit>[];
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  late bool _syncWasActive;
  int _lastNotificationOpenSequence = -1;
  String? _activeConversationId;
  bool _openingNotificationConversation = false;
  int? _sortedConversationsSignature;
  List<Conversation> _sortedConversations = const <Conversation>[];
  final ValueNotifier<String?> _openSwipeConversationId =
      ValueNotifier<String?>(null);

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
    var signature = widget.conversations.length;
    for (final conversation in widget.conversations) {
      signature = Object.hash(
        signature,
        identityHashCode(conversation),
        conversation.id,
        conversation.updatedAt.microsecondsSinceEpoch,
      );
    }
    if (_sortedConversationsSignature != signature) {
      _sortedConversationsSignature = signature;
      _sortedConversations = List<Conversation>.of(widget.conversations)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return _query.trim().isEmpty
        ? _sortedConversations
        : const <Conversation>[];
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
    widget.onConversationVisibilityChanged(true, conversation);
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
            messagesChangedRevision:
                widget.openConversationMessagesRevision,
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
            onRetrySend: (message) {
              widget.onRetrySend(conversation, message);
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
      widget.onConversationVisibilityChanged(false, null);
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

  void _toggleConversationSelectionMode() {
    HapticFeedback.selectionClick();
    _searchController.clear();
    setState(() {
      _selectingConversations = !_selectingConversations;
      _editingFavorites = _selectingConversations;
      _selectedConversationIds.clear();
      _query = '';
      _messageSearchResults = const <SmsSearchHit>[];
      _searchingMessages = false;
    });
  }

  void _toggleConversationSelection(Conversation conversation) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedConversationIds.add(conversation.id)) {
        _selectedConversationIds.remove(conversation.id);
      }
    });
  }

  Future<void> _deleteSelectedConversations() async {
    if (_selectedConversationIds.isEmpty || _deletingSelection) return;
    final selected = widget.conversations
        .where((item) => _selectedConversationIds.contains(item.id))
        .toList();
    final count = selected.length;
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('Delete $count Conversation${count == 1 ? '' : 's'}?'),
        message: const Text(
          'Deleted conversations cannot be recovered.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete $count Conversation${count == 1 ? '' : 's'}'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingSelection = true);
    final deletedIds = <String>{};
    Object? failure;
    for (final conversation in selected) {
      try {
        await widget.onDeleteConversation(conversation);
        deletedIds.add(conversation.id);
      } catch (error) {
        failure ??= error;
      }
    }
    if (!mounted) return;
    setState(() {
      widget.conversations.removeWhere(
        (conversation) => deletedIds.contains(conversation.id),
      );
      _selectedConversationIds.removeAll(deletedIds);
      _deletingSelection = false;
      if (_selectedConversationIds.isEmpty) {
        _selectingConversations = false;
      }
    });
    HapticFeedback.mediumImpact();
    if (failure != null && mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Some Conversations Were Not Deleted'),
          content: const Text('Please try again.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _composeNewMessage() async {
    HapticFeedback.selectionClick();
    final conversation = await Navigator.of(context).push<Conversation>(
      CupertinoPageRoute<Conversation>(
        builder: (_) => _NewMessageRecipientScreen(
          conversations: widget.conversations,
          onResolveConversation: widget.onResolveConversation,
          smsController: widget.smsController,
        ),
      ),
    );
    if (!mounted || conversation == null) return;
    await _openConversation(conversation);
  }

  @override
  void dispose() {
    widget.syncProgress.removeListener(_handleSyncProgress);
    widget.notificationOpenRequest?.removeListener(
      _handleNotificationOpenRequest,
    );
    _searchDebounce?.cancel();
    _searchController.dispose();
    _openSwipeConversationId.dispose();
    super.dispose();
  }

  bool _handleConversationListScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        _openSwipeConversationId.value != null) {
      _openSwipeConversationId.value = null;
    }
    return false;
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
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleConversationListScroll,
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                    onTap: _selectingConversations
                        ? _toggleConversationSelection
                        : _openConversation,
                    editing: _editingFavorites,
                    selecting: _selectingConversations,
                    selectedIds: _selectedConversationIds,
                    onUnpin: _unpinConversation,
                    onLongPress: _selectingConversations
                        ? (_) {}
                        : _showConversationActions,
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
                      key: ValueKey('conversation-${regular[index].id}'),
                      conversation: regular[index],
                      openConversationId: _openSwipeConversationId,
                      selectionMode: _selectingConversations,
                      selected: _selectedConversationIds.contains(
                        regular[index].id,
                      ),
                      onTap: () => _selectingConversations
                          ? _toggleConversationSelection(regular[index])
                          : _openConversation(regular[index]),
                      onPin: () => _pinConversation(regular[index]),
                      onToggleMute: () => _toggleMute(regular[index]),
                      onDelete: () => _confirmDelete(regular[index]),
                      onLongPress: () =>
                          _showConversationActions(regular[index]),
                    ),
                    childCount: regular.length,
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: _selectingConversations ? 96 : 28,
                ),
              ),
                  ],
                ),
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
                    child: progress.active && !_selectingConversations
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
            if (_selectingConversations)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ConversationSelectionToolbar(
                  selectedCount: _selectedConversationIds.length,
                  deleting: _deletingSelection,
                  onDelete: _deleteSelectedConversations,
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
                _selectingConversations
                    ? '${_selectedConversationIds.length} Selected'
                    : 'Messages',
                key: const ValueKey('messages-title'),
                style: TextStyle(
                  color: MessagesPalette.label(context),
                  fontFamily: 'SF Pro Text',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.25,
                ),
              ),
              Positioned(
                left: 8,
                child: CupertinoButton(
                  key: const ValueKey('edit-conversations-button'),
                  minSize: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () {
                    _toggleConversationSelectionMode();
                  },
                  child: Text(
                    _selectingConversations ? 'Done' : 'Edit',
                    style: const TextStyle(
                      color: MessagesPalette.headerActionBlue,
                      fontFamily: 'SF Pro Text',
                      fontSize: 15,
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
                  onPressed: _selectingConversations ? null : _openSettings,
                  child: const Icon(
                    CupertinoIcons.ellipsis_circle,
                    color: MessagesPalette.headerActionBlue,
                    size: 21,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                child: CupertinoButton(
                  key: const ValueKey('new-message-button'),
                  minSize: 44,
                  padding: EdgeInsets.zero,
                  onPressed: _selectingConversations
                      ? null
                      : _composeNewMessage,
                  child: const Icon(
                    CupertinoIcons.square_pencil,
                    color: MessagesPalette.headerActionBlue,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? MessagesPalette.blue : CupertinoColors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? MessagesPalette.blue
              : MessagesPalette.secondaryLabel(context),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(
              CupertinoIcons.check_mark,
              size: 15,
              color: CupertinoColors.white,
            )
          : null,
    );
  }
}

class _ConversationSelectionToolbar extends StatelessWidget {
  const _ConversationSelectionToolbar({
    required this.selectedCount,
    required this.deleting,
    required this.onDelete,
  });

  final int selectedCount;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled = selectedCount > 0 && !deleting;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 58 + MediaQuery.paddingOf(context).bottom,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: MessagesPalette.background(context).withValues(alpha: .86),
            border: Border(
              top: BorderSide(
                color: MessagesPalette.hairline(context),
                width: .5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CupertinoButton(
                minSize: 44,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: enabled ? onDelete : null,
                child: deleting
                    ? const CupertinoActivityIndicator(radius: 9)
                    : Row(
                        children: [
                          Icon(
                            CupertinoIcons.delete,
                            size: 21,
                            color: enabled
                                ? CupertinoColors.systemRed
                                : MessagesPalette.secondaryLabel(context),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            selectedCount == 0
                                ? 'Delete'
                                : 'Delete ($selectedCount)',
                            style: TextStyle(
                              color: enabled
                                  ? CupertinoColors.systemRed
                                  : MessagesPalette.secondaryLabel(context),
                              fontFamily: 'SF Pro Text',
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewMessageRecipientScreen extends StatefulWidget {
  const _NewMessageRecipientScreen({
    required this.conversations,
    this.onResolveConversation,
    required this.smsController,
  });

  final List<Conversation> conversations;
  final Future<Conversation> Function(String address)? onResolveConversation;
  final AndroidSmsController smsController;

  @override
  State<_NewMessageRecipientScreen> createState() =>
      _NewMessageRecipientScreenState();
}

class _NewMessageRecipientScreenState
    extends State<_NewMessageRecipientScreen> {
  final _recipientController = TextEditingController();
  final _recipientFocus = FocusNode();
  String _query = '';
  bool _resolving = false;
  Timer? _contactSearchDebounce;
  int _contactSearchGeneration = 0;
  List<SmsContact> _contactMatches = const <SmsContact>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recipientFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _contactSearchDebounce?.cancel();
    _recipientController.dispose();
    _recipientFocus.dispose();
    super.dispose();
  }

  List<Conversation> get _matches {
    final query = _query.trim().toLowerCase();
    final conversations = [...widget.conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (query.isEmpty) return conversations.take(12).toList();
    return conversations
        .where(
          (conversation) =>
              conversation.title.toLowerCase().contains(query) ||
              (conversation.address?.toLowerCase().contains(query) ?? false),
        )
        .take(20)
        .toList();
  }

  Future<void> _useTypedRecipient() async {
    final address = _recipientController.text.trim();
    await _useRecipient(address);
  }

  Future<void> _useRecipient(String address) async {
    if (_resolving) return;
    if (address.isEmpty) return;
    for (final conversation in widget.conversations) {
      if (_sameAddress(conversation.address, address)) {
        Navigator.of(context).pop(conversation);
        return;
      }
    }
    final resolver = widget.onResolveConversation;
    if (resolver == null) {
      await _showError('SMS mode must be enabled to start a new conversation.');
      return;
    }
    setState(() => _resolving = true);
    try {
      final conversation = await resolver(address);
      if (mounted) Navigator.of(context).pop(conversation);
    } catch (_) {
      if (mounted) {
        setState(() => _resolving = false);
        await _showError('This conversation could not be created.');
      }
    }
  }

  void _onRecipientChanged(String value) {
    setState(() {
      _query = value;
      if (value.trim().isEmpty) _contactMatches = const <SmsContact>[];
    });
    _contactSearchDebounce?.cancel();
    final generation = ++_contactSearchGeneration;
    final query = value.trim();
    if (query.isEmpty) return;
    _contactSearchDebounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final results = await widget.smsController.searchContacts(query);
        if (!mounted || generation != _contactSearchGeneration) return;
        setState(() => _contactMatches = results);
      } catch (_) {
        if (!mounted || generation != _contactSearchGeneration) return;
        setState(() => _contactMatches = const <SmsContact>[]);
      }
    });
  }

  bool _sameAddress(String? first, String second) {
    if (first == null) return false;
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9+]'), '');
    return normalize(first) == normalize(second);
  }

  Future<void> _showError(String message) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('New Message'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final typedRecipient = _query.trim();
    return CupertinoPageScaffold(
      backgroundColor: MessagesPalette.background(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('New Message'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        border: Border(
          bottom: BorderSide(
            color: MessagesPalette.hairline(context),
            width: .5,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.fromLTRB(16, 5, 12, 5),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: MessagesPalette.hairline(context),
                    width: .5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'To:',
                    style: MessagesText.body(context).copyWith(
                      color: MessagesPalette.secondaryLabel(context),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CupertinoTextField.borderless(
                      key: const ValueKey('new-message-recipient-field'),
                      controller: _recipientController,
                      focusNode: _recipientFocus,
                      enabled: !_resolving,
                      placeholder: 'Name or phone number',
                      textInputAction: TextInputAction.done,
                      keyboardType: TextInputType.text,
                      style: MessagesText.body(context).copyWith(fontSize: 16),
                      onChanged: _onRecipientChanged,
                      onSubmitted: (_) => _useTypedRecipient(),
                    ),
                  ),
                  if (_resolving)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: CupertinoActivityIndicator(radius: 9),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (typedRecipient.isNotEmpty &&
                      !matches.any(
                        (item) => _sameAddress(item.address, typedRecipient),
                      ))
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _resolving ? null : _useTypedRecipient,
                      child: Container(
                        height: 58,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: MessagesPalette.hairline(context),
                              width: .5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.arrow_up_circle_fill,
                              color: MessagesPalette.blue,
                              size: 31,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Send to “$typedRecipient”',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MessagesText.body(context).copyWith(
                                  color: MessagesPalette.blue,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final conversation in matches)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _resolving
                          ? null
                          : () => Navigator.of(context).pop(conversation),
                      child: Container(
                        height: 66,
                        padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: MessagesPalette.hairline(context),
                              width: .5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            ContactAvatar(
                              conversation: conversation,
                              size: 44,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    conversation.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MessagesText.headline(context)
                                        .copyWith(fontSize: 16),
                                  ),
                                  if ((conversation.address ?? '').isNotEmpty)
                                    Text(
                                      conversation.address!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: MessagesText.secondary(context)
                                          .copyWith(fontSize: 13),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 15,
                              color: MessagesPalette.secondaryLabel(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final contact in _contactMatches.where(
                    (contact) => !matches.any(
                      (conversation) =>
                          _sameAddress(conversation.address, contact.address),
                    ),
                  ))
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _resolving
                          ? null
                          : () => _useRecipient(contact.address),
                      child: Container(
                        height: 66,
                        padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: MessagesPalette.hairline(context),
                              width: .5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            ContactAvatar(
                              conversation: Conversation(
                                id: 'contact-${contact.address}',
                                address: contact.address,
                                title: contact.name,
                                preview: '',
                                updatedAt: DateTime.now(),
                                avatarColors: const [
                                  Color(0xFF8E8E93),
                                  Color(0xFF636366),
                                ],
                                avatarBytes: contact.avatarBytes,
                                messages: <ChatMessage>[],
                              ),
                              size: 44,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    contact.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MessagesText.headline(context)
                                        .copyWith(fontSize: 16),
                                  ),
                                  Text(
                                    contact.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MessagesText.secondary(context)
                                        .copyWith(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 15,
                              color: MessagesPalette.secondaryLabel(context),
                            ),
                          ],
                        ),
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
    this.selecting = false,
    this.selectedIds = const <String>{},
    required this.onUnpin,
    required this.onLongPress,
  });

  final List<Conversation> conversations;
  final ValueChanged<Conversation> onTap;
  final bool editing;
  final bool selecting;
  final Set<String> selectedIds;
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
              onLongPress: editing || selecting
                  ? null
                  : () => onLongPress(conversation),
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: editing && !selecting
                    ? () {}
                    : () => onTap(conversation),
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
                        if (selecting)
                          Positioned(
                            left: -1,
                            bottom: -1,
                            child: _SelectionCircle(
                              selected: selectedIds.contains(conversation.id),
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
    required this.openConversationId,
    required this.onTap,
    required this.onPin,
    required this.onToggleMute,
    required this.onDelete,
    required this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final Conversation conversation;
  final ValueNotifier<String?> openConversationId;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onToggleMute;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final bool selectionMode;
  final bool selected;

  @override
  State<SwipeableConversationRow> createState() =>
      _SwipeableConversationRowState();
}

class _SwipeableConversationRowState extends State<SwipeableConversationRow>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 78.0;
  static const _rightActionsWidth = _actionWidth * 2;
  static const _longPressMoveTolerance = 8.0;
  late final AnimationController _offsetController =
      AnimationController.unbounded(vsync: this);
  Timer? _longPressTimer;
  int? _trackedPointer;
  Offset? _pointerOrigin;
  Offset? _lastPointerPosition;
  Duration? _lastPointerTime;
  bool? _trackingHorizontalSwipe;
  double _swipeStartOffset = 0;
  double _swipeVelocityX = 0;
  bool _suppressTapAfterLongPress = false;

  @override
  void initState() {
    super.initState();
    widget.openConversationId.addListener(_handleOpenRowChanged);
  }

  @override
  void didUpdateWidget(covariant SwipeableConversationRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openConversationId != widget.openConversationId) {
      oldWidget.openConversationId.removeListener(_handleOpenRowChanged);
      widget.openConversationId.addListener(_handleOpenRowChanged);
    }
    if (widget.selectionMode && !oldWidget.selectionMode) {
      _resetPointerTracking();
      _close();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.selectionMode) return;
    _resetPointerTracking();
    _suppressTapAfterLongPress = false;
    _trackedPointer = event.pointer;
    _pointerOrigin = event.position;
    _lastPointerPosition = event.position;
    _lastPointerTime = event.timeStamp;
    _swipeStartOffset = _offsetController.value;
    _longPressTimer = Timer(kLongPressTimeout, () {
      if (!mounted ||
          widget.selectionMode ||
          _trackedPointer != event.pointer) {
        return;
      }
      _longPressTimer = null;
      _suppressTapAfterLongPress = true;
      widget.onLongPress();
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_trackedPointer != event.pointer) return;
    final origin = _pointerOrigin;
    if (origin == null) return;
    final movement = event.position - origin;
    if (movement.distance > _longPressMoveTolerance) {
      _cancelLongPressTimer();
    }

    if (_trackingHorizontalSwipe == null && movement.distance >= 6) {
      final horizontal = movement.dx.abs();
      final vertical = movement.dy.abs();
      if (horizontal > vertical * 1.08) {
        _trackingHorizontalSwipe = true;
        _cancelLongPressTimer();
        _offsetController.stop();
        if (widget.openConversationId.value != widget.conversation.id) {
          widget.openConversationId.value = widget.conversation.id;
        }
      } else if (vertical > horizontal * 1.08) {
        _trackingHorizontalSwipe = false;
        _cancelLongPressTimer();
      }
    }

    if (_trackingHorizontalSwipe == true) {
      _offsetController.value = (_swipeStartOffset + movement.dx)
          .clamp(-_rightActionsWidth, _actionWidth)
          .toDouble();

      final lastPosition = _lastPointerPosition;
      final lastTime = _lastPointerTime;
      if (lastPosition != null && lastTime != null) {
        final elapsedMicros =
            (event.timeStamp - lastTime).inMicroseconds.clamp(1, 1000000);
        final instantaneousVelocity =
            (event.position.dx - lastPosition.dx) * 1000000 / elapsedMicros;
        _swipeVelocityX =
            (_swipeVelocityX * .35) + (instantaneousVelocity * .65);
      }
    }
    _lastPointerPosition = event.position;
    _lastPointerTime = event.timeStamp;
  }

  void _handlePointerEnd(PointerEvent event) {
    if (_trackedPointer != event.pointer) return;
    final wasHorizontalSwipe = _trackingHorizontalSwipe == true;
    final velocity = _swipeVelocityX;
    _resetPointerTracking();
    if (wasHorizontalSwipe) {
      _settleSwipe(velocity);
      return;
    }
    if (_suppressTapAfterLongPress) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _suppressTapAfterLongPress = false;
      });
    }
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _resetPointerTracking() {
    _cancelLongPressTimer();
    _trackedPointer = null;
    _pointerOrigin = null;
    _lastPointerPosition = null;
    _lastPointerTime = null;
    _trackingHorizontalSwipe = null;
    _swipeStartOffset = 0;
    _swipeVelocityX = 0;
  }

  void _handleOpenRowChanged() {
    if (widget.openConversationId.value != widget.conversation.id &&
        _offsetController.value.abs() > .01) {
      _animateTo(0);
    }
  }

  void _animateTo(double target) {
    _offsetController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _close() {
    if (widget.openConversationId.value == widget.conversation.id) {
      widget.openConversationId.value = null;
    } else if (_offsetController.value.abs() > .01) {
      _animateTo(0);
    }
  }

  void _settleSwipe(double velocity) {
    final offset = _offsetController.value;
    if (offset > 0 &&
        velocity >= -300 &&
        (velocity > 300 || offset > _actionWidth * .32)) {
      widget.openConversationId.value = widget.conversation.id;
      _animateTo(_actionWidth);
    } else if (offset < 0 &&
        velocity <= 300 &&
        (velocity < -300 || offset < -_actionWidth * .28)) {
      widget.openConversationId.value = widget.conversation.id;
      _animateTo(-_rightActionsWidth);
    } else {
      _close();
    }
  }

  void _handleTap() {
    if (_suppressTapAfterLongPress) {
      _suppressTapAfterLongPress = false;
      return;
    }
    if (_offsetController.value.abs() > .01) {
      _close();
    } else {
      widget.onTap();
    }
  }

  void _perform(VoidCallback action) {
    _offsetController.stop();
    _offsetController.value = 0;
    if (widget.openConversationId.value == widget.conversation.id) {
      widget.openConversationId.value = null;
    }
    action();
  }

  @override
  void dispose() {
    _resetPointerTracking();
    widget.openConversationId.removeListener(_handleOpenRowChanged);
    _offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetController,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerEnd,
        onPointerCancel: _handlePointerEnd,
        child: ConversationRow(
          conversation: widget.conversation,
          onTap: _handleTap,
          selectionMode: widget.selectionMode,
          selected: widget.selected,
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
    this.selectionMode = false,
    this.selected = false,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final highlighted = conversation.unreadCount > 0;
    return ColoredBox(
      color: MessagesPalette.background(context),
      child: Stack(
        children: [
          CupertinoButton(
            pressedOpacity: .55,
            padding: EdgeInsets.zero,
            onPressed: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 27),
                    child: _SelectionCircle(selected: selected),
                  )
                else
                  SizedBox(
                    width: 24,
                    // The dot and avatar share the same vertical center.
                    height: 78,
                    child: highlighted
                        ? const Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: MessagesPalette.blue,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox(width: 11, height: 11),
                            ),
                          )
                        : null,
                  ),
                SizedBox(
                  height: 78,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: selectionMode ? 10 : 0,
                      right: selectionMode ? 13 : 15,
                    ),
                    child: Center(
                      child: ContactAvatar(
                        conversation: conversation,
                        size: 44,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 78),
                    padding: const EdgeInsets.fromLTRB(0, 9, 10, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                  fontWeight: FontWeight.w500,
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
                                        color:
                                            MessagesPalette.secondaryLabel(
                                          context,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      conversation.preview,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: MessagesText.secondary(context)
                                          .copyWith(
                                        fontSize: 15,
                                        height: 1.15,
                                        fontWeight: FontWeight.w400,
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
                                _relativeTime(
                                  context,
                                  conversation.updatedAt,
                                ),
                                style:
                                    MessagesText.secondary(context).copyWith(
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
                                color:
                                    MessagesPalette.secondaryLabel(context),
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
          Positioned(
            left: 28,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ColoredBox(
                color: MessagesPalette.hairline(context)
                    .withValues(alpha: .55),
                child: const SizedBox(height: .45),
              ),
            ),
          ),
        ],
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
