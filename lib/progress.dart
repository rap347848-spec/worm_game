import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------
// المستويات: 100 مستوى من 0 إلى 2000 نقطة فوز. الصعود يزداد صعوبة تدريجياً.
// ---------------------------------------------------------------

double pointsNeeded(int n) {
  if (n <= 1) return 0;
  return (2000 * math.pow((n - 1) / 99, 1.6)).roundToDouble();
}

int levelForPoints(double p) {
  int lv = 1;
  for (int n = 2; n <= 100; n++) {
    if (p >= pointsNeeded(n)) {
      lv = n;
    } else {
      break;
    }
  }
  return lv;
}

double levelProgress(double p) {
  final lv = levelForPoints(p);
  if (lv >= 100) return 1.0;
  final a = pointsNeeded(lv);
  final b = pointsNeeded(lv + 1);
  return ((p - a) / (b - a)).clamp(0.0, 1.0).toDouble();
}

// ---------------------------------------------------------------
// نتيجة المباراة والمكافآت
// ---------------------------------------------------------------

class MatchResult {
  final bool won;
  final int kills;
  final int deaths;
  final int fruits;
  final int bestStreak;
  final int otherHumans;
  final Map<String, int> opponents; // اسم اللاعب الحقيقي -> مستواه
  MatchResult({
    required this.won,
    required this.kills,
    required this.deaths,
    required this.fruits,
    required this.bestStreak,
    required this.otherHumans,
    required this.opponents,
  });
}

class MatchReward {
  double gained = 0;
  double bonus = 0;
  int levelBefore = 1;
  int levelAfter = 1;
  final List<String> achievements = [];
  final List<String> missions = [];
}

// ---------------------------------------------------------------
// المهام اليومية
// ---------------------------------------------------------------

class MissionDef {
  final String title;
  final String type; // fruit / kill / win / match
  final int target;
  final double reward;
  const MissionDef(this.title, this.type, this.target, this.reward);
}

const List<MissionDef> kMissions = [
  MissionDef('كُل 40 فاكهة', 'fruit', 40, 1),
  MissionDef('كُل 100 فاكهة', 'fruit', 100, 2),
  MissionDef('اقتل 3 دودات', 'kill', 3, 1),
  MissionDef('اقتل 8 دودات', 'kill', 8, 2),
  MissionDef('افز بمباراة', 'win', 1, 2),
  MissionDef('العب 3 مباريات', 'match', 3, 1),
];

// ---------------------------------------------------------------
// الإنجازات
// ---------------------------------------------------------------

class Ach {
  final String id;
  final String title;
  final String desc;
  final bool Function(Profile, MatchResult) test;
  const Ach(this.id, this.title, this.desc, this.test);
}

final List<Ach> kAchievements = [
  Ach('first_kill', 'أول دم', 'اقتل أول دودة', (p, r) => p.kills >= 1),
  Ach('kills_100', 'صائد ماهر', 'اقتل 100 دودة', (p, r) => p.kills >= 100),
  Ach('fruits_1000', 'أكول', 'كُل 1000 فاكهة', (p, r) => p.fruits >= 1000),
  Ach('first_win', 'الفوز الأول', 'افز بأول مباراة', (p, r) => p.wins >= 1),
  Ach('wins_10', 'بطل', 'افز بـ 10 مباريات', (p, r) => p.wins >= 10),
  Ach('streak_3', 'سلسلة نار', 'افز 3 مرات متتالية',
      (p, r) => p.bestWinStreak >= 3),
  Ach('survivor', 'ناجٍ', 'افز بمباراة وأنت مت مرتين أو أقل',
      (p, r) => r.won && r.deaths <= 2),
  Ach('triple', 'قتل ثلاثي', 'اقتل 3 دودات خلال 6 ثوانٍ',
      (p, r) => r.bestStreak >= 3),
  Ach('social', 'لاعب جماعي', 'العب مباراة مع لاعبين حقيقيين',
      (p, r) => r.otherHumans > 0),
  Ach('lvl_10', 'ترقية', 'صل إلى المستوى 10', (p, r) => p.level >= 10),
  Ach('lvl_50', 'نصف الطريق', 'صل إلى المستوى 50', (p, r) => p.level >= 50),
  Ach('lvl_100', 'ملك الدود', 'صل إلى المستوى 100', (p, r) => p.level >= 100),
];

