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
    widget.onSend(text);
    setState(() {});
    Timer(const Duration(milliseconds: 40), _scrollToBottom);
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
                  child: ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(9, 18, 9, 10),
                    itemCount: widget.conversation.messages.length + 1,
                    itemBuilder: (context, index) {
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

                      return MessageBubble(
                        message: message,
                        showTail: showTail,
                        compactTop: compactTop,
                        showStatus: messageIndex ==
                            widget.conversation.messages.length - 1,
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ContactAvatar(conversation: conversation, size: 30),
          const SizedBox(height: 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 145),
                child: Text(
                  conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MessagesPalette.label(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 9,
                color: MessagesPalette.secondaryLabel(context),
              ),
            ],
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
