import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';

class QuestionsHubPage extends StatelessWidget {
  final AppData data;
  const QuestionsHubPage({super.key, required this.data});
  Future<void> open(BuildContext context, String type) async { await playClickSound(); await data.loadQuizQuestions(); if (!context.mounted) return; Navigator.push(context, MaterialPageRoute(builder: (_) => QuizPage(data: data, typeFilter: type))); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأسئلة')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _QuestionTypeCard(icon: Icons.person_search, title: 'احزر الشخصية', description: 'سؤال نصي مع أربعة اختيارات.', colorIndex: 0, onTap: () => open(context, 'guess_character')),
        _QuestionTypeCard(icon: Icons.image_search, title: 'خمن اسم الشخصية من الصورة', description: 'تظهر صورة الشخصية مع أربعة أسماء.', colorIndex: 1, onTap: () => open(context, 'image_character')),
        _QuestionTypeCard(icon: Icons.help_outline, title: 'أسئلة مباشرة', description: 'أسئلة مباشرة عن الأنمي والشخصيات.', colorIndex: 2, onTap: () => open(context, 'direct')),
      ]),
    );
  }
}

class _QuestionTypeCard extends StatelessWidget {
  final IconData icon; final String title; final String description; final VoidCallback onTap; final int colorIndex;
  const _QuestionTypeCard({required this.icon, required this.title, required this.description, required this.onTap, required this.colorIndex});
  @override
  Widget build(BuildContext context) {
    final color = AppColors.getColor(colorIndex);
    return Card(margin: const EdgeInsets.only(bottom: 14), child: ListTile(contentPadding: const EdgeInsets.all(16), leading: CircleAvatar(radius: 28, backgroundColor: color, child: Icon(icon, color: Colors.white)), title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), subtitle: Text(description), trailing: const Icon(Icons.arrow_back_ios), onTap: onTap));
  }
}

class QuizPage extends StatefulWidget {
  final AppData data; final String typeFilter;
  const QuizPage({super.key, required this.data, required this.typeFilter});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<Map<String, dynamic>> questions;
  int current = 0, correctAnswers = 0;
  int? selected;
  bool answered = false, _saved = false;

  @override
  void initState() { super.initState(); questions = widget.data.quizQuestions.where((q) { final rawType = clean(q['quiz_type']); final type = rawType.isEmpty ? 'direct' : rawType; return type == widget.typeFilter; }).toList(); }

  Map<String, dynamic>? get currentQuestion => (questions.isEmpty || current >= questions.length) ? null : questions[current];
  String option(int number) => clean(currentQuestion?['option$number']);

  Future<void> answer(int number) async {
    if (answered || currentQuestion == null) return;
    await playClickSound(); final correct = parseInt(currentQuestion!['correct_option']);
    setState(() { selected = number; answered = true; if (number == correct) correctAnswers++; });
  }

  Future<void> _saveResultIfNeeded() async { if (_saved) return; _saved = true; await widget.data.saveQuizResult(quizType: widget.typeFilter, correct: correctAnswers, total: questions.length); }
  
  Future<void> next() async {
    if (!answered) return;
    if (current + 1 >= questions.length) {
      await _saveResultIfNeeded(); if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuizResultPage(data: widget.data, correct: correctAnswers, total: questions.length, typeFilter: widget.typeFilter))); return;
    }
    setState(() { current++; selected = null; answered = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) return Scaffold(appBar: AppBar(title: Text(quizTypeName(widget.typeFilter))), body: const Center(child: Text('لا توجد أسئلة.')));
    final q = currentQuestion!; final correct = parseInt(q['correct_option']); final myColor = AppColors.getColor(widget.typeFilter.length);
    return Scaffold(
      appBar: AppBar(title: Text(quizTypeName(widget.typeFilter))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        LinearProgressIndicator(value: (current + 1) / questions.length, backgroundColor: AppColors.cardBlack, color: myColor),
        const SizedBox(height: 12),
        Text('السؤال ${current + 1} من ${questions.length}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: myColor)),
        const SizedBox(height: 16),
        if (widget.typeFilter == 'image_character' && clean(q['image_url']).isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(18), child: CachedNetworkImage(imageUrl: clean(q['image_url']), height: 250, fit: BoxFit.contain, errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 50, color: AppColors.gold))),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(clean(q['question']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)))),
        const SizedBox(height: 15),
        for (int i = 1; i <= 4; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: SizedBox(width: double.infinity, child: FilledButton(onPressed: answered ? null : () => answer(i), style: FilledButton.styleFrom(backgroundColor: answered && i == correct ? Colors.green : answered && i == selected ? Colors.red : myColor, foregroundColor: Colors.white), child: Padding(padding: const EdgeInsets.all(13), child: Text(option(i), textAlign: TextAlign.center))))),
        if (answered) Card(child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [Icon(selected == correct ? Icons.check_circle : Icons.cancel, color: selected == correct ? Colors.green : Colors.red), const SizedBox(width: 10), Expanded(child: Text(selected == correct ? 'إجابة صحيحة! 🔥' : 'إجابة خاطئة. الإجابة الصحيحة هي: ${option(correct)}', style: const TextStyle(fontWeight: FontWeight.bold)))]))),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: answered ? next : null, icon: const Icon(Icons.arrow_back), label: Text(current + 1 >= questions.length ? 'عرض النتيجة' : 'السؤال التالي')),
      ]),
    );
  }
}

