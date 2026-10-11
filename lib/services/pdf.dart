// Dependency-free PDF writer + the two report layouts (port of js/pdf.js, byte-identical output).
import 'dart:typed_data';

import '../core/util.dart';

const Map<String, List<int>> _pdfWidths = {
  'R': [250, 333, 408, 500, 500, 833, 778, 180, 333, 333, 500, 564, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444, 921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722, 556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500, 333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500, 500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541],
  'B': [250, 333, 555, 500, 500, 1000, 833, 278, 333, 333, 500, 570, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500, 930, 722, 667, 722, 722, 667, 611, 778, 778, 389, 500, 778, 667, 944, 722, 778, 611, 778, 722, 556, 667, 722, 722, 1000, 722, 722, 667, 333, 278, 333, 581, 500, 333, 500, 556, 444, 556, 444, 333, 500, 556, 278, 333, 556, 278, 833, 556, 500, 556, 556, 444, 389, 333, 556, 500, 722, 500, 500, 444, 394, 220, 394, 520],
  'I': [250, 333, 420, 500, 500, 833, 778, 214, 333, 333, 500, 675, 250, 333, 250, 278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 675, 675, 675, 500, 920, 611, 611, 667, 722, 611, 611, 722, 722, 333, 444, 667, 556, 833, 667, 722, 611, 722, 611, 500, 556, 722, 611, 833, 611, 556, 556, 389, 278, 389, 422, 500, 333, 500, 500, 444, 500, 444, 278, 500, 500, 278, 278, 444, 278, 722, 500, 500, 500, 500, 389, 389, 278, 500, 444, 667, 444, 444, 389, 400, 275, 400, 541],
};
const Map<String, String> _pdfFontNames = {'R': 'Times-Roman', 'B': 'Times-Bold', 'I': 'Times-Italic'};

/// Keep printable Latin-1; everything else becomes "?" so the PDF never breaks.
String pdfSanitize(String s) {
  final out = StringBuffer();
  for (final c in s.runes) {
    if (c == 9) {
      out.write(' ');
    } else if (c >= 32 && c <= 126) {
      out.writeCharCode(c);
    } else if (c >= 160 && c <= 255) {
      out.writeCharCode(c);
    } else {
      out.write('?');
    }
  }
  return out.toString();
}

double pdfTextWidth(String s, String font, double size) {
  final w = _pdfWidths[font]!;
  var sum = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    sum += (c >= 32 && c <= 126) ? w[c - 32] : 500;
  }
  return (sum * size) / 1000;
}

class PdfDoc {
  final double w;
  final double h;
  final List<List<String>> pages = [];

  PdfDoc({this.w = 595.28, this.h = 841.89}) {
    addPage();
  }

  void addPage() => pages.add([]);
  List<String> get ops => pages.last;

  static String n(double v) => jsNum((v * 100 + 0.5).floorToDouble() / 100);

  void text(String str, double x, double y,
      {String font = 'R', double size = 11, String align = 'left', double width = 0, bool underline = false}) {
    final s = pdfSanitize(str);
    if (s.isEmpty) return;
    final tw = pdfTextWidth(s, font, size);
    var px = x;
    if (align == 'right') {
      px = x + width - tw;
    } else if (align == 'center') {
      px = x + (width - tw) / 2;
    }
    final esc = s.replaceAllMapped(RegExp(r'[\\()]'), (m) => '\\${m[0]}');
    final base = h - y;
    ops.add('BT /F$font ${n(size)} Tf ${n(px)} ${n(base)} Td ($esc) Tj ET');
    if (underline) line(px, y + size * 0.12, px + tw, y + size * 0.12, size * 0.06);
  }

  void line(double x1, double y1, double x2, double y2, [double wd = 0.5, double gray = 0]) {
    ops.add('${n(gray)} G ${n(wd)} w ${n(x1)} ${n(h - y1)} m ${n(x2)} ${n(h - y2)} l S');
  }

  void rect(double x, double y, double wd, double ht, {double? fill, double? stroke = 0.5, double strokeW = 0.5}) {
    final parts = <String>[];
    if (fill != null) parts.add('${n(fill)} g');
    if (stroke != null) parts.add('${n(stroke)} G ${n(strokeW)} w');
    parts.add('${n(x)} ${n(h - y - ht)} ${n(wd)} ${n(ht)} re');
    parts.add(fill != null && stroke != null ? 'B' : (fill != null ? 'f' : 'S'));
    ops.add(parts.join(' ') + (fill != null ? ' 0 g' : ''));
  }

