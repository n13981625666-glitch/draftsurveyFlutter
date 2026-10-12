import 'package:flutter/material.dart';

import '../core/app_model.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

/// One draft survey card (Initial / Int1 / Int2 / Final).
class SurveyPage extends StatelessWidget {
  final AppModel m;
  final AppActions actions;
  final String tab;
  const SurveyPage({super.key, required this.m, required this.actions, required this.tab});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final sec = AppModel.surveyIdOf(tab);
    String id(String k) => '$sec-$k';
    final solve = m.s.checked(id('solveConst'));

    final inputs = CardBox(title: '1) Draft Inputs', children: [
      Grid(children: [
        NumField(m, id('f_wp'), label: 'Draft Fore Port (m)'),
        NumField(m, id('f_ws'), label: 'Draft Fore Starboard (m)'),
        NumField(m, id('m_wp'), label: 'Draft Mid Port (m)'),
        NumField(m, id('m_ws'), label: 'Draft Mid Starboard (m)'),
        NumField(m, id('a_wp'), label: 'Draft Aft Port (m)'),
        NumField(m, id('a_ws'), label: 'Draft Aft Starboard (m)'),
      ]),
      NumField(m, id('density'), label: 'Density (seawater, t/m³)'),
      const SizedBox(height: 10),
      Grid(children: [
        NumField(m, id('fuel'), label: 'Fuel Oil'),
        NumField(m, id('diesel'), label: 'Diesel Oil'),
        NumField(m, id('fresh'), label: 'Fresh Water'),
        NumField(m, id('ballast'), label: 'Ballast'),
        NumField(m, id('others'), label: 'Others'),
        NumField(m, id('constant'), label: 'Constant'),
      ]),
    ]);

    final props = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Ship Properties'),
      Grid(children: [
        NumField(m, id('lightShip'), label: 'Light Ship (t)'),
        NumField(m, id('breadth'), label: 'Breadth (m)'),
        NumField(m, id('keelPlate'), label: 'Keel Plate (m)'),
        NumField(m, id('lbp'), label: 'LBP (m)'),
        SelField(m, id('selLF'), label: 'LF'),
        SelField(m, id('selLM'), label: 'LM'),
        SelField(m, id('selLA'), label: 'LA'),
      ]),
      Grid(children: [
        Btn('Compute', () => m.computeForSection(sec), primary: true),
        Btn('Export PDF Report', actions.exportReport),
        Btn('Import Data', actions.importData),
        Btn('Export Data', actions.exportData),
      ]),
    ]);

    final results = CardBox(title: 'Results', titleSize: 16, children: [
      Grid(cols: 3, children: [
        OutField(m, id('heel'), label: 'Transverse Heel'),
        OutField(m, id('trim'), label: 'Trim (m)'),
        OutField(m, id('hogSag'), label: 'Hog / Sag (cm)'),
        OutField(m, id('corrF'), label: 'Corrected F (m)'),
        OutField(m, id('corrM'), label: 'Corrected M (m)'),
        OutField(m, id('corrA'), label: 'Corrected A (m)'),
      ]),
      Grid(cols: 3, children: [
        OutField(m, id('qMean'), label: 'Quarter Mean (m)'),
        OutField(m, id('disp'), label: 'Displacement (t)'),
        const SizedBox(),
        OutField(m, id('c1'), label: "1st Corr'n (t)"),
        OutField(m, id('c2'), label: "2nd Corr'n (t)"),
        OutField(m, id('tpc'), label: 'TPC (t/cm)'),
      ]),
      Grid(cols: 3, children: [OutField(m, id('trueDisp'), label: 'True Displacement (t)')]),
      Row(children: [
        Expanded(child: _mode(context, 'Calculate Cargo', !solve, () => m.setSolveMode(sec, false))),
        const SizedBox(width: 8),
        Expanded(child: _mode(context, 'Calculate Constant', solve, () => m.setSolveMode(sec, true))),
      ]),
      const SizedBox(height: 12),
      Grid(children: [
        Gesture2(
          onTrigger: () => m.foldCargoIntoBallast(sec),
          child: NumField(m, id("cargoWeight"), label: "Cargo Weight (t)"),
        ),
        const SizedBox(),
        NumField(m, id('blShore'), label: 'B/L or Shore Figure (t)'),
        OutField(m, id('difference'), label: 'Difference (t)'),
      ]),
    ]);

    final log = CardBox(title: 'Log', titleSize: 16, children: [
      const Muted('Results update as you type. Press Compute to keep a snapshot here.'),
      const SizedBox(height: 8),
      LogBox(m.surveyLogs[sec] ?? ''),
    ]);

    return PageBox(children: [
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 760) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: inputs),
            const SizedBox(width: 14),
            Expanded(child: props),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [inputs, const SizedBox(height: 8), props]);
      }),
      Divider(height: 28, color: p.border),
      results,
      log,
    ]);
  }

  Widget _mode(BuildContext context, String text, bool active, VoidCallback onTap) {
    final p = Pal.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? p.accent : p.btnBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? p.accent : p.btnBorder),
        ),
        child: Text(text,
            style: TextStyle(fontWeight: FontWeight.w700, color: active ? p.btnPrimaryFg : p.fg, fontSize: 14)),
      ),
    );
  }
}
