import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:characters/characters.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

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
    final settings = AppSettingsScope.maybeOf(context);
    final useIos3 = settings?.interfaceStyle == InterfaceStyle.ios3;
    final useIos26 = settings?.interfaceStyle == InterfaceStyle.ios26;
    final isImageAttachment =
        message.attachment?.kind == MessageAttachmentKind.image;
    final useGreenBubble = isFromMe &&
        settings?.sentBubbleColor == SentBubbleColor.green;
    final showIos3FailureIcon = useIos3 &&
        isFromMe &&
        message.deliveryState == DeliveryState.failed &&
        widget.onRetry != null;
    final emojiScale = emojiOnlyTextScale(message.text);
    final renderedTextScale = emojiScale == 2 ? 4.0 : emojiScale;
    final Color color;
    if (isImageAttachment && !useIos3) {
      color = CupertinoColors.transparent;
    } else if (useIos3 && isImageAttachment) {
      color = isFromMe
          ? (useGreenBubble
              ? const Color(0xFF75BF42)
              : const Color(0xFF83CAFF))
          : const Color(0xFFD7D7D7);
    } else if (isFromMe) {
      color = useGreenBubble
          ? MessagesPalette.customBubbleGreen
          : MessagesPalette.sentBubble(context);
    } else {
      color = MessagesPalette.receivedBubble(context);
    }
    final foregroundColor = isImageAttachment && !useIos3
        ? MessagesPalette.label(context)
        : useIos3
            ? CupertinoColors.black
            : isFromMe
                ? CupertinoColors.white
                : MessagesPalette.label(context);
    final classicGradient = useIos3
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isFromMe
                ? (useGreenBubble
                    ? const [
                        Color(0xFF20B45C),
                        Color(0xFF52B847),
                        Color(0xFF75BF42),
                        Color(0xFF78C043),
                        Color(0xFF98D3FF),
                      ]
                    : const [Color(0xFF6EBEFF), Color(0xFF98D3FF)])
                : const [Color(0xFFECECEC), Color(0xFFC8C8C8)],
            stops: isFromMe && useGreenBubble
                ? const [0, .2, .5, .875, 1]
                : null,
          )
        : null;

    return Semantics(
      label: isFromMe ? 'Sent message' : 'Received message',
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.compactTop
              ? (useIos26 ? 4 : (useIos3 ? 3 : 2))
              : (useIos26 ? 10 : 8),
        ),
        child: Column(
          crossAxisAlignment:
              isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Align(
              alignment:
                  isFromMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  right: showIos3FailureIcon ? 35 : 0,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      key: _paintKey,
                      painter: MessageBubblePainter(
                        color: color,
                        gradient: classicGradient ??
                            (isFromMe &&
                                    !useGreenBubble &&
                                    !isImageAttachment
                                ? LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: useIos26
                                        ? const [
                                            Color(0xFF4EBAFF),
                                            Color(0xFF0088FF),
                                          ]
                                        : const [
                                            Color(0xFF00B7FF),
                                            MessagesPalette.blue,
                                          ],
                                  )
                                : null),
                        fixedGradient: useIos3 || useIos26,
                        useIos3Shape: useIos3,
                        useIos3Green: useIos3 && isFromMe && useGreenBubble,
                        ios3Media: useIos3 && isImageAttachment,
                        useIos26Shape: useIos26,
                        scrollPosition: _scrollPosition,
                        paintKey: _paintKey,
                        screenHeight: MediaQuery.sizeOf(context).height,
                        isFromMe: isFromMe,
                        showTail: widget.showTail,
                        shadowElevation:
                            useIos3 && widget.shadowElevation < 2
                                ? 2
                                : widget.shadowElevation,
                      ),
                      child: Container(
                        constraints: BoxConstraints(
                          minHeight: useIos26 ? 40 : 36,
                          maxWidth: MediaQuery.sizeOf(context).width *
                              (useIos26
                                  ? (280 / 402)
                                  : (useIos3 ? .84 : (274 / 375))),
                        ),
                        padding: isImageAttachment && !useIos3
                            ? EdgeInsets.zero
                            : isImageAttachment && useIos3
                                ? EdgeInsets.zero
                                : EdgeInsets.symmetric(
                                    horizontal: useIos26
                                        ? 13
                                        : (useIos3 ? 13 : 12),
                                    vertical:
                                        useIos26 ? 9 : (useIos3 ? 5 : 7),
                                  ),
                        child: Align(
                          alignment: Alignment.center,
                          widthFactor: 1,
                          heightFactor: 1,
                          child: _MessageBubbleContent(
                            message: message,
                            renderedTextScale: renderedTextScale,
                            foregroundColor: foregroundColor,
                            useIos3: useIos3,
                          ),
                        ),
                      ),
                    ),
                    if (showIos3FailureIcon)
                      Positioned(
                        right: -35,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: CupertinoButton(
                            minSize: 21,
                            padding: EdgeInsets.zero,
                            onPressed: widget.onRetry,
                            child: const _Ios3FailureIcon(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if ((widget.showStatus ||
                    message.deliveryState == DeliveryState.failed) &&
                isFromMe)
              Padding(
                // Keep the delivery label visually clear of the outgoing
                // bubble tail instead of aligning it with the tail's tip.
                padding: EdgeInsets.only(
                  top: useIos26 ? 8 : 4,
                  right: useIos26 ? 14 : 8,
                ),
                child: message.deliveryState == DeliveryState.failed &&
                        widget.onRetry != null
                    ? CupertinoButton(
                        minSize: 20,
                        padding: EdgeInsets.zero,
                        onPressed: widget.onRetry,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!useIos3) ...[
                              const Icon(
                                CupertinoIcons.exclamationmark_circle_fill,
                                size: 13,
                                color: CupertinoColors.systemRed,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              MessageStatusStrings.label(
                                context,
                                message.deliveryState,
                              ),
                              style: TextStyle(
                                color: useIos3
                                    ? const Color(0xFFA70F24)
                                    : CupertinoColors.systemRed,
                                fontSize: 11,
                                fontWeight: useIos3
                                    ? FontWeight.w700
                                    : FontWeight.w400,
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
                      )
                    : Text(
                        MessageStatusStrings.label(
                          context,
                          message.deliveryState,
                        ),
                        style: TextStyle(
                          color: useIos3
                              ? const Color(0xFF7E8798)
                              : MessagesPalette.secondaryLabel(context),
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

class _Ios3FailureIcon extends StatelessWidget {
  const _Ios3FailureIcon();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 21,
        child: CustomPaint(painter: _Ios3FailureIconPainter()),
      );
}

class _Ios3FailureIconPainter extends CustomPainter {
  const _Ios3FailureIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 21;
    canvas.save();
    canvas.scale(scale, scale);
    const center = Offset(10.3, 9.3);

    canvas.drawCircle(
      center,
      8.5,
      Paint()
        ..color = const Color(0xFF707070)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .65),
    );
    canvas.drawCircle(
      center.translate(0, 1),
      8.5,
      Paint()..color = const Color(0x40000000),
    );
    canvas.drawCircle(center, 8.5, Paint()..color = CupertinoColors.white);
    canvas.drawCircle(center, 7.5, Paint()..color = const Color(0xFFDE5463));

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: 7.5)));
    final lowerShade = Path()
      ..moveTo(3.3, 10.93)
      ..quadraticBezierTo(10.3, 5.8, 17.3, 10.93)
      ..lineTo(17.8, 17.2)
      ..lineTo(2.8, 17.2)
      ..close();
    canvas.drawPath(
      lowerShade,
      Paint()..color = const Color(0x80C02125),
    );
    canvas.restore();

    final symbolShadow = Paint()
      ..color = const Color(0x40000000)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final symbol = Paint()
      ..color = CupertinoColors.white
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(10.3, 4.6),
      const Offset(10.3, 10.8),
      symbolShadow,
    );
    canvas.drawLine(
      const Offset(10.3, 4.1),
      const Offset(10.3, 10.3),
      symbol,
    );
    canvas.drawCircle(const Offset(10.3, 13.55), 1, symbolShadow);
    canvas.drawCircle(const Offset(10.3, 13.05), 1, symbol);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Ios3FailureIconPainter oldDelegate) => false;
}

class _MessageBubbleContent extends StatelessWidget {
  const _MessageBubbleContent({
    required this.message,
    required this.renderedTextScale,
    required this.foregroundColor,
    required this.useIos3,
  });

  final ChatMessage message;
  final double renderedTextScale;
  final Color foregroundColor;
  final bool useIos3;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attachment?.kind == MessageAttachmentKind.image)
          _ImageAttachment(
            attachment: attachment!,
            useIos3: useIos3,
          ),
        if (attachment?.kind == MessageAttachmentKind.audio)
          _AudioAttachment(
            attachment: attachment!,
            foregroundColor: foregroundColor,
          ),
        if (message.text.isNotEmpty) ...[
          if (attachment != null) const SizedBox(height: 6),
          Padding(
            padding: useIos3 &&
                    attachment?.kind == MessageAttachmentKind.image
                ? const EdgeInsets.fromLTRB(10, 0, 10, 8)
                : EdgeInsets.zero,
            child: Text(
              message.text,
              textAlign: TextAlign.left,
              textWidthBasis: TextWidthBasis.longestLine,
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              style: MessagesText.body(context).copyWith(
                fontSize: (useIos3 ? 17 : 16) * renderedTextScale,
                height:
                    renderedTextScale > 1 ? 1 : (useIos3 ? 1.12 : 1.18),
                letterSpacing: renderedTextScale > 1 ? 0 : -.15,
                color: foregroundColor,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({
    required this.attachment,
    required this.useIos3,
  });

  final MessageAttachment attachment;
  final bool useIos3;

  @override
  Widget build(BuildContext context) {
    final bytes = attachment.thumbnailBytes;
    final path = attachment.localPath;
    final image = bytes != null
        ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
        : path != null
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    CupertinoIcons.photo,
                    size: 42,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              )
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
        borderRadius: BorderRadius.circular(useIos3 ? 19.5 : 12),
        child: SizedBox(
          width: 220,
          height: 170,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              if (useIos3)
                Positioned(
                  left: 4,
                  right: 4,
                  top: 0,
                  height: 6,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xCCFFFFFF), Color(0x00F3FFF2)],
                        ),
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
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completionSubscription;
  bool _playing = false;
  bool _sourceReady = false;
  bool _scrubbing = false;
  Duration _position = Duration.zero;
  late Duration _duration = Duration(
    milliseconds: widget.attachment.durationMilliseconds ?? 0,
  );

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _positionSubscription = player.onPositionChanged.listen((position) {
      if (mounted && !_scrubbing) setState(() => _position = position);
    });
    _durationSubscription = player.onDurationChanged.listen((duration) {
      if (mounted && duration > Duration.zero) {
        setState(() => _duration = duration);
      }
    });
    _stateSubscription = player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
    _completionSubscription = player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
    return _player = player;
  }

  Future<AudioPlayer?> _ensureSource() async {
    final path = widget.attachment.localPath;
    if (path == null || path.isEmpty) return null;
    final player = _ensurePlayer();
    if (!_sourceReady) {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(DeviceFileSource(path));
      _sourceReady = true;
    }
    return player;
  }

  Future<void> _toggle() async {
    try {
      final player = await _ensureSource();
      if (player == null) return;
      if (_playing) {
        await player.pause();
      } else {
        if (_duration > Duration.zero && _position >= _duration) {
          await player.seek(Duration.zero);
        }
        await player.resume();
      }
    } on Exception {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _seek(double milliseconds) async {
    try {
      final player = await _ensureSource();
      if (player == null) return;
      final position = Duration(milliseconds: milliseconds.round());
      await player.seek(position);
      if (mounted) setState(() => _position = position);
    } on Exception {
      // Leave the existing position visible if Android rejects the seek.
    }
  }

  void _scrubTo(double localX, double width) {
    if (_duration <= Duration.zero || width <= 0) return;
    final fraction = (localX / width).clamp(0.0, 1.0);
    setState(() {
      _scrubbing = true;
      _position = Duration(
        milliseconds: (_duration.inMilliseconds * fraction).round(),
      );
    });
  }

  Future<void> _finishScrubbing() async {
    if (!_scrubbing) return;
    final milliseconds = _position.inMilliseconds.toDouble();
    setState(() => _scrubbing = false);
    await _seek(milliseconds);
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_stateSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMilliseconds = _duration.inMilliseconds;
    final maximum = totalMilliseconds > 0 ? totalMilliseconds.toDouble() : 1.0;
    final value = _position.inMilliseconds
        .toDouble()
        .clamp(0.0, maximum)
        .toDouble();
    return SizedBox(
      width: 220,
      height: 42,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final progress = totalMilliseconds <= 0
                    ? 0.0
                    : (value / maximum).clamp(0.0, 1.0);
                return RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: <Type, GestureRecognizerFactory>{
                    EagerGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            EagerGestureRecognizer>(
                      EagerGestureRecognizer.new,
                      (_) {},
                    ),
                  },
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: totalMilliseconds <= 0
                        ? null
                        : (event) => _scrubTo(event.localPosition.dx, width),
                    onPointerMove: totalMilliseconds <= 0
                        ? null
                        : (event) => _scrubTo(event.localPosition.dx, width),
                    onPointerUp: totalMilliseconds <= 0
                        ? null
                        : (_) => unawaited(_finishScrubbing()),
                    onPointerCancel: totalMilliseconds <= 0
                        ? null
                        : (_) => unawaited(_finishScrubbing()),
                    child: Semantics(
                      label: 'Audio position',
                      value:
                          '${_position.inSeconds} of ${_duration.inSeconds} seconds',
                      child: SizedBox(
                        height: 32,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: widget.foregroundColor
                                    .withValues(alpha: .25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: widget.foregroundColor
                                      .withValues(alpha: .9),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Positioned(
                              left: progress * (width - 12),
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: widget.foregroundColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${_position.inMinutes}:${_position.inSeconds.remainder(60).toString().padLeft(2, '0')}',
            style: TextStyle(
              color: widget.foregroundColor.withValues(alpha: .8),
              fontFamily: 'SF Pro Text',
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
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
    required this.fixedGradient,
    required this.useIos3Shape,
    required this.useIos3Green,
    required this.ios3Media,
    required this.useIos26Shape,
    required this.scrollPosition,
    required this.paintKey,
    required this.screenHeight,
    required this.isFromMe,
    required this.showTail,
    required this.shadowElevation,
  }) : super(
          repaint: gradient == null || fixedGradient ? null : scrollPosition,
        );

  final Color color;
  final LinearGradient? gradient;
  final bool fixedGradient;
  final bool useIos3Shape;
  final bool useIos3Green;
  final bool ios3Media;
  final bool useIos26Shape;
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
    if (gradient != null && fixedGradient) {
      paint.shader = gradient!.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height + 7),
      );
    } else if (gradient != null && screenHeight > 0) {
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
            Radius.circular(useIos3Shape ? 19.5 : 20),
          ),
        );
      bubble = body;

      if (showTail) {
        final tail = useIos3Shape
            ? _ios3Tail(size, isFromMe: isFromMe)
            : useIos26Shape
                ? _ios26Tail(size, isFromMe: isFromMe)
                : Path();
        if (!useIos3Shape && !useIos26Shape && isFromMe) {
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
        } else if (!useIos3Shape && !useIos26Shape) {
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

    if (useIos3Shape) {
      canvas.drawShadow(
        bubble.shift(const Offset(0, 1)),
        CupertinoColors.black.withValues(alpha: .18),
        1.5,
        true,
      );
    } else if (shadowElevation > 0) {
      canvas.drawShadow(
        bubble,
        CupertinoColors.black.withValues(alpha: .38),
        shadowElevation,
        true,
      );
    }
    canvas.drawPath(bubble, paint);
    if (useIos3Shape && !ios3Media) {
      canvas.save();
      canvas.clipPath(bubble);
      final highlightRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .045,
          size.height * .01,
          size.width * .91,
          size.height * .17,
        ),
        Radius.circular(size.height * .085),
      );
      final glossPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xCCFFFFFF), Color(0x00F3FFF2)],
        ).createShader(highlightRect.outerRect);
      canvas.drawRRect(highlightRect, glossPaint);
      final innerTint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: useIos3Green
              ? const [Color(0x00BDFF43), Color(0x66BDFF43)]
              : isFromMe
                  ? const [Color(0x00FFFFFF), Color(0x7AFFFFFF)]
                  : const [Color(0x00FFFFFF), Color(0x24FFFFFF)],
          stops: useIos3Green ? const [.78, 1] : const [.35, 1],
        ).createShader(Offset.zero & size);
      canvas.drawPath(
        bubble,
        innerTint,
      );
      canvas.restore();
      canvas.save();
      canvas.clipPath(bubble);
      final lowerReflection = Path();
      final lowerStart = isFromMe ? 3.5 : 8.0;
      final lowerEnd = size.width - (isFromMe ? 8.0 : 3.5);
      final lowerY = size.height - 1.4;
      lowerReflection
        ..moveTo(lowerStart, lowerY - 2.2)
        ..quadraticBezierTo(lowerStart + 1.2, lowerY, lowerStart + 4, lowerY)
        ..lineTo(lowerEnd - 4, lowerY)
        ..quadraticBezierTo(lowerEnd - 1.2, lowerY, lowerEnd, lowerY - 2.2);
      canvas.drawPath(
        lowerReflection,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xB8FFFFFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .35),
      );
      canvas.restore();
      canvas.drawPath(
        bubble,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF8D8D8D).withValues(alpha: .45),
      );
    }
  }

  @override
  bool shouldRepaint(MessageBubblePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.gradient != gradient ||
      oldDelegate.fixedGradient != fixedGradient ||
      oldDelegate.useIos3Shape != useIos3Shape ||
      oldDelegate.useIos3Green != useIos3Green ||
      oldDelegate.ios3Media != ios3Media ||
      oldDelegate.useIos26Shape != useIos26Shape ||
      oldDelegate.scrollPosition != scrollPosition ||
      oldDelegate.paintKey != paintKey ||
      oldDelegate.screenHeight != screenHeight ||
      oldDelegate.isFromMe != isFromMe ||
      oldDelegate.showTail != showTail ||
      oldDelegate.shadowElevation != shadowElevation;

  static Path _ios3Tail(Size size, {required bool isFromMe}) {
    final path = Path();
    final direction = isFromMe ? 1.0 : -1.0;
    final edge = isFromMe ? size.width : 0.0;
    double x(double distance) => edge + distance * direction;
    path
      ..moveTo(x(-6.15), size.height - 5.3)
      ..cubicTo(
        x(-3.35),
        size.height - 2.95,
        x(.3),
        size.height - 1.5,
        x(4.3),
        size.height - 1.5,
      )
      ..cubicTo(
        x(6.3),
        size.height - 1.5,
        x(8.25),
        size.height - 1.85,
        x(10),
        size.height - 2.55,
      )
      ..cubicTo(
        x(4.4),
        size.height - 2.55,
        x(-.1),
        size.height - 6.8,
        x(-.1),
        size.height - 12.25,
      )
      ..lineTo(x(-.1), size.height - 17.35)
      ..cubicTo(
        x(0),
        size.height - 18.05,
        x(0),
        size.height - 18.8,
        x(0),
        size.height - 19.5,
      );
    path.close();
    return path;
  }

  static Path _ios26Tail(Size size, {required bool isFromMe}) {
    const designWidth = 70.0;
    final path = Path();
    double x(double value) => isFromMe
        ? size.width - designWidth + value
        : designWidth - value;

    path
      ..moveTo(x(47.78), size.height)
      ..cubicTo(
        x(48.77),
        size.height,
        x(49.42),
        size.height + .31,
        x(50.75),
        size.height + 1.24,
      )
      ..cubicTo(
        x(51.46),
        size.height + 1.74,
        x(54.2),
        size.height + 3.84,
        x(56.47),
        size.height + 5.09,
      )
      ..cubicTo(
        x(58.43),
        size.height + 6.17,
        x(60.11),
        size.height + 6.91,
        x(60.53),
        size.height + 6.94,
      )
      ..cubicTo(
        x(61.79),
        size.height + 7.04,
        x(61.95),
        size.height + 5.85,
        x(61.46),
        size.height + 5.21,
      )
      ..cubicTo(
        x(60.97),
        size.height + 4.57,
        x(60.41),
        size.height + 3.74,
        x(60.19),
        size.height + 3.29,
      )
      ..cubicTo(
        x(59.71),
        size.height + 2.28,
        x(59.56),
        size.height + 1.75,
        x(59.56),
        size.height + .24,
      )
      ..cubicTo(
        x(59.56),
        size.height - 1.62,
        x(60.88),
        size.height - 3,
        x(61.92),
        size.height - 3.92,
      )
      ..cubicTo(
        x(62.01),
        size.height - 4,
        x(62.13),
        size.height - 4.1,
        x(62.27),
        size.height - 4.21,
      )
      ..cubicTo(
        x(62.51),
        size.height - 4.4,
        x(62.74),
        size.height - 4.59,
        x(62.97),
        size.height - 4.78,
      )
      ..lineTo(x(62.97), size.height - 11)
      ..lineTo(x(45.98), size.height - 11)
      ..lineTo(x(45.98), size.height)
      ..close();
    return path;
  }
}
