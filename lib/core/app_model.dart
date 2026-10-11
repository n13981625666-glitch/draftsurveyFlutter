import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'constants.dart';
import 'field_store.dart';
import 'registry.dart';
import 'ship.dart';
import 'util.dart';

enum ToastKind { info, success, warn, error }

class TankLock {
  final String soundingText;
  final String correctionText;
  final double? volume;
  final double weight;
  TankLock(this.soundingText, this.correctionText, this.volume, this.weight);

  Map<String, dynamic> toJson() => {
        'soundingText': soundingText,
        'correctionText': correctionText,
        'volume': volume,
        'weight': weight,
      };
}

class SurveyInputs {
  double fWp = 0, fWs = 0, mWp = 0, mWs = 0, aWp = 0, aWs = 0;
  double density = 0, fuel = 0, diesel = 0, fresh = 0, ballast = 0, others = 0, constant = 0;
  double lf = 0, lm = 0, la = 0, breadth = 0, keelPlate = 0, lbp = 0, lightShip = 0, blShore = 0;
  bool solveConstant = false;
  double cargo = 0;
  bool cargoBlank = true;
}

class SurveyResult {
  double heelDeg = 0;
  String heelDir = '';
  double corrF = 0, corrM = 0, corrA = 0, trim = 0, hogSag = 0, qMean = 0;
  double disp = double.nan, tpc = double.nan, c1 = 0, c2 = 0, trueDisp = 0, cargoWeight = 0, constant = 0;
  bool solveConstant = false;
  double difference = 0;
}

class TankRowResult {
  final int n;
  final String name;
  final String soundingText;
  final String correctionText;
  final bool empty;
  final double? volume;
  final double? weight;
  TankRowResult(this.n, this.name, this.soundingText, this.correctionText, this.empty, this.volume, this.weight);
}

/// Holds every field plus all calculation logic of the app (the old js/*.js files).
class AppModel extends ChangeNotifier {
  final ShipData ship;
  final FieldStore s = FieldStore();

  /// UI hooks
  void Function(String message, ToastKind kind, {int? ms})? toast;
  Future<void> Function(String json)? persist;
  Future<void> Function(List<dynamic> data)? pushShared;

  final Map<String, String> surveyLogs = {for (final id in surveySections) id: ''};
  String soundingLog = '';
  final Map<String, TankLock> tankLocks = {};
  int conditionTankRows = conditionTankBase;
  int conditionUserRows = conditionUserBase;
  final Map<String, bool> intShown = {for (final k in intKeys) k: false};
  String fpLastportTitle = 'Details For Preceeding From Loading Port To Discharging Port';
  String lastDraftSurveyTab = 'initial';
  Map<String, dynamic>? reportInfo;
  Timer? _saveTimer;
  bool _restoring = false;
  bool _sfBusy = false;

  AppModel(this.ship) {
    registerAll(s, ship);
    s.dynamicDisabled = _dynamicDisabled;
    s.onUserEdit = _onUserEdit;
    _populateFromShip();
  }

  void _toast(String m, ToastKind k, {int? ms}) => toast?.call(m, k, ms: ms);

  // ------------------------------------------------------------------ ship -> fields
  void _populateFromShip() {
    for (final sec in surveySections) {
      final p = '$sec-';
      s.set('${p}lightShip', jsNum(ship.lightShip));
      s.set('${p}breadth', jsNum(ship.breadth));
      s.set('${p}keelPlate', jsNum(ship.keelPlate));
      s.set('${p}lbp', jsNum(ship.lbp));
    }
    if (ship.breadth.isFinite && ship.breadth > 0) s.set('misc-breadth', jsNum(ship.breadth));
    s.set('stowage-light-ship', jsNum(ship.lightShip));
    s.set('stowage-capacity', jsNum(ship.capacity));
    s.set('stowage-summer-draft', jsNum(ship.summerDraft));
    s.set('stowage-tropical-draft', jsNum(ship.tropicalDraft));
    s.set('stowage-constant', jsNum(ship.constant));
    s.set('stowage-keel-plate', jsNum(ship.keelPlate));
  }

  // ------------------------------------------------------------------ dynamic disabled rules
  bool _dynamicDisabled(String id) {
    final m = RegExp(r'^(survey-\d)-(constant|cargoWeight)$').firstMatch(id);
    if (m != null) {
      final solve = s.checked('${m.group(1)}-solveConst');
      return m.group(2) == 'constant' ? solve : !solve;
    }
    for (final k in stowageLegKeys) {
      if (id == draftLimitInput[k]) return !s.checked('$k-draft-limit-toggle');
      if (id == 'stowage-$k-port-fo' || id == 'stowage-$k-port-do') return s.checked('stowage-$k-toggle');
    }
    return false;
  }

  // ------------------------------------------------------------------ user edits
  void _onUserEdit(String id) {
    if (_restoring) return;
    _recalcForField(id);
    scheduleSave();
    notifyListeners();
  }

