import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../l10n/message_status_strings.dart';
import '../models/conversation.dart';
import '../models/notification_open_request.dart';
import '../settings/app_settings.dart';
import '../theme/messages_theme.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/ios3_navigation_chrome.dart';
import '../widgets/liquid_glass_surface.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';

const double _ios3ConversationHeaderHeight = 50;
const double _ios3ConversationHeaderCenterY =
    _ios3ConversationHeaderHeight / 2;
const double _ios3ConversationHeaderButtonHeight = 32;

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversation,
    required this.allConversations,
    required this.messagesPreloaded,
    this.initialMessageId,
    this.notificationOpenRequest,
    required this.messagesChangedRevision,
    required this.onLoad,
    required this.onLoadOlder,
    required this.onSend,
    this.onSendAttachment,
    required this.onRetrySend,
    required this.onCall,
    required this.onOpenContact,
  });

  final Conversation conversation;
  final List<Conversation> allConversations;
  final bool messagesPreloaded;
  final String? initialMessageId;
  final ValueListenable<NotificationOpenRequest?>? notificationOpenRequest;
  final ValueListenable<int> messagesChangedRevision;
  final Future<int> Function() onLoad;
  final Future<int> Function() onLoadOlder;
  final ValueChanged<String> onSend;
  final void Function(MessageAttachment attachment, String caption)?
      onSendAttachment;
  final ValueChanged<ChatMessage> onRetrySend;
  final VoidCallback onCall;
  final VoidCallback onOpenContact;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with TickerProviderStateMixin {
  static const _timestampRevealDistance = 58.0;
  static const _messageInsertionDuration = Duration(milliseconds: 420);
  final _scrollController = ScrollController();
  final _initialMessageKey = GlobalKey();
  GlobalKey<AnimatedListState> _messageListKey = GlobalKey<AnimatedListState>();
  late final AnimationController _timestampRevealController =
      AnimationController.unbounded(vsync: this);
  late final AnimationController _scrollElasticController =
      AnimationController.unbounded(vsync: this);
  final Set<String> _selectedMessageIds = <String>{};
  bool _selectionMode = false;
  bool _loadingMessages = true;
  bool _loadingOlderMessages = false;
  bool _hasOlderMessages = true;
  bool _programmaticScroll = false;
  int _programmaticScrollGeneration = 0;
  double _lastManualScrollDelta = 0;
  Object? _loadError;
  bool _initialMessagePositioned = false;
  int _initialMessagePositionAttempts = 0;
  int _lastNotificationOpenSequence = -1;
  bool _refreshingFromNotification = false;
  bool _refreshingFromProvider = false;
  bool _providerRefreshQueued = false;
  Timer? _providerRefreshDebounce;
  Timer? _sendingStatePoller;
  bool _sendingOutgoingMessage = false;
  bool _showSendingProgress = false;
  late int _lastMessagesChangedRevision;

  @override
  void initState() {
    super.initState();
    if (widget.messagesPreloaded) {
      _loadingMessages = false;
      _hasOlderMessages = widget.conversation.messages.isNotEmpty;
    }
    final request = widget.notificationOpenRequest?.value;
    if (request?.threadId == widget.conversation.id) {
      _lastNotificationOpenSequence = request!.sequence;
    }
    widget.notificationOpenRequest?.addListener(
      _handleNotificationOpenRequest,
    );
    _lastMessagesChangedRevision = widget.messagesChangedRevision.value;
    widget.messagesChangedRevision.addListener(_handleProviderMessagesChanged);
    _sendingOutgoingMessage = _hasPendingOutgoingMessage;
    _showSendingProgress = _sendingOutgoingMessage;
    if (_sendingOutgoingMessage) _startSendingStatePoller();
    unawaited(_loadMessages(showLoading: !widget.messagesPreloaded));
  }

  @override
  void didUpdateWidget(ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationOpenRequest != widget.notificationOpenRequest) {
      oldWidget.notificationOpenRequest?.removeListener(
        _handleNotificationOpenRequest,
      );
      widget.notificationOpenRequest?.addListener(
        _handleNotificationOpenRequest,
      );
    }
    if (oldWidget.messagesChangedRevision != widget.messagesChangedRevision) {
      oldWidget.messagesChangedRevision.removeListener(
        _handleProviderMessagesChanged,
      );
      _lastMessagesChangedRevision = widget.messagesChangedRevision.value;
      widget.messagesChangedRevision.addListener(
        _handleProviderMessagesChanged,
      );
    }
  }

  void _handleProviderMessagesChanged() {
    final revision = widget.messagesChangedRevision.value;
    if (revision == _lastMessagesChangedRevision) return;
    _lastMessagesChangedRevision = revision;
    _providerRefreshDebounce?.cancel();
    _providerRefreshDebounce = Timer(
      const Duration(milliseconds: 100),
      () => unawaited(_refreshFromProvider()),
    );
  }

  Future<void> _refreshFromProvider() async {
    if (_refreshingFromProvider) {
      _providerRefreshQueued = true;
      return;
    }
    _refreshingFromProvider = true;
    try {
      do {
        _providerRefreshQueued = false;
        final wasNearBottom = !_scrollController.hasClients ||
            _scrollController.position.pixels <= 120;
        final previousLastId = widget.conversation.messages.isEmpty
            ? null
            : widget.conversation.messages.last.id;
        await _loadMessages(showLoading: false);
        if (!mounted) return;
        final currentLastId = widget.conversation.messages.isEmpty
            ? null
            : widget.conversation.messages.last.id;
        if (wasNearBottom && currentLastId != previousLastId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToBottom();
          });
        }
      } while (_providerRefreshQueued && mounted);
    } finally {
      _refreshingFromProvider = false;
    }
  }

  void _handleNotificationOpenRequest() {
    final request = widget.notificationOpenRequest?.value;
    if (request == null ||
        request.threadId != widget.conversation.id ||
        request.sequence == _lastNotificationOpenSequence) {
      return;
    }
    _lastNotificationOpenSequence = request.sequence;
    unawaited(_refreshFromNotification());
  }

  Future<void> _refreshFromNotification() async {
    if (_refreshingFromNotification) return;
    _refreshingFromNotification = true;
    try {
      await _loadMessages(showLoading: false);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    } finally {
      _refreshingFromNotification = false;
    }
  }

  Future<void> _loadMessages({bool showLoading = true}) async {
    final previousIds = widget.conversation.messages
        .map((message) => message.id)
        .toList(growable: false);
    if (showLoading && !_loadingMessages) {
      setState(() {
        _loadingMessages = true;
        _loadError = null;
      });
    }
    try {
      final loadedCount = await widget.onLoad();
      if (!mounted) return;
      final currentIds = widget.conversation.messages
          .map((message) => message.id)
          .toList(growable: false);
      final messagesChanged = !_sameIds(previousIds, currentIds);
      final appendedMessageCount = _appendedMessageCount(
        previousIds,
        currentIds,
      );
      final listState = _messageListKey.currentState;
      final animateAppendedMessages = !showLoading &&
          appendedMessageCount > 0 &&
          listState != null;
      final itemCountChanged = previousIds.length != currentIds.length;
      if (!showLoading && !messagesChanged && _loadError == null) {
        _hasOlderMessages = loadedCount > 0;
        return;
      }
      setState(() {
        _loadingMessages = false;
        _hasOlderMessages = loadedCount > 0;
        _loadError = null;
        // A provider refresh can replace a pending message with its persisted
        // version without changing the number of rows. Keeping the list alive
        // avoids flashing every existing bubble. Only rebuild the entire list
        // when its item count changed in a way AnimatedList cannot describe.
        if (showLoading || (itemCountChanged && !animateAppendedMessages)) {
          _messageListKey = GlobalKey<AnimatedListState>();
        }
      });
      if (animateAppendedMessages) {
        listState!.insertAllItems(
          0,
          appendedMessageCount,
          duration: _messageInsertionDuration,
        );
      }
      _scheduleInitialMessagePosition();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
        _loadError = error;
      });
    }
  }

  bool _sameIds(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  int _appendedMessageCount(List<String> previous, List<String> current) {
    if (current.length <= previous.length) return 0;
    for (var index = 0; index < previous.length; index++) {
      if (previous[index] != current[index]) return 0;
    }
    return current.length - previous.length;
  }

  void _scheduleInitialMessagePosition() {
    if (widget.initialMessageId == null || _initialMessagePositioned) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _positionInitialMessage();
    });
  }

  void _positionInitialMessage() {
    if (_initialMessagePositioned) return;
    final targetContext = _initialMessageKey.currentContext;
    if (targetContext != null) {
      _initialMessagePositioned = true;
      Scrollable.ensureVisible(
        targetContext,
        alignment: .5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (!_scrollController.hasClients ||
        _initialMessagePositionAttempts >= 5) {
      return;
    }
    final targetIndex = widget.conversation.messages.indexWhere(
      (message) => message.id == widget.initialMessageId,
    );
    if (targetIndex == -1) return;
    final reversedIndex = widget.conversation.messages.length - 1 - targetIndex;
    final denominator =
        (widget.conversation.messages.length - 1).clamp(1, 1 << 30);
    final ratio = reversedIndex / denominator;
    final position = _scrollController.position;
    position.jumpTo(
      (position.maxScrollExtent * ratio)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
    _initialMessagePositionAttempts++;
    _scheduleInitialMessagePosition();
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMessages ||
        _loadingOlderMessages ||
        !_hasOlderMessages ||
        !_scrollController.hasClients) {
      return;
    }
    final previousMessageCount = widget.conversation.messages.length;
    setState(() => _loadingOlderMessages = true);
    try {
      final addedCount = await widget.onLoadOlder();
      if (!mounted) return;
      final listState = _messageListKey.currentState;
      if (addedCount > 0 && listState != null) {
        listState.insertAllItems(
          previousMessageCount,
          addedCount,
          duration: Duration.zero,
        );
      }
      setState(() {
        _loadingOlderMessages = false;
        // Some Android SMS providers apply their own page cap. Only an empty
        // page proves that the beginning of the thread has been reached.
        _hasOlderMessages = addedCount > 0;
        if (listState == null) {
          _messageListKey = GlobalKey<AnimatedListState>();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  int _beginProgrammaticScroll() {
    final generation = ++_programmaticScrollGeneration;
    _programmaticScroll = true;
    _scrollElasticController
      ..stop()
      ..value = 0;
    return generation;
  }

  void _finishProgrammaticScroll(int generation) {
    if (!mounted || generation != _programmaticScrollGeneration) return;
    _scrollElasticController.value = 0;
    _programmaticScroll = false;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    final generation = _beginProgrammaticScroll();
    unawaited(
      _scrollController
          .animateTo(
            _scrollController.position.minScrollExtent,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _finishProgrammaticScroll(generation)),
    );
  }

  void _send(String text) {
    final previousLength = widget.conversation.messages.length;
    widget.onSend(text);
    _refreshSendingState();
    if (widget.conversation.messages.length <= previousLength) return;
    _messageListKey.currentState?.insertItem(
      0,
      duration: _messageInsertionDuration,
    );
    Timer(const Duration(milliseconds: 40), _scrollToBottom);
    Timer(_messageInsertionDuration, _scrollToBottom);
  }

  void _sendAttachment(MessageAttachment attachment, String caption) {
    widget.onSendAttachment?.call(attachment, caption);
    _refreshSendingState();
  }

  bool get _hasPendingOutgoingMessage => widget.conversation.messages.any(
        (message) =>
            message.isFromMe &&
            message.deliveryState == DeliveryState.sending,
      );

  void _startSendingStatePoller() {
    _sendingStatePoller ??= Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _refreshSendingState(),
    );
  }

  void _refreshSendingState() {
    if (!mounted) return;
    final isSending = _hasPendingOutgoingMessage;
    if (isSending != _sendingOutgoingMessage ||
        (isSending && !_showSendingProgress)) {
      setState(() {
        _sendingOutgoingMessage = isSending;
        if (isSending) _showSendingProgress = true;
      });
    }
    if (isSending) {
      _startSendingStatePoller();
    } else {
      _sendingStatePoller?.cancel();
      _sendingStatePoller = null;
    }
  }

  void _handleSendingProgressCompleted() {
    if (!mounted || _sendingOutgoingMessage || !_showSendingProgress) return;
    setState(() => _showSendingProgress = false);
  }

  Future<void> _retryFailedMessage(ChatMessage message) async {
    if (message.deliveryState != DeliveryState.failed) return;
    final shouldRetry = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(MessageStatusStrings.retryTitle(context)),
        content: Text(MessageStatusStrings.retryPrompt(context)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MessageStatusStrings.cancel(context)),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MessageStatusStrings.retry(context)),
          ),
        ],
      ),
    );
    if (shouldRetry != true || !mounted) return;
    HapticFeedback.lightImpact();
    widget.onRetrySend(message);
    _refreshSendingState();
    if (!mounted) return;
    setState(() => _messageListKey = GlobalKey<AnimatedListState>());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBottom();
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _timestampRevealController.value =
        (_timestampRevealController.value + details.delta.dx)
            .clamp(-_timestampRevealDistance, 0)
            .toDouble();
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final releaseVelocity = (details.primaryVelocity ?? 0)
        .clamp(-700.0, 700.0)
        .toDouble();
    _timestampRevealController.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: .74,
          stiffness: 270,
          ratio: 1,
        ),
        _timestampRevealController.value,
        0,
        releaseVelocity,
      ),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_programmaticScroll && notification.metrics.extentAfter <= 1800) {
      unawaited(_loadOlderMessages());
    }
    if (_programmaticScroll) {
      if (_scrollElasticController.value != 0) {
        _scrollElasticController.value = 0;
      }
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _lastManualScrollDelta = 0;
      _scrollElasticController
        ..stop()
        ..value = 0;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _lastManualScrollDelta = notification.scrollDelta ?? 0;
    } else if (notification is OverscrollNotification) {
      _lastManualScrollDelta = notification.overscroll;
    } else if (notification is ScrollEndNotification) {
      _scrollElasticController.value =
          (-_lastManualScrollDelta * .06).clamp(-1.5, 1.5).toDouble();
      _lastManualScrollDelta = 0;
      _scrollElasticController.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: .45,
            stiffness: 240,
            ratio: .78,
          ),
          _scrollElasticController.value,
          0,
          0,
        ),
      );
    }
    return false;
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    if (_selectionMode) return;
    HapticFeedback.mediumImpact();
    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close message actions',
      barrierColor: CupertinoColors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return _MessageContextOverlay(
          message: message,
          onAction: (value) => Navigator.of(context).pop(value),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.text));
        HapticFeedback.selectionClick();
        break;
      case 'forward':
        await _openForwardPicker(<ChatMessage>[message]);
        break;
      case 'delete':
        await _confirmDelete(<String>{message.id});
        break;
      case 'selectText':
        await _showSelectableText(message);
        break;
      case 'properties':
        await _showProperties(message);
        break;
      case 'select':
        _enterSelection(message);
        break;
    }
  }

  void _enterSelection(ChatMessage message) {
    _timestampRevealController.value = 0;
    setState(() {
      _selectionMode = true;
      _selectedMessageIds
        ..clear()
        ..add(message.id);
    });
  }

  void _enterSelectionMode() {
    _timestampRevealController.value = 0;
    setState(() {
      _selectionMode = true;
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelection(ChatMessage message) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedMessageIds.add(message.id)) {
        _selectedMessageIds.remove(message.id);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  List<ChatMessage> get _selectedMessages => widget.conversation.messages
      .where((message) => _selectedMessageIds.contains(message.id))
      .toList();

  Future<void> _confirmDelete(Set<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(
          messageIds.length == 1 ? 'Delete Message?' : 'Delete Messages?',
        ),
        content: Text(
          messageIds.length == 1
              ? 'This message will be removed.'
              : '${messageIds.length} messages will be removed.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      widget.conversation.messages
          .removeWhere((message) => messageIds.contains(message.id));
      widget.conversation.preview = widget.conversation.messages.isEmpty
          ? 'No Messages'
          : widget.conversation.messages.last.text;
      widget.conversation.updatedAt = DateTime.now();
      _selectionMode = false;
      _selectedMessageIds.clear();
      _messageListKey = GlobalKey<AnimatedListState>();
    });
  }

  Future<void> _showSelectableText(ChatMessage message) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => _SelectableMessageSheet(text: message.text),
    );
  }

  Future<void> _showProperties(ChatMessage message) async {
    final sender = message.isFromMe ? 'You' : widget.conversation.title;
    final directionLabel = message.isFromMe ? 'Sent at' : 'Received at';
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Message Properties'),
        message: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PropertyRow(label: 'Sender', value: sender),
            _PropertyRow(
              label: directionLabel,
              value: _formatFullDateTime(context, message.sentAt),
            ),
            _PropertyRow(
              label: 'Status',
              value: MessageStatusStrings.label(
                context,
                message.deliveryState,
              ),
            ),
          ],
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ),
    );
  }

  Future<void> _openForwardPicker(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final target = await Navigator.of(context).push<Conversation>(
      CupertinoPageRoute<Conversation>(
        builder: (context) => _ForwardPickerScreen(
          conversations: widget.allConversations
              .where((item) => item.id != widget.conversation.id)
              .toList(),
        ),
      ),
    );
    if (target == null || !mounted) return;

    final now = DateTime.now();
    for (var index = 0; index < messages.length; index++) {
      target.messages.add(
        ChatMessage(
          id: 'forward-${now.microsecondsSinceEpoch}-$index',
          text: messages[index].text,
          sentAt: now.add(Duration(milliseconds: index)),
          isFromMe: true,
          deliveryState: DeliveryState.delivered,
        ),
      );
    }
    target.preview = messages.last.text;
    target.updatedAt = now;
    HapticFeedback.lightImpact();
    _cancelSelection();
  }

  @override
  void dispose() {
    _providerRefreshDebounce?.cancel();
    _sendingStatePoller?.cancel();
    widget.messagesChangedRevision.removeListener(
      _handleProviderMessagesChanged,
    );
    widget.notificationOpenRequest?.removeListener(
      _handleNotificationOpenRequest,
    );
    _timestampRevealController.dispose();
    _scrollElasticController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final interfaceStyle = AppSettingsScope.of(context).interfaceStyle;
    final useIos3 = interfaceStyle == InterfaceStyle.ios3;
    final useIos26 = interfaceStyle == InterfaceStyle.ios26;
    final baseTopBarHeight =
        useIos3 ? _ios3ConversationHeaderHeight : 44.0;
    final topCompensation = useIos3
        ? 0.0
        : (baseTopBarHeight - MediaQuery.paddingOf(context).top)
            .clamp(0.0, baseTopBarHeight)
            .toDouble();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: !useIos3 && MessagesPalette.isDark(context)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: CupertinoPageScaffold(
        backgroundColor: useIos3
            ? const Color(0xFFDCE1EC)
            : MessagesPalette.background(context),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => FocusScope.of(context).unfocus(),
                        onHorizontalDragUpdate: _selectionMode
                            ? null
                            : _handleHorizontalDragUpdate,
                        onHorizontalDragEnd:
                            _selectionMode ? null : _handleHorizontalDragEnd,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handleScrollNotification,
                          child: AnimatedList(
                            key: _messageListKey,
                            controller: _scrollController,
                            reverse: true,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              useIos3 ? 14 : 10,
                              _selectionMode
                                  ? (useIos3
                                      ? _ios3ConversationHeaderHeight + 12
                                      : 64)
                                  : (useIos26
                                              ? 106
                                              : useIos3
                                                  ? _ios3ConversationHeaderHeight +
                                                      12
                                                  : 92) +
                                          topCompensation,
                              14,
                              useIos3 ? 12 : 10,
                            ),
                            initialItemCount:
                                widget.conversation.messages.length + 1,
                            itemBuilder: (context, index, animation) {
                              final messageCount =
                                  widget.conversation.messages.length;
                              if (index == messageCount) {
                                return Column(
                                  children: [
                                    if (_loadingOlderMessages)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 10),
                                        child: CupertinoActivityIndicator(),
                                      ),
                                    _DateSeparator(
                                      value: widget
                                              .conversation.messages.isEmpty
                                          ? DateTime.now()
                                          : widget.conversation.messages.first
                                              .sentAt,
                                      message:
                                          widget.conversation.messages.isEmpty
                                              ? null
                                              : widget.conversation.messages
                                                  .first,
                                    ),
                                    if (widget.conversation.id == 'tobias')
                                      const _PhotoStackMessage(),
                                  ],
                                );
                              }

                              final messageIndex = messageCount - 1 - index;
                              if (messageIndex < 0 ||
                                  messageIndex >= messageCount) {
                                return const SizedBox.shrink();
                              }
                              final message = widget
                                  .conversation.messages[messageIndex];
                              final next = messageIndex + 1 <
                                      widget.conversation.messages.length
                                  ? widget.conversation
                                      .messages[messageIndex + 1]
                                  : null;
                              final previous = messageIndex > 0
                                  ? widget.conversation
                                      .messages[messageIndex - 1]
                                  : null;
                              final showTail = next == null ||
                                  next.isFromMe != message.isFromMe ||
                                  next.sentAt
                                          .difference(message.sentAt)
                                          .inMinutes >
                                      3;
                              final compactTop = previous != null &&
                                  previous.isFromMe == message.isFromMe &&
                                  message.sentAt
                                          .difference(previous.sentAt)
                                          .inMinutes <=
                                      3;
                              final showDateSeparator = previous != null &&
                                  !_isSameCalendarDay(
                                    previous.sentAt,
                                    message.sentAt,
                                  );

                              final messageBubble = _TimestampRevealMessage(
                                revealAnimation: _timestampRevealController,
                                sentAt: message.sentAt,
                                child: MessageBubble(
                                  key: ValueKey(message.id),
                                  message: message,
                                  showTail: showTail,
                                  compactTop: compactTop,
                                  showStatus: !_selectionMode &&
                                      messageIndex ==
                                          widget.conversation.messages.length -
                                              1,
                                  onRetry:
                                      message.deliveryState ==
                                          DeliveryState.failed
                                      ? () => _retryFailedMessage(message)
                                      : null,
                                ),
                              );
                              final interactiveMessage = _MessageHoldRegion(
                                enabled: !_selectionMode,
                                onHold: () => _showMessageActions(message),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _selectionMode
                                      ? () => _toggleSelection(message)
                                      : null,
                                  child: messageBubble,
                                ),
                              );

                              final fadeAnimation = CurvedAnimation(
                                parent: animation,
                                curve: const Interval(
                                  0,
                                  .82,
                                  curve: Curves.easeOutCubic,
                                ),
                              );
                              final motionAnimation = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutQuart,
                              );
                              final insertedMessage = FadeTransition(
                                opacity: fadeAnimation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, .035),
                                    end: Offset.zero,
                                  ).animate(motionAnimation),
                                  child: _selectionMode
                                      ? Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Transform.translate(
                                              // MessageBubble paints below its
                                              // own top spacing. Compensate
                                              // so the control is centered on
                                              // the visible bubble.
                                              offset: Offset(
                                                0,
                                                compactTop ? 1 : 4,
                                              ),
                                              child: _SelectionCircle(
                                                selected: _selectedMessageIds
                                                    .contains(message.id),
                                                onPressed: () =>
                                                    _toggleSelection(message),
                                              ),
                                            ),
                                            Expanded(
                                              child: interactiveMessage,
                                            ),
                                          ],
                                        )
                                      : interactiveMessage,
                                ),
                              );
                              final groupedMessage = showDateSeparator
                                  ? Column(
                                      children: [
                                        _DateSeparator(
                                          value: message.sentAt,
                                          precedingMessage: previous,
                                          message: message,
                                        ),
                                        insertedMessage,
                                      ],
                                    )
                                  : insertedMessage;
                              final positionedMessage =
                                  message.id == widget.initialMessageId
                                      ? KeyedSubtree(
                                          key: _initialMessageKey,
                                          child: groupedMessage,
                                        )
                                      : groupedMessage;
                              return RepaintBoundary(
                                child: _ElasticMessageMotion(
                                  animation: _scrollElasticController,
                                  intensity: .78 + (messageIndex % 3) * .1,
                                  child: positionedMessage,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    if (_loadingMessages)
                      Positioned.fill(
                        child: ColoredBox(
                          color: useIos3
                              ? const Color(0xFFDCE1EC)
                              : MessagesPalette.background(context),
                          child: const Center(
                            child: CupertinoActivityIndicator(),
                          ),
                        ),
                      )
                    else if (_loadError != null)
                      Positioned.fill(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Messages could not be loaded.',
                                  textAlign: TextAlign.center,
                                  style: MessagesText.secondary(context),
                                ),
                                const SizedBox(height: 8),
                                CupertinoButton(
                                  onPressed: _loadMessages,
                                  child: const Text('Try Again'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: _selectionMode
                          ? _SelectionHeader(
                              selectionCount: _selectedMessageIds.length,
                              onCancel: _cancelSelection,
                            )
                          : _ConversationHeader(
                              conversation: widget.conversation,
                              isSending: _sendingOutgoingMessage,
                              showSendingProgress: _showSendingProgress,
                              onSendingProgressCompleted:
                                  _handleSendingProgressCompleted,
                              topCompensation: topCompensation,
                              backUnreadCount: widget.allConversations
                                  .where(
                                    (item) =>
                                        item.id != widget.conversation.id,
                                  )
                                  .fold<int>(
                                    0,
                                    (sum, item) => sum + item.unreadCount,
                                  ),
                              onCall: widget.onCall,
                              onOpenContact: widget.onOpenContact,
                              onEdit: _enterSelectionMode,
                            ),
                    ),
                  ],
                ),
              ),
              if (_selectionMode)
                _SelectionToolbar(
                  selectionCount: _selectedMessageIds.length,
                  onDelete: _selectedMessageIds.isEmpty
                      ? null
                      : () => _confirmDelete(<String>{
                            ..._selectedMessageIds,
                          }),
                  onForward: _selectedMessageIds.isEmpty
                      ? null
                      : () => _openForwardPicker(_selectedMessages),
                )
              else ...[
                if (widget.conversation.isMuted)
                  _MutedConversationNotice(
                    contactName: widget.conversation.title,
                  ),
                MessageComposer(
                  onSend: _send,
                  onSendAttachment: _sendAttachment,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ElasticMessageMotion extends StatelessWidget {
  const _ElasticMessageMotion({
    required this.animation,
    required this.intensity,
    required this.child,
  });

  final Animation<double> animation;
  final double intensity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final rawOffset = animation.value * intensity;
        final snappedOffset =
            (rawOffset * devicePixelRatio).roundToDouble() / devicePixelRatio;
        return Transform.translate(
          offset: Offset(0, snappedOffset),
          child: child,
        );
      },
    );
  }
}

