import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/roles.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'game.dart';

Future<void> openGameLog(BuildContext context, String id) async {
  final app = context.read<AppState>();
  try {
    final g = Map<String, dynamic>.from(await app.api.get('/games/$id'));
    if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameLogScreen(g)));
  } on ApiError catch (e) {
    app.toast(e.message);
  }
}

void openLiveLog(BuildContext context) {
  final app = context.read<AppState>();
  final s = app.s!;
  final all = (s['allRoles'] as Map?)?.cast<String, dynamic>();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => GameLogScreen({
      'num': null,
      'code': s['code'],
      'players': app.players.where((p) => p['playing'] == true).map((p) => {...p, 'role': all?[p['id']]}).toList(),
      'winner': s['winner'],
      'log': s['log'],
      'live': true,
    }),
  ));
}

class GameLogScreen extends StatelessWidget {
  final Map<String, dynamic> g;
  const GameLogScreen(this.g, {super.key});

  static (String, String, String?) line(Map e) => switch (e['t']) {
        'vote' => ('🗳️', '${e['name']} طلع تصويت${e['host'] == true ? ' · صار الهوست' : ''}', e['team']),
        'kill' => ('🔪', '${e['name']} انغتل', e['team']),
        'saved' => ('🛡️', 'بنت الصالحين حمت حدا وما حدا مات', null),
        'snipe' => ('🎯', '${e['name']} انقنص', e['team']),
        'sniper' => ('💥', '${e['name']} طلع مع اللي قنصه', e['team']),
        'silence' => ('🤐', '${e['name']} انسكّت', null),
        'pull' => ('⛓️', '${e['name']} سحب ${e['tname']} معه', e['team']),
        'host' => ('🎙️', '${e['name']} صار الهوست', null),
        'calm' => ('🌙', 'ليلة هادية… ما صار إشي', null),
        _ => ('•', '', null),
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final players = ((g['players'] as List?) ?? []).cast<Map>();
    final withRoles = players.where((p) => p['role'] != null).toList();
    final n = withRoles.isNotEmpty ? withRoles.length : players.length;
    final meta = [
      g['num'] != null ? 'لعبة #${g['num']}' : 'اللعبة الحالية',
      'غرفة ${g['code']}',
      '$n لاعبين',
      if (g['endedAt'] != null) ago(g['endedAt']),
    ].join(' · ');

    final items = <Widget>[];
    String lastHd = '';
    for (final e in ((g['log'] as List?) ?? []).cast<Map>()) {
      final hd = e['night'] != null ? 'الليلة ${e['night']}' : 'النهار ${e['day'] ?? 1}';
      if (hd != lastHd) {
        items.add(Padding(padding: const EdgeInsets.only(top: 6), child: Text(hd, style: lalezar(19, C.gold2))));
        lastHd = hd;
      }
      final (i, t, team) = line(e);
      if (t.isEmpty) continue;
      items.add(Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x14FFFFFF), border: Border.all(color: C.line)),
          child: Text(i, style: const TextStyle(fontSize: 17)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(t, style: tsBold.copyWith(fontSize: 14.5))),
        if (team != null) Tag(kTeamName[team]!, team),
      ]));
    }

    return AppPage(
      title: 'سجل اللعبة',
      children: [
        Text(meta, style: tsMuted),
        if (g['winner'] != null) WinnerBanner(g['winner'] == 'mafia', size: 30),
        Panel(children: items.isEmpty ? [const Empty('لسا ما صار إشي')] : items),
        if (withRoles.isNotEmpty)
          Panel(children: [
            Text('🃏 كروت الكل', style: lalezar(22)),
            ...withRoles.map((p) => Opacity(
                  opacity: p['won'] == false && g['winner'] != null ? .55 : 1,
                  child: Row(children: [
                    Avatar(p['avatar'], p['name'], size: 34),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${p['name']}', style: tsBold)),
                    Tag('${role(p['role']).icon} ${role(p['role']).name}', p['won'] == true ? 'gold' : role(p['role']).team),
                  ]),
                )),
          ]),
        if (g['live'] != true && app.s != null && app.s!['phase'] == 'ended' && app.isLeader)
          GoldButton('جولة جديدة', onTap: () => app.emit('reset')),
      ],
    );
  }
}
