import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../core/theme_manager.dart';
import '../data/app_data.dart';

// =======================================================
// صفحة المنشورات
// =======================================================
class PostsPage extends StatelessWidget {
  final AppData data;
  const PostsPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المنشورات')),
      body: AnimatedBuilder(animation: data, builder: (context, _) {
        if (data.posts.isEmpty) return const Center(child: Text('لا توجد منشورات بعد.'));
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: data.posts.length, itemBuilder: (_, i) => PostCard(data: data, post: data.posts[i]));
      }),
    );
  }
}

// =======================================================
// بطاقة المنشور (مع زر تنزيل محسّن)
// =======================================================
class PostCard extends StatefulWidget {
  final AppData data; final Map<String, dynamic> post;
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

  /// ✅ تنزيل الصورة مباشرة للمعرض (باستخدام gal)
  Future<void> _downloadImage() async {
    final img = clean(widget.post['image_url']);
    if (img.isEmpty) return;
    showSnack(context, 'جاري التنزيل...');
    final ok = await downloadImageToGallery(img, fileName: 'mr_otaku_post');
    if (mounted) {
      showSnack(context, ok ? '✅ تم حفظ الصورة في معرض هاتفك.' : 'تعذر الحفظ. تحقق من صلاحيات التطبيق.');
    }
  }

  Future<void> _report() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('الإبلاغ عن المنشور'),
      content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'سبب الإبلاغ...')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('إبلاغ')),
      ],
    ));
    if (reason != null && reason.isNotEmpty) {
      final ok = await widget.data.submitComplaint(targetType: 'post', targetId: widget.post['id'], reason: reason);
      if (mounted) showSnack(context, ok ? 'تم إرسال البلاغ للإدارة.' : 'تعذر الإرسال.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data; final post = widget.post;
    final name = data.displayNameForAccount(post['account_id']);
    final avatar = data.avatarForAccount(post['account_id']);
    final img = clean(post['image_url']);
    final vid = clean(post['video_url']);
    final postId = post['id'];
    final liked = data.likedPosts.contains(postId.toString());
    final saved = data.isPostSaved(postId);
    final isVerified = data.isPlayerAdmin(post['account_id']);
    final time = timeAgo(clean(post['created_at']));
    final primary = ThemeManager.instance.primaryColor;

    return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(data: data, accountId: parseInt(post['account_id']), userName: name))), child: CircleAvatar(backgroundColor: primary, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.white) : null)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name))), if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 16)]]),
          Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
        PopupMenuButton(itemBuilder: (_) => [
          if (data.isAdmin || parseInt(post['account_id']) == data.currentAccountId) const PopupMenuItem(value: 'delete', child: Text('حذف')),
          const PopupMenuItem(value: 'report', child: Text('إبلاغ')),
        ], onSelected: (v) { if (v == 'delete') data.deletePost(postId); else if (v == 'report') _report(); }),
      ]),
      const SizedBox(height: 10),
      if (clean(post['content']).isNotEmpty) Text(clean(post['content']), style: const TextStyle(fontSize: 16)),
      if (img.isNotEmpty) ...[
        const SizedBox(height: 10),
        GestureDetector(
          onDoubleTap: () { if (!liked) _handleLike(); },
          child: Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: img, width: double.infinity, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox())),
            Positioned(bottom: 8, right: 8, child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.download, color: Colors.white, size: 20),
                onPressed: _downloadImage,
                tooltip: 'تنزيل الصورة',
              ),
            )),
          ]),
        ),
      ],
      if (vid.isNotEmpty) ...[
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(12), child: InlineVideo(url: vid)),
      ],
      const SizedBox(height: 10),
      Row(children: [
        AnimatedScale(scale: _isAnimating ? 1.4 : 1.0, duration: const Duration(milliseconds: 150), child: IconButton(onPressed: _handleLike, icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : AppColors.gold))),
        Text('${data.postLikeCounts[postId] ?? 0}'),
        const SizedBox(width: 8),
        IconButton(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => PostCommentsSheet(data: data, postId: postId)), icon: const Icon(Icons.comment_outlined, color: AppColors.gold)),
        Text('${data.postCommentCounts[postId] ?? 0}'),
        const Spacer(),
        IconButton(onPressed: () => data.toggleSavePost(postId), icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, color: saved ? Colors.amber : AppColors.gold)),
        IconButton(onPressed: _sharePost, icon: const Icon(Icons.share_outlined, color: AppColors.gold, size: 22)),
      ]),
    ])));
  }
}

