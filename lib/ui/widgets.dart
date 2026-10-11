import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_model.dart';
import 'theme.dart';

/// A card with an optional title (the `.card` / `h2` / `h3` blocks of the original page).
class CardBox extends StatelessWidget {
  final String? title;
  final double titleSize;
  final Color? titleColor;
  final List<Widget> children;
  final Widget? trailing;
  const CardBox({super.key, this.title, this.titleSize = 17, this.titleColor, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(
                  child: Text(title!,
                      style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w700, color: titleColor ?? p.fg)),
                ),
                if (trailing != null) trailing!,
              ]),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// Lays children out in rows of [cols] equal columns; fewer columns on narrow screens.
class Grid extends StatelessWidget {
  final List<Widget> children;
  final int cols;
  final double gap;
  const Grid({super.key, required this.children, this.cols = 2, this.gap = 10});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      var n = cols;
      if (c.maxWidth < 330) {
        n = 1;
      } else if (c.maxWidth < 520 && n > 2) {
        n = 2;
      }
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += n) {
        final chunk = children.sublist(i, i + n > children.length ? children.length : i + n);
        rows.add(Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var j = 0; j < n; j++) ...[
              if (j > 0) SizedBox(width: gap),
              Expanded(child: j < chunk.length ? chunk[j] : const SizedBox()),
            ],
          ]),
        ));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
    });
  }
}

InputDecoration _deco(Pal p, String? label, {bool out = false, String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: out ? p.outBg : p.inputBg,
      labelStyle: TextStyle(color: p.muted, fontSize: 13),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.btnBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.btnBorder)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.accent, width: 1.6)),
    );

final _numFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9eE+\-.,]'));

/// Editable number field bound to a store id.
class NumField extends StatelessWidget {
  final AppModel m;
  final String id;
  final String? label;
  final bool readOnly;
  const NumField(this.m, this.id, {super.key, this.label, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final disabled = m.s.isDisabled(id);
    final locked = readOnly || disabled;
    return TextField(
      controller: m.s.controller(id),
      enabled: !disabled,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [_numFormatter],
      style: TextStyle(color: locked ? p.muted : p.fg, fontSize: 15),
      decoration: _deco(p, label, out: locked),
      onChanged: (_) => m.s.typed(id),
    );
  }
}

/// Calculated value (read only).
class OutField extends StatelessWidget {
  final AppModel m;
  final String id;
  final String? label;
  const OutField(this.m, this.id, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TextField(
      controller: m.s.controller(id),
      readOnly: true,
      style: TextStyle(color: p.fg, fontSize: 15, fontWeight: FontWeight.w600),
      decoration: _deco(p, label, out: true),
    );
  }
}

class SelField extends StatelessWidget {
  final AppModel m;
  final String id;
  final String? label;
  final Map<String, String>? labels; // value -> text shown
  const SelField(this.m, this.id, {super.key, this.label, this.labels});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final opts = m.s.options[id] ?? const <String>[];
    var v = m.s.get(id);
    if (!opts.contains(v)) v = opts.isEmpty ? '' : opts.first;
    final disabled = m.s.isDisabled(id);
    return InputDecorator(
      decoration: _deco(p, label, out: disabled),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: opts.isEmpty ? null : v,
          isExpanded: true,
          isDense: true,
          dropdownColor: p.card,
          style: TextStyle(color: p.fg, fontSize: 15),
          items: [
            for (final o in opts)
              DropdownMenuItem<String>(
                value: o,
                child: Text(labels != null ? (labels![o] ?? o) : (o.isEmpty ? '-' : o), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: disabled ? null : (nv) {
            if (nv != null) m.s.select(id, nv);
          },
        ),
      ),
    );
  }
}

class ChkField extends StatelessWidget {
  final AppModel m;
  final String id;
  final String label;
  const ChkField(this.m, this.id, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return InkWell(
      onTap: () => m.s.toggle(id, !m.s.checked(id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(value: m.s.checked(id), onChanged: (v) => m.s.toggle(id, v ?? false)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: TextStyle(color: p.fg, fontSize: 14))),
        ]),
      ),
    );
  }
}

class Btn extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool primary;
  final Widget? icon;
  const Btn(this.text, this.onPressed, {super.key, this.primary = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(primary ? p.accent : p.btnBg),
      foregroundColor: WidgetStatePropertyAll(primary ? p.btnPrimaryFg : p.fg),
      side: WidgetStatePropertyAll(BorderSide(color: primary ? p.accent : p.btnBorder)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    );
    final label = Text(text, textAlign: TextAlign.center);
    return icon == null
        ? OutlinedButton(style: style, onPressed: onPressed, child: label)
        : OutlinedButton.icon(style: style, onPressed: onPressed, icon: icon!, label: label);
  }
}

/// Read-only table cell text (the td cells of the original tables).
class CellText extends StatelessWidget {
  final String text;
  final bool bold;
  final TextAlign align;
  const CellText(this.text, {super.key, this.bold = false, this.align = TextAlign.right});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Text(text,
        textAlign: align, style: TextStyle(color: p.fg, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: 14));
  }
}

class Muted extends StatelessWidget {
  final String text;
  final double size;
  const Muted(this.text, {super.key, this.size = 13});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: Pal.of(context).muted, fontSize: size, height: 1.4));
}

/// Log box (the <pre> of the original page).
class LogBox extends StatelessWidget {
  final String text;
  const LogBox(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 60, maxHeight: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.inputBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.btnBorder)),
      child: SingleChildScrollView(
        child: SelectableText(text, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: p.fg)),
      ),
    );
  }
}

/// Double-tap (mouse) or long-press (touch) on [child].
class Gesture2 extends StatelessWidget {
  final Widget child;
  final VoidCallback onTrigger;
  const Gesture2({super.key, required this.child, required this.onTrigger});
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: onTrigger,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onTrigger();
        },
        child: child,
      );
}

/// Toast helper (SnackBar based, one at a time like a stack of short messages).
void showToast(BuildContext context, String text, ToastKind kind, {int? ms}) {
  final p = Pal.of(context);
  final colors = {
    ToastKind.info: p.btnBg,
    ToastKind.success: p.ok,
    ToastKind.warn: p.warn,
    ToastKind.error: p.err,
  };
  final fg = kind == ToastKind.info ? p.fg : const Color(0xFF0B1220);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    backgroundColor: colors[kind],
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    duration: Duration(milliseconds: ms ?? (kind == ToastKind.warn ? 6000 : (kind == ToastKind.error ? 5000 : 3000))),
  ));
}
