import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_state.dart';
import '../core/config.dart';
import '../core/roles.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'gamelog.dart';
import 'shell.dart';

/* =====================================================================
   شاشة اللعبة: بتتبدّل حسب حالة الغرفة اللي بتوصل من السيرفر
   ===================================================================== */
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  String lastScr = '';
  bool cardFlipped = false;
  bool resFlipped = false;
  int resFlipNo = -1;
  String? nightSel;
  int nightSelNo = -1;
  String? pullSel;
  String? outType; // انغتلت/انقنصت (بعد الصبح)

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s!;
    final scr = app.gameScreen;
    if (scr != lastScr) {
      if (scr == 'card') cardFlipped = false;
      lastScr = scr;
    }
    if (resFlipNo != s['nightNo']) {
      resFlipped = false;
      resFlipNo = s['nightNo'];
    }
    final morning = s['morning'] as Map?;
    final showMorning = morning != null && s['phase'] != 'lobby' && (morning['no'] as num) > app.morningSeen;
    final hostBar = app.isController && !showMorning;

    final Widget page = switch (scr) {
      'lobby' => LobbyView(app),
      'card' => _card(app),
      'night' => _night(app),
      'nightRes' => _nightRes(app),
      'pull' => _pull(app),
      'gameover' => GameOverView(app),
      _ => BoardView(app),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) async {
        if (did) return;
        if (s['phase'] == 'lobby' && await confirmDialog(context, 'بدك تطلع من الغرفة؟')) app.leaveRoom();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: Stack(children: [
          Positioned.fill(
            child: Bg(
              night: scr == 'night' || scr == 'nightRes' || (scr == 'board' && s['stage'] == 'night'),
              child: SafeArea(
                bottom: !hostBar,
                child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(scr), child: page)),
              ),
            ),
          ),
          if (showMorning) Positioned.fill(child: _morning(app, morning)),
          if (outType != null) Positioned.fill(child: _out(app)),
          if (!app.connected) const Positioned(top: 0, left: 0, right: 0, child: _Offline()),
        ]),
        bottomNavigationBar: hostBar ? HostBar(app) : null,
      ),
    );
  }

  /* ---------- الكرت ---------- */
  Widget _card(AppState app) {
    final s = app.s!;
    final me = app.meState;
    final r = me['role'] as String;
    final mates = me['mates'] as List?;
    final silenced = (s['silenced'] as Map?)?['id'] == app.myId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 848 / 1264,
              child: FlipCard(
                flipped: cardFlipped,
                onTap: () {
                  app.vibrate();
                  setState(() => cardFlipped = !cardFlipped);
                },
                front: RoleCard(r, app.meP?['name'] ?? ''),
                back: const CardBack(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Hint(cardFlipped ? 'اضغط مرة ثانية لتخبّيه' : '👆 اضغط على الكرت لتقلبه', calm: cardFlipped),
        if (cardFlipped && mates != null) ...[const SizedBox(height: 8), MatesBox(mates)],
        if (silenced) ...[
          const SizedBox(height: 8),
          const RedChip('🤐 إنت مسكّت اليوم — ممنوع تحكي'),
        ],
        const SizedBox(height: 10),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: SurrenderButton(onConfirm: () => app.emit('surrender'))),
      ]),
    );
  }

  /* ---------- الليل ---------- */
  String _instruction(AppState app) {
    final r = app.meState['role'];
    final n = app.night!;
    if (n['killer'] == true) {
      return r != 'mafiaSheikh' ? 'شيخكم طالع — اختاروا مين تغتالوا الليلة (الأكثرية بتقرر)' : 'اختار مين بدكم تغتالوا الليلة';
    }
    return switch (r) {
      'mafiaGirl' => 'اقترحي على شيخ المافيا مين تغتالوا',
      'mafia' => 'اقترح على شيخ المافيا مين تغتالوا',
      'mafiaBoy' => 'اختار مين بدك تسكّته بكرة',
      'doctor' => 'اختاري مين بدك تحمي الليلة (بتقدري تحمي حالك)',
      'sniper' => n['bullet'] == true ? 'اختار مين بدك تقنص (معك طلقة وحدة) — أو ولا حدا' : 'طلقتك خلصت — مين بتشك إنه مافيا؟',
      'townSheikh' => 'اختار مين بدك تسأل عنه',
      _ => 'مين بتشك إنه مافيا؟',
    };
  }

  Widget _nightTop(AppState app) {
    final p = (app.s!['progress'] as Map?) ?? {'done': 0, 'total': 0};
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      GoldChip('🌙 الليلة ${app.s!['nightNo']}'),
      GreyChip('اختاروا ${p['done']} من ${p['total']}'),
    ]);
  }

  Widget _night(AppState app) {
    final s = app.s!;
    if (nightSelNo != s['nightNo']) {
      nightSel = null;
      nightSelNo = s['nightNo'];
    }
    final n = app.night!;
    final sug = (n['suggest'] as List?) ?? [];
    final votes = <String, int>{};
    for (final x in sug) {
      votes[x['to']] = (votes[x['to']] ?? 0) + 1;
    }
    final canSelf = app.meState['role'] == 'doctor';
    final tiles = <Widget>[
      for (final p in app.players.where((p) => p['playing'] == true))
        () {
          final out = p['surrendered'] == true, self = p['id'] == app.myId;
          final v = votes[p['id']] ?? 0;
          return PlayerTile(
            p,
            sub: out ? 'طالع' : self ? 'إنت' : v > 0 ? '$v ${v > 1 ? 'أصوات' : 'صوت'}' : 'لاعب',
            subRed: v > 0,
            selected: nightSel == p['id'],
            disabled: out || (self && !canSelf),
            onTap: () {
              app.vibrate();
              setState(() => nightSel = p['id']);
            },
          );
        }(),
      PlayerTile(
        const {'name': 'ولا حدا'},
        none: true,
        sub: 'تخطّي الليلة',
        selected: nightSel == 'none',
        onTap: () {
          app.vibrate();
          setState(() => nightSel = 'none');
        },
      ),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), children: [
      _nightTop(app),
      const SizedBox(height: 24),
      const GoldTitle('🌙 الليل — اختار لاعب', size: 30),
      const SizedBox(height: 8),
      Text(_instruction(app), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: C.text)),
      if (sug.isNotEmpty) ...[
        const SizedBox(height: 10),
        RedChip('🤝 اقتراحات جماعتك: ${sug.map((x) => '${x['from']} ← ${app.pById(x['to'])?['name'] ?? '؟'}').join(' · ')}'),
      ],
      const SizedBox(height: 16),
      Grid2(tiles, cols: 3),
      const SizedBox(height: 18),
      GoldButton('تأكيد',
          onTap: nightSel == null
              ? null
              : () {
                  app.emit('pick', {'target': nightSel == 'none' ? null : nightSel});
                  app.vibrate(2);
                }),
      const SizedBox(height: 10),
      const Text('خلّي شاشتك لحالك 🤫', textAlign: TextAlign.center, style: tsMuted),
    ]);
  }

  Widget _nightRes(AppState app) {
    final res = (app.night!['result'] as Map?) ?? {'kind': 'chose'};
    final t = app.pById(res['target']);
    final who = ((app.s!['progress'] as Map?)?['who'] as List?)?.toSet() ?? {};
    final Widget front = res['kind'] == 'ask'
        ? ResultFace(children: [
            Text(res['answer'] == 'up' ? '👍' : '👎', style: const TextStyle(fontSize: 90)),
            Avatar(t?['avatar'], res['name'], size: 64),
            Text('${res['name']}', style: lalezar(26, C.text)),
            Text(res['answer'] == 'up' ? 'صالح' : 'مافيا!', style: lalezar(24, res['answer'] == 'up' ? C.green : C.red)),
          ])
        : ResultFace(children: [
            const Text('🌙', style: TextStyle(fontSize: 64)),
            t != null ? Avatar(t['avatar'], t['name'], size: 64) : const Text('🚫', style: TextStyle(fontSize: 48)),
            Text('اخترت: ${t != null ? t['name'] : 'ولا حدا'}', textAlign: TextAlign.center, style: lalezar(24, C.text)),
            const Text('اختيارك انحفظ 🤫', style: tsMuted),
          ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(children: [
        _nightTop(app),
        const SizedBox(height: 18),
        GoldTitle(res['kind'] == 'ask' ? 'جواب سؤالك' : 'اضغط على الكرت', size: 28),
        const SizedBox(height: 10),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 848 / 1264,
              child: FlipCard(
                flipped: resFlipped,
                onTap: () {
                  app.vibrate();
                  setState(() => resFlipped = !resFlipped);
                },
                front: front,
                back: const CardBack(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Hint(resFlipped ? 'اضغط مرة ثانية لتخبّيه' : '👆 اضغط على الكرت لتقلبه', calm: resFlipped),
        const SizedBox(height: 6),
        const Text('استنى الصبح…', style: TextStyle(fontWeight: FontWeight.w800, color: C.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: app.alive
              .map((p) => Stack(clipBehavior: Clip.none, children: [
                    Opacity(opacity: who.contains(p['id']) ? 1 : .45, child: Avatar(p['avatar'], p['name'], size: 38)),
                    if (who.contains(p['id']))
                      const Positioned(
                          bottom: -2,
                          right: -2,
                          child: CircleAvatar(
                              radius: 8,
                              backgroundColor: C.gold,
                              child: Text('✓', style: TextStyle(fontSize: 10, color: C.dark, fontWeight: FontWeight.w900)))),
                  ]))
              .toList(),
        ),
      ]),
    );
  }

  /* ---------- ولد الصالحين ---------- */
  Widget _pull(AppState app) => ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 24), children: [
        const Text('⛓️', textAlign: TextAlign.center, style: TextStyle(fontSize: 46)),
        const GoldTitle('إنت طالع… بس مش لحالك!', size: 28),
        const Sub('اختار لاعب يطلع معك من اللعبة'),
        const SizedBox(height: 16),
        Grid2(
          app.alive
              .map<Widget>((p) => PlayerTile(p, sub: 'لاعب', green: true, selected: pullSel == p['id'], onTap: () => setState(() => pullSel = p['id'])))
              .toList(),
          cols: 3,
        ),
        const SizedBox(height: 18),
        GoldButton('اسحبه معي',
            onTap: pullSel == null
                ? null
                : () async {
                    if (await confirmDialog(context, 'متأكد بدك تسحب ${app.pById(pullSel)?['name']} معك؟')) {
                      app.emit('pull', pullSel);
                      pullSel = null;
                    }
                  }),
        TextBtn('ما بدي أسحب حدا', () async {
          if (await confirmDialog(context, 'أكيد ما بدك تسحب حدا؟')) app.emit('pull', null);
        }, color: C.muted),
      ]);

  /* ---------- الصبح ---------- */
  Widget _morning(AppState app, Map m) {
    final events = (m['events'] as List).cast<Map>();
    final iDied = events.where((e) => ['kill', 'snipe', 'sniper'].contains(e['t']) && e['pid'] == app.myId).firstOrNull;
    final me = app.meState;
    return Material(
      color: const Color(0xF0060102),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
              const Text('☀️', textAlign: TextAlign.center, style: TextStyle(fontSize: 56)),
              const GoldTitle('صباح الخير'),
              Sub('الليلة ${m['no']}'),
              const SizedBox(height: 14),
              ...gap(events.where((e) => e['t'] != 'sniper').map<Widget>((e) => MorningEvent(e, events, app)).toList(), 10),
              const SizedBox(height: 14),
              const Text('النقاش والتصويت بالإيد · اللي بيطلع بيكبس سلّم كرتك', textAlign: TextAlign.center, style: tsMuted),
              const SizedBox(height: 14),
              GoldButton(me['role'] != null && me['surrendered'] != true ? 'رجوع لكرتي' : 'تمام', onTap: () {
                app.markMorningSeen((m['no'] as num).toInt());
                if (iDied != null) setState(() => outType = iDied['t']);
              }),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _out(AppState app) {
    final r = app.meState['role'] as String? ?? 'citizen';
    return Material(
      color: const Color(0xF0060102),
      child: SafeArea(
        child: Center(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
            Center(
              child: SizedBox(
                width: 200,
                child: Stack(alignment: Alignment.center, children: [
                  ColorFiltered(
                    colorFilter: const ColorFilter.matrix([.33, .59, .11, 0, 0, .33, .59, .11, 0, 0, .33, .59, .11, 0, 0, 0, 0, 0, 1, 0]),
                    child: Image.asset(cardAsset(r)),
                  ),
                  Transform.rotate(
                    angle: -.25,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: C.red, width: 4), borderRadius: BorderRadius.circular(10)),
                      child: Text('طالع', style: lalezar(40, C.red)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            GoldTitle(outType == 'kill' ? '🔪 انغتلت الليلة' : '🎯 انقنصت'),
            const Sub('خلص دورك… بس فيك تضل تتفرج وما تحكي 🤫'),
            const SizedBox(height: 16),
            GoldButton('تفرّج على اللعبة', onTap: () => setState(() => outType = null)),
          ]),
        ),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline();
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xE6400A14), borderRadius: BorderRadius.circular(99), border: Border.all(color: C.red)),
          child: const Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: C.pink)),
            SizedBox(width: 8),
            Text('انقطع الاتصال… بنرجع نتصل', style: TextStyle(color: C.pink, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        ),
      );
}

/* =====================================================================
   الغرفة
   ===================================================================== */
class LobbyView extends StatefulWidget {
  final AppState app;
  const LobbyView(this.app, {super.key});
  @override
  State<LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends State<LobbyView> {
  List onlineFriends = [];
  Timer? t;

  @override
  void initState() {
    super.initState();
    loadFriends();
    t = Timer.periodic(const Duration(seconds: 10), (_) => loadFriends());
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Future<void> loadFriends() async {
    final app = widget.app;
    if (!app.loggedIn) return;
    try {
      final list = (await app.api.get('/friends') as List)
          .where((f) => f['online'] == true && !app.players.any((p) => p['uid'] == f['id']))
          .toList();
      if (mounted) setState(() => onlineFriends = list);
    } catch (_) {}
  }

  String get link => '$kServer/?room=${widget.app.s!['code']}';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s!;
    final fixed = s['hostMode'] == 'fixed';
    final players = app.players;
    final playing = math.max(0, players.length - (fixed ? 1 : 0));
    final size = (s['size'] as num).toInt();
    final roles = Map<String, dynamic>.from(s['roles']);
    final used = kSpecial.fold<int>(0, (a, k) => a + ((roles[k] as num?)?.toInt() ?? 0));
    final leader = app.isLeader;

    void setRoles({int? newSize, String? k, int d = 0, String? hostMode}) {
      var sz = size;
      var rs = roles.map((k, v) => MapEntry(k, (v as num).toInt()));
      if (newSize != null) {
        sz = newSize.clamp(3, 30);
        rs = defaultRoles(sz);
      } else if (k != null) {
        rs[k] = math.max(0, (rs[k] ?? 0) + d);
      }
      app.emit('settings', {'size': sz, 'roles': rs, 'hostMode': hostMode ?? s['hostMode']});
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: gap([
      Panel(red: true, cross: CrossAxisAlignment.center, children: [
        const Text('كود الغرفة', style: tsMuted),
        Directionality(textDirection: TextDirection.ltr, child: GoldTitle('${s['code']}', size: 64)),
        Row(children: [
          Expanded(
              child: SBtn('🔗 نسخ رابط الدعوة', onTap: () {
            Clipboard.setData(ClipboardData(text: link));
            app.toast('انسخ الرابط ✔️');
          })),
          const SizedBox(width: 8),
          Expanded(
              child: SBtn('📤 مشاركة',
                  onTap: () => SharePlus.instance.share(ShareParams(text: 'تعال العب مافيا! كود الغرفة ${s['code']}\n$link')))),
        ]),
      ]),
      Panel(children: [
        H2('اللاعبين', trailing: Text('$playing / $size', style: lalezar(20, C.gold2))),
        ...players.map((p) => Row(children: [
              Opacity(
                  opacity: p['online'] == true ? 1 : .45,
                  child: Avatar(p['avatar'], p['name'], size: 38, status: p['online'] == true ? 'on' : 'off')),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${p['name']}', style: tsBold),
                  if (p['id'] == app.myId) const TextSpan(text: ' (إنت)', style: tsMuted),
                ])),
              ),
              if (p['id'] == s['leaderId']) Tag(fixed ? '🎙️ الهوست' : '👑 الليدر', 'gold'),
              if (leader && p['id'] != app.myId)
                IconButton(
                    onPressed: () async {
                      if (await confirmDialog(context, 'تطلّع ${p['name']} من الغرفة؟')) app.emit('kick', p['id']);
                    },
                    icon: const Icon(Icons.close, color: C.pink, size: 20)),
            ])),
      ]),
      if (onlineFriends.isNotEmpty)
        Panel(children: [
          Text('📨 ادعي أصحابك', style: lalezar(22)),
          SizedBox(height: 168, child: ListView(scrollDirection: Axis.horizontal, children: onlineFriends.map<Widget>((f) => FriendCard(f)).toList())),
        ]),
      Panel(children: [
        Text('🃏 الكروت', style: lalezar(22)),
        _stepRow('👥 عدد اللاعبين', null, size, leader ? (d) => setRoles(newSize: size + d) : null),
        ...kSpecial.map((k) => _stepRow('${role(k).icon} ${role(k).name}', role(k).team, (roles[k] as num).toInt(), leader ? (d) => setRoles(k: k, d: d) : null)),
        _stepRow('${role('citizen').icon} ${role('citizen').name}', 'town', math.max(0, size - used), null),
      ]),
      Panel(children: [
        Text('🎙️ الهوست', style: lalezar(22)),
        HostOptions(s['hostMode'], leader ? (m) => setRoles(hostMode: m) : null),
      ]),
      if (leader)
        GoldButton('ابدأ اللعبة', onTap: playing == size ? () => app.emit('start') : null),
      Text(
        leader ? (playing < size ? 'ناقص ${size - playing} لاعب' : playing > size ? 'في ${playing - size} زيادة' : 'جاهزين! 🔥') : 'استنى الليدر يبدأ اللعبة…',
        textAlign: TextAlign.center,
        style: tsMuted.copyWith(fontSize: 15),
      ),
      GoldButton('اطلع من الغرفة', kind: BtnKind.dark, onTap: app.leaveRoom),
    ]));
  }

  Widget _stepRow(String name, String? team, int v, void Function(int)? onStep) {
    Widget b(String t, int d) => GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onStep!(d);
          },
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x14FFFFFF), border: Border.all(color: C.line2)),
            child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.gold, height: 1.1)),
          ),
        );
    return Row(children: [
      Expanded(
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
          Text(name, style: tsBold),
          if (team != null) Tag(team == 'mafia' ? 'مافيا' : 'مواطنين', team),
        ]),
      ),
      if (onStep != null) b('−', -1),
      SizedBox(width: 40, child: Text('$v', textAlign: TextAlign.center, style: lalezar(24))),
      if (onStep != null) b('+', 1),
    ]);
  }
}

