import 'package:flutter/material.dart';

import '../core/app_model.dart';
import '../core/registry.dart';
import 'theme.dart';
import 'widgets.dart';

class ArrivalPage extends StatelessWidget {
  final AppModel m;
  const ArrivalPage({super.key, required this.m});

  Widget _adder(BuildContext context, String kind, String label) {
    final p = Pal.of(context);
    final n = kind == 'tank' ? m.conditionTankRows : m.conditionUserRows;
    final base = kind == 'tank' ? conditionTankBase : conditionUserBase;
    final max = kind == 'tank' ? conditionTankMax : conditionUserMax;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Text(label, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
        const Spacer(),
        IconButton.outlined(
            tooltip: 'Remove last',
            onPressed: n <= base ? null : () => m.arrivalRowsChanged(kind, false),
            icon: const Icon(Icons.remove, size: 18)),
        const SizedBox(width: 6),
        IconButton.outlined(
            tooltip: 'Add load',
            onPressed: n >= max ? null : () => m.arrivalRowsChanged(kind, true),
            icon: const Icon(Icons.add, size: 18)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = m.ship.capacityPlan.keys.toList();
    final labels = <String, String>{'': '-'};
    m.s.options['condition-load1-location']?.skip(1).toList().asMap().forEach((i, v) => labels[v] = plan[i]);
    return CardBox(title: 'Arrival Condition Calculation', titleSize: 22, children: [
      CardBox(title: 'Initial Condition', titleSize: 16, children: [
        Grid(children: [
          NumField(m, 'condition-df', label: 'DF (m)'),
          NumField(m, 'condition-da', label: 'DA (m)'),
          NumField(m, 'condition-dm', label: 'DM (m)'),
          NumField(m, 'condition-density', label: 'Density (t/m³)'),
        ]),
      ]),
      CardBox(children: [
        for (var i = 0; i < m.conditionTankRows; i++) ...[
          Text('Load ${conditionKey('tank', i)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Grid(cols: 3, children: [
            NumField(m, 'condition-load${conditionKey('tank', i)}', label: 'Weight (Mt)'),
            OutField(m, 'condition-load${conditionKey('tank', i)}-long', label: 'Longitudinal'),
            SelField(m, 'condition-load${conditionKey('tank', i)}-location', label: 'Location', labels: labels),
          ]),
        ],
        _adder(context, 'tank', 'Loads in tanks'),
        for (var i = 0; i < m.conditionUserRows; i++) ...[
          Text('Load ${conditionKey('user', i)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Grid(cols: 3, children: [
            NumField(m, 'condition-load${conditionKey('user', i)}', label: 'Weight (Mt)'),
            NumField(m, 'condition-load${conditionKey('user', i)}-long', label: 'Longitudinal'),
            OutField(m, 'condition-load${conditionKey('user', i)}-location', label: 'Location'),
          ]),
        ],
        _adder(context, 'user', 'User-defined loads'),
        const Text('Final Condition', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Grid(children: [
          OutField(m, 'final-condition-df', label: 'DF (m)'),
          OutField(m, 'final-condition-da', label: 'DA (m)'),
          OutField(m, 'final-condition-dm', label: 'DM (m)'),
          NumField(m, 'final-condition-density', label: 'Density (t/m³)'),
        ]),
      ]),
    ]);
  }
}

class MiscPage extends StatelessWidget {
  final AppModel m;
  const MiscPage({super.key, required this.m});

  @override
  Widget build(BuildContext context) {
    return CardBox(title: 'Miscellaneous Calculation', titleSize: 22, children: [
      CardBox(title: 'Draft Calculation by Heel', titleSize: 16, children: [
        Grid(children: [
          NumField(m, 'misc-breadth', label: 'Breadth'),
          const SizedBox(),
          SelField(m, 'observedSide', label: 'Which side did you observe?', labels: const {
            'port': 'Port side',
            'starboard': 'Starboard side',
          }),
          NumField(m, 'draft-read', label: 'Draft Observed'),
          SelField(m, 'heelDir', label: 'Heel direction (which side is down)', labels: const {
            'port': 'Port side down',
            'starboard': 'Starboard side down',
          }),
          NumField(m, 'heelAngle', label: 'Heel angle (deg)'),
        ]),
        const Text('Result', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Grid(children: [
          OutField(m, 'draft-opposited', label: 'Opposite Draft'),
          OutField(m, 'draft-difference', label: 'Draft Difference'),
        ]),
      ]),
      CardBox(title: 'Interpolation Calculation', titleSize: 16, children: [
        Grid(children: [
          NumField(m, 'interp-x0', label: 'x₀'),
          NumField(m, 'interp-y0', label: 'y₀'),
          NumField(m, 'interp-x1', label: 'x₁'),
          NumField(m, 'interp-y1', label: 'y₁'),
          NumField(m, 'interp-x', label: 'x (to interpolate)'),
          const SizedBox(),
        ]),
        const Text('Result', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Grid(children: [OutField(m, 'interp-y', label: 'Interpolated y')]),
      ]),
      CardBox(title: 'Dewpoint Calculation', titleSize: 16, children: [
        Grid(children: [
          NumField(m, 'dewpoint-dry', label: 'Dry Bulb Temperature (°C)'),
          NumField(m, 'dewpoint-wet', label: 'Wet Bulb Temperature (°C)'),
          NumField(m, 'dewpoint-pressure', label: 'Pressure (hPa)'),
          const SizedBox(),
        ]),
        const Text('Result', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Grid(children: [OutField(m, 'dewpoint-value', label: 'Dew Point (°C)')]),
      ]),
    ]);
  }
}
