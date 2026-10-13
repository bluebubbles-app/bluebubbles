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
  });

  final ChatMessage message;
  final bool showTail;
  final bool compactTop;
  final bool showStatus;

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
              child: ClipPath(
                clipper: MessageTailClipper(
                  isFromMe: isFromMe,
                  showTail: showTail,
                ),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: 36,
                    maxWidth: MediaQuery.sizeOf(context).width * .77,
                  ),
                  color: color,
                  padding: EdgeInsets.fromLTRB(
                    isFromMe ? 13 : (showTail ? 19 : 13),
                    8,
                    isFromMe ? (showTail ? 19 : 13) : 13,
                    8,
                  ),
                  child: Text(
                    message.text,
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

/// Geometry adapted from the OpenBubbles TailClipper (Apache-2.0).
class MessageTailClipper extends CustomClipper<Path> {
  const MessageTailClipper({
    required this.isFromMe,
    required this.showTail,
  });

  final bool isFromMe;
  final bool showTail;

  @override
  Path getClip(Size size) {
    final path = Path();
    final start = isFromMe ? 0.0 : 8.0;
    final end = isFromMe ? size.width - 8 : size.width;

    path.moveTo(start, 18);

    if (!isFromMe && showTail) {
      path.lineTo(start, size.height - 9);
      path.arcToPoint(
        Offset(0, size.height),
        radius: const Radius.circular(9),
      );
      path.arcToPoint(
        Offset(start + 6, size.height - 5),
        radius: const Radius.circular(18),
        clockwise: false,
      );
      path.arcToPoint(
        Offset(start + 18, size.height),
        radius: const Radius.circular(18),
        clockwise: false,
      );
    } else {
      path.lineTo(start, size.height - 18);
      path.arcToPoint(
        Offset(start + 18, size.height),
        radius: const Radius.circular(18),
        clockwise: false,
      );
    }

    if (isFromMe && showTail) {
      path.lineTo(end - 18, size.height);
      path.arcToPoint(
        Offset(end - 6, size.height - 5),
        radius: const Radius.circular(18),
        clockwise: false,
      );
      path.arcToPoint(
        Offset(size.width, size.height),
        radius: const Radius.circular(18),
        clockwise: false,
      );
      path.arcToPoint(
        Offset(end, size.height - 9),
        radius: const Radius.circular(9),
      );
    } else {
      path.lineTo(end - 18, size.height);
      path.arcToPoint(
        Offset(end, size.height - 18),
        radius: const Radius.circular(18),
        clockwise: false,
      );
    }

    path.lineTo(end, 18);
    path.arcToPoint(
      Offset(end - 18, 0),
      radius: const Radius.circular(18),
      clockwise: false,
    );
    path.lineTo(start + 18, 0);
    path.arcToPoint(
      Offset(start, 18),
      radius: const Radius.circular(18),
      clockwise: false,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(MessageTailClipper oldClipper) =>
      oldClipper.isFromMe != isFromMe || oldClipper.showTail != showTail;
}