/* =====================================================================
   اللي طالعين / الهوست
   ===================================================================== */
class BoardView extends StatelessWidget {
  final AppState app;
  const BoardView(this.app, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = app.s!;
    final night = s['stage'] == 'night';
    final all = (s['allRoles'] as Map?)?.cast<String, dynamic>();
    final picks = (s['allPicks'] as Map?)?.cast<String, dynamic>() ?? {};
    final who = ((s['progress'] as Map?)?['who'] as List?)?.toSet() ?? {};
    List<Widget> head;
    if (app.isHost) {
      head = [
        const Text('🎙️', textAlign: TextAlign.center, style: TextStyle(fontSize: 54)),
        const GoldTitle('إنت الهوست'),
        Sub(night ? 'الليلة ${s['nightNo']} — بتشوف مين اختار مين' : 'بتشوف كل الكروت. أدير اللعبة من الشريط تحت'),
      ];
    } else if (night) {
      head = [const Text('🌙', textAlign: TextAlign.center, style: TextStyle(fontSize: 64)), const GoldTitle('المدينة نايمة…'), const Sub('بنستنى الباقي يختاروا')];
    } else if (app.meState['role'] != null) {
      head = [
        const Text('🪦', textAlign: TextAlign.center, style: TextStyle(fontSize: 54)),
        const GoldTitle('إنت طالع'),
        const Sub('كمّل تفرّج على اللعبة… بس بدون ما تحكي 🤫'),
      ];
    } else {
      head = [const Text('👀', textAlign: TextAlign.center, style: TextStyle(fontSize: 54)), const GoldTitle('بتتفرّج')];
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: gap([
      Column(children: gap(head, 6)),
      Panel(children: [
        Text(all != null ? 'كروت الكل' : 'اللاعبين', style: lalezar(22)),
        ...app.players.where((p) => p['playing'] == true).map((p) {
          final r = all?[p['id']] as String?;
          final out = p['surrendered'] == true;
          String pick = '';
          if (night && all != null && !out) {
            final t = picks[p['id']] as String?;
            final tName = t == null ? 'ولا حدا' : '${app.pById(t)?['name'] ?? ''}';
            pick = picks.containsKey(p['id']) ? ' ← $tName' : ' …';
          } else if (night && !out && who.contains(p['id'])) {
            pick = ' ✓';
          }
          return Opacity(
            opacity: out ? .5 : 1,
            child: Row(children: [
              Avatar(p['avatar'], p['name'], size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${p['name']}', style: tsBold.copyWith(decoration: out ? TextDecoration.lineThrough : null)),
                  TextSpan(text: pick, style: tsMuted.copyWith(color: pick == ' ✓' ? C.gold : C.muted)),
                ])),
              ),
              if (r != null)
                Tag('${role(r).icon} ${role(r).name}', role(r).team)
              else if (p['team'] != null)
                Tag(kTeamName[p['team']]!, p['team']),
            ]),
          );
        }),
      ]),
      GoldButton('سجل اللعبة', icon: Icons.history, kind: BtnKind.dark, onTap: () => openLiveLog(context)),
      if (app.isLeader)
        GoldButton('أنهِ الجولة وارجع للغرفة', onTap: () async {
          if (await confirmDialog(context, 'متأكد بدك تنهي الجولة؟')) app.emit('reset');
        }),
      TextBtn('اطلع من الغرفة', () async {
        if (await confirmDialog(context, 'بدك تطلع من الغرفة؟')) app.leaveRoom();
      }),
    ]));
  }
}

