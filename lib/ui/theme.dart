import 'dart:ui' show FontFeature;

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

  // Chart-table palette: deep hull navy, sea-chart paper, brass for computed results.
  static const darkPal = Pal._(true,
      bg: Color(0xFF0A1218),
      card: Color(0xFF111C25),
      fg: Color(0xFFE6EDF2),
      muted: Color(0xFF8FA1AF),
      accent: Color(0xFF4FC1D0),
      border: Color(0xFF1E2E3B),
      inputBg: Color(0xFF0D161E),
      btnBg: Color(0xFF172632),
      btnBorder: Color(0xFF263A4A),
      thBg: Color(0xFF0A1218),
      hover: Color(0xFF16303A),
      outBg: Color(0xFF14232E),
      btnPrimaryFg: Color(0xFF04222A));

  static const lightPal = Pal._(false,
      bg: Color(0xFFE9EEF1),
      card: Color(0xFFFFFFFF),
      fg: Color(0xFF12222D),
      muted: Color(0xFF5A6C79),
      accent: Color(0xFF0A6C86),
      border: Color(0xFFD3DDE3),
      inputBg: Color(0xFFF5F8FA),
      btnBg: Color(0xFFE4ECF0),
      btnBorder: Color(0xFFC4D1D9),
      thBg: Color(0xFFE4ECF0),
      hover: Color(0xFFDCEEF2),
      outBg: Color(0xFFE6F0F3),
      btnPrimaryFg: Color(0xFFFFFFFF));

  /// Header colours (header sits on the page background).
  Color get bar => bg;
  Color get barFg => fg;
  Color get barAccent => accent;
  /// Brass highlight for computed values.
  Color get brass => dark ? const Color(0xFFE2B866) : const Color(0xFF8A5A00);

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
      visualDensity: VisualDensity.standard,
      dividerColor: border,
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: border)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: border)),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent)),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: btnBorder, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
    );
  }
}

/// Tabular figures keep columns of numbers aligned.
const kNumFeatures = [FontFeature.tabularFigures()];
