import 'package:flutter/material.dart';
import 'config.dart';
import 'lobby_screens.dart';
import 'models.dart';
import 'profile_screen.dart';
import 'progress.dart';
import 'settings_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
  }

  Future<void> _firstRun() async {
    final p = Store.i.profile;
    if (p.name.isEmpty) await _askName();
    if (!mounted) return;
    if (!p.tutorialSeen) {
      await _howTo();
      p.tutorialSeen = true;
      Store.i.saveProfile();
    }
    final r = Store.i.claimDaily();
    if (r > 0 && mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🎁 مكافأة الدخول اليومي'),
          content: Text(
              '+${r.toStringAsFixed(1)} نقطة\nأيام متتالية: ${p.loginStreak}\n(كل يوم متتالٍ يزيد المكافأة حتى 7 أيام)'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('رائع')),
          ],
        ),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _askName() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('اختر اسم لاعبك'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                maxLength: 12,
                autofocus: true,
                onChanged: (_) => setS(() {}),
                decoration: const InputDecoration(hintText: 'اسمك في اللعبة'),
              ),
              const Text('الاسم يبقى ثابتاً في كل مرة تدخل فيها اللعبة.',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: ctrl.text.trim().isEmpty
                  ? null
                  : () {
                      Store.i.profile.name = ctrl.text.trim();
                      Store.i.saveProfile();
                      Navigator.pop(ctx);
                    },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _howTo() {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('كيف تلعب'),
        content: SingleChildScrollView(
          child: Text(
            '• المس أي مكان بالشاشة وحرّك إصبعك: الدودة تتجه حسب حركة إصبعك.\n'
            '• ضغطتان سريعتان: تسريع ${Cfg.boostDuration.round()} ثوانٍ، ثم انتظار ${Cfg.boostCooldown.round()} ثوانٍ.\n'
            '• كُل الفواكه لتكبر. الفاكهة الذهبية تعطي نمواً أكبر.\n'
            '• القدرات: 🛡️ درع يحميك من موت واحد، 🧲 مغناطيس يجذب الفواكه، ❄️ تجميد يبطّئ من حولك.\n'
            '• إذا لمس رأسك الجدار أو جسم دودة أخرى تموت وتتحول إلى فواكه.\n'
            '• تفوز بقتل ${10} دودات، وتخرج بعد ${10} موتات.\n'
            '• اسحب الخريطة المصغرة ولوحة الترتيب لأي مكان.\n'
            '• كل فوز يرفع مستواك: 100 مستوى وألقاب وألوان توهج تتغير كل 10 مستويات.',
            style: const TextStyle(height: 1.6),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
        ],
      ),
    );
  }

  Future<void> _go(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  void _multi() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.wifi_tethering),
              title: const Text('استضافة غرفة'),
              subtitle: const Text('افتح غرفة ليدخلها أصدقاؤك (بلوتوث / واي فاي)'),
              onTap: () {
                Navigator.pop(ctx);
                _go(const HostLobbyScreen());
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('الانضمام لغرفة'),
              subtitle: const Text('ابحث عن غرفة قريبة منك'),
              onTap: () {
                Navigator.pop(ctx);
                _go(const JoinScreen());
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Store.i.profile;
    final lv = p.level;
    final tier = tierOf(lv);
    final gc = kGlowColors[tier];

    Widget btn(String text, IconData icon, VoidCallback f, {bool main = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: main
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: f,
                  icon: Icon(icon),
                  label: Text(text, style: const TextStyle(fontSize: 18)),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: f,
                  icon: Icon(icon),
                  label: Text(text),
                ),
        );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B2A3A), Color(0xFF16526B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('🐍 لعبة الدودة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => _go(const ProfileScreen()),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x33FFFFFF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: gc, width: 2),
                          boxShadow: [
                            BoxShadow(color: gc.withAlpha(120), blurRadius: 12)
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(p.name.isEmpty ? '...' : p.name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text('${kTitles[tier]} · المستوى $lv · ${p.wins} فوز',
                                style: TextStyle(
                                    color: gc, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                                value: levelProgress(p.points),
                                minHeight: 6,
                                color: gc),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    btn('لعب فردي ضد البوتات', Icons.person,
                        () => _go(const SoloSetupScreen()),
                        main: true),
                    btn('لعب جماعي (بلوتوث / واي فاي)', Icons.groups, _multi,
                        main: true),
                    btn('الملف الشخصي والإنجازات', Icons.emoji_events,
                        () => _go(const ProfileScreen())),
                    btn('الإعدادات', Icons.settings,
                        () => _go(const SettingsScreen())),
                    btn('كيف تلعب؟', Icons.help_outline, _howTo),
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
