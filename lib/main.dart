import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

late final SupabaseClient supabase;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://sekchgllbimoedsjoumi.supabase.co',
    anonKey: 'sb_publishable_EZLVSUviR39RXi6OP3OqfQ_3j7vMZcU',
  );

  supabase = Supabase.instance.client;

  await LocalCache.init();

  runApp(const MrOtakuApp());

  Future.delayed(const Duration(seconds: 2), () async {
    try {
      await NotificationService.init();
      await NotificationService.registerBackgroundTask();
    } catch (e) {
      debugPrint('Notification setup error: $e');
    }
  });
}

// =======================================================
// أدوات عامة
// =======================================================

Future<void> playClickSound() async {
  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {}
}

int toInt(dynamic value) {
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double toDouble(dynamic value) {
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String clean(dynamic value) {
  return value?.toString() ?? '';
}

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
    case 'guess_character':
      return 'احزر الشخصية';
    case 'image_character':
      return 'خمن الشخصية من الصورة';
    default:
      return 'أسئلة مباشرة';
  }
}

// =======================================================
// الشارات
// =======================================================

class BadgeInfo {
  final int points;
  final String icon;
  final String name;

  const BadgeInfo({
    required this.points,
    required this.icon,
    required this.name,
  });
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
    if (points >= badge.points) {
      current = badge;
    }
  }
  return current;
}

// =======================================================
// الألوان الذهبية
// =======================================================
class AppColors {
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFE8C766);
  static const Color goldDark = Color(0xFF8B7320);
  static const Color black = Color(0xFF000000);
  static const Color cardBlack = Color(0xFF141414);
  static const Color inputBlack = Color(0xFF1A1A1A);
  static const Color borderGold = Color(0x66D4AF37);
}

// =======================================================
// جلسة المدير
// =======================================================

Future<bool> checkAdminSession() async {
  final prefs = await SharedPreferences.getInstance();
  final savedAccountId = prefs.getString('mr_otaku_account_id');

  if (savedAccountId == null || savedAccountId.isEmpty) {
    return false;
  }

  try {
    final player = await supabase
        .from('players')
        .select()
        .eq('account_id', int.tryParse(savedAccountId) ?? -1)
        .maybeSingle();

    if (player == null) return false;

    return player['is_admin'] == true;
  } catch (e) {
    debugPrint('Admin session error: $e');
    return false;
  }
}

// =======================================================
// AppData
// =======================================================

class AppData extends ChangeNotifier {
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

  bool get hasAccount =>
      currentAccountId != null && currentUserName.trim().isNotEmpty;

  bool get hasQuizQuestions => quizQuestions.isNotEmpty;

  int get unreadNotificationCount {
    return notifications.where((n) {
      return !_readNotifications.contains(n['id'].toString());
    }).length;
  }

  bool get hasNewNews {
    if (news.isEmpty) return false;
    return clean(news.first['id']) != _lastSeenNewsId;
  }

  bool get hasNewQuiz {
    return quizQuestions.length > _lastSeenQuizCount &&
        _lastSeenQuizCount >= 0;
  }

  bool get hasNewGallery {
    return gallery.length > _lastSeenGalleryCount;
  }

  bool get hasNewImportantNews {
    if (importantNews.isEmpty) return false;
    final lastSeen = LocalCache.loadString('last_seen_important_news');
    return importantNewsUpdatedAt != lastSeen;
  }

  Map<String, dynamic>? get currentPlayer {
    if (currentAccountId == null) return null;

    for (final player in players) {
      if (toInt(player['account_id']) == currentAccountId) {
        return player;
      }
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
    sorted.sort(
      (a, b) => toInt(b['points']).compareTo(toInt(a['points'])),
    );

    return sorted.first;
  }

  // ✅ جديد: إيجاد أيقونة أي حساب من قائمة players المحمّلة
  String avatarForAccount(dynamic accountId) {
    if (accountId == null) return '';
    final id = toInt(accountId);
    if (id <= 0) return '';
    for (final p in players) {
      if (toInt(p['account_id']) == id) {
        return clean(p['avatar_url']);
      }
    }
    return '';
  }

  // ✅ جديد: إيجاد أيقونة بالاسم (للتعليقات القديمة التي لا تخزّن account_id)
  String avatarForName(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return '';
    for (final p in players) {
      if (clean(p['name']).trim().toLowerCase() == n) {
        return clean(p['avatar_url']);
      }
    }
    return '';
  }

  Future<void> setAdminSession(bool value) async {
    _isAdmin = value;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mr_otaku_admin_session', value);

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
    await LocalCache.saveInt(
      'last_seen_gallery_count',
      _lastSeenGalleryCount,
    );
    notifyListeners();
  }

  Future<void> markImportantNewsSeen() async {
    await LocalCache.saveString(
      'last_seen_important_news',
      importantNewsUpdatedAt,
    );
    notifyListeners();
  }

  // ===================== الحساب =====================

  Future<void> loadLocalAccount() async {
    final prefs = await SharedPreferences.getInstance();

    final id = prefs.getString('mr_otaku_account_id');
    final name = prefs.getString('mr_otaku_user_name');

    currentAccountId = int.tryParse(id ?? '');
    currentUserName = name?.trim() ?? '';

    _lastSeenNewsId = LocalCache.loadString('last_seen_news_id') ?? '';
    _lastSeenQuizCount = LocalCache.loadInt('last_seen_quiz_count') ?? 0;
    _lastSeenGalleryCount =
        LocalCache.loadInt('last_seen_gallery_count') ?? 0;
  }

  Future<bool> loginAccount(String name, int accountId) async {
    if (name.trim().isEmpty || accountId <= 0) return false;

    try {
      final player = await supabase
          .from('players')
          .select()
          .eq('account_id', accountId)
          .maybeSingle();

      if (player == null) return false;

      final savedName = clean(player['name']).trim();

      if (savedName.toLowerCase() != name.trim().toLowerCase()) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        'mr_otaku_account_id',
        accountId.toString(),
      );
      await prefs.setString('mr_otaku_user_name', savedName);

      currentAccountId = accountId;
      currentUserName = savedName;

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Account login error: $e');
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

  // ===================== تحميل البيانات =====================

  Future<void> loadFromCache() async {
    final cachedNews = LocalCache.loadList('news');
    final cachedPlayers = LocalCache.loadList('players');
    final cachedLatest = LocalCache.loadList('latest');
    final cachedNotifs = LocalCache.loadList('notifications');
    final cachedQuiz = LocalCache.loadList('quiz_questions');
    final cachedChat = LocalCache.loadList('public_chat');
    final cachedGallery = LocalCache.loadList('gallery');

    if (cachedNews.isNotEmpty) news = cachedNews;
    if (cachedPlayers.isNotEmpty) players = cachedPlayers;
    if (cachedLatest.isNotEmpty) latest = cachedLatest;
    if (cachedNotifs.isNotEmpty) notifications = cachedNotifs;
    if (cachedQuiz.isNotEmpty) quizQuestions = cachedQuiz;
    if (cachedChat.isNotEmpty) publicChat = cachedChat;
    if (cachedGallery.isNotEmpty) gallery = cachedGallery;

    final cachedPoll = LocalCache.loadMap('active_poll');
    if (cachedPoll != null) activePoll = cachedPoll;

    importantNews = LocalCache.loadString('important_news') ?? '';
    importantNewsUpdatedAt =
        LocalCache.loadString('important_news_updated_at') ?? '';

    notifyListeners();
  }

  Future<void> _saveAllToCache() async {
    await LocalCache.saveList('news', news);
    await LocalCache.saveList('players', players);
    await LocalCache.saveList('latest', latest);
    await LocalCache.saveList('notifications', notifications);
    await LocalCache.saveList('quiz_questions', quizQuestions);
    await LocalCache.saveList('public_chat', publicChat);
    await LocalCache.saveList('gallery', gallery);
    await LocalCache.saveMap('active_poll', activePoll);

    await LocalCache.saveString('important_news', importantNews);
    await LocalCache.saveString(
      'important_news_updated_at',
      importantNewsUpdatedAt,
    );
  }

  Future<void> loadData() async {
    if (news.isEmpty) {
      await loadFromCache();
    }

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

      if (_isAdmin) {
        final messagesData = await supabase
            .from('messages')
            .select()
            .order('created_at', ascending: false);

        messages = List<Map<String, dynamic>>.from(messagesData);

        final requestsData = await supabase
            .from('purchase_requests')
            .select()
            .order('created_at', ascending: false);

        purchaseRequests =
            List<Map<String, dynamic>>.from(requestsData);

        final quizResultsData = await supabase
            .from('quiz_results')
            .select()
            .order('created_at', ascending: false);

        quizResults =
            List<Map<String, dynamic>>.from(quizResultsData);
      } else {
        messages = [];
        purchaseRequests = [];
        quizResults = [];
      }

      await _saveAllToCache();
    } catch (e) {
      debugPrint('Load data error: $e');
    }

    loading = false;
    notifyListeners();
  }

  // ✅ جديد: تحديث قائمة اللاعبين فقط (نستخدمها في الدردشة لالتقاط الأيقونات الجديدة)
  Future<void> loadPlayers() async {
    try {
      final result = await supabase
          .from('players')
          .select()
          .order('points', ascending: false);

      players = List<Map<String, dynamic>>.from(result);
      await LocalCache.saveList('players', players);
      notifyListeners();
    } catch (e) {
      debugPrint('Load players error: $e');
    }
  }

  // ===================== الخبر المهم =====================

  Future<void> loadImportantNews() async {
    try {
      final result = await supabase
          .from('important_news')
          .select()
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (result == null) {
        importantNews = '';
        importantNewsUpdatedAt = '';
      } else {
        importantNews = clean(result['content']);
        importantNewsUpdatedAt = clean(result['updated_at']);
      }
    } catch (e) {
      debugPrint('Load important news error: $e');
    }
  }

  Future<bool> updateImportantNews(String content) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('important_news').delete().gte('id', 0);

      await supabase.from('important_news').insert({
        'content': content.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      await loadImportantNews();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Update important news error: $e');
      return false;
    }
  }

  Future<bool> clearImportantNews() async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('important_news').delete().gte('id', 0);
      importantNews = '';
      importantNewsUpdatedAt = '';
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===================== Client ID =====================

  Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance();

    String? id = prefs.getString('mr_otaku_client_id');

    if (id == null || id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      await prefs.setString('mr_otaku_client_id', id);
    }

    return id;
  }

  // ===================== الإعجابات =====================

  Future<void> loadLikes() async {
    try {
      final clientId = await getClientId();

      final result = await supabase
          .from('news_likes')
          .select('news_id, client_id');

      likeCounts.clear();
      likedNews.clear();

      for (final item in result) {
        final id = item['news_id'];
        likeCounts[id] = (likeCounts[id] ?? 0) + 1;

        if (clean(item['client_id']) == clientId) {
          likedNews.add(id.toString());
        }
      }
    } catch (e) {
      debugPrint('Likes error: $e');
    }
  }