/* =====================================================================
   نهاية اللعبة
   ===================================================================== */
class GameOverView extends StatelessWidget {
  final AppState app;
  const GameOverView(this.app, {super.key});
  static const awardsInfo = {'kills': ['🔪', 'أكثر واحد اغتال'], 'saves': ['🛡️', 'أحسن حماية'], 'snipe': ['🎯', 'قنصة اللعبة'], 'found': ['👳', 'كشف المافيا']};

  @override
  Widget build(BuildContext context) {
    final s = app.s!;
    final mw = s['winner'] == 'mafia';
    final all = (s['allRoles'] as Map?)?.cast<String, dynamic>() ?? {};
    final aw = (s['awards'] as List?) ?? [];
    final withRole = app.players.where((p) => all[p['id']] != null).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: gap([
      WinnerBanner(mw, sub: '${mw ? 'المافيا سيطروا على المدينة' : 'المدينة نضفت من المافيا'} · ${nightsTxt(s['nightNo'])}'),
      Panel(children: [
        Text('🃏 كروت الكل', style: lalezar(22)),
        Grid2(
          withRole.map<Widget>((p) {
            final r = all[p['id']] as String;
            final win = role(r).team == s['winner'];
            return MiniCard(r, p['name'], win: win);
          }).toList(),
          cols: 3,
          spacing: 8,
        ),
      ]),
      if (aw.isNotEmpty)
        Panel(children: [
          Text('🏅 أبطال اللعبة', style: lalezar(22)),
          ...aw.map((a) {
            final info = awardsInfo[a['k']] ?? ['🏅', ''];
            return Text.rich(TextSpan(children: [
              TextSpan(text: '${info[0]} ${info[1]}: '),
              TextSpan(text: '${a['name']}', style: const TextStyle(color: C.gold)),
              TextSpan(text: ' (${a['n']})', style: tsMuted),
            ]), style: tsBold);
          }),
        ]),
      if (app.isLeader)
        GoldButton('جولة جديدة', onTap: () => app.emit('reset'))
      else
        const Text('استنى الليدر يبلّش جولة جديدة…', textAlign: TextAlign.center, style: tsMuted),
      Row(children: [
        Expanded(
            child: GoldButton('سجل اللعبة',
                kind: BtnKind.dark, small: true, onTap: () => s['gameId'] != null ? openGameLog(context, s['gameId']) : openLiveLog(context))),
        const SizedBox(width: 10),
        Expanded(
            child: GoldButton('مشاركة النتيجة',
                kind: BtnKind.dark,
                small: true,
                onTap: () => SharePlus.instance.share(ShareParams(
                    text:
                        '${mw ? 'المافيا فازت 🔪' : 'الصالحين فازوا 🏆'} بلعبة مافيا! ${nightsTxt(s['nightNo'])} · ${app.players.where((p) => p['playing'] == true).length} لاعبين\n$kServer')))),
      ]),
      TextBtn('اطلع من الغرفة', app.leaveRoom),
    ]));
  }
}

