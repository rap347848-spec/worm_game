import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> _askName({bool change = false}) async {
    final ctrl = TextEditingController(text: change ? Store.i.profile.name : '');
    await showDialog(
      context: context,
      barrierDismissible: change,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(change ? 'تغيير الاسم' : 'اختر اسم لاعبك'),
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
              const Text('يُحفظ اسمك ولا يُطلب منك كل مرة، ويمكنك تغييره من أيقونة القلم.',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            if (change)
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
            FilledButton(
              onPressed: ctrl.text.trim().isEmpty
                  ? null
                  : () async {
                      Store.i.profile.name = ctrl.text.trim();
                      await Store.i.saveProfile();
                      if (ctx.mounted) Navigator.pop(ctx);
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
            '• كُل الفواكه لتطول دودتك. الفاكهة الذهبية تعطي نمواً أكبر.\n'
            '• القدرات: 🛡️ درع يحميك من موت واحد، 🧲 مغناطيس يجذب الفواكه، ❄️ تجميد يبطّئ من حولك.\n'
            '• إذا لمس رأسك الجدار أو جسم دودة أخرى تموت وتتحول إلى فواكه.\n'
            '• تفوز بقتل 10 دودات، وتخرج بعد 10 موتات.\n'
            '• اسحب الخريطة المصغرة ولوحة الترتيب لأي مكان.\n'
            '• كل فوز يرفع مستواك: 100 مستوى وألقاب وألوان توهج تتغير كل 10 مستويات.',
            style: const TextStyle(height: 1.5),
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
    Widget tile(IconData icon, String title, String sub, Widget page) =>
        ListTile(
          dense: true,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(sub, style: const TextStyle(fontSize: 11)),
          onTap: () {
            Navigator.pop(context);
            _go(page);
          },
        );
    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 420),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('غرفة واي فاي (سريعة وثابتة)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              tile(Icons.wifi, 'استضافة غرفة واي فاي',
                  'نفس الشبكة أو نقطة اتصال هاتفك', const HostLobbyScreen(wifi: true)),
              tile(Icons.wifi_find, 'الانضمام لغرفة واي فاي',
                  'ابحث عن غرف على نفس الشبكة', const JoinScreen(wifi: true)),
              const Divider(),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('غرفة بلوتوث (بدون إنترنت)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              tile(Icons.bluetooth, 'استضافة غرفة بلوتوث',
                  'افتح غرفة ليدخلها أصدقاؤك', const HostLobbyScreen()),
              tile(Icons.bluetooth_searching, 'الانضمام لغرفة بلوتوث',
                  'ابحث عن غرفة قريبة منك', const JoinScreen()),
            ],
          ),
        ),
      ),
    );
  }

  void _exit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خروج من اللعبة'),
        content: const Text('هل تريد إغلاق اللعبة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لا')),
          FilledButton(
              onPressed: () => SystemNavigator.pop(), child: const Text('نعم، خروج')),
        ],
      ),
    );
  }

  Widget _btn(String text, IconData icon, VoidCallback f, {bool main = false}) {
    final label = Text(text, style: const TextStyle(fontSize: 14));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: main
            ? FilledButton.icon(onPressed: f, icon: Icon(icon, size: 18), label: label)
            : OutlinedButton.icon(onPressed: f, icon: Icon(icon, size: 18), label: label),
      ),
    );
  }

  Widget _profileCard() {
    final p = Store.i.profile;
    final lv = p.level;
    final tier = tierOf(lv);
    final gc = kGlowColors[tier];
    return GestureDetector(
      onTap: () => _go(const ProfileScreen()),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gc, width: 2),
          boxShadow: [BoxShadow(color: gc.withAlpha(110), blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(p.name.isEmpty ? '...' : p.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    await _askName(change: true);
                    if (mounted) setState(() {});
                  },
                  child: const Icon(Icons.edit, size: 16, color: Colors.white70),
                ),
              ],
            ),
            Text('${kTitles[tier]} · المستوى $lv · ${p.wins} فوز',
                style: TextStyle(color: gc, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
                value: levelProgress(p.points), minHeight: 5, color: gc),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final left = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('🐍 لعبة الدودة',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _profileCard(),
        const SizedBox(height: 10),
        const Text(Cfg.credit,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
        const Text(Cfg.phone,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );

    final right = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _btn('لعب فردي ضد البوتات', Icons.person, () => _go(const SoloSetupScreen()),
            main: true),
        _btn('لعب جماعي (واي فاي / بلوتوث)', Icons.groups, _multi, main: true),
        _btn('الملف الشخصي والإنجازات', Icons.emoji_events,
            () => _go(const ProfileScreen())),
        _btn('الإعدادات', Icons.settings, () => _go(const SettingsScreen())),
        _btn('كيف تلعب؟', Icons.help_outline, _howTo),
        _btn('خروج من اللعبة', Icons.exit_to_app, _exit),
      ],
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
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: LayoutBuilder(builder: (context, box) {
                  if (box.maxWidth >= 480) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 5, child: left),
                        const SizedBox(width: 16),
                        Expanded(flex: 6, child: right),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [left, const SizedBox(height: 12), right],
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
