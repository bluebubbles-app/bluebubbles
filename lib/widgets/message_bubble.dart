import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:characters/characters.dart';
import 'package:flutter/cupertino.dart';

import '../l10n/message_status_strings.dart';
import '../models/conversation.dart';
import '../settings/app_settings.dart';
import '../theme/messages_theme.dart';

double emojiOnlyTextScale(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return 1;

  final emojiCount = compact.characters.length;
  if (!compact.characters.every(_isEmojiCluster)) return 1;
  if (emojiCount == 1) return 2;
  if (emojiCount <= 5) return 1.5;
  return 1;
}

bool _isEmojiCluster(String cluster) {
  final runes = cluster.runes.toList(growable: false);
  final isKeycap = runes.contains(0x20E3);
  var hasEmojiBase = false;

  for (final rune in runes) {
    if (_isEmojiBase(rune) ||
        (isKeycap &&
            (rune == 0x23 ||
                rune == 0x2A ||
                (rune >= 0x30 && rune <= 0x39)))) {
      hasEmojiBase = true;
      continue;
    }
    if (rune == 0x200D ||
        rune == 0x20E3 ||
        rune == 0xFE0E ||
        rune == 0xFE0F ||
        (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
        (rune >= 0xE0020 && rune <= 0xE007F)) {
      continue;
    }
    return false;
  }
  return hasEmojiBase;
}

bool _isEmojiBase(int rune) =>
    rune == 0x00A9 ||
    rune == 0x00AE ||
    rune == 0x203C ||
    rune == 0x2049 ||
    rune == 0x2122 ||
    rune == 0x3030 ||
    rune == 0x303D ||
    rune == 0x3297 ||
    rune == 0x3299 ||
    (rune >= 0x2300 && rune <= 0x23FF) ||
    (rune >= 0x2600 && rune <= 0x27BF) ||
    (rune >= 0x2B00 && rune <= 0x2BFF) ||
    (rune >= 0x1F000 && rune <= 0x1FAFF);

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.showTail,
    required this.compactTop,
    this.showStatus = false,
    this.shadowElevation = 0,
    this.onRetry,
  });

  final ChatMessage message;
  final bool showTail;
  final bool compactTop;
  final bool showStatus;
  final double shadowElevation;
  final VoidCallback? onRetry;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final _paintKey = GlobalKey();
  ScrollPosition? _scrollPosition;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollPosition = Scrollable.maybeOf(context)?.position;
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isFromMe = message.isFromMe;
    final isImageAttachment =
        message.attachment?.kind == MessageAttachmentKind.image;
    final useGreenBubble = isFromMe &&
        AppSettingsScope.maybeOf(context)?.sentBubbleColor ==
            SentBubbleColor.green;
    final emojiScale = emojiOnlyTextScale(message.text);
    final renderedTextScale = emojiScale == 2 ? 4.0 : emojiScale;
    final Color color;
    if (isImageAttachment) {
      color = CupertinoColors.transparent;
    } else if (isFromMe) {
      color = useGreenBubble
          ? MessagesPalette.customBubbleGreen
          : MessagesPalette.sentBubble(context);
    } else {
      color = MessagesPalette.receivedBubble(context);
    }
    final foregroundColor = isImageAttachment
        ? MessagesPalette.label(context)
        : isFromMe
            ? CupertinoColors.white
            : MessagesPalette.label(context);

    return Semantics(
      label: isFromMe ? 'Sent message' : 'Received message',
      child: Padding(
        padding: EdgeInsets.only(top: widget.compactTop ? 2 : 8),
        child: Column(
          crossAxisAlignment:
              isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Align(
              alignment:
                  isFromMe ? Alignment.centerRight : Alignment.centerLeft,
              child: CustomPaint(
                key: _paintKey,
                painter: MessageBubblePainter(
                  color: color,
                  gradient: isFromMe && !useGreenBubble && !isImageAttachment
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF00B7FF),
                            MessagesPalette.blue,
                          ],
                        )
                      : null,
                  scrollPosition: _scrollPosition,
                  paintKey: _paintKey,
                  screenHeight: MediaQuery.sizeOf(context).height,
                  isFromMe: isFromMe,
                  showTail: widget.showTail,
                  shadowElevation: widget.shadowElevation,
                ),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: 36,
                    // 274 pt on the 375 pt-wide SVG artboard.
                    maxWidth: MediaQuery.sizeOf(context).width * (274 / 375),
                  ),
                  padding: isImageAttachment
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                  child: Align(
                    alignment: Alignment.center,
                    widthFactor: 1,
                    heightFactor: 1,
                    child: _MessageBubbleContent(
                      message: message,
                      renderedTextScale: renderedTextScale,
                      foregroundColor: foregroundColor,
                    ),
                  ),
                ),
              ),
            ),
            if ((widget.showStatus ||
                    message.deliveryState == DeliveryState.failed) &&
                isFromMe)
              Padding(
                // Keep the delivery label visually clear of the outgoing
                // bubble tail instead of aligning it with the tail's tip.
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: message.deliveryState == DeliveryState.failed &&
                        widget.onRetry != null
                    ? CupertinoButton(
                        minSize: 20,
                        padding: EdgeInsets.zero,
                        onPressed: widget.onRetry,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              CupertinoIcons.exclamationmark_circle_fill,
                              size: 13,
                              color: CupertinoColors.systemRed,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              MessageStatusStrings.label(
                                context,
                                message.deliveryState,
                              ),
                              style: const TextStyle(
                                color: CupertinoColors.systemRed,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        MessageStatusStrings.label(
                          context,
                          message.deliveryState,
                        ),
                        style: TextStyle(
                          color: MessagesPalette.secondaryLabel(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

}

class _MessageBubbleContent extends StatelessWidget {
  const _MessageBubbleContent({
    required this.message,
    required this.renderedTextScale,
    required this.foregroundColor,
  });

  final ChatMessage message;
  final double renderedTextScale;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attachment?.kind == MessageAttachmentKind.image)
          _ImageAttachment(attachment: attachment!),
        if (attachment?.kind == MessageAttachmentKind.audio)
          _AudioAttachment(
            attachment: attachment!,
            foregroundColor: foregroundColor,
          ),
        if (message.text.isNotEmpty) ...[
          if (attachment != null) const SizedBox(height: 6),
          Text(
            message.text,
            textAlign: TextAlign.left,
            textWidthBasis: TextWidthBasis.longestLine,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: MessagesText.body(context).copyWith(
              fontSize: 16 * renderedTextScale,
              height: renderedTextScale > 1 ? 1 : 1.18,
              letterSpacing: renderedTextScale > 1 ? 0 : -.15,
              color: foregroundColor,
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final bytes = attachment.thumbnailBytes;
    final path = attachment.localPath;
    final image = bytes != null
        ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
        : path != null && File(path).existsSync()
            ? Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true)
            : const Center(
                child: Icon(
                  CupertinoIcons.photo,
                  size: 42,
                  color: CupertinoColors.systemGrey,
                ),
              );
    return GestureDetector(
      onTap: () => showCupertinoDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => CupertinoPageScaffold(
          backgroundColor: CupertinoColors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(child: image),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(dialogContext).top + 8,
                right: 12,
                child: CupertinoButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: CupertinoColors.white,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 220, height: 170, child: image),
      ),
    );
  }
}

class _AudioAttachment extends StatefulWidget {
  const _AudioAttachment({
    required this.attachment,
    required this.foregroundColor,
  });

  final MessageAttachment attachment;
  final Color foregroundColor;

  @override
  State<_AudioAttachment> createState() => _AudioAttachmentState();
}

class _AudioAttachmentState extends State<_AudioAttachment> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  Future<void> _toggle() async {
    final path = widget.attachment.localPath;
    if (path == null || !File(path).existsSync()) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(path));
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final milliseconds = widget.attachment.durationMilliseconds ?? 0;
    final duration = Duration(milliseconds: milliseconds);
    return SizedBox(
      width: 220,
      height: 34,
      child: Row(
        children: [
          CupertinoButton(
            minSize: 32,
            padding: EdgeInsets.zero,
            onPressed: _toggle,
            child: Icon(
              _playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              size: 20,
              color: widget.foregroundColor,
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var index = 0; index < 22; index++)
                  Container(
                    width: 2,
                    height: const [6.0, 13.0, 20.0, 10.0, 17.0, 8.0]
                        [index % 6],
                    decoration: BoxDecoration(
                      color: widget.foregroundColor.withValues(alpha: .78),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}',
            style: TextStyle(
              color: widget.foregroundColor.withValues(alpha: .8),
              fontFamily: 'SF Pro Text',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the tail outside the bubble's layout bounds so adding a new message
/// never changes the position of text in an existing bubble.
class MessageBubblePainter extends CustomPainter {
  MessageBubblePainter({
    required this.color,
    required this.gradient,
    required this.scrollPosition,
    required this.paintKey,
    required this.screenHeight,
    required this.isFromMe,
    required this.showTail,
    required this.shadowElevation,
  }) : super(repaint: gradient == null ? null : scrollPosition);

  final Color color;
  final LinearGradient? gradient;
  final ScrollPosition? scrollPosition;
  final GlobalKey paintKey;
  final double screenHeight;
  final bool isFromMe;
  final bool showTail;
  final double shadowElevation;
  Size? _cachedPathSize;
  Path? _cachedBubblePath;
  double? _referenceScreenTop;
  double? _referenceScrollOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (gradient != null && screenHeight > 0) {
      if (_referenceScreenTop == null) {
        final renderObject =
            paintKey.currentContext?.findRenderObject() as RenderBox?;
        _referenceScreenTop =
            renderObject?.localToGlobal(Offset.zero).dy ?? 0;
        _referenceScrollOffset = scrollPosition?.pixels ?? 0;
      }
      final currentScrollOffset = scrollPosition?.pixels ?? 0;
      final scrollDirection = scrollPosition?.axisDirection == AxisDirection.up
          ? 1.0
          : -1.0;
      final screenTop = _referenceScreenTop! +
          (currentScrollOffset - _referenceScrollOffset!) * scrollDirection;
      paint.shader = gradient!.createShader(
        Rect.fromLTWH(0, -screenTop, size.width, screenHeight),
      );
    }
    late Path bubble;
    if (_cachedPathSize == size && _cachedBubblePath != null) {
      bubble = _cachedBubblePath!;
    } else {
      final body = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            const Radius.circular(20),
          ),
        );
      bubble = body;

      if (showTail) {
        final tail = Path();
        if (isFromMe) {
          tail
          ..moveTo(size.width - 1, size.height - 6.5)
          ..cubicTo(
            size.width - .5,
            size.height - 3.49,
            size.width + 2.33,
            size.height - .67,
            size.width + 4,
            size.height,
          )
          ..cubicTo(
            size.width - 2.4,
            size.height,
            size.width - 6.5,
            size.height - 2.17,
            size.width - 7.5,
            size.height - 3.5,
          )
          ..lineTo(size.width - 12.5, size.height - 2)
          ..lineTo(size.width - 12, size.height - 17)
          ..lineTo(size.width - 1.5, size.height - 17)
          ..lineTo(size.width - 1.5, size.height - 12.5)
          ..cubicTo(
            size.width - 1.5,
            size.height - 11.5,
            size.width - 1.5,
            size.height - 9.5,
            size.width - 1,
            size.height - 6.5,
          );
        } else {
          tail
          ..moveTo(1, size.height - 6.5)
          ..cubicTo(
            .5,
            size.height - 3.49,
            -2.33,
            size.height - .67,
            -4,
            size.height,
          )
          ..cubicTo(
            2.4,
            size.height,
            6.5,
            size.height - 2.17,
            7.5,
            size.height - 3.5,
          )
          ..lineTo(12.5, size.height - 2)
          ..lineTo(12, size.height - 17)
          ..lineTo(1.5, size.height - 17)
          ..lineTo(1.5, size.height - 12.5)
          ..cubicTo(
            1.5,
            size.height - 11.5,
            1.5,
            size.height - 9.5,
            1,
            size.height - 6.5,
          );
        }
        tail.close();
        // Joining two subpaths can cancel their overlapping winding area and
        // leave a white notch between the body and tail. A geometric union
        // guarantees a single solid silhouette on every Android renderer.
        bubble = Path.combine(PathOperation.union, body, tail);
      }
      _cachedPathSize = size;
      _cachedBubblePath = bubble;
    }

    if (shadowElevation > 0) {
      canvas.drawShadow(
        bubble,
        CupertinoColors.black.withValues(alpha: .38),
        shadowElevation,
        true,
      );
    }
    canvas.drawPath(bubble, paint);
  }

  @override
  bool shouldRepaint(MessageBubblePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.gradient != gradient ||
      oldDelegate.scrollPosition != scrollPosition ||
      oldDelegate.paintKey != paintKey ||
      oldDelegate.screenHeight != screenHeight ||
      oldDelegate.isFromMe != isFromMe ||
      oldDelegate.showTail != showTail ||
      oldDelegate.shadowElevation != shadowElevation;
}