/* =====================================================================
   شريط الهوست
   ===================================================================== */
class HostBar extends StatelessWidget {
  final AppState app;
  const HostBar(this.app, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = app.s!;
    final al = app.alive.length;
    String label;
    Widget? bar;
    Widget btn;
    if (s['stage'] == 'night') {
      final p = (s['progress'] as Map?) ?? {'done': 0, 'total': al};
      final done = (p['done'] as num).toInt(), total = (p['total'] as num).toInt();
      label = done >= total ? 'كلهم اختاروا ✓' : 'اختاروا $done من $total';
      bar = ProgressBar(total == 0 ? 0 : done / total, height: 5);
      btn = GoldButton(done >= total ? '☀️ طلّع الصبح' : 'أنهِ الليل', expand: false, small: true, kind: done >= total ? BtnKind.gold : BtnKind.dark, onTap: () async {
        if (done >= total || await confirmDialog(context, 'لسا ${total - done} ما اختاروا. ننهي الليل؟')) app.emit('endNight');
      });
    } else if (s['pendingPull'] != null) {
      label = '⛓️ ${s['pendingPull']} بختار مين يسحب معه…';
      btn = GoldButton('تخطّي', expand: false, small: true, kind: BtnKind.dark, onTap: () async {
        if (await confirmDialog(context, 'نتخطّى السحب؟')) app.emit('skipPull');
      });
    } else {
      label = 'الليلة ${(s['nightNo'] as num) + 1} · باقي $al لاعبين';
      btn = GoldButton('🌙 الليلة التالية', expand: false, small: true, onTap: () async {
        if (await confirmDialog(context, 'نبلّش الليل؟ كل اللاعبين رح يختاروا عتلفوناتهم')) app.emit('nextNight');
      });
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF22090F), Color(0xFF0D0306)]),
        border: Border(top: BorderSide(color: C.gold2, width: 1.5)),
        boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, -10))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Row(children: [
                  Icon(Icons.mic, color: C.gold, size: 16),
                  SizedBox(width: 4),
                  Text('أدوات الهوست', style: TextStyle(color: C.gold, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
                Text(label, style: tsMuted.copyWith(fontSize: 12.5)),
                if (bar != null) ...[const SizedBox(height: 4), bar],
              ]),
            ),
            const SizedBox(width: 10),
            btn,
          ]),
        ),
      ),
    );
  }
}

