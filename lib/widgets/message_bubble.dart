import 'dart:ui';

import 'package:flutter/cupertino.dart';

import '../models/conversation.dart';
import '../theme/messages_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.showTail,
    required this.compactTop,
    this.showStatus = false,
    this.shadowElevation = 0,
  });

  final ChatMessage message;
  final bool showTail;
  final bool compactTop;
  final bool showStatus;
  final double shadowElevation;

  @override
  Widget build(BuildContext context) {
    final isFromMe = message.isFromMe;
    final color = isFromMe
        ? MessagesPalette.sentBubble(context)
        : MessagesPalette.receivedBubble(context);

    return Semantics(
      label: isFromMe ? 'Sent message' : 'Received message',
      child: Padding(
        padding: EdgeInsets.only(top: compactTop ? 2 : 8),
        child: Column(
          crossAxisAlignment:
              isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Align(
              alignment:
                  isFromMe ? Alignment.centerRight : Alignment.centerLeft,
              child: CustomPaint(
                painter: MessageBubblePainter(
                  color: color,
                  isFromMe: isFromMe,
                  showTail: showTail,
                  shadowElevation: shadowElevation,
                ),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: 36,
                    maxWidth: MediaQuery.sizeOf(context).width * .77,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  child: Text(
                    message.text,
                    textAlign: TextAlign.center,
                    style: MessagesText.body(context).copyWith(
                      color: isFromMe
                          ? CupertinoColors.white
                          : MessagesPalette.label(context),
                    ),
                  ),
                ),
              ),
            ),
            if (showStatus && isFromMe)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(
                  _statusLabel(message.deliveryState),
                  style: TextStyle(
                    color: MessagesPalette.secondaryLabel(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(DeliveryState state) {
    return switch (state) {
      DeliveryState.sending => 'Sending…',
      DeliveryState.delivered => 'Delivered',
      DeliveryState.read => 'Read',
      DeliveryState.failed => 'Not Delivered',
    };
  }
}

/// Paints the tail outside the bubble's layout bounds so adding a new message
/// never changes the position of text in an existing bubble.
class MessageBubblePainter extends CustomPainter {
  const MessageBubblePainter({
    required this.color,
    required this.isFromMe,
    required this.showTail,
    required this.shadowElevation,
  });

  final Color color;
  final bool isFromMe;
  final bool showTail;
  final double shadowElevation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
      );
    var bubble = body;

    if (showTail) {
      final tail = Path();
      if (isFromMe) {
        tail
          ..moveTo(size.width - 12, size.height - 10)
          ..cubicTo(
            size.width - 5,
            size.height - 5,
            size.width + 1,
            size.height,
            size.width + 7,
            size.height,
          )
          ..cubicTo(
            size.width + 2,
            size.height - 2,
            size.width,
            size.height - 7,
            size.width - 1,
            size.height - 12,
          );
      } else {
        tail
          ..moveTo(12, size.height - 10)
          ..cubicTo(
            5,
            size.height - 5,
            -1,
            size.height,
            -7,
            size.height,
          )
          ..cubicTo(
            -2,
            size.height - 2,
            0,
            size.height - 7,
            1,
            size.height - 12,
          );
      }
      tail.close();
      // Joining two subpaths can cancel their overlapping winding area and
      // leave a white notch between the body and tail. A geometric union
      // guarantees a single solid silhouette on every Android renderer.
      bubble = Path.combine(PathOperation.union, body, tail);
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
      oldDelegate.isFromMe != isFromMe ||
      oldDelegate.showTail != showTail ||
      oldDelegate.shadowElevation != shadowElevation;
}
