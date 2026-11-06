import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';

// ================= لوحة إحصائيات المدير =================
class AdminStatsPage extends StatelessWidget {
  final AppData data;
  const AdminStatsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        final players = data.players.length;
        final posts = data.posts.length;
        final news = data.news.length;
        final gallery = data.gallery.length;
        final complaints = data.complaints.length;
        final pendingComplaints = data.complaints.where((c) => c['status'] == 'pending').length;
        final onlinePlayers = data.players.where((p) {
          final last = clean(p['last_seen']);
          if (last.isEmpty) return false;
          try { return DateTime.now().difference(DateTime.parse(last)).inMinutes < 3; } catch (_) { return false; }
        }).length;

        return Scaffold(
          appBar: AppBar(title: const Text('إحصائيات المدير')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // بطاقات الإحصائيات
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _statCard('👥', 'المستخدمون', '$players', Colors.blue),
                  _statCard('🟢', 'متصل الآن', '$onlinePlayers', Colors.green),
                  _statCard('📝', 'المنشورات', '$posts', AppColors.getColor(6)),
                  _statCard('📰', 'الأخبار', '$news', AppColors.getColor(2)),
                  _statCard('📸', 'صور المعرض', '$gallery', AppColors.getColor(4)),
                  _statCard('⚠️', 'بلاغات معلقة', '$pendingComplaints', Colors.red),
                ],
              ),
              const SizedBox(height: 16),
              // المتصدر
              if (data.leader != null)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.gold,
                      backgroundImage: clean(data.leader!['avatar_url']).isNotEmpty ? CachedNetworkImageProvider(clean(data.leader!['avatar_url'])) : null,
                      child: clean(data.leader!['avatar_url']).isEmpty ? const Icon(Icons.emoji_events, color: Colors.black) : null,
                    ),
                    title: const Text('المتصدر', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
                    subtitle: Text(clean(data.leader!['name'])),
                    trailing: Text('${parseInt(data.leader!['points'])} نقطة', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              const SizedBox(height: 16),
              // آخر النشاطات
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('📊 إجمالي البلاغات', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
                    const SizedBox(height: 8),
                    Text('المجموع: $complaints  |  معلقة: $pendingComplaints  |  تم حلها: ${complaints - pendingComplaints}'),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String icon, String title, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.3), color.withOpacity(0.1)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(icon, style: const TextStyle(fontSize: 32)),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(title, style: TextStyle(fontSize: 12, color: color)),
      ]),
    );
  }
}

// ================= صفحة البلاغات =================
class ManageComplaintsPage extends StatelessWidget {
  final AppData data;
  const ManageComplaintsPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البلاغات')),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          if (data.complaints.isEmpty) return const Center(child: Text('لا توجد بلاغات.'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: data.complaints.length,
            itemBuilder: (_, i) {
              final c = data.complaints[i];
              final status = clean(c['status']);
              final color = status == 'pending' ? Colors.red : Colors.green;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.flag, color: color),
                      const SizedBox(width: 8),
                      Expanded(child: Text('بلاغ من: ${clean(c['reporter_name'])}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      Chip(label: Text(status), backgroundColor: color.withOpacity(0.2)),
                    ]),
                    const SizedBox(height: 8),
                    Text('النوع: ${clean(c['target_type'])} | ID: ${c['target_id']}'),
                    Text('السبب: ${clean(c['reason'])}', style: const TextStyle(fontStyle: FontStyle.italic)),
                    if (status == 'pending') Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () async { await data.resolveComplaint(c['id'], 'resolved'); }, child: const Text('تم الحل'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton(onPressed: () async { await data.resolveComplaint(c['id'], 'rejected'); }, child: const Text('رفض البلاغ'))),
                    ]),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}