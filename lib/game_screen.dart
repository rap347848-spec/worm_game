import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'config.dart';
import 'engine.dart';
import 'models.dart';
import 'painters.dart';

class GameScreen extends StatefulWidget {
  final int bots;
  final Difficulty difficulty;
  const GameScreen({super.key, required this.bots, required this.difficulty});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late GameEngine _engine;
  late WorldPainter _painter;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _paused = false;

  Offset? _mapPos;
  Offset? _boardPos;

  int? _pid;
  Offset _anchor = Offset.zero;
  int _lastDownMs = -100000;
  Offset _lastDownPos = Offset.zero;

  static const double _mapSize = 110;
  static const double _boardW = 150;

  @override
  void initState() {
    super.initState();
    _newGame();
    _ticker = createTicker(_onTick)..start();
  }

  void _newGame() {
    _engine = GameEngine(bots: widget.bots, difficulty: widget.difficulty);
    _painter = WorldPainter(_engine);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _engine.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt =
        ((elapsed - _last).inMicroseconds / 1000000.0).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    if (!_paused) _engine.update(dt);
  }

  // ---------------- اللمس: توجيه + ضغطتان للتسريع ----------------

  void _down(PointerDownEvent e) {
    final now = e.timeStamp.inMilliseconds;
    if (now - _lastDownMs < 300 &&
        (e.position - _lastDownPos).distance < 90) {
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
    final d = e.localPosition - _anchor;
    final dist = d.distance;
    if (dist > 6) {
      _engine.steer(math.atan2(d.dy, d.dx));
    }
    if (dist > 28) {
      _anchor = e.localPosition - d / dist * 28;
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer == _pid) _pid = null;
  }

  // ---------------- الواجهة ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        _mapPos ??= const Offset(8, 8);
        _boardPos ??= Offset(size.width - _boardW - 8, 8);

        return Stack(
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

            // رسائل الحالة (موت / خروج)
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

            // شاشة الإيقاف المؤقت
            if (_paused && !_engine.over) _pauseOverlay(),
          ],
        );
      }),
    );
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
    if (!shown.contains(_engine.player)) shown.add(_engine.player);

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
          const Text('الترتيب  (قتل / موت)',
              style: TextStyle(
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
                  Text('${w.kills}/${Cfg.killsToWin} · ${w.deaths}',
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
    if (_engine.over) {
      text = null;
    } else if (p.eliminated) {
      text = 'خرجت من المباراة (${Cfg.maxDeaths} موتات) — تتابع المشاهدة';
    } else if (!p.alive) {
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
    return Positioned.fill(
      child: Container(
        color: const Color(0xAA000000),
        alignment: Alignment.center,
        child: Container(
          width: 340,
          constraints: BoxConstraints(maxHeight: size.height * 0.9),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFF16313F),
              borderRadius: BorderRadius.circular(16)),
          child: child,
        ),
      ),
    );
  }

  Widget _pauseOverlay() {
    return Builder(builder: (context) {
      final size = MediaQuery.of(context).size;
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
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('القائمة الرئيسية'),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _resultOverlay(Size size) {
    final e = _engine;
    final ranking = [...e.worms]..sort((a, b) {
        if (b.kills != a.kills) return b.kills.compareTo(a.kills);
        return a.deaths.compareTo(b.deaths);
      });
    final won = e.winner != null && e.winner!.isPlayer;
    final title = won
        ? '🏆 فزت بالمباراة!'
        : 'انتهت المباراة — الفائز: ${e.winner?.name ?? ''}';

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
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
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
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() {
              _engine.dispose();
              _newGame();
              _paused = false;
            }),
            child: const Text('لعبة جديدة'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('القائمة الرئيسية'),
          ),
        ],
      ),
    );
  }
}
