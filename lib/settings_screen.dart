import 'package:flutter/material.dart';
import 'progress.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Settings s = Store.i.settings;

  void _save() {
    Store.i.saveSettings();
    setState(() {});
  }

  Widget _sw(String title, String sub, bool v, void Function(bool) f) =>
      SwitchListTile(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        value: v,
        onChanged: (x) {
          f(x);
          _save();
        },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B2A3A), Color(0xFF16526B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      _sw('صوت الأكل', 'تشغيل أو كتم صوت الأكل لكل الدود', s.eatAll,
                          (v) => s.eatAll = v),
                      _sw('صوت أكل دودتي', 'يعمل فقط عند تشغيل صوت الأكل',
                          s.eatMine, (v) => s.eatMine = v),
                      _sw('صوت أكل الخصوم', 'يعمل فقط عند تشغيل صوت الأكل',
                          s.eatOthers, (v) => s.eatOthers = v),
                      _sw('أصوات القتل والموت والمستوى', 'نغمات ناعمة قصيرة',
                          s.sfxOther, (v) => s.sfxOther = v),
                      _sw('الاهتزاز', 'اهتزاز خفيف عند القتل والموت', s.vibration,
                          (v) => s.vibration = v),
                      _sw('توفير البطارية', 'يقلل التوهج والمؤثرات للهواتف الضعيفة',
                          s.batterySaver, (v) => s.batterySaver = v),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            const Text('حساسية اللمس',
                                style: TextStyle(color: Colors.white)),
                            Slider(
                              value: s.sensitivity,
                              min: 0.5,
                              max: 2.0,
                              divisions: 6,
                              label: s.sensitivity.toStringAsFixed(2),
                              onChanged: (v) {
                                s.sensitivity = v;
                                _save();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
