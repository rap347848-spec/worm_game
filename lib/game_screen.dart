import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'engine.dart';
import 'models.dart';
import 'net.dart';
import 'painters.dart';
import 'progress.dart';
import 'sfx.dart';

class GameScreen extends StatefulWidget {
  final GameEngine engine;
  final NetHost? host;
  final NetClient? client;
  const GameScreen({super.key, required this.engine, this.host, this.client});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameEngine _engine = widget.engine;
  late final WorldPainter _painter = WorldPainter(_engine);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;
  bool _chatOpen = false;
  bool _lost = false;
  String? _err;

  Offset? _mapPos;
  Offset? _boardPos;

  int? _pid;
  Offset _anchor = Offset.zero;
  int _lastDownMs = -100000;
  Offset _lastDownPos = Offset.zero;
  int _lastEat2 = 0;

  String _flash = '';
  double _flashUntil = 0;

  int _recordedRound = -1;
  MatchReward? _reward;

  static const double _mapSize = 110;
  static const double _boardW = 150;

  @override
  void initState() {
    super.initState();
    _engine.onEvent = _onEvent;

    final host = widget.host;
    if (host != null) {
      _engine.onSnapshot = (m) => host.broadcast(m);
      host.onMessage = (peer, m) {
        if (m['t'] == 'in' || m['t'] == 'chat') _engine.remoteInput(peer, m);
      };
      host.onLeft = (peer) => _engine.humanLeft(peer);
    }
    final client = widget.client;
    if (client != null) {
      _engine.onSend = (m) => client.send(m);
      client.onMessage = (m) {
        final t = m['t'];
        if (t == 'snap') {
          _engine.applySnapshot(m);
        } else if (t == 'start') {
          _engine.applyRoster(
              m['roster'] as List, (m['you'] as num).toInt(), (m['k'] as num).toInt());
        } else if (t == 'bye') {
          _connectionLost();
        }
      };
      client.onDisconnected = _connectionLost;
    }
    _ticker = createTicker(_onTick)..start();
  }

