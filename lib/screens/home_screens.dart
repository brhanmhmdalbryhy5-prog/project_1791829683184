import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';
import 'social_screens.dart';
import 'admin_screens.dart';
import 'games_screens.dart';

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
    _playersRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) async => await widget.data.loadPlayers());
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
          setState(() => index = value);
          if (value == 0) await widget.data.markImportantNewsSeen();
          if (value == 1) await widget.data.markNewsSeen();
          if (value == 2) { await widget.data.markQuizSeen(); await widget.data.markGallerySeen(); }
          if (value == 3) await widget.data.markAllNotificationsRead();
        },
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: widget.data.hasNewImportantNews, backgroundColor: AppColors.gold, child: const Icon(Icons.home_outlined)),
            selectedIcon: const Icon(Icons.home),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: widget.data.hasNewNews, backgroundColor: AppColors.gold, child: const Icon(Icons.newspaper_outlined)),
            selectedIcon: const Icon(Icons.newspaper),
            label: 'الأخبار',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: widget.data.hasNewQuiz || widget.data.hasNewGallery, backgroundColor: AppColors.gold, child: const Icon(Icons.apps_outlined)),
            selectedIcon: const Icon(Icons.apps),
            label: 'الخدمات',
          ),
          NavigationDestination(
            icon: Badge(isLabelVisible: widget.data.unreadNotificationCount > 0, backgroundColor: AppColors.gold, label: Text(widget.data.unreadNotificationCount.toString(), style: const TextStyle(color: Colors.black)), child: const Icon(Icons.settings_outlined)),
            selectedIcon: const Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

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
    final leader = widget.data.leader;
    return Scaffold(
      appBar: AppBar(
        title: const Text('مستر أوتاكو', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(data: widget.data))),
            icon: Badge(isLabelVisible: widget.data.unreadNotificationCount > 0, backgroundColor: AppColors.gold, label: Text(widget.data.unreadNotificationCount.toString(), style: const TextStyle(color: Colors.black)), child: const Icon(Icons.notifications)),
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
                decoration: BoxDecoration(color: AppColors.black, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.gold, width: 2), boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.2), blurRadius: 12, spreadRadius: 1)]),
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.campaign, color: AppColors.gold, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('إعلان مهم', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(widget.data.importantNews, style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ])),
                ]),
              ),
            if (widget.data.importantNews.trim().isNotEmpty) const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: AppColors.black, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.gold)), child: const Center(child: Text('من تطوير برهان البريهي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.gold)))),
            const SizedBox(height: 16),
            if (widget.data.news.isNotEmpty)
              SizedBox(
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
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.borderGold)),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(fit: StackFit.expand, children: [
                          if (image.isNotEmpty) Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.cardBlack, child: const Icon(Icons.newspaper, size: 50, color: AppColors.gold))) else Container(color: AppColors.cardBlack, child: const Icon(Icons.newspaper, size: 50, color: AppColors.gold)),
                          Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])), child: Text(clean(item['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.gold)))),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
              GestureDetector(onTap: () => showAvatarDialog(context, widget.data.currentAvatar, widget.data.currentUserName), child: CircleAvatar(radius: 40, backgroundColor: AppColors.inputBlack, backgroundImage: widget.data.currentAvatar.isNotEmpty ? NetworkImage(widget.data.currentAvatar) : null, child: widget.data.currentAvatar.isEmpty ? const Icon(Icons.person, size: 40, color: AppColors.gold) : null)),
              const SizedBox(height: 10),
              Text('مرحباً ${widget.data.currentUserName}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: AppColors.gold)),
              const SizedBox(height: 8),
              const Text('مجتمع ومسابقات وأخبار الأنمي'),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _MiniStat(title: 'النقاط', value: widget.data.currentPoints.toString()),
                const SizedBox(width: 25),
                _MiniStat(title: 'المستوى', value: widget.data.currentLevel),
              ]),
            ]))),
            const SizedBox(height: 16),
            if (leader != null)
              Card(child: ListTile(
                leading: GestureDetector(onTap: () => showAvatarDialog(context, clean(leader['avatar_url']), clean(leader['name'])), child: CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: clean(leader['avatar_url']).isNotEmpty ? NetworkImage(clean(leader['avatar_url'])) : null, child: clean(leader['avatar_url']).isEmpty ? const Icon(Icons.emoji_events, color: Colors.black) : null)),
                title: const Text('متصدر الأوتاكو', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
                subtitle: Text(clean(leader['name'])),
                trailing: Text('${parseInt(leader['points'])} نقطة'),
              )),
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('كل جديد', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: AppColors.gold)),
              const SizedBox(height: 10),
              if (widget.data.latest.isEmpty) const Text('لا يوجد جديد حالياً.')
              else ...widget.data.latest.take(5).map((item) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.campaign), title: Text(clean(item['title'])), subtitle: Text(clean(item['description'])))),
            ]))),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title; final String value;
  const _MiniStat({required this.title, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.gold)),
      Text(title, style: TextStyle(color: AppColors.gold.withOpacity(0.7))),
    ]);
  }
}

