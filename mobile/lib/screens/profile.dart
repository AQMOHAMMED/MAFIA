import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/avatar_pick.dart';
import '../core/config.dart';
import '../core/roles.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'auth.dart';
import 'gamelog.dart';
import 'shell.dart';
import 'social.dart';

/* =====================================================================
   قطع مشتركة للبروفايلات
   ===================================================================== */
class ProfileHead extends StatelessWidget {
  final Map d;
  final bool crown;
  final (String, String)? status;
  const ProfileHead(this.d, {super.key, this.crown = false, this.status});
  @override
  Widget build(BuildContext context) {
    final s = d['stats'] as Map;
    return Column(children: gap([
      Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Avatar(d['avatar'], d['username'], size: 108),
        if (crown) const Positioned(top: -26, child: Text('👑', style: TextStyle(fontSize: 34))),
      ]),
      Column(children: [
        GoldTitle(d['username'], size: 30),
        if (status != null) Text('● ${status!.$2}', style: TextStyle(color: statusColor(status!.$1), fontWeight: FontWeight.w700)),
        Directionality(textDirection: TextDirection.ltr, child: Text('${d['friendCode']}', style: tsMuted.copyWith(letterSpacing: 1))),
      ]),
      Panel(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(child: Text('🎖️ ${d['title']}', style: tsBold.copyWith(color: C.gold))),
          Tag('المستوى ${d['level']}', 'mafia'),
        ]),
        ProgressBar((d['xp'] as num) / (d['next'] as num), height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('الخبرة (XP)', style: tsMuted),
          Text('${d['xp']} / ${d['next']}', style: tsMuted),
        ]),
      ]),
      Row(children: [
        Expanded(child: _counter('${s['games']}', 'لعبة', C.gold)),
        const SizedBox(width: 10),
        Expanded(child: _counter('${s['wins']}', 'فوز', C.green)),
        const SizedBox(width: 10),
        Expanded(child: _counter('${s['rate']}%', 'نسبة الفوز', C.gold)),
      ]),
    ], 10));
  }

  Widget _counter(String v, String l, Color c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xCC140709), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Column(children: [
          Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c, height: 1.2)),
          Text(l, style: tsMuted),
        ]),
      );
}

const _statTiles = [
  ('winsTown', '🛡️', 'فزت وأنا مواطن', 'g'), ('winsMafia', '🗡️', 'فزت وأنا مافيا', 'r'),
  ('saves', '⚕️', 'حميت صح وأنا بنت الصالحين', 'g'), ('snipeMafia', '🎯', 'قنصت مافيا وأنا القناص', 'g'),
  ('snipeTown', '⚠️', 'قنصت مواطن بالغلط', 'r'), ('kills', '🔪', 'اغتلت وأنا بالمافيا', 'r'),
  ('found', '👎', 'كشفت مافيا وأنا شيخ الصالحين', 'g'), ('silenced', '🤐', 'سكّت حدا وأنا ولد المافيا', 'r'),
  ('pulled', '⛓️', 'سحبت حدا معي وأنا ولد الصالحين', 'g'), ('votedOut', '🙌', 'طلعت تصويت', ''),
  ('killed', '🌙', 'انغتلت بالليل', ''), ('hosted', '🎙️', 'كنت الهوست', ''),
];

String _she(String x) {
  const r = [
    ('فزت', 'فاز'), ('حميت', 'حمى'), ('قنصت', 'قنص'), ('اغتلت', 'اغتال'), ('كشفت', 'كشف'), ('سحبت', 'سحب'),
    ('انغتلت', 'انغتل'), ('طلعت', 'طلع'), ('كنت', 'كان'), ('وأنا', 'وهو'), ('معي', 'معه'),
  ];
  for (final (a, b) in r) {
    x = x.replaceAll(a, b);
  }
  return x;
}

class StatTiles extends StatelessWidget {
  final Map<String, dynamic> s;
  final bool she;
  const StatTiles(this.s, {super.key, this.she = false});
  @override
  Widget build(BuildContext context) =>
      Grid2(_statTiles.map<Widget>((t) => StatTile('${s[t.$1] ?? 0}', she ? _she(t.$3) : t.$3, icon: t.$2, tone: t.$4)).toList());
}

