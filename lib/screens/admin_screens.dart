import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';

Future<bool> confirmDelete(BuildContext context, String itemName) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('تأكيد الحذف'),
      content: Text('هل أنت متأكد من حذف "$itemName"؟\nلا يمكن التراجع عن هذا الإجراء.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('حذف نهائي')),
      ],
    ),
  );
  return result ?? false;
}

// =======================================================
// 1. لوحة الإدارة
// =======================================================
class AdminPanelPage extends StatelessWidget {
  final AppData data;
  const AdminPanelPage({super.key, required this.data});

  Future<void> logout(BuildContext context) async {
    await data.setAdminSession(false);
    if (!context.mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (!data.isAdmin) {
      return Scaffold(appBar: AppBar(title: const Text('الإدارة')), body: const Center(child: Text('ليس لديك صلاحية الوصول.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الإدارة'), actions: [IconButton(onPressed: () => logout(context), icon: const Icon(Icons.logout))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AdminTile(icon: Icons.people, title: 'إدارة ومراقبة الحسابات', colorIndex: 0, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManagePointsPage(data: data)))),
        AdminTile(icon: Icons.campaign, title: 'الخبر المهم', colorIndex: 1, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageImportantNewsPage(data: data)))),
        AdminTile(icon: Icons.photo_library, title: 'إدارة معرض الصور', colorIndex: 2, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageGalleryPage(data: data)))),
        AdminTile(icon: Icons.assignment_turned_in, title: 'نتائج الاختبارات', colorIndex: 3, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageQuizResultsPage(data: data)))),
        AdminTile(icon: Icons.quiz, title: 'إدارة الأسئلة', colorIndex: 4, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageQuizPage(data: data)))),
        AdminTile(icon: Icons.newspaper, title: 'إدارة الأخبار', colorIndex: 5, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageNewsPage(data: data)))),
        AdminTile(icon: Icons.notifications, title: 'إدارة الإشعارات', colorIndex: 6, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageNotificationsPage(data: data)))),
        AdminTile(icon: Icons.poll, title: 'إدارة الاستطلاعات', colorIndex: 7, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManagePollPage(data: data)))),
        AdminTile(icon: Icons.campaign, title: 'إدارة كل جديد', colorIndex: 8, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageLatestPage(data: data)))),
        AdminTile(icon: Icons.message, title: 'الرسائل', colorIndex: 9, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageMessagesPage(data: data)))),
        AdminTile(icon: Icons.shopping_bag, title: 'طلبات المتجر', colorIndex: 10, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManagePurchaseRequestsPage(data: data)))),
      ]),
    );
  }
}

class AdminTile extends StatelessWidget {
  final IconData icon; final String title; final VoidCallback onTap; final int colorIndex;
  const AdminTile({super.key, required this.icon, required this.title, required this.onTap, required this.colorIndex});
  @override
  Widget build(BuildContext context) {
    final color = AppColors.getColor(colorIndex);
    return Card(
      margin: const EdgeInsets.only(bottom: 10), elevation: 4, shadowColor: color.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withOpacity(0.3))),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: [color.withOpacity(0.15), color.withOpacity(0.05)])),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white)),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          trailing: const Icon(Icons.arrow_back_ios),
        ),
      ),
    );
  }
}

// =======================================================
// 2. إدارة الحسابات
// =======================================================
class ManagePointsPage extends StatefulWidget {
  final AppData data;
  const ManagePointsPage({super.key, required this.data});
  @override
  State<ManagePointsPage> createState() => _ManagePointsPageState();
}

