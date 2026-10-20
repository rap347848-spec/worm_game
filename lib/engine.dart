import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'config.dart';
import 'models.dart';

enum Difficulty { auto, easy, medium, hard }

enum Role { solo, host, client }

class HumanSeed {
  final String peer;
  final String name;
  final int level;
  const HumanSeed(this.peer, this.name, this.level);
}

class _Bp {
  final double look;
  final double reaction;
  final double hunt;
  final double fruitRange;
  final double boostChance;
  final double turnMul;
  const _Bp({
    required this.look,
    required this.reaction,
    required this.hunt,
    required this.fruitRange,
    required this.boostChance,
    required this.turnMul,
  });
}

/// ذكاء البوتات يتدرج من 0 (سهل) إلى 1 (صعب).
_Bp _bpFor(double t) => _Bp(
      look: 6 + 7 * t,
      reaction: 0.35 - 0.25 * t,
      hunt: 0.6 * t,
      fruitRange: 22 + 33 * t,
      boostChance: 0.04 * t,
      turnMul: 0.8 + 0.35 * t,
    );

class _Death {
  final Worm w;
  final Worm? killer;
  _Death(this.w, this.killer);
}

double angDiff(double a, double b) {
  double d = (a - b) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  if (d < -math.pi) d += 2 * math.pi;
  return d;
}

double angNorm(double a) {
  a = a % (2 * math.pi);
  if (a > math.pi) a -= 2 * math.pi;
  return a;
}

/// ألوان الدودات: لا يوجد أزرق ولا سماوي حتى لا تختفي على أرض الساحة.
const List<Color> kWormColors = [
  Color(0xFFE53935), // أحمر
  Color(0xFFFB8C00), // برتقالي
  Color(0xFFFDD835), // أصفر
  Color(0xFF2E7D32), // أخضر غامق
  Color(0xFF8E24AA), // بنفسجي
  Color(0xFFEC407A), // وردي
  Color(0xFF6D4C41), // بني
  Color(0xFF212121), // أسود
  Color(0xFFF5F5F5), // أبيض
  Color(0xFF9E9D24), // زيتي
  Color(0xFF757575), // رمادي
];

const List<String> kBotNames = [
  'صقر', 'نمر', 'ذئب', 'فهد', 'أسد', 'عنتر',
  'شبح', 'برق', 'رعد', 'نسر', 'ظل', 'قيس',
];

typedef GameEventCb = void Function(String type, Worm w, Worm? other);

class GameEngine extends ChangeNotifier {
  final math.Random rng = math.Random();
  final Role role;
  final bool practice;
  int killsToWin;
  int maxDeaths;
  int myId = 0;

  final List<Worm> worms = <Worm>[];
  final List<Fruit> fruits = <Fruit>[];
  final List<PowerUp> powerUps = <PowerUp>[];

  _Bp _bp = _bpFor(0.5);
  final Worm _dummy = Worm(
      id: -1,
      name: '',
      color: const Color(0xFF000000),
      colorIdx: 0,
      pattern: 0);

  bool over = false;
  Worm? winner;
  int round = 0;
  double time = 0;
  Offset cam = const Offset(Cfg.arena / 2, Cfg.arena / 2);
  Offset? lastDeathPos;

  // إحصاءات اللاعب المحلي للمباراة الحالية
  int myFruits = 0;
  int bestStreak = 0;
  final List<double> _killTimes = <double>[];

  // ربط خارجي
  GameEventCb? onEvent;
  void Function(Map<String, dynamic>)? onSnapshot;
  void Function(Map<String, dynamic>)? onSend;

  final List<List<dynamic>> _pending = <List<dynamic>>[];
  double _snapAcc = 0;
  double _fruitAcc = 99;
  double snapHz = Cfg.snapshotHz;
  double _powerTimer = 8;
  double _goldTimer = 15;
  double _lastSendT = -1;
  double _lastSentAngle = 0;

  /// ---------------- الإنشاء ----------------

