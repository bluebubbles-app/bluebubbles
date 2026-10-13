import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme/messages_theme.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSend,
  });

  final ValueChanged<String> onSend;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: MessagesPalette.background(context).withValues(alpha: .96),
          border: Border(
            top: BorderSide(
              color: MessagesPalette.hairline(context).withValues(alpha: .55),
              width: .4,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CupertinoButton(
              minSize: 34,
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              onPressed: () => HapticFeedback.selectionClick(),
              child: Container(
                width: 31,
                height: 31,
                decoration: const BoxDecoration(
                  color: MessagesPalette.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.plus,
                  size: 21,
                  color: CupertinoColors.white,
                ),
              ),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 36, maxHeight: 122),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: MessagesPalette.hairline(context),
                    width: .7,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: CupertinoTextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        placeholder: 'Message',
                        placeholderStyle: MessagesText.body(context).copyWith(
                          color: MessagesPalette.secondaryLabel(context),
                        ),
                        style: MessagesText.body(context),
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        decoration: null,
                        padding: const EdgeInsets.fromLTRB(11, 7, 6, 7),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 3),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: _hasText
                            ? CupertinoButton(
                                key: const ValueKey('send'),
                                minSize: 28,
                                padding: EdgeInsets.zero,
                                onPressed: _send,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: const BoxDecoration(
                                    color: MessagesPalette.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.arrow_up,
                                    size: 19,
                                    color: CupertinoColors.white,
                                  ),
                                ),
                              )
                            : Icon(
                                key: const ValueKey('mic'),
                                CupertinoIcons.mic,
                                size: 23,
                                color: MessagesPalette.secondaryLabel(context),
                              ),
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
}
