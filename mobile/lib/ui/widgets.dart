import 'package:flutter/material.dart';
import '../core/config.dart';
import 'theme.dart';

/* ---------- الخلفية والصفحات ---------- */
class Bg extends StatelessWidget {
  final Widget child;
  final bool night;
  const Bg({super.key, required this.child, this.night = false});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: C.bg,
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.3,
            colors: night ? const [Color(0xFF14102A), Color(0xFF0A0614), C.bg] : const [Color(0xFF4A0A15), Color(0xFF1C050A), C.bg],
            stops: const [0, .45, .9],
          ),
        ),
        child: child,
      );
}

// صفحة عادية: شريط علوي (رجوع + عنوان) ومحتوى بيسكرول
class AppPage extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final List<Widget> actions;
  final bool back;
  final Future<void> Function()? onRefresh;
  final Widget? bottom;
  final EdgeInsets padding;
  const AppPage(
      {super.key,
      this.title,
      required this.children,
      this.actions = const [],
      this.back = true,
      this.onRefresh,
      this.bottom,
      this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 28)});

  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
        if (title != null || back || actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              if (back) IconBtn(Icons.arrow_back_rounded, () => Navigator.of(context).maybePop()),
              if (back) const SizedBox(width: 10),
              if (title != null) Expanded(child: GoldTitle(title!, size: 27, align: TextAlign.start)) else const Spacer(),
              ...actions,
            ]),
          ),
        ...gap(children),
      ],
    );
    if (onRefresh case final r?) list = RefreshIndicator(onRefresh: r, color: C.gold, backgroundColor: C.panel, child: list);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Bg(child: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: list)))),
      bottomNavigationBar: bottom,
    );
  }
}

List<Widget> gap(List<Widget> items, [double h = 14]) {
  final out = <Widget>[];
  for (final w in items) {
    if (out.isNotEmpty) out.add(SizedBox(height: h));
    out.add(w);
  }
  return out;
}

/* ---------- نصوص ---------- */
class GoldTitle extends StatelessWidget {
  final String text;
  final double size;
  final TextAlign align;
  const GoldTitle(this.text, {super.key, this.size = 32, this.align = TextAlign.center});
  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => C.goldText.createShader(r),
        child: Text(text,
            textAlign: align,
            style: lalezar(size, Colors.white).copyWith(shadows: const [Shadow(color: Color(0xFF4A2C05), offset: Offset(0, 2))])),
      );
}

class H2 extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const H2(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(text, style: lalezar(22))),
        if (trailing != null) trailing!,
      ]);
}

class Sub extends StatelessWidget {
  final String text;
  const Sub(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 15, fontWeight: FontWeight.w600));
}

class Empty extends StatelessWidget {
  final String text;
  final String? emoji;
  const Empty(this.text, {super.key, this.emoji});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(children: [
          if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 50)),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w700)),
        ]),
      );
}

/* ---------- لوحات ---------- */
class Panel extends StatelessWidget {
  final List<Widget> children;
  final bool red;
  final CrossAxisAlignment cross;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const Panel(
      {super.key, required this.children, this.red = false, this.cross = CrossAxisAlignment.stretch, this.padding = const EdgeInsets.all(16), this.onTap});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: C.panelGrad,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: red ? const Color(0x8CFF3B55) : C.line),
        boxShadow: [
          BoxShadow(color: red ? const Color(0x2EFF3B55) : const Color(0x59000000), blurRadius: red ? 18 : 24, offset: red ? Offset.zero : const Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: cross, mainAxisSize: MainAxisSize.min, children: gap(children, 12)),
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: box);
  }
}

/* ---------- أزرار ---------- */
class _HexClip extends CustomClipper<Path> {
  final double cut;
  const _HexClip(this.cut);
  @override
  Path getClip(Size s) => Path()
    ..moveTo(cut, 0)
    ..lineTo(s.width - cut, 0)
    ..lineTo(s.width, s.height / 2)
    ..lineTo(s.width - cut, s.height)
    ..lineTo(cut, s.height)
    ..lineTo(0, s.height / 2)
    ..close();
  @override
  bool shouldReclip(_HexClip o) => o.cut != cut;
}

enum BtnKind { gold, dark, danger }

