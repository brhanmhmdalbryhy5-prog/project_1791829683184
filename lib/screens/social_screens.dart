import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 👈 لزر النسخ (المشاركة)
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';

// ================= 1. صفحة المنشورات =================
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

// ================= بطاقة المنشور (مثل تيك توك) =================
class PostCard extends StatefulWidget {
  final AppData data;
  final Map<String, dynamic> post;
  const PostCard({super.key, required this.data, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isAnimating = false;

  void _handleLike() async {
    setState(() => _isAnimating = true);
    await widget.data.togglePostLike(widget.post['id']);
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() => _isAnimating = false);
  }

  void _sharePost() {
    final text = '${widget.post['user_name']}: ${widget.post['content']}';
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, 'تم نسخ المنشور!');
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final post = widget.post;
    final name = clean(post['user_name']);
    final avatar = data.avatarForAccount(post['account_id']);
    final img = clean(post['image_url']);
    final postId = post['id'];
    final liked = data.likedPosts.contains(postId.toString());
    final isVerified = data.isPlayerAdmin(post['account_id']); // شارة التحقق للمدير
    final time = timeAgo(clean(post['created_at'])); // منذ ساعة

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 🔝 رأس المنشور
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(data: data, accountId: parseInt(post['account_id']), userName: name))),
              child: CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name))),
                if (isVerified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: Colors.blue, size: 16), // ✓ علامة التوثيق
                ],
              ]),
              Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)), // منذ ساعة
            ])),
            if ((data.isAdmin || parseInt(post['account_id']) == data.currentAccountId))
              IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => data.deletePost(postId)),
          ]),
          const SizedBox(height: 10),
          
          // 📝 محتوى المنشور
          Text(clean(post['content']), style: const TextStyle(fontSize: 16)),
          
          if (img.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onDoubleTap: () { if (!liked) _handleLike(); }, // 👈 النقر المزدوج للإعجاب
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: img, width: double.infinity, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox())),
            ),
          ],
          const SizedBox(height: 10),
          
          // ❤️ أزرار التفاعل (إعجاب، تعليق، مشاركة)
          Row(children: [
            // إعجاب مع حركة النبض
            AnimatedScale(
              scale: _isAnimating ? 1.4 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: IconButton(
                onPressed: _handleLike,
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : AppColors.gold),
              ),
            ),
            Text('${data.postLikeCounts[postId] ?? 0}'),
            const SizedBox(width: 12),
            
            // تعليق
            IconButton(
              onPressed: () async { await playClickSound(); showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => PostCommentsSheet(data: data, postId: postId)); },
              icon: const Icon(Icons.comment_outlined, color: AppColors.gold),
            ),
            Text('${data.postCommentCounts[postId] ?? 0}'),
            const SizedBox(width: 12),
            
            // مشاركة (نسخ)
            IconButton(
              onPressed: _sharePost,
              icon: const Icon(Icons.share_outlined, color: AppColors.gold, size: 22),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ================= نافذة تعليقات المنشورات =================
class PostCommentsSheet extends StatefulWidget {
  final AppData data; final dynamic postId;
  const PostCommentsSheet({super.key, required this.data, required this.postId});
  @override
  State<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  final ctrl = TextEditingController();
  final focusNode = FocusNode();
  List<Map<String, dynamic>> comments = [];
  bool loading = true;
  String? _replyTo;

  @override
  void initState() { super.initState(); load(); }
  
  Future<void> load() async { 
    final res = await widget.data.getPostComments(widget.postId); 
    if (mounted) setState(() { comments = res; loading = false; }); 
  }
  
  Future<void> send() async { 
    if (ctrl.text.trim().isEmpty) return; 
    final ok = await widget.data.addPostComment(widget.postId, ctrl.text, replyTo: _replyTo); 
    if (ok) { 
      ctrl.clear(); 
      setState(() => _replyTo = null); 
      await load(); 
    } 
  }

  void _startReply(String userName) {
    setState(() => _replyTo = userName);
    focusNode.requestFocus();
  }
  
  @override
  void dispose() { ctrl.dispose(); focusNode.dispose(); super.dispose(); }

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
              final replyTo = clean(c['reply_to']);
              final avatarUrl = widget.data.avatarForAccount(c['account_id']);
              final isVerified = widget.data.isPlayerAdmin(c['account_id']);

              return ListTile(
                leading: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(data: widget.data, accountId: parseInt(c['account_id']), userName: name))),
                  child: CircleAvatar(backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null, child: avatarUrl.isEmpty ? const Icon(Icons.person) : null)
                ),
                title: Row(children: [
                  Text(name, style: TextStyle(color: AppColors.getColorForName(name), fontWeight: FontWeight.bold)),
                  if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 14)],
                ]),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (replyTo.isNotEmpty)
                      Text('↩️ رداً على $replyTo', style: TextStyle(fontSize: 11, color: AppColors.gold, fontStyle: FontStyle.italic)),
                    Text(clean(c['comment_text'])),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.reply, color: AppColors.gold, size: 20),
                  onPressed: () => _startReply(name),
                ),
              );
            },
          )),
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: AppColors.gold.withOpacity(0.15),
              child: Row(children: [
                Icon(Icons.reply, color: AppColors.gold, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('الرد على $_replyTo', style: TextStyle(color: AppColors.gold, fontSize: 13))),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null)),
              ]),
            ),
          Padding(padding: const EdgeInsets.all(10), child: Row(children: [
            Expanded(child: TextField(
              controller: ctrl, 
              focusNode: focusNode,
              decoration: InputDecoration(hintText: _replyTo == null ? 'أضف تعليقاً...' : 'الرد على $_replyTo...'),
            )),
            IconButton(onPressed: send, icon: const Icon(Icons.send, color: AppColors.gold)),
          ])),
        ]),
      ),
    );
  }
}