  Future<bool> toggleLike(dynamic newsId) async {
    try {
      final clientId = await getClientId();
      final key = newsId.toString();

      if (likedNews.contains(key)) {
        await supabase
            .from('news_likes')
            .delete()
            .eq('news_id', newsId)
            .eq('client_id', clientId);

        likedNews.remove(key);
        likeCounts[newsId] = max(0, (likeCounts[newsId] ?? 1) - 1);
      } else {
        await supabase.from('news_likes').insert({
          'news_id': newsId,
          'client_id': clientId,
        });

        likedNews.add(key);
        likeCounts[newsId] = (likeCounts[newsId] ?? 0) + 1;
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Toggle like error: $e');
      return false;
    }
  }

  // ===================== التعليقات =====================

  Future<void> loadCommentCounts() async {
    try {
      final result =
          await supabase.from('news_comments').select('news_id');

      commentCounts.clear();

      for (final item in result) {
        final id = item['news_id'];
        commentCounts[id] = (commentCounts[id] ?? 0) + 1;
      }
    } catch (e) {
      debugPrint('Comment count error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getComments(
    dynamic newsId,
  ) async {
    try {
      final result = await supabase
          .from('news_comments')
          .select()
          .eq('news_id', newsId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      return [];
    }
  }

  Future<bool> addComment(
    dynamic newsId,
    String userName,
    String text,
  ) async {
    if (text.trim().isEmpty) return false;

    try {
      final clientId = await getClientId();

      final name = currentUserName.trim().isNotEmpty
          ? currentUserName.trim()
          : userName.trim().isEmpty
              ? 'مستخدم'
              : userName.trim();

      await supabase.from('news_comments').insert({
        'news_id': newsId,
        'client_id': clientId,
        'user_name': name,
        'comment_text': text.trim(),
      });

      commentCounts[newsId] = (commentCounts[newsId] ?? 0) + 1;

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Add comment error: $e');
      return false;
    }
  }

  // ===================== الإشعارات =====================

  Future<void> loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('mr_otaku_read_notifications');

      _readNotifications.clear();
      if (saved != null) {
        _readNotifications.addAll(saved);
      }

      final result = await supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false);

      notifications = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Notifications error: $e');
    }
  }

  bool isNotificationRead(dynamic id) {
    return _readNotifications.contains(id.toString());
  }

  Future<void> markNotificationRead(dynamic id) async {
    final prefs = await SharedPreferences.getInstance();

    _readNotifications.add(id.toString());

    await prefs.setStringList(
      'mr_otaku_read_notifications',
      _readNotifications.toList(),
    );

    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    final prefs = await SharedPreferences.getInstance();

    for (final item in notifications) {
      _readNotifications.add(item['id'].toString());
    }

    await prefs.setStringList(
      'mr_otaku_read_notifications',
      _readNotifications.toList(),
    );

    notifyListeners();
  }

  Future<bool> addNotification(String title, String body) async {
    if (!_isAdmin || title.trim().isEmpty) return false;

    try {
      await supabase.from('notifications').insert({
        'title': title.trim(),
        'body': body.trim(),
      });

      await loadNotifications();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Add notification error: $e');
      return false;
    }
  }

  // ===================== الاستطلاع =====================

  Future<void> loadPoll() async {
    try {
      final polls = await supabase
          .from('polls')
          .select()
          .eq('active', true)
          .order('created_at', ascending: false);

      if (polls.isEmpty) {
        activePoll = null;
        activePollOptions = [];
        pollVoteCounts.clear();
        votedPollId = null;
        pollVoters = [];
        return;
      }

      activePoll = Map<String, dynamic>.from(polls.first);
      final pollId = activePoll!['id'];

      final options = await supabase
          .from('poll_options')
          .select()
          .eq('poll_id', pollId)
          .order('position', ascending: true);

      activePollOptions = List<Map<String, dynamic>>.from(options);

      final votes = await supabase
          .from('poll_votes')
          .select('option_id, client_id, account_id, user_name')
          .eq('poll_id', pollId);

      pollVoteCounts.clear();
      pollVoters = [];

      final clientId = await getClientId();
      votedPollId = null;

      for (final vote in votes) {
        final optionId = vote['option_id'];
        pollVoteCounts[optionId] =
            (pollVoteCounts[optionId] ?? 0) + 1;

        if (clean(vote['client_id']) == clientId) {
          votedPollId = pollId.toString();
        }

        pollVoters.add({
          'option_id': optionId,
          'account_id': vote['account_id'],
          'user_name': clean(vote['user_name']),
        });
      }
    } catch (e) {
      debugPrint('Poll load error: $e');
    }
  }

  bool get hasVotedInActivePoll {
    if (activePoll == null) return false;
    return votedPollId == clean(activePoll!['id']);
  }

  int get totalPollVotes {
    return pollVoteCounts.values.fold(0, (a, b) => a + b);
  }

  double getPollPercentage(dynamic optionId) {
    if (totalPollVotes == 0) return 0;
    return (pollVoteCounts[optionId] ?? 0) / totalPollVotes * 100;
  }

  List<Map<String, dynamic>> votersForOption(dynamic optionId) {
    return pollVoters
        .where((v) => v['option_id'] == optionId)
        .toList();
  }

  Future<bool> votePoll(dynamic optionId) async {
    if (activePoll == null || hasVotedInActivePoll) return false;

    try {
      final clientId = await getClientId();

      await supabase.from('poll_votes').insert({
        'poll_id': activePoll!['id'],
        'option_id': optionId,
        'client_id': clientId,
        'account_id': currentAccountId,
        'user_name': currentUserName,
      });

      votedPollId = clean(activePoll!['id']);
      pollVoteCounts[optionId] = (pollVoteCounts[optionId] ?? 0) + 1;

      pollVoters.add({
        'option_id': optionId,
        'account_id': currentAccountId,
        'user_name': currentUserName,
      });

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Vote error: $e');
      return false;
    }
  }

  Future<bool> createPoll(
    String question,
    List<String> options,
  ) async {
    if (!_isAdmin || question.trim().isEmpty || options.length < 2) {
      return false;
    }

    try {
      await supabase
          .from('polls')
          .update({'active': false})
          .eq('active', true);

      final poll = await supabase
          .from('polls')
          .insert({'question': question.trim(), 'active': true})
          .select()
          .single();

      for (int i = 0; i < options.length; i++) {
        if (options[i].trim().isEmpty) continue;

        await supabase.from('poll_options').insert({
          'poll_id': poll['id'],
          'option_text': options[i].trim(),
          'position': i,
        });
      }

      await loadPoll();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Create poll error: $e');
      return false;
    }
  }

  // ===================== الأسئلة والنتائج =====================

  Future<void> loadQuizQuestions() async {
    try {
      final result = await supabase
          .from('quiz_questions')
          .select()
          .order('created_at', ascending: true);

      quizQuestions = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Quiz load error: $e');
      quizQuestions = [];
    }
  }

  Future<void> loadQuizResults() async {
    if (!_isAdmin) return;
    try {
      final result = await supabase
          .from('quiz_results')
          .select()
          .order('created_at', ascending: false);

      quizResults = List<Map<String, dynamic>>.from(result);
      notifyListeners();
    } catch (e) {
      debugPrint('Quiz results error: $e');
    }
  }

  Future<void> saveQuizResult({
    required String quizType,
    required int correct,
    required int total,
  }) async {
    try {
      await supabase.from('quiz_results').insert({
        'account_id': currentAccountId,
        'user_name': currentUserName,
        'quiz_type': quizType,
        'correct_answers': correct,
        'total_questions': total,
      });
    } catch (e) {
      debugPrint('Save quiz result error: $e');
    }
  }

  Future<bool> addQuizQuestion({
    required String question,
    required String option1,
    required String option2,
    required String option3,
    required String option4,
    required int correctOption,
    String quizType = 'direct',
    String? imageUrl,
  }) async {
    if (!_isAdmin ||
        question.trim().isEmpty ||
        option1.trim().isEmpty ||
        option2.trim().isEmpty ||
        option3.trim().isEmpty ||
        option4.trim().isEmpty ||
        correctOption < 1 ||
        correctOption > 4) {
      return false;
    }

    try {
      await supabase.from('quiz_questions').insert({
        'question': question.trim(),
        'option1': option1.trim(),
        'option2': option2.trim(),
        'option3': option3.trim(),
        'option4': option4.trim(),
        'correct_option': correctOption,
        'quiz_type': quizType,
        'image_url': imageUrl,
      });

      await loadQuizQuestions();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Add quiz error: $e');
      return false;
    }
  }

  Future<bool> updateQuizQuestion({
    required dynamic id,
    required String question,
    required String option1,
    required String option2,
    required String option3,
    required String option4,
    required int correctOption,
    String quizType = 'direct',
    String? imageUrl,
  }) async {
    if (!_isAdmin) return false;

    try {
      await supabase
          .from('quiz_questions')
          .update({
            'question': question.trim(),
            'option1': option1.trim(),
            'option2': option2.trim(),
            'option3': option3.trim(),
            'option4': option4.trim(),
            'correct_option': correctOption,
            'quiz_type': quizType,
            'image_url': imageUrl,
          })
          .eq('id', id);

      await loadQuizQuestions();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Update quiz error: $e');
      return false;
    }
  }

  Future<bool> deleteQuizQuestion(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase
          .from('quiz_questions')
          .delete()
          .eq('id', id);

      await loadQuizQuestions();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> uploadQuizImage(File file) async {
    if (!_isAdmin) return null;

    try {
      final extension = _safeExtension(file.path);
      final path =
          'quiz/${DateTime.now().millisecondsSinceEpoch}.$extension';

      await supabase.storage.from('news-images').upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: false),
          );

      return supabase.storage.from('news-images').getPublicUrl(path);
    } catch (e) {
      debugPrint('Quiz image upload error: $e');
      return null;
    }
  }

  // ===================== معرض الصور =====================

  Future<void> loadGallery() async {
    try {
      final result = await supabase
          .from('gallery')
          .select()
          .order('created_at', ascending: false);

      gallery = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Load gallery error: $e');
      gallery = [];
    }
    // ✅ مهم جدًا: إعلام الواجهة بعد التحديث
    notifyListeners();
  }

  Future<bool> addGalleryImage(
    File imageFile, {
    String caption = '',
  }) async {
    if (currentAccountId == null) {
      debugPrint('Add gallery error: currentAccountId == null');
      return false;
    }

    try {
      final extension = _safeExtension(imageFile.path);
      final path =
          'gallery/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      // 1) رفع الصورة
      await supabase.storage.from('news-images').upload(
            path,
            imageFile,
            fileOptions: const FileOptions(upsert: false),
          );

      final imageUrl =
          supabase.storage.from('news-images').getPublicUrl(path);

      // 2) إدخال السجل
      await supabase.from('gallery').insert({
        'account_id': currentAccountId,
        'user_name': currentUserName.trim().isEmpty
            ? 'مستخدم'
            : currentUserName.trim(),
        'image_url': imageUrl,
        'caption': caption.trim(),
      });

      // 3) إعادة التحميل + إعلام الواجهة + الحفظ في الكاش
      await loadGallery();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('Add gallery error: $e');
      debugPrint('Add gallery stack: $st');
      return false;
    }
  }