/* =====================================================================
   قطع اللعبة
   ===================================================================== */

// قلب الكرت (ثلاثي الأبعاد)
class FlipCard extends StatefulWidget {
  final bool flipped;
  final VoidCallback onTap;
  final Widget front, back;
  const FlipCard({super.key, required this.flipped, required this.onTap, required this.front, required this.back});
  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: widget.flipped ? 1 : 0);
  late final a = CurvedAnimation(parent: c, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack.flipped);

  @override
  void didUpdateWidget(FlipCard old) {
    super.didUpdateWidget(old);
    if (old.flipped != widget.flipped) widget.flipped ? c.forward() : c.reverse();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: a,
          builder: (context, _) {
            final angle = a.value * math.pi;
            final showFront = angle > math.pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0012)
                ..rotateY(angle),
              child: showFront ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: widget.front) : widget.back,
            );
          },
        ),
      );
}

class CardBack extends StatefulWidget {
  const CardBack({super.key});
  @override
  State<CardBack> createState() => _CardBackState();
}

class _CardBackState extends State<CardBack> with SingleTickerProviderStateMixin {
  late final glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  @override
  void dispose() {
    glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: glow,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: C.gold.withValues(alpha: .12 + .25 * glow.value), blurRadius: 8 + 20 * glow.value)],
          ),
          child: child,
        ),
        child: Image.asset('assets/cards/back.webp', fit: BoxFit.contain),
      );
}

