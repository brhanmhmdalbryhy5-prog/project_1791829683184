import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../core/theme_manager.dart';
import '../data/app_data.dart';
import 'social_screens.dart';
import 'admin_screens.dart';
import 'admin_stats.dart';
import 'followers_page.dart';
import 'stories_page.dart';
import 'games_screens.dart';

// =======================================================
// 1. الحاوية الرئيسية
// =======================================================
class HomePage extends StatefulWidget {
  final AppData data;
  const HomePage({super.key, required this.data});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  Timer? _playersRefreshTimer;

  @override
  void initState() {
    super.initState();
    widget.data.updateLastSeen();
    _playersRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await widget.data.updateLastSeen();
      await widget.data.loadPlayers();
      await widget.data.loadUnreadMessagesCount();
    });
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
      PostsPage(data: widget.data),
      PrivateMessagesPage(data: widget.data),
      ServicesPage(data: widget.data),
      ProfilePage(data: widget.data),
    ];

    final totalUnreadMessages = widget.data.unreadMessageCounts.values.fold<int>(0, (a, b) => a + b);
    final primary = ThemeManager.instance.primaryColor;

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) async {
          await playClickSound();
          if (!mounted) return;
          setState(() => index = value);
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(
            icon: Badge(isLabelVisible: widget.data.hasNewNews, backgroundColor: primary, child: const Icon(Icons.newspaper_outlined)),
            selectedIcon: const Icon(Icons.newspaper),
            label: 'الأخبار',
          ),
          const NavigationDestination(icon: Icon(Icons.post_add), selectedIcon: Icon(Icons.post_add), label: 'المنشورات'),
          NavigationDestination(
            icon: Badge(isLabelVisible: totalUnreadMessages > 0, backgroundColor: Colors.red, label: Text('$totalUnreadMessages'), child: const Icon(Icons.forum_outlined)),
            selectedIcon: const Icon(Icons.forum),
            label: 'الرسائل',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: widget.data.hasNewQuiz || widget.data.hasNewGallery, backgroundColor: primary, child: const Icon(Icons.apps_outlined)),
            selectedIcon: const Icon(Icons.apps),
            label: 'الخدمات',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}

