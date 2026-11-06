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
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> purchaseRequests = [];
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> quizQuestions = [];
  List<Map<String, dynamic>> quizResults = [];
  List<Map<String, dynamic>> gallery = [];
  List<Map<String, dynamic>> posts = [];
  List<Map<String, dynamic>> privateMessages = [];
  List<Map<String, dynamic>> userRewards = [];
  List<Map<String, dynamic>> savedPosts = [];
  List<Map<String, dynamic>> complaints = [];
  List<Map<String, dynamic>> stories = [];

  final Map<dynamic, int> postLikeCounts = {};
  final Set<String> likedPosts = {};
  final Map<dynamic, int> postCommentCounts = {};

  final Map<dynamic, int> likeCounts = {};
  final Set<String> likedNews = {};
  final Map<dynamic, int> commentCounts = {};

  final Map<dynamic, int> commentLikeCounts = {};
  final Set<String> likedComments = {};

  final Set<int> followingIds = {};
  int myFollowersCount = 0;
  int myFollowingCount = 0;

  final Set<String> _viewedStoryIds = {};

  Map<String, dynamic>? activePoll;
  List<Map<String, dynamic>> activePollOptions = [];
  List<Map<String, dynamic>> pollVoters = [];
  final Map<dynamic, int> pollVoteCounts = {};
  String? votedPollId;

  final Map<int, int> unreadMessageCounts = {};

  String importantNews = '';
  String importantNewsUpdatedAt = '';
  final Set<String> _readNotifications = {};
  bool loading = true;
  bool _isAdmin = false;
  int? currentAccountId;
  String currentUserName = '';

  String _lastSeenNewsId = '';
  int _lastSeenQuizCount = 0;
  int _lastSeenGalleryCount = 0;

  bool get isAdmin => _isAdmin;
  bool get hasAccount => currentAccountId != null && currentUserName.trim().isNotEmpty;
  int get unreadNotificationCount => notifications.where((n) => !_readNotifications.contains(n['id'].toString())).length;
  bool get hasNewNews => news.isNotEmpty && clean(news.first['id']) != _lastSeenNewsId;
  bool get hasNewQuiz => quizQuestions.length > _lastSeenQuizCount && _lastSeenQuizCount >= 0;
  bool get hasNewGallery => gallery.length > _lastSeenGalleryCount;
  bool get hasNewImportantNews {
    if (importantNews.isEmpty) return false;
    final lastSeen = LocalCache.loadString('last_seen_important_news');
    return importantNewsUpdatedAt != lastSeen;
  }

  List<Map<String, dynamic>> get activeStories {
    final now = DateTime.now().toUtc();
    return stories.where((s) {
      final exp = clean(s['expires_at']);
      if (exp.isEmpty) return true;
      try { return DateTime.parse(exp).isAfter(now); } catch (_) { return true; }
    }).toList();
  }

  bool hasViewedStory(dynamic storyId) => _viewedStoryIds.contains(storyId.toString());

  Map<String, dynamic>? get currentPlayer {
    if (currentAccountId == null) return null;
    for (final player in players) { if (parseInt(player['account_id']) == currentAccountId) return player; }
    return null;
  }
  String get currentAvatar => clean(currentPlayer?['avatar_url']);
  int get currentPoints => parseInt(currentPlayer?['points']);
  String get currentLevel => getUserLevel(currentPoints);
  BadgeInfo? get currentBadge => getCurrentBadge(currentPoints);
  BadgeInfo? get nextBadge => getNextBadge(currentPoints);

  String get currentDisplayName {
    final player = currentPlayer;
    if (player == null) return currentUserName;
    final channel = clean(player['channel_name']);
    return channel.isNotEmpty ? channel : currentUserName;
  }

  String displayNameForAccount(dynamic accountId) {
    if (accountId == null) return '';
    final id = parseInt(accountId);
    if (id <= 0) return '';
    for (final p in players) {
      if (parseInt(p['account_id']) == id) {
        final channel = clean(p['channel_name']);
        return channel.isNotEmpty ? channel : clean(p['name']);
      }
    }
    return '';
  }

  Map<String, dynamic>? get leader {
    if (players.isEmpty) return null;
    final sorted = [...players]; sorted.sort((a, b) => parseInt(b['points']).compareTo(parseInt(a['points']))); return sorted.first;
  }

  List<Map<String, dynamic>> get myPosts => posts.where((p) => parseInt(p['account_id']) == currentAccountId).toList();
  List<Map<String, dynamic>> get myLikedPosts => posts.where((p) => likedPosts.contains(p['id'].toString())).toList();
  int get myPostsCount => myPosts.length;
  int get myReceivedLikes {
    int total = 0;
    for (final post in posts) {
      if (parseInt(post['account_id']) == currentAccountId) {
        total += postLikeCounts[post['id']] ?? 0;
      }
    }
    return total;
  }

  String avatarForAccount(dynamic accountId) {
    if (accountId == null) return '';
    final id = parseInt(accountId);
    if (id <= 0) return '';
    for (final p in players) { if (parseInt(p['account_id']) == id) return clean(p['avatar_url']); }
    return '';
  }

  bool isPlayerAdmin(dynamic accountId) {
    for (final p in players) { if (parseInt(p['account_id']) == parseInt(accountId)) return p['is_admin'] == true; }
    return false;
  }

  Future<void> setAdminSession(bool value) async { _isAdmin = value; notifyListeners(); }
  Future<void> markNewsSeen() async { if (news.isNotEmpty) { _lastSeenNewsId = clean(news.first['id']); await LocalCache.saveString('last_seen_news_id', _lastSeenNewsId); notifyListeners(); } }
  Future<void> markQuizSeen() async { _lastSeenQuizCount = quizQuestions.length; await LocalCache.saveInt('last_seen_quiz_count', _lastSeenQuizCount); notifyListeners(); }
  Future<void> markGallerySeen() async { _lastSeenGalleryCount = gallery.length; await LocalCache.saveInt('last_seen_gallery_count', _lastSeenGalleryCount); notifyListeners(); }
  Future<void> markImportantNewsSeen() async { await LocalCache.saveString('last_seen_important_news', importantNewsUpdatedAt); notifyListeners(); }

  Future<void> updateLastSeen() async {
    if (currentAccountId == null) return;
    try { await supabase.from('players').update({'last_seen': DateTime.now().toUtc().toIso8601String()}).eq('account_id', currentAccountId!); } catch (e) { debugPrint('Update last seen error: $e'); }
  }

  Future<void> loadLocalAccount() async {
    final prefs = await SharedPreferences.getInstance();
    currentAccountId = int.tryParse(prefs.getString('mr_otaku_account_id') ?? '');
    currentUserName = prefs.getString('mr_otaku_user_name')?.trim() ?? '';
    _lastSeenNewsId = LocalCache.loadString('last_seen_news_id') ?? '';
    _lastSeenQuizCount = LocalCache.loadInt('last_seen_quiz_count') ?? 0;
    _lastSeenGalleryCount = LocalCache.loadInt('last_seen_gallery_count') ?? 0;
    final viewedList = prefs.getStringList('mr_otaku_viewed_stories');
    if (viewedList != null) _viewedStoryIds.addAll(viewedList);
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
      currentAccountId = accountId; currentUserName = savedName; notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<void> logoutAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mr_otaku_account_id'); await prefs.remove('mr_otaku_user_name');
    currentAccountId = null; currentUserName = ''; notifyListeners();
  }

  Future<bool> changeMyName(String newName) async {
    if (currentAccountId == null || newName.trim().isEmpty) return false;
    try {
      await supabase.from('players').update({'channel_name': newName.trim()}).eq('account_id', currentAccountId!);
      for (final p in players) { if (parseInt(p['account_id']) == currentAccountId) p['channel_name'] = newName.trim(); }
      notifyListeners(); return true;
    } catch (e) { return false; }
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
      await loadPoll(); await loadQuizQuestions(); await loadImportantNews();
      await loadGallery(); await loadPosts(); await loadUserRewards();
      await loadUnreadMessagesCount(); await loadSavedPosts();
      await loadFollowStats(); await loadCommentLikes(); await loadStories();
      if (_isAdmin) {
        final msgData = await supabase.from('messages').select().order('created_at', ascending: false); messages = List<Map<String, dynamic>>.from(msgData);
        final reqData = await supabase.from('purchase_requests').select().order('created_at', ascending: false); purchaseRequests = List<Map<String, dynamic>>.from(reqData);
        final quizData = await supabase.from('quiz_results').select().order('created_at', ascending: false); quizResults = List<Map<String, dynamic>>.from(quizData);
        final compData = await supabase.from('complaints').select().order('created_at', ascending: false); complaints = List<Map<String, dynamic>>.from(compData);
      } else { messages = []; purchaseRequests = []; quizResults = []; complaints = []; }
    } catch (e) { debugPrint('Load data error: $e'); }
    loading = false; notifyListeners();
  }

  Future<void> loadPlayers() async { try { final result = await supabase.from('players').select().order('points', ascending: false); players = List<Map<String, dynamic>>.from(result); notifyListeners(); } catch (e) {} }
  Future<void> loadPosts() async { try { final result = await supabase.from('posts').select().order('created_at', ascending: false); posts = List<Map<String, dynamic>>.from(result); await _loadPostInteractions(); notifyListeners(); } catch (e) {} }

  Future<void> _loadPostInteractions() async {
    try {
      final likes = await supabase.from('post_likes').select();
      postLikeCounts.clear(); likedPosts.clear();
      for (final item in likes) { final id = item['post_id']; postLikeCounts[id] = (postLikeCounts[id] ?? 0) + 1; if (parseInt(item['account_id']) == currentAccountId) likedPosts.add(id.toString()); }
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
    try { final result = await supabase.from('post_comments').select().eq('post_id', postId).order('created_at', ascending: true); return List<Map<String, dynamic>>.from(result); } catch (e) { return []; }
  }

  Future<bool> addPostComment(dynamic postId, String text, {String? replyTo, File? imageFile}) async {
    if ((text.trim().isEmpty && imageFile == null) || currentAccountId == null) return false;
    try {
      String? imageUrl;
      if (imageFile != null) imageUrl = await uploadGeneralImage(imageFile, 'comments');
      await supabase.from('post_comments').insert({
        'post_id': postId, 'account_id': currentAccountId, 'user_name': currentDisplayName, 'comment_text': text.trim(), 'reply_to': replyTo, 'image_url': imageUrl,
      });
      postCommentCounts[postId] = (postCommentCounts[postId] ?? 0) + 1; notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<String?> addPost(String content, File? imageFile, {File? videoFile}) async {
    if (currentAccountId == null) return 'لم يتم تسجيل الدخول.';
    if (content.trim().isEmpty && imageFile == null && videoFile == null) return 'المنشور فارغ.';

    if (videoFile != null) {
      final remaining = await getRemainingVideos();
      if (remaining <= 0) return 'وصلت للحد الأقصى: 5 فيديوهات شهرياً. يتجدد الشهر القادم.';
    }

    try {
      String? imageUrl;
      String? videoUrl;
      if (imageFile != null) imageUrl = await uploadGeneralImage(imageFile, 'posts');
      if (videoFile != null) videoUrl = await uploadGeneralVideo(videoFile);

      await supabase.from('posts').insert({
        'account_id': currentAccountId, 'user_name': currentDisplayName, 'content': content.trim(), 'image_url': imageUrl, 'video_url': videoUrl,
      });

      if (videoFile != null) await _incrementVideoCount();
      await loadPosts();
      return null;
    } catch (e) { debugPrint('Add post error: $e'); return 'خطأ: $e'; }
  }

  Future<int> getRemainingVideos() async {
    if (currentAccountId == null) return 5;
    try {
      final player = await supabase.from('players').select('videos_this_month, video_month').eq('account_id', currentAccountId!).maybeSingle();
      if (player == null) return 5;
      final currentMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
      final storedMonth = clean(player['video_month']);
      final count = parseInt(player['videos_this_month']);
      if (storedMonth != currentMonth) return 5;
      return (5 - count).clamp(0, 5);
    } catch (e) { return 5; }
  }

  Future<void> _incrementVideoCount() async {
    if (currentAccountId == null) return;
    try {
      final currentMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
      final player = await supabase.from('players').select('videos_this_month, video_month').eq('account_id', currentAccountId!).maybeSingle();
      if (player == null) return;
      final storedMonth = clean(player['video_month']);
      final currentCount = parseInt(player['videos_this_month']);
      final newCount = (storedMonth == currentMonth) ? currentCount + 1 : 1;
      await supabase.from('players').update({'videos_this_month': newCount, 'video_month': currentMonth}).eq('account_id', currentAccountId!);
      for (final p in players) { if (parseInt(p['account_id']) == currentAccountId) { p['videos_this_month'] = newCount; p['video_month'] = currentMonth; } }
      notifyListeners();
    } catch (e) { debugPrint('Increment video error: $e'); }
  }

  Future<bool> deletePost(dynamic id) async {
    if (currentAccountId == null) return false;
    try { final post = posts.firstWhere((p) => p['id'] == id, orElse: () => {}); if (parseInt(post['account_id']) != currentAccountId && !_isAdmin) return false; await supabase.from('posts').delete().eq('id', id); await loadPosts(); return true; } catch (e) { return false; }
  }

  // ================= STORIES =================
  Future<void> loadStories() async {
    try {
      final result = await supabase.from('stories').select().order('created_at', ascending: false);
      stories = List<Map<String, dynamic>>.from(result);
      notifyListeners();
    } catch (e) { debugPrint('Load stories error: $e'); }
  }

  Future<bool> addStory(File imageFile) async {
    if (currentAccountId == null) return false;
    try {
      final ext = safeExtension(imageFile.path);
      final path = 'stories/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('news-images').upload(path, imageFile);
      final url = supabase.storage.from('news-images').getPublicUrl(path);
      final expires = DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
      await supabase.from('stories').insert({'account_id': currentAccountId, 'user_name': currentDisplayName, 'image_url': url, 'expires_at': expires});
      await loadStories();
      return true;
    } catch (e) { debugPrint('Add story error: $e'); return false; }
  }

  Future<void> markStoryViewed(dynamic storyId) async {
    _viewedStoryIds.add(storyId.toString());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('mr_otaku_viewed_stories', _viewedStoryIds.toList());
    } catch (_) {}
    notifyListeners();
  }

  // ================= FOLLOWERS =================
  Future<List<Map<String, dynamic>>> getFollowers(int accountId) async {
    try {
      final result = await supabase.from('follows').select('follower_id').eq('following_id', accountId);
      final ids = result.map((e) => parseInt(e['follower_id'])).toList();
      return players.where((p) => ids.contains(parseInt(p['account_id']))).toList();
    } catch (e) { return []; }
  }

  Future<List<Map<String, dynamic>>> getFollowing(int accountId) async {
    try {
      final result = await supabase.from('follows').select('following_id').eq('follower_id', accountId);
      final ids = result.map((e) => parseInt(e['following_id'])).toList();
      return players.where((p) => ids.contains(parseInt(p['account_id']))).toList();
    } catch (e) { return []; }
  }

  // ================= PRIVATE MESSAGES =================
  Future<void> loadPrivateMessages(int otherUserId) async {
    if (currentAccountId == null) return;
    try {
      final result = await supabase.from('private_messages').select().or('and(sender_id.eq.$currentAccountId,receiver_id.eq.$otherUserId),and(sender_id.eq.$otherUserId,receiver_id.eq.$currentAccountId)').order('created_at', ascending: true);
      privateMessages = List<Map<String, dynamic>>.from(result);
      await supabase.from('private_messages').update({'is_read': true}).eq('receiver_id', currentAccountId!).eq('sender_id', otherUserId).eq('is_read', false);
      unreadMessageCounts.remove(otherUserId); notifyListeners();
    } catch (e) {}
  }

  Future<bool> sendPrivateMessage(int receiverId, String message) async {
    if (currentAccountId == null || message.trim().isEmpty) return false;
    try { await supabase.from('private_messages').insert({'sender_id': currentAccountId, 'sender_name': currentDisplayName, 'receiver_id': receiverId, 'message': message.trim()}); return true; } catch (e) { return false; }
  }

  Future<void> loadUnreadMessagesCount() async {
    if (currentAccountId == null) return;
    try {
      final result = await supabase.from('private_messages').select('sender_id').eq('receiver_id', currentAccountId!).eq('is_read', false);
      unreadMessageCounts.clear();
      for (final row in result) { final senderId = parseInt(row['sender_id']); if (senderId > 0) { unreadMessageCounts[senderId] = (unreadMessageCounts[senderId] ?? 0) + 1; } }
      notifyListeners();
    } catch (e) {}
  }

  Future<void> loadUserRewards() async {
    if (currentAccountId == null) return;
    try { final result = await supabase.from('user_rewards').select().eq('account_id', currentAccountId!); userRewards = List<Map<String, dynamic>>.from(result); notifyListeners(); } catch (e) {}
  }
  Future<bool> claimReward(String rewardName, String rewardIcon) async { if (currentAccountId == null) return false; try { await supabase.from('user_rewards').insert({'account_id': currentAccountId, 'reward_name': rewardName, 'reward_icon': rewardIcon}); await loadUserRewards(); return true; } catch (e) { return false; } }
  bool hasReward(String rewardName) => userRewards.any((r) => r['reward_name'] == rewardName);

  Future<void> loadImportantNews() async {
    try { final result = await supabase.from('important_news').select().order('updated_at', ascending: false).limit(1).maybeSingle(); if (result == null) { importantNews = ''; importantNewsUpdatedAt = ''; } else { importantNews = clean(result['content']); importantNewsUpdatedAt = clean(result['updated_at']); } } catch (e) {}
  }
  Future<bool> updateImportantNews(String content) async { if (!_isAdmin) return false; try { await supabase.from('important_news').delete().gte('id', 0); await supabase.from('important_news').insert({'content': content.trim(), 'updated_at': DateTime.now().toIso8601String()}); await loadImportantNews(); notifyListeners(); return true; } catch (e) { return false; } }
  Future<bool> clearImportantNews() async { if (!_isAdmin) return false; try { await supabase.from('important_news').delete().gte('id', 0); importantNews = ''; importantNewsUpdatedAt = ''; notifyListeners(); return true; } catch (e) { return false; } }

  Future<void> loadGallery() async { try { final result = await supabase.from('gallery').select().order('created_at', ascending: false); gallery = List<Map<String, dynamic>>.from(result); } catch (e) { gallery = []; } notifyListeners(); }
  Future<String?> addGalleryImage(File imageFile, {String caption = ''}) async { if (currentAccountId == null) return 'لم يتم تسجيل الدخول.'; try { final ext = safeExtension(imageFile.path); final path = 'gallery/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$ext'; await supabase.storage.from('news-images').upload(path, imageFile); final url = supabase.storage.from('news-images').getPublicUrl(path); await supabase.from('gallery').insert({'account_id': currentAccountId, 'user_name': currentDisplayName, 'image_url': url, 'caption': caption.trim()}); await loadGallery(); return null; } catch (e) { return 'خطأ: $e'; } }
  Future<bool> deleteGalleryImage(dynamic id) async { if (!_isAdmin) return false; try { await supabase.from('gallery').delete().eq('id', id); await loadGallery(); return true; } catch (e) { return false; } }

  Future<bool> updateAvatar(File imageFile) async {
    if (currentAccountId == null) return false;
    try { final ext = safeExtension(imageFile.path); final path = 'avatars/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$ext'; await supabase.storage.from('news-images').upload(path, imageFile); final url = supabase.storage.from('news-images').getPublicUrl(path); await supabase.from('players').update({'avatar_url': url}).eq('account_id', currentAccountId!); for (final player in players) { if (parseInt(player['account_id']) == currentAccountId) player['avatar_url'] = url; } notifyListeners(); return true; } catch (e) { return false; }
  }

  Future<String?> uploadGeneralImage(File file, String folder) async { try { final ext = safeExtension(file.path); final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$ext'; await supabase.storage.from('news-images').upload(path, file); return supabase.storage.from('news-images').getPublicUrl(path); } catch (e) { return null; } }

  Future<String?> uploadGeneralVideo(File file) async {
    try { final ext = safeExtension(file.path); final path = 'posts/video_${DateTime.now().millisecondsSinceEpoch}.$ext'; await supabase.storage.from('news-images').upload(path, file); return supabase.storage.from('news-images').getPublicUrl(path); } catch (e) { debugPrint('Upload video error: $e'); return null; }
  }

  Future<void> loadQuizQuestions() async { try { final result = await supabase.from('quiz_questions').select().order('created_at', ascending: true); quizQuestions = List<Map<String, dynamic>>.from(result); } catch (e) { quizQuestions = []; } }
  Future<void> loadQuizResults() async { if (!_isAdmin) return; try { final result = await supabase.from('quiz_results').select().order('created_at', ascending: false); quizResults = List<Map<String, dynamic>>.from(result); notifyListeners(); } catch (e) {} }
  Future<void> saveQuizResult({required String quizType, required int correct, required int total}) async { try { await supabase.from('quiz_results').insert({'account_id': currentAccountId, 'user_name': currentDisplayName, 'quiz_type': quizType, 'correct_answers': correct, 'total_questions': total}); } catch (e) {} }
  Future<bool> addQuizQuestion({required String question, required String option1, required String option2, required String option3, required String option4, required int correctOption, String quizType = 'direct', String? imageUrl}) async { if (!_isAdmin) return false; try { await supabase.from('quiz_questions').insert({'question': question.trim(), 'option1': option1.trim(), 'option2': option2.trim(), 'option3': option3.trim(), 'option4': option4.trim(), 'correct_option': correctOption, 'quiz_type': quizType, 'image_url': imageUrl}); await loadQuizQuestions(); return true; } catch (e) { return false; } }
  Future<bool> deleteQuizQuestion(dynamic id) async { if (!_isAdmin) return false; try { await supabase.from('quiz_questions').delete().eq('id', id); await loadQuizQuestions(); return true; } catch (e) { return false; } }

  Future<void> loadLikes() async { try { final clientId = await getClientId(); final result = await supabase.from('news_likes').select('news_id, client_id'); likeCounts.clear(); likedNews.clear(); for (final item in result) { final id = item['news_id']; likeCounts[id] = (likeCounts[id] ?? 0) + 1; if (clean(item['client_id']) == clientId) likedNews.add(id.toString()); } } catch (e) {} }
  Future<bool> toggleLike(dynamic newsId) async { try { final clientId = await getClientId(); final key = newsId.toString(); if (likedNews.contains(key)) { await supabase.from('news_likes').delete().eq('news_id', newsId).eq('client_id', clientId); likedNews.remove(key); likeCounts[newsId] = max(0, (likeCounts[newsId] ?? 1) - 1); } else { await supabase.from('news_likes').insert({'news_id': newsId, 'client_id': clientId}); likedNews.add(key); likeCounts[newsId] = (likeCounts[newsId] ?? 0) + 1; } notifyListeners(); return true; } catch (e) { return false; } }
  Future<void> loadCommentCounts() async { try { final result = await supabase.from('news_comments').select('news_id'); commentCounts.clear(); for (final item in result) { final id = item['news_id']; commentCounts[id] = (commentCounts[id] ?? 0) + 1; } } catch (e) {} }
  Future<List<Map<String, dynamic>>> getComments(dynamic newsId) async { try { final result = await supabase.from('news_comments').select().eq('news_id', newsId).order('created_at', ascending: false); return List<Map<String, dynamic>>.from(result); } catch (e) { return []; } }

  // ✅ مضاف: account_id عند حفظ التعليق
  Future<bool> addComment(dynamic newsId, String userName, String text, {String? replyTo, File? imageFile}) async {
    if ((text.trim().isEmpty && imageFile == null)) return false;
    try {
      final clientId = await getClientId();
      String? imageUrl;
      if (imageFile != null) imageUrl = await uploadGeneralImage(imageFile, 'comments');
      await supabase.from('news_comments').insert({
        'news_id': newsId,
        'client_id': clientId,
        'account_id': currentAccountId,
        'user_name': currentDisplayName,
        'comment_text': text.trim(),
        'reply_to': replyTo,
        'image_url': imageUrl,
      });
      commentCounts[newsId] = (commentCounts[newsId] ?? 0) + 1; notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<void> loadCommentLikes() async {
    if (currentAccountId == null) return;
    try {
      final result = await supabase.from('comment_likes').select();
      commentLikeCounts.clear(); likedComments.clear();
      for (final row in result) {
        final key = '${row['comment_type']}_${row['comment_id']}';
        commentLikeCounts[key] = (commentLikeCounts[key] ?? 0) + 1;
        if (parseInt(row['account_id']) == currentAccountId) likedComments.add(key);
      }
      notifyListeners();
    } catch (e) {}
  }

  Future<bool> toggleCommentLike(dynamic commentId, String type) async {
    if (currentAccountId == null) return false;
    try {
      final key = '${type}_$commentId';
      if (likedComments.contains(key)) {
        await supabase.from('comment_likes').delete().eq('comment_id', commentId).eq('comment_type', type).eq('account_id', currentAccountId!);
        likedComments.remove(key); commentLikeCounts[key] = max(0, (commentLikeCounts[key] ?? 1) - 1);
      } else {
        await supabase.from('comment_likes').insert({'comment_id': commentId, 'comment_type': type, 'account_id': currentAccountId});
        likedComments.add(key); commentLikeCounts[key] = (commentLikeCounts[key] ?? 0) + 1;
      }
      notifyListeners(); return true;
    } catch (e) { return false; }
  }

  int commentLikesCount(dynamic commentId, String type) => commentLikeCounts['${type}_$commentId'] ?? 0;
  bool isCommentLiked(dynamic commentId, String type) => likedComments.contains('${type}_$commentId');

  Future<void> loadSavedPosts() async {
    if (currentAccountId == null) return;
    try { final result = await supabase.from('saved_posts').select('post_id').eq('account_id', currentAccountId!); savedPosts = List<Map<String, dynamic>>.from(result); } catch (e) {}
  }
  bool isPostSaved(dynamic postId) => savedPosts.any((s) => parseInt(s['post_id']) == parseInt(postId));
  Future<bool> toggleSavePost(dynamic postId) async {
    if (currentAccountId == null) return false;
    try {
      if (isPostSaved(postId)) { await supabase.from('saved_posts').delete().eq('post_id', postId).eq('account_id', currentAccountId!); savedPosts.removeWhere((s) => parseInt(s['post_id']) == parseInt(postId)); }
      else { await supabase.from('saved_posts').insert({'post_id': postId, 'account_id': currentAccountId}); savedPosts.add({'post_id': postId}); }
      notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<void> loadFollowStats() async {
    if (currentAccountId == null) return;
    try {
      final following = await supabase.from('follows').select('following_id').eq('follower_id', currentAccountId!);
      followingIds.clear();
      for (final row in following) { followingIds.add(parseInt(row['following_id'])); }
      myFollowingCount = following.length;
      final followers = await supabase.from('follows').select('follower_id').eq('following_id', currentAccountId!);
      myFollowersCount = followers.length;
      notifyListeners();
    } catch (e) {}
  }

  bool isFollowing(int accountId) => followingIds.contains(accountId);
  Future<bool> toggleFollow(int accountId) async {
    if (currentAccountId == null || accountId == currentAccountId) return false;
    try {
      if (followingIds.contains(accountId)) { await supabase.from('follows').delete().eq('follower_id', currentAccountId!).eq('following_id', accountId); followingIds.remove(accountId); myFollowingCount = max(0, myFollowingCount - 1); }
      else { await supabase.from('follows').insert({'follower_id': currentAccountId, 'following_id': accountId}); followingIds.add(accountId); myFollowingCount++; }
      notifyListeners(); return true;
    } catch (e) { return false; }
  }

  Future<Map<String, int>> getUserFollowStats(int accountId) async {
    try {
      final followers = await supabase.from('follows').select('follower_id').eq('following_id', accountId);
      final following = await supabase.from('follows').select('following_id').eq('follower_id', accountId);
      return {'followers': followers.length, 'following': following.length};
    } catch (e) { return {'followers': 0, 'following': 0}; }
  }

  Future<bool> submitComplaint({required String targetType, required dynamic targetId, required String reason}) async {
    if (currentAccountId == null || reason.trim().isEmpty) return false;
    try { await supabase.from('complaints').insert({'reporter_id': currentAccountId, 'reporter_name': currentDisplayName, 'target_type': targetType, 'target_id': targetId, 'reason': reason.trim(), 'status': 'pending'}); return true; } catch (e) { return false; }
  }

  Future<void> loadComplaints() async {
    if (!_isAdmin) return;
    try { final result = await supabase.from('complaints').select().order('created_at', ascending: false); complaints = List<Map<String, dynamic>>.from(result); notifyListeners(); } catch (e) {}
  }

  Future<bool> resolveComplaint(dynamic id, String status) async {
    if (!_isAdmin) return false;
    try { await supabase.from('complaints').update({'status': status}).eq('id', id); await loadComplaints(); return true; } catch (e) { return false; }
  }

  Future<String> getClientId() async { final prefs = await SharedPreferences.getInstance(); String? id = prefs.getString('mr_otaku_client_id'); if (id == null || id.isEmpty) { id = DateTime.now().microsecondsSinceEpoch.toString(); await prefs.setString('mr_otaku_client_id', id); } return id; }

  Future<void> loadNotifications() async { try { final prefs = await SharedPreferences.getInstance(); final saved = prefs.getStringList('mr_otaku_read_notifications'); _readNotifications.clear(); if (saved != null) _readNotifications.addAll(saved); final result = await supabase.from('notifications').select().order('created_at', ascending: false); notifications = List<Map<String, dynamic>>.from(result); } catch (e) {} }
  bool isNotificationRead(dynamic id) => _readNotifications.contains(id.toString());
  Future<void> markNotificationRead(dynamic id) async { final prefs = await SharedPreferences.getInstance(); _readNotifications.add(id.toString()); await prefs.setStringList('mr_otaku_read_notifications', _readNotifications.toList()); notifyListeners(); }
  Future<void> markAllNotificationsRead() async { final prefs = await SharedPreferences.getInstance(); for (final item in notifications) _readNotifications.add(item['id'].toString()); await prefs.setStringList('mr_otaku_read_notifications', _readNotifications.toList()); notifyListeners(); }
  Future<bool> addNotification(String title, String body) async { if (!_isAdmin || title.trim().isEmpty) return false; try { await supabase.from('notifications').insert({'title': title.trim(), 'body': body.trim()}); await loadNotifications(); notifyListeners(); return true; } catch (e) { return false; } }

  Future<void> loadPoll() async {
    try {
      final polls = await supabase.from('polls').select().eq('active', true).order('created_at', ascending: false);
      if (polls.isEmpty) { activePoll = null; activePollOptions = []; pollVoteCounts.clear(); votedPollId = null; pollVoters = []; return; }
      activePoll = Map<String, dynamic>.from(polls.first);
      final pollId = activePoll!['id'];
      final options = await supabase.from('poll_options').select().eq('poll_id', pollId).order('position', ascending: true);
      activePollOptions = List<Map<String, dynamic>>.from(options);
      final votes = await supabase.from('poll_votes').select('option_id, client_id, account_id, user_name').eq('poll_id', pollId);
      pollVoteCounts.clear(); pollVoters = [];
      final clientId = await getClientId(); votedPollId = null;
      for (final vote in votes) { final optionId = vote['option_id']; pollVoteCounts[optionId] = (pollVoteCounts[optionId] ?? 0) + 1; if (clean(vote['client_id']) == clientId) votedPollId = pollId.toString(); pollVoters.add({'option_id': optionId, 'account_id': vote['account_id'], 'user_name': clean(vote['user_name'])}); }
    } catch (e) {}
  }
  bool get hasVotedInActivePoll => activePoll != null && votedPollId == clean(activePoll!['id']);
  int get totalPollVotes => pollVoteCounts.values.fold(0, (a, b) => a + b);
  double getPollPercentage(dynamic optionId) => totalPollVotes == 0 ? 0 : (pollVoteCounts[optionId] ?? 0) / totalPollVotes * 100;
  List<Map<String, dynamic>> votersForOption(dynamic optionId) => pollVoters.where((v) => v['option_id'] == optionId).toList();
  Future<bool> votePoll(dynamic optionId) async { if (activePoll == null || hasVotedInActivePoll) return false; try { final clientId = await getClientId(); await supabase.from('poll_votes').insert({'poll_id': activePoll!['id'], 'option_id': optionId, 'client_id': clientId, 'account_id': currentAccountId, 'user_name': currentDisplayName}); votedPollId = clean(activePoll!['id']); pollVoteCounts[optionId] = (pollVoteCounts[optionId] ?? 0) + 1; pollVoters.add({'option_id': optionId, 'account_id': currentAccountId, 'user_name': currentDisplayName}); notifyListeners(); return true; } catch (e) { return false; } }
  Future<bool> createPoll(String question, List<String> options) async { if (!_isAdmin || question.trim().isEmpty || options.length < 2) return false; try { await supabase.from('polls').update({'active': false}).eq('active', true); final poll = await supabase.from('polls').insert({'question': question.trim(), 'active': true}).select().single(); for (int i = 0; i < options.length; i++) { if (options[i].trim().isEmpty) continue; await supabase.from('poll_options').insert({'poll_id': poll['id'], 'option_text': options[i].trim(), 'position': i}); } await loadPoll(); return true; } catch (e) { return false; } }

  Future<bool> addNews(String title, String description, {File? imageFile}) async { if (!_isAdmin || title.trim().isEmpty) return false; try { String? imageUrl; if (imageFile != null) { final ext = safeExtension(imageFile.path); final path = 'news_${DateTime.now().millisecondsSinceEpoch}.$ext'; await supabase.storage.from('news-images').upload(path, imageFile); imageUrl = supabase.storage.from('news-images').getPublicUrl(path); } await supabase.from('news').insert({'title': title.trim(), 'description': description.trim(), 'image_url': imageUrl}); await loadData(); return true; } catch (e) { return false; } }
  Future<bool> deleteNews(dynamic id) async { if (!_isAdmin) return false; try { await supabase.from('news').delete().eq('id', id); await loadData(); return true; } catch (e) { return false; } }

  Future<bool> addPlayer(String name, int points, {int? accountId}) async { if (!_isAdmin || name.trim().isEmpty) return false; try { if (accountId != null) { final exists = await supabase.from('players').select('id').eq('account_id', accountId).maybeSingle(); if (exists != null) return false; } await supabase.from('players').insert({'name': name.trim(), 'points': max(0, points), if (accountId != null) 'account_id': accountId}); await loadData(); return true; } catch (e) { return false; } }
  Future<bool> updatePlayer(dynamic id, String name, int points, {int? accountId}) async { if (!_isAdmin || name.trim().isEmpty) return false; try { if (accountId != null) { final existing = await supabase.from('players').select('id').eq('account_id', accountId).maybeSingle(); if (existing != null && clean(existing['id']) != clean(id)) return false; } await supabase.from('players').update({'name': name.trim(), 'points': max(0, points), 'account_id': accountId}).eq('id', id); await loadData(); return true; } catch (e) { return false; } }
  Future<bool> deletePlayer(dynamic id) async { if (!_isAdmin) return false; try { await supabase.from('players').delete().eq('id', id); await loadData(); return true; } catch (e) { return false; } }

  Future<bool> addLatest(String title, String description) async { if (!_isAdmin || title.trim().isEmpty) return false; try { await supabase.from('latest').insert({'title': title.trim(), 'description': description.trim()}); await loadData(); return true; } catch (e) { return false; } }
  Future<bool> deleteLatest(dynamic id) async { if (!_isAdmin) return false; try { await supabase.from('latest').delete().eq('id', id); await loadData(); return true; } catch (e) { return false; } }
  Future<bool> sendMessage(String name, String message) async { if (message.trim().isEmpty) return false; try { await supabase.from('messages').insert({'name': currentDisplayName, 'message': message.trim()}); return true; } catch (e) { return false; } }
  Future<bool> deleteMessage(dynamic id) async { if (!_isAdmin) return false; try { await supabase.from('messages').delete().eq('id', id); await loadData(); return true; } catch (e) { return false; } }

  Future<bool> approvePurchase(Map<String, dynamic> request) async { if (!_isAdmin || request['status'] != 'pending') return false; try { final playerId = request['player_id']; final cost = parseInt(request['cost']); final player = await supabase.from('players').select().eq('id', playerId).maybeSingle(); if (player == null) return false; final points = parseInt(player['points']); if (points < cost) return false; await supabase.from('players').update({'points': points - cost}).eq('id', playerId); await supabase.from('purchase_requests').update({'status': 'approved'}).eq('id', request['id']); await loadData(); return true; } catch (e) { return false; } }
  Future<bool> rejectPurchase(dynamic id) async { if (!_isAdmin) return false; try { await supabase.from('purchase_requests').update({'status': 'rejected'}).eq('id', id); await loadData(); return true; } catch (e) { return false; } }
}