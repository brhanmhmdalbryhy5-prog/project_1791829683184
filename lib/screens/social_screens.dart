import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';

// دالة مساعدة لتكبير الأيقونة 🌟
void showAvatarDialog(BuildContext context, String url, String name) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold, width: 4),
              boxShadow: [
                BoxShadow(color: AppColors.gold.withOpacity(0.5), blurRadius: 20, spreadRadius: 5),
              ],
            ),
            child: CircleAvatar(
              radius: 100,
              backgroundColor: AppColors.inputBlack,
              backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
              child: url.isEmpty ? const Icon(Icons.person, size: 100, color: AppColors.gold) : null,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold),
            ),
            child: Text(
              name,
              style: const TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
}

// =======================================================
// 1. صفحة المنشورات (تويتر)
// =======================================================
class PostsPage extends StatefulWidget {
  final AppData data;
  const PostsPage({super.key, required this.data});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  final textCtrl = TextEditingController();
  File? _image;
  bool _loading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _post() async {
    if (textCtrl.text.trim().isEmpty && _image == null) return;
    setState(() => _loading = true);
    final ok = await widget.data.addPost(textCtrl.text, _image);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (ok) { textCtrl.clear(); _image = null; }
    });
    if (ok) showSnack(context, 'تم النشر بنجاح!');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المنشورات')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: textCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'بماذا تفكر يا أوتاكو؟',
                        border: InputBorder.none,
                      ),
                    ),
                    if (_image != null)
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Image.file(_image!, height: 150, width: double.infinity, fit: BoxFit.cover),
                          IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => _image = null)),
                        ],
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.image, color: AppColors.gold), onPressed: _pickImage),
                        FilledButton.icon(
                          onPressed: _loading ? null : _post,
                          icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                          label: const Text('نشر'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.data,
              builder: (context, _) {
                if (widget.data.posts.isEmpty) return const Center(child: Text('لا توجد منشورات بعد.'));
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: widget.data.posts.length,
                  itemBuilder: (_, i) {
                    final post = widget.data.posts[i];
                    final name = clean(post['user_name']);
                    final avatar = widget.data.avatarForAccount(post['account_id']);
                    final img = clean(post['image_url']);
                    final rewards = widget.data.userRewards.where((r) => r['account_id'] == post['account_id']).toList();
                    final myColor = AppColors.getColorForName(name);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => showAvatarDialog(context, avatar, name),
                                  child: CircleAvatar(
                                    backgroundColor: AppColors.gold,
                                    backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                    child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: myColor)),
                                      if (rewards.isNotEmpty)
                                        Wrap(
                                          spacing: 4,
                                          children: rewards.map((r) => Text(clean(r['reward_icon']), style: const TextStyle(fontSize: 16))).toList(),
                                        ),
                                    ],
                                  ),
                                ),
                                if (widget.data.isAdmin)
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                    onPressed: () => widget.data.deletePost(post['id']),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(clean(post['content']), style: const TextStyle(fontSize: 16)),
                            if (img.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(img, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// 2. صفحة الجوائز
// =======================================================
class RewardsPage extends StatelessWidget {
  final AppData data;
  const RewardsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خزانة الجوائز')),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: allRewards.length,
            itemBuilder: (_, i) {
              final reward = allRewards[i];
              final isUnlocked = data.currentPoints >= reward.requiredPoints;
              final isClaimed = data.hasReward(reward.name);

              return Card(
                child: ListTile(
                  leading: Text(reward.icon, style: const TextStyle(fontSize: 40)),
                  title: Text(reward.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
                  subtitle: Text('يتطلب ${reward.requiredPoints} نقطة'),
                  trailing: isClaimed
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 30)
                      : isUnlocked
                          ? FilledButton(
                              onPressed: () async {
                                final ok = await data.claimReward(reward.name, reward.icon);
                                if (ok && context.mounted) showSnack(context, 'مبروك! حصلت على ${reward.name}');
                              },
                              child: const Text('استلام'),
                            )
                          : const Icon(Icons.lock, color: Colors.grey),
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
// 3. الرسائل الخاصة
// =======================================================
class PrivateMessagesPage extends StatelessWidget {
  final AppData data;
  const PrivateMessagesPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final others = data.players.where((p) => toInt(p['account_id']) != data.currentAccountId).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل الخاصة')),
      body: others.isEmpty
          ? const Center(child: Text('لا يوجد مستخدمون آخرون.'))
          : ListView.builder(
              itemCount: others.length,
              itemBuilder: (_, i) {
                final p = others[i];
                final avatar = clean(p['avatar_url']);
                final name = clean(p['name']);
                return Card(
                  child: ListTile(
                    leading: GestureDetector(
                      onTap: () => showAvatarDialog(context, avatar, name),
                      child: CircleAvatar(
                        backgroundColor: AppColors.gold,
                        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                        child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null,
                      ),
                    ),
                    title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name))),
                    trailing: const Icon(Icons.message),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(data: data, other: p))),
                  ),
                );
              },
            ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final AppData data;
  final Map<String, dynamic> other;
  const ChatScreen({super.key, required this.data, required this.other});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ctrl = TextEditingController();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  Future<void> _load() async {
    await widget.data.loadPrivateMessages(toInt(widget.other['account_id']));
  }

  Future<void> _send() async {
    if (ctrl.text.trim().isEmpty) return;
    final ok = await widget.data.sendPrivateMessage(toInt(widget.other['account_id']), ctrl.text);
    if (ok) {
      ctrl.clear();
      await _load();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherName = clean(widget.other['name']);
    final otherAvatar = clean(widget.other['avatar_url']);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            GestureDetector(
              onTap: () => showAvatarDialog(context, otherAvatar, otherName),
              child: CircleAvatar(
                radius: 16,
                backgroundImage: otherAvatar.isNotEmpty ? NetworkImage(otherAvatar) : null,
                child: otherAvatar.isEmpty ? const Icon(Icons.person, size: 16) : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(otherName),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: widget.data,
              builder: (context, _) {
                final msgs = widget.data.privateMessages;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final isMe = toInt(m['sender_id']) == widget.data.currentAccountId;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Card(
                        color: isMe ? AppColors.gold.withOpacity(0.2) : AppColors.cardBlack,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(clean(m['message'])),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'اكتب رسالة...'))),
                IconButton(onPressed: _send, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// 4. معرض الصور (مع تكبير الأيقونة)
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

    final captionController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة صورة'),
        content: TextField(controller: captionController, maxLines: 3, decoration: const InputDecoration(labelText: 'تعليق (اختياري)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('نشر')),
        ],
      ),
    );
    if (confirm != true) { captionController.dispose(); return; }
    if (!mounted) { captionController.dispose(); return; }

    final messenger = ScaffoldMessenger.of(context);
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.gold)));

    final errorMessage = await widget.data.addGalleryImage(File(picked.path), caption: captionController.text);
    if (!mounted) { captionController.dispose(); return; }
    Navigator.of(context, rootNavigator: true).pop();

    final text = errorMessage == null ? '✅ تم نشر الصورة.' : '❌ $errorMessage';
    messenger.showSnackBar(SnackBar(content: Text(text), backgroundColor: errorMessage == null ? Colors.green.shade800 : Colors.red.shade800));
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
            onRefresh: widget.data.loadGallery,
            color: AppColors.gold,
            child: widget.data.gallery.isEmpty
                ? ListView(children: const [SizedBox(height: 200), Center(child: Text('لا توجد صور بعد.\nكن أول من يشارك صورة!', textAlign: TextAlign.center))])
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.data.gallery.length,
                    itemBuilder: (_, index) {
                      final item = widget.data.gallery[index];
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GalleryImagePage(data: widget.data, item: item))),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.cardBlack, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.goldDark, width: 3), boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)]),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(border: Border.all(color: AppColors.gold, width: 2)),
                            child: Column(
                              children: [
                                AspectRatio(aspectRatio: 1.15, child: Image.network(clean(item['image_url']), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.gold))),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => showAvatarDialog(context, widget.data.avatarForName(clean(item['user_name'])), clean(item['user_name'])),
                                  child: Text(clean(item['user_name']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.gold)),
                                ),
                                if (clean(item['caption']).isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(clean(item['caption']), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                                ],
                              ],
                            ),
                          ),
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
  final AppData data;
  final Map<String, dynamic> item;
  const GalleryImagePage({super.key, required this.data, required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = clean(item['image_url']);
    final userName = clean(item['user_name']);
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Text(userName),
        actions: [
          if (data.isAdmin)
            IconButton(
              onPressed: () async {
                await data.deleteGalleryImage(item['id']);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 80, color: AppColors.gold)),
        ),
      ),
    );
  }
}