// ---------------------------------------------------------------
// الملف الشخصي والإعدادات
// ---------------------------------------------------------------

class Profile {
  String name = '';
  double points = 0;
  int wins = 0;
  int matches = 0;
  int kills = 0;
  int deaths = 0;
  int fruits = 0;
  int winStreak = 0;
  int bestWinStreak = 0;
  String lastDaily = '';
  int loginStreak = 0;
  bool tutorialSeen = false;

  String missionDay = '';
  List<int> missionIds = [];
  List<int> missionProg = [];
  List<int> missionDone = [];

  Set<String> ach = <String>{};
  Map<String, Map<String, dynamic>> friends = {};

  int get level => levelForPoints(points);

  void ensureDay(String day) {
    if (missionDay == day && missionIds.length == 3) return;
    missionDay = day;
    final ids = List<int>.generate(kMissions.length, (i) => i)
      ..shuffle(math.Random());
    missionIds = ids.take(3).toList();
    missionProg = [0, 0, 0];
    missionDone = [0, 0, 0];
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'points': points,
        'wins': wins,
        'matches': matches,
        'kills': kills,
        'deaths': deaths,
        'fruits': fruits,
        'ws': winStreak,
        'bws': bestWinStreak,
        'ld': lastDaily,
        'ls': loginStreak,
        'ts': tutorialSeen,
        'md': missionDay,
        'mi': missionIds,
        'mp': missionProg,
        'mdn': missionDone,
        'ach': ach.toList(),
        'fr': friends,
      };

  static Profile fromJson(Map<String, dynamic> j) {
    final p = Profile();
    p.name = (j['name'] ?? '') as String;
    p.points = ((j['points'] ?? 0) as num).toDouble();
    p.wins = (j['wins'] ?? 0) as int;
    p.matches = (j['matches'] ?? 0) as int;
    p.kills = (j['kills'] ?? 0) as int;
    p.deaths = (j['deaths'] ?? 0) as int;
    p.fruits = (j['fruits'] ?? 0) as int;
    p.winStreak = (j['ws'] ?? 0) as int;
    p.bestWinStreak = (j['bws'] ?? 0) as int;
    p.lastDaily = (j['ld'] ?? '') as String;
    p.loginStreak = (j['ls'] ?? 0) as int;
    p.tutorialSeen = (j['ts'] ?? false) as bool;
    p.missionDay = (j['md'] ?? '') as String;
    p.missionIds = List<int>.from((j['mi'] ?? <int>[]) as List);
    p.missionProg = List<int>.from((j['mp'] ?? <int>[]) as List);
    p.missionDone = List<int>.from((j['mdn'] ?? <int>[]) as List);
    p.ach = Set<String>.from((j['ach'] ?? <String>[]) as List);
    final fr = (j['fr'] ?? <String, dynamic>{}) as Map;
    fr.forEach((k, v) {
      p.friends[k as String] = Map<String, dynamic>.from(v as Map);
    });
    return p;
  }
}

class Settings {
  bool eatAll = true; // صوت الأكل (الكل)
  bool eatMine = true; // صوت أكل دودتي
  bool eatOthers = true; // صوت أكل الخصوم
  bool sfxOther = true; // أصوات القتل والموت والمستوى
  bool vibration = true;
  double sensitivity = 1.0;
  bool batterySaver = false;

  Map<String, dynamic> toJson() => {
        'ea': eatAll,
        'em': eatMine,
        'eo': eatOthers,
        'so': sfxOther,
        'vb': vibration,
        'se': sensitivity,
        'bs': batterySaver,
      };

  static Settings fromJson(Map<String, dynamic> j) {
    final s = Settings();
    s.eatAll = (j['ea'] ?? true) as bool;
    s.eatMine = (j['em'] ?? true) as bool;
    s.eatOthers = (j['eo'] ?? true) as bool;
    s.sfxOther = (j['so'] ?? true) as bool;
    s.vibration = (j['vb'] ?? true) as bool;
    s.sensitivity = ((j['se'] ?? 1.0) as num).toDouble();
    s.batterySaver = (j['bs'] ?? false) as bool;
    return s;
  }
}

// ---------------------------------------------------------------
// التخزين المحلي مع توقيع للحماية من التعديل
// ---------------------------------------------------------------

