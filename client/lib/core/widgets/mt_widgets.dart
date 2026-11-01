import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../theme/tokens.dart';

/// White rounded card used throughout the design (24 px radius, soft blue shadow, hairline border).
class MtCard extends StatelessWidget {
  const MtCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.radius = Mt.radiusCard, this.color = Colors.white, this.border = Mt.border, this.shadow = true, this.gradient});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final Color border;
  final bool shadow;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: gradient == null ? color : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border),
          boxShadow: shadow ? Mt.shadow(.08, 28, 10) : null,
        ),
        clipBehavior: Clip.antiAlias,
        padding: padding,
        child: child,
      );
}

class Tappable extends StatelessWidget {
  const Tappable({super.key, required this.child, this.onTap, this.semanticLabel, this.radius = 20});
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double radius;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: child),
        ),
      );
}

/// The capsule / round tablet drawn in code, as in the design (no raster assets).
class PillIcon extends StatelessWidget {
  const PillIcon(this.appearance, {super.key, this.size = 52});
  final String? appearance;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = PillStyle.of(appearance);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(size * .31)),
      alignment: Alignment.center,
      child: ExcludeSemantics(
        child: p.capsule
            ? Transform.rotate(
                angle: -0.7,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(size * .15),
                  child: SizedBox(
                    width: size * .69,
                    height: size * .31,
                    child: Row(children: [Expanded(child: DecoratedBox(decoration: BoxDecoration(gradient: p.a), child: const SizedBox.expand())), Expanded(child: DecoratedBox(decoration: BoxDecoration(gradient: p.b), child: const SizedBox.expand()))]),
                  ),
                ),
              )
            : Container(
                width: size * .54,
                height: size * .54,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: p.a, boxShadow: const [BoxShadow(color: Color(0x2E101B2D), blurRadius: 8, offset: Offset(0, 4))]),
                child: Center(child: Transform.rotate(angle: -0.6, child: Container(width: size * .38, height: 2, color: Colors.white54))),
              ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.fg, required this.bg, this.icon, this.big = false});
  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final bool big;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: big ? 13 : 11, vertical: big ? 8 : 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: big ? 17 : 15, color: fg), const SizedBox(width: 6)],
          Flexible(child: Text(label, style: TextStyle(color: fg, fontSize: big ? 15 : 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, required this.onPressed, this.icon, this.loading = false, this.color, this.height = 58});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: onPressed == null ? .55 : 1,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: color == null ? const LinearGradient(colors: [Mt.blueLight, Mt.blue]) : null,
          color: color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: (color ?? Mt.blue).withValues(alpha: .3), blurRadius: 26, offset: const Offset(0, 12))],
        ),
        child: Tappable(
          radius: 18,
          onTap: enabled ? onPressed : null,
          child: Center(
            child: loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 10)],
                    Flexible(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                  ]),
          ),
        ),
      ),
    );
  }
}

class OutlineBtn extends StatelessWidget {
  const OutlineBtn(this.label, {super.key, required this.onPressed, this.icon, this.color = Mt.blueText, this.border = Mt.outline, this.height = 54});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color border;
  final double height;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? .55 : 1,
        child: Container(
          height: height,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
          child: Tappable(
            radius: 16,
            onTap: onPressed,
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, color: color, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
              ]),
            ),
          ),
        ),
      );
}

class TextAction extends StatelessWidget {
  const TextAction(this.label, {super.key, required this.onPressed, this.color = Mt.blue});
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: color, textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        child: Text(label),
      );
}

/// Pill-shaped segmented control (design's `seg`).
class SegControl<T> extends StatelessWidget {
  const SegControl({super.key, required this.options, required this.value, required this.onChanged, this.semanticLabel});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        container: true,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Mt.track, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            for (final (v, label) in options)
              Expanded(
                child: Semantics(
                  selected: v == value,
                  inMutuallyExclusiveGroup: true,
                  button: true,
                  child: GestureDetector(
                    onTap: () => onChanged(v),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: v == value ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: v == value ? Mt.shadow(.14, 8, 2) : null,
                      ),
                      child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: v == value ? FontWeight.w700 : FontWeight.w500, color: v == value ? Mt.blueText : Mt.muted2)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
}

/// Filter chip row (design's `chips`).
class ChipRow<T> extends StatelessWidget {
  const ChipRow({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          for (final (v, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                selected: v == value,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(v),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? Mt.blue : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: v == value ? Mt.blue : Mt.inputBorder),
                    ),
                    child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: v == value ? Colors.white : Mt.ink2)),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.label, this.sub, required this.value, required this.onChanged});
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        label: label,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Mt.hairline))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  if (sub != null) Text(sub!, style: const TextStyle(fontSize: 14, color: Mt.muted)),
                ]),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 32,
                decoration: BoxDecoration(color: value ? Mt.blue : const Color(0xFFCBD6E6), borderRadius: BorderRadius.circular(16)),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(margin: const EdgeInsets.all(3), width: 26, height: 26, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x40101B2D), blurRadius: 6, offset: Offset(0, 2))])),
                ),
              ),
            ]),
          ),
        ),
      );
}

