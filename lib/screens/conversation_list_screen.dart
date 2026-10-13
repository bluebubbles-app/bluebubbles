import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../theme/messages_theme.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/ios_search_field.dart';
import 'conversation_screen.dart';

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({
    super.key,
    required this.conversations,
    required this.onSend,
  });

  final List<Conversation> conversations;
  final void Function(Conversation conversation, String text) onSend;

  @override
  State<ConversationListScreen> createState() =>
      _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  List<Conversation> get _filtered {
    final conversations = [...widget.conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_query.trim().isEmpty) return conversations;
    final query = _query.toLowerCase().trim();
    return conversations
        .where(
          (conversation) =>
              conversation.title.toLowerCase().contains(query) ||
              conversation.preview.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _openConversation(Conversation conversation) async {
    setState(() => conversation.unreadCount = 0);
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ConversationScreen(
          conversation: conversation,
          onSend: (text) {
            widget.onSend(conversation, text);
            setState(() {});
          },
        ),
      ),
    );
    setState(() {});
  }

  void _pinConversation(Conversation conversation) {
    HapticFeedback.mediumImpact();
    setState(() => conversation.isPinned = true);
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
      setState(() => widget.conversations.remove(conversation));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinned =
        _filtered.where((conversation) => conversation.isPinned).toList();
    final regular =
        _filtered.where((conversation) => !conversation.isPinned).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: MessagesPalette.isDark(context)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: CupertinoPageScaffold(
        backgroundColor: MessagesPalette.background(context),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 7, 16, 9),
                  child: IosSearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),
              if (pinned.isNotEmpty)
                SliverToBoxAdapter(
                  child: _PinnedGrid(
                    conversations: pinned,
                    onTap: _openConversation,
                  ),
                ),
              if (_filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No Conversations',
                      style: MessagesText.secondary(context),
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
                    ),
                    childCount: regular.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 13, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text('Messages', style: MessagesText.largeTitle(context)),
          ),
          CupertinoButton(
            minSize: 36,
            padding: EdgeInsets.zero,
            onPressed: () => HapticFeedback.selectionClick(),
            child: const Icon(CupertinoIcons.ellipsis_circle, size: 25),
          ),
          const SizedBox(width: 10),
          CupertinoButton(
            minSize: 36,
            padding: EdgeInsets.zero,
            onPressed: () => HapticFeedback.selectionClick(),
            child: const Icon(CupertinoIcons.square_pencil, size: 25),
          ),
        ],
      ),
    );
  }
}

class _PinnedGrid extends StatelessWidget {
  const _PinnedGrid({required this.conversations, required this.onTap});

  final List<Conversation> conversations;
  final ValueChanged<Conversation> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      child: Wrap(
        alignment: WrapAlignment.start,
        runSpacing: 16,
        children: conversations.map((conversation) {
          return SizedBox(
            width: MediaQuery.sizeOf(context).width / 3 - 6,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => onTap(conversation),
              child: Column(
                children: [
                  ContactAvatar(
                    conversation: conversation,
                    size: 76,
                    showUnreadBadge: true,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MessagesText.secondary(context).copyWith(
                      color: MessagesPalette.label(context),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
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
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onToggleMute;
  final VoidCallback onDelete;

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
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
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
                    color: Color(0xFFFF9F0A),
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
            ),
          ),
          AnimatedBuilder(
            animation: _offsetController,
            builder: (context, child) => Transform.translate(
              offset: Offset(_offsetController.value, 0),
              child: child,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              child: ConversationRow(
                conversation: widget.conversation,
                onTap: widget.onTap,
              ),
            ),
          ),
        ],
      ),
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
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: ContactAvatar(conversation: conversation, size: 50),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 70),
                padding: const EdgeInsets.fromLTRB(0, 10, 10, 9),
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
                              fontWeight: highlighted
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
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
                            _relativeTime(conversation.updatedAt),
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

  String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 60) return '${difference.inMinutes} min';
    if (difference.inHours < 24) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    if (difference.inDays == 1) return 'Yesterday';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
  }
}
