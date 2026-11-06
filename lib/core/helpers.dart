import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'colors.dart';

Future<void> playClickSound() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('mr_otaku_sound_enabled') ?? true) {
      await HapticFeedback.lightImpact();
    }
  } catch (_) {}
}

/// تنزيل الصورة إلى معرض الهاتف (باستخدام gal الحديثة)
Future<bool> downloadImageToGallery(String imageUrl, {String fileName = 'mr_otaku_image'}) async {
  try {
    // 1) تنزيل البايتات
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) {
      debugPrint('Download failed: ${response.statusCode}');
      return false;
    }

    // 2) طلب صلاحية الوصول للمعرض
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        debugPrint('Gal permission denied');
        return false;
      }
    }

    // 3) حفظ الصورة
    await Gal.putImageBytes(
      response.bodyBytes,
      name: '${fileName}_${DateTime.now().millisecondsSinceEpoch}',
    );
    return true;
  } catch (e) {
    debugPrint('Download error: $e');
    return false;
  }
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
  const allowed = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'bmp', 'mp4', 'mov', 'webm'];
  if (raw.length <= 5 && allowed.contains(raw)) return raw;
  return 'jpg';
}

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

BadgeInfo? getNextBadge(int points) {
  for (final badge in otakuBadges) { if (points < badge.points) return badge; }
  return null;
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

class Certificate {
  final String title; final String icon; final bool unlocked; final String description;
  const Certificate({required this.title, required this.icon, required this.unlocked, required this.description});
}

List<Certificate> buildCertificates({required int postsCount, required int receivedLikes, required int points, required String level}) {
  return [
    Certificate(title: 'البداية', icon: '🌱', unlocked: points >= 5, description: 'وصلت إلى 5 نقاط'),
    Certificate(title: 'منشئ المحتوى', icon: '✍️', unlocked: postsCount >= 1, description: 'نشرت أول منشور'),
    Certificate(title: 'كاتب نشيط', icon: '📚', unlocked: postsCount >= 5, description: 'نشرت 5 منشورات'),
    Certificate(title: 'كاتب محترف', icon: '🖋️', unlocked: postsCount >= 10, description: 'نشرت 10 منشورات'),
    Certificate(title: 'محبوب', icon: '❤️', unlocked: receivedLikes >= 10, description: 'حصلت على 10 إعجابات'),
    Certificate(title: 'نجم الأوتاكو', icon: '⭐', unlocked: receivedLikes >= 50, description: 'حصلت على 50 إعجاب'),
    Certificate(title: 'مئة نقطة', icon: '💯', unlocked: points >= 100, description: 'وصلت إلى 100 نقطة'),
    Certificate(title: 'خمسمئة نقطة', icon: '🔥', unlocked: points >= 500, description: 'وصلت إلى 500 نقطة'),
    Certificate(title: 'أوتاكو متقدم', icon: '🥈', unlocked: level == 'A' || level == 'S' || level == 'SS', description: 'وصلت للمستوى A'),
    Certificate(title: 'أسطورة', icon: '🏆', unlocked: level == 'SS', description: 'وصلت للمستوى SS'),
  ];
}