class _ManagePointsPageState extends State<ManagePointsPage> {
  Future<void> edit([Map<String, dynamic>? player]) async {
    final name = TextEditingController(text: clean(player?['name']));
    final channel = TextEditingController(text: clean(player?['channel_name']));
    final points = TextEditingController(text: parseInt(player?['points']).toString());
    final accountId = TextEditingController(text: player?['account_id']?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(player == null ? 'إضافة حساب' : 'تعديل الحساب'),
        content: SingleChildScrollView(child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المدير (للدخول)')),
          const SizedBox(height: 10),
          TextField(controller: channel, decoration: const InputDecoration(labelText: 'اسم القناة (يظهر للجميع - اختياري)')),
          const SizedBox(height: 10),
          TextField(controller: accountId, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'معرف الحساب (ID)')),
          const SizedBox(height: 10),
          TextField(controller: points, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'النقاط')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () async {
            final parsedId = accountId.text.trim().isEmpty ? null : int.tryParse(accountId.text.trim());
            final parsedPoints = int.tryParse(points.text.trim()) ?? 0;
            bool ok;
            if (player == null) {
              ok = await widget.data.addPlayer(name.text, parsedPoints, accountId: parsedId);
            } else {
              ok = await widget.data.updatePlayer(player['id'], name.text, parsedPoints, accountId: parsedId);
            }
            if (ok && player != null && channel.text.trim().isNotEmpty) {
              try {
                await widget.data.supabase.from('players').update({'channel_name': channel.text.trim()}).eq('id', player['id']);
                await widget.data.loadData();
              } catch (_) {}
            }
            if (context.mounted) {
              Navigator.pop(context);
              showSnack(context, ok ? 'تم حفظ الحساب.' : 'فشل الحفظ.');
            }
          }, child: const Text('حفظ')),
        ],
      ),
    );
    name.dispose();
    channel.dispose();
    points.dispose();
    accountId.dispose();
  }

  String _getUserStatus(Map<String, dynamic> player) {
    final lastSeenStr = player['last_seen']?.toString();
    if (lastSeenStr == null || lastSeenStr.isEmpty || lastSeenStr == 'null') return 'never';
    try {
      final lastSeen = DateTime.parse(lastSeenStr).toLocal();
      return DateTime.now().difference(lastSeen).inMinutes < 3 ? 'online' : 'offline';
    } catch (e) {
      return 'never';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: widget.data, builder: (context, _) {
      final players = widget.data.players;
      final onlineCount = players.where((p) => _getUserStatus(p) == 'online').length;
      final offlineCount = players.where((p) => _getUserStatus(p) == 'offline').length;
      final neverCount = players.where((p) => _getUserStatus(p) == 'never').length;

      return Scaffold(
        appBar: AppBar(title: const Text('المراقبة والإدارة'), actions: [IconButton(onPressed: () => widget.data.loadPlayers(), icon: const Icon(Icons.refresh))]),
        floatingActionButton: FloatingActionButton(onPressed: () => edit(), child: const Icon(Icons.person_add)),
        body: Column(children: [
          Container(padding: const EdgeInsets.all(12), color: AppColors.cardBlack, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _statBox('🟢 متصل', onlineCount, Colors.green),
            _statBox('🔴 خرج', offlineCount, Colors.red),
            _statBox('⚪ لم يفتح', neverCount, Colors.grey),
          ])),
          Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: players.length, itemBuilder: (_, index) {
            final player = players[index];
            final avatar = clean(player['avatar_url']);
            final status = _getUserStatus(player);
            final hasId = player['account_id'] != null && parseInt(player['account_id']) > 0;
            final displayName = widget.data.displayNameForAccount(player['account_id']);
            Color statusColor;
            String statusText;
            if (!hasId) {
              statusColor = Colors.orange;
              statusText = '⚠️ بدون معرف';
            } else if (status == 'online') {
              statusColor = Colors.green;
              statusText = '🟢 يفتح التطبيق';
            } else if (status == 'offline') {
              statusColor = Colors.red;
              statusText = '🔴 خرج';
            } else {
              statusColor = Colors.grey;
              statusText = '⚪ لم يفتح أبداً';
            }

            return Card(child: ListTile(
              leading: Stack(children: [
                CircleAvatar(backgroundColor: AppColors.gold, backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null, child: avatar.isEmpty ? Text('${index + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)) : null),
                Positioned(bottom: 0, right: 0, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
              ]),
              title: Text(displayName, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getColorForName(displayName))),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                Text('ID: ${player['account_id'] ?? 'بدون'} | ${parseInt(player['points'])} نقطة', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => edit(player), icon: const Icon(Icons.edit, size: 20)),
                IconButton(onPressed: () async {
                  final ok = await confirmDelete(context, 'الحساب "$displayName"');
                  if (ok) await widget.data.deletePlayer(player['id']);
                }, icon: const Icon(Icons.delete, color: Colors.red, size: 20)),
              ]),
            ));
          })),
        ]),
      );
    });
  }

  Widget _statBox(String title, int count, Color color) => Column(children: [
    Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
    Text(title, style: TextStyle(color: color, fontSize: 11)),
  ]);
}

