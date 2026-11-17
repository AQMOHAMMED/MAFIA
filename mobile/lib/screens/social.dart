import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/config.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'profile.dart';
import 'shell.dart';

(String, String) statusOf(Map f) {
  if (f['playing'] == true) return ('busy', 'بيلعب هلأ');
  if (f['online'] == true) return ('on', 'متصل الآن');
  return ('off', f['lastSeen'] != null ? 'آخر ظهور ${ago(f['lastSeen'])}' : 'مش متصل');
}

Color statusColor(String s) => s == 'on' ? C.green : s == 'busy' ? C.pink : C.muted;

Future<bool> sendRequest(BuildContext context, String to) async {
  final app = context.read<AppState>();
  try {
    final r = await app.api.post('/friends/request', {'to': to});
    app.toast(r['relation'] == 'friend' ? 'صرتوا أصحاب ✓' : 'انبعت طلب الصداقة ✓');
    return true;
  } on ApiError catch (e) {
    app.toast(e.message);
    return false;
  }
}

void openUser(BuildContext context, String id) {
  final app = context.read<AppState>();
  if (!app.loggedIn) return app.toast('سجّل دخول لتشوف البروفايلات');
  if (id == app.me!['id']) {
    push(context, const ProfileTab(pushed: true));
    return;
  }
  push(context, FriendProfile(id));
}

/* ============ الأصدقاء ============ */
class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});
  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  List data = [];
  bool loaded = false;
  String q = '';
  int tick = -1;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final app = context.read<AppState>();
    tick = app.friendsTick;
    try {
      final d = await app.api.get('/friends');
      if (mounted) setState(() => (data = d, loaded = true));
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (tick != app.friendsTick) WidgetsBinding.instance.addPostFrameCallback((_) => load());
    final list = data.where((f) => q.isEmpty || (f['username'] as String).toLowerCase().contains(q.toLowerCase())).toList();
    return AppPage(
      back: false,
      title: 'أصدقائي',
      onRefresh: load,
      actions: [IconBtn(Icons.person_add_alt_1, () => push(context, const RequestsScreen()), badge: (app.me?['requests'] as num?)?.toInt() ?? 0)],
      children: [
        Field(hint: 'دوّر بأصدقائك', icon: Icons.search, onChanged: (v) => setState(() => q = v.trim())),
        GoldButton('أضف صديق', icon: Icons.add, small: true, onTap: () => push(context, const AddFriendScreen())),
        if (!loaded)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else if (list.isEmpty)
          Empty(data.isEmpty ? 'لسا ما عندك أصحاب… اضغط "أضف صديق" ☝️' : 'ما لقينا حدا بهالاسم')
        else
          ListCol(list.map<Widget>((f) {
            final (cls, txt) = statusOf(f);
            return Li(
              leading: Avatar(f['avatar'], f['username'], size: 48, status: cls),
              title: f['username'],
              subtitle: txt,
              subColor: statusColor(cls),
              onTap: () => openUser(context, f['id']),
              trailing: SBtn('ادعيه', gold: true, onTap: () => inviteFriend(context, f['id'])),
            );
          }).toList()),
      ],
    );
  }
}

