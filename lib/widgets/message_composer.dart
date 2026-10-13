import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../services/message_sounds.dart';
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
    unawaited(MessageSounds.playSent());
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
        padding: const EdgeInsets.fromLTRB(12, 6, 15, 5),
        color: MessagesPalette.background(context).withValues(alpha: .97),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CupertinoButton(
                minSize: 36,
                padding: EdgeInsets.zero,
                onPressed: () => HapticFeedback.selectionClick(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: MessagesPalette.isDark(context)
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE9E9EA),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.plus,
                    size: 21,
                    color: MessagesPalette.secondaryLabel(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
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
                        placeholderStyle: const TextStyle(
                          fontFamily: 'SF Pro Text',
                          color: Color(0xFFC7C7CC),
                          fontSize: 17,
                          height: 1.2,
                        ),
                        style: MessagesText.body(context),
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        decoration: null,
                        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 3),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: CupertinoButton(
                          key: ValueKey(_hasText),
                          minSize: 30,
                          padding: EdgeInsets.zero,
                          onPressed: _hasText
                              ? _send
                              : () => HapticFeedback.selectionClick(),
                          child: Icon(
                            _hasText
                                ? CupertinoIcons.arrow_up_circle_fill
                                : CupertinoIcons.mic,
                            size: _hasText ? 30 : 19,
                            color: _hasText
                                ? MessagesPalette.blue
                                : MessagesPalette.secondaryLabel(context),
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
      ),
    );
  }
}
