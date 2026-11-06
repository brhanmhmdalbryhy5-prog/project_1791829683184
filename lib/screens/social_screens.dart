import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';

// ================= 1. صفحة المنشورات (للعرض فقط الآن) =================
class PostsPage extends StatelessWidget {
  final AppData data;
  const PostsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المنشورات')),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          if (data.posts.isEmpty) return const Center(child: Text('لا توجد منشورات بعد.'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: data.posts.length,
            itemBuilder: (_, i) => PostCard(data: data, post: data.posts[i]),
          );
        },
      ),
    );
  }
}

// 🃏 بطاقة المنشور (مشتركة)
class PostCard extends StatelessWidget {
  final AppData data;
  final Map<String, dynamic> post;
  const PostCard({super.key, required this.data, required this.post});

  @override
  Widget build(BuildContext context) {
    final name = clean(post['user_name']);
    final avatar = data.avatarForAccount(post['account_id']);
    final img = clean(post['image_url']);
    final rewards = data.userRewards.where((r) => r['account_id'] == post['account_id']).toList();
    final myColor = AppColors.getColorForName(name);
    final postId = post['id'];
    final liked = data.likedPosts.contains(postId.toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(
              onTap: () => showAvatarDialog(context, avatar, name),
              child: CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: myColor)),
              if (rewards.isNotEmpty) Wrap(spacing: 4, children: rewards.map((r) => Text(clean(r['reward_icon']), style: const TextStyle(fontSize: 16))).toList()),
            ])),
            if ((data.isAdmin || parseInt(post['account_id']) == data.currentAccountId))
              IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => data.deletePost(postId)),
          ]),
          const SizedBox(height: 10),
          Text(clean(post['content']), style: const TextStyle(fontSize: 16)),
          if (img.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: img, width: double.infinity, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox())),
          ],
          const SizedBox(height: 10),
          Row(children: [
            IconButton(
              onPressed: () async { await playClickSound(); await data.togglePostLike(postId); },
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : AppColors.gold),
            ),
            Text('${data.postLikeCounts[postId] ?? 0}'),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () async { await playClickSound(); showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => PostCommentsSheet(data: data, postId: postId)); },
              icon: const Icon(Icons.comment_outlined, color: AppColors.gold),
            ),
            Text('${data.postCommentCounts[postId] ?? 0}'),
          ]),
        ]),
      ),
    );
  }
}

class PostCommentsSheet extends StatefulWidget {
  final AppData data; final dynamic postId;
  const PostCommentsSheet({super.key, required this.data, required this.postId});
  @override
  State<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  final ctrl = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  bool loading = true;

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async { final res = await widget.data.getPostComments(widget.postId); if (mounted) setState(() { comments = res; loading = false; }); }
  Future<void> send() async { if (ctrl.text.trim().isEmpty) return; final ok = await widget.data.addPostComment(widget.postId, ctrl.text); if (ok) { ctrl.clear(); await load(); } }
  @override
  void dispose() { ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(color: AppColors.cardBlack, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('التعليقات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.gold))),
          Expanded(child: loading ? const Center(child: CircularProgressIndicator(color: AppColors.gold)) : ListView.builder(
            itemCount: comments.length,
            itemBuilder: (_, i) {
              final c = comments[i];
              final name = clean(c['user_name']);
              return ListTile(
                leading: CircleAvatar(backgroundImage: widget.data.avatarForAccount(c['account_id']).isNotEmpty ? CachedNetworkImageProvider(widget.data.avatarForAccount(c['account_id'])) : null, child: widget.data.avatarForAccount(c['account_id']).isEmpty ? const Icon(Icons.person) : null),
                title: Text(name, style: TextStyle(color: AppColors.getColorForName(name), fontWeight: FontWeight.bold)),
                subtitle: Text(clean(c['comment_text'])),
              );
            },
          )),
          Padding(padding: const EdgeInsets.all(10), child: Row(children: [
            Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'أضف تعليقاً...'))),
            IconButton(onPressed: send, icon: const Icon(Icons.send, color: AppColors.gold)),
          ])),
        ]),
      ),
    );
  }
}

// ================= 2. الرسائل الخاصة (مع ميزة المقروء وغير المقروء) =================
class PrivateMessagesPage extends StatelessWidget {
  final AppData data;
  const PrivateMessagesPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        final others = data.players.where((p) => parseInt(p['account_id']) != data.currentAccountId).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('الرسائل')),
          body: others.isEmpty ? const Center(child: Text('لا يوجد مستخدمون آخرون.')) : ListView.builder(
            itemCount: others.length,
            itemBuilder: (_, i) {
              final p = others[i]; 
              final avatar = clean(p['avatar_url']); 
              final name = clean(p['name']);
              final userId = parseInt(p['account_id']);
              final unreadCount = data.unreadMessageCounts[userId] ?? 0; // 👈 جلب عدد الرسائل غير المقروءة

              return Card(child: ListTile(
                leading: GestureDetector(
                  onTap: () => showAvatarDialog(context, avatar, name), 
                  child: CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null)
                ),
                title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name))),
                // 👇 إظهار التنبيه الأحمر
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (unreadCount > 0)
                      Badge(
                        label: Text('$unreadCount'),
                        backgroundColor: Colors.red,
                        textColor: Colors.white,
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.message, color: AppColors.gold),
                  ],
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(data: data, other: p))),
              ));
            },
          ),
        );
      },
    );
  }
}

class ChatScreen extends StatefulWidget {
  final AppData data; final Map<String, dynamic> other;
  const ChatScreen({super.key, required this.data, required this.other});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ctrl = TextEditingController();
  Timer? timer;

