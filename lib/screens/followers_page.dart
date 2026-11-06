import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';
import 'social_screens.dart';

// ================= قائمة المتابعين/يتابع =================
class FollowersPage extends StatefulWidget {
  final AppData data;
  final bool showFollowers; // true = من يتابعني، false = الذين أتابعهم
  final int accountId; // صاحب الحساب
  const FollowersPage({super.key, required this.data, required this.showFollowers, required this.accountId});

  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = widget.showFollowers
        ? await widget.data.getFollowers(widget.accountId)
        : await widget.data.getFollowing(widget.accountId);
    if (mounted) setState(() { _list = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.showFollowers ? 'المتابعون' : 'يتابع')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _list.isEmpty
              ? Center(child: Text(widget.showFollowers ? 'لا يوجد متابعون.' : 'لا تتابع أحداً.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final p = _list[i];
                    final name = clean(p['channel_name']).isNotEmpty ? clean(p['channel_name']) : clean(p['name']);
                    final avatar = clean(p['avatar_url']);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.gold,
                          backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                          child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.black) : null,
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.arrow_back_ios, size: 16),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => UserProfilePage(data: widget.data, accountId: parseInt(p['account_id']), userName: name),
                        )),
                      ),
                    );
                  },
                ),
    );
  }
}