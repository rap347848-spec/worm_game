import 'package:audioplayers/audioplayers.dart';

/// أصوات ناعمة وخفيفة. لا نهيّئ شيئاً عند تشغيل التطبيق (حتى لا يعلق)،
/// وتُنشأ المشغّلات عند أول استخدام، وأي عطل في الصوت لا يوقف اللعبة.
class Sfx {
  static final Sfx i = Sfx._();
  Sfx._();

  final Map<String, AudioPlayer> _p = {};
  bool disabled = false;
  int _fails = 0;

  Future<void> init() async {}

  void play(String name) {
    if (disabled) return;
    _play(name);
  }

  Future<void> _play(String name) async {
    try {
      var p = _p[name];
      if (p == null) {
        p = AudioPlayer();
        _p[name] = p;
      }
      await p
          .play(AssetSource('sfx/$name.wav'))
          .timeout(const Duration(seconds: 2));
      _fails = 0;
    } catch (_) {
      _fails++;
      if (_fails > 5) disabled = true;
    }
  }
}
