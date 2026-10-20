import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'config.dart';
import 'engine.dart';
import 'models.dart';
import 'progress.dart';

Color glowColorFor(int tier, double time) {
  if (tier >= 9) {
    return HSVColor.fromAHSV(1, (time * 90) % 360, 0.75, 1).toColor();
  }
  return kGlowColors[tier];
}

class WorldPainter extends CustomPainter {
  final GameEngine engine;
  WorldPainter(this.engine) : super(repaint: engine);

  static final Map<String, TextPainter> _tp = {};

  TextPainter _text(String s, double size, Color color) {
    final key = '$s|$size|${color.hashCode}';
    return _tp.putIfAbsent(
        key,
        () => TextPainter(
              text: TextSpan(
                  text: s, style: TextStyle(fontSize: size, color: color)),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
            )..layout());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sc = canvas.getSaveCount();
    try {
      _paintWorld(canvas, size);
    } catch (e) {
      canvas.restoreToCount(sc);
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0B1F2A));
      final tp = TextPainter(
        text: TextSpan(
            text: 'خطأ في الرسم:\n$e',
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13)),
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: size.width - 24);
      tp.paint(canvas, const Offset(12, 12));
    }
  }

  void _paintWorld(Canvas canvas, Size size) {
    final lowFx = Store.i.settings.batterySaver;
    final simple = Store.i.settings.simpleDraw;
    final scale = size.height / Cfg.viewHeight;
    final viewW = size.width / scale;
    const viewH = Cfg.viewHeight;

    double cx = engine.cam.dx;
    double cy = engine.cam.dy;
    cx = viewW >= Cfg.arena
        ? Cfg.arena / 2
        : math.max(viewW / 2, math.min(Cfg.arena - viewW / 2, cx));
    cy = math.max(viewH / 2, math.min(Cfg.arena - viewH / 2, cy));

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0B1F2A));

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-cx, -cy);

    final view = Rect.fromCenter(
        center: Offset(cx, cy), width: viewW, height: viewH);

    // أرض الساحة: أزرق فاتح
    canvas.drawRect(const Rect.fromLTWH(0, 0, Cfg.arena, Cfg.arena),
        Paint()..color = const Color(0xFFB3E5FC));

    // شبكة خفيفة (تُلغى في وضع توفير البطارية)
    if (!lowFx && !simple) {
      final grid = Paint()
        ..color = const Color(0x3390A4AE)
        ..strokeWidth = 0.12;
      final top = math.max(0.0, view.top);
      final bottom = math.min(Cfg.arena, view.bottom);
      final left = math.max(0.0, view.left);
      final right = math.min(Cfg.arena, view.right);
      for (double x = (left / 10).floor() * 10.0; x <= right; x += 10) {
        canvas.drawLine(Offset(x, top), Offset(x, bottom), grid);
      }
      for (double y = (top / 10).floor() * 10.0; y <= bottom; y += 10) {
        canvas.drawLine(Offset(left, y), Offset(right, y), grid);
      }
    }

    // الجدار: يتوهج بالأحمر عند اقتراب اللاعب منه
    double warn = 0;
    final pl = engine.player;
    if (pl.alive) {
      final h = pl.head;
      final dmin = math.min(
          math.min(h.dx, h.dy), math.min(Cfg.arena - h.dx, Cfg.arena - h.dy));
      warn = math.max(0.0, math.min(1.0, (10 - dmin) / 10));
    }
    const wallRect = Rect.fromLTWH(-0.5, -0.5, Cfg.arena + 1, Cfg.arena + 1);
    if (warn > 0) {
      canvas.drawRect(
          wallRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..color = Color.fromRGBO(255, 23, 68, 0.35 * warn));
    }
    canvas.drawRect(
        wallRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Color.lerp(
              const Color(0xFF455A64), const Color(0xFFFF1744), warn)!);

    // الفواكه والقدرات
    final fv = view.inflate(3);
    for (final f in engine.fruits) {
      if (!fv.contains(f.pos)) continue;
      simple ? _drawFruitSimple(canvas, f) : _drawFruit(canvas, f);
    }
    for (final p in engine.powerUps) {
      if (!fv.contains(p.pos)) continue;
      simple ? _drawPowerSimple(canvas, p) : _drawPower(canvas, p);
    }

    // الدودات: الخصوم أولاً ثم اللاعب فوقهم
    for (final w in engine.worms) {
      if (w.alive && !w.isPlayer) _drawWorm(canvas, w, lowFx, simple);
    }
    if (pl.alive) _drawWorm(canvas, pl, lowFx, simple);

    canvas.restore();
  }

  // ---------------- الفواكه ----------------

  void _drawFruit(Canvas c, Fruit f) {
    final p = f.pos;
    const r = Cfg.fruitRadius;
    final leaf = Paint()..color = const Color(0xFF43A047);
    switch (f.type) {
      case 0: // تفاح
        c.drawCircle(p, r, Paint()..color = const Color(0xFFE53935));
        c.drawCircle(p + const Offset(-r * 0.3, -r * 0.3), r * 0.28,
            Paint()..color = const Color(0x66FFFFFF));
        c.drawLine(
            p + const Offset(0, -r * 0.9),
            p + const Offset(r * 0.1, -r * 1.35),
            Paint()
              ..color = const Color(0xFF5D4037)
              ..strokeWidth = r * 0.18
              ..strokeCap = StrokeCap.round);
        c.drawOval(
            Rect.fromCenter(
                center: p + const Offset(r * 0.45, -r * 1.15),
                width: r * 0.6,
                height: r * 0.3),
            leaf);
        break;
      case 1: // موز
        c.drawArc(
            Rect.fromCircle(
                center: p + const Offset(0, -r * 0.2), radius: r * 0.85),
            0.5,
            2.2,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.8
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFFFFD54F));
        break;
      case 2: // عنب
        const offs = [
          Offset(-0.4, -0.3), Offset(0.4, -0.3), Offset(0, 0.1),
          Offset(-0.4, 0.5), Offset(0.4, 0.5), Offset(0, 0.9),
        ];
        final gp = Paint()..color = const Color(0xFF7B1FA2);
        final gh = Paint()..color = const Color(0x55FFFFFF);
        for (final o in offs) {
          final q = p + Offset(o.dx * r, (o.dy - 0.25) * r);
          c.drawCircle(q, r * 0.42, gp);
          c.drawCircle(q + const Offset(-r * 0.12, -r * 0.12), r * 0.12, gh);
        }
        c.drawOval(
            Rect.fromCenter(
                center: p + const Offset(r * 0.4, -r * 0.95),
                width: r * 0.6,
                height: r * 0.3),
            leaf);
        break;
      case 3: // فراولة
        final path = Path()
          ..moveTo(p.dx - r, p.dy - r * 0.4)
          ..quadraticBezierTo(p.dx, p.dy - r * 1.2, p.dx + r, p.dy - r * 0.4)
          ..quadraticBezierTo(
              p.dx + r * 0.7, p.dy + r * 0.7, p.dx, p.dy + r * 1.1)
          ..quadraticBezierTo(
              p.dx - r * 0.7, p.dy + r * 0.7, p.dx - r, p.dy - r * 0.4)
          ..close();
        c.drawPath(path, Paint()..color = const Color(0xFFE91E63));
        final seed = Paint()..color = const Color(0xFFFFEB3B);
        for (final o in const [
          Offset(-0.4, -0.2), Offset(0.4, -0.2), Offset(0, 0.2), Offset(0, 0.65)
        ]) {
          c.drawCircle(p + Offset(o.dx * r, o.dy * r), r * 0.09, seed);
        }
        c.drawOval(
            Rect.fromCenter(
                center: p + const Offset(0, -r * 0.8),
                width: r * 1.1,
                height: r * 0.35),
            leaf);
        break;
      case 5: // فاكهة ذهبية نادرة
        final pulse = 0.8 + 0.2 * math.sin(engine.time * 5);
        c.drawCircle(p, r * 2.1 * pulse,
            Paint()..color = const Color(0x55FFD700));
        c.drawCircle(p, r * 1.25, Paint()..color = const Color(0xFFFFC107));
        c.drawCircle(p, r * 1.25,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.2
              ..color = const Color(0xFFFFF176));
        c.drawPath(_star(p, r * 0.8, r * 0.35),
            Paint()..color = const Color(0xFFFFFDE7));
        break;
      default: // برتقال
        c.drawCircle(p, r, Paint()..color = const Color(0xFFFB8C00));
        c.drawCircle(p + const Offset(-r * 0.3, -r * 0.3), r * 0.28,
            Paint()..color = const Color(0x55FFFFFF));
        c.drawCircle(p + const Offset(0, -r * 0.85), r * 0.12,
            Paint()..color = const Color(0xFF8D4E00));
        c.drawOval(
            Rect.fromCenter(
                center: p + const Offset(r * 0.4, -r * 1.0),
                width: r * 0.6,
                height: r * 0.3),
            leaf);
    }
  }

  void _drawPower(Canvas c, PowerUp p) {
    const cols = [Color(0xFFFFC107), Color(0xFFAB47BC), Color(0xFF4FC3F7)];
    const emo = ['🛡️', '🧲', '❄️'];
    final pulse = 1 + 0.08 * math.sin(engine.time * 4 + p.pos.dx);
    final r = 1.7 * pulse;
    c.drawCircle(p.pos, r, Paint()..color = const Color(0xE6FFFFFF));
    c.drawCircle(
        p.pos,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.35
          ..color = cols[p.type]);
    final tp = _text(emo[p.type], 2.0, const Color(0xFF000000));
    tp.paint(c, Offset(p.pos.dx - tp.width / 2, p.pos.dy - tp.height / 2));
  }

  // ---------------- الدودة ----------------

  static const List<Color> _fruitCols = [
    Color(0xFFE53935), Color(0xFFFFD54F), Color(0xFF7B1FA2),
    Color(0xFFE91E63), Color(0xFFFB8C00), Color(0xFFFFC107),
  ];

  void _drawFruitSimple(Canvas c, Fruit f) {
    c.drawCircle(f.pos, Cfg.fruitRadius * (f.type == 5 ? 1.3 : 1.0),
        Paint()..color = _fruitCols[f.type.clamp(0, 5).toInt()]);
  }

  void _drawPowerSimple(Canvas c, PowerUp p) {
    const cols = [Color(0xFFFFC107), Color(0xFFAB47BC), Color(0xFF4FC3F7)];
    c.drawCircle(p.pos, 1.7, Paint()..color = const Color(0xE6FFFFFF));
    c.drawCircle(
        p.pos,
        1.7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = cols[p.type.clamp(0, 2).toInt()]);
  }

  void _drawWorm(Canvas canvas, Worm w, bool lowFx, bool simple) {
    final width = w.width;
    final ghost = w.invincible > 0;
    final tier = w.tier;
    final gc = glowColorFor(tier, engine.time);

    final path = Path()..moveTo(w.head.dx, w.head.dy);
    for (int i = w.trail.length - 1; i >= 0; i--) {
      path.lineTo(w.trail[i].dx, w.trail[i].dy);
    }

    if (simple) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width + 0.7
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF263238));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = w.color);
      canvas.drawCircle(w.head, width * 0.62, Paint()..color = w.color);
      final sd = Offset(math.cos(w.heading), math.sin(w.heading));
      final sn = Offset(-sd.dy, sd.dx);
      for (final k in const [1.0, -1.0]) {
        final e = w.head + sd * (width * 0.25) + sn * (width * 0.28 * k);
        canvas.drawCircle(e, width * 0.2, Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawCircle(e + sd * (width * 0.06), width * 0.1,
            Paint()..color = const Color(0xFF000000));
      }
      if (w.invincible > 0) {
        canvas.drawCircle(
            w.head,
            width * 1.3,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.25
              ..color = const Color(0xCCFFFFFF));
      }
      return;
    }

    // التوهج حول الدودة: لون وقوة حسب المستوى
    final pulse = 0.75 + 0.25 * math.sin(engine.time * 3 + w.id);
    final gw = width + 0.9 + tier * 0.22;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (!lowFx) {
      glow
        ..strokeWidth = gw + 1.2
        ..color = gc.withAlpha((70 * pulse).round());
      canvas.drawPath(path, glow);
    }
    glow
      ..strokeWidth = gw
      ..color = gc.withAlpha(lowFx ? 110 : (130 * pulse).round());
    canvas.drawPath(path, glow);

    final hsl = HSLColor.fromColor(w.color);
    final dark = hsl.lightness < 0.2
        ? const Color(0xFF616161)
        : hsl.withLightness((hsl.lightness * 0.55).clamp(0.0, 1.0)).toColor();

    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 0.9
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = dark);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 0.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = gc);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = w.color);

    // زخرفة الدودة
    final fill = Paint()..color = w.accent;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..color = w.accent;
    final gap = width * 1.4;
    double acc = gap;
    for (int i = w.trail.length - 1; i >= 1; i--) {
      final a = w.trail[i];
      final b = w.trail[i - 1];
      final seg = (a - b).distance;
      if (seg <= 0) continue;
      acc -= seg;
      if (acc <= 0) {
        acc += gap;
        _mark(canvas, a, (a - b) / seg, width, w.pattern, fill, stroke);
      }
    }

    // الرأس والعيون
    final hp = w.head;
    canvas.drawCircle(hp, width * 0.68, Paint()..color = gc);
    canvas.drawCircle(hp, width * 0.62, Paint()..color = dark);
    canvas.drawCircle(hp, width * 0.58, Paint()..color = w.color);
    final d = Offset(math.cos(w.heading), math.sin(w.heading));
    final n = Offset(-d.dy, d.dx);
    for (final s in const [1.0, -1.0]) {
      final e = hp + d * (width * 0.25) + n * (width * 0.28 * s);
      canvas.drawCircle(e, width * 0.2, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(e + d * (width * 0.06), width * 0.1,
          Paint()..color = const Color(0xFF000000));
    }


    // حلقات القدرات
    if (ghost) {
      canvas.drawCircle(
          hp,
          width * 1.3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.25
            ..color = const Color(0xCCFFFFFF));
    }
    if (w.shield > 0) {
      canvas.drawCircle(
          hp,
          width * 1.6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.4
            ..color = const Color(0xFFFFC107));
    }
    if (w.magnet > 0) {
      canvas.drawCircle(
          hp,
          width * 2.0 + 0.3 * math.sin(engine.time * 6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.25
            ..color = const Color(0xAAAB47BC));
    }
    if (w.freeze > 0) {
      final tp = _text('❄️', 1.8, const Color(0xFF000000));
      tp.paint(canvas, Offset(hp.dx - tp.width / 2, hp.dy - tp.height / 2));
    }

    // اللقب والاسم
    final tp = w.label;
    final labelTop = hp.dy - width * 1.3 - 1.0 - tp.height;
    tp.paint(canvas, Offset(hp.dx - tp.width / 2, labelTop));

    // فقاعة الرسالة السريعة
    if (w.chatTimer > 0 && w.chat.isNotEmpty) {
      final ct = _text(w.chat, 1.5, const Color(0xFF263238));
      final bw = ct.width + 1.4;
      final bh = ct.height + 0.8;
      final rect = Rect.fromLTWH(hp.dx - bw / 2, labelTop - bh - 0.5, bw, bh);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(0.8)),
          Paint()..color = const Color(0xF2FFFFFF));
      ct.paint(canvas, Offset(rect.left + 0.7, rect.top + 0.4));
    }

    // مؤشر جاهزية التسريع للاعب
    if (w.isPlayer) {
      const bw = 6.0;
      const bh = 0.7;
      final top = Offset(hp.dx - bw / 2, hp.dy + width * 1.3 + 0.8);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(top.dx, top.dy, bw, bh), const Radius.circular(0.35)),
          Paint()..color = const Color(0x66000000));
      double frac;
      Color col;
      if (w.boosting) {
        frac = w.boostTimer / Cfg.boostDuration;
        col = const Color(0xFFFF9800);
      } else if (w.boostCooldown > 0) {
        frac = 1 - w.boostCooldown / Cfg.boostCooldown;
        col = const Color(0xFF78909C);
      } else {
        frac = 1;
        col = const Color(0xFF43A047);
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(top.dx, top.dy, bw * frac.clamp(0.0, 1.0), bh),
              const Radius.circular(0.35)),
          Paint()..color = col);
    }
  }

  void _mark(Canvas c, Offset p, Offset d, double w, int pattern, Paint fill,
      Paint stroke) {
    final n = Offset(-d.dy, d.dx);
    final s = w * 0.3;
    switch (pattern) {
      case 0: // نقاط
        c.drawCircle(p, s, fill);
        break;
      case 1: // أشرطة
        stroke.strokeWidth = s * 1.1;
        c.drawLine(p + n * (w * 0.46), p - n * (w * 0.46), stroke);
        break;
      case 2: // حلقات
        stroke.strokeWidth = s * 0.5;
        c.drawCircle(p, s * 0.9, stroke);
        break;
      case 3: // معينات
        c.drawPath(
            Path()
              ..moveTo(p.dx + d.dx * s * 1.4, p.dy + d.dy * s * 1.4)
              ..lineTo(p.dx + n.dx * s * 1.1, p.dy + n.dy * s * 1.1)
              ..lineTo(p.dx - d.dx * s * 1.4, p.dy - d.dy * s * 1.4)
              ..lineTo(p.dx - n.dx * s * 1.1, p.dy - n.dy * s * 1.1)
              ..close(),
            fill);
        break;
      case 4: // نجوم
        c.drawPath(_star(p, s * 1.3, s * 0.55), fill);
        break;
      case 5: // شيفرون
        stroke.strokeWidth = s * 0.7;
        c.drawPath(
            Path()
              ..moveTo(p.dx + n.dx * w * 0.4 - d.dx * s * 1.2,
                  p.dy + n.dy * w * 0.4 - d.dy * s * 1.2)
              ..lineTo(p.dx, p.dy)
              ..lineTo(p.dx - n.dx * w * 0.4 - d.dx * s * 1.2,
                  p.dy - n.dy * w * 0.4 - d.dy * s * 1.2),
            stroke);
        break;
      case 6: // بقع كبيرة
        c.drawCircle(p, s * 1.5, fill);
        break;
      case 7: // مربعات
        c.drawPath(
            Path()
              ..moveTo(p.dx + (d.dx + n.dx) * s, p.dy + (d.dy + n.dy) * s)
              ..lineTo(p.dx + (d.dx - n.dx) * s, p.dy + (d.dy - n.dy) * s)
              ..lineTo(p.dx + (-d.dx - n.dx) * s, p.dy + (-d.dy - n.dy) * s)
              ..lineTo(p.dx + (-d.dx + n.dx) * s, p.dy + (-d.dy + n.dy) * s)
              ..close(),
            fill);
        break;
      case 8: // صلبان
        stroke.strokeWidth = s * 0.6;
        c.drawLine(p + d * s, p - d * s, stroke);
        c.drawLine(p + n * s, p - n * s, stroke);
        break;
      case 9: // مثلثات
        c.drawPath(
            Path()
              ..moveTo(p.dx + d.dx * s * 1.3, p.dy + d.dy * s * 1.3)
              ..lineTo(p.dx - d.dx * s * 0.8 + n.dx * s * 1.1,
                  p.dy - d.dy * s * 0.8 + n.dy * s * 1.1)
              ..lineTo(p.dx - d.dx * s * 0.8 - n.dx * s * 1.1,
                  p.dy - d.dy * s * 0.8 - n.dy * s * 1.1)
              ..close(),
            fill);
        break;
      default: // نقطتان
        c.drawCircle(p + n * (w * 0.2), s * 0.75, fill);
        c.drawCircle(p - n * (w * 0.2), s * 0.75, fill);
    }
  }

  Path _star(Offset c, double ro, double ri) {
    final p = Path();
    for (int i = 0; i < 10; i++) {
      final r = i.isEven ? ro : ri;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = c.dx + r * math.cos(a);
      final y = c.dy + r * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// الخريطة المصغرة: تعرض مكان كل الدودات.
class MiniMapPainter extends CustomPainter {
  final GameEngine engine;
  MiniMapPainter(this.engine) : super(repaint: engine);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rr, Paint()..color = const Color(0xCCB3E5FC));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xCCFFFFFF));
    final s = size.width / Cfg.arena;
    for (final f in engine.fruits) {
      if (f.type == 5) {
        canvas.drawCircle(Offset(f.pos.dx * s, f.pos.dy * s), 2.2,
            Paint()..color = const Color(0xFFFFC107));
      }
    }
    final pl = engine.player;
    for (final w in engine.worms) {
      if (!w.alive || identical(w, pl)) continue;
      final p = Offset(w.head.dx * s, w.head.dy * s);
      canvas.drawCircle(p, 3.5, Paint()..color = const Color(0xFF000000));
      canvas.drawCircle(p, 2.7, Paint()..color = w.color);
    }
    if (pl.alive) {
      final p = Offset(pl.head.dx * s, pl.head.dy * s);
      canvas.drawCircle(p, 5.5, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(p, 4.2, Paint()..color = pl.color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
