/// كل ثوابت اللعبة في مكان واحد. الوحدة في العالم = 1 سم.
class Cfg {
  // السرعة العادية للدودة (سم / ثانية)
  static const double speed = 10.0;

  // الزمن اللازم لقطع الساحة من جهة لجهة
  static const double crossSeconds = 15.0;

  // مقاس الساحة (مربع): السرعة × 15 ثانية
  static const double arena = speed * crossSeconds;

  // الحجم الأصلي للدودة
  static const double baseLength = 5.0;
  static const double baseWidth = 2.0;

  // النمو عند أكل فاكهة (نسبة من الحجم الأصلي)
  static const double lengthGrowth = 0.02; // 2% للطول
  static const double widthGrowth = 0.005; // 0.5% للعرض (كي يكون ملحوظاً)
  static const double maxLengthMult = 14.0;
  static const double maxWidthMult = 2.0;

  // الفواكه
  static const int fruitCount = 100;
  static const double fruitRadius = 1.1;
  static const double goldenValue = 3.0; // الفاكهة الذهبية

  // قواعد المباراة
  static const double respawnDelay = 2.0;
  static const double invincibleTime = 3.0;
  static const int maxWorms = 11;

  // التسريع (ضغطتان على الشاشة)
  static const double boostMult = 1.8;
  static const double boostDuration = 5.0;
  static const double boostCooldown = 10.0;

  // القدرات المؤقتة
  static const double shieldTime = 5.0;
  static const double magnetTime = 8.0;
  static const double freezeTime = 3.0;
  static const double freezeRadius = 22.0;
  static const double freezeSlow = 0.5;
  static const double magnetRadius = 12.0;
  static const double magnetPull = 16.0;
  static const int maxPowerUps = 3;

  // الكاميرا: الارتفاع الظاهر من الساحة (سم)
  static const double viewHeight = 38.0;

  // سرعة الدوران (راديان / ثانية) والمسافة بين نقاط جسم الدودة
  static const double turnRate = 4.5;
  static const double spacing = 0.5;

  // الشبكة: عدد اللقطات المرسلة في الثانية من المضيف
  static const double snapshotHz = 20.0;
}
