import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/colors.dart';
import '../core/helpers.dart';
import 'local_cache.dart';

class AppData extends ChangeNotifier {
  final supabase = Supabase.instance.client;

  // القوائم الأساسية
  List<Map<String, dynamic>> news = [];
  List<Map<String, dynamic>> players = [];
  List<Map<String, dynamic>> latest = [];
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> purchaseRequests = [];
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> quizQuestions = [];
  List<Map<String, dynamic>> quizResults = [];
  List<Map<String, dynamic>> publicChat = [];
  List<Map<String, dynamic>> gallery = [];

  // القوائم الجديدة (المنشورات، الرسائل الخاصة، الجوائز)
  List<Map<String, dynamic>> posts = [];
  List<Map<String, dynamic>> privateMessages = [];
  List<Map<String, dynamic>> userRewards = [];

  String importantNews = '';
  String importantNewsUpdatedAt = '';

  final Map<dynamic, int> likeCounts = {};
  final Set<String> likedNews = {};
  final Map<dynamic, int> commentCounts = {};

  Map<String, dynamic>? activePoll;
  List<Map<String, dynamic>> activePollOptions = [];
  List<Map<String, dynamic>> pollVoters = [];
  final Map<dynamic, int> pollVoteCounts = {};
  String? votedPollId;

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
  bool get hasQuizQuestions => quizQuestions.isNotEmpty;

  int get unreadNotificationCount => notifications.where((n) => !_readNotifications.contains(n['id'].toString())).length;

  bool get hasNewNews => news.isNotEmpty && clean(news.first['id']) != _lastSeenNewsId;
  bool get hasNewQuiz => quizQuestions.length > _lastSeenQuizCount && _lastSeenQuizCount >= 0;
  bool get hasNewGallery => gallery.length > _lastSeenGalleryCount;

  bool get hasNewImportantNews {
    if (importantNews.isEmpty) return false;
    final lastSeen = LocalCache.loadString('last_seen_important_news');
    return importantNewsUpdatedAt != lastSeen;
  }

  Map<String, dynamic>? get currentPlayer {
    if (currentAccountId == null) return null;
    for (final player in players) {
      if (toInt(player['account_id']) == currentAccountId) return player;
    }
    return null;
  }

  String get currentAvatar => clean(currentPlayer?['avatar_url']);
  int get currentPoints => toInt(currentPlayer?['points']);
  String get currentLevel => getUserLevel(currentPoints);
  BadgeInfo? get currentBadge => getCurrentBadge(currentPoints);

  Map<String, dynamic>? get leader {
    if (players.isEmpty) return null;
    final sorted = [...players];
    sorted.sort((a, b) => toInt(b['points']).compareTo(toInt(a['points'])));
    return sorted.first;
  }

  String avatarForAccount(dynamic accountId) {
    if (accountId == null) return '';
    final id = toInt(accountId);
    if (id <= 0) return '';
    for (final p in players) {
      if (toInt(p['account_id']) == id) return clean(p['avatar_url']);
    }
    return '';
  }

  String avatarForName(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return '';
    for (final p in players) {
      if (clean(p['name']).trim().toLowerCase() == n) return clean(p['avatar_url']);
    }
    return '';
  }

  Future<void> setAdminSession(bool value) async {
    _isAdmin = value;
    notifyListeners();
  }

  Future<void> markNewsSeen() async {
    if (news.isNotEmpty) {
      _lastSeenNewsId = clean(news.first['id']);
      await LocalCache.saveString('last_seen_news_id', _lastSeenNewsId);
      notifyListeners();
    }
  }

  Future<void> markQuizSeen() async {
    _lastSeenQuizCount = quizQuestions.length;
    await LocalCache.saveInt('last_seen_quiz_count', _lastSeenQuizCount);
    notifyListeners();
  }

  Future<void> markGallerySeen() async {
    _lastSeenGalleryCount = gallery.length;
    await LocalCache.saveInt('last_seen_gallery_count', _lastSeenGalleryCount);
    notifyListeners();
  }

  Future<void> markImportantNewsSeen() async {
    await LocalCache.saveString('last_seen_important_news', importantNewsUpdatedAt);
    notifyListeners();
  }