// الزر الذهبي المسدّس (نفس الموقع)
class GoldButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool small;
  final double? fontSize;
  final bool expand; // بياخذ كل العرض (زي الموقع)
  const GoldButton(this.label, {super.key, this.onTap, this.icon, this.kind = BtnKind.gold, this.small = false, this.fontSize, this.expand = true});
  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onTap != null;
    final dark = w.kind == BtnKind.dark;
    final inner = switch (w.kind) {
      BtnKind.gold => C.goldGrad,
      BtnKind.dark => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A1218), Color(0xFF14060A)]),
      BtnKind.danger => const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFD2D2), Color(0xFFFF6A6A), Color(0xFFC41D2E)]),
    };
    final fg = dark ? C.text : (w.kind == BtnKind.danger ? Colors.white : C.dark);
    final fs = w.fontSize ?? (w.small ? 17.0 : 22.0);
    Widget btn = ClipPath(
      clipper: const _HexClip(16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            gradient: dark
                ? const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF3C75A), Color(0xFF7A5112), Color(0xFFE0A93A)])
                : C.goldMetal),
        child: ClipPath(
          clipper: const _HexClip(15),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: w.small ? 7 : 10),
            decoration: BoxDecoration(gradient: inner),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              if (w.icon != null) ...[Icon(w.icon, color: fg, size: fs + 2), const SizedBox(width: 8)],
              Flexible(child: Text(w.label, textAlign: TextAlign.center, style: lalezar(fs, fg).copyWith(height: 1.4))),
            ]),
          ),
        ),
      ),
    );
    if (!enabled) {
      btn = Opacity(
          opacity: .55,
          child: ColorFiltered(
              colorFilter: const ColorFilter.matrix(
                  [.33, .59, .11, 0, 0, .33, .59, .11, 0, 0, .33, .59, .11, 0, 0, 0, 0, 0, 1, 0]),
              child: btn));
    }
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => down = true) : null,
      onTapUp: enabled ? (_) => setState(() => down = false) : null,
      onTapCancel: enabled ? () => setState(() => down = false) : null,
      onTap: w.onTap,
      child: AnimatedScale(scale: down ? .97 : 1, duration: const Duration(milliseconds: 90), child: w.expand ? SizedBox(width: double.infinity, child: btn) : btn),
    );
  }
}

// زر صغير مدوّر
class SBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool gold;
  final Color? color;
  const SBtn(this.label, {super.key, this.onTap, this.icon, this.gold = false, this.color});
  @override
  Widget build(BuildContext context) {
    final fg = gold ? C.dark : (color ?? C.text);
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: gold ? C.goldGrad : null,
              color: gold ? null : const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: gold ? null : Border.all(color: color?.withValues(alpha: .5) ?? C.line2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 5)],
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final int badge;
  const IconBtn(this.icon, this.onTap, {super.key, this.badge = 0});
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        Material(
          color: const Color(0x0FFFFFFF),
          shape: const CircleBorder(side: BorderSide(color: C.line)),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, color: C.text))),
        ),
        if (badge > 0)
          PositionedDirectional(
            top: -3,
            start: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1.2)),
            ),
          ),
      ]);
}

class TextBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  const TextBtn(this.label, this.onTap, {super.key, this.color = const Color(0xFFFF6A7A)});
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15, fontFamily: 'Cairo')),
      );
}

class LinkBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const LinkBtn(this.label, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800, fontSize: 14)),
        ),
      );
}

