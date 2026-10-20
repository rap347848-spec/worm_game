import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'config.dart';

/// الألقاب العشرة (المستوى 1-9 مبتدئ، ثم لقب جديد كل 10 مستويات).
const List<String> kTitles = [
  'مبتدئ', 'زاحف', 'صياد', 'مقاتل', 'مطارد',
  'فارس', 'قناص', 'زعيم', 'أسطورة', 'ملك الدود',
];

/// ألوان التوهج العشرة: كل لون أجمل وأقوى من السابق. الأخير قوس قزح متحرك.
const List<Color> kGlowColors = [
  Color(0xFF39FF14), // أخضر نيون
  Color(0xFFD4FF00), // ليموني
  Color(0xFFFF00AA), // فوشيا
  Color(0xFFB300FF), // بنفسجي
  Color(0xFFFF4D9D), // وردي
  Color(0xFFFF1744), // أحمر
  Color(0xFFFF9100), // برتقالي
  Color(0xFFFFD700), // ذهبي
  Color(0xFFFFF0FF), // أبيض لؤلؤي
  Color(0xFFFFFFFF), // قوس قزح (يتحرك)
];

const List<String> kChat = [
  'برافو 👏', 'جولة ثانية؟', 'حظ موفق 🍀',
  'يا للأسف 😅', 'ما شاء الله 🔥', 'سأنتصر 😎',
];

int tierOf(int level) => math.min(9, math.max(0, level) ~/ 10);

class Fruit {
  Offset pos;
  final int type; // 0 تفاح، 1 موز، 2 عنب، 3 فراولة، 4 برتقال، 5 ذهبية
  final double value;
  Fruit(this.pos, this.type, [this.value = 1.0]);
}

class PowerUp {
  Offset pos;
  final int type; // 0 درع، 1 مغناطيس، 2 تجميد
  PowerUp(this.pos, this.type);
}

class Worm {
  final int id;
  final String name;
  final Color color;
  final int colorIdx;
  final int pattern;

  bool isPlayer; // اللاعب المحلي على هذا الجهاز
  bool human; // يتحكم به إنسان (محلي أو عن بعد) وليس بوت
  String? peer; // معرف الجهاز البعيد
  int level;

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
  double shield = 0;
  double magnet = 0;
  double freeze = 0;

  // العميل فقط: آخر حالة وصلت من المضيف (للتنعيم والتوقع)
  Offset srvHead = Offset.zero;
  double srvHeading = 0;
  double srvAt = 0;
  bool hasSrv = false;

  String chat = '';
  double chatTimer = 0;

  String? _labelKey;
  TextPainter? _label;

  Worm({
    required this.id,
    required this.name,
    required this.color,
    required this.colorIdx,
    required this.pattern,
    this.isPlayer = false,
    this.human = false,
    this.peer,
    this.level = 1,
  });

  Color get accent => color.computeLuminance() > 0.5
      ? const Color(0xFF37474F)
      : const Color(0xFFFFFFFF);

  int get tier => tierOf(level);
  String get title => kTitles[tier];

  double get _lenMult => math.min(
      math.pow(1 + Cfg.lengthGrowth, eaten).toDouble(), Cfg.maxLengthMult);

  double get length => Cfg.baseLength * _lenMult;

  double get width =>
      Cfg.baseWidth *
      math.min(1 + Cfg.widthFollow * (_lenMult - 1), Cfg.maxWidthMult);

  bool get boosting => boostTimer > 0;

  /// اللقب + الاسم فوق الدودة.
  TextPainter get label {
    final key = '$name|$level';
    if (_label == null || _labelKey != key) {
      _labelKey = key;
      _label = TextPainter(
        text: TextSpan(children: [
          TextSpan(
            text: '$title\n',
            style: TextStyle(
              color: kGlowColors[tier],
              fontSize: 1.05,
              fontWeight: FontWeight.bold,
              shadows: const [
                Shadow(
                    color: Color(0xFF000000),
                    blurRadius: 0.3,
                    offset: Offset(0.07, 0.07)),
              ],
            ),
          ),
          TextSpan(
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
        ]),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      )..layout();
    }
    return _label!;
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
    shield = 0;
    magnet = 0;
    freeze = 0;
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
