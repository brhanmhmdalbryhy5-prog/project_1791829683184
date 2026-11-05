import 'package:flutter/material.dart';

class AppColors {
  // الألوان الأساسية
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFE8C766);
  static const Color goldDark = Color(0xFF8B7320);
  static const Color black = Color(0xFF000000);
  static const Color cardBlack = Color(0xFF141414);
  static const Color inputBlack = Color(0xFF1A1A1A);
  static const Color borderGold = Color(0x66D4AF37);

  // 🎨 الـ 12 لوناً الجديدة
  static const List<Color> palette = [
    Color(0xFFFF5252), // أحمر
    Color(0xFFE040FB), // بنفسجي
    Color(0xFF7C4DFF), // نيلي
    Color(0xFF536DFE), // أزرق
    Color(0xFF448AFF), // أزرق فاتح
    Color(0xFF00B0FF), // سماوي
    Color(0xFF00E676), // أخضر فاتح
    Color(0xFF4CAF50), // أخضر
    Color(0xFFFFEB3B), // أصفر
    Color(0xFFFF9800), // برتقالي
    Color(0xFF795548), // بني
    Color(0xFF9E9E9E), // رمادي
  ];

  static Color getColor(int index) {
    return palette[index % palette.length];
  }
}