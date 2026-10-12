import 'package:flutter/material.dart';

import '../core/app_model.dart';
import 'theme.dart';
import 'widgets.dart';

class TrimmingPage extends StatelessWidget {
  final AppModel m;
  const TrimmingPage({super.key, required this.m});

  Widget _pair(Widget l, Widget r) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 760) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: l),
            const SizedBox(width: 14),
            Expanded(child: r),
          ]);
        }
        return Column(children: [l, r]);
      });

  List<Widget> _holdRow(String sel, String f, String a) => [SelField(m, sel), OutField(m, f), OutField(m, a)];

  Widget _total(Pal p, List<Widget> cells) => Row(children: [
        Expanded(flex: 2, child: Text('Total Weight:', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: p.fg))),
        for (final c in cells) ...[const SizedBox(width: 10), Expanded(flex: 2, child: c)],
      ]);

  Widget _finalDraft(Pal p, String pre) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Final Draft', size: 18),
        Grid(cols: 4, children: [
          OutField(m, '$pre-df', label: 'DF (m)'),
          OutField(m, '$pre-dm', label: 'DM (m)'),
          OutField(m, '$pre-da', label: 'DA (m)'),
          OutField(m, '$pre-trim', label: 'Trim (m)'),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return PageBox(title: 'Trim Calculation', children: [
      CardBox(title: 'Profile', titleSize: 18, children: [
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
      CardBox(title: 'Change Per 100 Mt', titleSize: 18, children: [
        _pair(
          TableBox(headers: const ['Hold', 'Fore (cm)', 'Aft (cm)'], flex: const [2, 2, 2], rows: [
            _holdRow('firstHold', 'firstHoldF', 'firstHoldA'),
            _holdRow('secondHold', 'secondHoldF', 'secondHoldA'),
          ]),
          TableBox(
            headers: const ['Hold', 'Distribution (Mt)', 'Heeling Method'],
            flex: const [2, 2, 2],
            rows: [
              [OutField(m, 'firstHoldDistribution'), OutField(m, 'firstHoldDistributionWeight'), OutField(m, 'firstHoldDistributionWeightHeelMethod')],
              [OutField(m, 'secondHoldDistribution'), OutField(m, 'secondHoldDistributionWeight'), OutField(m, 'secondHoldDistributionWeightHeelMethod')],
            ],
            footer: _total(p, [OutField(m, 'distribution-total-weight-cell'), OutField(m, 'distribution-total-weight-cell-heel')]),
          ),
        ),
        _finalDraft(p, 'distribution-final'),
      ]),
      CardBox(title: 'Calculation', titleSize: 18, children: [
        _pair(
          TableBox(headers: const ['Hold', 'Fore (cm)', 'Aft (cm)'], flex: const [2, 2, 2], rows: [
            _holdRow('firstHoldCal', 'calFirstHoldF', 'calFirstHoldA'),
            _holdRow('secondHoldCal', 'calSencondHoldF', 'calSencondHoldA'),
            _holdRow('thirdHoldCal', 'calThirdHoldF', 'calThirdHoldA'),
          ]),
          TableBox(
            headers: const ['Hold', 'Distribution (Mt)'],
            flex: const [2, 3],
            rows: [
              [OutField(m, 'firstHoldCalDistribution'), NumField(m, 'firstHoldCalDistributionWeight')],
              [OutField(m, 'secondHoldCalDistribution'), NumField(m, 'secondHoldCalDistributionWeight')],
              [OutField(m, 'thirdHoldCalDistribution'), NumField(m, 'thirdHoldCalDistributionWeight')],
            ],
            footer: _total(p, [OutField(m, 'cal-total-weight-cell')]),
          ),
        ),
        _finalDraft(p, 'final-cal'),
      ]),
    ]);
  }
}
