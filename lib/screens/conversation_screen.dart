import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../settings/app_settings.dart';
import '../theme/messages_theme.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversation,
    required this.allConversations,
    required this.onLoad,
    required this.onLoadOlder,
    required this.onSend,
    required this.onCall,
  });

  final Conversation conversation;
  final List<Conversation> allConversations;
  final Future<int> Function() onLoad;
  final Future<int> Function() onLoadOlder;
  final ValueChanged<String> onSend;
  final VoidCallback onCall;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with TickerProviderStateMixin {
  static const _timestampRevealDistance = 58.0;
  final _scrollController = ScrollController();
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
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    unawaited(_loadMessages());
  }

  Future<void> _loadMessages() async {
    if (!_loadingMessages) {
      setState(() {
        _loadingMessages = true;
        _loadError = null;
      });
    }
    try {
      final loadedCount = await widget.onLoad();
      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
        _hasOlderMessages = loadedCount >= 40;
        _loadError = null;
        _messageListKey = GlobalKey<AnimatedListState>();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMessages = false;
        _loadError = error;
      });
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMessages ||
        _loadingOlderMessages ||
        !_hasOlderMessages ||
        !_scrollController.hasClients) {
      return;
    }
    final oldOffset = _scrollController.offset;
    final oldMaxExtent = _scrollController.position.maxScrollExtent;
    setState(() => _loadingOlderMessages = true);
    try {
      final addedCount = await widget.onLoadOlder();
      if (!mounted) return;
      setState(() {
        _loadingOlderMessages = false;
        _hasOlderMessages = addedCount >= 40;
        _messageListKey = GlobalKey<AnimatedListState>();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final addedExtent =
            _scrollController.position.maxScrollExtent - oldMaxExtent;
        final target = (oldOffset + addedExtent).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
        _jumpWithoutBubbleMotion(target.toDouble());
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _jumpWithoutBubbleMotion(_scrollController.position.maxScrollExtent);
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

  void _jumpWithoutBubbleMotion(double offset) {
    if (!_scrollController.hasClients) return;
    final generation = _beginProgrammaticScroll();
    _scrollController.jumpTo(offset);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _finishProgrammaticScroll(generation),
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    final generation = _beginProgrammaticScroll();
    unawaited(
      _scrollController
          .animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _finishProgrammaticScroll(generation)),
    );
  }

  void _send(String text) {
    final insertionIndex = widget.conversation.messages.length + 1;
    widget.onSend(text);
    _messageListKey.currentState?.insertItem(
      insertionIndex,
      duration: const Duration(milliseconds: 280),
    );
    Timer(const Duration(milliseconds: 40), _scrollToBottom);
    Timer(const Duration(milliseconds: 300), _scrollToBottom);
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
    if (!_programmaticScroll && notification.metrics.pixels <= 180) {
      unawaited(_loadOlderMessages());
    }
    if (_programmaticScroll) {
      if (_scrollElasticController.value != 0) {
        _scrollElasticController.value = 0;
      }
      return false;
    }
    if (notification is ScrollStartNotification) {
      _scrollElasticController.stop();
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      _scrollElasticController.value =
          (-delta * .16).clamp(-4.0, 4.0).toDouble();
    } else if (notification is OverscrollNotification) {
      _scrollElasticController.value =
          (-notification.overscroll * .2).clamp(-5.0, 5.0).toDouble();
    } else if (notification is ScrollEndNotification) {
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
              value: _deliveryStateLabel(message.deliveryState),
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
    _timestampRevealController.dispose();
    _scrollElasticController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topCompensation =
        (44.0 - MediaQuery.paddingOf(context).top)
            .clamp(0.0, 44.0)
            .toDouble();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: MessagesPalette.isDark(context)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: CupertinoPageScaffold(
        backgroundColor: MessagesPalette.background(context),
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
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              10,
                              _selectionMode
                                  ? 64
                                  : 92 + topCompensation,
                              14,
                              10,
                            ),
                      initialItemCount:
                          widget.conversation.messages.length + 1,
                      itemBuilder: (context, index, animation) {
                        if (index == 0) {
                          return Column(
                            children: [
                              if (_loadingOlderMessages)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: CupertinoActivityIndicator(),
                                ),
                              _DateSeparator(
                                value: widget.conversation.messages.isEmpty
                                    ? DateTime.now()
                                    : widget
                                        .conversation.messages.first.sentAt,
                              ),
                              if (widget.conversation.id == 'tobias')
                                const _PhotoStackMessage(),
                            ],
                          );
                        }

                        final messageIndex = index - 1;
                        final message =
                            widget.conversation.messages[messageIndex];
                        final next = messageIndex + 1 <
                                widget.conversation.messages.length
                            ? widget.conversation.messages[messageIndex + 1]
                            : null;
                        final previous = messageIndex > 0
                            ? widget.conversation.messages[messageIndex - 1]
                            : null;
                        final showTail = next == null ||
                            next.isFromMe != message.isFromMe ||
                            next.sentAt.difference(message.sentAt).inMinutes >
                                3;
                        final compactTop = previous != null &&
                            previous.isFromMe == message.isFromMe &&
                            message.sentAt
                                    .difference(previous.sentAt)
                                    .inMinutes <=
                                3;

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
                                    widget.conversation.messages.length - 1,
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

                        final curvedAnimation = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        );
                        final insertedMessage = FadeTransition(
                          opacity: curvedAnimation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(.10, .10),
                              end: Offset.zero,
                            ).animate(curvedAnimation),
                            child: _selectionMode
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Transform.translate(
                                        // MessageBubble paints below its own
                                        // top spacing. Compensate for half
                                        // that spacing so the control is
                                        // centered on the visible bubble.
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
                                      Expanded(child: interactiveMessage),
                                    ],
                                  )
                                : interactiveMessage,
                          ),
                        );
                        return _ElasticMessageMotion(
                          animation: _scrollElasticController,
                          intensity: .78 + (messageIndex % 3) * .1,
                          child: insertedMessage,
                        );
                      },
                          ),
                        ),
                      ),
                    ),
                    if (_loadingMessages)
                      const Positioned.fill(
                        child: Center(child: CupertinoActivityIndicator()),
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
                              topCompensation: topCompensation,
                              onCall: widget.onCall,
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
                MessageComposer(onSend: _send),
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
    required this.topCompensation,
    required this.onCall,
  });

  final Conversation conversation;
  final double topCompensation;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
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
                    onPressed: () => HapticFeedback.selectionClick(),
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
                    onPressed: () => HapticFeedback.selectionClick(),
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
    return ClipRect(
      key: const ValueKey('conversation-header-glass'),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: settings.headerBlurSigma,
          sigmaY: settings.headerBlurSigma,
        ),
        child: header,
      ),
    );
  }
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
  const _DateSeparator({required this.value});

  final DateTime value;

  @override
  Widget build(BuildContext context) {
    final label = _dateSeparatorParts(context, value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
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
          color: MessagesPalette.secondaryLabel(context),
          fontFamily: 'SF Pro Text',
          fontSize: 11,
          height: 1,
        ),
      ),
    );
  }
}

String _formatTime(BuildContext context, DateTime value) {
  return AppSettingsScope.of(context).formatTime(
    value,
    platformUses24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

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

String _deliveryStateLabel(DeliveryState state) {
  return switch (state) {
    DeliveryState.sending => 'Sending',
    DeliveryState.delivered => 'Delivered',
    DeliveryState.read => 'Read',
    DeliveryState.failed => 'Not Delivered',
  };
}