class _PhotoStackMessage extends StatelessWidget {
  const _PhotoStackMessage();

  static const _photos = <String>[
    'assets/photos/hike-1.jpg',
    'assets/photos/hike-2.jpg',
    'assets/photos/hike-3.jpg',
    'assets/photos/hike-4.jpg',
    'assets/photos/hike-5.jpg',
  ];
  static const _photoQuarterTurns = <int>[1, 0, 1, 1, 1];

  void _openViewer(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const _FullScreenPhotoViewer(
          photos: _photos,
          quarterTurns: _photoQuarterTurns,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 17, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 11,
                height: 11,
                child: Wrap(
                  spacing: 1,
                  runSpacing: 1,
                  children: List.generate(
                    4,
                    (_) => const DecoratedBox(
                      decoration: BoxDecoration(
                        color: MessagesPalette.blue,
                        borderRadius: BorderRadius.all(Radius.circular(1)),
                      ),
                      child: SizedBox(width: 5, height: 5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '5 photos',
                style: TextStyle(
                  color: MessagesPalette.blue,
                  fontFamily: 'SF Pro Text',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          GestureDetector(
            key: const ValueKey('photo-message-stack'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _openViewer(context),
            child: SizedBox(
              height: 282,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                for (var index = 2; index >= 0; index--)
                  Positioned(
                    left: index * 10.0,
                    top: index * 7.0,
                    child: Transform.rotate(
                      angle: index == 0 ? 0 : index * .018,
                      alignment: Alignment.topLeft,
                      child: _PhotoCard(
                        asset: _photos[index],
                        quarterTurns: _photoQuarterTurns[index],
                        width: 214,
                        height: 282.0 - index * 7.0,
                      ),
                    ),
                  ),
                Positioned(
                  left: 252,
                  top: 125,
                  child: CupertinoButton(
                    minSize: 36,
                    padding: EdgeInsets.zero,
                    onPressed: () => HapticFeedback.selectionClick(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MessagesPalette.background(context),
                        border: Border.all(
                          color: MessagesPalette.hairline(context)
                              .withValues(alpha: .55),
                          width: .6,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.share,
                        size: 18,
                        color: MessagesPalette.blue,
                      ),
                    ),
                  ),
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

class _FullScreenPhotoViewer extends StatefulWidget {
  const _FullScreenPhotoViewer({
    required this.photos,
    required this.quarterTurns,
  });

  final List<String> photos;
  final List<int> quarterTurns;

  @override
  State<_FullScreenPhotoViewer> createState() =>
      _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<_FullScreenPhotoViewer> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      key: const ValueKey('full-screen-photo-viewer'),
      backgroundColor: CupertinoColors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                clipBehavior: Clip.none,
                child: SizedBox.expand(
                  child: RotatedBox(
                    quarterTurns: widget.quarterTurns[index],
                    child: Image.asset(
                      widget.photos[index],
                      key: ValueKey('full-screen-photo-$index'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: CupertinoButton(
                  minSize: 40,
                  padding: EdgeInsets.zero,
                  color: CupertinoColors.systemGrey
                      .withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(20),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    color: CupertinoColors.white,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${_currentIndex + 1} of ${widget.photos.length}',
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontFamily: 'SF Pro Text',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.asset,
    required this.quarterTurns,
    required this.width,
    required this.height,
  });

  final String asset;
  final int quarterTurns;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: width,
        height: height,
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: Image.asset(
            asset,
            width: quarterTurns.isOdd ? height : width,
            height: quarterTurns.isOdd ? width : height,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _MutedConversationNotice extends StatelessWidget {
  const _MutedConversationNotice({required this.contactName});

  final String contactName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.moon_fill,
                size: 13,
                color: MessagesPalette.secondaryLabel(context),
              ),
              const SizedBox(width: 4),
              Text(
                '$contactName has notifications silenced',
                style: TextStyle(
                  color: MessagesPalette.secondaryLabel(context),
                  fontFamily: 'SF Pro Text',
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          CupertinoButton(
            minSize: 18,
            padding: EdgeInsets.zero,
            onPressed: () => HapticFeedback.selectionClick(),
            child: const Text(
              'Notify Anyway',
              style: TextStyle(
                fontFamily: 'SF Pro Text',
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.conversation,
    required this.isSending,
    required this.showSendingProgress,
    required this.onSendingProgressCompleted,
    required this.topCompensation,
    required this.backUnreadCount,
    required this.onCall,
    required this.onOpenContact,
    required this.onEdit,
  });

  final Conversation conversation;
  final bool isSending;
  final bool showSendingProgress;
  final VoidCallback onSendingProgressCompleted;
  final double topCompensation;
  final int backUnreadCount;
  final VoidCallback onCall;
  final VoidCallback onOpenContact;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    if (settings.interfaceStyle == InterfaceStyle.ios3) {
      return _buildIos3(context);
    }
    if (settings.interfaceStyle == InterfaceStyle.ios26) {
      return _buildIos26(context, settings);
    }
    final tint = MessagesPalette.isDark(context)
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF1F1F2);
    final header = Container(
      key: const ValueKey('conversation-header'),
      height: 80 + topCompensation,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: settings.headerTintOpacity),
        border: Border(
          bottom: BorderSide(
            color: MessagesPalette.hairline(context).withValues(alpha: .55),
            width: .5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: .12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: 80,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                left: 7,
                top: 6,
                child: _HeaderButton(
                  key: const ValueKey('conversation-back-button'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: CupertinoIcons.back,
                  iconSize: 30,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                child: Center(
                  child: CupertinoButton(
                    minSize: 0,
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onOpenContact();
                    },
                    child: SizedBox(
                      key: const ValueKey('conversation-contact-avatar'),
                      width: 52,
                      height: 52,
                      child: ContactAvatar(
                        conversation: conversation,
                        size: 52,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 63,
                child: Center(
                  child: CupertinoButton(
                    minSize: 0,
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onOpenContact();
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(
                            conversation.title,
                            key: const ValueKey('conversation-contact-name'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MessagesPalette.label(context),
                              fontFamily: 'SF Pro Text',
                              fontSize: 12,
                              height: 1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Positioned(
                          right: -14,
                          child: Icon(
                            CupertinoIcons.chevron_right,
                            size: 11,
                            color: MessagesPalette.secondaryLabel(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 7,
                top: 6,
                child: _HeaderButton(
                  key: const ValueKey('conversation-call-button'),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onCall();
                  },
                  icon: CupertinoIcons.phone,
                  iconSize: 25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (settings.headerBlurSigma < .1) return header;
    Widget addGlass(Widget child) => ClipRect(
          key: const ValueKey('conversation-header-glass'),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: settings.headerBlurSigma,
              sigmaY: settings.headerBlurSigma,
            ),
            child: RepaintBoundary(child: child),
          ),
        );
    return RepaintBoundary(child: addGlass(header));
  }

  Widget _buildIos3(BuildContext context) {
    final backLabel = backUnreadCount > 0
        ? 'Messages ($backUnreadCount)'
        : 'Messages';
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final screenCenterCorrection =
        (viewPadding.right - viewPadding.left) / 2;
    return Container(
      key: const ValueKey('conversation-header-ios3'),
      height: _ios3ConversationHeaderHeight + topCompensation,
      decoration: ios3TopBarDecoration,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: _ios3ConversationHeaderHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 6,
                top: _ios3ConversationHeaderCenterY -
                    (_ios3ConversationHeaderButtonHeight / 2),
                child: _Ios3NavigationButton(
                  key: const ValueKey('conversation-back-button'),
                  label: backLabel,
                  backShape: true,
                  height: _ios3ConversationHeaderButtonHeight,
                  fontWeight: FontWeight.w600,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(
                      screenCenterCorrection,
                      0,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 130,
                        child: showSendingProgress
                            ? _Ios3SendingProgress(
                                isSending: isSending,
                                onCompleted: onSendingProgressCompleted,
                              )
                            : Text(
                                conversation.title,
                                key: const ValueKey(
                                  'conversation-contact-name',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: ios3TopBarTitleStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: _ios3ConversationHeaderCenterY -
                    (_ios3ConversationHeaderButtonHeight / 2),
                child: _Ios3NavigationButton(
                  label: 'Edit',
                  height: _ios3ConversationHeaderButtonHeight,
                  fontWeight: FontWeight.w600,
                  onPressed: onEdit,
                ),
              ),
              const Ios3TopBarGloss(
                controlCenterY: _ios3ConversationHeaderCenterY,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIos26(
    BuildContext context,
    AppSettingsController settings,
  ) {
    final blur = settings.headerBlurSigma.clamp(0, 20).toDouble();
    final labelColor = MessagesPalette.label(context);
    final secondaryColor = MessagesPalette.secondaryLabel(context);
    final contactNameStyle = TextStyle(
      color: labelColor,
      fontFamily: 'SF Pro Text',
      fontSize: 17,
      height: 1,
      fontWeight: FontWeight.w600,
      letterSpacing: -.25,
    );
    final contactNamePainter = TextPainter(
      text: TextSpan(
        text: conversation.title,
        style: contactNameStyle,
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: 154);
    // The reference capsule is 115 px wide for “Alejandra”. Its width is
    // otherwise driven by the rendered contact name, not by a flex constraint.
    final contactNamePillWidth =
        (contactNamePainter.width + 50).clamp(64.0, 190.0).toDouble();
    return SizedBox(
      key: const ValueKey('conversation-header-ios26'),
      height: 96 + topCompensation,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: 96,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                left: 16,
                top: 8,
                child: LiquidGlassSurface(
                  borderRadius: BorderRadius.circular(22),
                  blurSigma: blur,
                  transparency: settings.headerTransparency,
                  child: SizedBox(
                    width: backUnreadCount > 0 ? 67 : 44,
                    height: 44,
                    child: CupertinoButton(
                      key: const ValueKey('conversation-back-button'),
                      minSize: 44,
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.chevron_left,
                            size: 23,
                            color: labelColor,
                          ),
                          if (backUnreadCount > 0) ...[
                            const SizedBox(width: 5),
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: labelColor.withValues(alpha: .82),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                backUnreadCount > 99
                                    ? '99+'
                                    : '$backUnreadCount',
                                style: TextStyle(
                                  color: MessagesPalette.background(context),
                                  fontFamily: 'SF Pro Text',
                                  fontSize: backUnreadCount > 99 ? 9 : 14,
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 8,
                child: LiquidGlassSurface(
                  borderRadius: BorderRadius.circular(22),
                  blurSigma: blur,
                  transparency: settings.headerTransparency,
                  child: SizedBox.square(
                    dimension: 44,
                    child: CupertinoButton(
                      key: const ValueKey('conversation-call-button'),
                      minSize: 44,
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onCall();
                      },
                      child: Icon(
                        CupertinoIcons.phone,
                        size: 20,
                        color: labelColor,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 57,
                child: CupertinoButton(
                  minSize: 0,
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onOpenContact();
                  },
                  child: LiquidGlassSurface(
                    borderRadius: BorderRadius.circular(16),
                    blurSigma: blur,
                    transparency: settings.headerTransparency,
                    child: SizedBox(
                      width: contactNamePillWidth,
                      height: 32,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Text(
                              conversation.title,
                              key: const ValueKey(
                                'conversation-contact-name',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: contactNameStyle,
                            ),
                          ),
                          Positioned(
                            right: 7,
                            child: Icon(
                              CupertinoIcons.chevron_right,
                              size: 12,
                              color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                child: CupertinoButton(
                  minSize: 0,
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onOpenContact();
                  },
                  child: Container(
                    key: const ValueKey('conversation-contact-avatar'),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CupertinoColors.white.withValues(alpha: .7),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withValues(alpha: .18),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ContactAvatar(
                      conversation: conversation,
                      size: 60,
                    ),
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

class _Ios3SendingProgress extends StatefulWidget {
  const _Ios3SendingProgress({
    required this.isSending,
    required this.onCompleted,
  });

  final bool isSending;
  final VoidCallback onCompleted;

  @override
  State<_Ios3SendingProgress> createState() => _Ios3SendingProgressState();
}

class _Ios3SendingProgressState extends State<_Ios3SendingProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  int _animationGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isSending) {
      _animateWaiting();
    } else {
      _animateCompletion();
    }
  }

  @override
  void didUpdateWidget(_Ios3SendingProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSending == widget.isSending) return;
    if (widget.isSending) {
      _animateWaiting();
    } else {
      _animateCompletion();
    }
  }

  void _animateWaiting() {
    _animationGeneration++;
    if (_controller.value > .82) _controller.value = 0;
    final milliseconds = ((.82 - _controller.value).abs() * 1400)
        .round()
        .clamp(180, 1200)
        .toInt();
    unawaited(
      _controller.animateTo(
        .82,
        duration: Duration(milliseconds: milliseconds),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _animateCompletion() {
    final generation = ++_animationGeneration;
    final milliseconds = ((1 - _controller.value) * 900)
        .round()
        .clamp(650, 900)
        .toInt();
    unawaited(
      _controller
          .animateTo(
            1,
            duration: Duration(milliseconds: milliseconds),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted ||
                generation != _animationGeneration ||
                widget.isSending) {
              return;
            }
            widget.onCompleted();
          }),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 36,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            MessageStatusStrings.label(context, DeliveryState.sending),
            key: const ValueKey('conversation-ios3-sending-label'),
            maxLines: 1,
            style: const TextStyle(
              color: CupertinoColors.white,
              fontFamily: 'SF Pro Text',
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: Color(0xAA26384E),
                  offset: Offset(0, -1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            key: const ValueKey('conversation-ios3-sending-progress'),
            width: 106,
            height: 9,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final progress = .04 + (_controller.value * .96);
                return CustomPaint(
                  painter: _Ios3SendingProgressPainter(progress: progress),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Ios3SendingProgressPainter extends CustomPainter {
  const _Ios3SendingProgressPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF29496E), Color(0xFF5D7DA2)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x99314764),
    );

    final innerRect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    final fillWidth = (innerRect.width * progress)
        .clamp(innerRect.height, innerRect.width)
        .toDouble();
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        innerRect.left,
        innerRect.top,
        fillWidth,
        innerRect.height,
      ),
      Radius.circular(innerRect.height / 2),
    );
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFB9C9D7)],
        ).createShader(fill.outerRect),
    );
    canvas.drawLine(
      Offset(innerRect.left + 2, innerRect.top + 1),
      Offset(innerRect.left + fillWidth - 2, innerRect.top + 1),
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..strokeWidth = .7,
    );
  }

  @override
  bool shouldRepaint(_Ios3SendingProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Ios3NavigationButton extends StatelessWidget {
  const _Ios3NavigationButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backShape = false,
    this.height = ios3TopBarButtonHeight,
    this.fontWeight = FontWeight.w700,
  });

  final String label;
  final VoidCallback onPressed;
  final bool backShape;
  final double height;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final labelStyle = ios3TopBarButtonTextStyle.copyWith(
      fontWeight: fontWeight,
    );
    final labelPainter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = backShape
        ? (labelPainter.width + 26).clamp(88.0, 116.0).toDouble()
        : (labelPainter.width + 32).clamp(60.0, 96.0).toDouble();
    return CupertinoButton(
      minSize: height,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: CustomPaint(
        painter: _Ios3NavigationButtonPainter(backShape: backShape),
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: EdgeInsets.only(left: backShape ? 8 : 0),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ios3NavigationButtonPainter extends CustomPainter {
  const _Ios3NavigationButtonPainter({required this.backShape});

  final bool backShape;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (backShape) {
      path
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
    } else {
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(4),
        ),
      );
    }
    final rect = Offset.zero & size;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ios3TopBarButtonGradient.createShader(rect),
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
  bool shouldRepaint(_Ios3NavigationButtonPainter oldDelegate) =>
      oldDelegate.backShape != backShape;
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.iconSize,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: CupertinoButton(
        minSize: 48,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(
          icon,
          size: iconSize,
          color: MessagesPalette.blue,
        ),
      ),
    );
  }
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    required this.selectionCount,
    required this.onCancel,
  });

  final int selectionCount;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (AppSettingsScope.of(context).interfaceStyle == InterfaceStyle.ios3) {
      return Container(
        height: _ios3ConversationHeaderHeight,
        decoration: ios3TopBarDecoration,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$selectionCount Selected',
              style: ios3TopBarTitleStyle,
            ),
            Positioned(
              right: 6,
              top: _ios3ConversationHeaderCenterY -
                  (_ios3ConversationHeaderButtonHeight / 2),
              child: _Ios3NavigationButton(
                label: 'Done',
                height: _ios3ConversationHeaderButtonHeight,
                onPressed: onCancel,
              ),
            ),
            const Ios3TopBarGloss(
              controlCenterY: _ios3ConversationHeaderCenterY,
            ),
          ],
        ),
      );
    }
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: MessagesPalette.elevatedBackground(context),
        border: Border(
          bottom: BorderSide(
            color: MessagesPalette.hairline(context).withValues(alpha: .5),
            width: .4,
          ),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '$selectionCount Selected',
            style: MessagesText.headline(context),
          ),
          Positioned(
            right: 6,
            child: CupertinoButton(
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimestampRevealMessage extends StatelessWidget {
  const _TimestampRevealMessage({
    required this.revealAnimation,
    required this.sentAt,
    required this.child,
  });

  final Animation<double> revealAnimation;
  final DateTime sentAt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: revealAnimation,
      child: child,
      builder: (context, child) {
        final reveal = (-revealAnimation.value /
                _ConversationScreenState._timestampRevealDistance)
            .clamp(0.0, 1.0)
            .toDouble();
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final snappedOffset =
            (revealAnimation.value * devicePixelRatio).roundToDouble() /
                devicePixelRatio;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: reveal,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Text(
                        _formatTime(context, sentAt),
                        style: TextStyle(
                          color: MessagesPalette.secondaryLabel(context),
                          fontFamily: 'SF Pro Text',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(snappedOffset, 0),
              child: child,
            ),
          ],
        );
      },
    );
  }
}

class _MessageHoldRegion extends StatefulWidget {
  const _MessageHoldRegion({
    required this.enabled,
    required this.onHold,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onHold;
  final Widget child;

  @override
  State<_MessageHoldRegion> createState() => _MessageHoldRegionState();
}

class _MessageHoldRegionState extends State<_MessageHoldRegion> {
  Timer? _holdTimer;
  Offset? _downPosition;

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _downPosition = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _cancelHold();
    _downPosition = event.position;
    _holdTimer = Timer(const Duration(milliseconds: 700), widget.onHold);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _downPosition;
    if (start != null && (event.position - start).distance > 12) {
      _cancelHold();
    }
  }

  @override
  void didUpdateWidget(_MessageHoldRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _cancelHold();
  }

  @override
  void dispose() {
    _cancelHold();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _cancelHold(),
      onPointerCancel: (_) => _cancelHold(),
      child: widget.child,
    );
  }
}

class _MessageContextOverlay extends StatelessWidget {
  const _MessageContextOverlay({
    required this.message,
    required this.onAction,
  });

  final ChatMessage message;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    const actions = <_MessageAction>[
      _MessageAction('copy', CupertinoIcons.doc_on_doc, 'Copy'),
      _MessageAction('forward', CupertinoIcons.share, 'Forward'),
      _MessageAction('delete', CupertinoIcons.delete_solid, 'Delete'),
      _MessageAction('selectText', CupertinoIcons.text_cursor, 'Select Text'),
      _MessageAction('properties', CupertinoIcons.info_circle, 'Properties'),
      _MessageAction('select', CupertinoIcons.checkmark_circle, 'Select'),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: ColoredBox(
                color: CupertinoColors.black.withValues(alpha: .12),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutBack,
                    tween: Tween<double>(begin: .92, end: 1.08),
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: child,
                    ),
                    child: MessageBubble(
                      message: message,
                      showTail: true,
                      compactTop: false,
                      shadowElevation: 18,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: message.isFromMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 238,
                      decoration: BoxDecoration(
                        color: MessagesPalette.elevatedBackground(context)
                            .withValues(alpha: .94),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color:
                                CupertinoColors.black.withValues(alpha: .16),
                            blurRadius: 22,
                            offset: const Offset(0, 9),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var index = 0;
                              index < actions.length;
                              index++) ...[
                            if (index > 0)
                              Container(
                                height: .5,
                                margin: const EdgeInsets.only(left: 14),
                                color: MessagesPalette.hairline(context),
                              ),
                            _MessageActionButton(
                              action: actions[index],
                              onPressed: () => onAction(actions[index].id),
                            ),
                          ],
                        ],
                      ),
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

class _MessageAction {
  const _MessageAction(this.id, this.icon, this.label);

  final String id;
  final IconData icon;
  final String label;
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    required this.action,
    required this.onPressed,
  });

  final _MessageAction action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDestructive = action.id == 'delete';
    final foreground = isDestructive
        ? CupertinoColors.systemRed.resolveFrom(context)
        : MessagesPalette.label(context);

    return CupertinoButton(
      minSize: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      onPressed: onPressed,
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            Expanded(
              child: Text(
                action.label,
                maxLines: 1,
                style: TextStyle(
                  color: foreground,
                  fontFamily: 'SF Pro Text',
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Icon(
              action.icon,
              size: 20,
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({
    required this.selected,
    required this.onPressed,
  });

  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: CupertinoButton(
        minSize: 36,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(
          selected
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.circle,
          size: 23,
          color: selected
              ? MessagesPalette.blue
              : MessagesPalette.secondaryLabel(context),
        ),
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectionCount,
    required this.onDelete,
    required this.onForward,
  });

  final int selectionCount;
  final VoidCallback? onDelete;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: MessagesPalette.elevatedBackground(context),
          border: Border(
            top: BorderSide(
              color: MessagesPalette.hairline(context).withValues(alpha: .5),
              width: .4,
            ),
          ),
        ),
        child: Row(
          children: [
            CupertinoButton(
              onPressed: onDelete,
              child: const Icon(CupertinoIcons.delete, size: 24),
            ),
            Expanded(
              child: Text(
                '$selectionCount selected',
                textAlign: TextAlign.center,
                style: MessagesText.secondary(context),
              ),
            ),
            CupertinoButton(
              onPressed: onForward,
              child: const Icon(CupertinoIcons.share, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForwardPickerScreen extends StatelessWidget {
  const _ForwardPickerScreen({required this.conversations});

  final List<Conversation> conversations;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: MessagesPalette.background(context),
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Forward To'),
      ),
      child: SafeArea(
        child: conversations.isEmpty
            ? Center(
                child: Text(
                  'No Other Conversations',
                  style: MessagesText.secondary(context),
                ),
              )
            : ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (context, index) => Container(
                  height: .5,
                  margin: const EdgeInsets.only(left: 76),
                  color: MessagesPalette.hairline(context),
                ),
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return CupertinoButton(
                    padding: const EdgeInsets.fromLTRB(16, 9, 14, 9),
                    onPressed: () => Navigator.of(context).pop(conversation),
                    child: Row(
                      children: [
                        ContactAvatar(conversation: conversation, size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                conversation.title,
                                style: MessagesText.headline(context),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                conversation.preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MessagesText.secondary(context),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 16,
                          color: MessagesPalette.secondaryLabel(context),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _SelectableMessageSheet extends StatefulWidget {
  const _SelectableMessageSheet({required this.text});

  final String text;

  @override
  State<_SelectableMessageSheet> createState() =>
      _SelectableMessageSheetState();
}

class _SelectableMessageSheetState extends State<_SelectableMessageSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPopupSurface(
      child: SafeArea(
        top: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 220),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          color: MessagesPalette.elevatedBackground(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select Text',
                textAlign: TextAlign.center,
                style: MessagesText.headline(context),
              ),
              const SizedBox(height: 22),
              CupertinoTextField(
                controller: _controller,
                readOnly: true,
                maxLines: null,
                padding: EdgeInsets.zero,
                decoration: null,
                style: MessagesText.body(context),
              ),
              const SizedBox(height: 22),
              CupertinoButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({
    required this.value,
    this.precedingMessage,
    this.message,
  });

  final DateTime value;
  final ChatMessage? precedingMessage;
  final ChatMessage? message;

  @override
  Widget build(BuildContext context) {
    final label = _dateSeparatorParts(context, value);
    final interfaceStyle = AppSettingsScope.of(context).interfaceStyle;
    final useIos3 = interfaceStyle == InterfaceStyle.ios3;
    final useIos26 = interfaceStyle == InterfaceStyle.ios26;
    final needsIos17Clearance = interfaceStyle == InterfaceStyle.ios17 &&
        _ios17DateNeedsClearance(context, precedingMessage);
    return Padding(
      padding: EdgeInsets.only(
        top: useIos26 ? 12 : (useIos3 ? 8 : (needsIos17Clearance ? 10 : 0)),
        bottom: useIos26 ? 2 : (useIos3 ? 6 : 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (useIos3 && message?.isFromMe == false) ...[
            _Ios3TextMessageDivider(
              label: MessageStatusStrings.textMessage(context),
            ),
            const SizedBox(height: 6),
          ],
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label.$1,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: '  ${label.$2}',
                  style: const TextStyle(fontWeight: FontWeight.w400),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: useIos3
                  ? const Color(0xFF868FA0)
                  : MessagesPalette.secondaryLabel(context),
              fontFamily: 'SF Pro Text',
              fontSize: useIos3 ? 12 : 11,
              height: 1,
              shadows: useIos3
                  ? const [
                      Shadow(
                        color: Color(0xCCFFFFFF),
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ios3TextMessageDivider extends StatelessWidget {
  const _Ios3TextMessageDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF9EA7B7);
    return Row(
      children: [
        const Expanded(
          child: CustomPaint(
            painter: _Ios3DottedLinePainter(color: color),
            size: Size.fromHeight(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: color,
            fontFamily: 'SF Pro Text',
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(
                color: Color(0xCCFFFFFF),
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: CustomPaint(
            painter: _Ios3DottedLinePainter(color: color),
            size: Size.fromHeight(2),
          ),
        ),
      ],
    );
  }
}

class _Ios3DottedLinePainter extends CustomPainter {
  const _Ios3DottedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final highlightPaint = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const dashWidth = 1.4;
    const dashGap = 1.8;
    const y = .5;
    for (double x = 0; x < size.width; x += dashWidth + dashGap) {
      final end = (x + dashWidth).clamp(0, size.width).toDouble();
      canvas.drawLine(
        Offset(x, y + 1),
        Offset(end, y + 1),
        highlightPaint,
      );
      canvas.drawLine(
        Offset(x, y),
        Offset(end, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Ios3DottedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

bool _ios17DateNeedsClearance(
  BuildContext context,
  ChatMessage? message,
) {
  if (message == null) return false;
  if (message.attachment != null) return true;

  final text = message.text.trim();
  if (text.isEmpty) return false;

  final textScale = emojiOnlyTextScale(text);
  final renderedTextScale = textScale == 2 ? 4.0 : textScale;
  final screenWidth = MediaQuery.sizeOf(context).width;
  final maxTextWidth = screenWidth * (274 / 375) - 24;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: MessagesText.body(context).copyWith(
        fontSize: 16 * renderedTextScale,
        height: renderedTextScale > 1 ? 1 : 1.18,
        letterSpacing: renderedTextScale > 1 ? 0 : -.15,
      ),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textWidthBasis: TextWidthBasis.longestLine,
  )..layout(maxWidth: maxTextWidth);

  final lineCount = painter.computeLineMetrics().length;
  final bubbleWidth = painter.width + 24;
  final crossesScreenCenter = bubbleWidth >= (screenWidth / 2) - 10;
  return lineCount >= 3 || crossesScreenCenter;
}

String _formatTime(BuildContext context, DateTime value) {
  return AppSettingsScope.of(context).formatTime(
    value,
    platformUses24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

bool _isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

(String, String) _dateSeparatorParts(BuildContext context, DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(value.year, value.month, value.day);
  final difference = today.difference(messageDay).inDays;
  final prefix = switch (difference) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => AppSettingsScope.of(context).formatDate(
        value,
        localeCode: Localizations.localeOf(context).languageCode,
      ),
  };
  return (prefix, _formatTime(context, value));
}

String _formatFullDateTime(BuildContext context, DateTime value) {
  final date = AppSettingsScope.of(context).formatDate(
    value,
    localeCode: Localizations.localeOf(context).languageCode,
  );
  return '$date at ${_formatTime(context, value)}';
}