  void _recalcForField(String id) {
    final sec = s.defs[id]?.section;
    if (sec == null) return;
    try {
      if (sec.startsWith('survey-')) {
        refreshSurvey(sec);
      } else if (sec == 'sounding') {
        if (id == 'sounding-df' || id == 'sounding-da' || id == 'sounding-density') {
          updateTrim();
        }
        calculateAndUpdateAllTanks();
      } else if (sec == 'trimming') {
        updateTrimming();
      } else if (sec == 'stowage') {
        _stowageEdited(id);
      } else if (sec == 'arrivalCondition') {
        calculateArrivalCondition();
      } else if (sec == 'miscellaneous') {
        if (id.startsWith('interp-')) {
          calculateInterpolation();
        } else if (id.startsWith('dewpoint-')) {
          calculateDewPoint();
        } else {
          calculateHeelDraft();
        }
      }
    } catch (e) {
      debugPrint('recalc failed for $id: $e');
    }
  }

  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    try {
      await persist?.call(jsonEncode(getSurveyExportData()));
    } catch (e) {
      debugPrint('Auto-save failed: $e');
    }
  }

  // ================================================================== DRAFT SURVEY
  SurveyInputs readSurveyInputs(String sec) {
    double n(String k) => toNum(s.get('$sec-$k'));
    final i = SurveyInputs();
    i.fWp = n('f_wp');
    i.fWs = n('f_ws');
    i.mWp = n('m_wp');
    i.mWs = n('m_ws');
    i.aWp = n('a_wp');
    i.aWs = n('a_ws');
    i.density = n('density');
    i.fuel = n('fuel');
    i.diesel = n('diesel');
    i.fresh = n('fresh');
    i.ballast = n('ballast');
    i.others = n('others');
    i.constant = n('constant');
    i.lf = n('selLF');
    i.lm = n('selLM');
    i.la = n('selLA');
    i.breadth = n('breadth');
    i.keelPlate = n('keelPlate');
    i.lbp = n('lbp');
    i.lightShip = n('lightShip');
    i.blShore = n('blShore');
    i.solveConstant = s.checked('$sec-solveConst');
    i.cargo = n('cargoWeight');
    i.cargoBlank = s.get('$sec-cargoWeight').trim().isEmpty;
    return i;
  }

  /// Pure draft survey calculation (calcDraftSurvey in the old survey.js).
  SurveyResult calcDraftSurvey(SurveyInputs i, [List<Row>? tableArg]) {
    final table = tableArg ?? ship.hydro;
    final r = SurveyResult();
    final sumF = (i.fWp + i.fWs) / 2;
    final sumM = (i.mWp + i.mWs) / 2;
    final sumA = (i.aWp + i.aWs) / 2;

    var heelDeg = 0.0;
    var heelDir = '';
    if (i.breadth > 0) {
      final diff = i.mWp - i.mWs;
      final clamped = math.max(-1.0, math.min(1.0, diff / i.breadth));
      heelDeg = (math.asin(clamped) * 180 / math.pi).abs();
      heelDir = diff > 0 ? 'to port' : 'to starboard';
    }

    var denom = i.lbp - i.lf - i.la;
    if (denom == 0 || denom.isNaN) denom = 1;
    final markTrim = sumA - sumF;
    final corrF = sumF - markTrim * (i.lf / denom) - i.keelPlate;
    final corrM = sumM - markTrim * (i.lm / denom) - i.keelPlate;
    final corrA = sumA + markTrim * (i.la / denom) - i.keelPlate;

    final trim = corrA - corrF;
    final hogSag = (corrF + corrA) / 2 - corrM;
    final qMean = (corrF + 6 * corrM + corrA) / 8;

    final disp = interpTable(table, 'DRAFT', 'DISP', qMean);
    final tpc = interpTable(table, 'DRAFT', 'TPC', qMean);
    final lcf = interpTable(table, 'DRAFT', 'LCF', qMean);

    final c1 = ((i.lbp / 2 - (lcf ?? 0)) * trim * (tpc ?? 0) * 100) / i.lbp;

    var floorDraft = table.isNotEmpty ? (table[0]['DRAFT'] ?? 0) : 0.0;
    for (var k = 0; k < table.length; k++) {
      final d = table[k]['DRAFT'] ?? double.nan;
      if (d <= qMean) {
        floorDraft = d;
      } else {
        break;
      }
    }
    final mtc1 = interpTable(table, 'DRAFT', 'MTC', floorDraft + 0.5);
    final mtc2 = interpTable(table, 'DRAFT', 'MTC', floorDraft - 0.5);
    final dMtcPerMetre = (mtc1 != null && mtc2 != null) ? (mtc1 - mtc2) : 0.0;
    final c2 = 50 * trim * trim * dMtcPerMetre / i.lbp;

    final density = (i.density == 0 || i.density.isNaN) ? seawaterDensity : i.density;
    final trueDisp = density * ((disp ?? 0) + c1 + c2) / seawaterDensity;
    final knownWeights = i.fuel + i.diesel + i.fresh + i.ballast + i.others;
    double cargoWeight, constant;
    if (i.solveConstant) {
      cargoWeight = i.cargo;
      constant = i.cargoBlank ? double.nan : trueDisp - knownWeights - i.lightShip - cargoWeight;
    } else {
      constant = i.constant;
      cargoWeight = trueDisp - knownWeights - constant - i.lightShip;
    }

    r.heelDeg = heelDeg;
    r.heelDir = heelDir;
    r.corrF = corrF;
    r.corrM = corrM;
    r.corrA = corrA;
    r.trim = trim;
    r.hogSag = hogSag;
    r.qMean = qMean;
    r.disp = disp ?? double.nan;
    r.tpc = tpc ?? double.nan;
    r.c1 = c1;
    r.c2 = c2;
    r.trueDisp = trueDisp;
    r.cargoWeight = cargoWeight;
    r.constant = constant;
    r.solveConstant = i.solveConstant;
    r.difference = i.blShore - cargoWeight;
    return r;
  }

  void renderSurveyResult(String sec, SurveyResult r) {
    final p = '$sec-';
    void setIf(String k, double v) => s.set('$p$k', toFixed(v, 3));
    void setStr(String k, String v) => s.set('$p$k', v);
    void setVal(String k, double v, int fixed) {
      if (v.isNaN) {
        s.set('$p$k', '-');
      } else {
        s.set('$p$k', toFixed(toNum(jsNum(v)), fixed));
      }
    }

    setStr('heel', r.heelDeg == 0 ? '${toFixed(r.heelDeg, 2)}°' : '${toFixed(r.heelDeg, 2)}° ${r.heelDir}');
    setIf('corrF', r.corrF);
    setIf('corrM', r.corrM);
    setIf('corrA', r.corrA);

    final trimVal = r.trim.abs();
    final trimDir = r.trim > 0 ? 'by the stern' : 'by head';
    setStr('trim', trimVal == 0 ? '${toFixed(trimVal, 3)} m Even Keel' : '${toFixed(trimVal, 3)} m $trimDir');
    setStr('hogSag', '${toFixed(r.hogSag.abs() * 100, 2)} cm ${r.hogSag > 0 ? 'HOG' : 'SAG'}');
    setIf('qMean', r.qMean);
    setVal('disp', r.disp, 2);
    setVal('tpc', r.tpc, 3);
    setIf('c1', r.c1);
    setIf('c2', r.c2);
    setIf('trueDisp', r.trueDisp);
    if (r.solveConstant) {
      setVal('constant', r.constant, 3);
    } else {
      setVal('cargoWeight', r.cargoWeight.abs() < 0.0005 ? 0 : r.cargoWeight, 3);
    }
    setStr('difference', r.difference.isFinite ? toFixed(r.difference, 3) : '');
  }

  bool _surveyReady(SurveyInputs i) => ship.hydro.isNotEmpty && i.lbp > 0;

  SurveyResult? refreshSurvey(String sec) {
    final inputs = readSurveyInputs(sec);
    if (!_surveyReady(inputs)) return null;
    final result = calcDraftSurvey(inputs);
    if (!result.trueDisp.isFinite) return null;
    renderSurveyResult(sec, result);
    return result;
  }

  void refreshAllSurveys() {
    for (final sec in surveySections) {
      refreshSurvey(sec);
    }
  }

  void setSolveMode(String sec, bool solveConst) {
    s.setChecked('$sec-solveConst', solveConst);
    refreshSurvey(sec);
    scheduleSave();
    notifyListeners();
  }

  String _timeNow() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(n.hour)}:${p(n.minute)}:${p(n.second)}';
  }

  void computeForSection(String sec) {
    final result = refreshSurvey(sec);
    if (result == null) {
      _toast('Cannot calculate: no ship data loaded, or the inputs are incomplete.', ToastKind.warn);
      notifyListeners();
      return;
    }
    final solved = result.solveConstant ? result.constant : result.cargoWeight;
    if (!solved.isFinite) {
      _toast('Enter the Cargo Weight first, then the Constant can be calculated.', ToastKind.warn);
      notifyListeners();
      return;
    }
    _toast('Calculation completed.', ToastKind.success);
    final what = result.solveConstant ? 'Constant' : 'Cargo Weight';
    surveyLogs[sec] = '[${_timeNow()}] Calculation Completed: $what = ${toFixed(solved, 3)} t\n${surveyLogs[sec]}';
    notifyListeners();
  }

  /// Easter egg: double-tap / long-press on Cargo Weight folds it into Ballast ("Calculate Cargo" mode only).
  void foldCargoIntoBallast(String sec) {
    if (s.checked('$sec-solveConst')) return;
    final r = refreshSurvey(sec);
    if (r == null || !r.cargoWeight.isFinite) return;
    final ballast = toNum(s.get('$sec-ballast')) + r.cargoWeight;
    if (ballast < 0) {
      _toast('Cannot adjust: Ballast would become negative.', ToastKind.warn);
      return;
    }
    s.set('$sec-ballast', toFixed((ballast * 1000).roundToDouble() / 1000, 3));
    refreshSurvey(sec);
    scheduleSave();
    _toast('Ballast adjusted by ${r.cargoWeight >= 0 ? '+' : ''}${toFixed(r.cargoWeight, 3)} t', ToastKind.success, ms: 2500);
    notifyListeners();
  }

  /// Easter egg: double-tap / long-press on the Sounding "Total Weight" row.
  void fillBallastFromSounding() {
    final total = double.tryParse(s.get('__tankTotal').trim());
    if (total == null || !total.isFinite) return;
    final sec = surveyIds[lastDraftSurveyTab] ?? surveyIds['initial']!;
    s.set('$sec-ballast', toFixed(total, 3));
    refreshSurvey(sec);
    scheduleSave();
    _toast('Ballast of ${surveyTitle(lastDraftSurveyTab)} set to ${toFixed(total, 3)} t', ToastKind.success, ms: 2500);
    notifyListeners();
  }

  static String surveyIdOf(String tab) => surveyIds[tab] ?? 'survey-0';

  static String surveyTitle(String tab) {
    switch (tab) {
      case 'int1':
        return 'Int1 Survey';
      case 'int2':
        return 'Int2 Survey';
      case 'final':
        return 'Final Survey';
      default:
        return 'Initial Survey';
    }
  }

  // ---------------------------------------------------------------- draft survey report data
  Map<String, dynamic> buildDraftSurveyReportData() {
    Map<String, dynamic> collect(String sec) {
      double get(String id) => toNum(s.get('$sec-$id'));
      final df = get('corrF'), da = get('corrA');
      final disp = get('disp');
      final bunkers = get('fuel') + get('diesel');
      final fw = get('fresh'), bw = get('ballast');
      return {
        'DF': df,
        'DA': da,
        'FAMean': (df + da) / 2,
        'DMP': get('m_wp'),
        'DMS': get('m_ws'),
        'DM': get('corrM'),
        'QM': get('qMean'),
        'density': s.get('$sec-density'),
        'disp': disp,
        'dispTrim': disp + get('c1') + get('c2'),
        'dispDensity': get('trueDisp'),
        'bunkers': bunkers,
        'fw': fw,
        'bw': bw,
        'knownWeight': bunkers + fw + bw,
        'lightShip': get('lightShip'),
        'constant': get('constant'),
        'cargo': get('cargoWeight'),
      };
    }

    return {
      'shipName': ship.name,
      'initial': collect('survey-0'),
      'final': collect('survey-3'),
    };
  }

  // ================================================================== SOUNDING
  double _bracketAt(List<double> xs, double x) => math.min(math.max(x, xs.first), xs.last);

  ({int lo, int hi, double wLo, double wHi, double at}) _bracket(List<double> xs, double x) {
    final at = _bracketAt(xs, x);
    final hi = xs.indexWhere((v) => v >= at);
    if (xs[hi] == at) return (lo: hi, hi: hi, wLo: 1, wHi: 0, at: at);
    final lo = hi - 1;
    final span = xs[hi] - xs[lo];
    return (lo: lo, hi: hi, wLo: (xs[hi] - at) / span, wHi: (at - xs[lo]) / span, at: at);
  }

  double _line(double a, double b, double x1, double x2, double x) => a + (b - a) * (x - x1) / (x2 - x1);

  /// Bilinear interpolation of a tank's volume table. null when the tank has no usable table.
  double? bilinearInterpolation(String tank, double sounding, double trim) {
    final data = ship.tankData[tank];
    if (data == null || !sounding.isFinite || !trim.isFinite) return null;
    if (data.trims.isEmpty || data.soundings.isEmpty) return null;
    final t = _bracket(data.trims, trim);
    final sb = _bracket(data.soundings, sounding);
    final v = data.volumes;
    final q11 = v[sb.lo][t.lo], q12 = v[sb.lo][t.hi], q21 = v[sb.hi][t.lo], q22 = v[sb.hi][t.hi];
    if (sb.lo == sb.hi && t.lo == t.hi) return q11;
    if (sb.lo == sb.hi) return _line(q11, q12, data.trims[t.lo], data.trims[t.hi], t.at);
    if (t.lo == t.hi) return _line(q11, q21, data.soundings[sb.lo], data.soundings[sb.hi], sb.at);
    final lower = t.wLo * q11 + t.wHi * q12;
    final upper = t.wLo * q21 + t.wHi * q22;
    return sb.wLo * lower + sb.wHi * upper;
  }

  double? parseOptionalNumber(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t.replaceAll(',', '.'));
    return (n != null && n.isFinite) ? n : null;
  }

  ({bool empty, double? volume, double? weight}) calcTankContent(
      String tankKey, String soundingText, String correctionText, double trim, double density) {
    final sounding = parseOptionalNumber(soundingText);
    if (sounding == null) return (empty: true, volume: null, weight: null);
    final volume = bilinearInterpolation(tankKey, sounding, trim);
    final tableVolume = (volume != null && volume.isNaN) ? null : volume;
    final finalVolume = parseOptionalNumber(correctionText) ?? tableVolume;
    if (finalVolume == null) return (empty: false, volume: volume, weight: null);
    final weight = finalVolume * density;
    return (empty: false, volume: volume, weight: weight.isNaN ? null : weight);
  }

  double get soundingDensity {
    final d = toNum(s.get('sounding-density'));
    return d == 0 ? seawaterDensity : d;
  }

  ({List<TankRowResult> rows, double total}) calcSounding() {
    final trim = toNum(s.get('sounding-trim'));
    final density = soundingDensity;
    final rows = <TankRowResult>[];
    for (final n in ship.tankNumbers) {
      final key = 'BWTANK$n';
      final name = ship.tankNames[n]!;
      final sText = s.get(tankKeyId(n, 'sounding'));
      final cText = s.get(tankKeyId(n, 'correction'));
      final lock = tankLocks[key];
      if (lock != null) {
        rows.add(TankRowResult(n, name, lock.soundingText, lock.correctionText, false, lock.volume, lock.weight));
      } else {
        final c = calcTankContent(key, sText, cText, trim, density);
        rows.add(TankRowResult(n, name, sText, cText, c.empty, c.volume, c.weight));
      }
    }
    final total = rows.fold<double>(0, (sum, r) => sum + (r.weight ?? 0));
    return (rows: rows, total: total);
  }

  ({List<TankRowResult> rows, double total}) calculateAndUpdateAllTanks() {
    final res = calcSounding();
    for (final r in res.rows) {
      s.set(tankKeyId(r.n, 'volume'), r.empty ? '-' : (r.volume == null ? 'N/A' : toFixed(r.volume!, 3)));
      s.set(tankKeyId(r.n, 'weight'), r.weight == null ? '-' : toFixed(r.weight!, 3));
    }
    s.set('__tankTotal', toFixed(res.total, 3));
    return res;
  }

  double updateTrim() {
    final trim = toNum(s.get('sounding-da')) - toNum(s.get('sounding-df'));
    s.set('sounding-trim', toFixed(trim, 3));
    return trim;
  }

  void recordSounding() {
    final res = calculateAndUpdateAllTanks();
    final drafts = 'DF ${toFixed(toNum(s.get('sounding-df')), 3)} / DA ${toFixed(toNum(s.get('sounding-da')), 3)}, density ${jsNum(soundingDensity)}';
    soundingLog = '[${_timeNow()}] Ballast Water Total = ${toFixed(res.total, 3)} t  ($drafts)\n$soundingLog';
    scheduleSave();
    _toast('Recorded.', ToastKind.success);
    notifyListeners();
  }

  void importSurveyDataToSounding(String type) {
    final sec = surveyIds[type];
    if (sec == null) return;
    s.set('sounding-df', toFixed(toNum(s.get('$sec-corrF')), 3));
    s.set('sounding-da', toFixed(toNum(s.get('$sec-corrA')), 3));
    s.set('sounding-density', toFixed(toNum(s.get('$sec-density')), 4));
    updateTrim();
    calculateAndUpdateAllTanks();
    scheduleSave();
    notifyListeners();
  }

  void applyTankLock(String key) {
    final lock = tankLocks[key];
    if (lock == null) return;
    final n = int.parse(key.replaceFirst('BWTANK', ''));
    s.set(tankKeyId(n, 'sounding'), lock.soundingText);
    s.set(tankKeyId(n, 'correction'), lock.correctionText);
  }

  bool isTankLocked(int n) => tankLocks.containsKey('BWTANK$n');

  void toggleTankLock(int n) {
    final key = 'BWTANK$n';
    if (tankLocks.containsKey(key)) {
      tankLocks.remove(key);
    } else {
      final row = calcSounding().rows.firstWhere((r) => r.n == n);
      if (row.empty) {
        _toast('Enter a sounding before locking this tank.', ToastKind.error);
        return;
      }
      if (row.weight == null) {
        _toast('This tank has no volume / weight to lock yet.', ToastKind.error);
        return;
      }
      tankLocks[key] = TankLock(row.soundingText, row.correctionText, row.volume, row.weight!);
    }
    applyTankLock(key);
    calculateAndUpdateAllTanks();
    scheduleSave();
    notifyListeners();
  }

  void unlockAllTanks() {
    if (tankLocks.isEmpty) return;
    tankLocks.clear();
    calculateAndUpdateAllTanks();
    scheduleSave();
    notifyListeners();
  }

  Map<String, dynamic> exportTankLocks() => {for (final e in tankLocks.entries) e.key: e.value.toJson()};

  void importTankLocks(Object? locks) {
    tankLocks.clear();
    final valid = ship.tankNumbers.map((n) => 'BWTANK$n').toSet();
    double? numOrNull(Object? v) => (v is num && v.isFinite) ? v.toDouble() : null;
    if (locks is Map) {
      locks.forEach((key, snap) {
        if (!valid.contains(key) || snap is! Map) return;
        final w = numOrNull(snap['weight']);
        if (w == null) return;
        tankLocks[key as String] = TankLock(
            '${snap['soundingText'] ?? ''}', '${snap['correctionText'] ?? ''}', numOrNull(snap['volume']), w);
      });
    }
    for (final key in tankLocks.keys) {
      applyTankLock(key);
    }
  }

  Map<String, dynamic> buildSoundingReportData() {
    final rows = calcSounding().rows;
    final printed = <Map<String, String>>[];
    for (final row in rows) {
      if (row.soundingText.trim().isEmpty) continue;
      final correction = parseOptionalNumber(row.correctionText);
      final volume = correction ?? row.volume;
      printed.add({
        'tank': row.name,
        'sounding': row.soundingText,
        'volume': (volume != null && volume.isFinite) ? toFixed(volume, 3) : '',
        'weight': row.weight == null ? '' : toFixed(row.weight!, 3),
      });
    }
    final total = printed.fold<double>(0, (sum, r) => sum + (r['weight']!.isEmpty ? 0 : double.parse(r['weight']!)));
    return {
      'title': 'Ballast Water Summary',
      'df': s.get('sounding-df'),
      'da': s.get('sounding-da'),
      'trim': s.get('sounding-trim'),
      'density': s.get('sounding-density'),
      'rows': printed,
      'total': toFixed(total, 3),
      'shipName': ship.name,
    };
  }

  // ================================================================== TRIMMING
  void updateTrimming() {
    double n(String id) => toNum(s.get(id));
    final cg = n('cgotoloaded');
    final df = n('trimming-df'), da = n('trimming-da'), dm = n('trimming-dm');
    final requiredTrim = n('trimming-requiredTrim');
    final firstHold = s.get('firstHold'), secondHold = s.get('secondHold');
    final firstHoldCal = s.get('firstHoldCal'), secondHoldCal = s.get('secondHoldCal'), thirdHoldCal = s.get('thirdHoldCal');
    final w1c = n('firstHoldCalDistributionWeight'), w2c = n('secondHoldCalDistributionWeight'), w3c = n('thirdHoldCalDistributionWeight');

    void setNum(String id, double v) => s.set(id, jsNum(v));

    final trim = round(da - df, 3);
    s.set('trimming-trim', jsNum(trim));
    s.set('trimming-requiredTrimConditon',
        requiredTrim > 0 ? 'By Stern' : (requiredTrim < 0 ? 'By Head' : 'Even Keel'));
    final trimChanging = round(requiredTrim - trim, 3);
    s.set('trimChanging', jsNum(trimChanging));

    final tpc = interpTable(ship.hydro, 'DRAFT', 'TPC', dm);
    double hf(String hold, String fa) => interpOrZero(ship.trimtable, 'DRAFT', '$hold|$fa', dm);
    final firstHoldF = hf(firstHold, 'F'), firstHoldA = hf(firstHold, 'A');
    final secondHoldF = hf(secondHold, 'F'), secondHoldA = hf(secondHold, 'A');
    final calFirstHoldF = hf(firstHoldCal, 'F'), calFirstHoldA = hf(firstHoldCal, 'A');
    final calSecondHoldF = hf(secondHoldCal, 'F'), calSecondHoldA = hf(secondHoldCal, 'A');
    final calThirdHoldF = hf(thirdHoldCal, 'F'), calThirdHoldA = hf(thirdHoldCal, 'A');

    s.set('firstHoldF', toFixed(firstHoldF, 2));
    s.set('firstHoldA', toFixed(firstHoldA, 2));
    s.set('secondHoldF', toFixed(secondHoldF, 2));
    s.set('secondHoldA', toFixed(secondHoldA, 2));
    s.set('calFirstHoldF', toFixed(calFirstHoldF, 2));
    s.set('calFirstHoldA', toFixed(calFirstHoldA, 2));
    s.set('calSencondHoldF', toFixed(calSecondHoldF, 2));
    s.set('calSencondHoldA', toFixed(calSecondHoldA, 2));
    s.set('calThirdHoldF', toFixed(calThirdHoldF, 2));
    s.set('calThirdHoldA', toFixed(calThirdHoldA, 2));

    s.set('firstHoldDistribution', firstHold);
    s.set('secondHoldDistribution', secondHold);
    s.set('firstHoldCalDistribution', firstHoldCal);
    s.set('secondHoldCalDistribution', secondHoldCal);
    s.set('thirdHoldCalDistribution', thirdHoldCal);

    final coef1 = (firstHoldA - firstHoldF) / 10000;
    final coef2 = (secondHoldA - secondHoldF) / 10000;
    var w1 = (trimChanging - coef2 * cg) / (coef1 - coef2);
    var w2 = cg - w1;
    w1 = round(w1, 3);
    w2 = round(w2, 3);
    setNum('firstHoldDistributionWeight', w1);
    setNum('secondHoldDistributionWeight', w2);

    final mtc = interpTable(ship.hydro, 'DRAFT', 'MTC', dm) ?? double.nan;
    final lcf = interpTable(ship.hydro, 'DRAFT', 'LCF', dm) ?? double.nan;
    final lcg1 = ship.holdsLcg[firstHold] ?? double.nan;
    final lcg2 = ship.holdsLcg[secondHold] ?? double.nan;
    final heel1 = (100 * mtc * (trim - requiredTrim) - cg * (lcg2 - lcf)) / (lcg1 - lcg2);
    s.set('firstHoldDistributionWeightHeelMethod', toFixed(heel1, 3));
    final heel2 = cg - heel1;
    s.set('secondHoldDistributionWeightHeelMethod', toFixed(heel2, 3));
    s.set('distribution-total-weight-cell-heel', toFixed(heel1 + heel2, 3));
    s.set('distribution-total-weight-cell', toFixed(w1 + w2, 3));

    final tp = tpc ?? 0;
    final finalDf = round(df + (w1 * firstHoldF + w2 * secondHoldF) / 10000, 3);
    s.set('distribution-final-df', jsNum(finalDf));
    final finalDm = round(dm + ((w1 + w2) / tp) / 100, 3);
    s.set('distribution-final-dm', jsNum(finalDm));
    final finalDa = round(da + (w1 * firstHoldA + w2 * secondHoldA) / 10000, 3);
    s.set('distribution-final-da', jsNum(finalDa));
    s.set('distribution-final-trim', jsNum(round(finalDa - finalDf, 3)));

    s.set('cal-total-weight-cell', toFixed(w1c + w2c + w3c, 3));
    final fcDf = round(df + (w1c * calFirstHoldF + w2c * calSecondHoldF + w3c * calThirdHoldF) / 10000, 3);
    final fcDa = round(da + (w1c * calFirstHoldA + w2c * calSecondHoldA + w3c * calThirdHoldA) / 10000, 3);
    final fcDm = round(dm + ((w1c + w2c + w3c) / tp) / 100, 3);
    s.set('final-cal-df', jsNum(fcDf));
    s.set('final-cal-dm', jsNum(fcDm));
    s.set('final-cal-da', jsNum(fcDa));
    s.set('final-cal-trim', jsNum(round(fcDa - fcDf, 3)));
  }

  void importSurveyDataToTrimming(String type) {
    final sec = surveyIds[type];
    if (sec == null) return;
    s.set('trimming-df', toFixed(toNum(s.get('$sec-corrF')), 3));
    s.set('trimming-da', toFixed(toNum(s.get('$sec-corrA')), 3));
    s.set('trimming-dm', toFixed(toNum(s.get('$sec-corrM')), 3));
    updateTrimming();
    scheduleSave();
    notifyListeners();
  }

  // ================================================================== PRE-STOWAGE
  void syncIntPortCards() {
    var prevKey = 'lp';
    var shown = true;
    for (final key in intKeys) {
      shown = shown && s.get(nextPortSelect[prevKey]!) == '0';
      intShown[key] = shown;
      if (shown) prevKey = key;
    }
    final from = prevKey == 'lp' ? 'Loading Port' : '${prevKey[0].toUpperCase()}${prevKey.substring(1)}';
    fpLastportTitle = 'Details For Preceeding From $from To Discharging Port';
  }

  bool isLegVisible(String key) => key == 'lp' || key == 'fp' || (intShown[key] ?? false);

  void onNextPortChanged(String selectId) {
    final chain = ['lp', ...intKeys];
    final i = chain.indexWhere((k) => nextPortSelect[k] == selectId);
    if (i < 0) return;
    for (final k in chain.sublist(i + 1)) {
      final opts = s.options[nextPortSelect[k]] ?? const ['1'];
      s.set(nextPortSelect[k]!, opts.last);
    }
    syncIntPortCards();
  }

  void _stowageEdited(String id) {
    // cargo stowage factor converter
    if (!_sfBusy && (id == 'stowage-sf-cuft-mt' || id == 'stowage-sf-cum-t' || id == 'stowage-sf-cuft-lt')) {
      _sfBusy = true;
      final v = toNum(s.get(id));
      if (id == 'stowage-sf-cuft-mt') {
        s.set('stowage-sf-cum-t', toFixed(v * cuftToM3, 3));
        s.set('stowage-sf-cuft-lt', toFixed(v * 1.0160465812, 3));
      } else if (id == 'stowage-sf-cum-t') {
        s.set('stowage-sf-cuft-mt', toFixed(v * 35.3144754, 3));
        s.set('stowage-sf-cuft-lt', toFixed(v * 35.881152, 3));
      } else {
        s.set('stowage-sf-cuft-mt', toFixed(v * 0.984206845, 3));
        s.set('stowage-sf-cum-t', toFixed(v * 0.027869785, 3));
      }
      _sfBusy = false;
    }
    if (nextPortSelect.containsValue(id)) onNextPortChanged(id);
    for (final k in stowageLegKeys) {
      if (id == 'stowage-$k-toggle') {
        // toggleContent: nothing to write, enabled/disabled is derived from the checkbox
      }
      if (id == '$k-draft-limit-toggle') {
        final on = s.checked(id);
        s.set(draftLimitInput[k]!, on ? '12.5' : '');
      }
    }
    calcPreStowageMinCargo();
  }

  String? _previousLegKey(String legKey) {
    final order = ['lp', ...intKeys];
    if (legKey == 'lp') return null;
    if (legKey == 'fp') {
      for (var i = order.length - 1; i > 0; i--) {
        if (intShown[order[i]] ?? false) return order[i];
      }
      return 'lp';
    }
    return order[order.indexOf(legKey) - 1];
  }

  void updateLegBunkers(String legKey) {
    if (!s.checked('stowage-$legKey-toggle')) return;
    final p = 'stowage-$legKey';
    double n(String id) => toNum(s.get(id));
    final prev = _previousLegKey(legKey);
    if (prev != null) {
      final q = 'stowage-$prev';
      s.set('$p-current-fo',
          toFixed(n('$q-port-fo') - n('$q-port-stay') * n('$q-port-daily-fo') + n('$q-fo-supply'), 3));
      s.set('$p-current-do',
          toFixed(n('$q-port-do') - n('$q-port-stay') * n('$q-port-daily-do') + n('$q-do-supply'), 3));
    }
    final speed = n('$p-ship-speed');
    final hours = (n('$p-distance-lp') / (speed == 0 ? 1 : speed)) / 24;
    s.set('$p-port-fo', toFixed(n('$p-current-fo') - hours * n('$p-daily-fo'), 3));
    s.set('$p-port-do', toFixed(n('$p-current-do') - hours * n('$p-daily-do'), 3));
  }

  double _stowageCargo(double displacement, double tpc, Map<String, double> leg, double constant, double lightShip) {
    return displacement -
        leg['bw']! -
        leg['fw']! -
        leg['sagging']! * tpc * saggingCoeff -
        leg['portFo']! -
        leg['portDo']! +
        leg['portStay']! * (leg['portDailyFo']! + leg['portDailyDo']!) -
        leg['foSupply']! -
        leg['doSupply']! -
        leg['fwSupply']! -
        constant -
        lightShip;
  }

  void calcPreStowageMinCargo() {
    double n(String id) => toNum(s.get(id));
    final keelPlate = n('stowage-keel-plate');
    final summerDraft = n('stowage-summer-draft') - keelPlate;
    final tropicalDraft = n('stowage-tropical-draft') - keelPlate;
    final constant = n('stowage-constant');
    final lightShip = n('stowage-light-ship');
    double disp(double d) => interpTable(ship.hydro, 'DRAFT', 'DISP', d) ?? 0;
    double tpc(double d) => interpTable(ship.hydro, 'DRAFT', 'TPC', d) ?? 0;

    final candidates = <MapEntry<String, double>>[
      MapEntry('Capacity Cargo', n('stowage-capacity') / (_orOne(n('stowage-sf-cuft-mt')) * cuftToM3)),
    ];
    const labels = {
      'lp': 'Loading Port',
      'int1': 'Int1',
      'int2': 'Int2',
      'int3': 'Int3',
      'int4': 'Int4',
      'fp': 'Discharging Port',
    };
    for (final key in stowageLegKeys) {
      if (!isLegVisible(key)) continue;
      updateLegBunkers(key);
      final p = 'stowage-$key';
      final dens = n('$p-density');
      final leg = <String, double>{
        'bw': n('$p-bw'),
        'fw': n('$p-fw'),
        'sagging': n('$p-sagging'),
        'portFo': n('$p-port-fo'),
        'portDo': n('$p-port-do'),
        'portStay': n('$p-port-stay'),
        'portDailyFo': n('$p-port-daily-fo'),
        'portDailyDo': n('$p-port-daily-do'),
        'foSupply': n('$p-fo-supply'),
        'doSupply': n('$p-do-supply'),
        'fwSupply': n('$p-fw-supply'),
        'density': dens == 0 ? seawaterDensity : dens,
      };
      final loadLineDraft = s.get('$p-loadline') == 'Summer' ? summerDraft : tropicalDraft;
      candidates.add(MapEntry('${labels[key]} Load Line Cargo',
          _stowageCargo(disp(loadLineDraft), tpc(loadLineDraft), leg, constant, lightShip)));
      if (s.checked('$key-draft-limit-toggle')) {
        final limitDraft = n(draftLimitInput[key]!) - keelPlate;
        candidates.add(MapEntry('${labels[key]} Draft Limit Cargo',
            _stowageCargo(disp(limitDraft) * leg['density']! / seawaterDensity, tpc(limitDraft), leg, constant, lightShip)));
      }
    }
    final valid = candidates.where((e) => !e.value.isNaN).toList();
    final minCargo = jsMin(valid.map((e) => e.value));
    s.set('stowage-final-result', toFixed(minCargo, 3));
    s.set('stowage-final-result-details', valid.map((e) => '${e.key}: ${toFixed(e.value, 3)}').join('\n'));
  }

  double _orOne(double v) => (v == 0 || v.isNaN) ? 1 : v;

  // ================================================================== ARRIVAL CONDITION
  List<String> conditionKeys() => [
        for (var i = 0; i < conditionTankRows; i++) conditionKey('tank', i),
        for (var i = 0; i < conditionUserRows; i++) conditionKey('user', i),
      ];

  bool addConditionLoad(String kind) {
    final n = kind == 'tank' ? conditionTankRows : conditionUserRows;
    final max = kind == 'tank' ? conditionTankMax : conditionUserMax;
    if (n >= max) return false;
    final key = conditionKey(kind, n);
    s.set('condition-load$key', '');
    if (kind == 'tank') {
      s.set('condition-load$key-location', '');
      s.set('condition-load$key-long', '-');
      conditionTankRows++;
    } else {
      s.set('condition-load$key-long', '');
      conditionUserRows++;
    }
    return true;
  }

  bool removeConditionLoad(String kind) {
    if (kind == 'tank') {
      if (conditionTankRows <= conditionTankBase) return false;
      conditionTankRows--;
    } else {
      if (conditionUserRows <= conditionUserBase) return false;
      conditionUserRows--;
    }
    return true;
  }

  void setConditionLoadCount(String kind, int count) {
    final base = kind == 'tank' ? conditionTankBase : conditionUserBase;
    final max = kind == 'tank' ? conditionTankMax : conditionUserMax;
    final want = math.min(max, math.max(base, count));
    while ((kind == 'tank' ? conditionTankRows : conditionUserRows) < want) {
      if (!addConditionLoad(kind)) break;
    }
    while ((kind == 'tank' ? conditionTankRows : conditionUserRows) > want) {
      if (!removeConditionLoad(kind)) break;
    }
  }

  void arrivalRowsChanged(String kind, bool add) {
    final changed = add ? addConditionLoad(kind) : removeConditionLoad(kind);
    if (changed) {
      calculateArrivalCondition();
      scheduleSave();
      notifyListeners();
    }
  }

  Map<String, dynamic> prepareArrivalImport(Object? fields) {
    if (fields is! Map) return {};
    final f = Map<String, dynamic>.from(fields);
    if (f.containsKey('condition-load4-long')) {
      if (f.containsKey('condition-load4')) f['condition-loadA'] = f['condition-load4'];
      f['condition-loadA-long'] = f['condition-load4-long'];
      f.remove('condition-load4');
      f.remove('condition-load4-long');
    }
    var tank = 0, user = 0;
    for (final id in f.keys) {
      var m = RegExp(r'^condition-load(\d+)(?:-location)?$').firstMatch(id);
      if (m != null) tank = math.max(tank, int.parse(m.group(1)!));
      m = RegExp(r'^condition-load([A-Z])(?:-long)?$').firstMatch(id);
      if (m != null) user = math.max(user, m.group(1)!.codeUnitAt(0) - 64);
    }
    setConditionLoadCount('tank', tank);
    setConditionLoadCount('user', user);
    return f;
  }

  Map<String, double> calculateArrivalCondition() {
    final dm = toNum(s.get('condition-dm'));
    final tpc = interpTable(ship.hydro, 'DRAFT', 'TPC', dm) ?? double.nan;
    final lcf = interpTable(ship.hydro, 'DRAFT', 'LCF', dm) ?? double.nan;
    final lcb = interpTable(ship.hydro, 'DRAFT', 'LCB', dm) ?? double.nan;
    final mtc = interpTable(ship.hydro, 'DRAFT', 'MTC', dm) ?? double.nan;
    final dispT = interpTable(ship.hydro, 'DRAFT', 'DISP', dm) ?? double.nan;
    final lbp = ship.lbp;

    final loads = <double>[];
    final longs = <double?>[];
    for (var i = 0; i < conditionTankRows; i++) {
      final key = conditionKey('tank', i);
      final weight = toNum(s.get('condition-load$key'));
      var long = double.tryParse(s.get('condition-load$key-location')) ?? double.nan;
      s.set('condition-load$key-long', !long.isNaN ? jsNum(long) : '-');
      double? l = long;
      if (long.isNaN || weight == 0) l = null;
      loads.add(weight);
      longs.add(l);
    }
    for (var i = 0; i < conditionUserRows; i++) {
      final key = conditionKey('user', i);
      final weight = toNum(s.get('condition-load$key'));
      final long = double.tryParse(s.get('condition-load$key-long').trim()) ?? double.nan;
      loads.add(weight);
      longs.add((long.isNaN || weight == 0) ? null : long);
    }

    final df = toNum(s.get('condition-df'));
    final da = toNum(s.get('condition-da'));
    final d0 = toNum(s.get('condition-density'));
    final density = d0 == 0 ? defaultArrivalDensity : d0;
    final fd0 = toNum(s.get('final-condition-density'));
    final finalDensity = fd0 == 0 ? seawaterDensity : fd0;

    var loadParallelDelta = 0.0;
    for (var i = 0; i < loads.length; i++) {
      if (longs[i] != null && !longs[i]!.isNaN) loadParallelDelta += loads[i];
    }
    loadParallelDelta = loadParallelDelta / (100 * tpc);

    var loadTrimDelta = 0.0;
    for (var i = 0; i < loads.length; i++) {
      final long = longs[i];
      var v = 0.0;
      if (long != null && !long.isNaN) v = lcf - long;
      loadTrimDelta += loads[i] * v;
    }
    loadTrimDelta = loadTrimDelta / (100 * mtc);

    final loadDraftDeltaF = loadParallelDelta - loadTrimDelta * (lbp - lcf) / lbp;
    final loadDraftDeltaA = loadParallelDelta + loadTrimDelta * lcf / lbp;

    final densityParallel = (dispT * (seawaterDensity / finalDensity - seawaterDensity / density)) / (100 * tpc);
    final densityTrim = (tpc *
        (lcf - lcb) *
        (dispT * (seawaterDensity / finalDensity - seawaterDensity / density) / (100 * tpc)) /
        mtc);
    final densityDraftDeltaF = densityParallel - densityTrim * (lbp - lcf) / lbp;
    final densityDraftDeltaA = densityParallel + densityTrim * lcf / lbp;

    final finalDf = df + loadDraftDeltaF + densityDraftDeltaF;
    final finalDa = da + loadDraftDeltaA + densityDraftDeltaA;
    final finalDm = dm + loadParallelDelta + densityParallel;
    s.set('final-condition-df', toFixed(finalDf, 3));
    s.set('final-condition-da', toFixed(finalDa, 3));
    s.set('final-condition-dm', toFixed(finalDm, 3));
    return {'final_condition_df': finalDf, 'final_condition_da': finalDa, 'final_condition_dm': finalDm};
  }

  // ================================================================== MISC
  void calculateHeelDraft() {
    final breadth = toNum(s.get('misc-breadth'));
    final observedSide = s.get('observedSide');
    final observedDraft = toNum(s.get('draft-read'));
    final heelDir = s.get('heelDir');
    final angle = toNum(s.get('heelAngle'));
    final diff = breadth * math.sin(angle * math.pi / 180);
    final opposite = observedSide == heelDir ? (observedDraft - diff) : (observedDraft + diff);
    s.set('draft-opposited', toFixed(opposite, 3));
    s.set('draft-difference', toFixed(diff, 3));
  }

  void calculateInterpolation() {
    double n(String id) => toNum(s.get(id));
    final y = lerp(n('interp-x0'), n('interp-y0'), n('interp-x1'), n('interp-y1'), n('interp-x'));
    s.set('interp-y', toFixed(y, 3));
  }

  void calculateDewPoint() {
    final tDry = toNum(s.get('dewpoint-dry'));
    final tWet = toNum(s.get('dewpoint-wet'));
    final pr = toNum(s.get('dewpoint-pressure'));
    final ews = 6.112 * math.exp((17.62 * tWet) / (243.12 + tWet));
    const a = 0.00066;
    final e = ews - a * pr * (tDry - tWet);
    final lnRatio = math.log(e / 6.112);
    final tDew = (243.12 * lnRatio) / (17.62 - lnRatio);
    s.set('dewpoint-value', toFixed(tDew, 2));
  }

  // ================================================================== recalc / data I/O
  void recalcAllPages() {
    final steps = <void Function()>[
      () => updateTrim(),
      () => calculateAndUpdateAllTanks(),
      updateTrimming,
      refreshAllSurveys,
      syncIntPortCards,
      calcPreStowageMinCargo,
      () => calculateArrivalCondition(),
      calculateHeelDraft,
      calculateInterpolation,
      calculateDewPoint,
    ];
    for (final f in steps) {
      try {
        f();
      } catch (e) {
        debugPrint('recalc step failed: $e');
      }
    }
  }

  List<FieldDef> _sectionDefs(String section) {
    final out = <FieldDef>[];
    final liveCond = section == 'arrivalCondition' ? conditionKeys().toSet() : null;
    for (final d in s.defs.values) {
      if (d.section != section) continue;
      if (liveCond != null) {
        final m = RegExp(r'^condition-load(\d+|[A-Z])').firstMatch(d.id);
        if (m != null && !liveCond.contains(m.group(1))) continue;
      }
      out.add(d);
    }
    return out;
  }

  Map<String, dynamic> collectFields(String section) {
    final fields = <String, dynamic>{};
    for (final d in _sectionDefs(section)) {
      if (d.kind == FK.cell || s.isDisabled(d.id)) continue;
      fields[d.id] = d.kind == FK.chk ? s.checked(d.id) : s.get(d.id);
    }
    return fields;
  }

  void applyFields(String section, Object? fieldsObj, void Function()? afterCheckboxes) {
    if (fieldsObj is! Map) return;
    final fields = fieldsObj;
    bool inSection(String id) => s.defs[id]?.section == section;
    for (final e in fields.entries) {
      final id = '${e.key}';
      if (inSection(id) && s.defs[id]!.kind == FK.chk && e.value is bool) {
        s.setChecked(id, e.value as bool);
      }
    }
    afterCheckboxes?.call();
    for (final e in fields.entries) {
      final id = '${e.key}';
      if (!inSection(id)) continue;
      final d = s.defs[id]!;
      if (s.isDisabled(id) || d.kind == FK.chk || d.kind == FK.cell) continue;
      final value = e.value;
      if (d.kind == FK.sel) {
        var v = value == null ? '' : '$value';
        if (holdSelects.any((h) => h[0] == id) && RegExp(r'^\d+$').hasMatch(v)) v = 'H$v';
        if ((s.options[id] ?? const []).contains(v)) s.set(id, v);
      } else {
        s.set(id, value == null ? '' : (value is num ? jsNum(value.toDouble()) : '$value'));
      }
    }
  }

  List<dynamic> getSurveyExportData() {
    final result = <dynamic>[];
    for (var idx = 0; idx < 4; idx++) {
      final sec = 'survey-$idx';
      final p = '$sec-';
      result.add({
        'survey': idx,
        'draftInputs': {for (final k in surveyInputKeys) k: s.get('$p$k')},
        'shipProps': {for (final k in ['selLF', 'selLM', 'selLA']) k: s.get('$p$k')},
        'blShore': s.get('${p}blShore'),
        'fields': collectFields(sec),
      });
    }
    for (final page in dataPages) {
      final entry = <String, dynamic>{'survey': page[0], 'data': collectFields(page[1])};
      if (page[0] == 'sounding') {
        entry['locks'] = exportTankLocks();
        entry['log'] = soundingLog;
      }
      result.add(entry);
    }
    if (reportInfo != null && reportInfo!.isNotEmpty) {
      result.add({'survey': 'reportInfo', 'data': reportInfo});
    }
    return result;
  }

  void syncStowageToggles() {
    // enabled / disabled and visibility are derived from the checkboxes, nothing to write
  }

  void setSurveyImportData(Object? data, {bool recalc = true}) {
    if (data is! List) return;
    _restoring = true;
    try {
      for (final item in data) {
        if (item is! Map) continue;
        final sv = item['survey'];
        if (sv is int) {
          if (sv < 0 || sv > 3) continue;
          final sec = 'survey-$sv';
          final p = '$sec-';
          if (item['fields'] != null) {
            applyFields(sec, item['fields'], null);
          } else {
            final di = item['draftInputs'];
            if (di is Map) {
              di.forEach((k, v) {
                if (surveyInputKeys.contains(k)) s.set('$p$k', '$v');
              });
            }
            final sp = item['shipProps'];
            if (sp is Map) {
              final f = <String, dynamic>{};
              sp.forEach((k, v) {
                if (RegExp(r'^sel').hasMatch('$k')) f['$p$k'] = v;
              });
              applyFields(sec, f, null);
            }
            if (item['blShore'] != null) s.set('${p}blShore', '${item['blShore']}');
          }
          continue;
        }
        if (sv == 'reportInfo') {
          final d = item['data'];
          reportInfo = d is Map ? Map<String, dynamic>.from(d) : {};
          continue;
        }
        final page = dataPages.where((p) => p[0] == sv).toList();
        if (page.isEmpty) continue;
        final sec = page[0][1];
        var fields = item['data'];
        if (sv == 'arrivalCondition') fields = prepareArrivalImport(fields);
        applyFields(sec, fields, null);
        if (sv == 'sounding') {
          if (item['log'] is String) soundingLog = item['log'] as String;
          importTankLocks(item['locks']);
        }
      }
    } finally {
      _restoring = false;
    }
    if (recalc) recalcAllPages();
    notifyListeners();
  }

  /// Restore the automatic save of the last session (called once after start-up).
  void restoreSaved(String? json) {
    if (json == null || json.isEmpty) return;
    try {
      setSurveyImportData(jsonDecode(json));
    } catch (e) {
      debugPrint('Error loading survey data: $e');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    s.dispose();
    super.dispose();
  }
}