// =======================================================
// 2. الرئيسية (مع Stories + الاستطلاع + الأخبار + المتصدر)
// =======================================================
class HomeTab extends StatefulWidget {
  final AppData data;
  const HomeTab({super.key, required this.data});
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
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.data.news.isEmpty || !controller.hasClients) return;
      newsIndex = (newsIndex + 1 >= widget.data.news.length) ? 0 : newsIndex + 1;
      controller.animateToPage(newsIndex, duration: const Duration(milliseconds: 650), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() { timer?.cancel(); controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مستر أوتاكو', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: () => showSearch(context: context, delegate: CustomSearchDelegate(widget.data)), icon: const Icon(Icons.search)),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(data: widget.data))),
            icon: Badge(isLabelVisible: widget.data.unreadNotificationCount > 0, backgroundColor: Colors.red, label: Text(widget.data.unreadNotificationCount.toString()), child: const Icon(Icons.notifications)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.data.loadData,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          children: [
            StoriesBar(data: widget.data),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: ThemeManager.instance.getPrimaryGradient(),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: ThemeManager.instance.getGlowShadow(),
                ),
                child: Column(children: [
                  GestureDetector(
                    onTap: () => showAvatarDialog(context, widget.data.currentAvatar, widget.data.currentDisplayName),
                    child: CircleAvatar(radius: 40, backgroundColor: Colors.white, backgroundImage: widget.data.currentAvatar.isNotEmpty ? CachedNetworkImageProvider(widget.data.currentAvatar) : null, child: widget.data.currentAvatar.isEmpty ? const Icon(Icons.person, size: 40, color: AppColors.gold) : null),
                  ),
                  const SizedBox(height: 10),
                  Text('مرحباً ${widget.data.currentDisplayName}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _MiniStat(title: 'النقاط', value: widget.data.currentPoints.toString()),
                    const SizedBox(width: 25),
                    _MiniStat(title: 'المستوى', value: widget.data.currentLevel),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.data.news.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 190,
                  child: PageView.builder(
                    controller: controller,
                    itemCount: widget.data.news.length,
                    itemBuilder: (context, index) {
                      final item = widget.data.news[index];
                      final image = clean(item['image_url']);
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailsPage(news: item))),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: ThemeManager.instance.primaryColor.withOpacity(0.4))),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(fit: StackFit.expand, children: [
                            if (image.isNotEmpty) CachedNetworkImage(imageUrl: image, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: AppColors.cardBlack, child: const Icon(Icons.newspaper, size: 50, color: AppColors.gold))) else Container(color: AppColors.cardBlack, child: const Icon(Icons.newspaper, size: 50, color: AppColors.gold)),
                            Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])), child: Text(clean(item['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.gold)))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (widget.data.importantNews.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(color: AppColors.cardBlack, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.getColor(9), width: 2)),
                  padding: const EdgeInsets.all(16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.campaign, color: AppColors.getColor(9), size: 30),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('إعلان مهم', style: TextStyle(color: AppColors.getColor(9), fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(widget.data.importantNews, style: const TextStyle(color: Colors.white, fontSize: 15)),
                    ])),
                  ]),
                ),
              ),
            if (widget.data.importantNews.trim().isNotEmpty) const SizedBox(height: 16),
            // ✅ استطلاع الرأي
            if (widget.data.activePoll != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PollCard(data: widget.data),
              ),
            if (widget.data.activePoll != null) const SizedBox(height: 16),
            if (widget.data.leader != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: AppColors.getColor(4).withOpacity(0.15),
                  child: ListTile(
                    leading: GestureDetector(onTap: () => showAvatarDialog(context, clean(widget.data.leader!['avatar_url']), widget.data.displayNameForAccount(widget.data.leader!['account_id'])), child: CircleAvatar(backgroundColor: AppColors.getColor(4), backgroundImage: clean(widget.data.leader!['avatar_url']).isNotEmpty ? CachedNetworkImageProvider(clean(widget.data.leader!['avatar_url'])) : null, child: clean(widget.data.leader!['avatar_url']).isEmpty ? const Icon(Icons.emoji_events, color: Colors.white) : null)),
                    title: Text('متصدر الأوتاكو', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColor(4))),
                    subtitle: Text(widget.data.displayNameForAccount(widget.data.leader!['account_id'])),
                    trailing: Text('${parseInt(widget.data.leader!['points'])} نقطة', style: TextStyle(color: AppColors.getColor(4), fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// ✅ بطاقة الاستطلاع
// =======================================================
class PollCard extends StatelessWidget {
  final AppData data;
  const PollCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final voted = data.hasVotedInActivePoll;
    final poll = data.activePoll!;
    final options = data.activePollOptions;
    final primary = ThemeManager.instance.primaryColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.poll, color: primary, size: 24),
              const SizedBox(width: 8),
              const Text(
                'استطلاع الرأي',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: AppColors.gold),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              clean(poll['question']),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 12),
            ...options.map((option) {
              final id = option['id'];
              final voters = data.votersForOption(id);
              final percentage = data.getPollPercentage(id);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!voted)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () async {
                            await playClickSound();
                            await data.votePoll(id);
                          },
                          child: Text(clean(option['option_text'])),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.cardBlack,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: primary.withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: Text(clean(option['option_text']), style: const TextStyle(fontWeight: FontWeight.bold))),
                              Text('${percentage.toStringAsFixed(0)}%', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: percentage / 100,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade800,
                                valueColor: AlwaysStoppedAnimation(primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (data.isAdmin && voters.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 4),
                        child: Text(
                          'صوّت: ${voters.map((v) => clean(v['user_name'])).join(', ')}',
                          style: TextStyle(fontSize: 11, color: AppColors.gold.withOpacity(0.7)),
                        ),
                      ),
                  ],
                ),
              );
            }),
            if (voted)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    'إجمالي المصوتين: ${data.totalPollVotes}',
                    style: TextStyle(fontSize: 12, color: AppColors.gold.withOpacity(0.7)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// البحث
// =======================================================
class CustomSearchDelegate extends SearchDelegate {
  final AppData data;
  CustomSearchDelegate(this.data);

  @override
  List<Widget>? buildActions(BuildContext context) => [if (query.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);
  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.search, size: 80, color: Colors.grey), SizedBox(height: 16), Text('ابحث عن مستخدم أو منشور أو خبر', style: TextStyle(fontSize: 16))])));
    }

    final q = query.toLowerCase();
    final players = data.players.where((p) {
      final name = clean(p['name']).toLowerCase();
      final channel = clean(p['channel_name']).toLowerCase();
      return name.contains(q) || channel.contains(q);
    }).toList();
    final newsList = data.news.where((n) => clean(n['title']).toLowerCase().contains(q) || clean(n['description']).toLowerCase().contains(q)).toList();
    final posts = data.posts.where((p) => clean(p['content']).toLowerCase().contains(q)).toList();

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (players.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('👤 المستخدمون:', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 18))),
        ...players.map((p) {
          final displayName = data.displayNameForAccount(p['account_id']);
          final avatar = clean(p['avatar_url']);
          return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
            leading: CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null),
            title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('ID: ${p['account_id']}', style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.arrow_back_ios, size: 16),
            onTap: () { close(context, null); Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(data: data, accountId: parseInt(p['account_id']), userName: displayName))); },
          ));
        }),
        const SizedBox(height: 16),
      ],
      if (newsList.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('📰 الأخبار:', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 18))),
        ...newsList.map((n) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          leading: const Icon(Icons.newspaper, color: AppColors.gold),
          title: Text(clean(n['title'])),
          subtitle: Text(clean(n['description']), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.arrow_back_ios, size: 16),
          onTap: () { close(context, null); Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailsPage(news: n))); },
        ))),
        const SizedBox(height: 16),
      ],
      if (posts.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('📝 المنشورات:', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 18))),
        ...posts.map((p) {
          final ownerName = data.displayNameForAccount(p['account_id']);
          return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
            leading: const Icon(Icons.post_add, color: AppColors.gold),
            title: Text(clean(p['content']), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('بواسطة: $ownerName', style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.arrow_back_ios, size: 16),
            onTap: () { close(context, null); Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(data: data, accountId: parseInt(p['account_id']), userName: ownerName))); },
          ));
        }),
      ],
      if (players.isEmpty && newsList.isEmpty && posts.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.search_off, size: 80, color: Colors.grey), SizedBox(height: 16), Text('لا توجد نتائج لبحثك.', style: TextStyle(fontSize: 16))]))),
    ]);
  }
}