  /// لعب فردي أو مضيف (يشغّل المحاكاة كاملة).
  GameEngine({
    required this.role,
    int bots = 0,
    Difficulty difficulty = Difficulty.auto,
    String localName = 'أنت',
    int localLevel = 1,
    List<HumanSeed> humans = const <HumanSeed>[],
    int kills = 10,
    this.practice = false,
  })  : killsToWin = kills,
        maxDeaths = kills {
    double t;
    switch (difficulty) {
      case Difficulty.easy:
        t = 0.0;
        break;
      case Difficulty.medium:
        t = 0.5;
        break;
      case Difficulty.hard:
        t = 1.0;
        break;
      default:
        t = (localLevel / 100.0).clamp(0.0, 1.0).toDouble();
    }
    _bp = _bpFor(t);

    final colors = List<int>.generate(kWormColors.length, (i) => i)
      ..shuffle(rng);
    final patterns = List<int>.generate(11, (i) => i)..shuffle(rng);
    final names = List<String>.from(kBotNames)..shuffle(rng);

    int ci = 0;
    Worm make(int id, String name, int level, bool human, String? peer) {
      final c = colors[ci % colors.length];
      final p = patterns[ci % patterns.length];
      ci++;
      return Worm(
        id: id,
        name: name,
        color: kWormColors[c],
        colorIdx: c,
        pattern: p,
        isPlayer: id == 0,
        human: human,
        peer: peer,
        level: level,
      );
    }

    worms.add(make(0, localName, localLevel, true, null));
    for (int i = 0; i < humans.length; i++) {
      worms.add(make(1 + i, humans[i].name, humans[i].level, true, humans[i].peer));
    }
    for (int i = 0; i < bots; i++) {
      int lvl;
      if (difficulty == Difficulty.auto) {
        lvl = localLevel + rng.nextInt(17) - 8;
      } else {
        lvl = (t * 100).round() + rng.nextInt(11) - 5;
      }
      lvl = math.max(1, math.min(100, lvl));
      worms.add(make(1 + humans.length + i, names[i % names.length], lvl, false, null));
    }

    for (final w in worms) {
      final p = _freeSpot(minDist: 28);
      w.spawn(p, _headingToCenter(p));
    }
    cam = worms.first.head;
    while (fruits.length < Cfg.fruitCount) {
      _addFruit();
    }
  }

  /// نسخة العميل: تعرض ما يرسله المضيف فقط.
  GameEngine.client({required this.myId})
      : role = Role.client,
        practice = false,
        killsToWin = 10,
        maxDeaths = 10;

  Worm get player {
    for (final w in worms) {
      if (w.id == myId) return w;
    }
    return _dummy;
  }

  int get otherHumans {
    int n = 0;
    for (final w in worms) {
      if (w.human && w.id != myId) n++;
    }
    return n;
  }

  int get killStreak => _killTimes.length;

  List<List<dynamic>> roster() => [
        for (final w in worms)
          [w.id, w.name, w.colorIdx, w.pattern, w.level, w.human ? 1 : 0]
      ];

  // ---------------- مدخلات اللاعب ----------------

  void steer(double angle) {
    if (!player.alive) return;
    player.target = angle;
    if (role == Role.client) {
      if (time - _lastSendT > 0.04 &&
          angDiff(angle, _lastSentAngle).abs() > 0.03) {
        _lastSendT = time;
        _lastSentAngle = angle;
        onSend?.call({'t': 'in', 'a': (angNorm(angle) * 100).round(), 'b': 0});
      }
    }
  }

  void boost() {
    if (!player.alive) return;
    if (role == Role.client) {
      onSend?.call({
        't': 'in',
        'a': (angNorm(player.target) * 100).round(),
        'b': 1
      });
    } else {
      _boostWorm(player);
    }
  }

  void _boostWorm(Worm w) {
    if (w.boostTimer <= 0 && w.boostCooldown <= 0) {
      w.boostTimer = Cfg.boostDuration;
    }
  }

  void say(Worm w, int idx) {
    w.chat = kChat[idx % kChat.length];
    w.chatTimer = 3.5;
  }

  void sayLocal(int idx) {
    if (role == Role.client) {
      onSend?.call({'t': 'chat', 'm': idx});
    } else {
      say(player, idx);
    }
  }

