import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class ToastView extends StatelessWidget {
  const ToastView({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return ValueListenableBuilder<String?>(
      valueListenable: app.toastMsg,
      builder: (context, msg, _) => Positioned(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 96,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: msg == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xF21E0A10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: C.gold2),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 20)],
                  ),
                  child: Text(msg ?? '',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontFamily: 'Cairo', color: C.text, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// دعوة من صديق (بتظهر فوق بأي شاشة)
class InviteBanner extends StatelessWidget {
  const InviteBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return ValueListenableBuilder<J?>(
      valueListenable: app.invite,
      builder: (context, n, _) => AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        top: n == null ? -160 : MediaQuery.of(context).padding.top + 10,
        left: 12,
        right: 12,
        child: n == null
            ? const SizedBox()
            : Directionality(
                textDirection: TextDirection.rtl,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xF7240B12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.gold2, width: 1.5),
                      boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24)],
                    ),
                    child: Row(children: [
                      Avatar(n['avatar'], n['from'], size: 42),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${n['from']} عزمك على غرفة '),
                          TextSpan(text: '${n['code']}', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w900)),
                        ]), style: const TextStyle(fontFamily: 'Cairo', color: C.text, fontWeight: FontWeight.w700)),
                      ),
                      SBtn('انضم', gold: true, onTap: app.acceptInvite),
                      IconButton(onPressed: () => app.invite.value = null, icon: const Icon(Icons.close, color: C.muted)),
                    ]),
                  ),
                ),
              ),
      ),
    );
  }
}

// كشف اللاعب اللي طلع (تصويت أو سحب)
class RevealOverlay extends StatelessWidget {
  const RevealOverlay({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return ValueListenableBuilder<J?>(
      valueListenable: app.reveal,
      builder: (context, r, _) {
        if (r == null) return const SizedBox();
        final mafia = r['team'] == 'mafia';
        return Positioned.fill(
          child: GestureDetector(
            onTap: () => app.reveal.value = null,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Material(
                color: const Color(0xEB060102),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: .6, end: 1),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: gap([
                        if (r['pulledBy'] != null) ...[
                          const Text('⛓️', style: TextStyle(fontSize: 44)),
                          Text('${r['pulledBy']} سحب ${r['name']} معه!', textAlign: TextAlign.center, style: lalezar(24)),
                        ],
                        Avatar(r['avatar'], r['name'], size: 120),
                        Text('${r['name']}', style: lalezar(34, C.text)),
                        TeamBadge(mafia),
                        if (r['host'] == true) Text('🎙️ وصار هو الهوست', style: lalezar(22)),
                        const Text('اضغط بأي مكان للإغلاق', style: tsMuted),
                      ], 12)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class TeamBadge extends StatelessWidget {
  final bool mafia;
  const TeamBadge(this.mafia, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: mafia ? const [Color(0xFFFF6A7A), Color(0xFFC80134), Color(0xFF6A0018)] : const [Color(0xFF8BFFC0), Color(0xFF1BB866), Color(0xFF0B5A30)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: mafia ? const Color(0xFFFFB3B4) : const Color(0xFFB8FFD8), width: 1.5),
          boxShadow: [BoxShadow(color: (mafia ? C.red : C.green).withValues(alpha: .5), blurRadius: 30)],
        ),
        child: Text(mafia ? '🔪 مافيا' : '🕊️ مواطن صالح',
            style: lalezar(30, Colors.white).copyWith(shadows: const [Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)])),
      );
}