class _MiniStat extends StatelessWidget {
  final String title; final String value;
  const _MiniStat({required this.title, required this.value});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
    Text(title, style: const TextStyle(color: Colors.white70)),
  ]);
}

// =======================================================
// 3. صفحة حسابي
// =======================================================
class ProfilePage extends StatefulWidget {
  final AppData data;
  const ProfilePage({super.key, required this.data});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _tab = 0;

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null || !mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final ok = await widget.data.updateAvatar(File(picked.path));
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, ok ? 'تم تحديث الأيقونة.' : 'تعذر تحديث الأيقونة.');
  }

  Future<void> _changeName() async {
    final ctrl = TextEditingController(text: widget.data.currentDisplayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تغيير اسم القناة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('ملاحظة: اسم المدير (للدخول) لا يتغير. هذا اسمك الذي يظهر للجميع.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'اسم القناة الجديد')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      final ok = await widget.data.changeMyName(newName);
      if (mounted) showSnack(context, ok ? 'تم تغيير اسم القناة للجميع.' : 'تعذر التغيير.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.data,
      builder: (context, _) {
        final badge = widget.data.currentBadge;
        final avatar = widget.data.currentAvatar;
        final myPosts = widget.data.myPosts;
        final liked = widget.data.myLikedPosts;
        final saved = widget.data.posts.where((p) => widget.data.isPostSaved(p['id'])).toList();
        final primary = ThemeManager.instance.primaryColor;

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.data.currentDisplayName),
            actions: [IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemePickerPage())), icon: const Icon(Icons.palette))],
          ),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Stack(children: [
                    GestureDetector(
                      onTap: () => showAvatarDialog(context, avatar, widget.data.currentDisplayName),
                      child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primary, width: 3), boxShadow: ThemeManager.instance.getGlowShadow()), child: CircleAvatar(radius: 45, backgroundColor: AppColors.inputBlack, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, size: 45, color: AppColors.gold) : null)),
                    ),
                    Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _pickAvatar, child: Container(decoration: BoxDecoration(color: primary, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)), padding: const EdgeInsets.all(8), child: const Icon(Icons.camera_alt, size: 20, color: Colors.white)))),
                  ]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(widget.data.currentDisplayName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primary)),
                    IconButton(onPressed: _changeName, icon: Icon(Icons.edit, size: 18, color: primary)),
                  ]),
                  Text('ID: ${widget.data.currentAccountId} | ${widget.data.currentLevel}'),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    GestureDetector(onTap: () => setState(() => _tab = 0), child: _statTikTok('${myPosts.length}', 'منشورات')),
                    Container(width: 1, height: 30, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 20)),
                    GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowersPage(data: widget.data, showFollowers: true, accountId: widget.data.currentAccountId!))), child: _statTikTok('${widget.data.myFollowersCount}', 'متابع')),
                    Container(width: 1, height: 30, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 20)),
                    GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FollowersPage(data: widget.data, showFollowers: false, accountId: widget.data.currentAccountId!))), child: _statTikTok('${widget.data.myFollowingCount}', 'يتابع')),
                  ]),
                  if (badge != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${badge.icon} ${badge.name}')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(gradient: ThemeManager.instance.getButtonGradient(), borderRadius: BorderRadius.circular(30), boxShadow: ThemeManager.instance.getGlowShadow()),
                  child: Material(color: Colors.transparent, child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreatePostPage(data: widget.data))),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.add, size: 28, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text('نشر منشور في قناتك', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ])),
                  )),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  if (widget.data.isAdmin) ...[
                    ServiceTile(icon: Icons.admin_panel_settings, title: 'لوحة الإدارة', subtitle: 'إدارة التطبيق', colorIndex: 11, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPanelPage(data: widget.data)))),
                    ServiceTile(icon: Icons.bar_chart, title: 'إحصائيات المدير', subtitle: 'أرقام مفصلة', colorIndex: 0, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminStatsPage(data: widget.data)))),
                    ServiceTile(icon: Icons.flag, title: 'البلاغات', subtitle: '${widget.data.complaints.where((c) => c['status'] == 'pending').length} بلاغ معلق', colorIndex: 4, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageComplaintsPage(data: widget.data)))),
                  ],
                  ServiceTile(icon: Icons.palette, title: 'الثيمات', subtitle: 'تغيير لون التطبيق', colorIndex: 6, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemePickerPage()))),
                  ServiceTile(icon: Icons.volume_up, title: 'أصوات التطبيق', subtitle: 'الاهتزاز والصوت', colorIndex: 5, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SoundsPage()))),
                ]),
              ),
              const Divider(),
              Row(children: [
                _tabBtn(Icons.grid_on, 'منشوراتي', 0),
                _tabBtn(Icons.favorite, 'أعجبني', 1),
                _tabBtn(Icons.bookmark, 'محفوظاتي', 2),
              ]),
              if (_tab == 0)
                if (myPosts.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد منشورات')))
                else ...myPosts.map((p) => PostCard(data: widget.data, post: p)),
              if (_tab == 1)
                if (liked.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لم تعجب بأي منشور بعد')))
                else ...liked.map((p) => PostCard(data: widget.data, post: p)),
              if (_tab == 2)
                if (saved.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد منشورات محفوظة')))
                else ...saved.map((p) => PostCard(data: widget.data, post: p)),
            ],
          ),
        );
      },
    );
  }

  Widget _statTikTok(String value, String label) => Column(children: [
    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
  ]);

  Widget _tabBtn(IconData icon, String label, int tab) {
    final isSelected = _tab == tab;
    final primary = ThemeManager.instance.primaryColor;
    return Expanded(child: InkWell(
      onTap: () => setState(() => _tab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isSelected ? primary : Colors.transparent, width: 2))),
        child: Column(children: [
          Icon(icon, color: isSelected ? primary : Colors.grey),
          Text(label, style: TextStyle(fontSize: 11, color: isSelected ? primary : Colors.grey)),
        ]),
      ),
    ));
  }
}