  /// المضيف: استقبال حركة لاعب بعيد.
  void remoteInput(String peer, Map<String, dynamic> m) {
    for (final w in worms) {
      if (w.peer != peer || !w.human) continue;
      if (m['t'] == 'chat') {
        say(w, (m['m'] as num).toInt());
      } else if (w.alive) {
        w.target = (m['a'] as num) / 100.0;
        if (m['b'] == 1) _boostWorm(w);
      }
    }
  }

  /// انقطع لاعب: يستلمه بوت.
  void humanLeft(String peer) {
    for (final w in worms) {
      if (w.peer == peer) {
        w.human = false;
        w.peer = null;
      }
    }
    notifyListeners();
  }

  /// جولة جديدة بنفس اللاعبين.
  void reset() {
    round++;
    over = false;
    winner = null;
    fruits.clear();
    powerUps.clear();
    myFruits = 0;
    bestStreak = 0;
    _killTimes.clear();
    _pending.clear();
    for (final w in worms) {
      w.kills = 0;
      w.deaths = 0;
      w.eliminated = false;
      w.alive = false;
      w.chatTimer = 0;
    }
    for (final w in worms) {
      final p = _freeSpot(minDist: 28);
      w.spawn(p, _headingToCenter(p));
    }
    while (fruits.length < Cfg.fruitCount) {
      _addFruit();
    }
    _powerTimer = 8;
    _goldTimer = 15;
    _fruitAcc = 99;
    notifyListeners();
  }

  // ---------------- الحلقة الرئيسية ----------------

  void update(double dt) {
    time += dt;
    for (final w in worms) {
      if (w.chatTimer > 0) w.chatTimer -= dt;
    }
    if (role == Role.client) {
      _clientSmooth(dt);
      _updateCamera(dt);
      notifyListeners();
      return;
    }

    if (!over) {
      for (final w in worms) {
        if (w.eliminated) continue;
        if (!w.alive) {
          w.respawnTimer -= dt;
          if (w.respawnTimer <= 0) {
            _respawn(w);
            _emit('respawn', w);
          }
          continue;
        }
        if (w.invincible > 0) w.invincible -= dt;
        if (w.shield > 0) w.shield -= dt;
        if (w.freeze > 0) w.freeze -= dt;

        if (w.magnet > 0) {
          w.magnet -= dt;
          for (final f in fruits) {
            final dx = w.head.dx - f.pos.dx;
            final dy = w.head.dy - f.pos.dy;
            final d2 = dx * dx + dy * dy;
            if (d2 < Cfg.magnetRadius * Cfg.magnetRadius && d2 > 0.01) {
              final d = math.sqrt(d2);
              final mv = math.min(d, Cfg.magnetPull * dt);
              f.pos = Offset(f.pos.dx + dx / d * mv, f.pos.dy + dy / d * mv);
            }
          }
        }

        if (w.boostTimer > 0) {
          w.boostTimer -= dt;
          if (w.boostTimer <= 0) {
            w.boostTimer = 0;
            w.boostCooldown = Cfg.boostCooldown;
          }
        } else if (w.boostCooldown > 0) {
          w.boostCooldown -= dt;
        }

        if (!w.human) _think(w, dt);

        final diff = angDiff(w.target, w.heading);
        final maxTurn = Cfg.turnRate * dt * (w.human ? 1.0 : _bp.turnMul);
        w.heading += math.max(-maxTurn, math.min(maxTurn, diff));
        double sp = Cfg.speed * (w.boosting ? Cfg.boostMult : 1.0);
        if (w.freeze > 0) sp *= Cfg.freezeSlow;
        w.advance(dt, sp);
      }

      _eat();
      _collisions();
      _spawnFruits();
      _spawnSpecials(dt);
    }
    _updateCamera(dt);

    if (role == Role.host && onSnapshot != null) {
      _snapAcc += dt;
      _fruitAcc += dt;
      if (_snapAcc >= 1.0 / snapHz) {
        _snapAcc = 0;
        onSnapshot!(snapshot());
        _pending.clear();
      }
    }
    notifyListeners();
  }

  // ---------------- الأحداث ----------------

