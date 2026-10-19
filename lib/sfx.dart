import 'package:audioplayers/audioplayers.dart';

/// أصوات ناعمة وخفيفة: أكل، قتل، موت، رفع مستوى، قدرة.
class Sfx {
  static final Sfx i = Sfx._();
  Sfx._();

  final Map<String, AudioPlayer> _p = {};
  bool _ready = false;

  Future<void> init() async {
    try {
      for (final n in ['eat', 'eat2', 'kill', 'death', 'level', 'power']) {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        _p[n] = p;
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> play(String name) async {
    if (!_ready) return;
    try {
      final p = _p[name];
      if (p == null) return;
      await p.stop();
      await p.play(AssetSource('sfx/$name.wav'));
    } catch (_) {}
  }
}
