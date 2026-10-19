import 'package:flutter/material.dart';
import 'models.dart';
import 'progress.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Store.i.profile;
    final lv = p.level;
    final tier = tierOf(lv);
    final gc = kGlowColors[tier];
    final prog = levelProgress(p.points);
    final next = lv >= 100 ? null : pointsNeeded(lv + 1);

    final friends = p.friends.entries.toList()
      ..sort((a, b) =>
          ((b.value['level'] ?? 0) as int).compareTo((a.value['level'] ?? 0) as int));

    Widget section(String title, List<Widget> children) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        );

    Widget stat(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                  child: Text(k, style: const TextStyle(color: Colors.white70))),
              Text(v, style: const TextStyle(color: Colors.white)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
          title: const Text('الملف الشخصي'), backgroundColor: Colors.transparent),
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
              padding: const EdgeInsets.fromLTRB(14, 46, 14, 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: gc, width: 2),
                        boxShadow: [
                          BoxShadow(color: gc.withAlpha(140), blurRadius: 14)
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(p.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold)),
                          Text('${kTitles[tier]} · المستوى $lv',
                              style: TextStyle(
                                  color: gc,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                              value: prog, minHeight: 8, color: gc),
                          const SizedBox(height: 6),
                          Text(
                              next == null
                                  ? 'وصلت لأعلى مستوى 👑'
                                  : 'النقاط ${p.points.toStringAsFixed(1)} / ${next.toStringAsFixed(0)} للمستوى التالي',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    section('إحصائياتك', [
                      stat('الانتصارات', '${p.wins}'),
                      stat('المباريات', '${p.matches}'),
                      stat('القتلات', '${p.kills}'),
                      stat('الموتات', '${p.deaths}'),
                      stat('الفواكه المأكولة', '${p.fruits}'),
                      stat('أفضل سلسلة انتصارات', '${p.bestWinStreak}'),
                      stat('أيام الدخول المتتالية', '${p.loginStreak}'),
                    ]),
                    section('مهام اليوم', [
                      for (int i = 0; i < p.missionIds.length; i++)
                        _mission(p, i),
                    ]),
                    section('الإنجازات (${p.ach.length}/${kAchievements.length})', [
                      for (final a in kAchievements)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Text(p.ach.contains(a.id) ? '🏅' : '🔒',
                                  style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.title,
                                        style: TextStyle(
                                            color: p.ach.contains(a.id)
                                                ? Colors.white
                                                : Colors.white54,
                                            fontWeight: FontWeight.bold)),
                                    Text(a.desc,
                                        style: const TextStyle(
                                            color: Colors.white54, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ]),
                    section('لاعبون التقيت بهم', [
                      if (friends.isEmpty)
                        const Text('العب مع أصدقاء عبر البلوتوث لتظهر أسماؤهم هنا.',
                            style: TextStyle(color: Colors.white54)),
                      for (final f in friends)
                        stat('${f.key}  (${f.value['games']} مباريات)',
                            'مستوى ${f.value['level']}'),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mission(Profile p, int i) {
    final def = kMissions[p.missionIds[i]];
    final done = p.missionDone[i] == 1;
    final prog = p.missionProg[i].clamp(0, def.target);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${done ? '✅ ' : ''}${def.title}',
                    style: const TextStyle(color: Colors.white)),
              ),
              Text('+${def.reward.toStringAsFixed(0)} نقطة',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: prog / def.target, minHeight: 5),
        ],
      ),
    );
  }
}