  void _emit(String type, Worm w, [Worm? other]) {
    _track(type, w);
    onEvent?.call(type, w, other);
    if (role == Role.host && _pending.length < 40) {
      _pending.add([type, w.id, other?.id ?? -1]);
    }
  }

  void _track(String type, Worm w) {
    if (!w.isPlayer) return;
    if (type == 'eat') myFruits++;
    if (type == 'kill') {
      _killTimes.add(time);
      _killTimes.removeWhere((t) => time - t > 6);
      if (_killTimes.length > bestStreak) bestStreak = _killTimes.length;
    }
  }

  Worm? _byId(int id) {
    for (final w in worms) {
      if (w.id == id) return w;
    }
    return null;
  }

  // ---------------- الفواكه والقدرات ----------------

  Offset _randPos([double margin = 4]) => Offset(
        margin + rng.nextDouble() * (Cfg.arena - 2 * margin),
        margin + rng.nextDouble() * (Cfg.arena - 2 * margin),
      );

  void _addFruit() {
    fruits.add(Fruit(_randPos(3), rng.nextInt(5)));
  }

  void _spawnFruits() {
    int guard = 0;
    while (fruits.length < Cfg.fruitCount && guard < 5) {
      _addFruit();
      guard++;
    }
  }

  void _spawnSpecials(double dt) {
    _powerTimer -= dt;
    if (_powerTimer <= 0) {
      _powerTimer = 10 + rng.nextDouble() * 6;
      if (powerUps.length < Cfg.maxPowerUps) {
        powerUps.add(PowerUp(_randPos(6), rng.nextInt(3)));
      }
    }
    _goldTimer -= dt;
    if (_goldTimer <= 0) {
      _goldTimer = 20 + rng.nextDouble() * 10;
      bool has = false;
      for (final f in fruits) {
        if (f.type == 5) has = true;
      }
      if (!has) fruits.add(Fruit(_randPos(6), 5, Cfg.goldenValue));
    }
  }

  void _eat() {
    for (final w in worms) {
      if (!w.alive) continue;
      final thr = w.width / 2 + Cfg.fruitRadius + 0.6;
      final thr2 = thr * thr;
      for (int i = fruits.length - 1; i >= 0; i--) {
        final dx = w.head.dx - fruits[i].pos.dx;
        final dy = w.head.dy - fruits[i].pos.dy;
        if (dx * dx + dy * dy < thr2) {
          w.eaten += fruits[i].value;
          fruits.removeAt(i);
          _emit('eat', w);
        }
      }
      final pthr = w.width / 2 + 2.2;
      for (int i = powerUps.length - 1; i >= 0; i--) {
        if ((w.head - powerUps[i].pos).distance < pthr) {
          _applyPower(w, powerUps[i].type);
          powerUps.removeAt(i);
          _emit('power', w);
        }
      }
    }
  }

  void _applyPower(Worm w, int type) {
    if (type == 0) {
      w.shield = Cfg.shieldTime;
    } else if (type == 1) {
      w.magnet = Cfg.magnetTime;
    } else {
      for (final o in worms) {
        if (identical(o, w) || !o.alive) continue;
        if ((o.head - w.head).distance < Cfg.freezeRadius) {
          o.freeze = Cfg.freezeTime;
        }
      }
    }
  }

  // ---------------- التصادم والموت ----------------

  void _collisions() {
    final deaths = <_Death>[];
    for (final a in worms) {
      if (!a.alive || a.invincible > 0) continue;
      final r = a.width / 2;
      final hx = a.head.dx;
      final hy = a.head.dy;

      if (hx - r < 0 || hy - r < 0 || hx + r > Cfg.arena || hy + r > Cfg.arena) {
        deaths.add(_Death(a, null));
        continue;
      }

      bool hit = false;
      Worm? hitBy;
      for (final b in worms) {
        if (identical(a, b) || !b.alive) continue;
        final lim = (r + b.width / 2) * 0.85;
        final lim2 = lim * lim;

        final hdx = hx - b.head.dx;
        final hdy = hy - b.head.dy;
        if (hdx * hdx + hdy * hdy < lim2) {
          hit = true;
          hitBy = b.invincible > 0 ? b : null; // رأس برأس: يموتان
          break;
        }
        final tr = b.trail;
        for (int i = 0; i < tr.length; i++) {
          final dx = hx - tr[i].dx;
          final dy = hy - tr[i].dy;
          if (dx * dx + dy * dy < lim2) {
            hit = true;
            hitBy = b;
            break;
          }
        }
        if (hit) break;
      }
      if (hit) deaths.add(_Death(a, hitBy));
    }

    for (final d in deaths) {
      final v = d.w;
      if (!v.alive) continue;
      if (v.shield > 0) {
        // الدرع يحمي من موت واحد
        v.shield = 0;
        v.invincible = 1.5;
        _bounce(v);
        continue;
      }
      _kill(v, d.killer);
    }
    if (deaths.isNotEmpty) _checkEnd();
  }