// =======================================================
// 4. صفحة إنشاء منشور (TikTok-style)
// =======================================================
class CreatePostPage extends StatefulWidget {
  final AppData data;
  const CreatePostPage({super.key, required this.data});
  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final textCtrl = TextEditingController();
  File? _image;
  File? _video;
  int _remainingVideos = 5;
  bool _loadingInfo = true;

  @override
  void initState() { super.initState(); _loadRemaining(); }

  Future<void> _loadRemaining() async {
    final remaining = await widget.data.getRemainingVideos();
    if (mounted) setState(() { _remainingVideos = remaining; _loadingInfo = false; });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) setState(() { _image = File(picked.path); _video = null; });
  }

  Future<void> _pickVideo() async {
    if (_remainingVideos <= 0) { showSnack(context, 'وصلت للحد الأقصى: 5 فيديوهات شهرياً.'); return; }
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 5));
    if (picked != null) {
      final size = await File(picked.path).length();
      if (size > 5 * 1024 * 1024) { if (mounted) showSnack(context, 'الفيديو كبير (${(size / 1024 / 1024).toStringAsFixed(1)}MB). الحد 5MB.'); return; }
      setState(() { _video = File(picked.path); _image = null; });
    }
  }

  Future<void> _post() async {
    if (textCtrl.text.trim().isEmpty && _image == null && _video == null) return;
    final content = textCtrl.text;
    final image = _image;
    final video = _video;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Row(children: const [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        SizedBox(width: 12),
        Expanded(child: Text('جاري النشر...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      ]),
      duration: const Duration(minutes: 5), behavior: SnackBarBehavior.floating, backgroundColor: AppColors.cardBlack,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: ThemeManager.instance.primaryColor.withOpacity(0.5))),
    ));
    try {
      final error = await widget.data.addPost(content, image, videoFile: video);
      messenger.hideCurrentSnackBar();
      if (error == null) {
        messenger.showSnackBar(SnackBar(
          content: const Row(children: [Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8), Text('تم النشر بنجاح!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
          backgroundColor: Colors.green.shade700, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Row(children: [const Icon(Icons.error, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(error, style: const TextStyle(color: Colors.white)))]),
          backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('❌ خطأ غير متوقع: $e'), backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating));
    }
  }

  @override
  void dispose() { textCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final canPostVideo = _remainingVideos > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('نشر منشور')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          if (!_loadingInfo)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: canPostVideo ? LinearGradient(colors: [Colors.green.withOpacity(0.3), Colors.green.withOpacity(0.1)]) : LinearGradient(colors: [Colors.red.withOpacity(0.3), Colors.red.withOpacity(0.1)]),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: canPostVideo ? Colors.green : Colors.red),
              ),
              child: Row(children: [
                Icon(canPostVideo ? Icons.videocam : Icons.block, color: canPostVideo ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(canPostVideo ? 'متبقي لك $_remainingVideos فيديو من 5 هذا الشهر' : 'وصلت للحد الأقصى (5 فيديوهات). يتجدد الشهر القادم.', style: TextStyle(fontWeight: FontWeight.bold, color: canPostVideo ? Colors.green : Colors.red))),
              ]),
            ),
          const SizedBox(height: 12),
          TextField(controller: textCtrl, maxLines: 5, decoration: const InputDecoration(hintText: 'بماذا تفكر يا أوتاكو؟')),
          const SizedBox(height: 12),
          if (_image != null) Stack(alignment: Alignment.topRight, children: [
            Image.file(_image!, height: 200, width: double.infinity, fit: BoxFit.cover),
            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => _image = null)),
          ]),
          if (_video != null) Stack(alignment: Alignment.topRight, children: [
            Container(height: 200, width: double.infinity, color: Colors.black, child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam, color: AppColors.gold, size: 60), Text('فيديو 5 ثوان جاهز', style: TextStyle(color: AppColors.gold))]))),
            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => _video = null)),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            OutlinedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.image, size: 18), label: const Text('صورة')),
            OutlinedButton.icon(onPressed: canPostVideo ? _pickVideo : null, icon: Icon(Icons.videocam, size: 18, color: canPostVideo ? null : Colors.grey), label: Text('فيديو ($_remainingVideos/5)', style: TextStyle(color: canPostVideo ? null : Colors.grey))),
          ]),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _post, icon: const Icon(Icons.send), label: const Text('نشر'))),
        ]),
      ),
    );
  }
}