class Store {
  static final Store i = Store._();
  Store._();

  SharedPreferences? _sp;
  Profile profile = Profile();
  Settings settings = Settings();

  static const String _key = 'worm-game-local-key-v1-7c3f19';

  Future<void> init() async {
    try {
      _sp = await SharedPreferences.getInstance();
    } catch (_) {
      _sp = null;
    }
    final j = _sp?.getString('p');
    final s = _sp?.getString('ps');
    if (j != null && s == _sig(j)) {
      try {
        profile = Profile.fromJson(
            jsonDecode(utf8.decode(base64.decode(j))) as Map<String, dynamic>);
      } catch (_) {
        profile = Profile();
      }
    }
    final st = _sp?.getString('settings');
    if (st != null) {
      try {
        settings = Settings.fromJson(jsonDecode(st) as Map<String, dynamic>);
      } catch (_) {
        settings = Settings();
      }
    }
    profile.ensureDay(_day(DateTime.now()));
    saveProfile();
  }

  String _sig(String s) =>
      Hmac(sha256, utf8.encode(_key)).convert(utf8.encode(s)).toString();

  String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  void saveProfile() {
    final j = base64.encode(utf8.encode(jsonEncode(profile.toJson())));
    _sp?.setString('p', j);
    _sp?.setString('ps', _sig(j));
  }

  void saveSettings() {
    _sp?.setString('settings', jsonEncode(settings.toJson()));
  }

  /// مكافأة الدخول اليومي (تزيد مع الأيام المتتالية). ترجع 0 إذا أخذها اليوم.
  double claimDaily() {
    final now = DateTime.now();
    final today = _day(now);
    if (profile.lastDaily == today) return 0;
    final y = _day(now.subtract(const Duration(days: 1)));
    profile.loginStreak = profile.lastDaily == y ? profile.loginStreak + 1 : 1;
    profile.lastDaily = today;
    final r = 0.5 * math.min(profile.loginStreak, 7);
    profile.points += r;
    saveProfile();
    return r;
  }

  /// تسجيل نتيجة مباراة (ما عدا وضع التدريب).
  MatchReward recordMatch(MatchResult r) {
    final p = profile;
    final rw = MatchReward();
    rw.levelBefore = p.level;
    p.ensureDay(_day(DateTime.now()));

    p.matches++;
    p.kills += r.kills;
    p.deaths += r.deaths;
    p.fruits += r.fruits;

    if (r.won) {
      p.wins++;
      p.winStreak++;
      if (p.winStreak > p.bestWinStreak) p.bestWinStreak = p.winStreak;
      // الفوز ضد لاعبين حقيقيين بنقاط أكثر
      rw.gained = r.otherHumans > 0 ? 2.0 : 1.0;
    } else {
      p.winStreak = 0;
      rw.gained = 0.2; // تقدم صغير حتى مع الخسارة
    }

    r.opponents.forEach((name, level) {
      final f = p.friends[name] ?? <String, dynamic>{'level': level, 'games': 0};
      f['level'] = level;
      f['games'] = ((f['games'] ?? 0) as int) + 1;
      p.friends[name] = f;
    });

    // المهام اليومية
    for (int i = 0; i < 3; i++) {
      if (p.missionDone[i] == 1) continue;
      final def = kMissions[p.missionIds[i]];
      int add = 0;
      switch (def.type) {
        case 'fruit':
          add = r.fruits;
          break;
        case 'kill':
          add = r.kills;
          break;
        case 'win':
          add = r.won ? 1 : 0;
          break;
        default:
          add = 1;
      }
      p.missionProg[i] += add;
      if (p.missionProg[i] >= def.target) {
        p.missionDone[i] = 1;
        rw.bonus += def.reward;
        rw.missions.add(def.title);
      }
    }

    p.points = math.min(2000.0, p.points + rw.gained);

    // الإنجازات
    for (final a in kAchievements) {
      if (!p.ach.contains(a.id) && a.test(p, r)) {
        p.ach.add(a.id);
        rw.bonus += 0.5;
        rw.achievements.add(a.title);
      }
    }
    p.points = math.min(2000.0, p.points + rw.bonus);

    rw.levelAfter = p.level;
    saveProfile();
    return rw;
  }
}