  void _bounce(Worm w) {
    w.head = Offset(
      w.head.dx.clamp(3.0, Cfg.arena - 3.0).toDouble(),
      w.head.dy.clamp(3.0, Cfg.arena - 3.0).toDouble(),
    );
    final a = _headingToCenter(w.head);
    w.heading = a;
    w.target = a;
  }

  void _kill(Worm w, Worm? killer) {
    w.alive = false;
    w.deaths++;
    _dropFruits(w);
    if (w.isPlayer) lastDeathPos = w.head;
    if (killer != null && !identical(killer, w)) killer.kills++;
    if (w.deaths >= maxDeaths) {
      w.eliminated = true;
    } else {
      w.respawnTimer = Cfg.respawnDelay;
    }
    _emit('death', w);
    if (killer != null && !identical(killer, w)) _emit('kill', killer, w);
  }

  /// الدودة الميتة تتحول إلى فواكه بطول جسمها.
  void _dropFruits(Worm w) {
    if (fruits.length > 300) return;
    final n = math.min(40, math.max(5, (w.length / 1.4).round()));
    final step = math.max(1, (w.trail.length / n).floor());
    for (int i = w.trail.length - 1; i >= 0; i -= step) {
      final p = w.trail[i] +
          Offset((rng.nextDouble() - 0.5) * 1.0, (rng.nextDouble() - 0.5) * 1.0);
      fruits.add(Fruit(
        Offset(p.dx.clamp(1.5, Cfg.arena - 1.5).toDouble(),
            p.dy.clamp(1.5, Cfg.arena - 1.5).toDouble()),
        rng.nextInt(5),
      ));
    }
  }

  void _respawn(Worm w) {
    final p = _freeSpot(minDist: 18);
    w.spawn(p, _headingToCenter(p));
  }

  void _checkEnd() {
    Worm? best;
    for (final w in worms) {
      if (w.kills >= killsToWin) {
        if (best == null || w.kills > best.kills) best = w;
      }
    }
    if (best == null) {
      final remaining = worms.where((w) => !w.eliminated).toList();
      if (remaining.length <= 1) {
        best = remaining.isEmpty ? player : remaining.first;
      }
    }
    if (best != null) {
      winner = best;
      over = true;
    }
  }

  // ---------------- أماكن الظهور ----------------

  Offset _freeSpot({double minDist = 20}) {
    Offset best = const Offset(Cfg.arena / 2, Cfg.arena / 2);
    for (int t = 0; t < 30; t++) {
      final p = _randPos(15);
      bool ok = true;
      for (final w in worms) {
        if (!w.alive) continue;
        if ((w.head - p).distance < minDist) {
          ok = false;
          break;
        }
      }
      if (ok) return p;
      best = p;
    }
    return best;
  }

  double _headingToCenter(Offset p) {
    const c = Offset(Cfg.arena / 2, Cfg.arena / 2);
    return math.atan2(c.dy - p.dy, c.dx - p.dx) + (rng.nextDouble() - 0.5) * 0.8;
  }

  // ---------------- الكاميرا ----------------

  void _updateCamera(double dt) {
    final p = player;
    if (p.alive) {
      cam = p.head;
      return;
    }
    Offset t = lastDeathPos ?? cam;
    if (p.eliminated) {
      Worm? best;
      for (final w in worms) {
        if (!w.alive) continue;
        if (best == null || w.kills > best.kills) best = w;
      }
      if (best != null) t = best.head;
    }
    final k = math.min(1.0, dt * 4);
    cam = cam + (t - cam) * k;
  }