class FavRole extends StatelessWidget {
  final Map? fav;
  final String label;
  const FavRole(this.fav, this.label, {super.key});
  @override
  Widget build(BuildContext context) {
    if (fav == null) return const SizedBox.shrink();
    final r = role(fav!['role']);
    return Panel(children: [
      H2('🃏 $label', trailing: Tag('${fav!['count']} مرة', 'mafia')),
      Row(children: [
        SizedBox(width: 90, child: Image.asset(cardAsset(fav!['role']))),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Tag('فريق ${r.mafia ? 'المافيا' : 'الصالحين'}', r.team),
            Text(r.name, style: lalezar(26)),
            Text('نسبة الفوز فيه ${fav!['rate']}%', style: tsMuted),
          ]),
        ),
      ]),
    ]);
  }
}

class GameRow extends StatelessWidget {
  final Map g;
  const GameRow(this.g, {super.key});
  @override
  Widget build(BuildContext context) {
    final r = g['role'] != null ? role(g['role']) : null;
    return Li(
      leading: Text(r?.icon ?? '🎙️', style: const TextStyle(fontSize: 26)),
      title: r?.name ?? 'كنت الهوست',
      titleTrail: Text('#${g['code']}', style: tsMuted),
      subtitle: '${shortDate(g['at'])} · ${g['players']} لاعبين · ${nightsTxt(g['nights'])} · ${g['winner'] == 'mafia' ? 'المافيا فازت' : 'الصالحين فازوا'}',
      trailing: r != null ? Tag(g['won'] == true ? 'فوز' : 'خسارة', g['won'] == true ? 'gold' : 'grey') : null,
      onTap: () => openGameLog(context, g['id']),
    );
  }
}

class RecentGames extends StatelessWidget {
  final List list;
  final bool all;
  const RecentGames(this.list, {super.key, this.all = false});
  @override
  Widget build(BuildContext context) => Panel(children: [
        H2('🕓 آخر الألعاب', trailing: all ? LinkBtn('كل ألعابي', () => push(context, const MyGamesScreen())) : null),
        list.isEmpty ? const Empty('لسا ما في ألعاب') : ListCol(list.map<Widget>((g) => GameRow(g)).toList()),
      ]);
}

/* =====================================================================
   حسابي
   ===================================================================== */
class ProfileTab extends StatefulWidget {
  final bool pushed;
  const ProfileTab({super.key, this.pushed = false});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map? d;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final app = context.read<AppState>();
    try {
      final r = await app.api.get('/profile');
      if (mounted) setState(() => d = r);
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final d = this.d;
    return AppPage(
      back: widget.pushed,
      onRefresh: load,
      actions: [IconBtn(Icons.settings, () async {
        await push(context, const SettingsScreen());
        if (mounted) load();
      })],
      children: d == null
          ? [const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator()))]
          : [
              ProfileHead(d, crown: d['rank'] != null && d['rank'] <= 10),
              Center(child: LinkBtn('👥 ${d['friends']} صديق', () => push(context, const FriendsTab()))),
              Row(children: [
                Expanded(
                    child: GoldButton('تعديل الحساب', icon: Icons.edit, small: true, onTap: () async {
                  await push(context, const SettingsScreen());
                  load();
                })),
                const SizedBox(width: 10),
                Expanded(
                    child: GoldButton('مشاركة', icon: Icons.share, small: true, kind: BtnKind.dark, onTap: () {
                  final s = d['stats'];
                  final code = app.me?['friendCode'];
                  SharePlus.instance.share(ShareParams(
                      text: 'بروفايلي بلعبة مافيا: ${s['games']} لعبة · ${s['rate']}% فوز. ضيفني: $code\n$kServer/?add=$code'));
                })),
              ]),
              Panel(children: [Text('📊 إحصائياتي', style: lalezar(22)), StatTiles(Map<String, dynamic>.from(d['stats']))]),
              FavRole(d['fav'], 'أكثر كرت طلعلي'),
              RecentGames(d['recent'] as List, all: true),
            ],
    );
  }
}

