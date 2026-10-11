import 'field_store.dart';
import 'ship.dart';
import 'util.dart';

const surveySections = ['survey-0', 'survey-1', 'survey-2', 'survey-3'];
const dataPages = <List<String>>[
  ['sounding', 'sounding'],
  ['trimming', 'trimming'],
  ['stowage', 'stowage'],
  ['arrivalCondition', 'arrivalCondition'],
  ['miscellaneous', 'miscellaneous'],
];

const stowageLegKeys = ['lp', 'int1', 'int2', 'int3', 'int4', 'fp'];
const intKeys = ['int1', 'int2', 'int3', 'int4'];
const nextPortSelect = {
  'lp': 'stowage-ld-next-port',
  'int1': 'stowage-int1-next-port',
  'int2': 'stowage-int2-next-port',
  'int3': 'stowage-int3-next-port',
  'int4': 'stowage-int4-next-port',
};
const draftLimitInput = {
  'lp': 'stowage-draft-limit-1',
  'int1': 'stowage-draft-limit-2',
  'int2': 'stowage-draft-limit-3',
  'fp': 'stowage-draft-limit-4',
  'int3': 'stowage-draft-limit-5',
  'int4': 'stowage-draft-limit-6',
};

/// The five hold drop-downs of the Trimming page: id, preferred hold, fallback index.
const holdSelects = <List<Object>>[
  ['firstHold', 'H2', 1],
  ['secondHold', 'H4', 3],
  ['firstHoldCal', 'H2', 1],
  ['secondHoldCal', 'H3', 2],
  ['thirdHoldCal', 'H4', 3],
];

const surveyInputKeys = [
  'f_wp', 'f_ws', 'm_wp', 'm_ws', 'a_wp', 'a_ws', 'density', 'fuel', 'diesel', 'fresh', 'ballast', 'others', 'constant'
];

const conditionTankBase = 3, conditionTankMax = 20, conditionUserBase = 1, conditionUserMax = 26;

String tankKeyId(int n, String what) {
  switch (what) {
    case 'sounding':
      return 'bwtank$n';
    case 'volume':
      return 'bwtank$n-volume';
    case 'correction':
      return 'bwtank$n-vol-corr';
    default:
      return 'bwtank${n}weight';
  }
}

String conditionKey(String kind, int index) => kind == 'tank' ? '${index + 1}' : String.fromCharCode(65 + index);