  // ---------------- ذكاء البوتات ----------------

  static const List<double> _offsets = [
    0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4,
  ];

  void _think(Worm w, double dt) {
    w.thinkTimer -= dt;
    if (w.thinkTimer > 0) return;
    w.thinkTimer = _bp.reaction * (0.8 + rng.nextDouble() * 0.4);

    final desired = _desiredHeading(w);
    w.target = _safeHeading(w, desired);

    if (_bp.boostChance > 0 &&
        w.boostTimer <= 0 &&
        w.boostCooldown <= 0 &&
        rng.nextDouble() < _bp.boostChance) {
      w.boostTimer = Cfg.boostDuration;
    }
  }

  double _desiredHeading(Worm w) {
    final h = w.head;

    // مطاردة خصم: التصويب أمامه لقطع طريقه
    if (_bp.hunt > 0 && rng.nextDouble() < _bp.hunt) {
      Worm? prey;
      double bd = 45;
      for (final b in worms) {
        if (identical(b, w) || !b.alive || b.invincible > 0) continue;
        final d = (b.head - h).distance;
        if (d < bd) {
          bd = d;
          prey = b;
        }
      }
      if (prey != null) {
        final dir = Offset(math.cos(prey.heading), math.sin(prey.heading));
        final t = bd / Cfg.speed * 0.8;
        final aim = prey.head + dir * (Cfg.speed * t);
        return math.atan2(aim.dy - h.dy, aim.dx - h.dx);
      }
    }

    // أفضل هدف: فاكهة (الذهبية أغلى) أو قدرة
    Offset? best;
    double bs = double.infinity;
    for (final f in fruits) {
      final d = (f.pos - h).distance;
      if (d > _bp.fruitRange) continue;
      final s = d / (f.type == 5 ? 3.0 : 1.0);
      if (s < bs) {
        bs = s;
        best = f.pos;
      }
    }
    for (final p in powerUps) {
      final d = (p.pos - h).distance;
      if (d > _bp.fruitRange) continue;
      final s = d / 2.5;
      if (s < bs) {
        bs = s;
        best = p.pos;
      }
    }
    if (best != null) {
      return math.atan2(best.dy - h.dy, best.dx - h.dx);
    }

    return w.heading + (rng.nextDouble() - 0.5) * 1.2;
  }

  double _safeHeading(Worm w, double desired) {
    for (final off in _offsets) {
      final ang = desired + off;
      if (_clear(w, ang)) return ang;
    }
    const c = Offset(Cfg.arena / 2, Cfg.arena / 2);
    return math.atan2(c.dy - w.head.dy, c.dx - w.head.dx);
  }

  bool _clear(Worm w, double ang) {
    final margin = w.width / 2 + 1.0;
    final cs = math.cos(ang);
    final sn = math.sin(ang);
    final look = _bp.look * (w.boosting ? 1.5 : 1.0);
    for (final dist in [look * 0.5, look]) {
      final px = w.head.dx + cs * dist;
      final py = w.head.dy + sn * dist;
      if (px < margin ||
          px > Cfg.arena - margin ||
          py < margin ||
          py > Cfg.arena - margin) {
        return false;
      }
      for (final b in worms) {
        if (identical(b, w) || !b.alive) continue;
        final thr = margin + b.width / 2;
        final thr2 = thr * thr;
        final hdx = px - b.head.dx;
        final hdy = py - b.head.dy;
        if (hdx * hdx + hdy * hdy < thr2) return false;
        final tr = b.trail;
        for (int i = 0; i < tr.length; i += 2) {
          final dx = px - tr[i].dx;
          final dy = py - tr[i].dy;
          if (dx * dx + dy * dy < thr2) return false;
        }
      }
    }
    return true;
  }

  // ---------------- الشبكة: لقطة المضيف (خفيفة) ----------------

  int _q(double v) => (v * 10).round();

