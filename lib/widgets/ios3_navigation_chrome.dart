import 'dart:ui';

import 'package:flutter/cupertino.dart';

const double ios3TopBarHeight = 45;
const double ios3TopBarControlCenterY = 22.5;
const double ios3TopBarButtonHeight = 24;
const double ios3ConversationButtonHeight = 32;
const double ios3TopBarVerticalOffset =
    ios3TopBarControlCenterY - (ios3TopBarHeight / 2);

const BoxDecoration ios3TopBarDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF8BA9C7), Color(0xFF7595B1), Color(0xFF7795B4)],
    stops: [0, .5, 1],
  ),
  border: Border.fromBorderSide(
    BorderSide(color: Color(0x80303030), width: 1),
  ),
);

const LinearGradient ios3TopBarButtonGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFFA5B9CA),
    Color(0xFF809DB8),
    Color(0xFF5479A1),
    Color(0xFF365E8C),
  ],
  stops: [0, .25, .65, 1],
);

const TextStyle ios3TopBarTitleStyle = TextStyle(
  color: CupertinoColors.white,
  fontFamily: 'SF Pro Text',
  fontSize: 20,
  height: 1,
  fontWeight: FontWeight.w700,
  shadows: [
    Shadow(color: Color(0x4D000000), offset: Offset(0, -1)),
  ],
);

const TextStyle ios3TopBarButtonTextStyle = TextStyle(
  color: CupertinoColors.white,
  fontFamily: 'SF Pro Text',
  fontSize: 13,
  height: 1,
  fontWeight: FontWeight.w700,
  letterSpacing: -.39,
  shadows: [
    Shadow(color: Color(0xFF000000), offset: Offset(0, -1)),
  ],
);

class Ios3ButtonSurface extends StatelessWidget {
  const Ios3ButtonSurface({
    super.key,
    required this.width,
    required this.height,
    required this.onPressed,
    required this.child,
    this.backShape = false,
  });

  final double width;
  final double height;
  final VoidCallback? onPressed;
  final Widget child;
  final bool backShape;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        minSize: height,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: CustomPaint(
          painter: _Ios3NavigationButtonPainter(backShape: backShape),
          child: SizedBox(
            width: width,
            height: height,
            child: Center(child: child),
          ),
        ),
      );
}

class Ios3NavigationButton extends StatelessWidget {
  const Ios3NavigationButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backShape = false,
    this.height = ios3TopBarButtonHeight,
    this.maxWidth,
  });

  final String label;
  final VoidCallback onPressed;
  final bool backShape;
  final double height;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    const labelStyle = ios3TopBarButtonTextStyle;
    final labelPainter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final desiredWidth = backShape
        ? (labelPainter.width + 34).clamp(92.0, 136.0).toDouble()
        : (labelPainter.width + 32).clamp(60.0, 96.0).toDouble();
    final width = maxWidth == null
        ? desiredWidth
        : desiredWidth.clamp(0.0, maxWidth!).toDouble();
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: labelStyle,
    );
    return Ios3ButtonSurface(
      width: width,
      height: height,
      onPressed: onPressed,
      backShape: backShape,
      child: backShape
          ? SizedBox(
              width: width,
              height: height,
              child: Padding(
                padding: const EdgeInsets.only(left: 18, right: 16),
                child: Align(alignment: Alignment.centerLeft, child: text),
              ),
            )
          : text,
    );
  }
}

class _Ios3NavigationButtonPainter extends CustomPainter {
  const _Ios3NavigationButtonPainter({required this.backShape});

  final bool backShape;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (backShape) {
      path
        ..moveTo(17, 1)
        ..lineTo(size.width - 9, 1)
        ..quadraticBezierTo(size.width - 1, 1, size.width - 1, 9)
        ..lineTo(size.width - 1, size.height - 9)
        ..quadraticBezierTo(
          size.width - 1,
          size.height - 1,
          size.width - 9,
          size.height - 1,
        )
        ..lineTo(17, size.height - 1)
        ..lineTo(1, size.height / 2)
        ..close();
    } else {
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(8),
        ),
      );
    }
    final rect = Offset.zero & size;
    canvas.drawShadow(path, const Color(0x660D2741), 2, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ios3TopBarButtonGradient.createShader(rect),
    );
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path.shift(const Offset(0, 1)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xA6FFFFFF),
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4E6478), Color(0xFF324B69)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Ios3NavigationButtonPainter oldDelegate) =>
      oldDelegate.backShape != backShape;
}

class Ios3TopBarGloss extends StatelessWidget {
  const Ios3TopBarGloss({
    super.key,
    this.controlCenterY = ios3TopBarControlCenterY,
  });

  final double controlCenterY;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 1,
                height: controlCenterY - 1,
                child: const ColoredBox(color: Color(0x14FFFFFF)),
              ),
              const Positioned(
                left: 1,
                right: 1,
                top: 0,
                height: 1,
                child: ColoredBox(color: Color(0x80FFFFFF)),
              ),
            ],
          ),
        ),
      );
}
