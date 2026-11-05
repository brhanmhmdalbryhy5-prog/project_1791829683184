import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'colors.dart';

Future<void> playClickSound() async {
  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {}
}

int toInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
double toDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;
String clean(dynamic value) => value?.toString() ?? '';

String getUserLevel(int points) {
  if (points >= 100) return 'SS';
  if (points >= 70) return 'S';
  if (points >= 40) return 'A';
  if (points >= 20) return 'B';
  if (points >= 10) return 'C';
  if (points >= 5) return 'D';
  return 'E';
}

String quizTypeName(String type) {
  switch (type) {
    case 'guess_character': return 'احزر الشخصية';
    case 'image_character': return 'خمن الشخصية من الصورة';
    default: return 'أسئلة مباشرة';
  }
}

String safeExtension(String path) {
  final raw = path.split('.').last.toLowerCase();
  const allowed = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'bmp'];
  if (raw.length <= 5 && allowed.contains(raw)) return raw;
  return 'jpg';
}

class BadgeInfo {
  final int points;
  final String icon;
  final String name;
  const BadgeInfo({required this.points, required this.icon, required this.name});
}

const List<BadgeInfo> otakuBadges = [
  BadgeInfo(points: 30, icon: '🥉', name: 'أوتاكو ممتاز'),
  BadgeInfo(points: 60, icon: '⚔️', name: 'محارب الأنمي'),
  BadgeInfo(points: 100, icon: '🥈', name: 'أوتاكو متقدم'),
  BadgeInfo(points: 150, icon: '🔥', name: 'عاشق الأنمي'),
  BadgeInfo(points: 250, icon: '💎', name: 'أوتاكو نادر'),
  BadgeInfo(points: 400, icon: '👑', name: 'سيد الأوتاكو'),
  BadgeInfo(points: 600, icon: '🌟', name: 'أسطورة الأنمي'),
  BadgeInfo(points: 1000, icon: '🏆', name: 'إمبراطور الأنمي'),
];

BadgeInfo? getCurrentBadge(int points) {
  BadgeInfo? current;
  for (final badge in otakuBadges) {
    if (points >= badge.points) current = badge;
  }
  return current;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.black87,
    ),
  );
}