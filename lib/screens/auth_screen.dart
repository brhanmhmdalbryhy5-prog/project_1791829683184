import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/colors.dart';
import '../core/helpers.dart';
import '../data/app_data.dart';

class AccountSetupPage extends StatefulWidget {
  final AppData data;
  const AccountSetupPage({super.key, required this.data});

  @override
  State<AccountSetupPage> createState() => _AccountSetupPageState();
}

class _AccountSetupPageState extends State<AccountSetupPage> {
  final nameController = TextEditingController();
  final idController = TextEditingController();
  bool loading = false;

  Future<void> login() async {
    final name = nameController.text.trim();
    final id = int.tryParse(idController.text.trim());

    if (name.isEmpty || id == null || id <= 0) {
      showSnack(context, 'أدخل اسم المستخدم ومعرف الحساب بشكل صحيح.');
      return;
    }

    setState(() => loading = true);
    await playClickSound();

    final success = await widget.data.loginAccount(name, id);
    if (!mounted) return;

    if (!success) {
      setState(() => loading = false);
      showSnack(context, 'المعرف غير موجود أو الاسم لا يطابق الحساب.');
      return;
    }

    final isAdmin = await checkAdminSession(widget.data);
    await widget.data.setAdminSession(isAdmin);

    if (!mounted) return;
    setState(() => loading = false);
  }

  @override
  void dispose() {
    nameController.dispose();
    idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.auto_awesome, size: 75, color: AppColors.gold),
                    const SizedBox(height: 15),
                    const Text('مستر أوتاكو', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.gold)),
                    const SizedBox(height: 8),
                    const Text('تسجيل الدخول', style: TextStyle(fontSize: 17, color: AppColors.goldLight)),
                    const SizedBox(height: 25),
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person))),
                    const SizedBox(height: 14),
                    TextField(
                      controller: idController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'معرف الحساب', prefixIcon: Icon(Icons.badge)),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: loading ? null : login,
                        icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.login),
                        label: const Text('دخول'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('إذا لم يكن لديك حساب، اطلب من الإدارة إنشاء حساب لك.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.gold.withOpacity(0.7))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}