  @override
  void initState() { super.initState(); _load(); timer = Timer.periodic(const Duration(seconds: 3), (_) => _load()); }
  Future<void> _load() async => await widget.data.loadPrivateMessages(parseInt(widget.other['account_id']));
  Future<void> _send() async { if (ctrl.text.trim().isEmpty) return; final ok = await widget.data.sendPrivateMessage(parseInt(widget.other['account_id']), ctrl.text); if (ok) { ctrl.clear(); await _load(); } }
  @override
  void dispose() { timer?.cancel(); ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final otherName = clean(widget.other['name']); final otherAvatar = clean(widget.other['avatar_url']);
    return Scaffold(
      appBar: AppBar(title: Row(children: [
        GestureDetector(onTap: () => showAvatarDialog(context, otherAvatar, otherName), child: CircleAvatar(radius: 16, backgroundImage: otherAvatar.isNotEmpty ? CachedNetworkImageProvider(otherAvatar) : null, child: otherAvatar.isEmpty ? const Icon(Icons.person, size: 16) : null)),
        const SizedBox(width: 8), Text(otherName),
      ])),
      body: Column(children: [
        Expanded(child: AnimatedBuilder(animation: widget.data, builder: (context, _) {
          final msgs = widget.data.privateMessages;
          return ListView.builder(reverse: true, padding: const EdgeInsets.all(10), itemCount: msgs.length, itemBuilder: (_, i) {
            final m = msgs[i]; final isMe = parseInt(m['sender_id']) == widget.data.currentAccountId;
            return Align(alignment: isMe ? Alignment.centerRight : Alignment.centerLeft, child: Card(color: isMe ? AppColors.gold.withOpacity(0.2) : AppColors.cardBlack, child: Padding(padding: const EdgeInsets.all(10), child: Text(clean(m['message'])))));
          });
        })),
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'اكتب رسالة...'))),
          IconButton(onPressed: _send, icon: const Icon(Icons.send)),
        ])),
      ]),
    );
  }
}

// ================= 3. المعرض والجوائز =================
class GalleryPage extends StatefulWidget {
  final AppData data;
  const GalleryPage({super.key, required this.data});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  Future<void> pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null || !mounted) return;
    final captionController = TextEditingController();
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('إضافة صورة'), content: TextField(controller: captionController, maxLines: 3, decoration: const InputDecoration(labelText: 'تعليق (اختياري)')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('نشر'))],
    ));
    if (confirm != true) { captionController.dispose(); return; }
    if (!mounted) { captionController.dispose(); return; }
    final messenger = ScaffoldMessenger.of(context);
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.gold)));
    final errorMessage = await widget.data.addGalleryImage(File(picked.path), caption: captionController.text);
    if (!mounted) { captionController.dispose(); return; }
    Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(SnackBar(content: Text(errorMessage == null ? '✅ تم نشر الصورة.' : '❌ $errorMessage'), backgroundColor: errorMessage == null ? Colors.green.shade800 : Colors.red.shade800));
    captionController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معرض الصور'), actions: [IconButton(onPressed: () => widget.data.loadGallery(), icon: const Icon(Icons.refresh))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: pickAndUpload, icon: const Icon(Icons.add_a_photo), label: const Text('أضف صورة')),
      body: AnimatedBuilder(
        animation: widget.data,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: widget.data.loadGallery, color: AppColors.gold,
            child: widget.data.gallery.isEmpty
                ? ListView(children: const [SizedBox(height: 200), Center(child: Text('لا توجد صور بعد.\nكن أول من يشارك صورة!', textAlign: TextAlign.center))])
                : ListView.builder(
                    padding: const EdgeInsets.all(16), itemCount: widget.data.gallery.length,
                    itemBuilder: (_, index) {
                      final item = widget.data.gallery[index];
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GalleryImagePage(data: widget.data, item: item))),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.cardBlack, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.goldDark, width: 3), boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)]),
                          child: Column(children: [
                            AspectRatio(aspectRatio: 1.15, child: CachedNetworkImage(imageUrl: clean(item['image_url']), fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.gold))),
                            const SizedBox(height: 8),
                            Text(clean(item['user_name']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.gold)),
                            if (clean(item['caption']).isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(clean(item['caption']), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                            ],
                          ]),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class GalleryImagePage extends StatelessWidget {
  final AppData data; final Map<String, dynamic> item;
  const GalleryImagePage({super.key, required this.data, required this.item});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(title: Text(clean(item['user_name'])), actions: [
        if (data.isAdmin) IconButton(onPressed: () async { await data.deleteGalleryImage(item['id']); if (context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.delete)),
      ]),
      body: Center(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: clean(item['image_url']), fit: BoxFit.contain, errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 80, color: AppColors.gold)))),
    );
  }
}

class RewardsPage extends StatelessWidget {
  final AppData data;
  const RewardsPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خزانة الجوائز')),
      body: AnimatedBuilder(animation: data, builder: (context, _) => ListView.builder(
        padding: const EdgeInsets.all(16), itemCount: allRewards.length,
        itemBuilder: (_, i) {
          final reward = allRewards[i]; final isUnlocked = data.currentPoints >= reward.requiredPoints; final isClaimed = data.hasReward(reward.name);
          return Card(child: ListTile(
            leading: Text(reward.icon, style: const TextStyle(fontSize: 40)),
            title: Text(reward.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
            subtitle: Text('يتطلب ${reward.requiredPoints} نقطة'),
            trailing: isClaimed ? const Icon(Icons.check_circle, color: Colors.green, size: 30) : isUnlocked ? FilledButton(onPressed: () async { final ok = await data.claimReward(reward.name, reward.icon); if (ok && context.mounted) showSnack(context, 'مبروك!'); }, child: const Text('استلام')) : const Icon(Icons.lock, color: Colors.grey),
          ));
        },
      )),
    );
  }
}