/* =====================================================================
   ألعابي
   ===================================================================== */
class MyGamesScreen extends StatefulWidget {
  const MyGamesScreen({super.key});
  @override
  State<MyGamesScreen> createState() => _MyGamesScreenState();
}

class _MyGamesScreenState extends State<MyGamesScreen> {
  List? data;
  String f = 'all';
  @override
  void initState() {
    super.initState();
    context.read<AppState>().api.get('/games').then((r) {
      if (mounted) setState(() => data = r);
    }).catchError((e) => context.read<AppState>().toast('$e'));
  }

  @override
  Widget build(BuildContext context) {
    final list = (data ?? []).where((g) {
      if (f == 'all') return true;
      if (f == 'won') return g['won'] == true;
      if (f == 'lost') return g['role'] != null && g['won'] != true;
      return g['role'] != null && role(g['role']).team == f;
    }).toList();
    return AppPage(title: 'ألعابي', children: [
      Chips(const [('all', 'الكل'), ('won', 'فزت'), ('lost', 'خسرت'), ('mafia', 'كنت مافيا'), ('town', 'كنت مواطن')], f, (v) => setState(() => f = v)),
      if (data == null)
        const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
      else if (list.isEmpty)
        const Empty('ما في ألعاب هون لسا')
      else
        ListCol(list.map<Widget>((g) => GameRow(g)).toList()),
    ]);
  }
}

/* =====================================================================
   لوحة الصدارة
   ===================================================================== */
class LeaderboardTab extends StatefulWidget {
  const LeaderboardTab({super.key});
  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  String scope = 'all', period = 'all', sort = 'rate';
  Map? d;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final app = context.read<AppState>();
    try {
      final r = await app.api.get('/leaderboard?scope=$scope&period=$period&sort=$sort');
      if (mounted) setState(() => d = r);
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  void set(void Function() f) {
    setState(f);
    load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final list = (d?['list'] as List?) ?? [];
    final mine = d?['mine'] as Map?;
    Widget pod(Map? p, int place) {
      if (p == null) return const Expanded(child: SizedBox());
      final medal = ['👑', '🥈', '🥉'][place - 1];
      return Expanded(
        child: GestureDetector(
          onTap: () => openUser(context, p['id']),
          child: Container(
            margin: EdgeInsets.only(top: place == 1 ? 0 : 26),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: place == 1 ? const [Color(0xFF4A3410), Color(0xFF1A0B04)] : const [Color(0xFF2A1218), Color(0xFF14060A)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: place == 1 ? C.gold : C.line2, width: place == 1 ? 2 : 1),
            ),
            child: Column(children: [
              Text(medal, style: const TextStyle(fontSize: 26)),
              Avatar(p['avatar'], p['username'], size: place == 1 ? 64 : 52),
              const SizedBox(height: 4),
              Text(p['username'], maxLines: 1, overflow: TextOverflow.ellipsis, style: tsBold.copyWith(fontSize: 14)),
              Text('${p['rate']}%', style: lalezar(24)),
              Text('${p['wins']} فوز', style: tsMuted),
            ]),
          ),
        ),
      );
    }

    return AppPage(
      back: false,
      title: '🏆 لوحة الصدارة',
      onRefresh: load,
      children: [
        Tabs(const [('all', 'الكل'), ('friends', 'أصدقائي')], scope, (v) {
          if (v == 'friends' && !app.loggedIn) return app.toast('سجّل دخول لتشوف أصحابك');
          set(() => scope = v);
        }),
        Chips(const [('week', 'هالأسبوع'), ('month', 'هالشهر'), ('all', 'كل الوقت')], period, (v) => set(() => period = v)),
        Chips(const [('rate', 'حسب نسبة الفوز'), ('wins', 'حسب عدد الفوز')], sort, (v) => set(() => sort = v)),
        if (d != null) Text('لازم تلعب ${d!['min']} ألعاب على الأقل لتدخل الترتيب', textAlign: TextAlign.center, style: tsMuted),
        if (d == null)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (list.isEmpty)
          const Empty('لسا ما حدا دخل الترتيب… العبوا أكثر! 🔥')
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            pod(list.length > 1 ? list[1] : null, 2),
            const SizedBox(width: 8),
            pod(list[0], 1),
            const SizedBox(width: 8),
            pod(list.length > 2 ? list[2] : null, 3),
          ]),
        if (list.length > 3)
          ListCol([
            for (var i = 3; i < list.length; i++)
              Li(
                leading: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 26, child: Text('${i + 1}', style: lalezar(20, C.gold2))),
                  Avatar(list[i]['avatar'], list[i]['username'], size: 40),
                ]),
                title: list[i]['username'],
                subtitle: 'عدد الألعاب ${list[i]['games']}',
                extra: Padding(padding: const EdgeInsets.only(top: 4), child: ProgressBar((list[i]['rate'] as num) / 100, height: 4)),
                trailing: _rate(list[i]),
                onTap: () => openUser(context, list[i]['id']),
              ),
          ]),
        if (mine != null)
          Li(
            highlight: true,
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              if (mine['rank'] != null) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: Text('#${mine['rank']}', style: lalezar(20))),
              Avatar(mine['avatar'], mine['username'], size: 40),
            ]),
            title: '${mine['username']} (إنت)',
            subtitle: mine['rank'] != null ? 'عدد الألعاب ${mine['games']}' : 'لعبت ${mine['games']} من ${d!['min']} لتدخل الترتيب',
            trailing: _rate(mine),
          ),
      ],
    );
  }

  Widget _rate(Map p) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text('${p['rate']}%', style: lalezar(22)),
        Text('${p['wins']} فوز', style: tsMuted.copyWith(fontSize: 11.5)),
      ]);
}