// وجه الكرت مع اسم اللاعب بالخانة الفاضية
class RoleCard extends StatelessWidget {
  final String roleKey, name;
  const RoleCard(this.roleKey, this.name, {super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Stack(children: [
          Positioned.fill(child: Image.asset(cardAsset(roleKey), fit: BoxFit.contain)),
          Positioned(
            left: box.maxWidth * .33,
            width: box.maxWidth * .34,
            top: box.maxHeight * (kNameY[roleKey] ?? .6) - box.maxWidth * .04,
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: box.maxWidth * .044,
                  height: 1.2,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1))]),
            ),
          ),
        ]),
      );
}

class ResultFace extends StatelessWidget {
  final List<Widget> children;
  const ResultFace({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const RadialGradient(center: Alignment(0, -.5), radius: 1, colors: [Color(0xFF3A1240), Color(0xFF14081E), Color(0xFF07030C)]),
          border: Border.all(color: C.gold2, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x55F3C75A), blurRadius: 24)],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: gap(children, 10)),
        ),
      );
}

class MatesBox extends StatelessWidget {
  final List mates;
  const MatesBox(this.mates, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xD928040A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: C.red, width: 1.5),
          boxShadow: [BoxShadow(color: C.red.withValues(alpha: .35), blurRadius: 14)],
        ),
        child: mates.isEmpty
            ? const Text('🕶️ إنت المافيا الوحيد بهاي الجولة', textAlign: TextAlign.center, style: TextStyle(color: C.gold, fontWeight: FontWeight.w800))
            : Column(children: [
                const Text('🤝 جماعتك بالمافيا', style: TextStyle(color: C.gold, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: mates.map((m) {
                    final out = m['out'] == true;
                    return Opacity(
                      opacity: out ? .45 : 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                            color: const Color(0x24FF3B55), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0x8CFF3B55))),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${role(m['role']).icon} ${m['name']} '),
                            TextSpan(text: role(m['role']).name, style: const TextStyle(color: C.gold, fontSize: 12)),
                          ]),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, decoration: out ? TextDecoration.lineThrough : null),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ]),
      );
}