// =======================================================
// 3. الخبر المهم
// =======================================================
class ManageImportantNewsPage extends StatefulWidget {
  final AppData data;
  const ManageImportantNewsPage({super.key, required this.data});
  @override
  State<ManageImportantNewsPage> createState() => _ManageImportantNewsPageState();
}

class _ManageImportantNewsPageState extends State<ManageImportantNewsPage> {
  late final TextEditingController controller;
  @override
  void initState() { super.initState(); controller = TextEditingController(text: widget.data.importantNews); }
  @override
  void dispose() { controller.dispose(); super.dispose(); }

  Future<void> save() async {
    if (controller.text.trim().isEmpty) return;
    final ok = await widget.data.updateImportantNews(controller.text);
    if (!mounted) return;
    showSnack(context, ok ? 'تم حفظ الخبر.' : 'تعذر الحفظ.');
    if (ok) Navigator.pop(context);
  }

  Future<void> clear() async {
    final confirm = await confirmDelete(context, 'الخبر المهم الحالي');
    if (!confirm) return;
    final ok = await widget.data.clearImportantNews();
    if (!mounted) return;
    if (ok) {
      controller.clear();
      showSnack(context, 'تم الحذف.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('الخبر المهم')), body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: controller, maxLines: 5, decoration: const InputDecoration(labelText: 'نص الخبر المهم')),
      const SizedBox(height: 15),
      FilledButton(onPressed: save, child: const Text('حفظ ونشر')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: clear, child: const Text('حذف الخبر')),
    ]));
  }
}

// =======================================================
// 4. معرض الصور — ✅ مصحح: data بدلاً من widget.data
// =======================================================
class ManageGalleryPage extends StatelessWidget {
  final AppData data;
  const ManageGalleryPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('إدارة معرض الصور')), body: AnimatedBuilder(animation: data, builder: (context, _) {
      if (data.gallery.isEmpty) return const Center(child: Text('لا توجد صور.'));
      return ListView.builder(padding: const EdgeInsets.all(12), itemCount: data.gallery.length, itemBuilder: (_, index) {
        final item = data.gallery[index];
        return Card(clipBehavior: Clip.antiAlias, child: Column(children: [
          Image.network(clean(item['image_url']), width: double.infinity, height: 200, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 200, child: Icon(Icons.broken_image))),
          ListTile(
            title: Text(data.displayNameForAccount(item['account_id'])),
            trailing: IconButton(onPressed: () async {
              final ok = await confirmDelete(context, 'هذه الصورة');
              if (ok) await data.deleteGalleryImage(item['id']);
            }, icon: const Icon(Icons.delete, color: Colors.red)),
          ),
        ]));
      });
    }));
  }
}

// =======================================================
// 5. نتائج الاختبارات
// =======================================================
class ManageQuizResultsPage extends StatefulWidget {
  final AppData data;
  const ManageQuizResultsPage({super.key, required this.data});
  @override
  State<ManageQuizResultsPage> createState() => _ManageQuizResultsPageState();
}

