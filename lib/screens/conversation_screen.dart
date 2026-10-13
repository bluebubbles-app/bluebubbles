import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../theme/messages_theme.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversation,
    required this.onSend,
  });

  final Conversation conversation;
  final ValueChanged<String> onSend;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with SingleTickerProviderStateMixin {
  static const _timestampRevealDistance = 82.0;
  final _scrollController = ScrollController();
  final _messageListKey = GlobalKey<AnimatedListState>();
  late final AnimationController _timestampRevealController =
      AnimationController.unbounded(vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
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
        .clamp(-850.0, 850.0)
        .toDouble();
    _timestampRevealController.animateWith(
      SpringSimulation(
        const SpringDescription(
          mass: .72,
          stiffness: 235,
          damping: 15,
        ),
        _timestampRevealController.value,
        0,
        releaseVelocity,
      ),
    );
  }

  @override
  void dispose() {
    _timestampRevealController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: MessagesPalette.isDark(context)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: CupertinoPageScaffold(
        backgroundColor: MessagesPalette.background(context),
        child: SafeArea(
          child: Column(
            children: [
              _ConversationHeader(conversation: widget.conversation),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                  onHorizontalDragEnd: _handleHorizontalDragEnd,
                  child: AnimatedList(
                    key: _messageListKey,
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(9, 18, 9, 10),
                    initialItemCount: widget.conversation.messages.length + 1,
                    itemBuilder: (context, index, animation) {
                      if (index == 0) {
                        return _DateSeparator(
                          value: widget.conversation.messages.isEmpty
                              ? DateTime.now()
                              : widget.conversation.messages.first.sentAt,
                        );
                      }

                      final messageIndex = index - 1;
                      final message = widget.conversation.messages[messageIndex];
                      final next = messageIndex + 1 <
                              widget.conversation.messages.length
                          ? widget.conversation.messages[messageIndex + 1]
                          : null;
                      final previous = messageIndex > 0
                          ? widget.conversation.messages[messageIndex - 1]
                          : null;
                      final showTail = next == null ||
                          next.isFromMe != message.isFromMe ||
                          next.sentAt.difference(message.sentAt).inMinutes > 3;
                      final compactTop = previous != null &&
                          previous.isFromMe == message.isFromMe &&
                          message.sentAt.difference(previous.sentAt).inMinutes <= 3;

                      final curvedAnimation = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      );
                      return FadeTransition(
                        opacity: curvedAnimation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(.10, .10),
                            end: Offset.zero,
                          ).animate(curvedAnimation),
                          child: _TimestampRevealMessage(
                            revealAnimation: _timestampRevealController,
                            messageIndex: messageIndex,
                            sentAt: message.sentAt,
                            child: MessageBubble(
                              key: ValueKey(message.id),
                              message: message,
                              showTail: showTail,
                              compactTop: compactTop,
                              showStatus: messageIndex ==
                                  widget.conversation.messages.length - 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              MessageComposer(onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: MessagesPalette.elevatedBackground(context)
            .withValues(alpha: .96),
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
          Positioned(
            left: 2,
            child: CupertinoButton(
              minSize: 44,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(CupertinoIcons.back, size: 29),
            ),
          ),
          CupertinoButton(
            minSize: 68,
            padding: EdgeInsets.zero,
            onPressed: () => HapticFeedback.selectionClick(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ContactAvatar(conversation: conversation, size: 34),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 155),
                      child: Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MessagesPalette.label(context),
                          fontFamily: 'SF Pro Text',
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 12,
                      color: MessagesPalette.secondaryLabel(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 6,
            child: CupertinoButton(
              minSize: 44,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => HapticFeedback.selectionClick(),
              child: const Icon(CupertinoIcons.video_camera, size: 27),
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
    required this.messageIndex,
    required this.sentAt,
    required this.child,
  });

  final Animation<double> revealAnimation;
  final int messageIndex;
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
        final parallax = .96 + (messageIndex % 3) * .018;
        final wobble = math.sin((reveal * math.pi * 2) + messageIndex) *
            reveal *
            .65;
        final rotation =
            math.sin((reveal * math.pi) + messageIndex) * reveal * .0018;

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
                        _formatTime(sentAt),
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
              offset: Offset(revealAnimation.value * parallax, wobble),
              child: Transform.rotate(angle: rotation, child: child),
            ),
          ],
        );
      },
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.value});

  final DateTime value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        _formatDateSeparator(value),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: MessagesPalette.secondaryLabel(context),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

String _formatDateSeparator(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(value.year, value.month, value.day);
  final difference = today.difference(messageDay).inDays;
  final prefix = switch (difference) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => '${value.month}/${value.day}/${value.year}',
  };
  return '$prefix  ${_formatTime(value)}';
}