class Hint extends StatefulWidget {
  final String text;
  final bool calm;
  const Hint(this.text, {super.key, this.calm = false});
  @override
  State<Hint> createState() => _HintState();
}

class _HintState extends State<Hint> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.calm
      ? Text(widget.text, style: tsMuted)
      : FadeTransition(
          opacity: Tween(begin: 1.0, end: .55).animate(c),
          child: Text(widget.text, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800, fontSize: 15)),
        );
}

class SurrenderButton extends StatefulWidget {
  final VoidCallback onConfirm;
  const SurrenderButton({super.key, required this.onConfirm});
  @override
  State<SurrenderButton> createState() => _SurrenderButtonState();
}

class _SurrenderButtonState extends State<SurrenderButton> {
  bool confirm = false;
  Timer? t;
  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GoldButton(
        confirm ? 'متأكد؟ اضغط كمان مرة' : 'سلّم كرتك',
        fontSize: 25,
        kind: confirm ? BtnKind.danger : BtnKind.gold,
        onTap: () {
          if (!confirm) {
            HapticFeedback.mediumImpact();
            setState(() => confirm = true);
            t?.cancel();
            t = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => confirm = false);
            });
            return;
          }
          t?.cancel();
          setState(() => confirm = false);
          widget.onConfirm();
        },
      );
}

