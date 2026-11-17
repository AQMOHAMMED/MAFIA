import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/avatar_pick.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

void showTerms(BuildContext context) => context.read<AppState>().toast('العب بروح رياضية، واحترم أصحابك 🤝');

/* ============ تسجيل الدخول ============ */
class LoginScreen extends StatefulWidget {
  final bool pushed; // مفتوحة من فوق الرئيسية (ضيف بدّه يسجّل)
  const LoginScreen({super.key, this.pushed = false});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final user = TextEditingController(), pass = TextEditingController();
  bool remember = true, busy = false;

  Future<void> submit() async {
    final app = context.read<AppState>();
    if (user.text.trim().isEmpty || pass.text.isEmpty) return app.toast('اكتب الاسم وكلمة السر');
    setState(() => busy = true);
    try {
      final r = await app.api.post('/login', {'login': user.text, 'password': pass.text});
      pass.clear();
      app.setAuth(r['token'], Map<String, dynamic>.from(r['user']), remember: remember);
    } on ApiError catch (e) {
      app.toast(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return AppPage(
      back: widget.pushed,
      children: [
        Image.asset('assets/img/logo.webp', height: 210),
        const GoldTitle('أهلاً فيك من جديد'),
        const Sub('سجّل دخول وكمّل اللعب مع الشباب'),
        AutofillGroup(
          child: Panel(children: [
            Field(controller: user, hint: 'البريد الإلكتروني أو اسم اللاعب', icon: Icons.person_outline, autofill: const [AutofillHints.username], action: TextInputAction.next),
            Field(controller: pass, hint: 'كلمة السر', icon: Icons.lock_outline, password: true, autofill: const [AutofillHints.password], onSubmitted: (_) => submit()),
            Row(children: [
              Checkbox(value: remember, onChanged: (v) => setState(() => remember = v ?? true)),
              const Expanded(child: Text('خليني مسجّل دخول', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              LinkBtn('نسيت كلمة السر؟', () => app.toast('تواصل مع صاحب اللعبة ليرجّعلك حسابك')),
            ]),
            GoldButton(busy ? 'لحظة…' : 'دخول', onTap: busy ? null : submit),
          ]),
        ),
        const Divider2('أو'),
        if (!widget.pushed) GoldButton('العب كضيف بدون حساب', kind: BtnKind.dark, onTap: app.playAsGuest),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('ما عندك حساب؟ ', style: tsMuted),
          LinkBtn('اعمل حساب جديد', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()))),
        ]),
      ],
    );
  }
}

/* ============ حساب جديد ============ */
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final user = TextEditingController(), email = TextEditingController(), pass = TextEditingController(), pass2 = TextEditingController();
  bool terms = false, busy = false;
  String? avatar;

  Future<void> pick() async {
    try {
      final a = await pickAvatar();
      if (a != null) setState(() => avatar = a);
    } catch (e) {
      if (mounted) context.read<AppState>().toast('الصورة مش مدعومة');
    }
  }

  Future<void> submit() async {
    final app = context.read<AppState>();
    if (pass.text != pass2.text) return app.toast('كلمتين السر مش متطابقات');
    if (!terms) return app.toast('لازم توافق على شروط الاستخدام');
    setState(() => busy = true);
    try {
      final r = await app.api.post('/register', {'username': user.text, 'email': email.text, 'password': pass.text, 'avatar': avatar});
      app.setAuth(r['token'], Map<String, dynamic>.from(r['user']));
      app.toast('أهلاً فيك يا ${r['user']['username']} 🔥');
    } on ApiError catch (e) {
      app.toast(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
        children: [
          Image.asset('assets/img/logo.webp', height: 120),
          const GoldTitle('حساب جديد'),
          const Sub('انضم للعيلة وابدأ اللعب'),
          AutofillGroup(
            child: Panel(children: [
              Center(child: AvatarPicker(data: avatar, onTap: pick, label: 'اختار صورتك')),
              Field(controller: user, hint: 'اسم اللاعب', icon: Icons.person_outline, maxLength: 20, autofill: const [AutofillHints.nickname]),
              Field(controller: email, hint: 'البريد الإلكتروني', icon: Icons.mail_outline, keyboard: TextInputType.emailAddress, autofill: const [AutofillHints.email]),
              Field(controller: pass, hint: 'كلمة السر (6 أحرف أو أكثر)', icon: Icons.lock_outline, password: true, autofill: const [AutofillHints.newPassword]),
              Field(controller: pass2, hint: 'تأكيد كلمة السر', icon: Icons.lock_outline, password: true),
              Row(children: [
                Checkbox(value: terms, onChanged: (v) => setState(() => terms = v ?? false)),
                const Text('أوافق على ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                LinkBtn('شروط الاستخدام', () => showTerms(context)),
              ]),
              GoldButton(busy ? 'لحظة…' : 'إنشاء الحساب', onTap: busy ? null : submit),
            ]),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('عندك حساب؟ ', style: tsMuted),
            LinkBtn('سجّل دخول', () => Navigator.of(context).maybePop()),
          ]),
        ],
      );
}

class AvatarPicker extends StatelessWidget {
  final String? data; // data URL جديدة
  final String? url; // الصورة الحالية من السيرفر
  final String? name;
  final VoidCallback onTap;
  final String label;
  const AvatarPicker({super.key, this.data, this.url, this.name, required this.onTap, required this.label});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            data != null
                ? Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.gold2, width: 2.5)),
                    clipBehavior: Clip.antiAlias,
                    child: Image.memory(base64Decode(data!.split(',').last), fit: BoxFit.cover),
                  )
                : (url != null || name != null)
                    ? Avatar(url, name, size: 96)
                    : Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x0FFFFFFF), border: Border.all(color: C.gold2, width: 2)),
                        child: const Icon(Icons.person, size: 46, color: C.gold2),
                      ),
            const Positioned(
              bottom: 0,
              left: 0,
              child: CircleAvatar(radius: 15, backgroundColor: C.gold, child: Icon(Icons.photo_camera, size: 17, color: C.dark)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800)),
        ]),
      );
}
