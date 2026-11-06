import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'colors.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager instance = ThemeManager._();
  ThemeManager._();

  String _themeId = 'gold';
  bool _isDarkMode = true;

  String get themeId => _themeId;
  bool get isDarkMode => _isDarkMode;

  static const List<Map<String, dynamic>> themes = [
    {'id': 'gold',    'name': 'ذهبي',    'color': AppColors.gold,        'icon': Icons.auto_awesome},
    {'id': 'red',     'name': 'أحمر',    'color': Color(0xFFE53935),     'icon': Icons.favorite},
    {'id': 'blue',    'name': 'أزرق',    'color': Color(0xFF1E88E5),     'icon': Icons.water_drop},
    {'id': 'green',   'name': 'أخضر',    'color': Color(0xFF43A047),     'icon': Icons.eco},
    {'id': 'purple',  'name': 'بنفسجي',  'color': Color(0xFF8E24AA),     'icon': Icons.auto_awesome_mosaic},
    {'id': 'orange',  'name': 'برتقالي', 'color': Color(0xFFFB8C00),     'icon': Icons.local_fire_department},
    {'id': 'cyan',    'name': 'سماوي',   'color': Color(0xFF00ACC1),     'icon': Icons.cloud},
  ];

  Color get primaryColor {
    for (final t in themes) {
      if (t['id'] == _themeId) return t['color'] as Color;
    }
    return AppColors.gold;
  }

  // ✅ ألوان براقة للبطاقات
  LinearGradient getPrimaryGradient() {
    final color = primaryColor;
    return LinearGradient(
      colors: [color.withOpacity(0.9), color.withOpacity(0.5)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  LinearGradient getButtonGradient() {
    final color = primaryColor;
    return LinearGradient(
      colors: [color, color.withOpacity(0.7)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
  }

  List<BoxShadow> getGlowShadow() {
    final color = primaryColor;
    return [
      BoxShadow(color: color.withOpacity(0.5), blurRadius: 12, spreadRadius: 1),
      BoxShadow(color: color.withOpacity(0.2), blurRadius: 20, spreadRadius: 2),
    ];
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _themeId = prefs.getString('mr_otaku_theme') ?? 'gold';
      _isDarkMode = prefs.getBool('mr_otaku_dark_mode') ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setTheme(String id) async {
    _themeId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mr_otaku_theme', id);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggleDarkMode(bool value) async {
    _isDarkMode = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mr_otaku_dark_mode', value);
    } catch (_) {}
    notifyListeners();
  }
}

// ================= صفحة اختيار الثيمات =================
class ThemePickerPage extends StatelessWidget {
  const ThemePickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeManager.instance,
      builder: (context, _) {
        final primary = ThemeManager.instance.primaryColor;
        final isDark = ThemeManager.instance.isDarkMode;
        return Scaffold(
          appBar: AppBar(title: const Text('الثيمات')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: SwitchListTile(
                  secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: primary),
                  title: const Text('الوضع الليلي', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(isDark ? 'مفعّل - خلفية سوداء' : 'معطّل - خلفية بيضاء'),
                  value: isDark,
                  activeColor: primary,
                  onChanged: (v) => ThemeManager.instance.toggleDarkMode(v),
                ),
              ),
              const SizedBox(height: 16),
              ...ThemeManager.themes.map((theme) {
                final isSelected = ThemeManager.instance.themeId == theme['id'];
                final color = theme['color'] as Color;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: isSelected ? color.withOpacity(0.15) : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: isSelected ? color : Colors.transparent, width: 2),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 45, height: 45,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [color, color.withOpacity(0.6)]),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)],
                      ),
                      child: Icon(theme['icon'] as IconData, color: Colors.white, size: 24),
                    ),
                    title: Text(theme['name'] as String, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
                    trailing: isSelected ? Icon(Icons.check_circle, color: color, size: 30) : Icon(Icons.circle_outlined, color: Colors.grey.shade600),
                    onTap: () async {
                      await ThemeManager.instance.setTheme(theme['id'] as String);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تم تطبيق ثيم ${theme['name']}'), backgroundColor: color, behavior: SnackBarBehavior.floating),
                        );
                      }
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}