  Future<void> loadLocalAccount() async {
    currentAccountId = toInt(LocalCache.loadString('mr_otaku_account_id'));
    if (currentAccountId == 0) currentAccountId = null;
    currentUserName = LocalCache.loadString('mr_otaku_user_name') ?? '';
    _lastSeenNewsId = LocalCache.loadString('last_seen_news_id') ?? '';
    _lastSeenQuizCount = LocalCache.loadInt('last_seen_quiz_count') ?? 0;
    _lastSeenGalleryCount = LocalCache.loadInt('last_seen_gallery_count') ?? 0;
  }

  Future<bool> loginAccount(String name, int accountId) async {
    if (name.trim().isEmpty || accountId <= 0) return false;
    try {
      final player = await supabase.from('players').select().eq('account_id', accountId).maybeSingle();
      if (player == null) return false;
      final savedName = clean(player['name']).trim();
      if (savedName.toLowerCase() != name.trim().toLowerCase()) return false;

      await LocalCache.saveString('mr_otaku_account_id', accountId.toString());
      await LocalCache.saveString('mr_otaku_user_name', savedName);

      currentAccountId = accountId;
      currentUserName = savedName;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> logoutAccount() async {
    await LocalCache.remove('mr_otaku_account_id');
    await LocalCache.remove('mr_otaku_user_name');
    currentAccountId = null;
    currentUserName = '';
    notifyListeners();
  }

  // =======================================================
  // دوال التحميل (Loaders)
  // =======================================================

  Future<void> loadData() async {
    loading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        supabase.from('news').select().order('created_at', ascending: false),
        supabase.from('players').select().order('points', ascending: false),
        supabase.from('latest').select().order('created_at', ascending: false),
      ]);

      news = List<Map<String, dynamic>>.from(results[0]);
      players = List<Map<String, dynamic>>.from(results[1]);
      latest = List<Map<String, dynamic>>.from(results[2]);

      await loadLikes();
      await loadCommentCounts();
      await loadNotifications();
      await loadPoll();
      await loadQuizQuestions();
      await loadPublicChat();
      await loadImportantNews();
      await loadGallery();
      await loadPosts();
      await loadUserRewards();

      if (_isAdmin) {
        final msgData = await supabase.from('messages').select().order('created_at', ascending: false);
        messages = List<Map<String, dynamic>>.from(msgData);

        final reqData = await supabase.from('purchase_requests').select().order('created_at', ascending: false);
        purchaseRequests = List<Map<String, dynamic>>.from(reqData);

        final quizData = await supabase.from('quiz_results').select().order('created_at', ascending: false);
        quizResults = List<Map<String, dynamic>>.from(quizData);
      }

      await LocalCache.saveList('news', news);
      await LocalCache.saveList('players', players);
      await LocalCache.saveList('gallery', gallery);
      await LocalCache.saveList('posts', posts);

    } catch (e) {
      debugPrint('Load data error: $e');
    }