/* ---------- وسوم وصور ---------- */
class Tag extends StatelessWidget {
  final String text;
  final String kind; // mafia | town | gold | grey
  const Tag(this.text, this.kind, {super.key});
  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (kind) {
      'mafia' => (const Color(0x26FF3B55), C.pink, const Color(0x66FF3B55)),
      'town' => (const Color(0x1A2EF08A), C.green, const Color(0x592EF08A)),
      'gold' => (const Color(0x24F3C75A), C.gold, C.line2),
      _ => (const Color(0x12FFFFFF), C.muted, const Color(0x1FFFFFFF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: bd)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

// صورة اللاعب: صورته أو أول حرف من اسمه، مع نقطة الحالة
class Avatar extends StatelessWidget {
  final String? url;
  final String? name;
  final double size;
  final String? status; // on | busy | off
  const Avatar(this.url, this.name, {super.key, this.size = 44, this.status});
  @override
  Widget build(BuildContext context) {
    final u = absUrl(url);
    final letter = (name ?? '؟').trim().isEmpty ? '؟' : name!.trim().characters.first;
    final fallback = Center(child: Text(letter, style: TextStyle(color: C.gold, fontWeight: FontWeight.w900, fontSize: size * .42, height: 1.1)));
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A1018), Color(0xFF1A060B)]),
            border: Border.all(color: C.gold2, width: size > 60 ? 2.5 : 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: u == null ? fallback : Image.network(u, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
        ),
        if (status != null)
          PositionedDirectional(
            bottom: 0,
            end: 0,
            child: Container(
              width: size * .28,
              height: size * .28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status == 'on' ? C.green : status == 'busy' ? C.red : const Color(0xFF6B5A60),
                border: Border.all(color: C.bg, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

/* ---------- حقول ---------- */
class Field extends StatefulWidget {
  final TextEditingController? controller;
  final String hint;
  final IconData? icon;
  final bool password;
  final TextInputType? keyboard;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofill;
  final TextInputAction? action;
  const Field(
      {super.key,
      this.controller,
      required this.hint,
      this.icon,
      this.password = false,
      this.keyboard,
      this.maxLength,
      this.onChanged,
      this.onSubmitted,
      this.autofill,
      this.action});
  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) {
    final w = widget;
    return TextField(
      controller: w.controller,
      obscureText: w.password && hidden,
      keyboardType: w.keyboard,
      maxLength: w.maxLength,
      onChanged: w.onChanged,
      onSubmitted: w.onSubmitted,
      autofillHints: w.autofill,
      textInputAction: w.action,
      style: const TextStyle(fontSize: 16, color: C.text, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        counterText: '',
        hintText: w.hint,
        hintStyle: const TextStyle(color: Color(0xFF7D6A70), fontWeight: FontWeight.w600),
        filled: true,
        fillColor: C.field,
        prefixIcon: w.icon == null ? null : Icon(w.icon, color: C.gold2),
        suffixIcon: w.password
            ? IconButton(
                icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: C.muted),
                onPressed: () => setState(() => hidden = !hidden))
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.gold2, width: 1.5)),
      ),
    );
  }
}

/* ---------- اختيارات (فلاتر وتبويبات) ---------- */
class Chips extends StatelessWidget {
  final List<(String, String)> items;
  final String value;
  final ValueChanged<String> onChanged;
  const Chips(this.items, this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items
              .map((it) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: GestureDetector(
                      onTap: () => onChanged(it.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: it.$1 == value ? C.goldGrad : null,
                          color: it.$1 == value ? null : const Color(0x0FFFFFFF),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: it.$1 == value ? Colors.transparent : C.line),
                        ),
                        child: Text(it.$2,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: it.$1 == value ? C.dark : C.text)),
                      ),
                    ),
                  ))
              .toList(),
        ),
      );
}

class Tabs extends StatelessWidget {
  final List<(String, String)> items;
  final String value;
  final ValueChanged<String> onChanged;
  const Tabs(this.items, this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Row(
          children: items
              .map((it) => Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(it.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(gradient: it.$1 == value ? C.goldGrad : null, borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: Text(it.$2, style: TextStyle(fontWeight: FontWeight.w800, color: it.$1 == value ? C.dark : C.text)),
                      ),
                    ),
                  ))
              .toList(),
        ),
      );
}

// صف بقائمة (لاعب، لعبة، إعداد...)
class Li extends StatelessWidget {
  final Widget? leading;
  final String title;
  final Widget? titleTrail;
  final String? subtitle;
  final Color? subColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlight;
  final Widget? extra;
  const Li(
      {super.key,
      this.leading,
      required this.title,
      this.titleTrail,
      this.subtitle,
      this.subColor,
      this.trailing,
      this.onTap,
      this.highlight = false,
      this.extra});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: highlight ? const Color(0x24F3C75A) : const Color(0xD91A0B10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: highlight ? C.gold2 : C.line),
            ),
            child: Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tsBold)),
                    if (titleTrail != null) ...[const SizedBox(width: 6), titleTrail!],
                  ]),
                  if (subtitle != null)
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: tsMuted.copyWith(color: subColor ?? C.muted)),
                  ?extra,
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ]),
          ),
        ),
      );
}

