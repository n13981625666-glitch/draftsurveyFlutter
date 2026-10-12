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
    return PageBox(title: 'Sounding Calculation', children: [
      const SectionTitle('Profile', size: 18),
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
      const SizedBox(height: 8),
      const SectionTitle('Sounding', size: 18),
      Wrap(spacing: 10, runSpacing: 8, children: [
        Btn('Record', m.recordSounding, primary: true),
        Btn('Export PDF', actions.printSounding),
        Btn(locked > 0 ? 'Unlock all ($locked)' : 'Unlock all', locked > 0 ? m.unlockAllTanks : null,
            icon: const Icon(Icons.lock_open, size: 16)),
      ]),
      const SizedBox(height: 12),
      TableBox(
        headers: const ['Tank', 'Sounding (m)', 'Volume (m³)', 'Volume Corr. (m³)', 'Weight (t)', ''],
        flex: const [2, 3, 2, 3, 2, 1],
        rows: [
          for (final n in m.ship.tankNumbers)
            [
              CellLabel(m.ship.tankNames[n] ?? ''),
              NumField(m, tankKeyId(n, 'sounding'), readOnly: m.isTankLocked(n)),
              OutField(m, tankKeyId(n, 'volume')),
              NumField(m, tankKeyId(n, 'correction'), readOnly: m.isTankLocked(n)),
              OutField(m, tankKeyId(n, 'weight')),
              IconButton(
                tooltip: m.isTankLocked(n) ? 'Locked — click to unlock and recalculate' : 'Lock this tank (freeze its inputs and results)',
                onPressed: () => m.toggleTankLock(n),
                alignment: Alignment.centerLeft,
                icon: Icon(m.isTankLocked(n) ? Icons.lock : Icons.lock_open, color: m.isTankLocked(n) ? p.accent : p.muted, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
        ],
        footer: Gesture2(
          onTrigger: m.fillBallastFromSounding,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              const Text('Total Weight:  ', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(m.s.get('__tankTotal'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: p.brass, fontFeatures: kNumFeatures)),
              const Text(' t'),
            ]),
          ),
        ),
      ),
      const Muted('Double-click / long-press the total to copy it into Ballast of the draft survey you looked at last.', size: 12),
      const SizedBox(height: 14),
      CardBox(title: 'Log', titleSize: 16, children: [
        const Muted('Results update as you type. Press Record to keep a snapshot here.'),
        const SizedBox(height: 8),
        LogBox(m.soundingLog),
      ]),
    ]);
  }

}
