import 'package:flutter/material.dart';

import '../core/app_model.dart';
import '../core/registry.dart';
import 'theme.dart';
import 'widgets.dart';

class StowagePage extends StatelessWidget {
  final AppModel m;
  const StowagePage({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CardBox(title: 'Pre-Stowage Plan', titleSize: 22, children: [
        CardBox(title: 'Profile', titleSize: 16, children: [
          Grid(cols: 3, children: [
            NumField(m, 'stowage-capacity', label: 'Capacity'),
            NumField(m, 'stowage-summer-draft', label: 'Summer Draft (m)'),
            NumField(m, 'stowage-tropical-draft', label: 'Tropical Draft (m)'),
            NumField(m, 'stowage-keel-plate', label: 'Keel Plate (m)'),
            NumField(m, 'stowage-constant', label: 'Constant'),
            NumField(m, 'stowage-light-ship', label: 'Light Ship'),
            NumField(m, 'stowage-sf-cuft-mt', label: 'Cargo S.F (CuFt/Mt)'),
            NumField(m, 'stowage-sf-cum-t', label: 'Cargo S.F (m³/t)'),
            NumField(m, 'stowage-sf-cuft-lt', label: 'Cargo S.F (CuFt/lt)'),
          ]),
        ]),
        for (final k in stowageLegKeys)
          if (m.isLegVisible(k)) _leg(context, k),
        CardBox(title: 'Final Result (Mt)', titleSize: 16, children: [
          Text(m.s.get('stowage-final-result-details'), style: TextStyle(color: Pal.of(context).muted, height: 1.5)),
          const SizedBox(height: 10),
          OutField(m, 'stowage-final-result'),
        ]),
      ]),
    ]);
  }

  static const _intIndex = {'lp': 0, 'int1': 1, 'int2': 2, 'int3': 3, 'int4': 4};

  String _title(String k) {
    if (k == 'lp') return 'Loading Port';
    if (k == 'fp') return 'Discharging Port';
    return 'Intermediate Port/Position No.${k.substring(3)}';
  }

  String _detailsTitle(String k) {
    if (k == 'lp') return 'Details For Preceeding To Loading Port';
    if (k == 'fp') return m.fpLastportTitle;
    final n = int.parse(k.substring(3));
    final from = n == 1 ? 'Loading Port' : 'Int${n - 1}';
    return 'Details For Preceeding From $from To Intermediate Port/Position No.$n';
  }

  Widget _leg(BuildContext context, String k) {
    final p = 'stowage-$k';
    final isLp = k == 'lp';
    final on = m.s.checked('$p-toggle');
    final nextId = nextPortSelect[k];
    final nextIdx = (_intIndex[k] ?? 5) + 1;
    return CardBox(title: _title(k), titleSize: 17, children: [
      ChkField(m, '$p-toggle', 'Calculate R.O.B from last port/position'),
      if (on)
        CardBox(title: _detailsTitle(k), titleSize: 14, children: [
          Grid(cols: 3, children: [
            NumField(m, '$p-current-fo', label: isLp ? 'Current F.O' : 'F.O'),
            NumField(m, '$p-current-do', label: isLp ? 'Current D.O' : 'D.O'),
            NumField(m, '$p-ship-speed', label: 'Ship Speed'),
            NumField(m, '$p-distance-lp', label: isLp ? 'Distance (to L.P)' : 'Distance'),
            NumField(m, '$p-daily-fo', label: 'Daily F.O'),
            NumField(m, '$p-daily-do', label: 'Daily D.O'),
          ]),
        ]),
      Grid(cols: 3, children: [
        SelField(m, '$p-loadline', label: 'Load Line'),
        NumField(m, '$p-density', label: 'Density'),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ChkField(m, '$k-draft-limit-toggle', 'Draft Limit'),
          NumField(m, draftLimitInput[k]!),
        ]),
        NumField(m, '$p-bw', label: 'Ballast Water'),
        NumField(m, '$p-fw', label: 'Fresh Water'),
        SelField(m, '$p-sagging', label: 'Sagging (cm)'),
      ]),
      Grid(cols: 3, children: [
        NumField(m, '$p-port-fo', label: 'F.O'),
        NumField(m, '$p-port-do', label: 'D.O'),
        const SizedBox(),
        NumField(m, '$p-port-stay', label: 'Port Stay'),
        NumField(m, '$p-port-daily-fo', label: 'Port Daily F.O'),
        NumField(m, '$p-port-daily-do', label: 'Port Daily D.O'),
        NumField(m, '$p-fo-supply', label: 'F.O Supply'),
        NumField(m, '$p-do-supply', label: 'D.O Supply'),
        NumField(m, '$p-fw-supply', label: 'F.W Supply'),
      ]),
      if (nextId != null)
        Grid(cols: 3, children: [
          SelField(m, nextId, label: 'Next Port to', labels: {
            '0': 'Intermediate Port/Position No.$nextIdx',
            '1': 'Discharging Port',
          }),
        ]),
    ]);
  }
}