class _ManageQuizResultsPageState extends State<ManageQuizResultsPage> {
  bool loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => loading = true);
    await widget.data.loadQuizResults();
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.gold)));
    final list = [...widget.data.quizResults]..sort((a, b) => clean(b['created_at']).compareTo(clean(a['created_at'])));
    return Scaffold(appBar: AppBar(title: const Text('النتائج')), body: list.isEmpty ? const Center(child: Text('لا توجد نتائج.')) : ListView.builder(itemCount: list.length, itemBuilder: (_, i) {
      final item = list[i];
      return Card(child: ListTile(
        title: Text(widget.data.displayNameForAccount(item['account_id']), style: const TextStyle(color: AppColors.gold)),
        subtitle: Text('${quizTypeName(clean(item['quiz_type']))} — ${item['correct_answers']}/${item['total_questions']}'),
      ));
    }));
  }
}

// =======================================================
// 6. إدارة الأسئلة
// =======================================================
class ManageQuizPage extends StatefulWidget {
  final AppData data;
  const ManageQuizPage({super.key, required this.data});
  @override
  State<ManageQuizPage> createState() => _ManageQuizPageState();
}

class _ManageQuizPageState extends State<ManageQuizPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأسئلة')),
      floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizEditorPage(data: widget.data))), child: const Icon(Icons.add)),
      body: AnimatedBuilder(animation: widget.data, builder: (context, _) {
        final list = widget.data.quizQuestions;
        if (list.isEmpty) return const Center(child: Text('لا توجد أسئلة.'));
        return ListView.builder(itemCount: list.length, itemBuilder: (_, i) => Card(child: ListTile(
          title: Text(clean(list[i]['question'])),
          trailing: IconButton(onPressed: () async {
            final ok = await confirmDelete(context, 'هذا السؤال');
            if (ok) await widget.data.deleteQuizQuestion(list[i]['id']);
          }, icon: const Icon(Icons.delete)),
        )));
      }),
    );
  }
}

class QuizEditorPage extends StatefulWidget {
  final AppData data;
  const QuizEditorPage({super.key, required this.data});
  @override
  State<QuizEditorPage> createState() => _QuizEditorPageState();
}

class _QuizEditorPageState extends State<QuizEditorPage> {
  final q = TextEditingController(), o1 = TextEditingController(), o2 = TextEditingController(), o3 = TextEditingController(), o4 = TextEditingController();
  int correct = 1;
  String type = 'direct';
  @override
  void dispose() { q.dispose(); o1.dispose(); o2.dispose(); o3.dispose(); o4.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('إضافة سؤال')), body: ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<String>(value: type, items: const [
        DropdownMenuItem(value: 'direct', child: Text('مباشر')),
        DropdownMenuItem(value: 'guess_character', child: Text('احزر الشخصية')),
      ], onChanged: (v) => setState(() => type = v!)),
      TextField(controller: q, decoration: const InputDecoration(labelText: 'السؤال')),
      TextField(controller: o1, decoration: const InputDecoration(labelText: 'خيار 1')),
      TextField(controller: o2, decoration: const InputDecoration(labelText: 'خيار 2')),
      TextField(controller: o3, decoration: const InputDecoration(labelText: 'خيار 3')),
      TextField(controller: o4, decoration: const InputDecoration(labelText: 'خيار 4')),
      DropdownButtonFormField<int>(value: correct, items: List.generate(4, (i) => DropdownMenuItem(value: i + 1, child: Text('الإجابة ${i + 1}'))), onChanged: (v) => setState(() => correct = v!)),
      FilledButton(onPressed: () async {
        final ok = await widget.data.addQuizQuestion(question: q.text, option1: o1.text, option2: o2.text, option3: o3.text, option4: o4.text, correctOption: correct, quizType: type);
        if (ok && context.mounted) Navigator.pop(context);
      }, child: const Text('حفظ')),
    ]));
  }
}

