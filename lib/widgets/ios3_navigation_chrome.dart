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
