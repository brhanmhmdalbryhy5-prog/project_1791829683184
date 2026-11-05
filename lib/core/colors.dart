import 'package:flutter/material.dart';

class AppColors {
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFE8C766);
  static const Color goldDark = Color(0xFF8B7320);
  static const Color black = Color(0xFF000000);
  static const Color cardBlack = Color(0xFF141414);
  static const Color inputBlack = Color(0xFF1A1A1A);
  static const Color borderGold = Color(0x66D4AF37);

  static const List<Color> palette = [
    Color(0xFFFF5252), Color(0xFFE040FB), Color(0xFF7C4DFF),
    Color(0xFF536DFE), Color(0xFF448AFF), Color(0xFF00B0FF),
    Color(0xFF00E676), Color(0xFF4CAF50), Color(0xFFFFEB3B),
    Color(0xFFFF9800), Color(0xFF795548), Color(0xFF9E9E9E),
  ];

  static Color getColor(int index) => palette[index % palette.length];

  static Color getColorForName(String name) {
    if (name.isEmpty) return palette[0];
    final hash = name.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return getColor(hash);
  }
}