// =======================================================
// 5. الدردشة العامة
// =======================================================
class PublicChatPage extends StatefulWidget {
  final AppData data;
  const PublicChatPage({super.key, required this.data});

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
    _refreshAll();
    timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await widget.data.loadPublicChat();
      await widget.data.loadPlayers();
      if (mounted) setState(() {});
    });
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
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked != null && mounted) setState(() => selectedImage = File(picked.path));
  }

  Future<void> send() async {
    if (controller.text.trim().isEmpty && selectedImage == null) return;
    setState(() => sending = true);
    await playClickSound();
    final ok = await widget.data.sendPublicChat(controller.text, imageFile: selectedImage);
    if (!mounted) return;
    setState(() {
      sending = false;
      if (ok) { controller.clear(); selectedImage = null; }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدردشة العامة'), actions: [IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh))]),
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
                          final mine = toInt(item['account_id']) == widget.data.currentAccountId;
                          final messageImage = clean(item['image_url']);
                          final messageText = clean(item['message']);
                          final name = clean(item['user_name']);
                          final avatar = widget.data.avatarForAccount(item['account_id']);

                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: () => showAvatarDialog(context, avatar, name),
                                          child: CircleAvatar(
                                            radius: 20,
                                            backgroundColor: AppColors.gold,
                                            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                            child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black, size: 22) : null,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(name))),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    if (messageImage.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(messageImage, width: 200, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                                      ),
                                    if (messageText.isNotEmpty) Text(messageText),
                                    if (widget.data.isAdmin)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: IconButton(
                                          onPressed: () => widget.data.deletePublicChat(item['id']),
                                          icon: const Icon(Icons.delete, size: 20),
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
                      const Expanded(child: Text('صورة جاهزة للإرسال')),
                      IconButton(onPressed: () => setState(() => selectedImage = null), icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    IconButton(onPressed: pickImage, icon: const Icon(Icons.image)),
                    Expanded(child: TextField(controller: controller, decoration: const InputDecoration(labelText: 'اكتب رسالتك'))),
                    IconButton(
                      onPressed: sending ? null : send,
                      icon: sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)) : const Icon(Icons.send),
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