/* =====================================================================
   الإحصائيات
   ===================================================================== */
class StatsTab extends StatefulWidget {
  const StatsTab({super.key});
  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  String period = 'all';
  Map? d;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final app = context.read<AppState>();
    try {
      final r = await app.api.get('/stats?period=$period');
      if (mounted) setState(() => d = r);
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = this.d;
    final children = <Widget>[
      Chips(const [('week', 'هالأسبوع'), ('month', 'هالشهر'), ('all', 'كل الوقت')], period, (v) {
        setState(() => period = v);
        load();
      }),
    ];
    if (d == null) {
      children.add(const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())));
    } else {
      final s = Map<String, dynamic>.from(d['stats']);
      int n(String k) => (s[k] as num?)?.toInt() ?? 0;
      final days = (d['days'] as List).cast<Map>();
      final best = d['best'] as Map?;
      const outs = [('votedOut', 'تصويت', Color(0xFFF3C75A)), ('killed', 'اغتيال', Color(0xFFFF3B55)), ('sniped', 'قنص', Color(0xFFFF8D40)), ('pulledOut', 'سحب', Color(0xFF2EF08A))];
      final outTotal = outs.fold<int>(0, (a, o) => a + n(o.$1));
      final roles = Map<String, dynamic>.from(s['roles'] ?? {}), roleWins = Map<String, dynamic>.from(s['roleWins'] ?? {});
      children.addAll([
        Grid2([
          StatTile('${n('games')}', 'الألعاب'),
          StatTile('${n('wins')}', 'الفوز'),
          StatTile('${n('rate')}%', 'نسبة الفوز'),
          StatTile('${n('streak')}', 'أطول سلسلة فوز'),
        ], cols: 4, spacing: 8),
        Panel(children: [
          Text('فزت مع مين؟', style: lalezar(22)),
          Row(children: [
            SizedBox(width: 130, height: 130, child: CustomPaint(painter: _Donut(n('winsTown'), n('winsMafia')))),
            const SizedBox(width: 18),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _legend(C.green, 'مواطنين ${n('winsTown')}'),
              const SizedBox(height: 8),
              _legend(C.red, 'مافيا ${n('winsMafia')}'),
            ]),
          ]),
        ]),
        Panel(children: [
          Text('نسبة فوزي بكل دور', style: lalezar(22)),
          ...kAllRoles.map((r) {
            final c = (roles[r] as num?)?.toInt() ?? 0;
            final p = pct(roleWins[r] as num?, c);
            return Row(children: [
              SizedBox(width: 132, child: Text('${role(r).icon} ${role(r).name}', style: tsBold.copyWith(fontSize: 13))),
              Expanded(child: ProgressBar(p / 100, height: 8)),
              SizedBox(width: 44, child: Text(c > 0 ? '$p%' : '—', textAlign: TextAlign.end, style: tsBold.copyWith(color: C.gold, fontSize: 13))),
            ]);
          }),
        ]),
        Panel(children: [
          H2('أدائي آخر 30 يوم', trailing: const Text('الفوز التراكمي', style: tsMuted)),
          SizedBox(height: 110, child: CustomPaint(size: Size.infinite, painter: _Line(days))),
        ]),
        Grid2([
          StatTile('${pct(n('saves'), n('protects'))}%', 'دقة الحماية', icon: '⚕️', tone: 'g', note: '${n('saves')} من ${n('protects')} حماية صح'),
          StatTile('${pct(n('snipeMafia'), n('snipeMafia') + n('snipeTown'))}%', 'دقة القنص',
              icon: '🎯', tone: 'r', note: '${n('snipeMafia')} من ${n('snipeMafia') + n('snipeTown')} قنصة صح'),
        ]),
        Panel(children: [
          Text('كيف طلعت من اللعبة', style: lalezar(22)),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: outTotal == 0
                  ? Container(color: const Color(0x14FFFFFF))
                  : Row(children: [
                      for (final o in outs)
                        if (n(o.$1) > 0) Expanded(flex: n(o.$1), child: Container(color: o.$3)),
                    ]),
            ),
          ),
          Wrap(spacing: 14, runSpacing: 6, children: outs.map((o) => _legend(o.$3, '${o.$2} ${n(o.$1)}')).toList()),
        ]),
        if (best != null)
          Panel(children: [
            Text('أكثر لاعب بتفوز معه', style: lalezar(22)),
            Li(
              leading: Avatar(best['avatar'], best['username'], size: 50),
              title: best['username'],
              subtitle: 'فزتوا مع بعض ${best['together']} مرة',
              onTap: () => openUser(context, best['id']),
            ),
          ]),
      ]);
    }
    return AppPage(back: false, title: 'إحصائياتي', onRefresh: load, children: children);
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(t, style: tsBold.copyWith(fontSize: 13.5)),
      ]);
}