  void _connectionLost() {
    if (!mounted || _lost) return;
    setState(() => _lost = true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _engine.onEvent = null;
    _engine.onSnapshot = null;
    _engine.onSend = null;
    widget.host?.broadcast({'t': 'bye'});
    widget.host?.stop();
    widget.client?.stop();
    _engine.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt =
        ((elapsed - _last).inMicroseconds / 1000000.0).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    try {
      if (!_paused) _engine.update(dt);
      if (_engine.over && _recordedRound != _engine.round) _finish();
    } catch (e) {
      if (_err == null && mounted) setState(() => _err = '$e');
    }
  }

  // ---------------- الأصوات والاهتزاز ----------------

  void _onEvent(String type, Worm w, Worm? other) {
    final s = Store.i.settings;
    switch (type) {
      case 'eat':
        if (w.isPlayer) {
          if (s.eatAll && s.eatMine) Sfx.i.play('eat');
        } else if (s.eatAll && s.eatOthers) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastEat2 > 140 && (w.head - _engine.cam).distance < 28) {
            _lastEat2 = now;
            Sfx.i.play('eat2');
          }
        }
        break;
      case 'kill':
        if (w.isPlayer) {
          if (s.sfxOther) Sfx.i.play('kill');
          if (s.vibration) HapticFeedback.lightImpact();
          _streakFlash(other);
        }
        break;
      case 'death':
        if (w.isPlayer) {
          if (s.sfxOther) Sfx.i.play('death');
          if (s.vibration) HapticFeedback.heavyImpact();
        }
        break;
      case 'power':
        if (w.isPlayer && s.sfxOther) Sfx.i.play('power');
        break;
    }
  }

  void _streakFlash(Worm? victim) {
    final n = _engine.killStreak;
    String t;
    if (n >= 5) {
      t = 'مجزرة! 👑';
    } else if (n == 4) {
      t = 'قتل رباعي! 💥';
    } else if (n == 3) {
      t = 'قتل ثلاثي! 🔥';
    } else if (n == 2) {
      t = 'قتل مزدوج! ⚔️';
    } else {
      t = 'أطحت بـ ${victim?.name ?? 'خصم'}!';
    }
    _flash = t;
    _flashUntil = _engine.time + 2.2;
  }

  // ---------------- نهاية المباراة ----------------

  void _finish() {
    _recordedRound = _engine.round;
    if (_engine.practice) return;
    final me = _engine.player;
    final opp = <String, int>{};
    for (final w in _engine.worms) {
      if (w.human && !identical(w, me)) opp[w.name] = w.level;
    }
    final res = MatchResult(
      won: _engine.winner != null && identical(_engine.winner, me),
      kills: me.kills,
      deaths: me.deaths,
      fruits: _engine.myFruits,
      bestStreak: _engine.bestStreak,
      otherHumans: _engine.otherHumans,
      opponents: opp,
    );
    final rw = Store.i.recordMatch(res);
    if (rw.levelAfter > rw.levelBefore) {
      if (Store.i.settings.sfxOther) Sfx.i.play('level');
      if (Store.i.settings.vibration) HapticFeedback.mediumImpact();
    }
    setState(() => _reward = rw);
  }

  // ---------------- اللمس: توجيه + ضغطتان للتسريع ----------------

  void _down(PointerDownEvent e) {
    final now = e.timeStamp.inMilliseconds;
    if (now - _lastDownMs < 300 && (e.position - _lastDownPos).distance < 90) {
      _engine.boost();
      _lastDownMs = -100000;
    } else {
      _lastDownMs = now;
      _lastDownPos = e.position;
    }
    _pid ??= e.pointer;
    if (_pid == e.pointer) _anchor = e.localPosition;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pid) return;
    final sens = Store.i.settings.sensitivity;
    final d = e.localPosition - _anchor;
    final dist = d.distance;
    if (dist > 6 / sens) {
      _engine.steer(math.atan2(d.dy, d.dx));
    }
    final maxD = 28 / sens;
    if (dist > maxD) {
      _anchor = e.localPosition - d / dist * maxD;
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer == _pid) _pid = null;
  }

  // ---------------- الواجهة ----------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        _mapPos ??= const Offset(8, 8);
        _boardPos ??= Offset(size.width - _boardW - 8, 8);
        final multi = _engine.role != Role.solo;

        return Stack(
          fit: StackFit.expand,
          children: [
            // طبقة اللعب (اللمس في أي مكان)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: CustomPaint(painter: _painter, size: Size.infinite),
              ),
            ),

            // الخريطة المصغرة (قابلة للسحب)
            Positioned(
              left: _mapPos!.dx,
              top: _mapPos!.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => setState(() {
                  _mapPos = _clampPos(_mapPos! + d.delta, size, _mapSize, _mapSize);
                }),
                child: SizedBox(
                  width: _mapSize,
                  height: _mapSize,
                  child: CustomPaint(painter: MiniMapPainter(_engine)),
                ),
              ),
            ),

            // لوحة الترتيب (قابلة للسحب)
            Positioned(
              left: _boardPos!.dx,
              top: _boardPos!.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => setState(() {
                  _boardPos = _clampPos(_boardPos! + d.delta, size, _boardW, 120);
                }),
                child: AnimatedBuilder(
                  animation: _engine,
                  builder: (_, __) => _scoreBoard(),
                ),
              ),
            ),

            // زر الإيقاف المؤقت
            Positioned(
              top: 6,
              left: size.width / 2 - 20,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _paused = true),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      color: Color(0x66000000), shape: BoxShape.circle),
                  child: const Icon(Icons.pause, color: Colors.white),
                ),
              ),
            ),

            // الرسائل السريعة (في اللعب الجماعي فقط)
            if (multi)
              Positioned(
                bottom: 8,
                left: size.width / 2 - 20,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _chatOpen = !_chatOpen),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                        color: Color(0x66000000), shape: BoxShape.circle),
                    child: const Icon(Icons.chat_bubble_outline,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
            if (multi && _chatOpen)
              Positioned(
                bottom: 54,
                left: 40,
                right: 40,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(14)),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        for (int i = 0; i < kChat.length; i++)
                          ActionChip(
                            label: Text(kChat[i]),
                            onPressed: () {
                              _engine.sayLocal(i);
                              setState(() => _chatOpen = false);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // رسائل الحالة (موت / خروج / سلسلة قتل)
            Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _engine,
                  builder: (_, __) => _statusBanner(),
                ),
              ),
            ),

            // شاشة النتيجة
            AnimatedBuilder(
              animation: _engine,
              builder: (_, __) =>
                  _engine.over ? _resultOverlay(size) : const SizedBox.shrink(),
            ),

            if (_paused && !_engine.over) _pauseOverlay(size),
            if (_lost) _lostOverlay(size),
            Positioned(
              bottom: 2,
              right: 6,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _engine,
                  builder: (_, __) => Text(
                    'دودات ${_engine.worms.length} · فواكه ${_engine.fruits.length} · ث ${_engine.time.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ),
              ),
            ),
            if (_err != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xDD000000),
                    padding: const EdgeInsets.all(8),
                    child: Text('خطأ: $_err',
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                  ),
                ),
              ),
          ],
        );
      }),
    ));
  }

  Offset _clampPos(Offset p, Size size, double w, double h) {
    return Offset(
      p.dx.clamp(0.0, math.max(0.0, size.width - w)).toDouble(),
      p.dy.clamp(0.0, math.max(0.0, size.height - h)).toDouble(),
    );
  }

  Widget _scoreBoard() {
    final sorted = [..._engine.worms]..sort((a, b) {
        if (b.kills != a.kills) return b.kills.compareTo(a.kills);
        return a.deaths.compareTo(b.deaths);
      });
    final shown = sorted.take(6).toList();
    final me = _engine.player;
    if (!shown.contains(me) && _engine.worms.contains(me)) shown.add(me);

    return Container(
      width: _boardW,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x73000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الترتيب  (من ${_engine.killsToWin} قتلات)',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          for (final w in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: w.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 1)),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      w.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: w.isPlayer
                              ? const Color(0xFFFFEE58)
                              : Colors.white,
                          fontSize: 11,
                          decoration: w.eliminated
                              ? TextDecoration.lineThrough
                              : TextDecoration.none),
                    ),
                  ),
                  Text('${w.kills} · ☠${w.deaths}',
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    final p = _engine.player;
    String? text;
    if (_engine.time < _flashUntil) {
      text = _flash;
    } else if (_engine.over) {
      text = null;
    } else if (p.eliminated) {
      text = 'خرجت من المباراة (${_engine.maxDeaths} موتات) — تتابع المشاهدة';
    } else if (!p.alive && _engine.worms.contains(p)) {
      text = 'ستعود خلال ${p.respawnTimer.ceil().clamp(1, 9)} ثانية';
    }
    if (text == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }

  Widget _dialog(Size size, Widget child) {
    return SizedBox.expand(
      child: Container(
        color: const Color(0xAA000000),
        alignment: Alignment.center,
        child: Container(
          width: 320,
          constraints: BoxConstraints(maxHeight: size.height * 0.92),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFF16313F),
              borderRadius: BorderRadius.circular(16)),
          child: child,
        ),
      ),
    );
  }

  void _toMenu() => Navigator.of(context).popUntil((r) => r.isFirst);

  Widget _pauseOverlay(Size size) {
    return _dialog(
      size,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('إيقاف مؤقت',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          if (_engine.role != Role.solo)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('في اللعب الجماعي تستمر المباراة عند الآخرين',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _paused = false),
              child: const Text('متابعة'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _toMenu,
              child: const Text('القائمة الرئيسية'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lostOverlay(Size size) {
    return _dialog(
      size,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('انقطع الاتصال بالمضيف',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _toMenu, child: const Text('القائمة الرئيسية')),
        ],
      ),
    );
  }

  Widget _resultOverlay(Size size) {
    final e = _engine;
    final ranking = [...e.worms]..sort((a, b) {
        if (b.kills != a.kills) return b.kills.compareTo(a.kills);
        return a.deaths.compareTo(b.deaths);
      });
    final won = e.winner != null && identical(e.winner, e.player);
    final title = won
        ? '🏆 فزت بالمباراة!'
        : 'انتهت المباراة — الفائز: ${e.winner?.name ?? ''}';
    final rw = _reward;

    return _dialog(
      size,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (e.practice)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('وضع التدريب: لا يؤثر على مستواك',
                          style: TextStyle(color: Colors.white60, fontSize: 12)),
                    ),
                  if (rw != null) _rewardBox(rw),
                  _awards(ranking),
                  for (int i = 0; i < ranking.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text('${i + 1}',
                                style: const TextStyle(color: Colors.white70)),
                          ),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: ranking[i].color,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white54, width: 1)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ranking[i].name,
                              style: TextStyle(
                                  color: ranking[i].isPlayer
                                      ? const Color(0xFFFFEE58)
                                      : Colors.white),
                            ),
                          ),
                          Text(
                              'قتل ${ranking[i].kills}  ·  موت ${ranking[i].deaths}',
                              style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (e.role == Role.client)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('بانتظار المضيف لبدء جولة جديدة...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70)),
            )
          else
            FilledButton(
              onPressed: () => setState(() {
                e.reset();
                _reward = null;
                _paused = false;
              }),
              child: const Text('جولة جديدة'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _toMenu,
            child: const Text('القائمة الرئيسية'),
          ),
        ],
      ),
    );
  }

  /// جوائز ما بعد المباراة.
  Widget _awards(List<Worm> ranking) {
    if (ranking.isEmpty) return const SizedBox.shrink();
    Worm topKiller = ranking.first;
    Worm longest = ranking.first;
    for (final w in ranking) {
      if (w.kills > topKiller.kills) topKiller = w;
      if (w.eaten > longest.eaten) longest = w;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: const Color(0x22FFFFFF), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text('⚔️ أكثر قتلاً: ${topKiller.name} (${topKiller.kills})',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          Text('📏 الأطول دودة: ${longest.name}',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          Text('🍎 فواكهك: ${_engine.myFruits}',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _rewardBox(MatchReward rw) {
    final up = rw.levelAfter > rw.levelBefore;
    final tier = tierOf(rw.levelAfter);
    final gc = kGlowColors[tier];
    final lines = <String>[
      '+${(rw.gained + rw.bonus).toStringAsFixed(1)} نقطة',
      for (final m in rw.missions) '✅ مهمة منجزة: $m',
      for (final a in rw.achievements) '🏅 إنجاز جديد: $a',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: up ? Border.all(color: gc, width: 2) : null,
        boxShadow: up ? [BoxShadow(color: gc.withAlpha(150), blurRadius: 16)] : null,
      ),
      child: Column(
        children: [
          if (up) ...[
            const Text('⬆️ ارتقيت!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text('المستوى ${rw.levelAfter} — ${kTitles[tier]}',
                style: TextStyle(
                    color: gc, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
          ],
          for (final l in lines)
            Text(l, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }
}
