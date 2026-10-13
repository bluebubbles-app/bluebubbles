import 'package:flutter/cupertino.dart';

import '../theme/messages_theme.dart';

class IosSearchField extends StatelessWidget {
  const IosSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: MessagesPalette.fill(context),
        borderRadius: BorderRadius.circular(10),
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
            ? null
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