class _Donut extends CustomPainter {
  final int town, mafia;
  _Donut(this.town, this.mafia);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;
    canvas.drawCircle(c, r, p..color = const Color(0x14FFFFFF));
    final tot = town + mafia;
    if (tot > 0) {
      final tw = town / tot * math.pi * 2;
      canvas.drawArc(rect, -math.pi / 2, tw, false, p..color = C.green);
      canvas.drawArc(rect, -math.pi / 2 + tw, math.pi * 2 - tw, false, p..color = C.red);
    }
    void txt(String s, double dy, TextStyle st) {
      final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.rtl)..layout();
      tp.paint(canvas, c + Offset(-tp.width / 2, dy - tp.height / 2));
    }

    txt('$tot', -6, const TextStyle(fontFamily: 'Cairo', color: C.gold, fontSize: 26, fontWeight: FontWeight.w900));
    txt('فوز', 18, const TextStyle(fontFamily: 'Cairo', color: C.muted, fontSize: 12, fontWeight: FontWeight.w700));
  }

  @override
  bool shouldRepaint(_Donut o) => o.town != town || o.mafia != mafia;
}

class _Line extends CustomPainter {
  final List<Map> days;
  _Line(this.days);
  @override
  void paint(Canvas canvas, Size size) {
    var cum = 0;
    final pts = <int>[];
    for (final d in days) {
      cum += (d['wins'] as num).toInt();
      pts.add(cum);
    }
    final maxY = math.max(1, cum);
    final n = math.max(1, pts.length - 1);
    // من اليسار لليمين (الأقدم ← الأحدث)
    Offset at(int i) => Offset(i / n * size.width, size.height - 10 - pts[i] / maxY * (size.height - 20));
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < pts.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x26FF3B55));
    canvas.drawPath(
        line,
        Paint()
          ..color = C.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..maskFilter = null);
    for (var i = 0; i < pts.length; i++) {
      if ((days[i]['games'] as num) > 0) canvas.drawCircle(at(i), 3.5, Paint()..color = const Color(0xFFFFF0B0));
    }
  }

  @override
  bool shouldRepaint(_Line o) => true;
}

