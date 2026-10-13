import 'dart:async';

import 'package:flutter/cupertino.dart';
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

class _ConversationScreenState extends State<ConversationScreen> {
  final _scrollController = ScrollController();
  final _messageListKey = GlobalKey<AnimatedListState>();

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

  @override
  void dispose() {
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
        navigationBar: CupertinoNavigationBar(
          backgroundColor:
              MessagesPalette.elevatedBackground(context).withValues(alpha: .88),
          border: Border(
            bottom: BorderSide(
              color: MessagesPalette.hairline(context).withValues(alpha: .5),
              width: .4,
            ),
          ),
          transitionBetweenRoutes: true,
          middle: _ContactHeader(conversation: widget.conversation),
          trailing: CupertinoButton(
            minSize: 34,
            padding: EdgeInsets.zero,
            onPressed: () => HapticFeedback.selectionClick(),
            child: const Icon(CupertinoIcons.video_camera, size: 27),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: AnimatedList(
                    key: _messageListKey,
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(9, 18, 9, 10),
                    initialItemCount: widget.conversation.messages.length + 1,
                    itemBuilder: (context, index, animation) {
                      if (index == 0) return const _DateSeparator();

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
                          child: MessageBubble(
                            key: ValueKey(message.id),
                            message: message,
                            showTail: showTail,
                            compactTop: compactTop,
                            showStatus: messageIndex ==
                                widget.conversation.messages.length - 1,
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

class _ContactHeader extends StatelessWidget {
  const _ContactHeader({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minSize: 42,
      padding: EdgeInsets.zero,
      onPressed: () => HapticFeedback.selectionClick(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          ContactAvatar(conversation: conversation, size: 28),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 145),
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
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        'Today  6:42 PM',
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
