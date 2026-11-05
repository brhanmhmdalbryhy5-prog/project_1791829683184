import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';

// =======================================================
// 1. مركز الأسئلة
// =======================================================
class QuestionsHubPage extends StatelessWidget {
  final AppData data;
  const QuestionsHubPage({super.key, required this.data});

  Future<void> open(BuildContext context, String type) async {
    await playClickSound();
    await data.loadQuizQuestions();
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuizPage(data: data, typeFilter: type)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأسئلة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _QuestionTypeCard(
            icon: Icons.person_search,
            title: 'احزر الشخصية',
            description: 'سؤال نصي مع أربعة اختيارات.',
            colorIndex: 0,
            onTap: () => open(context, 'guess_character'),
          ),
          _QuestionTypeCard(
            icon: Icons.image_search,
            title: 'خمن اسم الشخصية من الصورة',
            description: 'تظهر صورة الشخصية مع أربعة أسماء.',
            colorIndex: 1,
            onTap: () => open(context, 'image_character'),
          ),
          _QuestionTypeCard(
            icon: Icons.help_outline,
            title: 'أسئلة مباشرة',
            description: 'أسئلة مباشرة عن الأنمي والشخصيات.',
            colorIndex: 2,
            onTap: () => open(context, 'direct'),
          ),
        ],
      ),
    );
  }
}

class _QuestionTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final int colorIndex;

  const _QuestionTypeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.colorIndex,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getColor(colorIndex);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(radius: 28, backgroundColor: color, child: Icon(icon, color: Colors.white)),
        title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        subtitle: Text(description),
        trailing: const Icon(Icons.arrow_back_ios),
        onTap: onTap,
      ),
    );
  }
}

