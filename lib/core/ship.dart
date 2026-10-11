import 'util.dart';

class TankTable {
  final List<double> trims;
  final List<double> soundings;
  final List<List<double>> volumes;
  TankTable(this.trims, this.soundings, this.volumes);
}

/// Everything the calculations need about the loaded ship (the old globals ship / hydro / trimtable ...).
class ShipData {
  String id = '';
  String name = '(no ship loaded)';
  double lightShip = 0, breadth = 0, keelPlate = 0, lbp = 0;
  List<double> lf = [0], lm = [0], la = [0];
  double capacity = 0, summerDraft = 0, tropicalDraft = 0, constant = 0;
  List<Row> hydro = [];
  List<String> holdIds = [];
  Map<String, double> holdsLcg = {};
  List<Row> trimtable = [];
  /// load point name -> LCG (insertion ordered)
  Map<String, double> capacityPlan = {};
  /// tank number (1-based) -> name
  Map<int, String> tankNames = {};
  /// 'BWTANK<n>' -> table
  Map<String, TankTable> tankData = {};
  List<String> messages = [];

  int get tankCount => tankNames.length;
  List<int> get tankNumbers => (tankNames.keys.toList()..sort());
}

bool _isNum(Object? v) => v is num && v.isFinite;
bool _isNumArr(Object? a, [int min = 1]) => a is List && a.length >= min && a.every(_isNum);
bool _ascending(List<num> a) {
  for (var i = 1; i < a.length; i++) {
    if (!(a[i] > a[i - 1])) return false;
  }
  return true;
}

List<double> _dl(Object? a) => (a as List).map((e) => (e as num).toDouble()).toList();

String holdIdOf(Object? h) {
  if (h is Map) {
    final id = h['id'];
    if (id is String && id.trim().isNotEmpty) return id.trim();
    final no = h['no'];
    if (no is int && no >= 1) return 'H$no';
  }
  return '';
}

class ShipProfileError implements Exception {
  final String message;
  ShipProfileError(this.message);
  @override
  String toString() => 'Invalid ship profile: $message';
}

/// Same checks as validateShipProfile() in the old shell.js.
void validateShipProfile(Object? p) {
  Never fail(String m) => throw ShipProfileError(m);
  if (p is! Map) fail('not an object');
  if (p['schemaVersion'] != 1) fail('unsupported schemaVersion (expected 1)');

  final s = p['ship'];
  if (s is! Map || s['name'] is! String || (s['name'] as String).trim().isEmpty) fail('ship.name missing');
  for (final k in ['lightShip', 'breadth', 'keelPlate', 'lbp', 'capacity', 'summerDraft', 'tropicalDraft', 'constant']) {
    if (!_isNum(s[k])) fail('ship.$k must be a number');
  }
  final marks = s['marks'];
  if (marks is! Map) fail('ship.marks missing');
  for (final k in ['lf', 'lm', 'la']) {
    if (!_isNumArr(marks[k])) fail('ship.marks.$k must be a non-empty number array');
  }

  final hs = p['hydrostatic'];
  final rows = hs is Map ? hs['rows'] : null;
  if (rows is! List || rows.length < 2) fail('hydrostatic.rows needs at least 2 rows');
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    for (final k in ['DRAFT', 'DISP', 'TPC', 'MTC', 'LCB', 'LCF']) {
      if (r is! Map || !_isNum(r[k])) fail('hydrostatic.rows[$i].$k must be a number');
    }
  }
  if (!_ascending(rows.map<num>((r) => r['DRAFT'] as num).toList())) {
    fail('hydrostatic.rows must be sorted by ascending DRAFT');
  }

  final drafts = p['trimCorrectionDrafts'];
  if (!_isNumArr(drafts, 2) || !_ascending((drafts as List).cast<num>())) {
    fail('trimCorrectionDrafts must be ascending numbers (min 2)');
  }

  final holds = p['holds'];
  if (holds is! List || holds.isEmpty) fail('holds must have at least 1 entry');
  final seen = <String>{};
  for (var i = 0; i < holds.length; i++) {
    final h = holds[i];
    final id = holdIdOf(h);
    if (id.isEmpty) fail('holds[$i] needs an "id" such as "H1", "F20" or "F-5"');
    if (seen.contains(id)) fail('holds[$i].id "$id" is used twice');
    seen.add(id);
    if (!_isNum((h as Map)['lcg'])) fail('holds[$i].lcg must be a number');
    final tc = h['trimCorrection'];
    if (tc is! Map ||
        !_isNumArr(tc['f']) ||
        !_isNumArr(tc['a']) ||
        (tc['f'] as List).length != drafts.length ||
        (tc['a'] as List).length != drafts.length) {
      fail('holds[$i].trimCorrection.f/a must match trimCorrectionDrafts length');
    }
  }

  final tanks = p['tanks'];
  if (tanks is! List) fail('tanks must be an array');
  for (var i = 0; i < tanks.length; i++) {
    final t = tanks[i];
    if (t is! Map || t['name'] is! String || (t['name'] as String).isEmpty) fail('tanks[$i].name missing');
    if (!_isNumArr(t['trims']) || !_ascending((t['trims'] as List).cast<num>())) {
      fail('tanks[$i].trims must be ascending numbers');
    }
    if (!_isNumArr(t['soundings']) || !_ascending((t['soundings'] as List).cast<num>())) {
      fail('tanks[$i].soundings must be ascending numbers');
    }
    final vols = t['volumes'];
    if (vols is! List || vols.length != (t['soundings'] as List).length) {
      fail('tanks[$i].volumes rows must equal soundings count');
    }
    for (var j = 0; j < vols.length; j++) {
      if (!_isNumArr(vols[j]) || (vols[j] as List).length != (t['trims'] as List).length) {
        fail('tanks[$i].volumes[$j] length must equal trims count');
      }
    }
  }

  final lps = p['loadPoints'];
  if (lps is! List) fail('loadPoints must be an array');
  for (var i = 0; i < lps.length; i++) {
    final l = lps[i];
    if (l is! Map || l['name'] is! String || !_isNum(l['lcg'])) fail('loadPoints[$i] needs name and numeric lcg');
  }
}

