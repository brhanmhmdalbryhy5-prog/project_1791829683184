import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommentsScreen extends StatefulWidget {
  final String postId; // معرف الخبر/المنشور الذي نعرض تعليقاته

  const CommentsScreen({Key? key, required this.postId}) : super(key: key);

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> comments = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchComments();
  }

  // دالة جلب التعليقات مع بيانات المستخدم من Supabase
  Future<void> fetchComments() async {
    try {
      final response = await supabase
          .from('comments')
          // هنا نقوم بربط جدول التعليقات بجدول المستخدمين لجلب الاسم والصورة
          .select('''
            id,
            comment_text,
            created_at,
            user_id,
            profiles (
              username,
              avatar_url
            )
          ''')
          .eq('post_id', widget.postId) // جلب التعليقات الخاصة بهذا الخبر فقط
          .order('created_at', ascending: false); // ترتيب التعليقات من الأحدث للأقدم

      setState(() {
        comments = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      print('خطأ في جلب التعليقات: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التعليقات'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : comments.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد تعليقات بعد',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return _buildCommentItem(comment);
                  },
                ),
    );
  }

  // تصميم شكل التعليق الواحد
  Widget _buildCommentItem(Map<String, dynamic> comment) {
    // جلب بيانات المستخدم المرتبطة بالتعليق
    final profile = comment['profiles'];
    
    // الاسم: إذا لم يوجد نضع "مستخدم"
    final String username = profile?['username'] ?? 'مستخدم';
    
    // الصورة: إذا لم توجد نضع null
    final String? avatarUrl = profile?['avatar_url'];
    
    // نص التعليق
    final String commentText = comment['comment_text'] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. الصورة الرمزية للمستخدم
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey[800],
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? NetworkImage(avatarUrl)
                : null, // إذا لم توجد صورة، لا نضع شيئاً
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? const Icon(Icons.person, color: Colors.white, size: 28) // أيقونة بديلة
                : null,
          ),
          const SizedBox(width: 12),
          
          // 2. الاسم ونص التعليق
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  commentText,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}