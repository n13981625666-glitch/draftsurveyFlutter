import 'package:flutter/material.dart';

import '../core/app_model.dart';
import 'theme.dart';
import 'widgets.dart';

class TrimmingPage extends StatelessWidget {
  final AppModel m;
  const TrimmingPage({super.key, required this.m});

  Widget _holdRow(String sel, String f, String a) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Grid(cols: 3, children: [
        SelField(m, sel, label: 'Hold / Frame'),
        OutField(m, f, label: 'Fore (cm)'),
        OutField(m, a, label: 'Aft (cm)'),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CardBox(title: 'Trim Calculation', titleSize: 22, children: [
        CardBox(title: 'Profile', titleSize: 16, children: [
          NumField(m, 'cgotoloaded', label: 'Cargo to be loaded'),
          const SizedBox(height: 10),
          Grid(cols: 3, children: [
            NumField(m, 'trimming-df', label: 'DF (m)'),
            NumField(m, 'trimming-dm', label: 'DM (m)'),
            NumField(m, 'trimming-da', label: 'DA (m)'),
          ]),
          Grid(cols: 3, children: [
            OutField(m, 'trimming-trim', label: 'Trim (m)'),
            NumField(m, 'trimming-requiredTrim', label: 'Required Trim (m)'),
            OutField(m, 'trimming-requiredTrimConditon', label: 'Required Condition'),
          ]),
          Grid(cols: 3, children: [OutField(m, 'trimChanging', label: 'Trim changing')]),
        ]),
        Grid(cols: 4, children: [
          Btn('Initial Condition', () => m.importSurveyDataToTrimming('initial'), primary: true),
          Btn('Int1 Condition', () => m.importSurveyDataToTrimming('int1')),
          Btn('Int2 Condition', () => m.importSurveyDataToTrimming('int2')),
          Btn('Final Condition', () => m.importSurveyDataToTrimming('final')),
        ]),
        CardBox(title: 'Change Per 100 Mt', titleSize: 16, children: [
          _holdRow('firstHold', 'firstHoldF', 'firstHoldA'),
          _holdRow('secondHold', 'secondHoldF', 'secondHoldA'),
          Text('Distribution', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Grid(cols: 3, children: [
            OutField(m, 'firstHoldDistribution', label: 'Hold / Frame'),
            OutField(m, 'firstHoldDistributionWeight', label: 'Distribution (Mt)'),
            OutField(m, 'firstHoldDistributionWeightHeelMethod', label: 'Heeling Method'),
            OutField(m, 'secondHoldDistribution', label: 'Hold / Frame'),
            OutField(m, 'secondHoldDistributionWeight', label: 'Distribution (Mt)'),
            OutField(m, 'secondHoldDistributionWeightHeelMethod', label: 'Heeling Method'),
            const SizedBox(),
            OutField(m, 'distribution-total-weight-cell', label: 'Total Weight'),
            OutField(m, 'distribution-total-weight-cell-heel', label: 'Total Weight (heel)'),
          ]),
          const Text('Final Draft', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Grid(cols: 4, children: [
            OutField(m, 'distribution-final-df', label: 'DF (m)'),
            OutField(m, 'distribution-final-dm', label: 'DM (m)'),
            OutField(m, 'distribution-final-da', label: 'DA (m)'),
            OutField(m, 'distribution-final-trim', label: 'Trim (m)'),
          ]),
        ]),
        CardBox(title: 'Calculation', titleSize: 16, children: [
          _holdRow('firstHoldCal', 'calFirstHoldF', 'calFirstHoldA'),
          _holdRow('secondHoldCal', 'calSencondHoldF', 'calSencondHoldA'),
          _holdRow('thirdHoldCal', 'calThirdHoldF', 'calThirdHoldA'),
          Grid(cols: 3, children: [
            OutField(m, 'firstHoldCalDistribution', label: 'Hold / Frame'),
            NumField(m, 'firstHoldCalDistributionWeight', label: 'Distribution (Mt)'),
            const SizedBox(),
            OutField(m, 'secondHoldCalDistribution', label: 'Hold / Frame'),
            NumField(m, 'secondHoldCalDistributionWeight', label: 'Distribution (Mt)'),
            const SizedBox(),
            OutField(m, 'thirdHoldCalDistribution', label: 'Hold / Frame'),
            NumField(m, 'thirdHoldCalDistributionWeight', label: 'Distribution (Mt)'),
            const SizedBox(),
            const SizedBox(),
            OutField(m, 'cal-total-weight-cell', label: 'Total Weight'),
            const SizedBox(),
          ]),
          const Text('Final Draft', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Grid(cols: 4, children: [
            OutField(m, 'final-cal-df', label: 'DF (m)'),
            OutField(m, 'final-cal-dm', label: 'DM (m)'),
            OutField(m, 'final-cal-da', label: 'DA (m)'),
            OutField(m, 'final-cal-trim', label: 'Trim (m)'),
          ]),
        ]),
      ]),
    ]);
  }
}