// =======================================================
// مشغل فيديو مضمّن
// =======================================================
class InlineVideo extends StatefulWidget {
  final String url;
  const InlineVideo({super.key, required this.url});
  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  late VideoPlayerController _controller;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      _controller.setLooping(true);
      _controller.setVolume(0);
      _controller.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return Container(height: 250, color: AppColors.cardBlack, child: const Center(child: CircularProgressIndicator(color: AppColors.gold)));
    }
    return Stack(children: [
      AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
      Positioned(bottom: 8, right: 8, child: CircleAvatar(
        backgroundColor: Colors.black54,
        child: IconButton(
          icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20),
          onPressed: () { setState(() => _muted = !_muted); _controller.setVolume(_muted ? 0 : 1); },
        ),
      )),
    ]);
  }
}

// =======================================================
// تعليقات المنشورات
// =======================================================
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
  File? _image;

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async { await widget.data.loadCommentLikes(); final res = await widget.data.getPostComments(widget.postId); if (mounted) setState(() { comments = res; loading = false; }); }
  Future<void> _pickImage() async { final picker = ImagePicker(); final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70); if (picked != null) setState(() => _image = File(picked.path)); }
  Future<void> send() async {
    if (ctrl.text.trim().isEmpty && _image == null) return;
    final ok = await widget.data.addPostComment(widget.postId, ctrl.text, replyTo: _replyTo, imageFile: _image);
    if (ok) { ctrl.clear(); setState(() { _replyTo = null; _image = null; }); await load(); }
  }
  void _startReply(String userName) { setState(() => _replyTo = userName); focusNode.requestFocus(); }
  @override
  void dispose() { ctrl.dispose(); focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(color: AppColors.cardBlack, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('التعليقات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.gold))),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(itemCount: comments.length, itemBuilder: (_, i) {
          final c = comments[i];
          final name = widget.data.displayNameForAccount(c['account_id']);
          final replyTo = clean(c['reply_to']);
          final img = clean(c['image_url']);
          final avatarUrl = widget.data.avatarForAccount(c['account_id']);
          final isVerified = widget.data.isPlayerAdmin(c['account_id']);
          final cid = c['id'];
          final isLiked = widget.data.isCommentLiked(cid, 'post');
          return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfilePage(data: widget.data, accountId: parseInt(c['account_id']), userName: name))), child: CircleAvatar(radius: 18, backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null, child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 18) : null)),
              const SizedBox(width: 8),
              Expanded(child: Row(children: [Text(name, style: TextStyle(color: AppColors.getColorForName(name), fontWeight: FontWeight.bold)), if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 14)]])),
              IconButton(icon: const Icon(Icons.reply, color: AppColors.gold, size: 20), onPressed: () => _startReply(name)),
            ]),
            if (replyTo.isNotEmpty) Text('↩️ رداً على $replyTo', style: TextStyle(fontSize: 11, color: AppColors.gold, fontStyle: FontStyle.italic)),
            if (clean(c['comment_text']).isNotEmpty) Text(clean(c['comment_text'])),
            if (img.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: img, height: 120, fit: BoxFit.cover))),
            Row(children: [
              IconButton(onPressed: () async { await widget.data.toggleCommentLike(cid, 'post'); setState(() {}); }, icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : AppColors.gold, size: 18)),
              Text('${widget.data.commentLikesCount(cid, 'post')}', style: const TextStyle(fontSize: 12)),
            ]),
          ])));
        })),
        if (_replyTo != null) Container(padding: const EdgeInsets.all(8), color: AppColors.gold.withOpacity(0.15), child: Row(children: [const Icon(Icons.reply, size: 18, color: AppColors.gold), const SizedBox(width: 6), Expanded(child: Text('الرد على $_replyTo', style: const TextStyle(color: AppColors.gold, fontSize: 13))), IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null))])),
        if (_image != null) Container(padding: const EdgeInsets.all(8), color: AppColors.cardBlack, child: Row(children: [const Icon(Icons.image, color: AppColors.gold), const SizedBox(width: 8), const Expanded(child: Text('صورة جاهزة')), IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 18), onPressed: () => setState(() => _image = null))])),
        Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          IconButton(icon: const Icon(Icons.image, color: AppColors.gold), onPressed: _pickImage),
          Expanded(child: TextField(controller: ctrl, focusNode: focusNode, decoration: InputDecoration(hintText: _replyTo == null ? 'أضف تعليقاً...' : 'الرد على $_replyTo...'))),
          IconButton(onPressed: send, icon: const Icon(Icons.send, color: AppColors.gold)),
        ])),
      ]),
    ));
  }
}

