import 'package:flutter/material.dart';

import '../core/app_model.dart';
import '../core/registry.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

class SoundingPage extends StatelessWidget {
  final AppModel m;
  final AppActions actions;
  const SoundingPage({super.key, required this.m, required this.actions});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final locked = m.tankLocks.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CardBox(title: 'Sounding Calculation', titleSize: 22, children: [
        const Text('Profile', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Grid(cols: 4, children: [
          NumField(m, 'sounding-df', label: 'DF (m)'),
          NumField(m, 'sounding-da', label: 'DA (m)'),
          NumField(m, 'sounding-trim', label: 'Trim (m)'),
          NumField(m, 'sounding-density', label: 'Density (t/m³)'),
        ]),
        Grid(cols: 4, children: [
          Btn('Initial Condition', () => m.importSurveyDataToSounding('initial'), primary: true),
          Btn('Int1 Condition', () => m.importSurveyDataToSounding('int1')),
          Btn('Int2 Condition', () => m.importSurveyDataToSounding('int2')),
          Btn('Final Condition', () => m.importSurveyDataToSounding('final')),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Sounding', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Btn('Record', m.recordSounding, primary: true),
          Btn('Export PDF', actions.printSounding),
          Btn(locked > 0 ? 'Unlock all ($locked)' : 'Unlock all', locked > 0 ? m.unlockAllTanks : null,
              icon: const Icon(Icons.lock_open, size: 16)),
        ]),
        const SizedBox(height: 12),
        for (final n in m.ship.tankNumbers) _tank(context, n),
        Gesture2(
          onTrigger: m.fillBallastFromSounding,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border, width: 2))),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              const Text('Total Weight:  ', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(m.s.get('__tankTotal'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: p.accent)),
              const Text(' t'),
            ]),
          ),
        ),
        const Muted('Double-click / long-press the total to copy it into Ballast of the draft survey you looked at last.', size: 12),
      ]),
      CardBox(title: 'Log', titleSize: 16, children: [
        const Muted('Results update as you type. Press Record to keep a snapshot here.'),
        const SizedBox(height: 8),
        LogBox(m.soundingLog),
      ]),
    ]);
  }

  Widget _tank(BuildContext context, int n) {
    final p = Pal.of(context);
    final isLocked = m.isTankLocked(n);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLocked ? p.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isLocked ? p.accent : p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m.ship.tankNames[n] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          IconButton(
            tooltip: isLocked ? 'Locked — click to unlock and recalculate' : 'Lock this tank (freeze its inputs and results)',
            onPressed: () => m.toggleTankLock(n),
            icon: Icon(isLocked ? Icons.lock : Icons.lock_open, color: isLocked ? p.accent : p.muted, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ]),
        Grid(cols: 4, children: [
          NumField(m, tankKeyId(n, 'sounding'), label: 'Sounding (m)', readOnly: isLocked),
          OutField(m, tankKeyId(n, 'volume'), label: 'Volume (m³)'),
          NumField(m, tankKeyId(n, 'correction'), label: 'Volume Corr. (m³)', readOnly: isLocked),
          OutField(m, tankKeyId(n, 'weight'), label: 'Weight (t)'),
        ]),
      ]),
    );
  }
}