/* =====================================================================
   الإعدادات
   ===================================================================== */
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppState app = context.read<AppState>();
  late final user = TextEditingController(text: app.me!['username']);
  late final email = TextEditingController(text: app.me!['email']);
  final oldPw = TextEditingController(), newPw = TextEditingController();
  String? avatar;
  bool showPass = false;

  static const toggles = [('vibrate', '📳 الاهتزاز'), ('sounds', '🔊 الأصوات'), ('invites', '📨 إشعارات دعوات اللعب'), ('showOnline', '🟢 إظهار إني متصل للأصدقاء')];

  Future<void> save() async {
    try {
      final body = {'username': user.text, 'email': email.text, 'avatar': ?avatar};
      app.updateMe(Map<String, dynamic>.from(await app.api.put('/me', body)));
      app.toast('انحفظ ✔️');
      avatar = null;
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  Future<void> toggle(String k, bool v) async {
    try {
      app.updateMe(Map<String, dynamic>.from(await app.api.put('/me', {
        'settings': {k: v}
      })));
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  Future<void> changePass() async {
    try {
      await app.api.put('/me/password', {'old': oldPw.text, 'password': newPw.text});
      app.toast('تغيّرت كلمة السر ✔️');
      oldPw.clear();
      newPw.clear();
      setState(() => showPass = false);
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  Future<void> deleteAccount() async {
    final pw = await promptDialog(context, 'حذف الحساب نهائي وما بيرجع. اكتب كلمة السر للتأكيد:', password: true, ok: 'احذف');
    if (pw == null || pw.isEmpty) return;
    try {
      await app.api.delete('/me', {'password': pw});
      app.toast('انحذف الحساب');
      app.setAuth(null, null);
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    if (me == null) return const SizedBox();
    final st = app.settings;
    return AppPage(title: 'الإعدادات', children: [
      Panel(children: [
        Center(
          child: AvatarPicker(
            data: avatar,
            url: me['avatar'],
            name: me['username'],
            label: 'تغيير الصورة',
            onTap: () async {
              try {
                final a = await pickAvatar();
                if (a != null) setState(() => avatar = a);
              } catch (_) {
                app.toast('الصورة مش مدعومة');
              }
            },
          ),
        ),
        const Text('اسم اللاعب', style: tsMuted),
        Field(controller: user, hint: 'اسم اللاعب', maxLength: 20),
        const Text('البريد الإلكتروني', style: tsMuted),
        Field(controller: email, hint: 'البريد الإلكتروني', keyboard: TextInputType.emailAddress),
        GoldButton('حفظ', onTap: save),
      ]),
      ListCol(toggles
          .map<Widget>((t) => Li(
                title: t.$2,
                trailing: Switch(value: st[t.$1] != false, onChanged: (v) => toggle(t.$1, v)),
              ))
          .toList()),
      ListCol([
        Li(title: '🔑 تغيير كلمة السر', trailing: const Icon(Icons.chevron_left, color: C.muted), onTap: () => setState(() => showPass = !showPass)),
        const Li(title: '🌐 اللغة: العربية'),
        Li(title: '📜 شروط الاستخدام', trailing: const Icon(Icons.chevron_left, color: C.muted), onTap: () => showTerms(context)),
      ]),
      if (showPass)
        Panel(children: [
          Field(controller: oldPw, hint: 'كلمة السر الحالية', password: true),
          Field(controller: newPw, hint: 'كلمة السر الجديدة', password: true),
          GoldButton('غيّر كلمة السر', small: true, onTap: changePass),
        ]),
      TextBtn('تسجيل خروج', () async {
        if (await confirmDialog(context, 'بدك تسجّل خروج؟')) app.logout();
      }),
      TextBtn('حذف الحساب', deleteAccount, color: const Color(0xAAFF6A7A)),
    ]);
  }
}
