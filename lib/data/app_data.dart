import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide toInt;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/colors.dart';
import '../core/helpers.dart';

class LocalCache {
  static const String _prefix = 'mr_otaku_cache_';
  static SharedPreferences? _prefs;
  static Future<void> init() async => _prefs ??= await SharedPreferences.getInstance();
  static Future<void> saveString(String key, String? value) async { await init(); try { if (value == null) { await _prefs!.remove('$_prefix$key'); } else { await _prefs!.setString('$_prefix$key', value); } } catch (_) {} }
  static String? loadString(String key) => _prefs?.getString('$_prefix$key');
  static Future<void> saveInt(String key, int? value) async { await init(); try { if (value == null) { await _prefs!.remove('$_prefix$key'); } else { await _prefs!.setInt('$_prefix$key', value); } } catch (_) {} }
  static int? loadInt(String key) => _prefs?.getInt('$_prefix$key');
  static Future<void> remove(String key) async { await init(); try { await _prefs!.remove('$_prefix$key'); } catch (_) {} }
}

class AppData extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> news = [];
  List<Map<String, dynamic>> players = [];
  List<Map<String, dynamic>> latest = [];
  List<Map<String, dynamic>> messages = []; // رسائل الإدارة
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> quizQuestions = [];
  List<Map<String, dynamic>> quizResults = [];
  List<Map<String, dynamic>> gallery = [];
  List<Map<String, dynamic>> posts = [];
  List<Map<String, dynamic>> privateMessages = [];
  List<Map<String, dynamic>> userRewards = [];

  // الإعجابات والتعليقات على المنشورات
  final Map<dynamic, int> postLikeCounts = {};
  final Set<String> likedPosts = {};
  final Map<dynamic, int> postCommentCounts = {};

  // الأخبار
  final Map<dynamic, int> likeCounts = {};
  final Set<String> likedNews = {};
  final Map<dynamic, int> commentCounts = {};

  String importantNews = '';
  String importantNewsUpdatedAt = '';
  final Set<String> _readNotifications = {};
  bool loading = true;
  bool _isAdmin = false;
  int? currentAccountId;
  String currentUserName = '';

  bool get isAdmin => _isAdmin;
  bool get hasAccount => currentAccountId != null && currentUserName.trim().isNotEmpty;
  int get unreadNotificationCount => notifications.where((n) => !_readNotifications.contains(n['id'].toString())).length;
  
  Map<String, dynamic>? get currentPlayer {
    if (currentAccountId == null) return null;
    for (final player in players) { if (parseInt(player['account_id']) == currentAccountId) return player; }
    return null;
  }

  String get currentAvatar => clean(currentPlayer?['avatar_url']);
  int get currentPoints => parseInt(currentPlayer?['points']);
  String get currentLevel => getUserLevel(currentPoints);
  BadgeInfo? get currentBadge => getCurrentBadge(currentPoints);

  Map<String, dynamic>? get leader {
    if (players.isEmpty) return null;
    final sorted = [...players]; sorted.sort((a, b) => parseInt(b['points']).compareTo(parseInt(a['points']))); return sorted.first;
  }

  List<Map<String, dynamic>> get myPosts => posts.where((p) => parseInt(p['account_id']) == currentAccountId).toList();

  String avatarForAccount(dynamic accountId) {
    if (accountId == null) return '';
    final id = parseInt(accountId);
    if (id <= 0) return '';
    for (final p in players) { if (parseInt(p['account_id']) == id) return clean(p['avatar_url']); }
    return '';
  }

  Future<void> setAdminSession(bool value) async { _isAdmin = value; notifyListeners(); }

  Future<void> loadLocalAccount() async {
    final prefs = await SharedPreferences.getInstance();
    currentAccountId = int.tryParse(prefs.getString('mr_otaku_account_id') ?? '');
    currentUserName = prefs.getString('mr_otaku_user_name')?.trim() ?? '';
  }

  Future<bool> loginAccount(String name, int accountId) async {
    if (name.trim().isEmpty || accountId <= 0) return false;
    try {
      final player = await supabase.from('players').select().eq('account_id', accountId).maybeSingle();
      if (player == null) return false;
      final savedName = clean(player['name']).trim();
      if (savedName.toLowerCase() != name.trim().toLowerCase()) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mr_otaku_account_id', accountId.toString());
      await prefs.setString('mr_otaku_user_name', savedName);
      currentAccountId = accountId;
      currentUserName = savedName;
      notifyListeners();
      return true;
    } catch (e) { return false; }
  }

  Future<void> logoutAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mr_otaku_account_id');
    await prefs.remove('mr_otaku_user_name');
    currentAccountId = null;
    currentUserName = '';
    notifyListeners();
  }

  Future<void> loadData() async {
    loading = true; notifyListeners();
    try {
      final results = await Future.wait([
        supabase.from('news').select().order('created_at', ascending: false),
        supabase.from('players').select().order('points', ascending: false),
        supabase.from('latest').select().order('created_at', ascending: false),
      ]);
      news = List<Map<String, dynamic>>.from(results[0]);
      players = List<Map<String, dynamic>>.from(results[1]);
      latest = List<Map<String, dynamic>>.from(results[2]);

      await loadLikes(); await loadCommentCounts(); await loadNotifications(); 
      await loadQuizQuestions(); await loadImportantNews(); await loadGallery(); 
      await loadPosts(); await loadUserRewards();

      if (_isAdmin) {
        final msgData = await supabase.from('messages').select().order('created_at', ascending: false); messages = List<Map<String, dynamic>>.from(msgData);
        final quizData = await supabase.from('quiz_results').select().order('created_at', ascending: false); quizResults = List<Map<String, dynamic>>.from(quizData);
      } else { messages = []; quizResults = []; }
    } catch (e) { debugPrint('Load data error: $e'); }
    loading = false; notifyListeners();
  }

  Future<void> loadPlayers() async {
    try {
      final result = await supabase.from('players').select().order('points', ascending: false);
      players = List<Map<String, dynamic>>.from(result);
      notifyListeners();
    } catch (e) {}
  }

  // ================= المنشورات والإعجابات والتعليقات =================
  Future<void> loadPosts() async {
    try {
      final result = await supabase.from('posts').select().order('created_at', ascending: false);
      posts = List<Map<String, dynamic>>.from(result);
      await _loadPostInteractions();
      notifyListeners();
    } catch (e) {}
  }

  Future<void> _loadPostInteractions() async {
    try {
      final likes = await supabase.from('post_likes').select();
      postLikeCounts.clear(); likedPosts.clear();
      for (final item in likes) {
        final id = item['post_id'];
        postLikeCounts[id] = (postLikeCounts[id] ?? 0) + 1;
        if (parseInt(item['account_id']) == currentAccountId) likedPosts.add(id.toString());
      }
      final comments = await supabase.from('post_comments').select('post_id');
      postCommentCounts.clear();
      for (final item in comments) { final id = item['post_id']; postCommentCounts[id] = (postCommentCounts[id] ?? 0) + 1; }
    } catch (e) {}
  }

  Future<bool> togglePostLike(dynamic postId) async {
    if (currentAccountId == null) return false;
    try {
      final key = postId.toString();
      if (likedPosts.contains(key)) {
        await supabase.from('post_likes').delete().eq('post_id', postId).eq('account_id', currentAccountId!);
        likedPosts.remove(key); postLikeCounts[postId] = max(0, (postLikeCounts[postId] ?? 1) - 1);
      } else {
        await supabase.from('post_likes').insert({'post_id': postId, 'account_id': currentAccountId});
        likedPosts.add(key); postLikeCounts[postId] = (postLikeCounts[postId] ?? 0) + 1;
      }
      notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<List<Map<String, dynamic>>> getPostComments(dynamic postId) async {
    try {
      final result = await supabase.from('post_comments').select().eq('post_id', postId).order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) { return []; }
  }

  Future<bool> addPostComment(dynamic postId, String text) async {
    if (text.trim().isEmpty || currentAccountId == null) return false;
    try {
      await supabase.from('post_comments').insert({'post_id': postId, 'account_id': currentAccountId, 'user_name': currentUserName, 'comment_text': text.trim()});
      postCommentCounts[postId] = (postCommentCounts[postId] ?? 0) + 1;
      notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<bool> addPost(String content, File? imageFile) async {
    if (currentAccountId == null || content.trim().isEmpty) return false;
    try {
      String? imageUrl; if (imageFile != null) imageUrl = await uploadGeneralImage(imageFile, 'posts');
      await supabase.from('posts').insert({'account_id': currentAccountId, 'user_name': currentUserName, 'content': content.trim(), 'image_url': imageUrl});
      await loadPosts(); return true;
    } catch (e) { return false; }
  }

  Future<bool> deletePost(dynamic id) async {
    if (currentAccountId == null) return false;
    try {
      final post = posts.firstWhere((p) => p['id'] == id, orElse: () => {});
      if (parseInt(post['account_id']) != currentAccountId && !_isAdmin) return false;
      await supabase.from('posts').delete().eq('id', id); await loadPosts(); return true;
    } catch (e) { return false; }
  }

  // ================= الرسائل والجوائز =================
  Future<void> loadPrivateMessages(int otherUserId) async {
    if (currentAccountId == null) return;
    try {
      final result = await supabase.from('private_messages').select().or('and(sender_id.eq.$currentAccountId,receiver_id.eq.$otherUserId),and(sender_id.eq.$otherUserId,receiver_id.eq.$currentAccountId)').order('created_at', ascending: true);
      privateMessages = List<Map<String, dynamic>>.from(result); notifyListeners();
    } catch (e) {}
  }

  Future<bool> sendPrivateMessage(int receiverId, String message) async {
    if (currentAccountId == null || message.trim().isEmpty) return false;
    try { await supabase.from('private_messages').insert({'sender_id': currentAccountId, 'sender_name': currentUserName, 'receiver_id': receiverId, 'message': message.trim()}); return true; } catch (e) { return false; }
  }

  Future<void> loadUserRewards() async {
    if (currentAccountId == null) return;
    try { final result = await supabase.from('user_rewards').select().eq('account_id', currentAccountId!); userRewards = List<Map<String, dynamic>>.from(result); notifyListeners(); } catch (e) {}
  }

  Future<bool> claimReward(String rewardName, String rewardIcon) async {
    if (currentAccountId == null) return false;
    try { await supabase.from('user_rewards').insert({'account_id': currentAccountId, 'reward_name': rewardName, 'reward_icon': rewardIcon}); await loadUserRewards(); return true; } catch (e) { return false; }
  }
  bool hasReward(String rewardName) => userRewards.any((r) => r['reward_name'] == rewardName);

  // ================= الأخبار والمعرض =================
  Future<void> loadImportantNews() async {
    try {
      final result = await supabase.from('important_news').select().order('updated_at', ascending: false).limit(1).maybeSingle();
      if (result == null) { importantNews = ''; importantNewsUpdatedAt = ''; } else { importantNews = clean(result['content']); importantNewsUpdatedAt = clean(result['updated_at']); }
    } catch (e) {}
  }
  
  Future<void> loadGallery() async {
    try { final result = await supabase.from('gallery').select().order('created_at', ascending: false); gallery = List<Map<String, dynamic>>.from(result); } catch (e) { gallery = []; }
    notifyListeners();
  }

  Future<String?> addGalleryImage(File imageFile, {String caption = ''}) async {
    if (currentAccountId == null) return 'لم يتم تسجيل الدخول.';
    try { final ext = safeExtension(imageFile.path); final path = 'gallery/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$ext'; await supabase.storage.from('news-images').upload(path, imageFile); final url = supabase.storage.from('news-images').getPublicUrl(path); await supabase.from('gallery').insert({'account_id': currentAccountId, 'user_name': currentUserName, 'image_url': url, 'caption': caption.trim()}); await loadGallery(); return null; } catch (e) { return 'خطأ: $e'; }
  }

  Future<bool> deleteGalleryImage(dynamic id) async {
    if (!_isAdmin) return false;
    try { await supabase.from('gallery').delete().eq('id', id); await loadGallery(); return true; } catch (e) { return false; }
  }

  Future<bool> updateAvatar(File imageFile) async {
    if (currentAccountId == null) return false;
    try {
      final ext = safeExtension(imageFile.path); final path = 'avatars/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('news-images').upload(path, imageFile);
      final url = supabase.storage.from('news-images').getPublicUrl(path);
      await supabase.from('players').update({'avatar_url': url}).eq('account_id', currentAccountId!);
      for (final player in players) { if (parseInt(player['account_id']) == currentAccountId) player['avatar_url'] = url; }
      notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<String?> uploadGeneralImage(File file, String folder) async {
    try { final ext = safeExtension(file.path); final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$ext'; await supabase.storage.from('news-images').upload(path, file); return supabase.storage.from('news-images').getPublicUrl(path); } catch (e) { return null; }
  }

  // ================= الأسئلة والإعجابات =================
  Future<void> loadQuizQuestions() async {
    try { final result = await supabase.from('quiz_questions').select().order('created_at', ascending: true); quizQuestions = List<Map<String, dynamic>>.from(result); } catch (e) { quizQuestions = []; }
  }
  Future<void> saveQuizResult({required String quizType, required int correct, required int total}) async {
    try { await supabase.from('quiz_results').insert({'account_id': currentAccountId, 'user_name': currentUserName, 'quiz_type': quizType, 'correct_answers': correct, 'total_questions': total}); } catch (e) {}
  }
  Future<void> loadQuizResults() async {
    if (!_isAdmin) return;
    try { final result = await supabase.from('quiz_results').select().order('created_at', ascending: false); quizResults = List<Map<String, dynamic>>.from(result); notifyListeners(); } catch (e) {}
  }
  
  Future<void> loadLikes() async {
    try {
      final clientId = await getClientId(); final result = await supabase.from('news_likes').select('news_id, client_id'); likeCounts.clear(); likedNews.clear();
      for (final item in result) { final id = item['news_id']; likeCounts[id] = (likeCounts[id] ?? 0) + 1; if (clean(item['client_id']) == clientId) likedNews.add(id.toString()); }
    } catch (e) {}
  }

  Future<bool> toggleLike(dynamic newsId) async {
    try {
      final clientId = await getClientId(); final key = newsId.toString();
      if (likedNews.contains(key)) { await supabase.from('news_likes').delete().eq('news_id', newsId).eq('client_id', clientId); likedNews.remove(key); likeCounts[newsId] = max(0, (likeCounts[newsId] ?? 1) - 1); }
      else { await supabase.from('news_likes').insert({'news_id': newsId, 'client_id': clientId}); likedNews.add(key); likeCounts[newsId] = (likeCounts[newsId] ?? 0) + 1; }
      notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<void> loadCommentCounts() async {
    try { final result = await supabase.from('news_comments').select('news_id'); commentCounts.clear(); for (final item in result) { final id = item['news_id']; commentCounts[id] = (commentCounts[id] ?? 0) + 1; } } catch (e) {}
  }

  Future<List<Map<String, dynamic>>> getComments(dynamic newsId) async {
    try { final result = await supabase.from('news_comments').select().eq('news_id', newsId).order('created_at', ascending: false); return List<Map<String, dynamic>>.from(result); } catch (e) { return []; }
  }

  Future<bool> addComment(dynamic newsId, String userName, String text) async {
    if (text.trim().isEmpty) return false;
    try {
      final clientId = await getClientId();
      await supabase.from('news_comments').insert({'news_id': newsId, 'client_id': clientId, 'user_name': userName, 'comment_text': text.trim()});
      commentCounts[newsId] = (commentCounts[newsId] ?? 0) + 1; notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance(); String? id = prefs.getString('mr_otaku_client_id');
    if (id == null || id.isEmpty) { id = DateTime.now().microsecondsSinceEpoch.toString(); await prefs.setString('mr_otaku_client_id', id); }
    return id;
  }

  // ================= الإشعارات ورسائل الإدارة =================
  Future<void> loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance(); final saved = prefs.getStringList('mr_otaku_read_notifications'); _readNotifications.clear(); if (saved != null) _readNotifications.addAll(saved);
      final result = await supabase.from('notifications').select().order('created_at', ascending: false); notifications = List<Map<String, dynamic>>.from(result);
    } catch (e) {}
  }
  bool isNotificationRead(dynamic id) => _readNotifications.contains(id.toString());
  Future<void> markNotificationRead(dynamic id) async { final prefs = await SharedPreferences.getInstance(); _readNotifications.add(id.toString()); await prefs.setStringList('mr_otaku_read_notifications', _readNotifications.toList()); notifyListeners(); }
  Future<void> markAllNotificationsRead() async { final prefs = await SharedPreferences.getInstance(); for (final item in notifications) _readNotifications.add(item['id'].toString()); await prefs.setStringList('mr_otaku_read_notifications', _readNotifications.toList()); notifyListeners(); }

  Future<bool> sendMessage(String name, String message) async {
    if (message.trim().isEmpty) return false;
    try { await supabase.from('messages').insert({'name': currentUserName.trim().isNotEmpty ? currentUserName : name.trim().isEmpty ? 'مستخدم' : name.trim(), 'message': message.trim()}); return true; } catch (e) { return false; }
  }
}