class PlayerTile extends StatelessWidget {
  final Map p;
  final String sub;
  final bool selected, disabled, none, green, subRed;
  final VoidCallback? onTap;
  const PlayerTile(this.p,
      {super.key, required this.sub, this.selected = false, this.disabled = false, this.none = false, this.green = false, this.subRed = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final accent = green ? C.green : C.gold;
    return Opacity(
      opacity: disabled ? .35 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: AnimatedScale(
          scale: selected ? 1.04 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xD91A101A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? accent : C.line, width: selected ? 2.5 : 1.5),
              boxShadow: selected ? [BoxShadow(color: accent.withValues(alpha: .35), blurRadius: 18)] : null,
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
                Center(
                  child: none
                      ? Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x0FFFFFFF)),
                          child: const Icon(Icons.block, color: C.gold, size: 34),
                        )
                      : Avatar(p['avatar'], p['name'], size: 58),
                ),
                const SizedBox(height: 6),
                Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: tsBold),
                Text(sub, textAlign: TextAlign.center, style: tsMuted.copyWith(fontSize: 11.5, color: subRed ? C.pink : C.muted)),
              ]),
              if (selected)
                PositionedDirectional(
                  top: -6,
                  end: -2,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: green ? null : C.goldGrad, color: green ? C.green : null),
                    child: const Text('✓', style: TextStyle(color: C.dark, fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class GoldChip extends StatelessWidget {
  final String text;
  const GoldChip(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(gradient: C.goldGrad, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: const TextStyle(color: C.dark, fontWeight: FontWeight.w900, fontSize: 13)),
      );
}

class GreyChip extends StatelessWidget {
  final String text;
  const GreyChip(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(99), border: Border.all(color: C.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: C.green)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      );
}

class RedChip extends StatelessWidget {
  final String text;
  const RedChip(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: const Color(0x26FF3B55), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x99FF3B55))),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFB3B4), fontWeight: FontWeight.w800, fontSize: 14)),
      );
}

class MiniCard extends StatelessWidget {
  final String roleKey;
  final String name;
  final bool win;
  const MiniCard(this.roleKey, this.name, {super.key, required this.win});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: win ? 1 : .55,
        child: Column(children: [
          Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            Image.asset(cardAsset(roleKey)),
            if (win) const Positioned(top: -12, child: Text('👑', style: TextStyle(fontSize: 22))),
          ]),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tsBold.copyWith(fontSize: 13)),
          Text(role(roleKey).name, style: tsMuted.copyWith(fontSize: 11)),
        ]),
      );
}

class WinnerBanner extends StatelessWidget {
  final bool mafia;
  final String? sub;
  final double size;
  const WinnerBanner(this.mafia, {super.key, this.sub, this.size = 38});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: RadialGradient(
            center: const Alignment(0, -1),
            radius: 1.2,
            colors: mafia ? const [Color(0x8CC80134), Color(0xE61E0408)] : const [Color(0x4D2EF08A), Color(0xE61E1404)],
          ),
          border: Border.all(color: mafia ? const Color(0xB3FF3B55) : C.gold2, width: 1.5),
          boxShadow: [BoxShadow(color: (mafia ? C.red : C.gold).withValues(alpha: .3), blurRadius: 40)],
        ),
        child: Column(children: [
          GoldTitle(mafia ? 'المافيا فازت! 🔪' : 'الصالحين فازوا! 🏆', size: size),
          if (sub != null) Text(sub!, textAlign: TextAlign.center, style: tsMuted),
        ]),
      );
}

class MorningEvent extends StatelessWidget {
  final Map e;
  final List<Map> events;
  final AppState app;
  const MorningEvent(this.e, this.events, this.app, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget av(String? id) {
      final p = app.pById(id);
      return Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: Avatar(p?['avatar'], p?['name'], size: 34));
    }

    Widget row(String icon, String text, {String? small, List<Widget> avs = const [], String? team, bool saved = false}) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: saved ? const Color(0x1A2EF08A) : const Color(0xCC1A0B10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: saved ? const Color(0x662EF08A) : C.line),
          ),
          child: Row(children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: tsBold),
                if (small != null) Text(small, style: tsMuted),
              ]),
            ),
            ...avs,
            if (team != null) ...[const SizedBox(width: 6), Tag(kTeamName[team]!, team)],
          ]),
        );

    switch (e['t']) {
      case 'kill':
        return row('🔪', '${e['name']} انغتل الليلة', avs: [av(e['pid'])], team: e['team']);
      case 'saved':
        return row('⚕️', 'المافيا حاولوا يغتالوا حدا… بس بنت الصالحين حمته!', small: 'ما حدا مات', saved: true);
      case 'snipe':
        final sn = events.where((x) => x['t'] == 'sniper').firstOrNull;
        if (sn != null) {
          return row('🎯', 'القناص قنص مواطن صالح… وطلعوا الاثنين',
              small: '${e['name']} و ${sn['name']}', avs: [av(e['pid']), av(sn['pid'])], team: 'town');
        }
        return row('🎯', '${e['name']} انقنص', avs: [av(e['pid'])], team: e['team']);
      case 'silence':
        return row('🤐', '${e['name']} مسكّت اليوم', small: 'ممنوع يحكي');
      case 'host':
        return row('🎙️', '${e['name']} صار الهوست');
      case 'calm':
        return row('🌙', 'ليلة هادية… ما صار إشي');
    }
    return const SizedBox.shrink();
  }
}