  Uint8List build() {
    final objs = <String?>[];
    int add(String body) {
      objs.add(body);
      return objs.length;
    }

    const catalogId = 1, pagesId = 2;
    objs.add(null);
    objs.add(null);
    final fontIds = <String, int>{};
    for (final k in ['R', 'B', 'I']) {
      fontIds[k] = add('<< /Type /Font /Subtype /Type1 /BaseFont /${_pdfFontNames[k]} /Encoding /WinAnsiEncoding >>');
    }
    final fontRes = '<< /FR ${fontIds['R']} 0 R /FB ${fontIds['B']} 0 R /FI ${fontIds['I']} 0 R >>';
    final pageIds = <int>[];
    for (final o in pages) {
      final stream = o.join('\n');
      final contentId = add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
      pageIds.add(add(
          '<< /Type /Page /Parent $pagesId 0 R /MediaBox [0 0 ${n(w)} ${n(h)}] /Resources << /Font $fontRes >> /Contents $contentId 0 R >>'));
    }
    objs[catalogId - 1] = '<< /Type /Catalog /Pages $pagesId 0 R >>';
    objs[pagesId - 1] =
        '<< /Type /Pages /Kids [${pageIds.map((i) => '$i 0 R').join(' ')}] /Count ${pageIds.length} >>';

    final out = StringBuffer('%PDF-1.4\n%âãÏÓ\n');
    final offsets = <int>[];
    for (var i = 0; i < objs.length; i++) {
      offsets.add(out.length);
      out.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
    }
    final xref = out.length;
    out.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
    for (final o in offsets) {
      out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    out.write('trailer\n<< /Size ${objs.length + 1} /Root $catalogId 0 R >>\nstartxref\n$xref\n%%EOF\n');
    final str = out.toString();
    final bytes = Uint8List(str.length);
    for (var i = 0; i < str.length; i++) {
      bytes[i] = str.codeUnitAt(i) & 0xff;
    }
    return bytes;
  }
}

String _fmt3(Object? v) {
  if (v == null || v == '') return '';
  if (v is num) return v.isFinite ? toFixed(v.toDouble(), 3) : '$v';
  final d = double.tryParse('$v');
  if (d == null || !d.isFinite) return '$v';
  return toFixed(d, 3);
}

/// Report 1 - Draft Survey Report (one A4 page).
Uint8List buildDraftSurveyPdf(Map<String, dynamic> d) {
  final doc = PdfDoc();
  const m = 79.0;
  final cw = doc.w - 2 * m;
  var y = 62.0;

  doc.text('DRAFT SURVEY REPORT', m, y, font: 'B', size: 16, align: 'center', width: cw, underline: true);
  y += 34;
  final info = [
    ['VESSEL :', '${d['shipName'] ?? ''}'.toUpperCase()],
    ['VOY NO.', '${d['voyNo'] ?? ''}'],
    ['CARGO:', '${d['cargo'] ?? ''}'],
    ['PORT:', '${d['port'] ?? ''}'],
    ['DATE :', '${d['date'] ?? ''}'],
  ];
  for (final kv in info) {
    doc.text(kv[0], m + 7, y, size: 11);
    doc.text(kv[1], m + 7 + 180, y, size: 11);
    y += 18;
  }
  y += 10;

  final boxX1 = m + cw - 240, boxX2 = m + cw - 120;
  void cell(String v, double x, bool bold) =>
      doc.text(v, x, y, font: bold ? 'B' : 'R', size: 10.5, align: 'right', width: 120 - 7);
  void line(String label, Object? a, Object? b, {bool bold = false, bool numeric = true}) {
    doc.text(label, m + 7, y, font: bold ? 'B' : 'R', size: 10.5);
    cell(numeric ? _fmt3(a) : '${a ?? ''}', boxX1, bold);
    cell(numeric ? _fmt3(b) : '${b ?? ''}', boxX2, bold);
    y += 16.5;
  }

  void section(String title) {
    y += 8;
    doc.text(title, m + 7, y, font: 'B', size: 11);
    y += 17;
  }

  doc.text("SHIP'S DRAFT", m + 7, y, font: 'B', size: 10.5);
  cell('INITIAL', boxX1, true);
  cell('FINAL', boxX2, true);
  y += 16.5;
  final i = d['initial'] as Map, f = d['final'] as Map;
  line('FORWARD MEAN', i['DF'], f['DF']);
  line('AFTER MEAN', i['DA'], f['DA']);
  line('FORE & AFT MEAN', i['FAMean'], f['FAMean']);
  line('PORT MIDSHIP', i['DMP'], f['DMP']);
  line('STARBOARD MIDSHIP', i['DMS'], f['DMS']);
  line('MEAN MIDSHIP', i['DM'], f['DM']);
  line('QUARTER MEANS', i['QM'], f['QM']);
  line('DENSITY', i['density'], f['density'], numeric: false);

  section('DISPLACEMENT');
  line('FROM CORRECTED DRAFTS', i['disp'], f['disp']);
  line('CORRECTED FOR TRIM', i['dispTrim'], f['dispTrim']);
  line('CORRECTED FOR DENSITY', i['dispDensity'], f['dispDensity']);

  section('KNOWN WEIGHTS');
  line('BUNKERS', i['bunkers'], f['bunkers']);
  line('FRESH WATER', i['fw'], f['fw']);
  line('BALLAST', i['bw'], f['bw']);
  line('OTHER', 0, 0);
  line('TOTAL KNOWN WEIGHTS', i['knownWeight'], f['knownWeight'], bold: true);

  section('SUMMARY');
  line('CORRECTED DISPLACEMENT', i['dispDensity'], f['dispDensity']);
  line('TOTAL KNOWN WEIGHTS', i['knownWeight'], f['knownWeight']);
  line('LIGHT SHIP', i['lightShip'], f['lightShip']);
  line('CONSTANT', i['constant'], f['constant']);
  line('CARGO', i['cargo'], f['cargo'], bold: true);

  y += 16;
  doc.text('From the above figures obtained at initial and final surveys it is estimated that the amount of cargo', m + 6, y,
      size: 10.5);
  y += 14;
  doc.text('loaded/discharged to be as follows:', m + 6, y, size: 10.5);
  y += 30;

  final ic = toNum('${i['cargo']}'), fc = toNum('${f['cargo']}');
  String result;
  if (ic > fc) {
    result = 'When Discharging : (Initial cargo - final cargo) = ${toFixed(ic - fc, 2)} (Mt)';
  } else if (ic < fc) {
    result = 'When Loading : (Final cargo - initial cargo) = ${toFixed(fc - ic, 2)} (Mt)';
  } else {
    result = 'No cargo loaded/discharged.';
  }
  doc.text(result, m, y, font: 'B', size: 11.5, align: 'center', width: cw);
  y += 70;
  doc.text('SURVEYOR:', m + 20, y, size: 11);
  doc.text('CHIEF OFFICE:', m + 20 + cw / 2 - 20, y, size: 11);
  return doc.build();
}

/// Report 2 - Ballast Water Summary (paginated table).
Uint8List buildSoundingPdf(Map<String, dynamic> d) {
  final doc = PdfDoc();
  const m = 57.0;
  final cw = doc.w - 2 * m;
  final cols = [
    [cw * 0.34, 'left', 'Tank'],
    [cw * 0.22, 'right', 'Sounding(m)'],
    [cw * 0.22, 'right', 'Volume(m3)'],
    [cw * 0.22, 'right', 'Weight (t)'],
  ];
  const rh = 20.0, top = 56.0;
  final bottom = doc.h - 60;
  var y = top;

  void header(bool first) {
    if (first) {
      doc.text('${d['title']}', m, y + 6, font: 'B', size: 18, align: 'center', width: cw);
      y += 34;
      final meta = [
        ['DF:', '${d['df']}'],
        ['DA:', '${d['da']}'],
        ['TRIM:', '${d['trim']}'],
        ['DENSITY:', '${d['density']}'],
      ];
      var x = m;
      for (final kv in meta) {
        doc.text(kv[0], x, y, font: 'B', size: 11);
        doc.text(kv[1], x + pdfTextWidth(kv[0], 'B', 11) + 4, y, size: 11);
        x += 120;
      }
      y += 14;
    }
    var x = m;
    doc.rect(m, y, cw, rh, fill: 0.955, stroke: 0.4);
    for (final c in cols) {
      doc.text(c[2] as String, x + 6, y + 14,
          font: 'B', size: 10.5, align: c[1] as String, width: (c[0] as double) - 12);
      x += c[0] as double;
    }
    y += rh;
  }

  header(true);
  for (final r in (d['rows'] as List)) {
    if (y + rh > bottom) {
      doc.addPage();
      y = top;
      header(false);
    }
    var x = m;
    doc.rect(m, y, cw, rh, fill: null, stroke: 0.4);
    final vals = ['${r['tank']}', '${r['sounding']}', '${r['volume']}', '${r['weight']}'];
    for (var i = 0; i < 4; i++) {
      doc.text(vals[i], x + 6, y + 14, size: 10.5, align: cols[i][1] as String, width: (cols[i][0] as double) - 12);
      x += cols[i][0] as double;
    }
    y += rh;
  }

  if (y + 120 > doc.h - 30) {
    doc.addPage();
    y = top;
  }
  y += 26;
  doc.text('Total Weight: ${d['total']} t', m, y, font: 'B', size: 11, align: 'right', width: cw);
  y += 56;
  doc.text('M.V ${d['shipName'] ?? ''}', m, y, font: 'B', size: 11, align: 'right', width: cw);
  return doc.build();
}
