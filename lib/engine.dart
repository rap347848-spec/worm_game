import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'config.dart';
import 'models.dart';

enum Difficulty { easy, medium, hard }

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

const _Bp _easy = _Bp(
    look: 6, reaction: 0.35, hunt: 0.0, fruitRange: 22, boostChance: 0.0, turnMul: 0.8);
const _Bp _medium = _Bp(
    look: 9, reaction: 0.2, hunt: 0.25, fruitRange: 35, boostChance: 0.01, turnMul: 1.0);
const _Bp _hard = _Bp(
    look: 13, reaction: 0.1, hunt: 0.6, fruitRange: 55, boostChance: 0.04, turnMul: 1.15);

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

class GameEngine extends ChangeNotifier {
  final math.Random rng = math.Random();
  final Difficulty difficulty;
  final List<Worm> worms = <Worm>[];
  final List<Fruit> fruits = <Fruit>[];
  late final Worm player;
  late final _Bp _bp;

  bool over = false;
  Worm? winner;
  Offset cam = const Offset(Cfg.arena / 2, Cfg.arena / 2);
  Offset? lastDeathPos;

  GameEngine({required int bots, required this.difficulty}) {
    _bp = difficulty == Difficulty.easy
        ? _easy
        : (difficulty == Difficulty.medium ? _medium : _hard);

    final colors = List<int>.generate(kWormColors.length, (i) => i)
      ..shuffle(rng);
    final patterns = List<int>.generate(11, (i) => i)..shuffle(rng);
    final names = List<String>.from(kBotNames)..shuffle(rng);

    player = Worm(
      id: 0,
      name: 'أنت',
      isPlayer: true,
      color: kWormColors[colors[0]],
      pattern: patterns[0],
    );
    worms.add(player);
    for (int i = 1; i <= bots; i++) {
      worms.add(Worm(
        id: i,
        name: names[(i - 1) % names.length],
        isPlayer: false,
        color: kWormColors[colors[i]],
        pattern: patterns[i],
      ));
    }
    for (final w in worms) {
      final p = _freeSpot(minDist: 28);
      w.spawn(p, _headingToCenter(p));
    }
    cam = player.head;
    while (fruits.length < Cfg.fruitCount) {
      _addFruit();
    }
  }

  // ---------------- التحكم من اللاعب ----------------

  void steer(double angle) {
    if (player.alive) player.target = angle;
  }

  void boost() {
    if (!player.alive) return;
    if (player.boostTimer <= 0 && player.boostCooldown <= 0) {
      player.boostTimer = Cfg.boostDuration;
    }
  }

  // ---------------- الحلقة الرئيسية ----------------

  void update(double dt) {
    if (over) return;

    for (final w in worms) {
      if (w.eliminated) continue;
      if (!w.alive) {
        w.respawnTimer -= dt;
        if (w.respawnTimer <= 0) _respawn(w);
        continue;
      }
      if (w.invincible > 0) w.invincible -= dt;

      if (w.boostTimer > 0) {
        w.boostTimer -= dt;
        if (w.boostTimer <= 0) {
          w.boostTimer = 0;
          w.boostCooldown = Cfg.boostCooldown;
        }
      } else if (w.boostCooldown > 0) {
        w.boostCooldown -= dt;
      }

      if (!w.isPlayer) _think(w, dt);

      final diff = angDiff(w.target, w.heading);
      final maxTurn = Cfg.turnRate * dt * (w.isPlayer ? 1.0 : _bp.turnMul);
      w.heading += math.max(-maxTurn, math.min(maxTurn, diff));
      w.advance(dt, Cfg.speed * (w.boosting ? Cfg.boostMult : 1.0));
    }

    _eat();
    _collisions();
    _spawnFruits();
    _updateCamera(dt);
    notifyListeners();
  }

  // ---------------- الفواكه ----------------

  void _addFruit() {
    fruits.add(Fruit(
      Offset(3 + rng.nextDouble() * (Cfg.arena - 6),
          3 + rng.nextDouble() * (Cfg.arena - 6)),
      rng.nextInt(5),
    ));
  }

  void _spawnFruits() {
    int guard = 0;
    while (fruits.length < Cfg.fruitCount && guard < 5) {
      _addFruit();
      guard++;
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

      if (hx - r < 0 ||
          hy - r < 0 ||
          hx + r > Cfg.arena ||
          hy + r > Cfg.arena) {
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
      if (!d.w.alive) continue;
      _kill(d.w, d.killer);
    }
    if (deaths.isNotEmpty) _checkEnd();
  }

  void _kill(Worm w, Worm? killer) {
    w.alive = false;
    w.deaths++;
    _dropFruits(w);
    if (w.isPlayer) lastDeathPos = w.head;
    if (killer != null && !identical(killer, w)) killer.kills++;
    if (w.deaths >= Cfg.maxDeaths) {
      w.eliminated = true;
    } else {
      w.respawnTimer = Cfg.respawnDelay;
    }
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
      if (w.kills >= Cfg.killsToWin) {
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
      final p = Offset(15 + rng.nextDouble() * (Cfg.arena - 30),
          15 + rng.nextDouble() * (Cfg.arena - 30));
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
    if (player.alive) {
      cam = player.head;
      return;
    }
    Offset t = lastDeathPos ?? cam;
    if (player.eliminated) {
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

    // أقرب فاكهة
    Fruit? bestF;
    double bd = _bp.fruitRange;
    for (final f in fruits) {
      final d = (f.pos - h).distance;
      if (d < bd) {
        bd = d;
        bestF = f;
      }
    }
    if (bestF != null) {
      return math.atan2(bestF.pos.dy - h.dy, bestF.pos.dx - h.dx);
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
}
