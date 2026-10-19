import 'package:flutter/material.dart';
import 'config.dart';
import 'engine.dart';
import 'game_screen.dart';
import 'models.dart';
import 'net.dart';
import 'progress.dart';

class MatchOptions {
  int bots = 3;
  Difficulty diff = Difficulty.auto;
  int mode = 0; // 0 عادية (10 قتلات) · 1 سريعة (5 قتلات) · 2 تدريب
}

Widget _bg({required Widget child}) => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B2A3A), Color(0xFF16526B)],
        ),
      ),
      child: SafeArea(child: child),
    );

Widget _card({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(16)),
      child: child,
    );

const TextStyle _label = TextStyle(color: Colors.white, fontSize: 16);

/// لوحة خيارات المباراة (تُستخدم في الفردي والاستضافة).
Widget optionsPanel(
  MatchOptions o, {
  required int minBots,
  required int maxBots,
  required bool allowPractice,
  required VoidCallback refresh,
}) {
  if (o.bots < minBots) o.bots = minBots;
  if (o.bots > maxBots) o.bots = maxBots;
  if (!allowPractice && o.mode == 2) o.mode = 0;

  Widget chip(String text, bool sel, VoidCallback onTap) => ChoiceChip(
        label: Text(text),
        selected: sel,
        onSelected: (_) {
          onTap();
          refresh();
        },
      );

  return _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('عدد البوتات: ${o.bots}', style: _label),
        if (maxBots > minBots)
          Slider(
            value: o.bots.toDouble(),
            min: minBots.toDouble(),
            max: maxBots.toDouble(),
            divisions: maxBots - minBots,
            label: '${o.bots}',
            onChanged: (v) {
              o.bots = v.round();
              refresh();
            },
          ),
        const SizedBox(height: 6),
        const Text('صعوبة البوتات', style: _label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            chip('تلقائي (حسب مستواك)', o.diff == Difficulty.auto,
                () => o.diff = Difficulty.auto),
            chip('سهل', o.diff == Difficulty.easy, () => o.diff = Difficulty.easy),
            chip('متوسط', o.diff == Difficulty.medium,
                () => o.diff = Difficulty.medium),
            chip('صعب', o.diff == Difficulty.hard, () => o.diff = Difficulty.hard),
          ],
        ),
        const SizedBox(height: 10),
        const Text('نوع المباراة', style: _label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            chip('عادية (10 قتلات)', o.mode == 0, () => o.mode = 0),
            chip('سريعة (5 قتلات)', o.mode == 1, () => o.mode = 1),
            if (allowPractice)
              chip('تدريب (لا يؤثر على مستواك)', o.mode == 2, () => o.mode = 2),
          ],
        ),
      ],
    ),
  );
}

// ============================================================
// لعب فردي
// ============================================================

class SoloSetupScreen extends StatefulWidget {
  const SoloSetupScreen({super.key});

  @override
  State<SoloSetupScreen> createState() => _SoloSetupScreenState();
}

class _SoloSetupScreenState extends State<SoloSetupScreen> {
  final MatchOptions _o = MatchOptions();