class ServicesPage extends StatelessWidget {
  final AppData data;
  const ServicesPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخدمات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ServiceTile(icon: Icons.post_add, title: 'المنشورات (تويتر)', subtitle: 'شارك أفكارك وصورك مع الجميع', colorIndex: 0, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostsPage(data: data)))),
          ServiceTile(icon: Icons.emoji_events, title: 'خزانة الجوائز', subtitle: 'شاهد الجوائز التي حصلت عليها', colorIndex: 1, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RewardsPage(data: data)))),
          ServiceTile(icon: Icons.forum, title: 'الرسائل الخاصة', subtitle: 'تحدث مع أصدقائك بشكل خاص', colorIndex: 2, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PrivateMessagesPage(data: data)))),
          ServiceTile(icon: Icons.photo_library, title: 'معرض الصور', subtitle: 'شارك صورك المفضلة مع المجتمع', badge: data.hasNewGallery, colorIndex: 3, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GalleryPage(data: data))).then((_) => data.markGallerySeen())),
          ServiceTile(icon: Icons.quiz, title: 'لعبة الأسئلة', subtitle: 'ثلاثة أنواع من الأسئلة', badge: data.hasNewQuiz, colorIndex: 4, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionsHubPage(data: data)))),
          ServiceTile(icon: Icons.chat, title: 'الدردشة العامة', subtitle: 'تحدث مع مجتمع مستر أوتاكو', colorIndex: 5, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicChatPage(data: data)))),
          ServiceTile(icon: Icons.sports_esports, title: 'لعبة القفز', subtitle: 'اقفز فوق الصخور وحطم رقمك', colorIndex: 6, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JumpGamePage(data: data)))),
          ServiceTile(icon: Icons.leaderboard, title: 'المتصدرون', subtitle: 'شاهد ترتيب لاعبي الأوتاكو', colorIndex: 7, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaderboardPage(data: data)))),
          ServiceTile(icon: Icons.shopping_bag, title: 'متجر النقاط', subtitle: 'استخدم نقاطك للحصول على المزايا', colorIndex: 8, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopPage(data: data)))),
          ServiceTile(icon: Icons.message, title: 'إرسال رسالة للإدارة', subtitle: 'تواصل مع إدارة مستر أوتاكو', colorIndex: 9, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SendMessagePage(data: data)))),
        ],
      ),
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
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: Badge(isLabelVisible: badge, backgroundColor: Colors.red, child: CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white))),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_back_ios, size: 18),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final AppData data;
  const SettingsPage({super.key, required this.data});

  Future<void> _pickAvatar(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null) return;
    if (!context.mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.gold)));
    final ok = await data.updateAvatar(File(picked.path));
    if (!context.mounted) return;
    Navigator.pop(context);
    showSnack(context, ok ? 'تم تحديث الأيقونة.' : 'تعذر تحديث الأيقونة.');
  }

  Future<void> logout(BuildContext context) async {
    await playClickSound();
    await data.logoutAccount();
  }

  @override
  Widget build(BuildContext context) {
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
              Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
                Stack(children: [
                  GestureDetector(
                    onTap: () => showAvatarDialog(context, avatar, data.currentUserName),
                    child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.gold, width: 3)), child: CircleAvatar(radius: 45, backgroundColor: AppColors.inputBlack, backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, size: 45, color: AppColors.gold) : null)),
                  ),
                  Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: () => _pickAvatar(context), child: Container(decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle, border: Border.all(color: AppColors.black, width: 2)), padding: const EdgeInsets.all(8), child: const Icon(Icons.camera_alt, size: 20, color: Colors.black)))),
                ]),
                const SizedBox(height: 12),
                Text(data.currentUserName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: AppColors.gold)),
                Text('معرف الحساب: ${data.currentAccountId}'),
                Text('المستوى: ${data.currentLevel}'),
                Text('النقاط: ${data.currentPoints}'),
                if (badge != null) Text('${badge.icon} ${badge.name}'),
                if (data.userRewards.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 8, children: data.userRewards.map((r) => Text(clean(r['reward_icon']), style: const TextStyle(fontSize: 24))).toList())),
              ]))),
              const SizedBox(height: 12),
              ServiceTile(icon: Icons.notifications, title: 'الإشعارات', subtitle: 'عرض إشعارات الإدارة', colorIndex: 10, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(data: data)))),
              if (data.isAdmin)
                ServiceTile(icon: Icons.admin_panel_settings, title: 'لوحة الإدارة', subtitle: 'إدارة التطبيق', colorIndex: 11, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPanelPage(data: data)))),
              Card(child: ListTile(leading: const Icon(Icons.logout), title: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)), onTap: () => logout(context))),
            ],
          ),
        );
      },
    );
  }
}