// =======================================================
// صفحة حساب أي مستخدم
// =======================================================
class UserProfilePage extends StatefulWidget {
  final AppData data; final int accountId; final String userName;
  const UserProfilePage({super.key, required this.data, required this.accountId, required this.userName});
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, int> _stats = {'followers': 0, 'following': 0};
  @override
  void initState() { super.initState(); _loadStats(); }
  Future<void> _loadStats() async { final s = await widget.data.getUserFollowStats(widget.accountId); if (mounted) setState(() => _stats = s); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: widget.data, builder: (context, _) {
      Map<String, dynamic>? player;
      for (final p in widget.data.players) { if (parseInt(p['account_id']) == widget.accountId) { player = p; break; } }
      final avatar = clean(player?['avatar_url']);
      final points = parseInt(player?['points']);
      final posts = widget.data.posts.where((p) => parseInt(p['account_id']) == widget.accountId).toList();
      final isVerified = widget.data.isPlayerAdmin(widget.accountId);
      final isFollowing = widget.data.isFollowing(widget.accountId);
      final isMe = widget.accountId == widget.data.currentAccountId;
      final displayName = widget.data.displayNameForAccount(widget.accountId);
      final primary = ThemeManager.instance.primaryColor;

      return Scaffold(appBar: AppBar(title: Text(displayName)), body: ListView(children: [
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          GestureDetector(onTap: () => showAvatarDialog(context, avatar, displayName), child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primary, width: 3), boxShadow: ThemeManager.instance.getGlowShadow()), child: CircleAvatar(radius: 45, backgroundColor: AppColors.inputBlack, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, size: 45, color: AppColors.gold) : null))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(displayName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primary)), if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 20)]]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _stat('${posts.length}', 'منشورات'),
            Container(width: 1, height: 30, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 20)),
            _stat('${_stats['followers']}', 'متابع'),
            Container(width: 1, height: 30, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 20)),
            _stat('${_stats['following']}', 'يتابع'),
          ]),
          const SizedBox(height: 8),
          Text('المستوى: ${getUserLevel(points)} | النقاط: $points'),
          const SizedBox(height: 12),
          if (!isMe) Container(
            decoration: BoxDecoration(gradient: isFollowing ? LinearGradient(colors: [Colors.grey, Colors.grey.shade400]) : ThemeManager.instance.getButtonGradient(), borderRadius: BorderRadius.circular(30), boxShadow: ThemeManager.instance.getGlowShadow()),
            child: Material(color: Colors.transparent, child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () async { await widget.data.toggleFollow(widget.accountId); await _loadStats(); },
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12), child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isFollowing ? Icons.person_remove : Icons.person_add, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(isFollowing ? 'إلغاء المتابعة' : 'متابعة', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ])),
            )),
          ),
        ])),
        const Divider(),
        const Padding(padding: EdgeInsets.all(12), child: Text('المنشورات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        if (posts.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد منشورات')))
        else ...posts.map((p) => PostCard(data: widget.data, post: p)),
      ]));
    });
  }

  Widget _stat(String value, String label) => Column(children: [Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))]);
}

