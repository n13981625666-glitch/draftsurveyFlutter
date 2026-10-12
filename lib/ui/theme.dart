import 'package:flutter/material.dart';

/// Colour tokens of the original CSS (dark = default, light = [data-theme="light"]).
class Pal {
  final Color bg, card, fg, muted, accent, border, inputBg, btnBg, btnBorder, thBg, hover, outBg;
  final Color ok = const Color(0xFF22C55E);
  final Color warn = const Color(0xFFF59E0B);
  final Color err = const Color(0xFFEF4444);
  final Color btnPrimaryFg;
  final bool dark;
  const Pal._(this.dark,
      {required this.bg,
      required this.card,
      required this.fg,
      required this.muted,
      required this.accent,
      required this.border,
      required this.inputBg,
      required this.btnBg,
      required this.btnBorder,
      required this.thBg,
      required this.hover,
      required this.outBg,
      required this.btnPrimaryFg});

  static const darkPal = Pal._(true,
      bg: Color(0xFF0B1220),
      card: Color(0xFF121A2B),
      fg: Color(0xFFE8EEF7),
      muted: Color(0xFFA9B5C5),
      accent: Color(0xFF65C3FF),
      border: Color(0xFF243356),
      inputBg: Color(0xFF0F1626),
      btnBg: Color(0xFF0F1626),
      btnBorder: Color(0xFF2A3555),
      thBg: Color(0xFF0B1220),
      hover: Color(0xFF18213A),
      outBg: Color(0xFF0D1422),
      btnPrimaryFg: Color(0xFF00243F));

  static const lightPal = Pal._(false,
      bg: Color(0xFFF7F9FC),
      card: Color(0xFFFFFFFF),
      fg: Color(0xFF21304B),
      muted: Color(0xFF535F70),
      accent: Color(0xFF3FA2FD),
      border: Color(0xFFC9D6EA),
      inputBg: Color(0xFFF2F6FA),
      btnBg: Color(0xFFF2F6FA),
      btnBorder: Color(0xFFC9D6EA),
      thBg: Color(0xFFE9F2FD),
      hover: Color(0xFFE9F2FD),
      outBg: Color(0xFFEAF0F7),
      btnPrimaryFg: Color(0xFFFFFFFF));

  static Pal of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? darkPal : lightPal;

  ThemeData toTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: dark ? Brightness.dark : Brightness.light)
          .copyWith(primary: accent, surface: card),
      canvasColor: card,
      dividerColor: border,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: fg, displayColor: fg),
    );
  }
}