// ================= 🌟 صفحة حساب أي مستخدم (مثل تيك توك) =================
class UserProfilePage extends StatelessWidget {
  final AppData data;
  final int accountId;
  final String userName;
  const UserProfilePage({super.key, required this.data, required this.accountId, required this.userName});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        // جلب بيانات هذا المستخدم
        Map<String, dynamic>? player;
        for (final p in data.players) {
          if (parseInt(p['account_id']) == accountId) { player = p; break; }
        }
        final avatar = clean(player?['avatar_url']);
        final points = parseInt(player?['points']);
        final posts = data.posts.where((p) => parseInt(p['account_id']) == accountId).toList();
        final isVerified = data.isPlayerAdmin(accountId);
        final badge = getCurrentBadge(points);

        return Scaffold(
          appBar: AppBar(title: Text(userName)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // الرأس (بيانات الحساب)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    GestureDetector(
                      onTap: () => showAvatarDialog(context, avatar, userName),
                      child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.gold, width: 3)), child: CircleAvatar(radius: 45, backgroundColor: AppColors.inputBlack, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, size: 45, color: AppColors.gold) : null)),
                    ),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(userName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: AppColors.gold)),
                      if (isVerified) ...[const SizedBox(width: 6), const Icon(Icons.verified, color: Colors.blue, size: 20)],
                    ]),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _statItem('${posts.length}', 'منشورات'),
                      Container(margin: const EdgeInsets.symmetric(horizontal: 20), width: 1, height: 30, color: Colors.grey),
                      _statItem('$points', 'نقاط'),
                      Container(margin: const EdgeInsets.symmetric(horizontal: 20), width: 1, height: 30, color: Colors.grey),
                      _statItem(getUserLevel(points), 'مستوى'),
                    ]),
                    if (badge != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${badge.icon} ${badge.name}')),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              // المنشورات
              const Text('المنشورات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.gold)),
              const SizedBox(height: 10),
              if (posts.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد منشورات لهذا المستخدم.')))
              else ...posts.map((post) => PostCard(data: data, post: post)),
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(String value, String label) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.gold)),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]);
  }
}

