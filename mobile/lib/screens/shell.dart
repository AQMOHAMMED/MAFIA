import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/roles.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'auth.dart';
import 'gamelog.dart';
import 'profile.dart';
import 'social.dart';

Future<void> push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

// الصفحات اللي بدها حساب
bool needLogin(BuildContext context) {
  final app = context.read<AppState>();
  if (app.loggedIn) return false;
  app.toast('سجّل دخول لتشوف هاي الصفحة');
  push(context, const LoginScreen(pushed: true));
  return true;
}

/* ============ الشريط السفلي ============ */
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;
  static const items = [
    (Icons.home_rounded, 'الرئيسية'),
    (Icons.leaderboard_rounded, 'الصدارة'),
    (Icons.group_rounded, 'الأصدقاء'),
    (Icons.bar_chart_rounded, 'الإحصائيات'),
    (Icons.person_rounded, 'حسابي'),
  ];

  void select(int i) {
    if (i >= 2 && needLogin(context)) return;
    HapticFeedback.selectionClick();
    setState(() => tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (tab >= 2 && !app.loggedIn) tab = 0;
    final page = switch (tab) {
      1 => const LeaderboardTab(),
      2 => const FriendsTab(),
      3 => const StatsTab(),
      4 => const ProfileTab(),
      _ => HomeTab(onTab: select),
    };
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => tab = 0);
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: KeyedSubtree(key: ValueKey(tab), child: page),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1C070C), Color(0xFF0B0204)]),
            border: Border(top: BorderSide(color: C.line2)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => select(i),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(items[i].$1, color: tab == i ? C.gold : C.muted, size: 25),
                          Text(items[i].$2,
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tab == i ? C.gold : C.muted, height: 1.5)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ============ الرئيسية ============ */
class HomeTab extends StatefulWidget {
  final void Function(int) onTab;
  const HomeTab({super.key, required this.onTab});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late final name = TextEditingController(text: context.read<AppState>().guestName);
  final code = TextEditingController();
  final codeFocus = FocusNode();
  List friends = [];
  Map? last;
  int tick = -1;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final app = context.read<AppState>();
    tick = app.friendsTick;
    if (!app.loggedIn) return;
    try {
      final r = await Future.wait([app.api.get('/friends'), app.api.get('/games')]);
      await app.refreshMe();
      if (!mounted) return;
      setState(() {
        friends = (r[0] as List).where((f) => f['online'] == true).toList();
        last = (r[1] as List).isNotEmpty ? r[1][0] : null;
      });
    } catch (_) {}
  }

  void join() {
    final app = context.read<AppState>();
    if (app.myName.isEmpty) return app.toast('اكتب اسمك أول');
    app.joinRoom(code.text);
  }

  void goCreate() {
    final app = context.read<AppState>();
    if (app.myName.isEmpty) return app.toast('اكتب اسمك أول');
    push(context, const CreateScreen());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (tick != app.friendsTick) WidgetsBinding.instance.addPostFrameCallback((_) => load());
    final me = app.me;
    final reqs = (me?['requests'] as num?)?.toInt() ?? 0;
    return AppPage(
      back: false,
      onRefresh: load,
      actions: [
        Expanded(
          child: me != null
              ? Row(children: [
                  Avatar(me['avatar'], me['username'], size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('أهلاً فيك', style: tsMuted),
                      Text(me['username'], style: tsBold.copyWith(fontSize: 17), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ])
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SBtn('تسجيل دخول', icon: Icons.person, gold: true, onTap: () => push(context, const LoginScreen(pushed: true))),
                ),
        ),
        if (me != null) IconBtn(Icons.notifications_none_rounded, () => push(context, const RequestsScreen()), badge: reqs),
        if (!app.connected) const Padding(padding: EdgeInsetsDirectional.only(start: 8), child: _Connecting()),
      ],
      children: [
        Image.asset('assets/img/logo.webp', height: 230),
        Text('في الظلّ… نحكُم', textAlign: TextAlign.center, style: lalezar(22, C.muted)),
        if (me == null)
          Panel(children: [
            const Text('اسمك باللعبة', style: tsMuted),
            Field(controller: name, hint: 'مثلاً: عبود', maxLength: 20, onChanged: app.setGuestName),
          ]),
        Row(children: [
          Expanded(child: ActCard('🎖️', 'إنشاء غرفة', 'ابدأ جولة جديدة مع أصحابك وكون إنت الليدر', onTap: goCreate)),
          const SizedBox(width: 12),
          Expanded(child: ActCard('🔑', 'انضمام بكود', 'ادخل رمز الغرفة السري والعب فوراً', red: true, onTap: () => codeFocus.requestFocus())),
        ]),
        Panel(children: [
          const Text('🔒 رمز الغرفة', style: tsMuted),
          Row(children: [
            Expanded(child: CodeInput(controller: code, focus: codeFocus, onDone: join)),
            const SizedBox(width: 10),
            SizedBox(width: 110, child: GoldButton('ادخل', onTap: join, small: true)),
          ]),
        ]),
        if (me != null) ...[
          H2('أصدقائك المتصلين', trailing: LinkBtn('عرض الكل', () => widget.onTab(2))),
          friends.isEmpty
              ? const Empty('ما في حدا من أصحابك متصل هلأ')
              : SizedBox(
                  height: 168,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: friends.map<Widget>((f) => FriendCard(f)).toList(),
                  ),
                ),
          if (last != null) ...[
            H2('🕓 آخر لعبة', trailing: Text('#${last!['code']}', style: tsMuted)),
            Li(
              leading: Text(last!['role'] != null ? role(last!['role']).icon : '🎙️', style: const TextStyle(fontSize: 30)),
              title: last!['role'] != null ? role(last!['role']).name : 'كنت الهوست',
              titleTrail: Tag(last!['winner'] == 'mafia' ? 'المافيا فازت' : 'الصالحين فازوا', last!['winner']),
              subtitle: '${last!['players']} لاعبين · ${ago(last!['at'])}',
              trailing: const Text('سجل اللعبة ‹', style: TextStyle(color: C.gold, fontWeight: FontWeight.w800, fontSize: 13)),
              onTap: () => openGameLog(context, last!['id']),
            ),
          ],
        ],
      ],
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();
  @override
  Widget build(BuildContext context) => const Tooltip(
        message: 'بنتصل بالسيرفر…',
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
}

class ActCard extends StatelessWidget {
  final String icon, title, sub;
  final bool red;
  final VoidCallback onTap;
  const ActCard(this.icon, this.title, this.sub, {super.key, this.red = false, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 172,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: red ? const [Color(0xFF4A0A15), Color(0xFF1A0408)] : const [Color(0xFF3A2A0A), Color(0xFF1A0B04)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: red ? const Color(0xAAFF3B55) : C.gold2, width: 1.5),
            boxShadow: [BoxShadow(color: (red ? C.red : C.gold).withValues(alpha: .18), blurRadius: 18)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x14FFFFFF), border: Border.all(color: C.line2)),
              child: Text(icon, style: const TextStyle(fontSize: 22)),
            ),
            const Spacer(),
            Text(title, style: lalezar(22, red ? const Color(0xFFFFB3B4) : C.gold)),
            Text(sub, maxLines: 2, style: tsMuted.copyWith(fontSize: 11.5)),
          ]),
        ),
      );
}

