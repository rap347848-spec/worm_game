import 'package:flutter/material.dart';
import 'config.dart';
import 'engine.dart';
import 'game_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  double _bots = 3;
  Difficulty _diff = Difficulty.medium;

  void _start() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          GameScreen(bots: _bots.round(), difficulty: _diff),
    ));
  }

  void _howTo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('كيف تلعب'),
        content: SingleChildScrollView(
          child: Text(
            '• المس أي مكان بالشاشة وحرّك إصبعك: الدودة تتجه حسب حركة إصبعك.\n'
            '• اضغط ضغطتين سريعتين: تسريع لمدة ${Cfg.boostDuration.round()} ثوانٍ، '
            'ثم انتظار ${Cfg.boostCooldown.round()} ثوانٍ قبل التسريع التالي.\n'
            '• كُل الفواكه لتكبر دودتك.\n'
            '• إذا لمس رأسك جدار الساحة أو جسم دودة أخرى تموت.\n'
            '• الدودة التي تموت تتحول إلى فواكه.\n'
            '• تفوز عندما تقتل ${Cfg.killsToWin} دودات، وتخرج بعد ${Cfg.maxDeaths} موتات.\n'
            '• يمكنك سحب الخريطة المصغرة ولوحة الترتيب لأي مكان.',
            style: const TextStyle(height: 1.6),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: const Color(0x33FFFFFF),
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('عدد البوتات: ${_bots.round()}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16)),
                          Slider(
                            value: _bots,
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '${_bots.round()}',
                            onChanged: (v) => setState(() => _bots = v),
                          ),
                          const SizedBox(height: 6),
                          const Text('مستوى صعوبة البوتات',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              _chip('سهل', Difficulty.easy),
                              _chip('متوسط', Difficulty.medium),
                              _chip('صعب', Difficulty.hard),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _start,
                      child:
                          const Text('ابدأ اللعب', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: _howTo, child: const Text('كيف تلعب؟')),
                    const SizedBox(height: 12),
                    const Text(
                      'اللعب مع أصدقاء عبر البلوتوث والواي فاي قادم في المرحلة الثالثة',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Difficulty d) {
    return ChoiceChip(
      label: Text(text),
      selected: _diff == d,
      onSelected: (_) => setState(() => _diff = d),
    );
  }
}