// =======================================================
// الرسائل الخاصة
// =======================================================
class PrivateMessagesPage extends StatelessWidget {
  final AppData data;
  const PrivateMessagesPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: data, builder: (context, _) {
      final others = data.players.where((p) => parseInt(p['account_id']) != data.currentAccountId).toList();
      return Scaffold(appBar: AppBar(title: const Text('الرسائل')), body: others.isEmpty ? const Center(child: Text('لا يوجد مستخدمون.')) : ListView.builder(itemCount: others.length, itemBuilder: (_, i) {
        final p = others[i];
        final avatar = clean(p['avatar_url']);
        final name = data.displayNameForAccount(p['account_id']);
        final userId = parseInt(p['account_id']);
        final unread = data.unreadMessageCounts[userId] ?? 0;
        final isVerified = data.isPlayerAdmin(userId);
        return Card(child: ListTile(
          leading: GestureDetector(onTap: () => showAvatarDialog(context, avatar, name), child: CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null)),
          title: Row(children: [Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name))), if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified, color: Colors.blue, size: 14)]]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (unread > 0) Badge(label: Text('$unread'), backgroundColor: Colors.red), const SizedBox(width: 8), const Icon(Icons.message, color: AppColors.gold)]),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(data: data, other: p))),
        ));
      }));
    });
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
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    widget.data.privateMessages.clear();
    await widget.data.loadPrivateMessages(parseInt(widget.other['account_id']));
    if (mounted) setState(() => _loading = false);
    _channel = supabase.channel('chat_${widget.data.currentAccountId}_${widget.other['account_id']}').onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'private_messages', callback: (payload) {
      final m = payload.newRecord;
      final s = parseInt(m['sender_id']);
      final r = parseInt(m['receiver_id']);
      if ((s == widget.data.currentAccountId && r == parseInt(widget.other['account_id'])) || (s == parseInt(widget.other['account_id']) && r == widget.data.currentAccountId)) widget.data.loadPrivateMessages(parseInt(widget.other['account_id']));
    }).subscribe();
  }

  Future<void> _send() async { if (ctrl.text.trim().isEmpty) return; if (await widget.data.sendPrivateMessage(parseInt(widget.other['account_id']), ctrl.text)) ctrl.clear(); }
  @override
  void dispose() { _channel?.unsubscribe(); ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final otherName = widget.data.displayNameForAccount(widget.other['account_id']);
    final otherAvatar = clean(widget.other['avatar_url']);
    return Scaffold(
      appBar: AppBar(title: Row(children: [
        GestureDetector(onTap: () => showAvatarDialog(context, otherAvatar, otherName), child: CircleAvatar(radius: 16, backgroundImage: otherAvatar.isNotEmpty ? CachedNetworkImageProvider(otherAvatar) : null, child: otherAvatar.isEmpty ? const Icon(Icons.person, size: 16) : null)),
        const SizedBox(width: 8), Text(otherName),
      ])),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
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

// =======================================================
// المعرض (مع زر تنزيل محسّن)
// =======================================================
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
    final c = TextEditingController();
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('إضافة صورة'), content: TextField(controller: c, maxLines: 3, decoration: const InputDecoration(labelText: 'تعليق')), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('نشر'))]));
    if (confirm != true) { c.dispose(); return; }
    if (!mounted) { c.dispose(); return; }
    final messenger = ScaffoldMessenger.of(context);
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final err = await widget.data.addGalleryImage(File(picked.path), caption: c.text);
    if (!mounted) { c.dispose(); return; }
    Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(SnackBar(content: Text(err == null ? '✅ تم النشر' : '❌ $err'), backgroundColor: err == null ? Colors.green : Colors.red));
    c.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('معرض الصور'), actions: [IconButton(onPressed: () => widget.data.loadGallery(), icon: const Icon(Icons.refresh))]), floatingActionButton: FloatingActionButton.extended(onPressed: pickAndUpload, icon: const Icon(Icons.add_a_photo), label: const Text('أضف صورة')), body: AnimatedBuilder(animation: widget.data, builder: (context, _) {
      return RefreshIndicator(onRefresh: widget.data.loadGallery, child: widget.data.gallery.isEmpty ? ListView(children: const [SizedBox(height: 200), Center(child: Text('لا توجد صور'))]) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: widget.data.gallery.length, itemBuilder: (_, index) {
        final item = widget.data.gallery[index];
        final imgUrl = clean(item['image_url']);
        final owner = widget.data.displayNameForAccount(item['account_id']);
        return Container(
          margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [ThemeManager.instance.primaryColor.withOpacity(0.2), AppColors.cardBlack]), borderRadius: BorderRadius.circular(16), border: Border.all(color: ThemeManager.instance.primaryColor.withOpacity(0.5), width: 2), boxShadow: ThemeManager.instance.getGlowShadow()),
          child: Column(children: [
            AspectRatio(aspectRatio: 1.15, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.gold)))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(owner, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold))),
              IconButton(icon: const Icon(Icons.download, color: AppColors.gold), onPressed: () async {
                showSnack(context, 'جاري التنزيل...');
                final ok = await downloadImageToGallery(imgUrl, fileName: 'mr_otaku_gallery');
                if (context.mounted) showSnack(context, ok ? '✅ تم الحفظ' : 'تعذر الحفظ');
              }),
            ]),
            if (clean(item['caption']).isNotEmpty) Text(clean(item['caption']), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ]),
        );
      }));
    }));
  }
}

class RewardsPage extends StatelessWidget {
  final AppData data;
  const RewardsPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('خزانة الجوائز')), body: AnimatedBuilder(animation: data, builder: (context, _) => ListView.builder(padding: const EdgeInsets.all(16), itemCount: allRewards.length, itemBuilder: (_, i) {
      final r = allRewards[i];
      final unlocked = data.currentPoints >= r.requiredPoints;
      final claimed = data.hasReward(r.name);
      return Card(child: ListTile(leading: Text(r.icon, style: const TextStyle(fontSize: 40)), title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)), subtitle: Text('يتطلب ${r.requiredPoints} نقطة'), trailing: claimed ? const Icon(Icons.check_circle, color: Colors.green, size: 30) : unlocked ? FilledButton(onPressed: () async { if (await data.claimReward(r.name, r.icon) && context.mounted) showSnack(context, 'مبروك!'); }, child: const Text('استلام')) : const Icon(Icons.lock, color: Colors.grey)));
    })));
  }
}