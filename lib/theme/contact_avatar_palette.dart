import 'package:flutter/cupertino.dart';

const _iosContactAvatarPalettes = <List<Color>>[
  [Color(0xFFAFB4BF), Color(0xFF858B94)],
  [Color(0xFFF19AB8), Color(0xFFEE6089)],
  [Color(0xFFF58D83), Color(0xFFF34C43)],
  [Color(0xFFF8C46B), Color(0xFFF5A524)],
  [Color(0xFFFFE478), Color(0xFFFFD33E)],
  [Color(0xFF9DE39C), Color(0xFF68CF74)],
  [Color(0xFF94D9F4), Color(0xFF62C5E7)],
  [Color(0xFFBCAEF2), Color(0xFF967DE2)],
];

List<Color> contactAvatarColors(String id) {
  var hash = 0;
  for (final codeUnit in id.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7FFFFFFF;
  }
  return _iosContactAvatarPalettes[hash % _iosContactAvatarPalettes.length];
}