/* ============ إضافة صديق ============ */
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});
  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final q = TextEditingController();
  List? results;
  List recent = [];
  bool qr = false;

  @override
  void initState() {
    super.initState();
    loadRecent();
  }

  Future<void> loadRecent() async {
    try {
      final r = await context.read<AppState>().api.get('/recent-players');
      if (mounted) setState(() => recent = r);
    } catch (_) {}
  }

  Future<void> search() async {
    final app = context.read<AppState>();
    if (q.text.trim().isEmpty) return;
    try {
      final r = await app.api.get('/users/search?q=${Uri.encodeQueryComponent(q.text.trim())}');
      if (mounted) setState(() => results = r);
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  Widget relBtn(Map u, VoidCallback reload) {
    final app = context.read<AppState>();
    return switch (u['relation']) {
      'friend' => const Tag('صديق', 'grey'),
      'sent' => const Tag('تم الإرسال ✓', 'gold'),
      'received' => SBtn('قبول', gold: true, onTap: () async {
          try {
            await app.api.post('/friends/accept', {'from': u['id']});
            app.toast('صرتوا أصحاب ✓');
            reload();
          } on ApiError catch (e) {
            app.toast(e.message);
          }
        }),
      _ => SBtn('+ أضف', gold: true, onTap: () async {
          if (await sendRequest(context, u['id'])) reload();
        }),
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final code = app.me?['friendCode'] ?? '';
    final link = '$kServer/?add=$code';
    return AppPage(
      title: 'أضف صديق',
      children: [
        Row(children: [
          Expanded(child: Field(controller: q, hint: 'اكتب اسم اللاعب أو كوده', icon: Icons.search, onSubmitted: (_) => search(), action: TextInputAction.search)),
          const SizedBox(width: 8),
          SBtn('بحث', gold: true, onTap: search),
        ]),
        Panel(red: true, cross: CrossAxisAlignment.center, children: [
          const Text('كودي', style: tsMuted),
          Directionality(textDirection: TextDirection.ltr, child: GoldTitle(code, size: 34)),
          Row(children: [
            Expanded(
                child: SBtn('نسخ', icon: Icons.copy, onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              app.toast('انسخ الكود ✔️');
            })),
            const SizedBox(width: 8),
            Expanded(child: SBtn('مشاركة', icon: Icons.share, onTap: () => SharePlus.instance.share(ShareParams(text: 'ضيفني بلعبة مافيا! كودي $code\n$link')))),
          ]),
          SBtn(qr ? 'خبّي الـ QR' : 'اعرض الـ QR تبعي', icon: Icons.qr_code_2, onTap: () => setState(() => qr = !qr)),
          if (qr) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: link, size: 180, backgroundColor: Colors.white),
            ),
            const Text('صاحبك بيمسحه بكاميرا تلفونه وبيوصلك طلب صداقة', textAlign: TextAlign.center, style: tsMuted),
          ],
        ]),
        if (results != null) ...[
          H2('نتائج البحث'),
          results!.isEmpty
              ? const Empty('ما لقينا حدا')
              : ListCol(results!
                  .map<Widget>((u) => Li(
                        leading: Avatar(u['avatar'], u['username'], size: 46),
                        title: u['username'],
                        subtitle: '${u['games']} لعبة · ${u['rate']}% فوز',
                        onTap: () => openUser(context, u['id']),
                        trailing: relBtn(u, search),
                      ))
                  .toList()),
        ],
        if (recent.isNotEmpty) ...[
          H2('لعبت معهم مؤخراً'),
          ListCol(recent
              .map<Widget>((u) => Li(
                    leading: Avatar(u['avatar'], u['username'], size: 46),
                    title: u['username'],
                    onTap: () => openUser(context, u['id']),
                    trailing: relBtn(u, loadRecent),
                  ))
              .toList()),
        ],
      ],
    );
  }
}

/* ============ طلبات الصداقة ============ */
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  String tab = 'received';
  Map? d;
  final accepted = <String>{};
  int tick = -1;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final app = context.read<AppState>();
    tick = app.friendsTick;
    try {
      final r = await app.api.get('/friends/requests');
      if (mounted) setState(() => d = r);
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  Future<void> act(String path, Map body, [String? acceptedId]) async {
    final app = context.read<AppState>();
    try {
      await app.api.post(path, body);
      if (acceptedId != null) setState(() => accepted.add(acceptedId));
      await app.refreshMe();
      if (acceptedId == null) await load();
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (tick != app.friendsTick) WidgetsBinding.instance.addPostFrameCallback((_) => load());
    final rec = (d?['received'] as List?) ?? [], sent = (d?['sent'] as List?) ?? [];
    final list = tab == 'received' ? rec : sent;
    return AppPage(
      title: 'طلبات الصداقة',
      onRefresh: load,
      children: [
        Tabs([('received', 'وصلتني (${rec.length})'), ('sent', 'بعتها (${sent.length})')], tab, (v) => setState(() => tab = v)),
        if (d == null)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else if (list.isEmpty)
          Empty('ما في طلبات ${tab == 'received' ? 'جديدة' : 'مبعوتة'}', emoji: '✉️')
        else
          ListCol(list.map<Widget>((u) {
            if (tab == 'sent') {
              return Li(
                leading: Avatar(u['avatar'], u['username'], size: 48),
                title: u['username'],
                subtitle: 'بانتظار الرد',
                onTap: () => openUser(context, u['id']),
                trailing: SBtn('إلغاء الطلب', onTap: () => act('/friends/cancel', {'to': u['id']})),
              );
            }
            final ok = accepted.contains(u['id']);
            return Li(
              leading: Avatar(u['avatar'], u['username'], size: 48),
              title: u['username'],
              subtitle: 'بدو يضيفك صديق · ${ago(u['at'])}',
              extra: (u['together'] ?? 0) > 0
                  ? Text('لعبتوا مع بعض ${u['together']} مرات', style: tsMuted.copyWith(color: C.gold))
                  : null,
              onTap: () => openUser(context, u['id']),
              trailing: ok
                  ? SBtn('ادعيه للعبة', gold: true, onTap: () => inviteFriend(context, u['id']))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      SBtn('قبول', gold: true, onTap: () => act('/friends/accept', {'from': u['id']}, u['id'])),
                      const SizedBox(width: 6),
                      SBtn('رفض', onTap: () => act('/friends/reject', {'from': u['id']})),
                    ]),
            );
          }).toList()),
      ],
    );
  }
}

