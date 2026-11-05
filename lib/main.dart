import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide toInt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'core/colors.dart';
import 'core/helpers.dart';
import 'data/app_data.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://sekchgllbimoedsjoumi.supabase.co',
    anonKey: 'sb_publishable_EZLVSUviR39RXi6OP3OqfQ_3j7vMZcU',
  );
  await LocalCache.init();
  runApp(const MrOtakuApp());

  Future.delayed(const Duration(seconds: 2), () async {
    try {
      await NotificationService.init();
      await NotificationService.registerBackgroundTask();
    } catch (e) {
      debugPrint('Notification setup error: $e');
    }
  });
}

class MrOtakuApp extends StatefulWidget {
  const MrOtakuApp({super.key});
  @override
  State<MrOtakuApp> createState() => _MrOtakuAppState();
}

class _MrOtakuAppState extends State<MrOtakuApp> {
  final AppData data = AppData();
  bool checking = true;

  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    try {
      await data.loadLocalAccount();
    } catch (e) {
      debugPrint('loadLocalAccount error: $e');
    }
    if (mounted) setState(() => checking = false);

    Future.microtask(() async {
      try {
        if (data.hasAccount) {
          final admin = await checkAdminSession(data); // من ملف helpers
          await data.setAdminSession(admin);
          await data.loadData();
        }
      } catch (e) {
        debugPrint('Background load error: $e');
      }
    });
  }

  ThemeData get theme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.black,
      cardColor: AppColors.cardBlack,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        onPrimary: Colors.black,
        secondary: AppColors.gold,
        onSecondary: Colors.black,
        surface: AppColors.cardBlack,
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.gold,
        centerTitle: true,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.black,
        indicatorColor: AppColors.gold.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.all(const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
        iconTheme: MaterialStateProperty.all(const IconThemeData(color: AppColors.gold)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBlack,
        labelStyle: const TextStyle(color: AppColors.gold),
        hintStyle: TextStyle(color: AppColors.gold.withOpacity(0.5)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.gold)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.borderGold)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.gold, width: 1.5)),
      ),
      cardTheme: CardTheme(
        color: AppColors.cardBlack,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(18)), side: const BorderSide(color: AppColors.borderGold)),
      ),
      iconTheme: const IconThemeData(color: AppColors.gold),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.gold)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.gold))),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.gold),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.gold))),
      );
    }

    return AnimatedBuilder(
      animation: data,
      builder: (_, __) {
        Widget home = !data.hasAccount ? AccountSetupPage(data: data) : HomePage(data: data);
        return MaterialApp(debugShowCheckedModeBanner: false, title: 'مستر أوتاكو', theme: theme, home: home);
      },
    );
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const String _channelId = 'mr_otaku_channel';
  static const String _channelName = 'إشعارات مستر أوتاكو';
  static const String _channelDesc = 'إشعارات الأخبار والإدارة';

  static Future<void> init() async {
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(settings);
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
      const AndroidNotificationChannel(_channelId, _channelName, description: _channelDesc, importance: Importance.high),
    );
  }

  static Future<void> show(String title, String body, {int id = 0}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(_channelId, _channelName, channelDescription: _channelDesc, importance: Importance.high, priority: Priority.high, icon: '@mipmap/ic_launcher'),
    );
    await _plugin.show(id, title, body, details);
  }

  static Future<void> registerBackgroundTask() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'mr_otaku_check', 'checkNotifications',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> checkNewNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getString('mr_otaku_last_notif_id') ?? '';
      final result = await Supabase.instance.client.from('notifications').select().order('created_at', ascending: false).limit(1);
      if (result.isEmpty) return;
      final first = result.first;
      final currentId = clean(first['id']);
      if (lastId.isNotEmpty && currentId != lastId) {
        await show(clean(first['title']), clean(first['body']), id: currentId.hashCode);
      }
      await prefs.setString('mr_otaku_last_notif_id', currentId);
    } catch (e) {
      debugPrint('Check notifications error: $e');
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      try { Supabase.instance.client; } catch (_) {
        await Supabase.initialize(url: 'https://sekchgllbimoedsjoumi.supabase.co', anonKey: 'sb_publishable_EZLVSUviR39RXi6OP3OqfQ_3j7vMZcU');
      }
    } catch (_) {}
    await NotificationService.init();
    await NotificationService.checkNewNotifications();
    return true;
  });
}