// =======================================================
// 5. الخدمات
// =======================================================
class ServicesPage extends StatelessWidget {
  final AppData data;
  const ServicesPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخدمات')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ServiceTile(icon: Icons.bar_chart, title: 'إحصائياتي', subtitle: 'نشاطك بالأرقام', colorIndex: 0, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyStatsPage(data: data)))),
        ServiceTile(icon: Icons.workspace_premium, title: 'شهادات الإنجاز', subtitle: 'شهاداتك', colorIndex: 6, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CertificatesPage(data: data)))),
        ServiceTile(icon: Icons.trending_up, title: 'لوحة التقدم', subtitle: 'تقدمك', colorIndex: 2, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgressPage(data: data)))),
        ServiceTile(icon: Icons.emoji_events, title: 'خزانة الجوائز', subtitle: 'جوائزك', colorIndex: 1, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RewardsPage(data: data)))),
        ServiceTile(icon: Icons.photo_library, title: 'معرض الصور', subtitle: 'معرض المجتمع', badge: data.hasNewGallery, colorIndex: 3, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GalleryPage(data: data))).then((_) => data.markGallerySeen())),
        ServiceTile(icon: Icons.quiz, title: 'لعبة الأسئلة', subtitle: 'اختبر نفسك', badge: data.hasNewQuiz, colorIndex: 4, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionsHubPage(data: data)))),
        ServiceTile(icon: Icons.leaderboard, title: 'المتصدرون', subtitle: 'الترتيب', colorIndex: 7, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaderboardPage(data: data)))),
        ServiceTile(icon: Icons.message, title: 'رسالة للإدارة', subtitle: 'تواصل', colorIndex: 9, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SendMessagePage(data: data)))),
      ]),
    );
  }
}