class BackHeader extends StatelessWidget {
  const BackHeader(this.title, {super.key, this.onBack, this.trailing});
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Semantics(
          button: true,
          label: 'Back',
          child: GestureDetector(
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE6EEF9)), boxShadow: Mt.shadow(.08, 12, 4)),
              child: const Icon(Icons.chevron_left_rounded, size: 28, color: Mt.ink),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ?trailing,
      ]);
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.sub, this.trailing});
  final String title;
  final String? sub;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.5))),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(fontSize: 15, color: Mt.muted))),
          ]),
        ),
        ?trailing,
      ]);
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Semantics(header: true, child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Mt.muted2, letterSpacing: .8))),
      );
}

class EmptyBox extends StatelessWidget {
  const EmptyBox(this.title, this.text, {super.key});
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFCFDDF0), style: BorderStyle.solid)),
        child: Column(children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 15, color: Mt.muted), textAlign: TextAlign.center),
        ]),
      );
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Mt.dangerBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: Mt.dangerBorder)),
        child: Column(children: [
          Text(errorText(error), style: const TextStyle(fontSize: 16, color: Mt.dangerDeep), textAlign: TextAlign.center),
          if (onRetry != null) ...[const SizedBox(height: 12), OutlineBtn('Try again', onPressed: onRetry, height: 48)],
        ]),
      );
}

String errorText(Object e) => e is ApiException ? e.message : 'Something went wrong. Please try again.';

void toast(BuildContext context, String msg) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(msg, textAlign: TextAlign.center), duration: const Duration(milliseconds: 2800)));
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String body, required String label, Color color = Mt.blue}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      title: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      content: Text(body, style: const TextStyle(fontSize: 16, color: Mt.muted2, height: 1.45)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(children: [
          Expanded(child: OutlineBtn('Cancel', color: Mt.muted2, height: 52, onPressed: () => Navigator.pop(c, false))),
          const SizedBox(width: 10),
          Expanded(child: PrimaryButton(label, color: color, height: 52, onPressed: () => Navigator.pop(c, true))),
        ]),
      ],
    ),
  );
  return r ?? false;
}

/// Bottom sheet with the design's 28 px top radius, grabber and close button.
Future<T?> showMtSheet<T>(BuildContext context, {required String title, required WidgetBuilder builder}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(c).viewInsets.bottom + 22),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5DFEC), borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)))),
              Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                  onTap: () => Navigator.pop(c),
                  child: Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFF1F5FB), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.close_rounded, size: 20)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            builder(c),
          ]),
        ),
      ),
    );

class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.controller, this.hint, this.error, this.keyboard, this.obscure = false, this.onChanged, this.maxLines = 1, this.autofillHints});
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? error;
  final TextInputType? keyboard;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          obscureText: obscure,
          maxLines: maxLines,
          onChanged: onChanged,
          autofillHints: autofillHints,
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(hintText: hint, errorText: error, hintStyle: const TextStyle(color: Mt.faint)),
        ),
      ]);
}

class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key, this.size = 48});
  final String initials;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFBCD9FF), Color(0xFF4F97F6)]), boxShadow: Mt.shadow(.2, 18, 6)),
        child: Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * .33)),
      );
}

/// Page scaffold used by every tab/screen: gradient background, 20 px gutter, room for the floating nav.
class ScreenScroll extends StatelessWidget {
  const ScreenScroll({super.key, required this.children, this.onRefresh, this.bottomPad = 124, this.gap = 16});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double bottomPad;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
      itemCount: children.length,
      separatorBuilder: (_, _) => SizedBox(height: gap),
      itemBuilder: (_, i) => children[i],
    );
    return SafeArea(bottom: false, child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list));
  }
}

class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFF6F9FF)])),
        child: child,
      );
}
