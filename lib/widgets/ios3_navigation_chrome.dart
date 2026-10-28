import 'package:flutter/cupertino.dart';

const double ios3TopBarHeight = 45;
const double ios3TopBarControlCenterY = 22.5;
const double ios3TopBarButtonHeight = 24;
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
    Color(0xFF4582B7),
    Color(0xFF4073A0),
    Color(0xFF4073A0),
    Color(0xFF4275A1),
    Color(0xFF4376A2),
  ],
  stops: [0, .283654, .5, .730769, 1],
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
  shadows: [
    Shadow(color: Color(0x4D000000), offset: Offset(0, -1)),
  ],
);

class Ios3NavigationButton extends StatelessWidget {
  const Ios3NavigationButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backShape = false,
    this.height = ios3TopBarButtonHeight,
    this.fontWeight = FontWeight.w700,
  });

  final String label;
  final VoidCallback onPressed;
  final bool backShape;
  final double height;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final labelStyle = ios3TopBarButtonTextStyle.copyWith(
      fontWeight: fontWeight,
    );
    final labelPainter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = backShape
        ? (labelPainter.width + 26).clamp(88.0, 116.0).toDouble()
        : (labelPainter.width + 32).clamp(60.0, 96.0).toDouble();
    return CupertinoButton(
      minSize: height,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: CustomPaint(
        painter: _Ios3NavigationButtonPainter(backShape: backShape),
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: EdgeInsets.only(left: backShape ? 8 : 0),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
          ),
        ),
      ),
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
        ..moveTo(13, 1)
        ..lineTo(size.width - 7, 1)
        ..quadraticBezierTo(size.width - 1, 1, size.width - 1, 7)
        ..lineTo(size.width - 1, size.height - 7)
        ..quadraticBezierTo(
          size.width - 1,
          size.height - 1,
          size.width - 7,
          size.height - 1,
        )
        ..lineTo(13, size.height - 1)
        ..lineTo(1, size.height / 2)
        ..close();
    } else {
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(4),
        ),
      );
    }
    final rect = Offset.zero & size;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ios3TopBarButtonGradient.createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x80000000),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = const Color(0x33FFFFFF),
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