class ServiceTile extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap; final bool badge; final int colorIndex;
  const ServiceTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap, required this.colorIndex, this.badge = false});
  @override
  Widget build(BuildContext context) {
    final color = AppColors.getColor(colorIndex);
    return Card(
      margin: const EdgeInsets.only(bottom: 12), elevation: 4, shadowColor: color.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withOpacity(0.3))),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: [color.withOpacity(0.15), color.withOpacity(0.05)])),
        child: ListTile(
          onTap: onTap,
          leading: Badge(isLabelVisible: badge, backgroundColor: Colors.red, child: CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white))),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.arrow_back_ios, size: 18),
        ),
      ),
    );
  }
}

// =======================================================
// 6. إحصائياتي
// =======================================================
class MyStatsPage extends StatelessWidget {
  final AppData data;
  const MyStatsPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('إحصائياتي')), body: AnimatedBuilder(animation: data, builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
      _statCard('📝', 'منشوراتي', '${data.myPostsCount}', 'منشور'),
      _statCard('❤️', 'الإعجابات المستلمة', '${data.myReceivedLikes}', 'إعجاب'),
      _statCard('👥', 'المتابعون', '${data.myFollowersCount}', 'متابع'),
      _statCard('👤', 'يتابع', '${data.myFollowingCount}', 'حساب'),
      _statCard('⭐', 'نقاطي', '${data.currentPoints}', 'نقطة'),
      _statCard('🎖️', 'المستوى', data.currentLevel, ''),
      _statCard('🏅', 'الجوائز', '${data.userRewards.length}', 'جائزة'),
    ])));
  }
  Widget _statCard(String icon, String title, String value, String suffix) => Card(margin: const EdgeInsets.only(bottom: 12), child: ListTile(leading: Text(icon, style: const TextStyle(fontSize: 40)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)), trailing: Text('$value $suffix', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))));
}

class CertificatesPage extends StatelessWidget {
  final AppData data;
  const CertificatesPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('شهادات الإنجاز')), body: AnimatedBuilder(animation: data, builder: (context, _) {
      final certs = buildCertificates(postsCount: data.myPostsCount, receivedLikes: data.myReceivedLikes, points: data.currentPoints, level: data.currentLevel);
      return ListView.builder(padding: const EdgeInsets.all(16), itemCount: certs.length, itemBuilder: (_, i) {
        final c = certs[i]; final color = c.unlocked ? AppColors.gold : Colors.grey;
        return Card(color: c.unlocked ? AppColors.getColor(6).withOpacity(0.15) : AppColors.cardBlack, child: ListTile(
          leading: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2)), padding: const EdgeInsets.all(8), child: Text(c.icon, style: TextStyle(fontSize: 32, color: c.unlocked ? null : Colors.grey))),
          title: Text(c.title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          subtitle: Text(c.description, style: const TextStyle(fontSize: 12)),
          trailing: Icon(c.unlocked ? Icons.verified : Icons.lock, color: color, size: 28),
        ));
      });
    }));
  }
}

class ProgressPage extends StatelessWidget {
  final AppData data;
  const ProgressPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('لوحة التقدم')), body: AnimatedBuilder(animation: data, builder: (context, _) {
      final points = data.currentPoints; final nextBadge = data.nextBadge; final currentBadge = data.currentBadge;
      final currentPts = currentBadge?.points ?? 0; final nextPts = nextBadge?.points ?? points;
      final range = nextPts - currentPts; final progress = range > 0 ? ((points - currentPts) / range).clamp(0.0, 1.0) : 1.0;
      return ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          const Text('نقاطك الحالية', style: TextStyle(color: Colors.grey)),
          Text('$points', style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: AppColors.gold)),
          Text('المستوى: ${data.currentLevel}', style: const TextStyle(fontSize: 18)),
        ]))),
        const SizedBox(height: 16),
        if (nextBadge != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Row(children: [Text(currentBadge?.icon ?? '', style: const TextStyle(fontSize: 32)), const Spacer(), Text(nextBadge.icon, style: const TextStyle(fontSize: 32))]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: progress, minHeight: 20, backgroundColor: Colors.grey.shade800, valueColor: AlwaysStoppedAnimation(AppColors.getColor(2)))),
          const SizedBox(height: 8),
          Center(child: Text('${(progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          Center(child: Text('الشارة القادمة: ${nextBadge.name} (${nextPts - points} نقطة متبقية)', style: const TextStyle(fontSize: 12))),
        ]))),
      ]);
    }));
  }
}

class SoundsPage extends StatefulWidget {
  const SoundsPage({super.key});
  @override
  State<SoundsPage> createState() => _SoundsPageState();
}