  Future<bool> deleteGalleryImage(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('gallery').delete().eq('id', id);
      await loadGallery();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Delete gallery error: $e');
      return false;
    }
  }

  // ===================== الأيقونة =====================

  Future<bool> updateAvatar(File imageFile) async {
    if (currentAccountId == null) return false;

    try {
      final extension = _safeExtension(imageFile.path);
      final path =
          'avatars/${currentAccountId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      await supabase.storage.from('news-images').upload(
            path,
            imageFile,
            fileOptions: const FileOptions(upsert: false),
          );

      final url =
          supabase.storage.from('news-images').getPublicUrl(path);

      await supabase
          .from('players')
          .update({'avatar_url': url})
          .eq('account_id', currentAccountId!);

      // تحديث محلي فوري
      for (final player in players) {
        if (toInt(player['account_id']) == currentAccountId) {
          player['avatar_url'] = url;
        }
      }

      // ✅ حفظ في الكاش حتى لا يعود القديم بعد إعادة التشغيل
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('Update avatar error: $e');
      debugPrint('Update avatar stack: $st');
      return false;
    }
  }

  // ===================== الأخبار =====================

  Future<bool> addNews(
    String title,
    String description, {
    File? imageFile,
  }) async {
    if (!_isAdmin || title.trim().isEmpty) return false;

    try {
      String? imageUrl;

      if (imageFile != null) {
        final extension = _safeExtension(imageFile.path);
        final path =
            'news_${DateTime.now().millisecondsSinceEpoch}.$extension';

        await supabase.storage.from('news-images').upload(
              path,
              imageFile,
              fileOptions: const FileOptions(upsert: false),
            );

        imageUrl =
            supabase.storage.from('news-images').getPublicUrl(path);
      }

      await supabase.from('news').insert({
        'title': title.trim(),
        'description': description.trim(),
        'image_url': imageUrl,
      });

      await loadData();
      return true;
    } catch (e) {
      debugPrint('Add news error: $e');
      return false;
    }
  }

  Future<bool> deleteNews(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('news').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===================== اللاعبين =====================

  Future<bool> addPlayer(
    String name,
    int points, {
    int? accountId,
  }) async {
    if (!_isAdmin || name.trim().isEmpty) return false;

    try {
      if (accountId != null) {
        if (accountId <= 0) return false;

        final exists = await supabase
            .from('players')
            .select('id')
            .eq('account_id', accountId)
            .maybeSingle();

        if (exists != null) return false;
      }

      await supabase.from('players').insert({
        'name': name.trim(),
        'points': max(0, points),
        if (accountId != null) 'account_id': accountId,
      });

      await loadData();
      return true;
    } catch (e) {
      debugPrint('Add player error: $e');
      return false;
    }
  }

  Future<bool> updatePlayer(
    dynamic id,
    String name,
    int points, {
    int? accountId,
  }) async {
    if (!_isAdmin || name.trim().isEmpty) return false;

    try {
      if (accountId != null) {
        final existing = await supabase
            .from('players')
            .select('id')
            .eq('account_id', accountId)
            .maybeSingle();

        if (existing != null && clean(existing['id']) != clean(id)) {
          return false;
        }
      }

      await supabase
          .from('players')
          .update({
            'name': name.trim(),
            'points': max(0, points),
            'account_id': accountId,
          })
          .eq('id', id);

      await loadData();
      return true;
    } catch (e) {
      debugPrint('Update player error: $e');
      return false;
    }
  }

  Future<bool> deletePlayer(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('players').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===================== كل جديد =====================

  Future<bool> addLatest(String title, String description) async {
    if (!_isAdmin || title.trim().isEmpty) return false;

    try {
      await supabase.from('latest').insert({
        'title': title.trim(),
        'description': description.trim(),
      });

      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteLatest(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('latest').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===================== الرسائل =====================

  Future<bool> sendMessage(String name, String message) async {
    if (message.trim().isEmpty) return false;

    try {
      await supabase.from('messages').insert({
        'name': currentUserName.trim().isNotEmpty
            ? currentUserName
            : name.trim().isEmpty
                ? 'مستخدم'
                : name.trim(),
        'message': message.trim(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteMessage(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('messages').delete().eq('id', id);
      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===================== المشتريات =====================

  Future<bool> createPurchaseRequest(
    dynamic playerId,
    String itemType,
    int cost,
  ) async {
    try {
      await supabase.from('purchase_requests').insert({
        'player_id': playerId,
        'item_type': itemType,
        'cost': cost,
        'status': 'pending',
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> approvePurchase(Map<String, dynamic> request) async {
    if (!_isAdmin || request['status'] != 'pending') return false;

    try {
      final playerId = request['player_id'];
      final cost = toInt(request['cost']);

      final player = await supabase
          .from('players')
          .select()
          .eq('id', playerId)
          .maybeSingle();

      if (player == null) return false;

      final points = toInt(player['points']);
      if (points < cost) return false;

      await supabase
          .from('players')
          .update({'points': points - cost})
          .eq('id', playerId);

      await supabase
          .from('purchase_requests')
          .update({'status': 'approved'})
          .eq('id', request['id']);

      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> rejectPurchase(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase
          .from('purchase_requests')
          .update({'status': 'rejected'})
          .eq('id', id);

      await loadData();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ===================== الدردشة =====================

  Future<void> loadPublicChat() async {
    try {
      final result = await supabase
          .from('public_chat')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      publicChat = List<Map<String, dynamic>>.from(result);
    } catch (e) {
      publicChat = [];
    }
  }

  Future<bool> sendPublicChat(
    String message, {
    File? imageFile,
  }) async {
    if (message.trim().isEmpty && imageFile == null) return false;

    try {
      String? imageUrl;

      if (imageFile != null) {
        imageUrl = await uploadGeneralImage(imageFile, 'chat');
      }

      await supabase.from('public_chat').insert({
        'account_id': currentAccountId,
        'user_name': currentUserName.trim().isEmpty
            ? 'مستخدم'
            : currentUserName.trim(),
        'message': message.trim(),
        'image_url': imageUrl,
      });

      await loadPublicChat();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Send chat error: $e');
      return false;
    }
  }

  Future<bool> deletePublicChat(dynamic id) async {
    if (!_isAdmin) return false;

    try {
      await supabase.from('public_chat').delete().eq('id', id);
      await loadPublicChat();
      await _saveAllToCache();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> uploadGeneralImage(
    File file,
    String folder,
  ) async {
    try {
      final extension = _safeExtension(file.path);
      final path =
          '$folder/${DateTime.now().millisecondsSinceEpoch}.$extension';

      await supabase.storage.from('news-images').upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: false),
          );

      return supabase.storage.from('news-images').getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload general image error: $e');
      return null;
    }
  }
}

// =======================================================
// ✅ دالة مساعدة آمنة لاستخراج امتداد الملف
// =======================================================
String _safeExtension(String path) {
  final raw = path.split('.').last.toLowerCase();
  const allowed = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'bmp'];
  if (raw.length <= 5 && allowed.contains(raw)) return raw;
  return 'jpg';
}
// =======================================================
// مدير التخزين المحلي
// =======================================================
class LocalCache {
  static const String _prefix = 'mr_otaku_cache_';
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<void> saveList(
    String key,
    List<Map<String, dynamic>> data,
  ) async {
    await init();
    try {
      await _prefs!.setString('$_prefix$key', jsonEncode(data));
    } catch (_) {}
  }

  static List<Map<String, dynamic>> loadList(String key) {
    final raw = _prefs?.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMap(String key, Map<String, dynamic>? data) async {
    await init();
    try {
      if (data == null) {
        await _prefs!.remove('$_prefix$key');
      } else {
        await _prefs!.setString('$_prefix$key', jsonEncode(data));
      }
    } catch (_) {}
  }

  static Map<String, dynamic>? loadMap(String key) {
    final raw = _prefs?.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveString(String key, String? value) async {
    await init();
    try {
      if (value == null) {
        await _prefs!.remove('$_prefix$key');
      } else {
        await _prefs!.setString('$_prefix$key', value);
      }
    } catch (_) {}
  }

  static String? loadString(String key) =>
      _prefs?.getString('$_prefix$key');

  static Future<void> saveInt(String key, int? value) async {
    await init();
    try {
      if (value == null) {
        await _prefs!.remove('$_prefix$key');
      } else {
        await _prefs!.setInt('$_prefix$key', value);
      }
    } catch (_) {}
  }

  static int? loadInt(String key) => _prefs?.getInt('$_prefix$key');

  static Future<void> saveBool(String key, bool value) async {
    await init();
    try {
      await _prefs!.setBool('$_prefix$key', value);
    } catch (_) {}
  }

  static bool loadBool(String key, {bool defaultValue = false}) =>
      _prefs?.getBool('$_prefix$key') ?? defaultValue;

  static Future<void> remove(String key) async {
    await init();
    try {
      await _prefs!.remove('$_prefix$key');
    } catch (_) {}
  }
}

// =======================================================
// التطبيق
// =======================================================

class MrOtakuApp extends StatefulWidget {
  const MrOtakuApp({super.key});

  @override
  State<MrOtakuApp> createState() => _MrOtakuAppState();
}

class _MrOtakuAppState extends State<MrOtakuApp> {
  final AppData data = AppData();
  bool checking = true;

  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    try {
      await data.loadLocalAccount();
    } catch (e) {
      debugPrint('loadLocalAccount error: $e');
    }

    if (mounted) {
      setState(() {
        checking = false;
      });
    }

    Future.microtask(() async {
      try {
        final admin = await checkAdminSession();
        await data.setAdminSession(admin);
        await data.loadData();
      } catch (e) {
        debugPrint('Background load error: $e');
      }
    });
  }

  ThemeData get theme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.black,
      cardColor: AppColors.cardBlack,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        onPrimary: Colors.black,
        secondary: AppColors.gold,
        onSecondary: Colors.black,
        surface: AppColors.cardBlack,
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.gold,
        centerTitle: true,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.black,
        indicatorColor: AppColors.gold.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.all(
          const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: MaterialStateProperty.all(
          const IconThemeData(color: AppColors.gold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBlack,
        labelStyle: const TextStyle(color: AppColors.gold),
        hintStyle: TextStyle(color: AppColors.gold.withOpacity(0.5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderGold),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      cardTheme: CardTheme(
        color: AppColors.cardBlack,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          side: const BorderSide(color: AppColors.borderGold),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.gold),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.black,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.gold),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: const BorderSide(color: AppColors.gold),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gold,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.gold,
        thumbColor: AppColors.gold,
        inactiveTrackColor: AppColors.borderGold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: data,
      builder: (_, __) {
        Widget home;

        if (!data.hasAccount) {
          home = AccountSetupPage(data: data);
        } else {
          home = HomePage(data: data);
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'مستر أوتاكو',
          theme: theme,
          home: home,
        );
      },
    );
  }
}

// =======================================================
// تسجيل الدخول
// =======================================================

class AccountSetupPage extends StatefulWidget {
  final AppData data;

  const AccountSetupPage({
    super.key,
    required this.data,
  });

  @override
  State<AccountSetupPage> createState() => _AccountSetupPageState();
}

class _AccountSetupPageState extends State<AccountSetupPage> {
  final nameController = TextEditingController();
  final idController = TextEditingController();

  bool loading = false;

  Future<void> login() async {
    final name = nameController.text.trim();
    final id = int.tryParse(idController.text.trim());

    if (name.isEmpty || id == null || id <= 0) {
      showSnack(
        context,
        'أدخل اسم المستخدم ومعرف الحساب بشكل صحيح.',
      );
      return;
    }

    setState(() {
      loading = true;
    });

    await playClickSound();

    final success = await widget.data.loginAccount(name, id);

    if (!mounted) return;

    if (!success) {
      setState(() {
        loading = false;
      });
      showSnack(
        context,
        'المعرف غير موجود أو الاسم لا يطابق الحساب.',
      );
      return;
    }

    final isAdmin = await checkAdminSession();
    await widget.data.setAdminSession(isAdmin);

    if (!mounted) return;

    setState(() {
      loading = false;
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(data: widget.data),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 75,
                      color: AppColors.gold,
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'مستر أوتاكو',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'تسجيل الدخول',
                      style: TextStyle(
                        fontSize: 17,
                        color: AppColors.goldLight,
                      ),
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: idController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'معرف الحساب',
                        prefixIcon: Icon(Icons.badge),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: loading ? null : login,
                        icon: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: const Text('دخول'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'إذا لم يكن لديك حساب، اطلب من الإدارة إنشاء حساب لك.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.gold.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =======================================================
// الرئيسية
// =======================================================

class HomePage extends StatefulWidget {
  final AppData data;

  const HomePage({
    super.key,
    required this.data,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  Timer? _playersRefreshTimer;

  @override
  void initState() {
    super.initState();
    // ✅ تحديث قائمة اللاعبين كل 30 ثانية لالتقاط أيقونات جديدة
    _playersRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        await widget.data.loadPlayers();
      },
    );
  }

  @override
  void dispose() {
    _playersRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(data: widget.data),
      NewsPage(data: widget.data),
      ServicesPage(data: widget.data),
      SettingsPage(data: widget.data),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) async {
          await playClickSound();
          if (!mounted) return;

          setState(() {
            index = value;
          });

          if (value == 0) {
            await widget.data.markImportantNewsSeen();
          } else if (value == 1) {
            await widget.data.markNewsSeen();
          } else if (value == 2) {
            await widget.data.markQuizSeen();
            await widget.data.markGallerySeen();
          } else if (value == 3) {
            await widget.data.markAllNotificationsRead();
          }
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.data.hasNewImportantNews,
              backgroundColor: AppColors.gold,
              child: const Icon(Icons.home_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: widget.data.hasNewImportantNews,
              backgroundColor: AppColors.gold,
              child: const Icon(Icons.home),
            ),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.data.hasNewNews,
              backgroundColor: AppColors.gold,
              child: const Icon(Icons.newspaper_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: widget.data.hasNewNews,
              backgroundColor: AppColors.gold,
              child: const Icon(Icons.newspaper),
            ),
            label: 'الأخبار',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.data.hasNewQuiz ||
                  widget.data.hasNewGallery,
              backgroundColor: AppColors.gold,
              child: const Icon(Icons.apps_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: widget.data.hasNewQuiz ||
                  widget.data.hasNewGallery,
              backgroundColor: AppColors.gold,
              child: const Icon(Icons.apps),
            ),
            label: 'الخدمات',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: widget.data.unreadNotificationCount > 0,
              backgroundColor: AppColors.gold,
              label: Text(
                widget.data.unreadNotificationCount.toString(),
                style: const TextStyle(color: Colors.black),
              ),
              child: const Icon(Icons.settings_outlined),
            ),
            selectedIcon: const Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

// =======================================================
// الصفحة الرئيسية
// =======================================================

class HomeTab extends StatefulWidget {
  final AppData data;

  const HomeTab({
    super.key,
    required this.data,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final PageController controller = PageController();
  Timer? timer;
  int newsIndex = 0;

  @override
  void initState() {
    super.initState();

    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted ||
            widget.data.news.isEmpty ||
            !controller.hasClients) {
          return;
        }

        if (newsIndex + 1 >= widget.data.news.length) {
          newsIndex = 0;
        } else {
          newsIndex++;
        }

        if (!controller.hasClients) return;

        controller.animateToPage(
          newsIndex,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOut,
        );
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leader = widget.data.leader;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مستر أوتاكو',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await playClickSound();
              if (!mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      NotificationsPage(data: widget.data),
                ),
              );
            },
            icon: Badge(
              isLabelVisible: widget.data.unreadNotificationCount > 0,
              backgroundColor: AppColors.gold,
              label: Text(
                widget.data.unreadNotificationCount.toString(),
                style: const TextStyle(color: Colors.black),
              ),
              child: const Icon(Icons.notifications),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.data.loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.data.importantNews.trim().isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.black,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.gold, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(0.2),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.campaign,
                      color: AppColors.gold,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إعلان مهم',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.data.importantNews,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.data.importantNews.trim().isNotEmpty)
              const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.black,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.gold),
              ),
              child: const Center(
                child: Text(
                  'من تطوير برهان البريهي',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.data.news.isNotEmpty)
              _NewsCarousel(
                data: widget.data,
                controller: controller,
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 60,
                      color: AppColors.gold,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'مرحباً ${widget.data.currentUserName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('مجتمع ومسابقات وأخبار الأنمي'),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _MiniStat(
                          title: 'النقاط',
                          value: widget.data.currentPoints.toString(),
                        ),
                        const SizedBox(width: 25),
                        _MiniStat(
                          title: 'المستوى',
                          value: widget.data.currentLevel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (leader != null)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.gold,
                    backgroundImage: clean(leader['avatar_url']).isNotEmpty
                        ? NetworkImage(clean(leader['avatar_url']))
                        : null,
                    child: clean(leader['avatar_url']).isEmpty
                        ? const Icon(
                            Icons.emoji_events,
                            color: Colors.black,
                          )
                        : null,
                  ),
                  title: const Text(
                    'متصدر الأوتاكو',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                  subtitle: Text(clean(leader['name'])),
                  trailing: Text('${toInt(leader['points'])} نقطة'),
                ),
              ),
            const SizedBox(height: 16),
            if (widget.data.activePoll != null)
              PollCard(data: widget.data),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'كل جديد',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.data.latest.isEmpty)
                      const Text('لا يوجد جديد حالياً.')
                    else
                      ...widget.data.latest.take(5).map(
                            (item) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.campaign),
                              title: Text(clean(item['title'])),
                              subtitle: Text(
                                clean(item['description']),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title;
  final String value;

  const _MiniStat({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        Text(
          title,
          style: TextStyle(color: AppColors.gold.withOpacity(0.7)),
        ),
      ],
    );
  }
}

// =======================================================
// شريط الأخبار
// =======================================================

class _NewsCarousel extends StatelessWidget {
  final AppData data;
  final PageController controller;

  const _NewsCarousel({
    required this.data,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: PageView.builder(
        controller: controller,
        itemCount: data.news.length,
        itemBuilder: (context, index) {
          final item = data.news[index];
          final image = clean(item['image_url']);

          return GestureDetector(
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewsDetailsPage(
                    data: data,
                    news: item,
                  ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 4, left: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.borderGold),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image.isNotEmpty)
                    Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          color: AppColors.cardBlack,
                          child: const Icon(
                            Icons.newspaper,
                            size: 50,
                            color: AppColors.gold,
                          ),
                        );
                      },
                    )
                  else
                    Container(
                      color: AppColors.cardBlack,
                      child: const Icon(
                        Icons.newspaper,
                        size: 50,
                        color: AppColors.gold,
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black87,
                          ],
                        ),
                      ),
                      child: Text(
                        clean(item['title']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =======================================================
// تفاصيل الخبر
// =======================================================

class NewsDetailsPage extends StatelessWidget {
  final AppData data;
  final Map<String, dynamic> news;

  const NewsDetailsPage({
    super.key,
    required this.data,
    required this.news,
  });

  @override
  Widget build(BuildContext context) {
    final image = clean(news['image_url']);

    return Scaffold(
      appBar: AppBar(title: const Text('الخبر')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (image.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                image,
                height: 230,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const SizedBox(
                    height: 230,
                    child: Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 50,
                        color: AppColors.gold,
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 15),
          Text(
            clean(news['title']),
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            clean(news['description']),
            style: const TextStyle(fontSize: 17, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// استطلاع
// =======================================================

class PollCard extends StatelessWidget {
  final AppData data;

  const PollCard({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final voted = data.hasVotedInActivePoll;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'استطلاع الرأي',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              clean(data.activePoll!['question']),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 10),
            ...data.activePollOptions.map((option) {
              final id = option['id'];
              final voters = data.votersForOption(id);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton(
                      onPressed: voted
                          ? null
                          : () async {
                              await playClickSound();
                              await data.votePoll(id);
                            },
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              clean(option['option_text']),
                            ),
                          ),
                          if (voted)
                            Text(
                              '${data.getPollPercentage(id).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (data.isAdmin && voters.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: 16,
                          top: 2,
                          bottom: 6,
                        ),
                        child: Text(
                          'صوّت: ${voters.map((v) => clean(v['user_name'])).join(', ')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.gold.withOpacity(0.7),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// الأخبار
// =======================================================

class NewsPage extends StatelessWidget {
  final AppData data;

  const NewsPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأخبار')),
      body: RefreshIndicator(
        onRefresh: data.loadData,
        child: data.news.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('لا توجد أخبار حالياً.')),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: data.news.length,
                itemBuilder: (_, index) {
                  return NewsCard(
                    data: data,
                    news: data.news[index],
                  );
                },
              ),
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  final AppData data;
  final Map<String, dynamic> news;

  const NewsCard({
    super.key,
    required this.data,
    required this.news,
  });

  @override
  Widget build(BuildContext context) {
    final id = news['id'];
    final image = clean(news['image_url']);
    final liked = data.likedNews.contains(id.toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image.isNotEmpty)
            Image.network(
              image,
              width: double.infinity,
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return const SizedBox(
                  width: double.infinity,
                  height: 210,
                  child: Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 50,
                      color: AppColors.gold,
                    ),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clean(news['title']),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(clean(news['description'])),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        await playClickSound();
                        await data.toggleLike(id);
                      },
                      icon: Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        color: liked ? Colors.red : AppColors.gold,
                      ),
                    ),
                    Text('${data.likeCounts[id] ?? 0}'),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () async {
                        await playClickSound();
                        if (!context.mounted) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CommentsPage(
                              data: data,
                              newsId: id,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.comment_outlined),
                    ),
                    Text('${data.commentCounts[id] ?? 0}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// ✅ التعليقات - مع أيقونة المستخدم
// =======================================================

class CommentsPage extends StatefulWidget {
  final AppData data;
  final dynamic newsId;

  const CommentsPage({
    super.key,
    required this.data,
    required this.newsId,
  });

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    // ✅ حدّث قائمة اللاعبين أولاً لضمان أحدث الأيقونات
    await widget.data.loadPlayers();
    final result = await widget.data.getComments(widget.newsId);
    if (!mounted) return;

    setState(() {
      comments = result;
      loading = false;
    });
  }

  Future<void> send() async {
    if (controller.text.trim().isEmpty) return;

    await playClickSound();

    final ok = await widget.data.addComment(
      widget.newsId,
      widget.data.currentUserName,
      controller.text,
    );

    if (!mounted) return;

    if (ok) {
      controller.clear();
      await load();
    } else {
      showSnack(context, 'تعذر إرسال التعليق.');
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// ✅ دالة مساعدة تبني أيقونة مع صورة أو حرف بديل
  Widget _buildAvatar(String userName) {
    final url = widget.data.avatarForName(userName);
    if (url.isNotEmpty) {
      return CircleAvatar(
        backgroundColor: AppColors.gold,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, __) {},
      );
    }
    return const CircleAvatar(
      backgroundColor: AppColors.gold,
      child: Icon(Icons.person, color: Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التعليقات')),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.gold,
                    ),
                  )
                : comments.isEmpty
                    ? const Center(
                        child: Text('لا توجد تعليقات بعد.'),
                      )
                    : AnimatedBuilder(
                        animation: widget.data,
                        builder: (context, _) {
                          return ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: comments.length,
                            itemBuilder: (_, index) {
                              final item = comments[index];
                              final name = clean(item['user_name']);

                              return Card(
                                child: ListTile(
                                  leading: _buildAvatar(name),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.gold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    clean(item['comment_text']),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'اكتب تعليقك',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// الإشعارات
// =======================================================

class NotificationsPage extends StatelessWidget {
  final AppData data;

  const NotificationsPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          if (data.notifications.isNotEmpty)
            IconButton(
              onPressed: () async {
                await playClickSound();
                await data.markAllNotificationsRead();
              },
              icon: const Icon(Icons.done_all),
            ),
        ],
      ),
      body: data.notifications.isEmpty
          ? const Center(child: Text('لا توجد إشعارات.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: data.notifications.length,
              itemBuilder: (_, index) {
                final item = data.notifications[index];
                final id = item['id'];
                final read = data.isNotificationRead(id);

                return Card(
                  child: ListTile(
                    leading: Icon(
                      read
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                    ),
                    title: Text(
                      clean(item['title']),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                    subtitle: Text(clean(item['body'])),
                    onTap: () async {
                      await data.markNotificationRead(id);
                    },
                  ),
                );
              },
            ),
    );
  }
}
// =======================================================
// الخدمات
// =======================================================

class ServicesPage extends StatelessWidget {
  final AppData data;

  const ServicesPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخدمات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ServiceTile(
            icon: Icons.photo_library,
            title: 'معرض الصور',
            subtitle: 'شارك صورك المفضلة مع المجتمع',
            badge: data.hasNewGallery,
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GalleryPage(data: data),
                ),
              ).then((_) => data.markGallerySeen());
            },
          ),
          ServiceTile(
            icon: Icons.quiz,
            title: 'لعبة الأسئلة',
            subtitle: 'ثلاثة أنواع من الأسئلة',
            badge: data.hasNewQuiz,
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuestionsHubPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.chat,
            title: 'الدردشة العامة',
            subtitle: 'تحدث مع مجتمع مستر أوتاكو',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicChatPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.sports_esports,
            title: 'لعبة القفز',
            subtitle: 'اقفز فوق الصخور وحطم رقمك',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JumpGamePage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.leaderboard,
            title: 'المتصدرون',
            subtitle: 'شاهد ترتيب لاعبي الأوتاكو',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LeaderboardPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.shopping_bag,
            title: 'متجر النقاط',
            subtitle: 'استخدم نقاطك للحصول على المزايا',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopPage(data: data),
                ),
              );
            },
          ),
          ServiceTile(
            icon: Icons.message,
            title: 'إرسال رسالة',
            subtitle: 'تواصل مع إدارة مستر أوتاكو',
            onTap: () async {
              await playClickSound();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SendMessagePage(data: data),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ServiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool badge;

  const ServiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: Badge(
          isLabelVisible: badge,
          backgroundColor: Colors.red,
          child: CircleAvatar(
            backgroundColor: AppColors.gold,
            child: Icon(icon, color: Colors.black),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_back_ios, size: 18),
      ),
    );
  }
}

// =======================================================
// ✅ معرض الصور - مع AnimatedBuilder لضمان التحديث الفوري
// =======================================================

class GalleryPage extends StatefulWidget {
  final AppData data;

  const GalleryPage({
    super.key,
    required this.data,
  });

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  Future<void> pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked == null) return;
    if (!mounted) return;

    final captionController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة صورة'),
        content: TextField(
          controller: captionController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'تعليق (اختياري)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نشر'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    // إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      ),
    );

    final ok = await widget.data.addGalleryImage(
      File(picked.path),
      caption: captionController.text,
    );

    if (!mounted) return;
    Navigator.pop(context); // إغلاق المؤشر

    showSnack(
      context,
      ok ? 'تم نشر الصورة.' : 'تعذر نشر الصورة. تحقق من الاتصال أو الصلاحيات.',
    );

    captionController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معرض الصور'),
        actions: [
          IconButton(
            onPressed: () async {
              await playClickSound();
              await widget.data.loadGallery();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await playClickSound();
          await pickAndUpload();
        },
        icon: const Icon(Icons.add_a_photo),
        label: const Text('أضف صورة'),
      ),
      // ✅ AnimatedBuilder لضمان إعادة البناء عند notifyListeners()
      body: AnimatedBuilder(
        animation: widget.data,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: widget.data.loadGallery,
            color: AppColors.gold,
            child: widget.data.gallery.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 200),
                      Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'لا توجد صور بعد.\nكن أول من يشارك صورة!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.data.gallery.length,
                    itemBuilder: (_, index) {
                      final item = widget.data.gallery[index];

                      return _MuseumFrame(
                        imageUrl: clean(item['image_url']),
                        userName: clean(item['user_name']),
                        caption: clean(item['caption']),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GalleryImagePage(
                                data: widget.data,
                                item: item,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

// =======================================================
// إطار المتحف - إطار ذهبي فاخر
// =======================================================
class _MuseumFrame extends StatelessWidget {
  final String imageUrl;
  final String userName;
  final String caption;
  final VoidCallback onTap;

  const _MuseumFrame({
    required this.imageUrl,
    required this.userName,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBlack,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.goldDark,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.gold,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1.15,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        color: AppColors.inputBlack,
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 50,
                            color: AppColors.gold,
                          ),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: AppColors.inputBlack,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.gold,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 60,
                height: 2,
                color: AppColors.goldDark,
              ),
              const SizedBox(height: 8),
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                  letterSpacing: 0.5,
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================
// عرض الصورة بكامل الشاشة
// =======================================================
class GalleryImagePage extends StatelessWidget {
  final AppData data;
  final Map<String, dynamic> item;

  const GalleryImagePage({
    super.key,
    required this.data,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = clean(item['image_url']);
    final userName = clean(item['user_name']);
    final caption = clean(item['caption']);

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text(userName),
        actions: [
          if (data.isAdmin)
            IconButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('حذف الصورة'),
                    content:
                        const Text('هل أنت متأكد من حذف هذه الصورة؟'),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context, false),
                        child: const Text('إلغاء'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('حذف'),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return;

                await data.deleteGalleryImage(item['id']);
                if (context.mounted) {
                  Navigator.pop(context);
                  showSnack(context, 'تم حذف الصورة.');
                }
              },
              icon: const Icon(Icons.delete),
            ),
        ],
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBlack,
            border: Border.all(color: AppColors.goldDark, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.gold,
                    width: 2,
                  ),
                ),
                child: InteractiveViewer(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      return const SizedBox(
                        height: 200,
                        child: Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 80,
                            color: AppColors.gold,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: 60,
                height: 2,
                color: AppColors.goldDark,
              ),
              const SizedBox(height: 12),
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold,
                  letterSpacing: 1,
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================
// مركز الأسئلة
// =======================================================

class QuestionsHubPage extends StatelessWidget {
  final AppData data;

  const QuestionsHubPage({
    super.key,
    required this.data,
  });

  Future<void> open(BuildContext context, String type) async {
    await playClickSound();
    await data.loadQuizQuestions();
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuizPage(data: data, typeFilter: type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأسئلة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _QuestionTypeCard(
            icon: Icons.person_search,
            title: 'احزر الشخصية',
            description: 'سؤال نصي مع أربعة اختيارات.',
            onTap: () => open(context, 'guess_character'),
          ),
          _QuestionTypeCard(
            icon: Icons.image_search,
            title: 'خمن اسم الشخصية من الصورة',
            description: 'تظهر صورة الشخصية مع أربعة أسماء.',
            onTap: () => open(context, 'image_character'),
          ),
          _QuestionTypeCard(
            icon: Icons.help_outline,
            title: 'أسئلة مباشرة',
            description: 'أسئلة مباشرة عن الأنمي والشخصيات.',
            onTap: () => open(context, 'direct'),
          ),
        ],
      ),
    );
  }
}

class _QuestionTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _QuestionTypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.gold,
          child: Icon(icon, color: Colors.black),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        subtitle: Text(description),
        trailing: const Icon(Icons.arrow_back_ios),
        onTap: onTap,
      ),
    );
  }
}

// =======================================================
// لعبة الأسئلة
// =======================================================

class QuizPage extends StatefulWidget {
  final AppData data;
  final String typeFilter;

  const QuizPage({
    super.key,
    required this.data,
    required this.typeFilter,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<Map<String, dynamic>> questions;

  int current = 0;
  int correctAnswers = 0;
  int? selected;
  bool answered = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();

    questions = widget.data.quizQuestions.where((q) {
      final rawType = clean(q['quiz_type']);
      final type = rawType.isEmpty ? 'direct' : rawType;
      return type == widget.typeFilter;
    }).toList();
  }

  Map<String, dynamic>? get currentQuestion {
    if (questions.isEmpty || current >= questions.length) return null;
    return questions[current];
  }

  String option(int number) {
    return clean(currentQuestion?['option$number']);
  }

  Future<void> answer(int number) async {
    if (answered || currentQuestion == null) return;

    await playClickSound();

    final correct = toInt(currentQuestion!['correct_option']);

    setState(() {
      selected = number;
      answered = true;

      if (number == correct) {
        correctAnswers++;
      }
    });
  }

  Future<void> _saveResultIfNeeded() async {
    if (_saved) return;
    _saved = true;
    await widget.data.saveQuizResult(
      quizType: widget.typeFilter,
      correct: correctAnswers,
      total: questions.length,
    );
  }

  void next() {
    if (!answered) return;

    if (current + 1 >= questions.length) {
      _saveResultIfNeeded();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuizResultPage(
            data: widget.data,
            correct: correctAnswers,
            total: questions.length,
            typeFilter: widget.typeFilter,
          ),
        ),
      );
      return;
    }

    setState(() {
      current++;
      selected = null;
      answered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(quizTypeName(widget.typeFilter)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'لا توجد أسئلة من هذا النوع حالياً.\nيمكن للمدير إضافتها من لوحة الإدارة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    }

    final q = currentQuestion!;
    final correct = toInt(q['correct_option']);

    return Scaffold(
      appBar: AppBar(title: Text(quizTypeName(widget.typeFilter))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(
            value: (current + 1) / questions.length,
            backgroundColor: AppColors.cardBlack,
            color: AppColors.gold,
          ),
          const SizedBox(height: 12),
          Text(
            'السؤال ${current + 1} من ${questions.length}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.typeFilter == 'image_character' &&
              clean(q['image_url']).isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                clean(q['image_url']),
                height: 250,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return const SizedBox(
                    height: 150,
                    child: Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 50,
                        color: AppColors.gold,
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                clean(q['question']),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          for (int i = 1; i <= 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: answered ? null : () => answer(i),
                  style: FilledButton.styleFrom(
                    backgroundColor: answered && i == correct
                        ? Colors.green
                        : answered && i == selected
                            ? Colors.red
                            : AppColors.gold,
                    foregroundColor: Colors.black,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Text(
                      option(i),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          if (answered)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Icon(
                      selected == correct
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: selected == correct
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        selected == correct
                            ? 'إجابة صحيحة! 🔥'
                            : 'إجابة خاطئة. الإجابة الصحيحة هي: ${option(correct)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: answered ? next : null,
            icon: const Icon(Icons.arrow_back),
            label: Text(
              current + 1 >= questions.length
                  ? 'عرض النتيجة'
                  : 'السؤال التالي',
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// نتيجة الأسئلة
// =======================================================

class QuizResultPage extends StatelessWidget {
  final AppData data;
  final int correct;
  final int total;
  final String typeFilter;

  const QuizResultPage({
    super.key,
    required this.data,
    required this.correct,
    required this.total,
    required this.typeFilter,
  });

  double get percentage {
    if (total == 0) return 0;
    return correct / total * 100;
  }

  String get message {
    if (percentage >= 90) return 'أسطوري! معلوماتك رائعة 🏆';
    if (percentage >= 70) return 'ممتاز! مستواك قوي جداً 🔥';
    if (percentage >= 50) return 'جيد! يمكنك الوصول للأفضل ⚔️';
    return 'تحتاج إلى المزيد من التدريب 😄';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النتيجة')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.emoji_events,
                    size: 80,
                    color: AppColors.gold,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'نتيجتك',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('$correct من $total إجابات صحيحة'),
                  const SizedBox(height: 15),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => QuizPage(
                              data: data,
                              typeFilter: typeFilter,
                            ),
                          ),
                        );
                      },
                      child: const Text('إعادة الاختبار'),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('العودة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =======================================================
// ✅ الدردشة العامة - مع أيقونة المستخدم
// =======================================================

class PublicChatPage extends StatefulWidget {
  final AppData data;

  const PublicChatPage({
    super.key,
    required this.data,
  });

  @override
  State<PublicChatPage> createState() => _PublicChatPageState();
}

class _PublicChatPageState extends State<PublicChatPage> {
  final controller = TextEditingController();
  Timer? timer;
  File? selectedImage;
  bool sending = false;

  @override
  void initState() {
    super.initState();

    // ✅ أول تحميل فوري
    _refreshAll();

    // ✅ تحديث الرسائل + اللاعبين (للأيقونات) كل 5 ثوان
    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) async {
        await widget.data.loadPublicChat();
        await widget.data.loadPlayers(); // ← لجلب الأيقونات الجديدة
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _refreshAll() async {
    await widget.data.loadPublicChat();
    await widget.data.loadPlayers();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      selectedImage = File(picked.path);
    });
  }

  Future<void> send() async {
    if (controller.text.trim().isEmpty && selectedImage == null) return;

    setState(() {
      sending = true;
    });

    await playClickSound();

    final ok = await widget.data.sendPublicChat(
      controller.text,
      imageFile: selectedImage,
    );

    if (!mounted) return;

    setState(() {
      sending = false;
    });

    if (ok) {
      controller.clear();
      setState(() {
        selectedImage = null;
      });
    } else {
      showSnack(context, 'تعذر إرسال الرسالة.');
    }
  }

  /// ✅ بناء أيقونة مستخدم الرسالة
  Widget _buildChatAvatar(Map<String, dynamic> item) {
    final accountId = item['account_id'];
    final name = clean(item['user_name']);

    // أولاً: حاول بـ account_id
    String url = widget.data.avatarForAccount(accountId);
    // إن لم يوجد، جرّب بالاسم
    if (url.isEmpty) {
      url = widget.data.avatarForName(name);
    }

    if (url.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.gold,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, __) {},
      );
    }

    return const CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.gold,
      child: Icon(Icons.person, color: Colors.black, size: 22),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الدردشة العامة'),
        actions: [
          IconButton(
            onPressed: () async {
              await playClickSound();
              await _refreshAll();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.data,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(
                child: widget.data.publicChat.isEmpty
                    ? const Center(child: Text('لا توجد رسائل بعد.'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: widget.data.publicChat.length,
                        itemBuilder: (_, index) {
                          final item = widget.data.publicChat[index];
                          final mine = toInt(item['account_id']) ==
                              widget.data.currentAccountId;
                          final messageImage = clean(item['image_url']);
                          final messageText = clean(item['message']);

                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // ✅ صف يحتوي الأيقونة + الاسم
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildChatAvatar(item),
                                        const SizedBox(width: 8),
                                        Text(
                                          clean(item['user_name']),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.gold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (messageImage.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 6),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.network(
                                            messageImage,
                                            width: 200,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) {
                                              return const SizedBox(
                                                width: 200,
                                                height: 100,
                                                child: Center(
                                                  child: Icon(
                                                    Icons.broken_image,
                                                    size: 40,
                                                    color: AppColors.gold,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    if (messageText.isNotEmpty)
                                      Text(messageText),
                                    if (widget.data.isAdmin)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: IconButton(
                                          onPressed: () async {
                                            await playClickSound();
                                            await widget.data
                                                .deletePublicChat(
                                                    item['id']);
                                          },
                                          icon: const Icon(
                                            Icons.delete,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (selectedImage != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const Icon(Icons.image, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'صورة جاهزة للإرسال',
                          style: TextStyle(
                            color: AppColors.gold.withOpacity(0.7),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            selectedImage = null;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: pickImage,
                      icon: const Icon(Icons.image),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'اكتب رسالتك',
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: sending ? null : send,
                      icon: sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.gold,
                              ),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =======================================================
// لعبة القفز
// =======================================================

class JumpGamePage extends StatefulWidget {
  final AppData data;

  const JumpGamePage({
    super.key,
    required this.data,
  });

  @override
  State<JumpGamePage> createState() => _JumpGamePageState();
}

class _JumpGamePageState extends State<JumpGamePage> {
  Timer? timer;
  double playerY = 0;
  double velocity = 0;
  double rockX = 1.1;
  bool playing = false;
  bool gameOver = false;
  int score = 0;
  int best = 0;
  DateTime lastScore = DateTime.now();

  @override
  void initState() {
    super.initState();
    loadBest();
  }

  Future<void> loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      best = prefs.getInt('mr_otaku_jump_best') ?? 0;
    });
  }

  Future<void> saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mr_otaku_jump_best', best);
  }

  void startGame() {
    timer?.cancel();
    setState(() {
      playing = true;
      gameOver = false;
      playerY = 0;
      velocity = 0;
      rockX = 1.1;
      score = 0;
      lastScore = DateTime.now();
    });

    timer = Timer.periodic(
      const Duration(milliseconds: 30),
      (_) => updateGame(),
    );
  }

  void updateGame() {
    if (!mounted || !playing) return;

    const gravity = -0.014;
    playerY += velocity;
    velocity += gravity;

    if (playerY < 0) {
      playerY = 0;
      velocity = 0;
    }

    final difficulty = 0.018 + min(score * 0.0007, 0.018);
    rockX -= difficulty;

    if (rockX < -1.2) {
      rockX = 1.1;
    }

    final playerHitX = rockX < -0.55 && rockX > -0.82;
    final playerOnGround = playerY < 0.10;

    if (playerHitX && playerOnGround) {
      endGame();
      return;
    }

    if (DateTime.now().difference(lastScore).inMilliseconds > 900) {
      lastScore = DateTime.now();
      setState(() {
        score++;
      });
    }

    setState(() {});
  }

  void jump() {
    if (!playing) {
      startGame();
      return;
    }

    if (playerY <= 0.01) {
      velocity = 0.25;
    }
  }

  Future<void> endGame() async {
    timer?.cancel();
    setState(() {
      playing = false;
      gameOver = true;
    });

    if (score > best) {
      best = score;
      await saveBest();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لعبة القفز')),
      body: GestureDetector(
        onTap: jump,
        child: Container(
          width: double.infinity,
          color: AppColors.black,
          child: Column(
            children: [
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    'النقاط: $score',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                  Text(
                    'الأفضل: $best',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: CustomPaint(
                  painter: JumpPainter(
                    playerY: playerY,
                    rockX: rockX,
                  ),
                  child: Container(),
                ),
              ),
              if (!playing)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        gameOver
                            ? 'انتهت اللعبة! نتيجتك: $score'
                            : 'اضغط للبدء',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      FilledButton.icon(
                        onPressed: startGame,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          gameOver ? 'إعادة اللعب' : 'ابدأ اللعبة',
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'اضغط على الشاشة للقفز فوق الصخور',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class JumpPainter extends CustomPainter {
  final double playerY;
  final double rockX;

  JumpPainter({
    required this.playerY,
    required this.rockX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height * 0.78;
    final playerX = size.width * 0.25;
    const playerHeight = 55.0;
    final py = groundY - playerY * size.height * 0.75 - playerHeight;

    final player = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.gold;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(playerX, py, 40, playerHeight),
        const Radius.circular(10),
      ),
      player,
    );

    final rockPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red.shade900;

    final rockXPosition = size.width * ((rockX + 1) / 2);
    final rockRect = Rect.fromLTWH(
      rockXPosition,
      groundY - 40,
      42,
      40,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rockRect,
        const Radius.circular(8),
      ),
      rockPaint,
    );

    final groundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.gold;

    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, 5),
      groundPaint,
    );
  }

  @override
  bool shouldRepaint(covariant JumpPainter oldDelegate) {
    return oldDelegate.playerY != playerY ||
        oldDelegate.rockX != rockX;
  }
}

// =======================================================
// المتصدرون
// =======================================================

class LeaderboardPage extends StatelessWidget {
  final AppData data;

  const LeaderboardPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final list = [...data.players];
    list.sort(
      (a, b) => toInt(b['points']).compareTo(toInt(a['points'])),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('المتصدرون')),
      body: list.isEmpty
          ? const Center(child: Text('لا يوجد لاعبون.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, index) {
                final player = list[index];
                final points = toInt(player['points']);
                final badge = getCurrentBadge(points);
                final avatar = clean(player['avatar_url']);

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.gold,
                      backgroundImage: avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar.isEmpty
                          ? Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      clean(player['name']),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                    subtitle: Text(
                      'المستوى ${getUserLevel(points)}'
                      '${badge == null ? '' : ' • ${badge.icon} ${badge.name}'}',
                    ),
                    trailing: Text(
                      '$points نقطة',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// =======================================================
// المتجر
// =======================================================

class ShopPage extends StatefulWidget {
  final AppData data;

  const ShopPage({
    super.key,
    required this.data,
  });

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  Map<String, dynamic>? selectedPlayer;

  @override
  void initState() {
    super.initState();
    selectedPlayer = widget.data.currentPlayer;
  }

  Future<void> buy(String item, int cost) async {
    if (selectedPlayer == null) {
      showSnack(context, 'لم يتم العثور على حساب.');
      return;
    }

    final points = toInt(selectedPlayer!['points']);
    if (points < cost) {
      showSnack(context, 'نقاطك غير كافية.');
      return;
    }

    final ok = await widget.data.createPurchaseRequest(
      selectedPlayer!['id'],
      item,
      cost,
    );

    if (!mounted) return;

    showSnack(
      context,
      ok ? 'تم إرسال طلب الشراء للإدارة.' : 'تعذر إرسال الطلب.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('متجر النقاط')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (selectedPlayer != null)
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.gold,
                  child: Icon(Icons.person, color: Colors.black),
                ),
                title: Text(
                  clean(selectedPlayer!['name']),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
                subtitle: Text(
                  '${toInt(selectedPlayer!['points'])} نقطة',
                ),
              ),
            ),
          const SizedBox(height: 15),
          _ShopItem(
            title: 'تغيير اسم المجموعة',
            cost: 5,
            icon: Icons.edit,
            onBuy: () => buy('تغيير اسم المجموعة', 5),
          ),
          _ShopItem(
            title: 'أيقونة خاصة',
            cost: 10,
            icon: Icons.image,
            onBuy: () => buy('أيقونة خاصة', 10),
          ),
        ],
      ),
    );
  }
}

class _ShopItem extends StatelessWidget {
  final String title;
  final int cost;
  final IconData icon;
  final VoidCallback onBuy;

  const _ShopItem({
    required this.title,
    required this.cost,
    required this.icon,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.gold,
          child: Icon(icon, color: Colors.black),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        subtitle: Text('$cost نقاط'),
        trailing: FilledButton(
          onPressed: onBuy,
          child: const Text('شراء'),
        ),
      ),
    );
  }
}

// =======================================================
// إرسال رسالة للإدارة
// =======================================================

class SendMessagePage extends StatefulWidget {
  final AppData data;

  const SendMessagePage({
    super.key,
    required this.data,
  });

  @override
  State<SendMessagePage> createState() => _SendMessagePageState();
}

class _SendMessagePageState extends State<SendMessagePage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final ok = await widget.data.sendMessage(
      widget.data.currentUserName,
      controller.text,
    );

    if (!mounted) return;

    if (ok) {
      controller.clear();
      showSnack(context, 'تم إرسال رسالتك للإدارة.');
    } else {
      showSnack(context, 'تعذر إرسال الرسالة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إرسال رسالة')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'سيتم إرسال الرسالة باسم ${widget.data.currentUserName}',
            ),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              maxLines: 7,
              decoration: const InputDecoration(
                labelText: 'رسالتك',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: send,
                icon: const Icon(Icons.send),
                label: const Text('إرسال'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// ✅ الإعدادات - مع AnimatedBuilder لتحديث الأيقونة فورًا
// =======================================================

class SettingsPage extends StatelessWidget {
  final AppData data;

  const SettingsPage({
    super.key,
    required this.data,
  });

  Future<void> _pickAvatar(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked == null) return;
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      ),
    );

    final ok = await data.updateAvatar(File(picked.path));

    if (!context.mounted) return;
    Navigator.pop(context);

    showSnack(
      context,
      ok ? 'تم تحديث الأيقونة.' : 'تعذر تحديث الأيقونة.',
    );
  }

  Future<void> logout(BuildContext context) async {
    await playClickSound();
    await data.logoutAccount();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => AccountSetupPage(data: data),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ AnimatedBuilder لإعادة البناء عند تغيّر الأيقونة أو الاسم أو النقاط
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        final badge = data.currentBadge;
        final avatar = data.currentAvatar;

        return Scaffold(
          appBar: AppBar(title: const Text('الإعدادات')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.gold,
                                width: 3,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 45,
                              backgroundColor: AppColors.inputBlack,
                              backgroundImage: avatar.isNotEmpty
                                  ? NetworkImage(avatar)
                                  : null,
                              child: avatar.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                      size: 45,
                                      color: AppColors.gold,
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _pickAvatar(context),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.black,
                                    width: 2,
                                  ),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 20,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.currentUserName,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                        ),
                      ),
                      Text('معرف الحساب: ${data.currentAccountId}'),
                      Text('المستوى: ${data.currentLevel}'),
                      Text('النقاط: ${data.currentPoints}'),
                      if (badge != null)
                        Text('${badge.icon} ${badge.name}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ServiceTile(
                icon: Icons.notifications,
                title: 'الإشعارات',
                subtitle: 'عرض إشعارات الإدارة',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsPage(data: data),
                    ),
                  );
                },
              ),
              if (data.isAdmin)
                ServiceTile(
                  icon: Icons.admin_panel_settings,
                  title: 'لوحة الإدارة',
                  subtitle: 'إدارة التطبيق',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminPanelPage(data: data),
                      ),
                    );
                  },
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text(
                    'تسجيل الخروج',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () => logout(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =======================================================
// لوحة الإدارة
// =======================================================

class AdminPanelPage extends StatelessWidget {
  final AppData data;

  const AdminPanelPage({
    super.key,
    required this.data,
  });

  Future<void> logout(BuildContext context) async {
    await data.setAdminSession(false);

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => AccountSetupPage(data: data),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!data.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('الإدارة')),
        body: const Center(
          child: Text('ليس لديك صلاحية الوصول.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الإدارة'),
        actions: [
          IconButton(
            onPressed: () => logout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminTile(
            icon: Icons.campaign,
            title: 'الخبر المهم',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManageImportantNewsPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.photo_library,
            title: 'إدارة معرض الصور',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageGalleryPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.assignment_turned_in,
            title: 'نتائج الاختبارات',
            onTap: () async {
              await data.loadQuizResults();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageQuizResultsPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.quiz,
            title: 'إدارة الأسئلة',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageQuizPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.newspaper,
            title: 'إدارة الأخبار',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageNewsPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.notifications,
            title: 'إدارة الإشعارات',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageNotificationsPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.poll,
            title: 'إدارة الاستطلاعات',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManagePollPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.people,
            title: 'إدارة اللاعبين والحسابات',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManagePointsPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.campaign,
            title: 'إدارة كل جديد',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageLatestPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.message,
            title: 'الرسائل',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageMessagesPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.chat,
            title: 'الدردشة العامة',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicChatPage(data: data),
                ),
              );
            },
          ),
          AdminTile(
            icon: Icons.shopping_bag,
            title: 'طلبات المتجر',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ManagePurchaseRequestsPage(data: data),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const AdminTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.gold,
          child: Icon(icon, color: Colors.black),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        trailing: const Icon(Icons.arrow_back_ios),
      ),
    );
  }
}
// =======================================================
// إدارة الخبر المهم
// =======================================================

class ManageImportantNewsPage extends StatefulWidget {
  final AppData data;

  const ManageImportantNewsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageImportantNewsPage> createState() =>
      _ManageImportantNewsPageState();
}

class _ManageImportantNewsPageState
    extends State<ManageImportantNewsPage> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: widget.data.importantNews,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (controller.text.trim().isEmpty) {
      showSnack(context, 'اكتب محتوى الخبر أولاً.');
      return;
    }

    await playClickSound();
    final ok = await widget.data.updateImportantNews(controller.text);

    if (!mounted) return;

    showSnack(
      context,
      ok ? 'تم حفظ الخبر المهم.' : 'تعذر الحفظ.',
    );

    if (ok) Navigator.pop(context);
  }

  Future<void> clear() async {
    await playClickSound();
    final ok = await widget.data.clearImportantNews();

    if (!mounted) return;

    if (ok) {
      controller.clear();
      showSnack(context, 'تم حذف الخبر المهم.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخبر المهم')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'سيظهر هذا الخبر في أعلى الصفحة الرئيسية لجميع المستخدمين.',
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'نص الخبر المهم',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 15),
          FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ ونشر'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: clear,
            icon: const Icon(Icons.delete),
            label: const Text('حذف الخبر الحالي'),
          ),
          const SizedBox(height: 20),
          if (widget.data.importantNews.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: AppColors.black,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.gold, width: 2),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الخبر الحالي:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.data.importantNews,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =======================================================
// ✅ إدارة معرض الصور - مع AnimatedBuilder
// =======================================================

class ManageGalleryPage extends StatelessWidget {
  final AppData data;

  const ManageGalleryPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة معرض الصور')),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          if (data.gallery.isEmpty) {
            return const Center(child: Text('لا توجد صور.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: data.gallery.length,
            itemBuilder: (_, index) {
              final item = data.gallery[index];
              final imageUrl = clean(item['image_url']);
              final userName = clean(item['user_name']);
              final caption = clean(item['caption']);

              return Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.network(
                      imageUrl,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const SizedBox(
                          height: 200,
                          child: Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 50,
                              color: AppColors.gold,
                            ),
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.gold,
                                  ),
                                ),
                                if (caption.isNotEmpty)
                                  Text(caption),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              await data.deleteGalleryImage(item['id']);
                              if (context.mounted) {
                                showSnack(
                                  context,
                                  'تم حذف الصورة.',
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// =======================================================
// نتائج الاختبارات
// =======================================================

class ManageQuizResultsPage extends StatelessWidget {
  final AppData data;

  const ManageQuizResultsPage({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final list = [...data.quizResults];
    list.sort((a, b) {
      final da = clean(a['created_at']);
      final db = clean(b['created_at']);
      return db.compareTo(da);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('نتائج الاختبارات'),
        actions: [
          IconButton(
            onPressed: () async {
              await data.loadQuizResults();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: list.isEmpty
          ? const Center(child: Text('لا توجد نتائج بعد.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, index) {
                final item = list[index];
                final name = clean(item['user_name']);
                final type = quizTypeName(clean(item['quiz_type']));
                final correct = toInt(item['correct_answers']);
                final total = toInt(item['total_questions']);
                final percent = total == 0
                    ? 0
                    : (correct / total * 100).toStringAsFixed(0);

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.gold,
                      child: const Icon(
                        Icons.assignment_turned_in,
                        color: Colors.black,
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                    subtitle: Text(
                      '$type — $correct/$total ($percent%)',
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// =======================================================
// إدارة الأسئلة
// =======================================================

class ManageQuizPage extends StatefulWidget {
  final AppData data;

  const ManageQuizPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageQuizPage> createState() => _ManageQuizPageState();
}

class _ManageQuizPageState extends State<ManageQuizPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.data,
      builder: (context, _) {
        final list = widget.data.quizQuestions;

        return Scaffold(
          appBar: AppBar(title: const Text('إدارة الأسئلة')),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizEditorPage(data: widget.data),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
          body: list.isEmpty
              ? const Center(child: Text('لا توجد أسئلة.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (_, index) {
                    final q = list[index];

                    return Card(
                      child: ListTile(
                        title: Text(clean(q['question'])),
                        subtitle: Text(
                          quizTypeName(
                            clean(q['quiz_type']).isEmpty
                                ? 'direct'
                                : clean(q['quiz_type']),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => QuizEditorPage(
                                      data: widget.data,
                                      question: q,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.edit),
                            ),
                            IconButton(
                              onPressed: () async {
                                await widget.data
                                    .deleteQuizQuestion(q['id']);
                              },
                              icon: const Icon(Icons.delete),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class QuizEditorPage extends StatefulWidget {
  final AppData data;
  final Map<String, dynamic>? question;

  const QuizEditorPage({
    super.key,
    required this.data,
    this.question,
  });

  @override
  State<QuizEditorPage> createState() => _QuizEditorPageState();
}

class _QuizEditorPageState extends State<QuizEditorPage> {
  late final TextEditingController question;
  late final TextEditingController option1;
  late final TextEditingController option2;
  late final TextEditingController option3;
  late final TextEditingController option4;

  late int correct;
  String type = 'direct';
  File? imageFile;
  String? imageUrl;
  bool saving = false;

  bool get editing => widget.question != null;

  @override
  void initState() {
    super.initState();

    final q = widget.question;
    question = TextEditingController(text: clean(q?['question']));
    option1 = TextEditingController(text: clean(q?['option1']));
    option2 = TextEditingController(text: clean(q?['option2']));
    option3 = TextEditingController(text: clean(q?['option3']));
    option4 = TextEditingController(text: clean(q?['option4']));

    correct = toInt(q?['correct_option']);
    if (correct < 1 || correct > 4) correct = 1;

    type = clean(q?['quiz_type']).isEmpty
        ? 'direct'
        : clean(q?['quiz_type']);

    imageUrl = clean(q?['image_url']);
    if (imageUrl?.isEmpty ?? true) imageUrl = null;
  }

  @override
  void dispose() {
    question.dispose();
    option1.dispose();
    option2.dispose();
    option3.dispose();
    option4.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      imageFile = File(picked.path);
    });
  }

  Future<void> save() async {
    if (question.text.trim().isEmpty ||
        option1.text.trim().isEmpty ||
        option2.text.trim().isEmpty ||
        option3.text.trim().isEmpty ||
        option4.text.trim().isEmpty) {
      showSnack(context, 'أكمل جميع الحقول.');
      return;
    }

    setState(() => saving = true);

    String? finalImage = imageUrl;

    if (type == 'image_character') {
      if (imageFile != null) {
        finalImage =
            await widget.data.uploadQuizImage(imageFile!);
      }

      if (finalImage == null || finalImage.isEmpty) {
        if (!mounted) return;
        showSnack(context, 'أضف صورة لهذا النوع من الأسئلة.');
        setState(() => saving = false);
        return;
      }
    } else {
      finalImage = null;
    }

    bool ok;
    if (editing) {
      ok = await widget.data.updateQuizQuestion(
        id: widget.question!['id'],
        question: question.text,
        option1: option1.text,
        option2: option2.text,
        option3: option3.text,
        option4: option4.text,
        correctOption: correct,
        quizType: type,
        imageUrl: finalImage,
      );
    } else {
      ok = await widget.data.addQuizQuestion(
        question: question.text,
        option1: option1.text,
        option2: option2.text,
        option3: option3.text,
        option4: option4.text,
        correctOption: correct,
        quizType: type,
        imageUrl: finalImage,
      );
    }

    if (!mounted) return;
    setState(() => saving = false);

    if (ok) {
      Navigator.pop(context);
    } else {
      showSnack(context, 'تعذر حفظ السؤال.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'تعديل السؤال' : 'إضافة سؤال'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: type,
            decoration: const InputDecoration(
              labelText: 'نوع السؤال',
            ),
            items: const [
              DropdownMenuItem(
                value: 'direct',
                child: Text('أسئلة مباشرة'),
              ),
              DropdownMenuItem(
                value: 'guess_character',
                child: Text('احزر الشخصية'),
              ),
              DropdownMenuItem(
                value: 'image_character',
                child: Text('خمن الشخصية من الصورة'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => type = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: question,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'السؤال'),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: [
                  option1,
                  option2,
                  option3,
                  option4,
                ][i],
                decoration: InputDecoration(
                  labelText: 'الخيار ${i + 1}',
                ),
              ),
            ),
          DropdownButtonFormField<int>(
            value: correct,
            decoration: const InputDecoration(
              labelText: 'الإجابة الصحيحة',
            ),
            items: List.generate(
              4,
              (index) => DropdownMenuItem(
                value: index + 1,
                child: Text('الخيار ${index + 1}'),
              ),
            ),
            onChanged: (value) {
              if (value != null) setState(() => correct = value);
            },
          ),
          if (type == 'image_character') ...[
            const SizedBox(height: 15),
            if (imageFile != null)
              Image.file(imageFile!, height: 180, fit: BoxFit.contain)
            else if (imageUrl != null)
              Image.network(imageUrl!, height: 180, fit: BoxFit.contain),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: pickImage,
              icon: const Icon(Icons.image),
              label: const Text('اختيار صورة الشخصية'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : save,
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text('حفظ السؤال'),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// إدارة الأخبار
// =======================================================

class ManageNewsPage extends StatefulWidget {
  final AppData data;

  const ManageNewsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageNewsPage> createState() => _ManageNewsPageState();
}

class _ManageNewsPageState extends State<ManageNewsPage> {
  final title = TextEditingController();
  final description = TextEditingController();
  File? image;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> add() async {
    title.clear();
    description.clear();
    image = null;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('إضافة خبر'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'العنوان',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'الوصف',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (image != null)
                    Image.file(image!, height: 120),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                      );

                      if (picked != null) {
                        setState(() {
                          image = File(picked.path);
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('إضافة صورة'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  final ok = await widget.data.addNews(
                    title.text,
                    description.text,
                    imageFile: image,
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    showSnack(
                      context,
                      ok ? 'تمت إضافة الخبر.' : 'تعذر إضافة الخبر.',
                    );
                  }
                },
                child: const Text('نشر'),
              ),
            ],
          );
        },
      ),
    );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.data,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('إدارة الأخبار')),
          floatingActionButton: FloatingActionButton(
            onPressed: add,
            child: const Icon(Icons.add),
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: widget.data.news.length,
            itemBuilder: (_, index) {
              final item = widget.data.news[index];

              return Card(
                child: ListTile(
                  title: Text(clean(item['title'])),
                  subtitle: Text(
                    clean(item['description']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    onPressed: () async {
                      await widget.data.deleteNews(item['id']);
                    },
                    icon: const Icon(Icons.delete),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// =======================================================
// إدارة الإشعارات
// =======================================================

class ManageNotificationsPage extends StatefulWidget {
  final AppData data;

  const ManageNotificationsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageNotificationsPage> createState() =>
      _ManageNotificationsPageState();
}

class _ManageNotificationsPageState
    extends State<ManageNotificationsPage> {
  final title = TextEditingController();
  final body = TextEditingController();

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> add() async {
    if (title.text.trim().isEmpty) return;

    final ok = await widget.data.addNotification(
      title.text,
      body.text,
    );

    if (!mounted) return;

    showSnack(
      context,
      ok ? 'تم إرسال الإشعار.' : 'تعذر إرسال الإشعار.',
    );

    if (ok) {
      title.clear();
      body.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الإشعارات')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(
                labelText: 'العنوان',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: body,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'نص الإشعار',
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: add,
                child: const Text('إرسال إشعار'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// إدارة الاستطلاع
// =======================================================

class ManagePollPage extends StatefulWidget {
  final AppData data;

  const ManagePollPage({
    super.key,
    required this.data,
  });

  @override
  State<ManagePollPage> createState() => _ManagePollPageState();
}

class _ManagePollPageState extends State<ManagePollPage> {
  final question = TextEditingController();
  final options = List.generate(4, (_) => TextEditingController());

  @override
  void dispose() {
    question.dispose();
    for (final controller in options) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> create() async {
    final values = options
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (question.text.trim().isEmpty || values.length < 2) {
      showSnack(context, 'أدخل السؤال وخيارين على الأقل.');
      return;
    }

    final ok = await widget.data.createPoll(
      question.text,
      values,
    );

    if (!mounted) return;

    showSnack(
      context,
      ok ? 'تم إنشاء الاستطلاع.' : 'تعذر إنشاء الاستطلاع.',
    );

    if (ok) {
      question.clear();
      for (final item in options) {
        item.clear();
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الاستطلاعات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: question,
            decoration: const InputDecoration(labelText: 'السؤال'),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: options[i],
                decoration: InputDecoration(
                  labelText: 'الخيار ${i + 1}',
                ),
              ),
            ),
          FilledButton(
            onPressed: create,
            child: const Text('إنشاء استطلاع'),
          ),
          const SizedBox(height: 20),
          if (widget.data.activePoll != null)
            Card(
              child: ListTile(
                title: const Text('الاستطلاع الحالي'),
                subtitle: Text(
                  clean(widget.data.activePoll!['question']),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =======================================================
// إدارة اللاعبين
// =======================================================

class ManagePointsPage extends StatefulWidget {
  final AppData data;

  const ManagePointsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManagePointsPage> createState() => _ManagePointsPageState();
}

class _ManagePointsPageState extends State<ManagePointsPage> {
  Future<void> edit([Map<String, dynamic>? player]) async {
    final name = TextEditingController(text: clean(player?['name']));
    final points = TextEditingController(
      text: toInt(player?['points']).toString(),
    );
    final accountId = TextEditingController(
      text: player?['account_id']?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(player == null ? 'إضافة حساب' : 'تعديل الحساب'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: accountId,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'معرف الحساب الفريد',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: points,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'النقاط',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final parsedId = accountId.text.trim().isEmpty
                  ? null
                  : int.tryParse(accountId.text.trim());

              final parsedPoints =
                  int.tryParse(points.text.trim()) ?? 0;

              bool ok;
              if (player == null) {
                ok = await widget.data.addPlayer(
                  name.text,
                  parsedPoints,
                  accountId: parsedId,
                );
              } else {
                ok = await widget.data.updatePlayer(
                  player['id'],
                  name.text,
                  parsedPoints,
                  accountId: parsedId,
                );
              }

              if (context.mounted) {
                Navigator.pop(context);
                showSnack(
                  context,
                  ok
                      ? 'تم حفظ الحساب.'
                      : 'فشل الحفظ. قد يكون معرف الحساب مستخدماً بالفعل.',
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    name.dispose();
    points.dispose();
    accountId.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.data,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('إدارة الحسابات والنقاط')),
          floatingActionButton: FloatingActionButton(
            onPressed: () => edit(),
            child: const Icon(Icons.person_add),
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: widget.data.players.length,
            itemBuilder: (_, index) {
              final player = widget.data.players[index];
              final avatar = clean(player['avatar_url']);

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.gold,
                    backgroundImage: avatar.isNotEmpty
                        ? NetworkImage(avatar)
                        : null,
                    child: avatar.isEmpty
                        ? Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  title: Text(clean(player['name'])),
                  subtitle: Text(
                    'ID: ${player['account_id'] ?? 'غير مرتبط'}\nالمستوى: ${getUserLevel(toInt(player['points']))}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${toInt(player['points'])}'),
                      IconButton(
                        onPressed: () => edit(player),
                        icon: const Icon(Icons.edit),
                      ),
                      IconButton(
                        onPressed: () async {
                          await widget.data.deletePlayer(player['id']);
                        },
                        icon: const Icon(Icons.delete),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// =======================================================
// إدارة كل جديد
// =======================================================

class ManageLatestPage extends StatefulWidget {
  final AppData data;

  const ManageLatestPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageLatestPage> createState() => _ManageLatestPageState();
}

class _ManageLatestPageState extends State<ManageLatestPage> {
  final title = TextEditingController();
  final description = TextEditingController();

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> add() async {
    final ok = await widget.data.addLatest(
      title.text,
      description.text,
    );

    if (!mounted) return;

    showSnack(context, ok ? 'تمت الإضافة.' : 'تعذر الإضافة.');

    if (ok) {
      title.clear();
      description.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.data,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('إدارة كل جديد')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'العنوان'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'الوصف'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: add,
                child: const Text('إضافة'),
              ),
              const SizedBox(height: 15),
              ...widget.data.latest.map(
                (item) => Card(
                  child: ListTile(
                    title: Text(clean(item['title'])),
                    subtitle: Text(clean(item['description'])),
                    trailing: IconButton(
                      onPressed: () async {
                        await widget.data.deleteLatest(item['id']);
                      },
                      icon: const Icon(Icons.delete),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =======================================================
// إدارة الرسائل
// =======================================================

class ManageMessagesPage extends StatefulWidget {
  final AppData data;

  const ManageMessagesPage({
    super.key,
    required this.data,
  });

  @override
  State<ManageMessagesPage> createState() =>
      _ManageMessagesPageState();
}

class _ManageMessagesPageState extends State<ManageMessagesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رسائل المستخدمين')),
      body: AnimatedBuilder(
        animation: widget.data,
        builder: (context, _) {
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: widget.data.messages.length,
            itemBuilder: (_, index) {
              final item = widget.data.messages[index];

              return Card(
                child: ListTile(
                  title: Text(clean(item['name'])),
                  subtitle: Text(clean(item['message'])),
                  trailing: IconButton(
                    onPressed: () async {
                      await widget.data.deleteMessage(item['id']);
                    },
                    icon: const Icon(Icons.delete),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// =======================================================
// إدارة طلبات المتجر
// =======================================================

class ManagePurchaseRequestsPage extends StatefulWidget {
  final AppData data;

  const ManagePurchaseRequestsPage({
    super.key,
    required this.data,
  });

  @override
  State<ManagePurchaseRequestsPage> createState() =>
      _ManagePurchaseRequestsPageState();
}

class _ManagePurchaseRequestsPageState
    extends State<ManagePurchaseRequestsPage> {
  Future<void> refresh() async {
    await widget.data.loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات المتجر'),
        actions: [
          IconButton(
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.data,
        builder: (context, _) {
          if (widget.data.purchaseRequests.isEmpty) {
            return const Center(child: Text('لا توجد طلبات.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: widget.data.purchaseRequests.length,
            itemBuilder: (_, index) {
              final item = widget.data.purchaseRequests[index];
              final status = clean(item['status']);

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('اللاعب: ${item['player_id']}'),
                      Text('العنصر: ${clean(item['item_type'])}'),
                      Text('التكلفة: ${toInt(item['cost'])}'),
                      Text('الحالة: $status'),
                      if (status == 'pending')
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  await widget.data
                                      .approvePurchase(item);
                                  await refresh();
                                },
                                child: const Text('موافقة'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  await widget.data
                                      .rejectPurchase(item['id']);
                                  await refresh();
                                },
                                child: const Text('رفض'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// =======================================================
// SnackBar
// =======================================================

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.cardBlack,
    ),
  );
}

// =======================================================
// خدمة الإشعارات
// =======================================================
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'mr_otaku_channel';
  static const String _channelName = 'إشعارات مستر أوتاكو';
  static const String _channelDesc = 'إشعارات الأخبار والإدارة';

  static Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );
  }

  static Future<void> show(
    String title,
    String body, {
    int id = 0,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );

    await _plugin.show(id, title, body, details);
  }

  static Future<void> registerBackgroundTask() async {
    await Workmanager().initialize(callbackDispatcher);

    await Workmanager().registerPeriodicTask(
      'mr_otaku_check',
      'checkNotifications',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> checkNewNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getString('mr_otaku_last_notif_id') ?? '';

      final result = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(1);

      if (result.isEmpty) return;

      final first = result.first;
      final currentId = clean(first['id']);

      if (lastId.isNotEmpty && currentId != lastId) {
        await show(
          clean(first['title']),
          clean(first['body']),
          id: currentId.hashCode,
        );
      }

      await prefs.setString('mr_otaku_last_notif_id', currentId);
    } catch (e) {
      debugPrint('Check notifications error: $e');
    }
  }
}

// =======================================================
// Dispatcher للمهمة الدورية
// =======================================================
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(
          url: 'https://sekchgllbimoedsjoumi.supabase.co',
          anonKey: 'sb_publishable_EZLVSUviR39RXi6OP3OqfQ_3j7vMZcU',
        );
      }
    } catch (_) {}

    await NotificationService.init();
    await NotificationService.checkNewNotifications();

    return true;
  });
}