// =======================================================
// 7. إدارة الأخبار
// =======================================================
class ManageNewsPage extends StatefulWidget {
  final AppData data;
  const ManageNewsPage({super.key, required this.data});
  @override
  State<ManageNewsPage> createState() => _ManageNewsPageState();
}

class _ManageNewsPageState extends State<ManageNewsPage> {
  final t = TextEditingController(), d = TextEditingController();
  File? _image;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الأخبار')),
      floatingActionButton: FloatingActionButton(onPressed: () {
        t.clear();
        d.clear();
        _image = null;
        showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) {
          return AlertDialog(title: const Text('خبر جديد'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: t, decoration: const InputDecoration(labelText: 'العنوان')),
            TextField(controller: d, decoration: const InputDecoration(labelText: 'الوصف')),
            const SizedBox(height: 10),
            if (_image != null) Image.file(_image!, height: 120, width: double.infinity, fit: BoxFit.cover),
            OutlinedButton.icon(onPressed: () async {
              final picker = ImagePicker();
              final picked = await picker.pickImage(source: ImageSource.gallery);
              if (picked != null) setState(() => _image = File(picked.path));
            }, icon: const Icon(Icons.image), label: const Text('اختيار صورة')),
          ])), actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(onPressed: () async {
              await widget.data.addNews(t.text, d.text, imageFile: _image);
              if (context.mounted) Navigator.pop(context);
            }, child: const Text('نشر')),
          ]);
        }));
      }, child: const Icon(Icons.add)),
      body: AnimatedBuilder(animation: widget.data, builder: (context, _) => ListView.builder(itemCount: widget.data.news.length, itemBuilder: (_, i) => Card(child: ListTile(
        title: Text(clean(widget.data.news[i]['title'])),
        trailing: IconButton(onPressed: () async {
          final ok = await confirmDelete(context, 'خبر "${clean(widget.data.news[i]['title'])}"');
          if (ok) await widget.data.deleteNews(widget.data.news[i]['id']);
        }, icon: const Icon(Icons.delete)),
      )))),
    );
  }
}

// =======================================================
// 8. إدارة الإشعارات
// =======================================================
class ManageNotificationsPage extends StatefulWidget {
  final AppData data;
  const ManageNotificationsPage({super.key, required this.data});
  @override
  State<ManageNotificationsPage> createState() => _ManageNotificationsPageState();
}

class _ManageNotificationsPageState extends State<ManageNotificationsPage> {
  final t = TextEditingController(), b = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('إرسال إشعار')), body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      TextField(controller: t, decoration: const InputDecoration(labelText: 'العنوان')),
      TextField(controller: b, decoration: const InputDecoration(labelText: 'النص')),
      FilledButton(onPressed: () async {
        await widget.data.addNotification(t.text, b.text);
        t.clear();
        b.clear();
        showSnack(context, 'تم الإرسال');
      }, child: const Text('إرسال')),
    ])));
  }
}

// =======================================================
// 9. إدارة الاستطلاعات
// =======================================================
class ManagePollPage extends StatefulWidget {
  final AppData data;
  const ManagePollPage({super.key, required this.data});
  @override
  State<ManagePollPage> createState() => _ManagePollPageState();
}

class _ManagePollPageState extends State<ManagePollPage> {
  final q = TextEditingController();
  final o1 = TextEditingController(), o2 = TextEditingController(), o3 = TextEditingController(), o4 = TextEditingController();
  @override
  void dispose() { q.dispose(); o1.dispose(); o2.dispose(); o3.dispose(); o4.dispose(); super.dispose(); }