// =======================================================
// 2. لعبة الأسئلة (مع إصلاح حفظ النتيجة)
// =======================================================
class QuizPage extends StatefulWidget {
  final AppData data;
  final String typeFilter;
  const QuizPage({super.key, required this.data, required this.typeFilter});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<Map<String, dynamic>> questions;
  int current = 0;
  int correctAnswers = 0;
  int? selected;
  bool answered = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    questions = widget.data.quizQuestions.where((q) {
      final rawType = clean(q['quiz_type']);
      final type = rawType.isEmpty ? 'direct' : rawType;
      return type == widget.typeFilter;
    }).toList();
  }

  Map<String, dynamic>? get currentQuestion {
    if (questions.isEmpty || current >= questions.length) return null;
    return questions[current];
  }

  String option(int number) => clean(currentQuestion?['option$number']);

  Future<void> answer(int number) async {
    if (answered || currentQuestion == null) return;
    await playClickSound();
    final correct = toInt(currentQuestion!['correct_option']);
    setState(() {
      selected = number;
      answered = true;
      if (number == correct) correctAnswers++;
    });
  }

  Future<void> _saveResultIfNeeded() async {
    if (_saved) return;
    _saved = true;
    await widget.data.saveQuizResult(
      quizType: widget.typeFilter,
      correct: correctAnswers,
      total: questions.length,
    );
  }

  // ✅ تم إصلاح هذه الدالة لتصبح async وتنتظر الحفظ
  Future<void> next() async {
    if (!answered) return;
    if (current + 1 >= questions.length) {
      await _saveResultIfNeeded();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuizResultPage(
            data: widget.data,
            correct: correctAnswers,
            total: questions.length,
            typeFilter: widget.typeFilter,
          ),
        ),
      );
      return;
    }
    setState(() {
      current++;
      selected = null;
      answered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(quizTypeName(widget.typeFilter))),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('لا توجد أسئلة من هذا النوع حالياً.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
          ),
        ),
      );
    }

    final q = currentQuestion!;
    final correct = toInt(q['correct_option']);
    final myColor = AppColors.getColor(widget.typeFilter.length);

    return Scaffold(
      appBar: AppBar(title: Text(quizTypeName(widget.typeFilter))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LinearProgressIndicator(value: (current + 1) / questions.length, backgroundColor: AppColors.cardBlack, color: myColor),
          const SizedBox(height: 12),
          Text('السؤال ${current + 1} من ${questions.length}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: myColor)),
          const SizedBox(height: 16),
          if (widget.typeFilter == 'image_character' && clean(q['image_url']).isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(clean(q['image_url']), height: 250, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50, color: AppColors.gold)),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(clean(q['question']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 15),
          for (int i = 1; i <= 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: answered ? null : () => answer(i),
                  style: FilledButton.styleFrom(
                    backgroundColor: answered && i == correct ? Colors.green : answered && i == selected ? Colors.red : myColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Text(option(i), textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),
          if (answered)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Icon(selected == correct ? Icons.check_circle : Icons.cancel, color: selected == correct ? Colors.green : Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        selected == correct ? 'إجابة صحيحة! 🔥' : 'إجابة خاطئة. الإجابة الصحيحة هي: ${option(correct)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: answered ? next : null, // تستدعي الدالة async
            icon: const Icon(Icons.arrow_back),
            label: Text(current + 1 >= questions.length ? 'عرض النتيجة' : 'السؤال التالي'),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// 3. نتيجة الأسئلة
// =======================================================
class QuizResultPage extends StatelessWidget {
  final AppData data;
  final int correct;
  final int total;
  final String typeFilter;

  const QuizResultPage({super.key, required this.data, required this.correct, required this.total, required this.typeFilter});

  double get percentage => total == 0 ? 0 : correct / total * 100;

  String get message {
    if (percentage >= 90) return 'أسطوري! معلوماتك رائعة 🏆';
    if (percentage >= 70) return 'ممتاز! مستواك قوي جداً 🔥';
    if (percentage >= 50) return 'جيد! يمكنك الوصول للأفضل ⚔️';
    return 'تحتاج إلى المزيد من التدريب 😄';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النتيجة')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => QuizPage(data: data, typeFilter: typeFilter)),
                        );
                      },
                      child: const Text('إعادة الاختبار'),
                    ),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('العودة')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =======================================================
// 4. لعبة القفز
// =======================================================
class JumpGamePage extends StatefulWidget {
  final AppData data;
  const JumpGamePage({super.key, required this.data});

  @override
  State<JumpGamePage> createState() => _JumpGamePageState();
}

class _JumpGamePageState extends State<JumpGamePage> {
  Timer? timer;
  double playerY = 0;
  double velocity = 0;
  double rockX = 1.1;
  bool playing = false;
  bool gameOver = false;
  int score = 0;
  int best = 0;
  DateTime lastScore = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadBest();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => best = prefs.getInt('mr_otaku_jump_best') ?? 0);
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mr_otaku_jump_best', best);
  }

  void startGame() {
    timer?.cancel();
    setState(() {
      playing = true;
      gameOver = false;
      playerY = 0;
      velocity = 0;
      rockX = 1.1;
      score = 0;
      lastScore = DateTime.now();
    });
    timer = Timer.periodic(const Duration(milliseconds: 30), (_) => updateGame());
  }

  void updateGame() {
    if (!mounted || !playing) return;
    const gravity = -0.014;
    playerY += velocity;
    velocity += gravity;
    if (playerY < 0) { playerY = 0; velocity = 0; }
    final difficulty = 0.018 + min(score * 0.0007, 0.018);
    rockX -= difficulty;
    if (rockX < -1.2) rockX = 1.1;
    final playerHitX = rockX < -0.55 && rockX > -0.82;
    final playerOnGround = playerY < 0.10;
    if (playerHitX && playerOnGround) { endGame(); return; }
    if (DateTime.now().difference(lastScore).inMilliseconds > 900) {
      lastScore = DateTime.now();
      setState(() => score++);
    }
    setState(() {});
  }

  void jump() {
    if (!playing) { startGame(); return; }
    if (playerY <= 0.01) velocity = 0.25;
  }

  Future<void> endGame() async {
    timer?.cancel();
    setState(() { playing = false; gameOver = true; });
    if (score > best) { best = score; await _saveBest(); }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لعبة القفز')),
      body: GestureDetector(
        onTap: jump,
        child: Container(
          width: double.infinity,
          color: AppColors.black,
          child: Column(
            children: [
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text('النقاط: $score', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.gold)),
                  Text('الأفضل: $best', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.gold)),
                ],
              ),
              Expanded(child: CustomPaint(painter: JumpPainter(playerY: playerY, rockX: rockX), child: Container())),
              if (!playing)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(gameOver ? 'انتهت اللعبة! نتيجتك: $score' : 'اضغط للبدء', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.gold)),
                      const SizedBox(height: 15),
                      FilledButton.icon(onPressed: startGame, icon: const Icon(Icons.play_arrow), label: Text(gameOver ? 'إعادة اللعب' : 'ابدأ اللعبة')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class JumpPainter extends CustomPainter {
  final double playerY;
  final double rockX;
  JumpPainter({required this.playerY, required this.rockX});

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height * 0.78;
    final playerX = size.width * 0.25;
    const playerHeight = 55.0;
    final py = groundY - playerY * size.height * 0.75 - playerHeight;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(playerX, py, 40, playerHeight), const Radius.circular(10)),
      Paint()..style = PaintingStyle.fill..color = AppColors.gold,
    );

    final rockXPosition = size.width * ((rockX + 1) / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rockXPosition, groundY - 40, 42, 40), const Radius.circular(8)),
      Paint()..style = PaintingStyle.fill..color = Colors.red.shade900,
    );

    canvas.drawRect(Rect.fromLTWH(0, groundY, size.width, 5), Paint()..color = AppColors.gold);
  }

  @override
  bool shouldRepaint(covariant JumpPainter oldDelegate) => oldDelegate.playerY != playerY || oldDelegate.rockX != rockX;
}

// =======================================================
// 5. المتصدرون
// =======================================================
class LeaderboardPage extends StatelessWidget {
  final AppData data;
  const LeaderboardPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final list = [...data.players];
    list.sort((a, b) => toInt(b['points']).compareTo(toInt(a['points'])));

    return Scaffold(
      appBar: AppBar(title: const Text('المتصدرون')),
      body: list.isEmpty
          ? const Center(child: Text('لا يوجد لاعبون.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, index) {
                final player = list[index];
                final points = toInt(player['points']);
                final badge = getCurrentBadge(points);
                final avatar = clean(player['avatar_url']);
                final name = clean(player['name']);
                final myColor = AppColors.getColorForName(name);

                return Card(
                  child: ListTile(
                    leading: GestureDetector(
                      onTap: () => showAvatarDialog(context, avatar, name),
                      child: CircleAvatar(
                        backgroundColor: myColor,
                        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                        child: avatar.isEmpty ? Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
                      ),
                    ),
                    title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: myColor)),
                    subtitle: Text('المستوى ${getUserLevel(points)}${badge == null ? '' : ' • ${badge.icon} ${badge.name}'}'),
                    trailing: Text('$points نقطة', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
                  ),
                );
              },
            ),
    );
  }
}

