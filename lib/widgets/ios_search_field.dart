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
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double height;
  final Color? backgroundColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? MessagesPalette.fill(context),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: CupertinoTextField(
        controller: controller,
        onChanged: onChanged,
        placeholder: 'Search',
        placeholderStyle: TextStyle(
          color: MessagesPalette.secondaryLabel(context),
          fontSize: 17,
        ),
        style: MessagesText.body(context),
        prefix: Padding(
          padding: const EdgeInsets.only(left: 8, right: 5),
          child: Icon(
            CupertinoIcons.search,
            size: 18,
            color: MessagesPalette.secondaryLabel(context),
          ),
        ),
        suffix: controller.text.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  CupertinoIcons.mic,
                  size: 18,
                  color: MessagesPalette.secondaryLabel(context),
                ),
              )
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
        padding: const EdgeInsets.symmetric(vertical: 7),
        textInputAction: TextInputAction.search,
      ),
    );
  }
}