void registerAll(FieldStore s, ShipData ship) {
  // ---------------- draft survey cards ----------------
  const defaults = {
    'f_wp': '12.800', 'f_ws': '12.800', 'm_wp': '13.000', 'm_ws': '13.000', 'a_wp': '13.000', 'a_ws': '13.000',
    'density': '1.025', 'fuel': '680.00', 'diesel': '120.00', 'fresh': '220.00', 'ballast': '200.00',
    'others': '0.00', 'constant': '300.00',
  };
  for (final sec in surveySections) {
    final p = '$sec-';
    for (final k in surveyInputKeys) {
      s.register(FieldDef('$p$k', FK.num, sec, def: defaults[k]!));
    }
    for (final k in ['lightShip', 'breadth', 'keelPlate', 'lbp']) {
      s.register(FieldDef('$p$k', FK.num, sec, disabled: true));
    }
    s.register(FieldDef('${p}selLF', FK.sel, sec, def: jsNum(ship.lf.first)), opts: ship.lf.map(jsNum).toList());
    s.register(FieldDef('${p}selLM', FK.sel, sec, def: jsNum(ship.lm.first)), opts: ship.lm.map(jsNum).toList());
    s.register(FieldDef('${p}selLA', FK.sel, sec, def: jsNum(ship.la.first)), opts: ship.la.map(jsNum).toList());
    for (final k in ['heel', 'trim', 'hogSag', 'corrF', 'corrM', 'corrA', 'qMean', 'disp', 'c1', 'c2', 'tpc', 'trueDisp', 'difference']) {
      s.register(FieldDef('$p$k', FK.text, sec, disabled: true));
    }
    s.register(FieldDef('${p}cargoWeight', FK.num, sec)); // enabled only while solving for the constant
    s.register(FieldDef('${p}blShore', FK.num, sec, def: '0.00'));
    s.register(FieldDef('${p}solveConst', FK.chk, sec));
  }

  // ---------------- sounding ----------------
  s.register(FieldDef('sounding-df', FK.num, 'sounding'));
  s.register(FieldDef('sounding-da', FK.num, 'sounding'));
  s.register(FieldDef('sounding-trim', FK.num, 'sounding', disabled: true));
  s.register(FieldDef('sounding-density', FK.num, 'sounding', def: '1.025'));
  for (final n in ship.tankNumbers) {
    s.register(FieldDef(tankKeyId(n, 'sounding'), FK.num, 'sounding'));
    s.register(FieldDef(tankKeyId(n, 'correction'), FK.num, 'sounding'));
    s.register(FieldDef(tankKeyId(n, 'volume'), FK.cell, 'sounding', def: '-'));
    s.register(FieldDef(tankKeyId(n, 'weight'), FK.cell, 'sounding', def: '-'));
  }
  s.register(FieldDef('__tankTotal', FK.cell, 'sounding', def: '-'));

  // ---------------- trimming ----------------
  const t = 'trimming';
  s.register(FieldDef('cgotoloaded', FK.num, t, def: '1000.000'));
  s.register(FieldDef('trimming-df', FK.num, t, def: '13.300'));
  s.register(FieldDef('trimming-dm', FK.num, t, def: '13.500'));
  s.register(FieldDef('trimming-da', FK.num, t, def: '13.800'));
  s.register(FieldDef('trimming-trim', FK.num, t, disabled: true));
  s.register(FieldDef('trimming-requiredTrim', FK.num, t, def: '0.300'));
  s.register(FieldDef('trimming-requiredTrimConditon', FK.text, t, disabled: true));
  s.register(FieldDef('trimChanging', FK.num, t, disabled: true));
  for (final h in holdSelects) {
    final pref = h[1] as String;
    final idx = h[2] as int;
    final def = ship.holdIds.contains(pref)
        ? pref
        : (ship.holdIds.isEmpty ? '' : ship.holdIds[idx < ship.holdIds.length - 1 ? idx : ship.holdIds.length - 1]);
    s.register(FieldDef(h[0] as String, FK.sel, t, def: def), opts: ship.holdIds);
  }
  for (final id in [
    'firstHoldF', 'firstHoldA', 'secondHoldF', 'secondHoldA', 'calFirstHoldF', 'calFirstHoldA',
    'calSencondHoldF', 'calSencondHoldA', 'calThirdHoldF', 'calThirdHoldA'
  ]) {
    s.register(FieldDef(id, FK.cell, t, def: '-'));
  }
  for (final id in [
    'firstHoldDistribution', 'secondHoldDistribution', 'firstHoldCalDistribution', 'secondHoldCalDistribution',
    'thirdHoldCalDistribution'
  ]) {
    s.register(FieldDef(id, FK.text, t, disabled: true));
  }
  for (final id in [
    'firstHoldDistributionWeight', 'secondHoldDistributionWeight', 'firstHoldDistributionWeightHeelMethod',
    'secondHoldDistributionWeightHeelMethod', 'distribution-total-weight-cell', 'distribution-total-weight-cell-heel',
    'cal-total-weight-cell', 'distribution-final-df', 'distribution-final-dm', 'distribution-final-da',
    'distribution-final-trim', 'final-cal-df', 'final-cal-dm', 'final-cal-da', 'final-cal-trim'
  ]) {
    s.register(FieldDef(id, FK.num, t, disabled: true));
  }
  s.register(FieldDef('firstHoldCalDistributionWeight', FK.num, t, def: '617'));
  s.register(FieldDef('secondHoldCalDistributionWeight', FK.num, t, def: '0'));
  s.register(FieldDef('thirdHoldCalDistributionWeight', FK.num, t, def: '383'));

  // ---------------- pre-stowage ----------------
  const w = 'stowage';
  s.register(FieldDef('stowage-capacity', FK.num, w, def: '71637.600'));
  s.register(FieldDef('stowage-summer-draft', FK.num, w, def: '13.592'));
  s.register(FieldDef('stowage-tropical-draft', FK.num, w, def: '14.115'));
  s.register(FieldDef('stowage-keel-plate', FK.num, w, def: '0.000'));
  s.register(FieldDef('stowage-constant', FK.num, w, def: '300.000'));
  s.register(FieldDef('stowage-light-ship', FK.num, w, def: '11657.000'));
  s.register(FieldDef('stowage-sf-cuft-mt', FK.num, w, def: '41.000'));
  s.register(FieldDef('stowage-sf-cum-t', FK.num, w, def: '1.160'));
  s.register(FieldDef('stowage-sf-cuft-lt', FK.num, w, def: '41.660'));
  const legDef = {
    // leg: [bw, fw, port-fo, port-do, port-stay, daily-fo, daily-do, fw-supply]
    'lp': ['200.000', '200.000', '1300.000', '130.000', '4.000', '3.000', '0.000', '0.000'],
    'int1': ['200', '200', '1200', '120.0', '0', '0.0', '0.0', '0.0'],
    'int2': ['200', '200', '1000.000', '100.0', '0', '0.0', '0.0', '0.0'],
    'int3': ['200', '200', '1000.000', '100.0', '0', '0.0', '0.0', '0.0'],
    'int4': ['200', '200', '1000.000', '100.0', '0', '0.0', '0.0', '0.0'],
    'fp': ['200', '200', '800', '70.0', '0', '0.0', '0.0', '0.0'],
  };
  for (final k in stowageLegKeys) {
    final p = 'stowage-$k';
    final d = legDef[k]!;
    s.register(FieldDef('$p-toggle', FK.chk, w));
    s.register(FieldDef('$p-current-fo', FK.num, w, def: '1300.000', disabled: k != 'lp'));
    s.register(FieldDef('$p-current-do', FK.num, w, def: '150.000', disabled: k != 'lp'));
    s.register(FieldDef('$p-ship-speed', FK.num, w, def: '13.000'));
    s.register(FieldDef('$p-distance-lp', FK.num, w, def: '3300.000'));
    s.register(FieldDef('$p-daily-fo', FK.num, w, def: '23.000'));
    s.register(FieldDef('$p-daily-do', FK.num, w, def: '3.000'));
    s.register(FieldDef('$p-loadline', FK.sel, w, def: 'Summer'), opts: const ['Summer', 'Tropical']);
    s.register(FieldDef('$p-density', FK.num, w, def: '1.022'));
    s.register(FieldDef('$k-draft-limit-toggle', FK.chk, w));
    s.register(FieldDef(draftLimitInput[k]!, FK.num, w));
    s.register(FieldDef('$p-bw', FK.num, w, def: d[0]));
    s.register(FieldDef('$p-fw', FK.num, w, def: d[1]));
    s.register(FieldDef('$p-sagging', FK.sel, w, def: '0'), opts: List.generate(12, (i) => '$i'));
    s.register(FieldDef('$p-port-fo', FK.num, w, def: d[2]));
    s.register(FieldDef('$p-port-do', FK.num, w, def: d[3]));
    s.register(FieldDef('$p-port-stay', FK.num, w, def: d[4]));
    s.register(FieldDef('$p-port-daily-fo', FK.num, w, def: d[5]));
    s.register(FieldDef('$p-port-daily-do', FK.num, w, def: d[5] == '3.000' ? '0.000' : d[6]));
    s.register(FieldDef('$p-fo-supply', FK.num, w, def: '0.000'));
    s.register(FieldDef('$p-do-supply', FK.num, w, def: '0.000'));
    s.register(FieldDef('$p-fw-supply', FK.num, w, def: d[7]));
    final np = nextPortSelect[k];
    if (np != null) {
      s.register(FieldDef(np, FK.sel, w, def: '1'), opts: k == 'int4' ? const ['1'] : const ['0', '1']);
    }
  }
  s.register(FieldDef('stowage-final-result', FK.num, w, disabled: true));
  s.register(FieldDef('stowage-final-result-details', FK.cell, w));

  // ---------------- arrival condition ----------------
  const a = 'arrivalCondition';
  s.register(FieldDef('condition-df', FK.num, a, def: '13.300'));
  s.register(FieldDef('condition-da', FK.num, a, def: '13.300'));
  s.register(FieldDef('condition-dm', FK.num, a, def: '13.300'));
  s.register(FieldDef('condition-density', FK.num, a, def: '1.022'));
  s.register(FieldDef('final-condition-df', FK.num, a, disabled: true));
  s.register(FieldDef('final-condition-da', FK.num, a, disabled: true));
  s.register(FieldDef('final-condition-dm', FK.num, a, disabled: true));
  s.register(FieldDef('final-condition-density', FK.num, a, def: '1.025'));
  final locOpts = ['', ...ship.capacityPlan.values.map(jsNum)];
  for (var i = 0; i < conditionTankMax; i++) {
    final key = conditionKey('tank', i);
    s.register(FieldDef('condition-load$key', FK.num, a));
    s.register(FieldDef('condition-load$key-location', FK.sel, a, def: ''), opts: locOpts);
    s.register(FieldDef('condition-load$key-long', FK.cell, a, def: '-'));
  }
  for (var i = 0; i < conditionUserMax; i++) {
    final key = conditionKey('user', i);
    s.register(FieldDef('condition-load$key', FK.num, a));
    s.register(FieldDef('condition-load$key-long', FK.num, a));
    s.register(FieldDef('condition-load$key-location', FK.text, a, def: 'User Defined Location', disabled: true));
  }

  // ---------------- miscellaneous ----------------
  const m = 'miscellaneous';
  s.register(FieldDef('misc-breadth', FK.num, m));
  s.register(FieldDef('observedSide', FK.sel, m, def: 'port'), opts: const ['port', 'starboard']);
  s.register(FieldDef('draft-read', FK.num, m, def: '13.300'));
  s.register(FieldDef('heelDir', FK.sel, m, def: 'port'), opts: const ['port', 'starboard']);
  s.register(FieldDef('heelAngle', FK.num, m, def: '0.1'));
  s.register(FieldDef('draft-opposited', FK.num, m, disabled: true));
  s.register(FieldDef('draft-difference', FK.num, m, disabled: true));
  s.register(FieldDef('interp-x0', FK.num, m, def: '0'));
  s.register(FieldDef('interp-y0', FK.num, m, def: '10'));
  s.register(FieldDef('interp-x1', FK.num, m, def: '1'));
  s.register(FieldDef('interp-y1', FK.num, m, def: '20'));
  s.register(FieldDef('interp-x', FK.num, m, def: '0.5'));
  s.register(FieldDef('interp-y', FK.num, m, disabled: true));
  s.register(FieldDef('dewpoint-dry', FK.num, m, def: '29.00'));
  s.register(FieldDef('dewpoint-wet', FK.num, m, def: '27.00'));
  s.register(FieldDef('dewpoint-pressure', FK.num, m, def: '1013.2'));
  s.register(FieldDef('dewpoint-value', FK.num, m, disabled: true));
}