// =======================================================
// 6. المتجر
// =======================================================
class ShopPage extends StatefulWidget {
  final AppData data;
  const ShopPage({super.key, required this.data});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  Map<String, dynamic>? selectedPlayer;

  @override
  void initState() {
    super.initState();
    selectedPlayer = widget.data.currentPlayer;
  }

  Future<void> buy(String item, int cost) async {
    if (selectedPlayer == null) { showSnack(context, 'لم يتم العثور على حساب.'); return; }
    final points = toInt(selectedPlayer!['points']);
    if (points < cost) { showSnack(context, 'نقاطك غير كافية.'); return; }

    final ok = await widget.data.createPurchaseRequest(selectedPlayer!['id'], item, cost);
    if (!mounted) return;
    showSnack(context, ok ? 'تم إرسال طلب الشراء للإدارة.' : 'تعذر إرسال الطلب.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('متجر النقاط')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (selectedPlayer != null)
            Card(
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: AppColors.gold, child: Icon(Icons.person, color: Colors.black)),
                title: Text(clean(selectedPlayer!['name']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold)),
                subtitle: Text('${toInt(selectedPlayer!['points'])} نقطة'),
              ),
            ),
          const SizedBox(height: 15),
          _ShopItem(title: 'تغيير اسم المجموعة', cost: 5, icon: Icons.edit, colorIndex: 0, onBuy: () => buy('تغيير اسم المجموعة', 5)),
          _ShopItem(title: 'أيقونة خاصة', cost: 10, icon: Icons.image, colorIndex: 1, onBuy: () => buy('أيقونة خاصة', 10)),
        ],
      ),
    );
  }
}

class _ShopItem extends StatelessWidget {
  final String title;
  final int cost;
  final IconData icon;
  final VoidCallback onBuy;
  final int colorIndex;

  const _ShopItem({required this.title, required this.cost, required this.icon, required this.onBuy, required this.colorIndex});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getColor(colorIndex);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white)),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        subtitle: Text('$cost نقاط'),
        trailing: FilledButton(onPressed: onBuy, child: const Text('شراء')),
      ),
    );
  }
}

// =======================================================
// 7. إرسال رسالة للإدارة
// =======================================================
class SendMessagePage extends StatefulWidget {
  final AppData data;
  const SendMessagePage({super.key, required this.data});

  @override
  State<SendMessagePage> createState() => _SendMessagePageState();
}

class _SendMessagePageState extends State<SendMessagePage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final ok = await widget.data.sendMessage(widget.data.currentUserName, controller.text);
    if (!mounted) return;
    if (ok) { controller.clear(); showSnack(context, 'تم إرسال رسالتك للإدارة.'); }
    else { showSnack(context, 'تعذر إرسال الرسالة.'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إرسال رسالة')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('سيتم إرسال الرسالة باسم ${widget.data.currentUserName}'),
            const SizedBox(height: 15),
            TextField(controller: controller, maxLines: 7, decoration: const InputDecoration(labelText: 'رسالتك', alignLabelWithHint: true)),
            const SizedBox(height: 15),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: send, icon: const Icon(Icons.send), label: const Text('إرسال'))),
          ],
        ),
      ),
    );
  }
}