// خانة كود الغرفة (4 أرقام)
class CodeInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focus;
  final VoidCallback onDone;
  const CodeInput({super.key, required this.controller, this.focus, required this.onDone});
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: controller,
          focusNode: focus,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: lalezar(34, C.gold).copyWith(letterSpacing: 14, height: 1.2),
          onChanged: (v) {
            if (v.length == 4) {
              FocusScope.of(context).unfocus();
              onDone();
            }
          },
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••',
            hintStyle: lalezar(34, const Color(0x55F3C75A)).copyWith(letterSpacing: 14),
            filled: true,
            fillColor: C.field,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line2)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.gold, width: 1.5)),
          ),
        ),
      );
}

// كرت صديق متصل مع زر دعوة
class FriendCard extends StatefulWidget {
  final Map f;
  const FriendCard(this.f, {super.key});
  @override
  State<FriendCard> createState() => _FriendCardState();
}

class _FriendCardState extends State<FriendCard> {
  bool sent = false;
  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    return Container(
      width: 120,
      margin: const EdgeInsetsDirectional.only(end: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xD91A0B10), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
      child: Column(children: [
        GestureDetector(
            onTap: () => openUser(context, f['id']), child: Avatar(f['avatar'], f['username'], size: 56, status: f['playing'] == true ? 'busy' : 'on')),
        const SizedBox(height: 4),
        Text(f['username'], maxLines: 1, overflow: TextOverflow.ellipsis, style: tsBold.copyWith(fontSize: 14)),
        Text(f['playing'] == true ? 'بيلعب هلأ' : 'متصل الآن', style: tsMuted.copyWith(fontSize: 11)),
        const Spacer(),
        SBtn(sent ? 'انبعتت ✓' : '+ ادعي', onTap: sent ? null : () => inviteFriend(context, f['id'], () => setState(() => sent = true))),
      ]),
    );
  }
}

