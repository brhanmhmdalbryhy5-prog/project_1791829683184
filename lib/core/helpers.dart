import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart';

Future<void> playClickSound() async {
  try { await SystemSound.play(SystemSoundType.click); } catch (_) {}
}

int parseInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
double parseDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;
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

// ✅ دالة "منذ ساعة / منذ يوم" مثل تيك توك ويوتيوب
String timeAgo(String dateStr) {
  if (dateStr.isEmpty) return '';
  try {
    final dt = DateTime.parse(dateStr).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'منذ ${diff.inDays} يوم';
    if (diff.inDays < 30) return 'منذ ${(diff.inDays / 7).floor()} أسبوع';
    if (diff.inDays < 365) return 'منذ ${(diff.inDays / 30).floor()} شهر';
    return 'منذ ${(diff.inDays / 365).floor()} سنة';
  } catch (e) { return ''; }
}

Future<bool> checkAdminSession(dynamic data) async {
  final accId = data.currentAccountId;
  if (accId == null) return false;
  try {
    final player = await Supabase.instance.client.from('players').select().eq('account_id', accId).maybeSingle();
    if (player == null) return false;
    return player['is_admin'] == true;
  } catch (e) { return false; }
}

void showAvatarDialog(BuildContext context, String url, String name) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold, width: 4),
            boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)],
          ),
          child: CircleAvatar(
            radius: 100,
            backgroundColor: AppColors.inputBlack,
            backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
            child: url.isEmpty ? const Icon(Icons.person, size: 100, color: AppColors.gold) : null,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(color: AppColors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.gold)),
          child: Text(name, style: const TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.bold)),
        ),
      ]),
    ),
  );
}

class BadgeInfo {
  final int points; final String icon; final String name;
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
  for (final badge in otakuBadges) { if (points >= badge.points) current = badge; }
  return current;
}

class RewardInfo {
  final String name; final String icon; final int requiredPoints;
  const RewardInfo({required this.name, required this.icon, required this.requiredPoints});
}

const List<RewardInfo> allRewards = [
  RewardInfo(name: 'ميدالية برونزية', icon: '🥉', requiredPoints: 10),
  RewardInfo(name: 'ميدالية فضية', icon: '🥈', requiredPoints: 30),
  RewardInfo(name: 'ميدالية ذهبية', icon: '🥇', requiredPoints: 60),
  RewardInfo(name: 'كأس ذهبي', icon: '🏆', requiredPoints: 100),
  RewardInfo(name: 'كرة ذهبية', icon: '⚽', requiredPoints: 250),
  RewardInfo(name: 'تاج ملكي', icon: '👑', requiredPoints: 500),
];

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, backgroundColor: AppColors.cardBlack),
  );
}