ShipData shipFromProfile(Map<String, dynamic> p, String shipId) {
  validateShipProfile(p);
  final s = p['ship'] as Map;
  final d = ShipData();
  d.id = shipId;
  d.name = s['name'] as String;
  d.lightShip = (s['lightShip'] as num).toDouble();
  d.breadth = (s['breadth'] as num).toDouble();
  d.keelPlate = (s['keelPlate'] as num).toDouble();
  d.lbp = (s['lbp'] as num).toDouble();
  final marks = s['marks'] as Map;
  d.lf = _dl(marks['lf']);
  d.lm = _dl(marks['lm']);
  d.la = _dl(marks['la']);
  d.capacity = (s['capacity'] as num).toDouble();
  d.summerDraft = (s['summerDraft'] as num).toDouble();
  d.tropicalDraft = (s['tropicalDraft'] as num).toDouble();
  d.constant = (s['constant'] as num).toDouble();

  d.hydro = (p['hydrostatic']['rows'] as List).map<Row>((r) {
    return {for (final k in ['DRAFT', 'DISP', 'TPC', 'MTC', 'LCB', 'LCF']) k: (r[k] as num).toDouble()};
  }).toList();

  final holds = p['holds'] as List;
  d.holdIds = holds.map(holdIdOf).toList();
  d.holdsLcg = {for (final h in holds) holdIdOf(h): (h['lcg'] as num).toDouble()};
  final drafts = _dl(p['trimCorrectionDrafts']);
  d.trimtable = [
    for (var i = 0; i < drafts.length; i++)
      {
        'DRAFT': drafts[i],
        for (final h in holds) ...{
          '${holdIdOf(h)}|F': (h['trimCorrection']['f'][i] as num).toDouble(),
          '${holdIdOf(h)}|A': (h['trimCorrection']['a'][i] as num).toDouble(),
        },
      }
  ];

  d.capacityPlan = {for (final l in p['loadPoints'] as List) l['name'] as String: (l['lcg'] as num).toDouble()};

  final tanks = p['tanks'] as List;
  for (var i = 0; i < tanks.length; i++) {
    final t = tanks[i] as Map;
    d.tankNames[i + 1] = t['name'] as String;
    d.tankData['BWTANK${i + 1}'] = TankTable(
      _dl(t['trims']),
      _dl(t['soundings']),
      (t['volumes'] as List).map<List<double>>((r) => _dl(r)).toList(),
    );
  }

  final msgs = p['messages'];
  if (msgs is List) {
    for (final m in msgs) {
      if (m is String && m.trim().isNotEmpty && !d.messages.contains(m.trim())) d.messages.add(m.trim());
    }
  }
  return d;
}