    loading = false;
    notifyListeners();
  }

  Future<void> loadPlayers() async {
    try {
      final result = await supabase.from('players').select().order('points', ascending: false);
      players = List<Map<String, dynamic>>.from(result);
      await LocalCache.saveList('players', players);
      notifyListeners();
    } catch (e) {
      debugPrint('Load players error: $e');
    }
  }

  Future<void> loadGallery() async {
    try {
      final result = await supabase.from('gallery').select().order('created_at', ascending: false);
      gallery = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      gallery = [];
    }
    notifyListeners();
  }

  Future<void> loadPosts() async {
    try {
      final result = await supabase.from('posts').select().order('created_at', ascending: false);
      posts = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      posts = [];
    }
    notifyListeners();
  }

  Future<void> loadUserRewards() async {
    if (currentAccountId == null) return;
    try {
      final result = await supabase.from('user_rewards').select().eq('account_id', currentAccountId!);
      userRewards = List<Map<String, dynamic>>.from(result);
      notifyListeners();
    } catch (e) {
      debugPrint('Rewards error: $e');
    }
  }

  // =======================================================
  // إضافة الميزات الجديدة (منشورات - جوائز - رسائل)
  // =======================================================

  Future<bool> addPost(String content, File? imageFile) async {
    if (currentAccountId == null || content.trim().isEmpty) return false;
    try {
      String? imageUrl;
      if (imageFile != null) {
        imageUrl = await uploadGeneralImage(imageFile, 'posts');
      }

      await supabase.from('posts').insert({
        'account_id': currentAccountId,
        'user_name': currentUserName,
        'content': content.trim(),
        'image_url': imageUrl,
      });
      await loadPosts();
      return true;
    } catch (e) {
      debugPrint('Add post error: $e');
      return false;
    }
  }

  Future<bool> claimReward(String rewardName, String rewardIcon) async {
    if (currentAccountId == null) return false;
    try {
      await supabase.from('user_rewards').insert({
        'account_id': currentAccountId,
        'reward_name': rewardName,
        'reward_icon': rewardIcon,
      });
      await loadUserRewards();
      return true;
    } catch (e) {
      debugPrint('Claim reward error: $e');
      return false;
    }
  }

  Future<bool> sendPrivateMessage(int receiverId, String message) async {
    if (currentAccountId == null || message.trim().isEmpty) return false;
    try {
      await supabase.from('private_messages').insert({
        'sender_id': currentAccountId,
        'sender_name': currentUserName,
        'receiver_id': receiverId,
        'message': message.trim(),
      });
      return true;
    } catch (e) {
      debugPrint('Private message error: $e');
      return false;
    }
  }

  Future<void> loadPrivateMessages(int otherUserId) async {
    if (currentAccountId == null) return;
    try {
      final result = await supabase.from('private_messages')
          .select()
          .or('and(sender_id.eq.$currentAccountId,receiver_id.eq.$otherUserId),and(sender_id.eq.$otherUserId,receiver_id.eq.$currentAccountId)')
          .order('created_at', ascending: true);
      privateMessages = List<Map<String, dynamic>>.from(result);
      notifyListeners();
    } catch (e) {
      debugPrint('Load messages error: $e');
    }
  }

  // =======================================================
  // الدوال القديمة (نقلناها كما هي لضمان عمل التطبيق)
  // =======================================================

  Future<void> loadImportantNews() async {
    try {
      final result = await supabase.from('important_news').select().order('updated_at', ascending: false).limit(1).maybeSingle();
      if (result == null) {
        importantNews = ''; importantNewsUpdatedAt = '';
      } else {
        importantNews = clean(result['content']);
        importantNewsUpdatedAt = clean(result['updated_at']);
      }
    } catch (_) {}
  }

  Future<String> getClientId() async {
    String? id = LocalCache.loadString('mr_otaku_client_id');
    if (id == null || id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      await LocalCache.saveString('mr_otaku_client_id', id);
    }
    return id;
  }

  Future<void> loadLikes() async {
    try {
      final clientId = await getClientId();
      final result = await supabase.from('news_likes').select('news_id, client_id');
      likeCounts.clear(); likedNews.clear();
      for (final item in result) {
        final id = item['news_id'];
        likeCounts[id] = (likeCounts[id] ?? 0) + 1;
        if (clean(item['client_id']) == clientId) likedNews.add(id.toString());
      }
    } catch (_) {}
  }

  Future<void> toggleLike(dynamic newsId) async {
    try {
      final clientId = await getClientId();
      final key = newsId.toString();
      if (likedNews.contains(key)) {
        await supabase.from('news_likes').delete().eq('news_id', newsId).eq('client_id', clientId);
        likedNews.remove(key);
        likeCounts[newsId] = max(0, (likeCounts[newsId] ?? 1) - 1);
      } else {
        await supabase.from('news_likes').insert({'news_id': newsId, 'client_id': clientId});
        likedNews.add(key);
        likeCounts[newsId] = (likeCounts[newsId] ?? 0) + 1;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadCommentCounts() async {
    try {
      final result = await supabase.from('news_comments').select('news_id');
      commentCounts.clear();
      for (final item in result) {
        final id = item['news_id'];
        commentCounts[id] = (commentCounts[id] ?? 0) + 1;
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getComments(dynamic newsId) async {
    try {
      final result = await supabase.from('news_comments').select().eq('news_id', newsId).order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(result);
    } catch (_) { return []; }
  }

  Future<bool> addComment(dynamic newsId, String userName, String text) async {
    if (text.trim().isEmpty) return false;
    try {
      final clientId = await getClientId();
      await supabase.from('news_comments').insert({
        'news_id': newsId, 'client_id': clientId, 'user_name': userName, 'comment_text': text.trim(),
      });
      commentCounts[newsId] = (commentCounts[newsId] ?? 0) + 1;
      notifyListeners();
      return true;
    } catch (_) { return false; }
  }

  Future<void> loadNotifications() async {
    try {
      final saved = LocalCache.loadList('read_notifs').map((e) => e['id'].toString()).toList();
      _readNotifications.clear(); _readNotifications.addAll(saved);
      final result = await supabase.from('notifications').select().order('created_at', ascending: false);
      notifications = List<Map<String, dynamic>>.from(result);
    } catch (_) {}
  }

  bool isNotificationRead(dynamic id) => _readNotifications.contains(id.toString());

  Future<void> markNotificationRead(dynamic id) async {
    _readNotifications.add(id.toString());
    await LocalCache.saveList('read_notifs', _readNotifications.map((e) => {'id': e}).toList());
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    for (final item in notifications) { _readNotifications.add(item['id'].toString()); }
    await LocalCache.saveList('read_notifs', _readNotifications.map((e) => {'id': e}).toList());
    notifyListeners();
  }

  Future<void> loadPoll() async {
    try {
      final polls = await supabase.from('polls').select().eq('active', true).order('created_at', ascending: false);
      if (polls.isEmpty) { activePoll = null; activePollOptions = []; return; }
      activePoll = Map<String, dynamic>.from(polls.first);
      final options = await supabase.from('poll_options').select().eq('poll_id', activePoll!['id']).order('position', ascending: true);
      activePollOptions = List<Map<String, dynamic>>.from(options);
    } catch (_) {}
  }

  Future<void> votePoll(dynamic optionId) async {
    if (activePoll == null) return;
    try {
      final clientId = await getClientId();
      await supabase.from('poll_votes').insert({
        'poll_id': activePoll!['id'], 'option_id': optionId, 'client_id': clientId, 'account_id': currentAccountId, 'user_name': currentUserName,
      });
      votedPollId = clean(activePoll!['id']);
      pollVoteCounts[optionId] = (pollVoteCounts[optionId] ?? 0) + 1;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadQuizQuestions() async {
    try {
      final result = await supabase.from('quiz_questions').select().order('created_at', ascending: true);
      quizQuestions = List<Map<String, dynamic>>.from(result);
    } catch (_) {}
  }

  Future<void> saveQuizResult({required String quizType, required int correct, required int total}) async {
    try {
      await supabase.from('quiz_results').insert({
        'account_id': currentAccountId, 'user_name': currentUserName, 'quiz_type': quizType, 'correct_answers': correct, 'total_questions': total,
      });
    } catch (e) { debugPrint('Save quiz error: $e'); }
  }

  Future<void> loadPublicChat() async {
    try {
      final result = await supabase.from('public_chat').select().order('created_at', ascending: false).limit(100);
      publicChat = List<Map<String, dynamic>>.from(result);
    } catch (_) {}
  }

  Future<void> sendPublicChat(String message, {File? imageFile}) async {
    if (message.trim().isEmpty && imageFile == null) return;
    try {
      String? imageUrl;
      if (imageFile != null) imageUrl = await uploadGeneralImage(imageFile, 'chat');
      await supabase.from('public_chat').insert({
        'account_id': currentAccountId, 'user_name': currentUserName, 'message': message.trim(), 'image_url': imageUrl,
      });
      await loadPublicChat();
    } catch (_) {}
  }

  Future<bool> addGalleryImage(File imageFile, {String caption = ''}) async {
    if (currentAccountId == null) return false;
    try {
      final imageUrl = await uploadGeneralImage(imageFile, 'gallery');
      await supabase.from('gallery').insert({
        'account_id': currentAccountId, 'user_name': currentUserName, 'image_url': imageUrl, 'caption': caption.trim(),
      });
      await loadGallery();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> updateAvatar(File imageFile) async {
    if (currentAccountId == null) return false;
    try {
      final imageUrl = await uploadGeneralImage(imageFile, 'avatars');
      await supabase.from('players').update({'avatar_url': imageUrl}).eq('account_id', currentAccountId!);
      for (final player in players) {
        if (toInt(player['account_id']) == currentAccountId) player['avatar_url'] = imageUrl;
      }
      notifyListeners();
      return true;
    } catch (e) { return false; }
  }

  Future<String?> uploadGeneralImage(File file, String folder) async {
    try {
      final ext = safeExtension(file.path);
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('news-images').upload(path, file);
      return supabase.storage.from('news-images').getPublicUrl(path);
    } catch (e) { return null; }
  }

  Future<bool> deletePost(dynamic id) async {
    try {
      await supabase.from('posts').delete().eq('id', id);
      await loadPosts();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> deleteGalleryImage(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('gallery').delete().eq('id', id);
      await loadGallery();
      return true;
    } catch (e) { return false; }
  }
}