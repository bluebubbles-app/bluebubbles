import 'package:flutter/cupertino.dart';

import '../models/conversation.dart';

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
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: conversation.avatarColors,
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
