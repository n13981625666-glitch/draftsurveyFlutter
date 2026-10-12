// Small helpers that reproduce the JavaScript semantics the original app relied on.

/// JS `Number(text)` with "not a number -> 0" (the original `toNum`).
double toNum(String? s) {
  if (s == null) return 0;
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return 0;
  final d = double.tryParse(t);
  if (d == null || !d.isFinite) return 0;
  return d;
}

/// JS `Number.prototype.toFixed` (also "NaN", "Infinity", never "-0.000" for an exact -0).
String toFixed(double v, int digits) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
  if (v == 0) v = 0.0; // drops the sign of -0
  return v.toStringAsFixed(digits);
}

/// JS `String(number)`: integers without ".0".
String jsNum(double v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
  if (v == 0) return '0';
  if (v == v.truncateToDouble() && v.abs() < 1e21) return v.toStringAsFixed(0);
  return v.toString();
}

/// JS unary plus on `toFixed`: `+(x).toFixed(d)`.
double round(double v, int digits) {
  if (!v.isFinite) return v;
  return double.parse(toFixed(v, digits));
}

double lerp(double x0, double y0, double x1, double y1, double x) {
  if (x1 == x0) return y0;
  return y0 + ((y1 - y0) * ((x - x0) / (x1 - x0)));
}

typedef TRow = Map<String, double>;

double _g(TRow r, String k) => r[k] ?? double.nan;

/// Linear interpolation / extrapolation in a table sorted ascending by [key]. null when the table is empty
/// or [x] is NaN (same as the JS `interpTable`).
double? interpTable(List<TRow> table, String key, String valKey, double x) {
  if (table.isEmpty) return null;
  final n = table.length;
  if (x <= _g(table[0], key)) {
    final r0 = table[0];
    final r1 = n > 1 ? table[1] : table[0];
    return lerp(_g(r0, key), _g(r0, valKey), _g(r1, key), _g(r1, valKey), x);
  }
  if (x >= _g(table[n - 1], key)) {
    final r1 = table[n - 1];
    final r0 = n > 1 ? table[n - 2] : r1;
    return lerp(_g(r0, key), _g(r0, valKey), _g(r1, key), _g(r1, valKey), x);
  }
  for (var i = 1; i < n; i++) {
    if (x <= _g(table[i], key)) {
      final r0 = table[i - 1];
      final r1 = table[i];
      return lerp(_g(r0, key), _g(r0, valKey), _g(r1, key), _g(r1, valKey), x);
    }
  }
  return null;
}

/// `interpTable(...) || 0`
double interpOrZero(List<TRow> table, String key, String valKey, double x) {
  final v = interpTable(table, key, valKey, x);
  if (v == null || v.isNaN) return 0;
  return v;
}

String ymdToday() {
  final n = DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${p(n.month)}-${p(n.day)}';
}

/// JS `Math.min(...list)` ("Infinity" for an empty list, NaN if any is NaN).
double jsMin(Iterable<double> xs) {
  var m = double.infinity;
  for (final x in xs) {
    if (x.isNaN) return double.nan;
    if (x < m) m = x;
  }
  return m;
}

String safeFileName(String s) => s.replaceAll(RegExp(r'[^\w.-]+'), '_');