// ================= 2. الرسائل الخاصة (مع Realtime) =================
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
              final unreadCount = data.unreadMessageCounts[userId] ?? 0;
              final isVerified = data.isPlayerAdmin(userId);

              return Card(child: ListTile(
                leading: GestureDetector(
                  onTap: () => showAvatarDialog(context, avatar, name), 
                  child: CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null)
                ),
                title: Row(children: [
                  Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name))),
                  if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 14)],
                ]),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (unreadCount > 0)
                      Badge(label: Text('$unreadCount'), backgroundColor: Colors.red, textColor: Colors.white),
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
  final supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    widget.data.privateMessages.clear();
    await widget.data.loadPrivateMessages(parseInt(widget.other['account_id']));
    if (mounted) setState(() => _loading = false);
    
    _channel = supabase.channel('chat_${widget.data.currentAccountId}_${widget.other['account_id']}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert, schema: 'public', table: 'private_messages',
        callback: (payload) {
          final newMsg = payload.newRecord;
          final senderId = parseInt(newMsg['sender_id']);
          final receiverId = parseInt(newMsg['receiver_id']);
          final myId = widget.data.currentAccountId;
          final otherId = parseInt(widget.other['account_id']);
          if ((senderId == myId && receiverId == otherId) || (senderId == otherId && receiverId == myId)) {
            widget.data.loadPrivateMessages(otherId);
          }
        }
      ).subscribe();
  }

  Future<void> _send() async { 
    if (ctrl.text.trim().isEmpty) return; 
    final ok = await widget.data.sendPrivateMessage(parseInt(widget.other['account_id']), ctrl.text); 
    if (ok) ctrl.clear(); 
  }

  @override
  void dispose() { 
    _channel?.unsubscribe(); 
    ctrl.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    final otherName = clean(widget.other['name']); 
    final otherAvatar = clean(widget.other['avatar_url']);
    final isVerified = widget.data.isPlayerAdmin(widget.other['account_id']);

    return Scaffold(
      appBar: AppBar(title: Row(children: [
        GestureDetector(onTap: () => showAvatarDialog(context, otherAvatar, otherName), child: CircleAvatar(radius: 16, backgroundImage: otherAvatar.isNotEmpty ? CachedNetworkImageProvider(otherAvatar) : null, child: otherAvatar.isEmpty ? const Icon(Icons.person, size: 16) : null)),
        const SizedBox(width: 8), 
        Text(otherName),
        if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 16)],
      ])),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : Column(children: [
              Expanded(child: AnimatedBuilder(animation: widget.data, builder: (context, _) {
                final msgs = widget.data.privateMessages;
                return ListView.builder(reverse: true, padding: const EdgeInsets.all(10), itemCount: msgs.length, itemBuilder: (_, i) {
                  final m = msgs[i]; 
                  final isMe = parseInt(m['sender_id']) == widget.data.currentAccountId;
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

// ================= 3. المعرض (مع Hero Animation) =================
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
                      final tag = 'gallery_${item['id']}';

                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GalleryImagePage(data: widget.data, item: item))),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.cardBlack, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.goldDark, width: 3), boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)]),
                          child: Column(children: [
                            AspectRatio(
                              aspectRatio: 1.15, 
                              child: Hero(tag: tag, child: CachedNetworkImage(imageUrl: clean(item['image_url']), fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.gold)))
                            ),
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
    final tag = 'gallery_${item['id']}';
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(title: Text(clean(item['user_name'])), actions: [
        if (data.isAdmin) IconButton(onPressed: () async { await data.deleteGalleryImage(item['id']); if (context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.delete)),
      ]),
      body: Center(child: InteractiveViewer(child: Hero(tag: tag, child: CachedNetworkImage(imageUrl: clean(item['image_url']), fit: BoxFit.contain, errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 80, color: AppColors.gold))))),
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