  Map<String, dynamic> snapshot() {
    final withFruit = _fruitAcc >= 0.5;
    if (withFruit) _fruitAcc = 0;

    final ws = <List<dynamic>>[];
    for (final w in worms) {
      // نقطة كل 1.5 سم فقط (الأحدث أولاً) لتقليل حجم البيانات
      final tr = <int>[];
      int i = w.trail.length - 1;
      int lastI = i;
      for (; i >= 0; i -= 3) {
        tr.add(_q(w.trail[i].dx));
        tr.add(_q(w.trail[i].dy));
        lastI = i;
      }
      if (lastI != 0 && w.trail.isNotEmpty) {
        tr.add(_q(w.trail[0].dx));
        tr.add(_q(w.trail[0].dy));
      }
      ws.add([
        w.id,
        _q(w.head.dx),
        _q(w.head.dy),
        (angNorm(w.heading) * 100).round(),
        (w.alive ? 1 : 0) | (w.eliminated ? 2 : 0),
        w.kills,
        w.deaths,
        _q(w.eaten),
        _q(w.invincible),
        _q(w.boostTimer),
        _q(w.boostCooldown),
        _q(w.respawnTimer),
        _q(w.shield),
        _q(w.magnet),
        _q(w.freeze),
        tr,
      ]);
    }
    final ch = <List<dynamic>>[];
    for (final w in worms) {
      if (w.chatTimer > 0) {
        ch.add([w.id, kChat.indexOf(w.chat), _q(w.chatTimer)]);
      }
    }
    final m = <String, dynamic>{
      't': 'snap',
      'r': round,
      'o': over ? 1 : 0,
      'w': winner?.id ?? -1,
      'ws': ws,
      'ch': ch,
      'ev': List<List<dynamic>>.from(_pending),
    };
    if (withFruit) {
      final f = <int>[];
      for (final x in fruits) {
        f.add(_q(x.pos.dx));
        f.add(_q(x.pos.dy));
        f.add(x.type);
      }
      final p = <int>[];
      for (final x in powerUps) {
        p.add(_q(x.pos.dx));
        p.add(_q(x.pos.dy));
        p.add(x.type);
      }
      m['f'] = f;
      m['p'] = p;
    }
    return m;
  }

  // ---------------- الشبكة: العميل ----------------

  void applyRoster(List<dynamic> r, int you, int k) {
    myId = you;
    killsToWin = k;
    maxDeaths = k;
    worms.clear();
    fruits.clear();
    powerUps.clear();
    for (final e in r) {
      final c = (e[2] as num).toInt();
      worms.add(Worm(
        id: (e[0] as num).toInt(),
        name: e[1] as String,
        color: kWormColors[c % kWormColors.length],
        colorIdx: c,
        pattern: (e[3] as num).toInt(),
        level: (e[4] as num).toInt(),
        human: e[5] == 1,
        isPlayer: (e[0] as num).toInt() == you,
      ));
    }
    over = false;
    winner = null;
    notifyListeners();
  }

  void _removeNearestFruit(Offset p) {
    int bi = -1;
    double bd = 4.0;
    for (int i = 0; i < fruits.length; i++) {
      final d = (fruits[i].pos - p).distance;
      if (d < bd) {
        bd = d;
        bi = i;
      }
    }
    if (bi >= 0) fruits.removeAt(bi);
  }

  void _removeNearestPower(Offset p) {
    int bi = -1;
    double bd = 4.0;
    for (int i = 0; i < powerUps.length; i++) {
      final d = (powerUps[i].pos - p).distance;
      if (d < bd) {
        bd = d;
        bi = i;
      }
    }
    if (bi >= 0) powerUps.removeAt(bi);
  }