class ListCol extends StatelessWidget {
  final List<Widget> children;
  const ListCol(this.children, {super.key});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gap(children, 8));
}

// خانة رقم/عنوان (إحصائية)
class StatTile extends StatelessWidget {
  final String value, label;
  final String? icon, note;
  final String tone; // g | r | ''
  final Color? valueColor;
  const StatTile(this.value, this.label, {super.key, this.icon, this.note, this.tone = '', this.valueColor});
  @override
  Widget build(BuildContext context) {
    final bd = tone == 'g' ? const Color(0x592EF08A) : tone == 'r' ? const Color(0x66FF3B55) : C.line;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xCC140709), borderRadius: BorderRadius.circular(14), border: Border.all(color: bd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: valueColor ?? C.gold, height: 1.2))),
          if (icon != null) Text(icon!, style: const TextStyle(fontSize: 20)),
        ]),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.text, height: 1.4)),
        if (note != null) Text(note!, style: tsMuted.copyWith(fontSize: 11.5)),
      ]),
    );
  }
}

class Grid2 extends StatelessWidget {
  final List<Widget> children;
  final int cols;
  final double spacing;
  const Grid2(this.children, {super.key, this.cols = 2, this.spacing = 10});
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final row = <Widget>[];
      for (var j = 0; j < cols; j++) {
        if (j > 0) row.add(SizedBox(width: spacing));
        row.add(Expanded(child: i + j < children.length ? children[i + j] : const SizedBox()));
      }
      rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: row)));
    }
    return Column(children: gap(rows, spacing));
  }
}

class ProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Gradient? gradient;
  const ProgressBar(this.value, {super.key, this.height = 6, this.gradient});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: const Color(0x14FFFFFF),
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0, 1).toDouble(),
            child: Container(decoration: BoxDecoration(gradient: gradient ?? C.goldGrad)),
          ),
        ),
      );
}

class Divider2 extends StatelessWidget {
  final String text;
  const Divider2(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: Divider(color: C.line)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(text, style: tsMuted)),
        const Expanded(child: Divider(color: C.line)),
      ]);
}

/* ---------- حوارات ---------- */
Future<bool> confirmDialog(BuildContext context, String msg, {String yes = 'آه', String no = 'لأ'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(yes, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w900))),
      ],
    ),
  );
  return r == true;
}

Future<String?> promptDialog(BuildContext context, String msg, {bool password = false, String ok = 'تأكيد'}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(msg),
        const SizedBox(height: 12),
        Field(controller: ctl, hint: password ? 'كلمة السر' : '', password: password),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء', style: TextStyle(color: C.muted, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(ok, style: const TextStyle(color: C.red, fontWeight: FontWeight.w900))),
      ],
    ),
  );
}

/* ---------- نصوص الوقت ---------- */
String ago(num? ts) {
  if (ts == null || ts == 0) return '';
  final m = ((DateTime.now().millisecondsSinceEpoch - ts) / 60000).round();
  if (m < 1) return 'هلأ';
  if (m < 60) return 'قبل $m ${m <= 10 ? 'دقايق' : 'دقيقة'}';
  final h = (m / 60).round();
  if (h < 24) return h == 1 ? 'قبل ساعة' : h == 2 ? 'قبل ساعتين' : 'قبل $h ساعات';
  final d = (h / 24).round();
  return d == 1 ? 'مبارح' : d == 2 ? 'قبل يومين' : 'قبل $d أيام';
}

String nightsTxt(num? n) => n == 0 ? 'بدون ولا ليلة' : n == 1 ? 'ليلة وحدة' : n == 2 ? 'ليلتين' : '$n ليالي';
int pct(num? a, num? b) => (b == null || b == 0) ? 0 : (((a ?? 0) / b) * 100).round();

const _months = ['كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
String shortDate(num? ts) {
  if (ts == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
  return '${d.day} ${_months[d.month - 1]}';
}