class QuizResultPage extends StatelessWidget {
  final AppData data; final int correct, total; final String typeFilter;
  const QuizResultPage({super.key, required this.data, required this.correct, required this.total, required this.typeFilter});
  double get percentage => total == 0 ? 0 : correct / total * 100;
  String get message { if (percentage >= 90) return 'أسطوري! معلوماتك رائعة 🏆'; if (percentage >= 70) return 'ممتاز! مستواك قوي جداً 🔥'; if (percentage >= 50) return 'جيد! يمكنك الوصول للأفضل ⚔️'; return 'تحتاج إلى المزيد من التدريب 😄'; }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النتيجة')),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Card(child: Padding(padding: const EdgeInsets.all(25), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.emoji_events, size: 80, color: AppColors.gold),
        const SizedBox(height: 15),
        const Text('نتيجتك', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.gold)),
        const SizedBox(height: 15),
        Text('${percentage.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppColors.gold)),
        const SizedBox(height: 10),
        Text('$correct من $total إجابات صحيحة'),
        const SizedBox(height: 15),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 25),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuizPage(data: data, typeFilter: typeFilter))), child: const Text('إعادة الاختبار'))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('العودة')),
      ]))))),
    );
  }
}

class LeaderboardPage extends StatelessWidget {
  final AppData data;
  const LeaderboardPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final list = [...data.players]..sort((a, b) => parseInt(b['points']).compareTo(parseInt(a['points'])));
    return Scaffold(
      appBar: AppBar(title: const Text('المتصدرون')),
      body: list.isEmpty ? const Center(child: Text('لا يوجد لاعبون.')) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: list.length, itemBuilder: (_, index) {
        final player = list[index]; final points = parseInt(player['points']); final badge = getCurrentBadge(points); final avatar = clean(player['avatar_url']); final name = clean(player['name']); final myColor = AppColors.getColorForName(name);
        return Card(child: ListTile(
          leading: GestureDetector(onTap: () => showAvatarDialog(context, avatar, name), child: CircleAvatar(backgroundColor: myColor, backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null, child: avatar.isEmpty ? Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null)),
          title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: myColor)),
          subtitle: Text('المستوى ${getUserLevel(points)}${badge == null ? '' : ' • ${badge.icon} ${badge.name}'}'),
          trailing: Text('$points نقطة', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
        ));
      }),
    );
  }
}

class SendMessagePage extends StatefulWidget {
  final AppData data;
  const SendMessagePage({super.key, required this.data});
  @override
  State<SendMessagePage> createState() => _SendMessagePageState();
}

class _SendMessagePageState extends State<SendMessagePage> {
  final controller = TextEditingController();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  Future<void> send() async { final ok = await widget.data.sendMessage(widget.data.currentUserName, controller.text); if (!mounted) return; if (ok) { controller.clear(); showSnack(context, 'تم إرسال رسالتك للإدارة.'); } else { showSnack(context, 'تعذر إرسال الرسالة.'); } }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إرسال رسالة')),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Text('سيتم إرسال الرسالة باسم ${widget.data.currentUserName}'),
        const SizedBox(height: 15),
        TextField(controller: controller, maxLines: 7, decoration: const InputDecoration(labelText: 'رسالتك', alignLabelWithHint: true)),
        const SizedBox(height: 15),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: send, icon: const Icon(Icons.send), label: const Text('إرسال'))),
      ])),
    );
  }
}