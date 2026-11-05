import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

// استيراد الملفات التي أنشأتها
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

  // 🌟 القوائم الجديدة (المنشورات، الرسائل الخاصة، الجوائز)
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

  // ===================== الحساب =====================

  Future<void> loadLocalAccount() async {
    final prefs = await SharedPreferences.getInstance();
    currentAccountId = int.tryParse(prefs.getString('mr_otaku_account_id') ?? '');
    currentUserName = prefs.getString('mr_otaku_user_name')?.trim() ?? '';
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

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mr_otaku_account_id', accountId.toString());
      await prefs.setString('mr_otaku_user_name', savedName);

      currentAccountId = accountId;
      currentUserName = savedName;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> logoutAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mr_otaku_account_id');
    await prefs.remove('mr_otaku_user_name');
    currentAccountId = null;
    currentUserName = '';
    notifyListeners();
  }

  // ===================== تحميل البيانات الأساسية =====================

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
      await loadPosts();          // 🌟 تحميل المنشورات
      await loadUserRewards();    // 🌟 تحميل الجوائز

      if (_isAdmin) {
        final messagesData = await supabase.from('messages').select().order('created_at', ascending: false);
        messages = List<Map<String, dynamic>>.from(messagesData);

        final requestsData = await supabase.from('purchase_requests').select().order('created_at', ascending: false);
        purchaseRequests = List<Map<String, dynamic>>.from(requestsData);

        final quizResultsData = await supabase.from('quiz_results').select().order('created_at', ascending: false);
        quizResults = List<Map<String, dynamic>>.from(quizResultsData);
      } else {
        messages = []; purchaseRequests = []; quizResults = [];
      }
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
      notifyListeners();
    } catch (e) {
      debugPrint('Load players error: $e');
    }
  }

  // ===================== 🌟 ميزات المنشورات (تويتر) =====================

  Future<void> loadPosts() async {
    try {
      final result = await supabase.from('posts').select().order('created_at', ascending: false);
      posts = List<Map<String, dynamic>>.from(result);
      notifyListeners();
    } catch (e) {
      debugPrint('Load posts error: $e');
    }
  }

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

  Future<bool> deletePost(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('posts').delete().eq('id', id);
      await loadPosts();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===================== 🌟 ميزات الرسائل الخاصة =====================

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
      debugPrint('Load private messages error: $e');
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
      debugPrint('Send private message error: $e');
      return false;
    }
  }

  // ===================== 🌟 ميزات الجوائز =====================

  Future<void> loadUserRewards() async {
    if (currentAccountId == null) return;
    try {
      final result = await supabase.from('user_rewards').select().eq('account_id', currentAccountId!);
      userRewards = List<Map<String, dynamic>>.from(result);
      notifyListeners();
    } catch (e) {
      debugPrint('Load rewards error: $e');
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

  bool hasReward(String rewardName) {
    return userRewards.any((r) => r['reward_name'] == rewardName);
  }

  // ===================== الدوال القديمة (الخبر، المعرض، الدردشة، الأسئلة) =====================

  Future<void> loadImportantNews() async {
    try {
      final result = await supabase.from('important_news').select().order('updated_at', ascending: false).limit(1).maybeSingle();
      if (result == null) { importantNews = ''; importantNewsUpdatedAt = ''; }
      else { importantNews = clean(result['content']); importantNewsUpdatedAt = clean(result['updated_at']); }
    } catch (e) { debugPrint('Load important news error: $e'); }
  }

  Future<void> loadGallery() async {
    try {
      final result = await supabase.from('gallery').select().order('created_at', ascending: false);
      gallery = List<Map<String, dynamic>>.from(result);
    } catch (e) { gallery = []; }
    notifyListeners();
  }

  Future<String?> addGalleryImage(File imageFile, {String caption = ''}) async {
    if (currentAccountId == null) return 'لم يتم تسجيل الدخول.';
    try {
      final extension = safeExtension(imageFile.path);
      final path = 'gallery/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await supabase.storage.from('news-images').upload(path, imageFile, fileOptions: const FileOptions(upsert: false));
      final imageUrl = supabase.storage.from('news-images').getPublicUrl(path);
      await supabase.from('gallery').insert({
        'account_id': currentAccountId, 'user_name': currentUserName, 'image_url': imageUrl, 'caption': caption.trim(),
      });
      await loadGallery();
      return null;
    } catch (e) { return 'خطأ: $e'; }
  }

  Future<bool> deleteGalleryImage(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('gallery').delete().eq('id', id);
      await loadGallery();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> updateAvatar(File imageFile) async {
    if (currentAccountId == null) return false;
    try {
      final extension = safeExtension(imageFile.path);
      final path = 'avatars/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await supabase.storage.from('news-images').upload(path, imageFile, fileOptions: const FileOptions(upsert: false));
      final url = supabase.storage.from('news-images').getPublicUrl(path);
      await supabase.from('players').update({'avatar_url': url}).eq('account_id', currentAccountId!);
      for (final player in players) {
        if (toInt(player['account_id']) == currentAccountId) player['avatar_url'] = url;
      }
      notifyListeners();
      return true;
    } catch (e) { return false; }
  }

  Future<String?> uploadGeneralImage(File file, String folder) async {
    try {
      final extension = safeExtension(file.path);
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$extension';
      await supabase.storage.from('news-images').upload(path, file, fileOptions: const FileOptions(upsert: false));
      return supabase.storage.from('news-images').getPublicUrl(path);
    } catch (e) { return null; }
  }

  Future<void> loadPublicChat() async {
    try {
      final result = await supabase.from('public_chat').select().order('created_at', ascending: false).limit(100);
      publicChat = List<Map<String, dynamic>>.from(result);
    } catch (e) { publicChat = []; }
  }

  Future<bool> sendPublicChat(String message, {File? imageFile}) async {
    if (message.trim().isEmpty && imageFile == null) return false;
    try {
      String? imageUrl;
      if (imageFile != null) imageUrl = await uploadGeneralImage(imageFile, 'chat');
      await supabase.from('public_chat').insert({
        'account_id': currentAccountId, 'user_name': currentUserName, 'message': message.trim(), 'image_url': imageUrl,
      });
      await loadPublicChat();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> deletePublicChat(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('public_chat').delete().eq('id', id);
      await loadPublicChat();
      return true;
    } catch (e) { return false; }
  }

  Future<void> loadQuizQuestions() async {
    try {
      final result = await supabase.from('quiz_questions').select().order('created_at', ascending: true);
      quizQuestions = List<Map<String, dynamic>>.from(result);
    } catch (e) { quizQuestions = []; }
  }

  Future<void> loadQuizResults() async {
    if (!_isAdmin) return;
    try {
      final result = await supabase.from('quiz_results').select().order('created_at', ascending: false);
      quizResults = List<Map<String, dynamic>>.from(result);
      notifyListeners();
    } catch (e) { debugPrint('Quiz results error: $e'); }
  }

  Future<void> saveQuizResult({required String quizType, required int correct, required int total}) async {
    try {
      await supabase.from('quiz_results').insert({
        'account_id': currentAccountId, 'user_name': currentUserName, 'quiz_type': quizType, 'correct_answers': correct, 'total_questions': total,
      });
    } catch (e) { debugPrint('Save quiz result error: $e'); }
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
    } catch (e) { debugPrint('Likes error: $e'); }
  }

  Future<bool> toggleLike(dynamic newsId) async {
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
      return true;
    } catch (e) { return false; }
  }

  Future<void> loadCommentCounts() async {
    try {
      final result = await supabase.from('news_comments').select('news_id');
      commentCounts.clear();
      for (final item in result) {
        final id = item['news_id'];
        commentCounts[id] = (commentCounts[id] ?? 0) + 1;
      }
    } catch (e) { debugPrint('Comment count error: $e'); }
  }

  Future<List<Map<String, dynamic>>> getComments(dynamic newsId) async {
    try {
      final result = await supabase.from('news_comments').select().eq('news_id', newsId).order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) { return []; }
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
    } catch (e) { return false; }
  }

  Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('mr_otaku_client_id');
    if (id == null || id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      await prefs.setString('mr_otaku_client_id', id);
    }
    return id;
  }

  Future<void> loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('mr_otaku_read_notifications');
      _readNotifications.clear();
      if (saved != null) _readNotifications.addAll(saved);

      final result = await supabase.from('notifications').select().order('created_at', ascending: false);
      notifications = List<Map<String, dynamic>>.from(result);
    } catch (e) { debugPrint('Notifications error: $e'); }
  }

  bool isNotificationRead(dynamic id) => _readNotifications.contains(id.toString());

  Future<void> markNotificationRead(dynamic id) async {
    final prefs = await SharedPreferences.getInstance();
    _readNotifications.add(id.toString());
    await prefs.setStringList('mr_otaku_read_notifications', _readNotifications.toList());
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    final prefs = await SharedPreferences.getInstance();
    for (final item in notifications) { _readNotifications.add(item['id'].toString()); }
    await prefs.setStringList('mr_otaku_read_notifications', _readNotifications.toList());
    notifyListeners();
  }

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
      final clientId = await getClientId();
      votedPollId = null;
      for (final vote in votes) {
        final optionId = vote['option_id'];
        pollVoteCounts[optionId] = (pollVoteCounts[optionId] ?? 0) + 1;
        if (clean(vote['client_id']) == clientId) votedPollId = pollId.toString();
        pollVoters.add({'option_id': optionId, 'account_id': vote['account_id'], 'user_name': clean(vote['user_name'])});
      }
    } catch (e) { debugPrint('Poll load error: $e'); }
  }

  bool get hasVotedInActivePoll => activePoll != null && votedPollId == clean(activePoll!['id']);
  int get totalPollVotes => pollVoteCounts.values.fold(0, (a, b) => a + b);
  double getPollPercentage(dynamic optionId) => totalPollVotes == 0 ? 0 : (pollVoteCounts[optionId] ?? 0) / totalPollVotes * 100;
  List<Map<String, dynamic>> votersForOption(dynamic optionId) => pollVoters.where((v) => v['option_id'] == optionId).toList();

  Future<bool> votePoll(dynamic optionId) async {
    if (activePoll == null || hasVotedInActivePoll) return false;
    try {
      final clientId = await getClientId();
      await supabase.from('poll_votes').insert({
        'poll_id': activePoll!['id'], 'option_id': optionId, 'client_id': clientId, 'account_id': currentAccountId, 'user_name': currentUserName,
      });
      votedPollId = clean(activePoll!['id']);
      pollVoteCounts[optionId] = (pollVoteCounts[optionId] ?? 0) + 1;
      pollVoters.add({'option_id': optionId, 'account_id': currentAccountId, 'user_name': currentUserName});
      notifyListeners();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> createPoll(String question, List<String> options) async {
    if (!_isAdmin || question.trim().isEmpty || options.length < 2) return false;
    try {
      await supabase.from('polls').update({'active': false}).eq('active', true);
      final poll = await supabase.from('polls').insert({'question': question.trim(), 'active': true}).select().single();
      for (int i = 0; i < options.length; i++) {
        if (options[i].trim().isEmpty) continue;
        await supabase.from('poll_options').insert({'poll_id': poll['id'], 'option_text': options[i].trim(), 'position': i});
      }
      await loadPoll();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> addQuizQuestion({
    required String question, required String option1, required String option2, required String option3, required String option4,
    required int correctOption, String quizType = 'direct', String? imageUrl,
  }) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('quiz_questions').insert({
        'question': question.trim(), 'option1': option1.trim(), 'option2': option2.trim(), 'option3': option3.trim(), 'option4': option4.trim(),
        'correct_option': correctOption, 'quiz_type': quizType, 'image_url': imageUrl,
      });
      await loadQuizQuestions();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> deleteQuizQuestion(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('quiz_questions').delete().eq('id', id);
      await loadQuizQuestions();
      return true;
    } catch (e) { return false; }
  }

  Future<String?> uploadQuizImage(File file) async {
    if (!_isAdmin) return null;
    try {
      final extension = safeExtension(file.path);
      final path = 'quiz/${DateTime.now().millisecondsSinceEpoch}.$extension';
      await supabase.storage.from('news-images').upload(path, file, fileOptions: const FileOptions(upsert: false));
      return supabase.storage.from('news-images').getPublicUrl(path);
    } catch (e) { return null; }
  }

  Future<bool> addNews(String title, String description, {File? imageFile}) async {
    if (!_isAdmin || title.trim().isEmpty) return false;
    try {
      String? imageUrl;
      if (imageFile != null) {
        final extension = safeExtension(imageFile.path);
        final path = 'news_${DateTime.now().millisecondsSinceEpoch}.$extension';
        await supabase.storage.from('news-images').upload(path, imageFile, fileOptions: const FileOptions(upsert: false));
        imageUrl = supabase.storage.from('news-images').getPublicUrl(path);
      }
      await supabase.from('news').insert({'title': title.trim(), 'description': description.trim(), 'image_url': imageUrl});
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> deleteNews(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('news').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> addPlayer(String name, int points, {int? accountId}) async {
    if (!_isAdmin || name.trim().isEmpty) return false;
    try {
      if (accountId != null) {
        final exists = await supabase.from('players').select('id').eq('account_id', accountId).maybeSingle();
        if (exists != null) return false;
      }
      await supabase.from('players').insert({'name': name.trim(), 'points': max(0, points), if (accountId != null) 'account_id': accountId});
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> updatePlayer(dynamic id, String name, int points, {int? accountId}) async {
    if (!_isAdmin || name.trim().isEmpty) return false;
    try {
      if (accountId != null) {
        final existing = await supabase.from('players').select('id').eq('account_id', accountId).maybeSingle();
        if (existing != null && clean(existing['id']) != clean(id)) return false;
      }
      await supabase.from('players').update({'name': name.trim(), 'points': max(0, points), 'account_id': accountId}).eq('id', id);
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> deletePlayer(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('players').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> addLatest(String title, String description) async {
    if (!_isAdmin || title.trim().isEmpty) return false;
    try {
      await supabase.from('latest').insert({'title': title.trim(), 'description': description.trim()});
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> deleteLatest(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('latest').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> sendMessage(String name, String message) async {
    if (message.trim().isEmpty) return false;
    try {
      await supabase.from('messages').insert({
        'name': currentUserName.trim().isNotEmpty ? currentUserName : name.trim().isEmpty ? 'مستخدم' : name.trim(),
        'message': message.trim(),
      });
      return true;
    } catch (e) { return false; }
  }

  Future<bool> deleteMessage(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('messages').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> createPurchaseRequest(dynamic playerId, String itemType, int cost) async {
    try {
      await supabase.from('purchase_requests').insert({'player_id': playerId, 'item_type': itemType, 'cost': cost, 'status': 'pending'});
      return true;
    } catch (e) { return false; }
  }

  Future<bool> approvePurchase(Map<String, dynamic> request) async {
    if (!_isAdmin || request['status'] != 'pending') return false;
    try {
      final playerId = request['player_id'];
      final cost = toInt(request['cost']);
      final player = await supabase.from('players').select().eq('id', playerId).maybeSingle();
      if (player == null) return false;
      final points = toInt(player['points']);
      if (points < cost) return false;

      await supabase.from('players').update({'points': points - cost}).eq('id', playerId);
      await supabase.from('purchase_requests').update({'status': 'approved'}).eq('id', request['id']);
      await loadData();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> rejectPurchase(dynamic id) async {
    if (!_isAdmin) return false;
    try {
      await supabase.from('purchase_requests').update({'status': 'rejected'}).eq('id', id);
      await loadData();
      return true;
    } catch (e) { return false; }
  }
}