class NewsPage extends StatelessWidget {
  final AppData data;
  const NewsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأخبار')),
      body: RefreshIndicator(
        onRefresh: data.loadData,
        child: data.news.isEmpty
            ? ListView(children: const [SizedBox(height: 200), Center(child: Text('لا توجد أخبار حالياً.'))])
            : ListView.builder(padding: const EdgeInsets.all(12), itemCount: data.news.length, itemBuilder: (_, index) => NewsCard(data: data, news: data.news[index])),
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  final AppData data; final Map<String, dynamic> news;
  const NewsCard({super.key, required this.data, required this.news});

  @override
  Widget build(BuildContext context) {
    final id = news['id'];
    final image = clean(news['image_url']);
    final liked = data.likedNews.contains(id.toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (image.isNotEmpty) Image.network(image, width: double.infinity, height: 210, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 210, child: Center(child: Icon(Icons.broken_image, size: 50, color: AppColors.gold)))),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(clean(news['title']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.gold)),
          const SizedBox(height: 8),
          Text(clean(news['description'])),
          const SizedBox(height: 10),
          Row(children: [
            IconButton(onPressed: () async { await playClickSound(); await data.toggleLike(id); }, icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : AppColors.gold)),
            Text('${data.likeCounts[id] ?? 0}'),
            const SizedBox(width: 12),
            IconButton(onPressed: () async { await playClickSound(); if (!context.mounted) return; Navigator.push(context, MaterialPageRoute(builder: (_) => CommentsPage(data: data, newsId: id))); }, icon: const Icon(Icons.comment_outlined)),
            Text('${data.commentCounts[id] ?? 0}'),
          ]),
        ])),
      ]),
    );
  }
}

class NewsDetailsPage extends StatelessWidget {
  final Map<String, dynamic> news;
  const NewsDetailsPage({super.key, required this.news});

  @override
  Widget build(BuildContext context) {
    final image = clean(news['image_url']);
    return Scaffold(
      appBar: AppBar(title: const Text('الخبر')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (image.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(image, height: 230, fit: BoxFit.cover)),
        const SizedBox(height: 15),
        Text(clean(news['title']), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: AppColors.gold)),
        const SizedBox(height: 12),
        Text(clean(news['description']), style: const TextStyle(fontSize: 17, height: 1.6)),
      ]),
    );
  }
}

class CommentsPage extends StatefulWidget {
  final AppData data; final dynamic newsId;
  const CommentsPage({super.key, required this.data, required this.newsId});
  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  bool loading = true;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    await widget.data.loadPlayers();
    final result = await widget.data.getComments(widget.newsId);
    if (!mounted) return;
    setState(() { comments = result; loading = false; });
  }

  Future<void> send() async {
    if (controller.text.trim().isEmpty) return;
    await playClickSound();
    final ok = await widget.data.addComment(widget.newsId, widget.data.currentUserName, controller.text);
    if (!mounted) return;
    if (ok) { controller.clear(); await load(); } else { showSnack(context, 'تعذر إرسال التعليق.'); }
  }

  @override
  void dispose() { controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التعليقات')),
      body: Column(children: [
        Expanded(
          child: loading ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : comments.isEmpty ? const Center(child: Text('لا توجد تعليقات بعد.'))
              : AnimatedBuilder(
                  animation: widget.data,
                  builder: (context, _) {
                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: comments.length,
                      itemBuilder: (_, index) {
                        final item = comments[index];
                        final name = clean(item['user_name']);
                        final url = widget.data.avatarForName(name);
                        return Card(child: ListTile(
                          leading: GestureDetector(
                            onTap: () => showAvatarDialog(context, url, name),
                            child: CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: url.isNotEmpty ? NetworkImage(url) : null, child: url.isEmpty ? const Icon(Icons.person, color: Colors.black) : null),
                          ),
                          title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name))),
                          subtitle: Text(clean(item['comment_text'])),
                        ));
                      },
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(child: TextField(controller: controller, decoration: const InputDecoration(labelText: 'اكتب تعليقك'))),
            IconButton(onPressed: send, icon: const Icon(Icons.send)),
          ]),
        ),
      ]),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  final AppData data;
  const NotificationsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات'), actions: [
        if (data.notifications.isNotEmpty) IconButton(onPressed: () async => await data.markAllNotificationsRead(), icon: const Icon(Icons.done_all)),
      ]),
      body: data.notifications.isEmpty
          ? const Center(child: Text('لا توجد إشعارات.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: data.notifications.length,
              itemBuilder: (_, index) {
                final item = data.notifications[index];
                final read = data.isNotificationRead(item['id']);
                return Card(child: ListTile(
                  leading: Icon(read ? Icons.notifications_none : Icons.notifications_active),
                  title: Text(clean(item['title']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
                  subtitle: Text(clean(item['body'])),
                  onTap: () async => await data.markNotificationRead(item['id']),
                ));
              },
            ),
    );
  }
}