  void applySnapshot(Map<String, dynamic> m) {
    if (worms.isEmpty) return;
    final r = (m['r'] as num).toInt();
    if (r != round) {
      round = r;
      myFruits = 0;
      bestStreak = 0;
      _killTimes.clear();
    }
    over = m['o'] == 1;
    final wid = (m['w'] as num).toInt();
    winner = wid >= 0 ? _byId(wid) : null;

    double d(dynamic v) => (v as num) / 10.0;

    for (final e in m['ws'] as List) {
      final w = _byId((e[0] as num).toInt());
      if (w == null) continue;
      final wasAlive = w.alive;
      final sh = Offset(d(e[1]), d(e[2]));
      final hd = (e[3] as num) / 100.0;
      final fl = (e[4] as num).toInt();
      w.alive = (fl & 1) != 0;
      w.eliminated = (fl & 2) != 0;
      w.kills = (e[5] as num).toInt();
      w.deaths = (e[6] as num).toInt();
      w.eaten = d(e[7]);
      w.invincible = d(e[8]);
      w.boostTimer = d(e[9]);
      w.boostCooldown = d(e[10]);
      w.respawnTimer = d(e[11]);
      w.shield = d(e[12]);
      w.magnet = d(e[13]);
      w.freeze = d(e[14]);
      final tr = e[15] as List;
      w.trail.clear();
      for (int i = tr.length - 2; i >= 0; i -= 2) {
        w.trail.add(Offset(d(tr[i]), d(tr[i + 1])));
      }
      w.srvHead = sh;
      w.srvHeading = hd;
      w.srvAt = time;
      if (!w.hasSrv || (w.alive && !wasAlive) || (w.head - sh).distance > 8) {
        w.head = sh;
        w.heading = hd;
        w.target = hd;
      }
      w.hasSrv = true;
      if (w.isPlayer && wasAlive && !w.alive) lastDeathPos = w.head;
    }

    final f = m['f'];
    if (f != null) {
      fruits.clear();
      final l = f as List;
      for (int i = 0; i + 2 < l.length; i += 3) {
        final type = (l[i + 2] as num).toInt();
        fruits.add(Fruit(Offset(d(l[i]), d(l[i + 1])), type,
            type == 5 ? Cfg.goldenValue : 1.0));
      }
    }
    final pw = m['p'];
    if (pw != null) {
      powerUps.clear();
      final l = pw as List;
      for (int i = 0; i + 2 < l.length; i += 3) {
        powerUps.add(PowerUp(
            Offset(d(l[i]), d(l[i + 1])), (l[i + 2] as num).toInt()));
      }
    }
    for (final c in m['ch'] as List) {
      final w = _byId((c[0] as num).toInt());
      final idx = (c[1] as num).toInt();
      if (w != null && idx >= 0) {
        w.chat = kChat[idx % kChat.length];
        w.chatTimer = d(c[2]);
      }
    }
    for (final ev in m['ev'] as List) {
      final w = _byId((ev[1] as num).toInt());
      if (w == null) continue;
      final type = ev[0] as String;
      final oid = (ev[2] as num).toInt();
      final o = oid >= 0 ? _byId(oid) : null;
      if (type == 'eat') _removeNearestFruit(w.srvHead);
      if (type == 'power') _removeNearestPower(w.srvHead);
      _track(type, w);
      onEvent?.call(type, w, o);
    }
    notifyListeners();
  }

  /// تنعيم حركة الدودات عند الضيف بين اللقطات (توقع المسار + تصحيح تدريجي).
  void _clientSmooth(double dt) {
    for (final w in worms) {
      if (!w.alive || !w.hasSrv) continue;
      final sp = Cfg.speed *
          (w.boosting ? Cfg.boostMult : 1.0) *
          (w.freeze > 0 ? Cfg.freezeSlow : 1.0);
      final age = math.min(0.25, time - w.srvAt);
      final pred = w.srvHead +
          Offset(math.cos(w.srvHeading), math.sin(w.srvHeading)) * (sp * age);
      if (w.id == myId) {
        // دودتي: أدور فوراً حسب إصبعي دون انتظار المضيف، ثم أصحح الموضع بهدوء
        final diff = angDiff(w.target, w.heading);
        final mt = Cfg.turnRate * dt;
        w.heading += math.max(-mt, math.min(mt, diff));
        w.head = w.head +
            Offset(math.cos(w.heading), math.sin(w.heading)) * (sp * dt);
        w.head = w.head + (pred - w.head) * math.min(1.0, dt * 6);
      } else {
        w.head = w.head + (pred - w.head) * math.min(1.0, dt * 14);
        w.heading += angDiff(w.srvHeading, w.heading) * math.min(1.0, dt * 14);
      }
    }
  }
}
