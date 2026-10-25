import 'package:flutter/cupertino.dart';

import '../theme/messages_theme.dart';

class IosSearchField extends StatelessWidget {
  const IosSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.height = 36,
    this.backgroundColor,
    this.borderRadius = 10,
    this.fontSize = 17,
    this.iconSize = 18,
    this.verticalPadding = 7,
    this.borderColor,
    this.showMicrophone = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double height;
  final Color? backgroundColor;
  final double borderRadius;
  final double fontSize;
  final double iconSize;
  final double verticalPadding;
  final Color? borderColor;
  final bool showMicrophone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? MessagesPalette.fill(context),
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: borderColor == null
            ? null
            : const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: CupertinoTextField(
        controller: controller,
        onChanged: onChanged,
        placeholder: 'Search',
        placeholderStyle: TextStyle(
          color: MessagesPalette.secondaryLabel(context),
          fontSize: fontSize,
        ),
        style: MessagesText.body(context).copyWith(fontSize: fontSize),
        prefix: Padding(
          padding: const EdgeInsets.only(left: 8, right: 5),
          child: Icon(
            CupertinoIcons.search,
            size: iconSize,
            color: MessagesPalette.secondaryLabel(context),
          ),
        ),
        suffix: controller.text.isEmpty
            ? showMicrophone
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      CupertinoIcons.mic,
                      size: iconSize,
                      color: MessagesPalette.secondaryLabel(context),
                    ),
                  )
                : null
            : CupertinoButton(
                minSize: 28,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                child: Icon(
                  CupertinoIcons.clear_circled_solid,
                  size: 17,
                  color: MessagesPalette.secondaryLabel(context),
                ),
              ),
        decoration: null,
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        textInputAction: TextInputAction.search,
      ),
    );
  }
}