  Future<void> create() async {
    if (q.text.trim().isEmpty) return;
    final options = [o1.text, o2.text, o3.text, o4.text].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (options.length < 2) {
      showSnack(context, 'أدخل خيارين على الأقل.');
      return;
    }
    final ok = await widget.data.createPoll(q.text, options);
    if (ok && context.mounted) {
      q.clear(); o1.clear(); o2.clear(); o3.clear(); o4.clear();
      showSnack(context, 'تم إنشاء الاستطلاع.');
      Navigator.pop(context);
    } else {
      showSnack(context, 'تعذر الإنشاء.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('إنشاء استطلاع')), body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: q, decoration: const InputDecoration(labelText: 'سؤال الاستطلاع')),
      const SizedBox(height: 10),
      TextField(controller: o1, decoration: const InputDecoration(labelText: 'الخيار الأول')),
      const SizedBox(height: 10),
      TextField(controller: o2, decoration: const InputDecoration(labelText: 'الخيار الثاني')),
      const SizedBox(height: 10),
      TextField(controller: o3, decoration: const InputDecoration(labelText: 'الخيار الثالث (اختياري)')),
      const SizedBox(height: 10),
      TextField(controller: o4, decoration: const InputDecoration(labelText: 'الخيار الرابع (اختياري)')),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: create, icon: const Icon(Icons.poll), label: const Text('نشر الاستطلاع')),
    ]));
  }
}

// =======================================================
// 10. كل جديد
// =======================================================
class ManageLatestPage extends StatefulWidget {
  final AppData data;
  const ManageLatestPage({super.key, required this.data});
  @override
  State<ManageLatestPage> createState() => _ManageLatestPageState();
}

class _ManageLatestPageState extends State<ManageLatestPage> {
  final t = TextEditingController(), d = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('كل جديد')), body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(controller: t, decoration: const InputDecoration(labelText: 'العنوان')),
        TextField(controller: d, decoration: const InputDecoration(labelText: 'الوصف')),
        FilledButton(onPressed: () async {
          await widget.data.addLatest(t.text, d.text);
          t.clear();
          d.clear();
        }, child: const Text('إضافة')),
      ])),
      Expanded(child: AnimatedBuilder(animation: widget.data, builder: (context, _) => ListView.builder(itemCount: widget.data.latest.length, itemBuilder: (_, i) => ListTile(
        title: Text(clean(widget.data.latest[i]['title'])),
        trailing: IconButton(onPressed: () async {
          final ok = await confirmDelete(context, 'هذا العنصر');
          if (ok) await widget.data.deleteLatest(widget.data.latest[i]['id']);
        }, icon: const Icon(Icons.delete)),
      )))),
    ]));
  }
}

// =======================================================
// 11. رسائل المستخدمين — ✅ مصحح: قوس ناقص
// =======================================================
class ManageMessagesPage extends StatelessWidget {
  final AppData data;
  const ManageMessagesPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رسائل المستخدمين')),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          return ListView.builder(
            itemCount: data.messages.length,
            itemBuilder: (_, i) {
              return Card(
                child: ListTile(
                  title: Text(clean(data.messages[i]['name'])),
                  subtitle: Text(clean(data.messages[i]['message'])),
                  trailing: IconButton(
                    onPressed: () async {
                      final ok = await confirmDelete(context, 'رسالة "${clean(data.messages[i]['name'])}"');
                      if (ok) await data.deleteMessage(data.messages[i]['id']);
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
// 12. طلبات الشراء
// =======================================================
class ManagePurchaseRequestsPage extends StatelessWidget {
  final AppData data;
  const ManagePurchaseRequestsPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('طلبات الشراء')), body: AnimatedBuilder(animation: data, builder: (context, _) => ListView.builder(itemCount: data.purchaseRequests.length, itemBuilder: (_, i) {
      final req = data.purchaseRequests[i];
      final status = clean(req['status']);
      return Card(child: ListTile(
        title: Text(clean(req['item_type'])),
        subtitle: Text('الحالة: $status'),
        trailing: status == 'pending' ? Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: () => data.approvePurchase(req), icon: const Icon(Icons.check, color: Colors.green)),
          IconButton(onPressed: () async {
            final ok = await confirmDelete(context, 'رفض هذا الطلب');
            if (ok) await data.rejectPurchase(req['id']);
          }, icon: const Icon(Icons.close, color: Colors.red)),
        ]) : null,
      ));
    })));
  }
}