class _SoundsPageState extends State<SoundsPage> {
  bool _soundEnabled = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final prefs = await SharedPreferences.getInstance(); setState(() => _soundEnabled = prefs.getBool('mr_otaku_sound_enabled') ?? true); }
  Future<void> _toggle(bool v) async { final prefs = await SharedPreferences.getInstance(); await prefs.setBool('mr_otaku_sound_enabled', v); setState(() => _soundEnabled = v); if (v) await playClickSound(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('أصوات التطبيق')), body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: SwitchListTile(title: const Text('الصوت/الاهتزاز', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)), subtitle: const Text('اهتزاز عند الضغط على الأزرار'), value: _soundEnabled, onChanged: _toggle, activeColor: AppColors.gold)),
    ]));
  }
}

// =======================================================
// 7. الأخبار + التعليقات
// =======================================================
class NewsPage extends StatelessWidget {
  final AppData data;
  const NewsPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('الأخبار')), body: RefreshIndicator(onRefresh: data.loadData, child: data.news.isEmpty ? ListView(children: const [SizedBox(height: 200), Center(child: Text('لا توجد أخبار'))]) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: data.news.length, itemBuilder: (_, index) => NewsCard(data: data, news: data.news[index]))));
  }
}

class NewsCard extends StatelessWidget {
  final AppData data; final Map<String, dynamic> news;
  const NewsCard({super.key, required this.data, required this.news});
  @override
  Widget build(BuildContext context) {
    final id = news['id']; final image = clean(news['image_url']); final liked = data.likedNews.contains(id.toString());
    return Card(margin: const EdgeInsets.only(bottom: 14), clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (image.isNotEmpty) CachedNetworkImage(imageUrl: image, width: double.infinity, height: 210, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox(height: 210, child: Icon(Icons.broken_image, size: 50, color: AppColors.gold))),
      Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(clean(news['title']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.gold)),
        const SizedBox(height: 8),
        Text(clean(news['description'])),
        const SizedBox(height: 10),
        Row(children: [
          IconButton(onPressed: () async { await playClickSound(); await data.toggleLike(id); }, icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : AppColors.gold)),
          Text('${data.likeCounts[id] ?? 0}'),
          const SizedBox(width: 12),
          IconButton(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => CommentsPage(data: data, newsId: id))); }, icon: const Icon(Icons.comment_outlined)),
          Text('${data.commentCounts[id] ?? 0}'),
        ]),
      ])),
    ]));
  }
}

class NewsDetailsPage extends StatelessWidget {
  final Map<String, dynamic> news;
  const NewsDetailsPage({super.key, required this.news});
  @override
  Widget build(BuildContext context) {
    final image = clean(news['image_url']);
    return Scaffold(appBar: AppBar(title: const Text('الخبر')), body: ListView(padding: const EdgeInsets.all(16), children: [
      if (image.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(18), child: CachedNetworkImage(imageUrl: image, height: 230, fit: BoxFit.cover)),
      const SizedBox(height: 15),
      Text(clean(news['title']), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: AppColors.gold)),
      const SizedBox(height: 12),
      Text(clean(news['description']), style: const TextStyle(fontSize: 17, height: 1.6)),
    ]));
  }
}