void inviteFriend(BuildContext context, String uid, [VoidCallback? sent]) {
  final app = context.read<AppState>();
  if (app.inviteFriend(uid)) {
    sent?.call();
    app.toast('انبعتت الدعوة 📨');
  } else {
    app.toast('اعمل الغرفة وبنبعتله الدعوة');
    push(context, const CreateScreen());
  }
}

/* ============ إنشاء غرفة ============ */
class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  int size = 8;
  String hostMode = 'first';
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return AppPage(
      title: 'غرفة جديدة',
      children: [
        Panel(children: [
          Text('👥 عدد اللاعبين', style: lalezar(22)),
          BigStepper(size, (d) => setState(() => size = (size + d).clamp(3, 30))),
        ]),
        Panel(children: [
          Text('🎙️ الهوست', style: lalezar(22)),
          HostOptions(hostMode, (m) => setState(() => hostMode = m)),
        ]),
        const Text('بتقدر تعدّل الكروت من داخل الغرفة', textAlign: TextAlign.center, style: tsMuted),
        GoldButton('اعمل الغرفة', onTap: () => app.createRoom(size, hostMode)),
      ],
    );
  }
}

class BigStepper extends StatelessWidget {
  final int value;
  final void Function(int) onStep;
  const BigStepper(this.value, this.onStep, {super.key});
  @override
  Widget build(BuildContext context) {
    Widget b(String t, int d) => GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onStep(d);
          },
          child: Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.goldGrad, boxShadow: [BoxShadow(color: C.gold.withValues(alpha: .3), blurRadius: 12)]),
            child: Text(t, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: C.dark, height: 1.1)),
          ),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      b('−', -1),
      Text('$value', style: lalezar(64).copyWith(height: 1.1)),
      b('+', 1),
    ]);
  }
}

class HostOptions extends StatelessWidget {
  final String mode;
  final void Function(String)? onPick;
  const HostOptions(this.mode, this.onPick, {super.key});
  @override
  Widget build(BuildContext context) => Column(
        children: gap(
          kHostOpts.map((o) {
            final sel = o.mode == mode;
            return Opacity(
              opacity: onPick == null && !sel ? .5 : 1,
              child: GestureDetector(
                onTap: onPick == null ? null : () => onPick!(o.mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0x1FF3C75A) : const Color(0x0AFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? C.gold : C.line, width: sel ? 2 : 1),
                  ),
                  child: Row(children: [
                    Text(o.icon, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.title, style: tsBold.copyWith(color: sel ? C.gold : C.text)),
                        Text(o.sub, style: tsMuted.copyWith(fontSize: 12)),
                      ]),
                    ),
                    if (sel) const Icon(Icons.check_circle, color: C.gold),
                  ]),
                ),
              ),
            );
          }).toList(),
          10,
        ),
      );
}