/* ============ بروفايل لاعب ============ */
class FriendProfile extends StatefulWidget {
  final String id;
  const FriendProfile(this.id, {super.key});
  @override
  State<FriendProfile> createState() => _FriendProfileState();
}

class _FriendProfileState extends State<FriendProfile> {
  Map? d;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final app = context.read<AppState>();
    try {
      final r = await app.api.get('/users/${widget.id}');
      if (mounted) setState(() => d = r);
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  Future<void> removeFriend() async {
    final app = context.read<AppState>();
    if (d?['relation'] != 'friend') return;
    if (!await confirmDialog(context, 'بدك تشيل ${d!['username']} من أصحابك؟')) return;
    try {
      await app.api.post('/friends/remove', {'id': d!['id']});
      app.toast('انشال من أصحابك');
      load();
    } on ApiError catch (e) {
      app.toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final d = this.d;
    if (d == null) return const AppPage(children: [Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator()))]);
    final (cls, txt) = statusOf(d);
    final rel = d['relation'];
    final t = d['together'] as Map;
    final me = app.me!;
    return AppPage(
      onRefresh: load,
      actions: [if (rel == 'friend') IconBtn(Icons.more_horiz, removeFriend)],
      children: [
        ProfileHead(d, status: (cls, txt)),
        Row(children: [
          if (rel == 'friend') ...[Expanded(child: GoldButton('ادعيه للعبة', small: true, onTap: () => inviteFriend(context, d['id']))), const SizedBox(width: 10)],
          Expanded(
            child: switch (rel) {
              'friend' => GoldButton('صديق ✓', small: true, kind: BtnKind.dark, onTap: removeFriend),
              'sent' => const GoldButton('تم إرسال الطلب ✓', small: true, kind: BtnKind.dark),
              'received' => GoldButton('قبول الطلب', small: true, onTap: () async {
                  await app.api.post('/friends/accept', {'from': d['id']});
                  load();
                }),
              _ => GoldButton('أضف صديق', icon: Icons.person_add, small: true, onTap: () async {
                  if (await sendRequest(context, d['id'])) load();
                }),
            },
          ),
        ]),
        Panel(red: true, children: [
          Text('🤝 أنا و${d['username']}', style: lalezar(22)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Avatar(me['avatar'], me['username'], size: 54),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: Text('⚔️', style: TextStyle(fontSize: 24))),
            Avatar(d['avatar'], d['username'], size: 54),
          ]),
          Grid2([
            StatTile('${t['games']}', 'لعبتوا مع بعض'),
            StatTile('${t['sameWin']}', 'فزتوا بنفس الفريق', tone: 'g'),
            StatTile('${t['against']}', 'كان مافيا ضدك', tone: 'r'),
            StatTile('${t['killedMe']}', 'اغتالك', tone: 'r'),
          ]),
        ]),
        Panel(children: [Text('📊 إحصائياته', style: lalezar(22)), StatTiles(Map<String, dynamic>.from(d['stats']), she: true)]),
        FavRole(d['fav'], 'أكثر كرت بيطلعله'),
        RecentGames(d['recent'] as List),
      ],
    );
  }
}
