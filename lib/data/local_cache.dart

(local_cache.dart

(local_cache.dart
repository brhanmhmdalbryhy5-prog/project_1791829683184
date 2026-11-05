import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

 LocalCache {
  static const String _prefix = 'mr_otaku_cache_';
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<void> saveList(String key, List<Map<String, dynamic>> data) async {
    await init();
    try { await _prefs!.setString('$_prefix$key', jsonEncode(data)); } catch (_) {}
  }

  static List<Map<String, dynamic>> loadList(String key) {
    final raw = _prefs?.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) { return []; }
  }

  static Future<void> saveMap(String key, Map<String, dynamic>? data) async {
    await init();
    try {
      if (data == null) { await _prefs!.remove('$_prefix$key'); } 
      else { await _prefs!.setString('$_prefix$key', jsonEncode(data)); }
    } catch (_) {}
  }

  static Map<String, dynamic>? loadMap(String key) {
    final raw = _prefs?.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return null;
    try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) { return null; }
  }

  static Future<void> saveString(String key, String? value) async {
    await init();
    try {
      if (value == null) { await _prefs!.remove('$_prefix$key'); } 
      else { await _prefs!.setString('$_prefix$key', value); }
    } catch (_) {}
  }

  static String? loadString(String key) => _prefs?.getString('$_prefix$key');

  static Future<void> saveInt(String key, int? value) async {
    await init();
    try {
      if (value == null) { await _prefs!.remove('$_prefix$key'); } 
      else { await _prefs!.setInt('$_prefix$key', value); }
    } catch (_) {}
  }

  static int? loadInt(String key) => _prefs?.getInt('$_prefix$key');

  static Future<void> saveBool(String key, bool value) async {
    await init();
    try { await _prefs!.setBool('$_prefix$key', value); } catch (_) {}
  }

  static bool loadBool(String key, {bool defaultValue = false}) => _prefs?.getBool('$_prefix$key') ?? defaultValue;

  static Future<void> remove(String key) async {
    await init();
    try { await _prefs!.remove('$_prefix$key'); } catch (_) {}
  }
}