  void _start() {
    final p = Store.i.profile;
    final e = GameEngine(
      role: Role.solo,
      bots: _o.bots,
      difficulty: _o.diff,
      localName: p.name,
      localLevel: p.level,
      kills: _o.mode == 1 ? 5 : 10,
      practice: _o.mode == 2,
    );
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(engine: e)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لعب فردي'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: _bg(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  optionsPanel(_o,
                      minBots: 1,
                      maxBots: Cfg.maxWorms - 1,
                      allowPractice: true,
                      refresh: () => setState(() {})),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _start,
                      child: const Text('ابدأ المباراة',
                          style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// استضافة غرفة (بلوتوث / واي فاي)
// ============================================================

class HostLobbyScreen extends StatefulWidget {
  const HostLobbyScreen({super.key});

  @override
  State<HostLobbyScreen> createState() => _HostLobbyScreenState();
}

class _HostLobbyScreenState extends State<HostLobbyScreen> {
  final MatchOptions _o = MatchOptions()..bots = 0;
  NetHost? _host;
  String? _error;
  bool _started = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final p = Store.i.profile;
    final ok = await ensureNearbyPermissions();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error =
          'لم تُمنح الأذونات المطلوبة (الموقع والبلوتوث). فعّلها من إعدادات الهاتف ثم أعد المحاولة.');
      return;
    }
    final h = NetHost(p.name, p.level);
    h.onChanged = () {
      if (mounted) setState(() {});
    };
    _host = h;
    final started = await h.start();
    if (!mounted) return;
    setState(() {
      _ready = started;
      if (!started) {
        _error =
            'تعذّر بدء الاستضافة. تأكد من تشغيل البلوتوث وخدمة الموقع ثم أعد المحاولة.';
      }
    });
  }

  @override
  void dispose() {
    if (!_started) _host?.stop();
    super.dispose();
  }

  void _start() {
    final h = _host;
    if (h == null) return;
    final peers = h.ready;
    if (peers.isEmpty) return;
    final p = Store.i.profile;
    final e = GameEngine(
      role: Role.host,
      bots: _o.bots,
      difficulty: _o.diff,
      localName: p.name,
      localLevel: p.level,
      humans: [for (final x in peers) HumanSeed(x.endpoint, x.name, x.level)],
      kills: _o.mode == 1 ? 5 : 10,
    );
    for (final x in peers) {
      Worm? me;
      for (final w in e.worms) {
        if (w.peer == x.endpoint) me = w;
      }
      if (me == null) continue;
      h.send(x.endpoint, {
        't': 'start',
        'you': me.id,
        'roster': e.roster(),
        'k': e.killsToWin,
      });
    }
    _started = true;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(engine: e, host: h)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Store.i.profile;
    final peers = _host?.ready ?? <PeerInfo>[];
    final maxBots = Cfg.maxWorms - 1 - peers.length;

    return Scaffold(
      appBar: AppBar(title: const Text('استضافة غرفة'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: _bg(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  if (_error != null)
                    _card(
                      child: Column(
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed: () {
                                setState(() => _error = null);
                                _init();
                              },
                              child: const Text('إعادة المحاولة')),
                        ],
                      ),
                    )
                  else ...[
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              _ready
                                  ? 'الغرفة مفتوحة باسم "${p.name}" — اطلب من أصدقائك اختيار "الانضمام لغرفة"'
                                  : 'جارٍ فتح الغرفة...',
                              style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 10),
                          Text('اللاعبون (${peers.length + 1})', style: _label),
                          const SizedBox(height: 4),
                          Text('• ${p.name} (أنت) — مستوى ${p.level}',
                              style: const TextStyle(color: Colors.white)),
                          for (final x in peers)
                            Text('• ${x.name} — مستوى ${x.level}',
                                style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    optionsPanel(_o,
                        minBots: 0,
                        maxBots: maxBots < 0 ? 0 : maxBots,
                        allowPractice: false,
                        refresh: () => setState(() {})),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: peers.isEmpty ? null : _start,
                        child: Text(
                            peers.isEmpty
                                ? 'بانتظار انضمام لاعبين...'
                                : 'ابدأ المباراة',
                            style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// الانضمام لغرفة
// ============================================================

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  NetClient? _c;
  GameEngine? _eng;
  String? _error;
  String _status = 'جارٍ البحث عن غرف قريبة...';
  bool _connecting = false;
  bool _started = false;
  List<dynamic> _lobby = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final p = Store.i.profile;
    final ok = await ensureNearbyPermissions();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error =
          'لم تُمنح الأذونات المطلوبة (الموقع والبلوتوث). فعّلها من إعدادات الهاتف ثم أعد المحاولة.');
      return;
    }
    final c = NetClient(p.name, p.level);
    c.onHostsChanged = () {
      if (mounted) setState(() {});
    };
    c.onConnected = () {
      if (mounted) {
        setState(() {
          _connecting = false;
          _status = 'تم الاتصال — بانتظار بدء المضيف للمباراة...';
        });
      }
    };
    c.onDisconnected = () {
      if (mounted && !_started) {
        setState(() {
          _connecting = false;
          _lobby = [];
          _status = 'تعذّر الاتصال أو انقطع. اختر غرفة من جديد.';
        });
      }
    };
    c.onMessage = _onMessage;
    _c = c;
    final started = await c.startDiscovery();
    if (!mounted) return;
    setState(() {
      if (!started) {
        _error =
            'تعذّر البحث عن الغرف. تأكد من تشغيل البلوتوث وخدمة الموقع ثم أعد المحاولة.';
      }
    });
  }

  void _onMessage(Map<String, dynamic> m) {
    final t = m['t'];
    if (t == 'lobby') {
      if (mounted) setState(() => _lobby = m['p'] as List);
    } else if (t == 'start') {
      final e = GameEngine.client(myId: (m['you'] as num).toInt());
      e.applyRoster(
          m['roster'] as List, (m['you'] as num).toInt(), (m['k'] as num).toInt());
      _eng = e;
      _started = true;
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => GameScreen(engine: e, client: _c)));
      }
    } else if (t == 'snap') {
      _eng?.applySnapshot(m);
    } else if (t == 'bye') {
      if (mounted && !_started) {
        setState(() {
          _lobby = [];
          _status = 'أغلق المضيف الغرفة.';
        });
      }
    }
  }

  @override
  void dispose() {
    if (!_started) _c?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final hosts = c?.hosts.entries.toList() ?? [];
    final connected = c?.connected ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('الانضمام لغرفة'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: _bg(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _error != null
                  ? _card(
                      child: Column(
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed: () {
                                setState(() => _error = null);
                                _init();
                              },
                              child: const Text('إعادة المحاولة')),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        _card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_status,
                                  style: const TextStyle(color: Colors.white70)),
                              if (connected && _lobby.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text('اللاعبون (${_lobby.length})', style: _label),
                                for (final p in _lobby)
                                  Text('• ${p[0]} — مستوى ${p[1]}',
                                      style: const TextStyle(color: Colors.white)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!connected)
                          _card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('الغرف القريبة', style: _label),
                                const SizedBox(height: 6),
                                if (hosts.isEmpty)
                                  const Text(
                                      'لا توجد غرف بعد. اطلب من المضيف فتح "استضافة غرفة".',
                                      style: TextStyle(color: Colors.white60)),
                                for (final h in hosts)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.wifi_tethering,
                                        color: Colors.white),
                                    title: Text('غرفة ${h.value}',
                                        style: const TextStyle(color: Colors.white)),
                                    trailing: FilledButton(
                                      onPressed: _connecting
                                          ? null
                                          : () {
                                              setState(() {
                                                _connecting = true;
                                                _status = 'جارٍ الاتصال...';
                                              });
                                              _c?.connect(h.key);
                                            },
                                      child: const Text('انضمام'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
