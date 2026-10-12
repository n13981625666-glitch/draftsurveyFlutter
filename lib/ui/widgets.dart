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
  /// A card inside another card: tinted, no shadow.
  final bool nested;
  const CardBox({super.key, this.title, this.titleSize = 17, this.titleColor, this.trailing, this.nested = false, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final nested = this.nested || _Nest.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
        boxShadow: (p.dark || nested) ? null : const [BoxShadow(color: Color(0x120F2A3A), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Container(width: 3, height: titleSize + 2, margin: const EdgeInsets.only(right: 9), color: p.accent),
                Expanded(
                  child: Text(title!,
                      style: TextStyle(fontSize: titleSize - 1, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: p.fg)),
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

class _Nest extends InheritedWidget {
  const _Nest({required super.child});
  static bool of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<_Nest>() != null;
  @override
  bool updateShouldNotify(_Nest old) => false;
}

/// Big section heading used inside page cards.
class SectionTitle extends StatelessWidget {
  final String text;
  final double size;
  const SectionTitle(this.text, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: 0.2, color: Pal.of(context).fg)),
      );
}

/// A whole page: one outer card with the page title; cards inside it are tinted.
class PageBox extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const PageBox({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
        boxShadow: p.dark ? null : const [BoxShadow(color: Color(0x120F2A3A), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: _Nest(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) SectionTitle(title!),
          ...children,
        ]),
      ),
    );
  }
}

/// Bordered table: header row, body rows, optional footer. Rows collapse into
/// labelled blocks on narrow screens.
class TableBox extends StatelessWidget {
  final List<String> headers;
  final List<int> flex;
  final List<List<Widget>> rows;
  final Widget? footer;
  const TableBox({super.key, required this.headers, required this.flex, required this.rows, this.footer});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 520;
        final hs = TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: p.fg);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (wide)
            Container(
              color: p.thBg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                for (var i = 0; i < headers.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(flex: flex[i], child: Text(headers[i], style: hs)),
                ],
              ]),
            ),
          if (wide) Divider(height: 1, color: p.border),
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0 && !wide) Divider(height: 1, color: p.border),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: wide ? 6 : 10),
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      for (var i = 0; i < rows[r].length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(flex: flex[i], child: rows[r][i]),
                      ],
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (var i = 0; i < rows[r].length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        if (i > 0 && headers[i].isNotEmpty) Text(headers[i], style: TextStyle(fontSize: 12, color: p.muted)),
                        rows[r][i],
                      ],
                    ]),
            ),
          ],
          if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 12), child: footer!),
        ]);
      }),
    );
  }
}

/// Right-aligned or plain table-cell label.
class CellLabel extends StatelessWidget {
  final String text;
  const CellLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Pal.of(context).fg));
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
      labelStyle: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w500),
      floatingLabelStyle: TextStyle(color: out ? p.muted : p.accent, fontSize: 13, fontWeight: FontWeight.w600),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: out ? p.border : p.btnBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: out ? p.border : p.btnBorder)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.accent, width: 2)),
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
      style: TextStyle(color: locked ? p.muted : p.fg, fontSize: 15, fontFeatures: kNumFeatures),
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
      style: TextStyle(color: p.brass, fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: kNumFeatures),
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
      elevation: const WidgetStatePropertyAll(0),
      foregroundColor: WidgetStatePropertyAll(primary ? p.btnPrimaryFg : p.fg),
      side: WidgetStatePropertyAll(BorderSide(color: primary ? p.accent : p.btnBorder)),
      overlayColor: WidgetStatePropertyAll(p.accent.withOpacity(0.12)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2)),
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
        textAlign: align, style: TextStyle(color: p.fg, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: 14, fontFeatures: kNumFeatures));
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
      decoration: BoxDecoration(color: p.inputBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.border)),
      child: SingleChildScrollView(
        child: SelectableText(text, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45, color: p.muted)),
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
