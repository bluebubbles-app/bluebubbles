import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../models/conversation.dart';
import '../theme/contact_avatar_palette.dart';

class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.conversation,
    this.size = 52,
    this.showUnreadBadge = false,
  });

  final Conversation conversation;
  final double size;
  final bool showUnreadBadge;

  @override
  Widget build(BuildContext context) {
    final avatarBytes = conversation.avatarBytes;
    final decodedSize = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 512)
        .toInt();
    final Widget avatarContent;
    if (avatarBytes != null) {
      avatarContent = Image.memory(
        avatarBytes,
        width: size,
        height: size,
        cacheWidth: decodedSize,
        cacheHeight: decodedSize,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (conversation.avatarAsset != null) {
      avatarContent = Image.asset(
        conversation.avatarAsset!,
        width: size,
        height: size,
        cacheWidth: decodedSize,
        cacheHeight: decodedSize,
        fit: BoxFit.cover,
      );
    } else if (conversation.isKnownContact == false) {
      avatarContent = SizedBox.square(
        dimension: size,
        child: const CustomPaint(
          key: ValueKey('unknown-contact-avatar'),
          painter: _UnknownContactAvatarPainter(),
        ),
      );
    } else {
      final colors = contactAvatarColors(conversation.id);
      final topColor = Color.alphaBlend(
        CupertinoColors.white.withValues(alpha: .12),
        colors.first,
      );
      final middleColor = Color.alphaBlend(
        CupertinoColors.white.withValues(alpha: .04),
        Color.lerp(colors.first, colors.last, .52)!,
      );
      avatarContent = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topColor, middleColor, colors.last],
            stops: const [0, .48, 1],
          ),
        ),
        child: Text(
          conversation.initials,
          style: TextStyle(
            color: CupertinoColors.white,
            fontSize: size * .34,
            fontWeight: FontWeight.w600,
            letterSpacing: -.4,
          ),
        ),
      );
    }
    final avatar = ClipOval(child: avatarContent);

    if (!showUnreadBadge || conversation.unreadCount == 0) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed.resolveFrom(context),
              shape: BoxShape.circle,
              border: Border.all(
                color: CupertinoColors.systemBackground.resolveFrom(context),
                width: 2,
              ),
            ),
            child: Text(
              '${conversation.unreadCount}',
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnknownContactAvatarPainter extends CustomPainter {
  const _UnknownContactAvatarPainter();

  static const _designSize = 263.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _designSize, size.height / _designSize);

    final background = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(131.5, -142),
        const Offset(131.5, 132),
        const [Color(0xFFBDC2D0), Color(0xFF9A9EA9)],
      );
    canvas.drawCircle(const Offset(131.5, 131.5), 131.5, background);

    final foreground = Paint()..color = CupertinoColors.white;
    final shoulders = Path()
      ..moveTo(213, 208.888)
      ..cubicTo(182.5, 253, 84.1525, 254.372, 51, 208.888)
      ..cubicTo(89.3443, 160.23, 174.783, 159.18, 213, 208.888)
      ..close();
    canvas.drawPath(shoulders, foreground);

    final head = Path()
      ..moveTo(178, 106)
      ..cubicTo(178, 133.062, 157.405, 155, 132, 155)
      ..cubicTo(106.595, 155, 86, 133.062, 86, 106)
      ..cubicTo(86, 78.938, 106.595, 57, 132, 57)
      ..cubicTo(157.405, 57, 178, 78.938, 178, 106)
      ..close();
    canvas.drawPath(head, foreground);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_UnknownContactAvatarPainter oldDelegate) => false;
}