// =======================================================
// ✅ تعليقات الأخبار (مُصلحة: الأسماء والأيقونات تظهر للجميع)
// =======================================================
class CommentsPage extends StatefulWidget {
  final AppData data; final dynamic newsId;
  const CommentsPage({super.key, required this.data, required this.newsId});
  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  List<Map<String, dynamic>> comments = [];
  bool loading = true;
  String? _replyTo;
  File? _image;

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async { await widget.data.loadPlayers(); await widget.data.loadCommentLikes(); final result = await widget.data.getComments(widget.newsId); if (!mounted) return; setState(() { comments = result; loading = false; }); }
  Future<void> _pickImage() async { final picker = ImagePicker(); final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70); if (picked != null) setState(() => _image = File(picked.path)); }
  Future<void> send() async {
    if (controller.text.trim().isEmpty && _image == null) return;
    await playClickSound();
    final ok = await widget.data.addComment(widget.newsId, widget.data.currentDisplayName, controller.text, replyTo: _replyTo, imageFile: _image);
    if (!mounted) return;
    if (ok) { controller.clear(); setState(() { _replyTo = null; _image = null; }); await load(); }
  }
  void _startReply(String userName) { setState(() => _replyTo = userName); focusNode.requestFocus(); }
  @override
  void dispose() { controller.dispose(); focusNode.dispose(); super.dispose(); }

  String _displayNameFor(Map<String, dynamic> item) {
    final accId = item['account_id'];
    if (accId != null) {
      final viaAcc = widget.data.displayNameForAccount(accId);
      if (viaAcc.isNotEmpty) return viaAcc;
    }
    final stored = clean(item['user_name']).trim();
    return stored.isEmpty ? 'مستخدم' : stored;
  }

  String _avatarFor(Map<String, dynamic> item) {
    final accId = item['account_id'];
    if (accId != null) {
      final viaAcc = widget.data.avatarForAccount(accId);
      if (viaAcc.isNotEmpty) return viaAcc;
    }
    final stored = clean(item['user_name']).trim().toLowerCase();
    if (stored.isEmpty) return '';
    for (final p in widget.data.players) {
      final pName = clean(p['name']).trim().toLowerCase();
      final pChannel = clean(p['channel_name']).trim().toLowerCase();
      if (pName == stored || pChannel == stored) {
        return clean(p['avatar_url']);
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('التعليقات')), body: Column(children: [
      Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : comments.isEmpty ? const Center(child: Text('لا توجد تعليقات')) : AnimatedBuilder(animation: widget.data, builder: (context, _) => ListView.builder(
        padding: const EdgeInsets.all(12), itemCount: comments.length,
        itemBuilder: (_, index) {
          final item = comments[index];
          final name = _displayNameFor(item);
          final replyTo = clean(item['reply_to']);
          final img = clean(item['image_url']);
          final url = _avatarFor(item);
          final cid = item['id'];
          final isLiked = widget.data.isCommentLiked(cid, 'news');
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => showAvatarDialog(context, url, name),
                child: CircleAvatar(radius: 18, backgroundColor: AppColors.gold, backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null, child: url.isEmpty ? const Icon(Icons.person, color: Colors.black, size: 18) : null),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name)))),
              IconButton(icon: const Icon(Icons.reply, color: AppColors.gold, size: 20), onPressed: () => _startReply(name)),
            ]),
            const SizedBox(height: 6),
            if (replyTo.isNotEmpty) Text('↩️ رداً على $replyTo', style: TextStyle(fontSize: 11, color: AppColors.gold, fontStyle: FontStyle.italic)),
            if (clean(item['comment_text']).isNotEmpty) Text(clean(item['comment_text'])),
            if (img.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: img, height: 120, fit: BoxFit.cover))),
            const SizedBox(height: 6),
            Row(children: [
              IconButton(onPressed: () async { await widget.data.toggleCommentLike(cid, 'news'); }, icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : AppColors.gold, size: 18)),
              Text('${widget.data.commentLikesCount(cid, 'news')}', style: const TextStyle(fontSize: 12)),
            ]),
          ])));
        },
      ))),
      if (_replyTo != null) Container(padding: const EdgeInsets.all(8), color: AppColors.gold.withOpacity(0.15), child: Row(children: [const Icon(Icons.reply, size: 18, color: AppColors.gold), Expanded(child: Text('الرد على $_replyTo', style: const TextStyle(color: AppColors.gold, fontSize: 13))), IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null))])),
      if (_image != null) Container(padding: const EdgeInsets.all(8), color: AppColors.cardBlack, child: Row(children: [const Icon(Icons.image, color: AppColors.gold), const SizedBox(width: 8), const Expanded(child: Text('صورة جاهزة')), IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 18), onPressed: () => setState(() => _image = null))])),
      Padding(padding: const EdgeInsets.all(10), child: Row(children: [
        IconButton(icon: const Icon(Icons.image, color: AppColors.gold), onPressed: _pickImage),
        Expanded(child: TextField(controller: controller, focusNode: focusNode, decoration: InputDecoration(hintText: _replyTo == null ? 'اكتب تعليقك' : 'الرد على $_replyTo'))),
        IconButton(onPressed: send, icon: const Icon(Icons.send)),
      ])),
    ]));
  }
}

class NotificationsPage extends StatelessWidget {
  final AppData data;
  const NotificationsPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('الإشعارات'), actions: [if (data.notifications.isNotEmpty) IconButton(onPressed: () => data.markAllNotificationsRead(), icon: const Icon(Icons.done_all))]), body: data.notifications.isEmpty ? const Center(child: Text('لا توجد إشعارات')) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: data.notifications.length, itemBuilder: (_, index) { final item = data.notifications[index]; final read = data.isNotificationRead(item['id']); return Card(child: ListTile(leading: Icon(read ? Icons.notifications_none : Icons.notifications_active, color: read ? Colors.grey : AppColors.gold), title: Text(clean(item['title']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)), subtitle: Text(clean(item['body'])), onTap: () => data.markNotificationRead(item['id']))); }));
  }
}