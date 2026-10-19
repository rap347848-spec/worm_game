import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'config.dart';

class Fruit {
  Offset pos;
  final int type; // 0 تفاح، 1 موز، 2 عنب، 3 فراولة، 4 برتقال
  final double value;
  Fruit(this.pos, this.type, [this.value = 1.0]);
}

class Worm {
  final int id;
  final String name;
  final bool isPlayer;
  final Color color;
  final int pattern;

  Offset head = Offset.zero;
  double heading = 0;
  double target = 0;

  /// نقاط الجسم: الأقدم أولاً، والأحدث في النهاية (قرب الرأس).
  final List<Offset> trail = <Offset>[];
  double trailLen = 0;

  double eaten = 0;
  int kills = 0;
  int deaths = 0;
  bool alive = false;
  bool eliminated = false;
  double respawnTimer = 0;
  double invincible = 0;
  double boostTimer = 0;
  double boostCooldown = 0;
  double thinkTimer = 0;

  TextPainter? _label;

  Worm({
    required this.id,
    required this.name,
    required this.isPlayer,
    required this.color,
    required this.pattern,
  });

  Color get accent => color.computeLuminance() > 0.5
      ? const Color(0xFF37474F)
      : const Color(0xFFFFFFFF);

  double get length => math.min(
      Cfg.baseLength * (1 + Cfg.lengthGrowth * eaten),
      Cfg.baseLength * Cfg.maxLengthMult);

  double get width => math.min(
      Cfg.baseWidth * (1 + Cfg.widthGrowth * eaten),
      Cfg.baseWidth * Cfg.maxWidthMult);

  bool get boosting => boostTimer > 0;

  TextPainter get label {
    return _label ??= (TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 1.5,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
                color: Color(0xFF000000),
                blurRadius: 0.3,
                offset: Offset(0.08, 0.08)),
          ],
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout());
  }

  /// ولادة جديدة بالحجم الأصلي.
  void spawn(Offset p, double h) {
    head = p;
    heading = h;
    target = h;
    eaten = 0;
    alive = true;
    invincible = Cfg.invincibleTime;
    boostTimer = 0;
    boostCooldown = 0;
    trail.clear();
    final dir = Offset(math.cos(h), math.sin(h));
    final n = (Cfg.baseLength / Cfg.spacing).ceil();
    for (int i = n; i >= 0; i--) {
      trail.add(p - dir * (i * Cfg.spacing));
    }
    trailLen = n * Cfg.spacing;
  }

  void advance(double dt, double speed) {
    final dir = Offset(math.cos(heading), math.sin(heading));
    head = head + dir * (speed * dt);
    while ((head - trail.last).distance >= Cfg.spacing) {
      final last = trail.last;
      final d = head - last;
      final np = last + d / d.distance * Cfg.spacing;
      trail.add(np);
      trailLen += Cfg.spacing;
    }
    _trim();
  }

  void _trim() {
    final gap = (head - trail.last).distance;
    while (trail.length > 2) {
      final seg = (trail[1] - trail[0]).distance;
      if (trailLen - seg + gap >= length) {
        trail.removeAt(0);
        trailLen -= seg;
      } else {
        break;
      }
    }
  }
}
