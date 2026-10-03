import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/rate_import_models.dart';
import 'rate_table_source.dart';

/// وقتی PDF هیچ متن قابل استخراجی ندارد (اسکن یا عکس).
class ScannedPdfException implements Exception {
  ScannedPdfException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// خواندن مستقیم PDF متنی (بدون OCR) با pdfrx.
/// ترتیب متن در PDF فارسی قابل اعتماد نیست، پس جدول از روی «مختصات کلمات» ساخته می‌شود.
/// خروجی هر جدول هم‌شکل شیت‌های Excel است:
///   [ستون‌های قیمت از چپ به راست ..., عنوان خدمت, شماره ردیف]
/// با سطر اول به‌عنوان سرستون.
class PdfRateTableSource implements RateTableSource {
  static bool _inited = false;

  @override
  Future<List<RawTable>> read(String path) async {
    if (!_inited) {
      pdfrxFlutterInitialize();
      _inited = true;
    }
    final doc = await PdfDocument.openFile(path);
    final pages = <List<PdfTok>>[];
    try {
      for (final page in doc.pages) {
        final raw = await page.loadText();
        pages.add(raw == null ? <PdfTok>[] : _tokensOf(raw));
      }
    } finally {
      doc.dispose();
    }

    final total = pages.fold<int>(0, (a, p) => a + p.length);
    if (total < 5) {
      throw ScannedPdfException(
          'این PDF متن قابل خواندن ندارد (اسکن یا عکس است). خواندن PDF اسکن‌شده در مرحله‌ی بعد (OCR) اضافه می‌شود.');
    }

    final built = await compute(buildPdfTables, pages);
    final result = <RawTable>[];
    for (final t in built) {
      result.add(RawTable(t.name, t.rows));
    }
    if (result.isEmpty) {
      throw ScannedPdfException('در این PDF جدولی با قیمت پیدا نشد.');
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// استخراج کلمه‌ها از pdfrx
// ---------------------------------------------------------------------------

/// یک کلمه با مختصات (دستگاه مختصات PDF: محور y رو به بالا).
class PdfTok {
  PdfTok(this.t, this.l, this.r, this.b, this.tp);
  final String t;
  final double l;
  final double r;
  final double b;
  final double tp;
  double get cx => (l + r) / 2;
  double get cy => (b + tp) / 2;
}

class PdfTableData {
  PdfTableData(this.name, this.rows);
  final String name;
  final List<List<String>> rows;
}

bool _isSpace(int c) =>
    c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0 || c == 0x2009 || c == 0x202F;

const Map<String, String> _charFix = {
  '\u06BE': '\u0647', // ھ -> ه
  '\u06C1': '\u0647', // ہ -> ه
  '\u064A': '\u06CC', // ي -> ی
  '\u0649': '\u06CC', // ى -> ی
  '\u0643': '\u06A9', // ك -> ک
};

final RegExp _invisible = RegExp('[\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');

String _fix(String s) {
  final cleaned = s.replaceAll(_invisible, '');
  final sb = StringBuffer();
  for (final ch in cleaned.split('')) {
    sb.write(_charFix[ch] ?? ch);
  }
  return sb.toString();
}

double _num(dynamic v) => (v as num).toDouble();

/// کلمه‌ها را از متن کامل + مستطیل هر حرف می‌سازد.
void _wordsFromChars(String s, List<dynamic> rects, List<PdfTok> out) {
  final n = s.length < rects.length ? s.length : rects.length;
  var i = 0;
  while (i < n) {
    if (_isSpace(s.codeUnitAt(i))) {
      i++;
      continue;
    }
    var j = i;
    while (j < n && !_isSpace(s.codeUnitAt(j))) {
      j++;
    }
    var l = double.infinity;
    var r = -double.infinity;
    var bt = double.infinity;
    var tp = -double.infinity;
    for (var k = i; k < j; k++) {
      final c = rects[k];
      final cl = _num(c.left);
      final cr = _num(c.right);
      final cb = _num(c.bottom);
      final ct = _num(c.top);
      if (cl < l) l = cl;
      if (cr > r) r = cr;
      if (cb < bt) bt = cb;
      if (ct > tp) tp = ct;
    }
    final word = _fix(s.substring(i, j));
    if (word.isNotEmpty && l.isFinite && r.isFinite) {
      out.add(PdfTok(word, l, r, bt, tp));
    }
    i = j;
  }
}

/// با نسخه‌های مختلف pdfrx سازگار است (PdfPageRawText یا PdfPageText) چون با dynamic کار می‌کند.
List<PdfTok> _tokensOf(dynamic raw) {
  final out = <PdfTok>[];
  String? full;
  List<dynamic>? rects;
  try {
    full = raw.fullText as String;
  } catch (_) {}
  try {
    rects = (raw.charRects as List).cast<dynamic>();
  } catch (_) {}
  if (full != null && rects != null && rects.isNotEmpty) {
    _wordsFromChars(full, rects, out);
    return out;
  }
  List<dynamic>? frags;
  try {
    frags = (raw.fragments as List).cast<dynamic>();
  } catch (_) {}
  if (frags == null) return out;
  for (final f in frags) {
    final String s = f.text as String;
    final n = s.length;
    if (n == 0 || s.trim().isEmpty) continue;
    List<dynamic>? fr;
    try {
      final cr = f.charRects;
      if (cr != null) fr = (cr as List).cast<dynamic>();
    } catch (_) {}
    if (fr != null && fr.length == n) {
      _wordsFromChars(s, fr, out);
    } else {
      final b = f.bounds;
      final bl = _num(b.left);
      final w = _num(b.right) - bl;
      var i = 0;
      while (i < n) {
        if (_isSpace(s.codeUnitAt(i))) {
          i++;
          continue;
        }
        var j = i;
        while (j < n && !_isSpace(s.codeUnitAt(j))) {
          j++;
        }
        final word = _fix(s.substring(i, j));
        if (word.isNotEmpty) {
          out.add(PdfTok(word, bl + w * i / n, bl + w * j / n, _num(b.bottom), _num(b.top)));
        }
        i = j;
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// ساخت جدول از مختصات (در Isolate اجرا می‌شود)
// ---------------------------------------------------------------------------

const String _dig = r'[0-9\u06F0-\u06F9\u0660-\u0669]';
const String _sep = r'[,\u066C\u060C]';
final RegExp _priceRe = RegExp('^(?:$_dig{1,3}(?:$_sep$_dig{3})+|$_dig{4,})-?\$');
final RegExp _placeholderRe = RegExp(r'^-?/{3,}-?$');
final RegExp _numberRe = RegExp('^$_dig{1,3}\$');
final RegExp _dashRe = RegExp(r'^[-\u2013\u2014]+$');

class _Line {
  _Line(this.cy, this.toks);
  double cy;
  final List<PdfTok> toks;
  PdfTok? rowNo;
  List<PdfTok> prices = [];
  List<PdfTok> text = [];
  bool get isData => prices.isNotEmpty || rowNo != null;
}

class _Tbl {
  _Tbl(this.multi);
  final bool multi;
  final List<_Line> header = [];
  final List<_Line> lines = [];
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

List<_Line> _clusterLines(List<PdfTok> input) {
  final toks = input.where((t) => !_dashRe.hasMatch(t.t)).toList()
    ..sort((a, b) => b.cy.compareTo(a.cy));
  List<_Line> pass(double tol) {
    final lines = <_Line>[];
    for (final w in toks) {
      if (lines.isNotEmpty && (lines.last.cy - w.cy).abs() <= tol) {
        final l = lines.last;
        l.toks.add(w);
        var sum = 0.0;
        for (final x in l.toks) {
          sum += x.cy;
        }
        l.cy = sum / l.toks.length;
      } else {
        lines.add(_Line(w.cy, [w]));
      }
    }
    return lines;
  }

  final first = pass(1.5);
  final gaps = <double>[];
  for (var i = 0; i + 1 < first.length; i++) {
    final g = first[i].cy - first[i + 1].cy;
    if (g >= 6) gaps.add(g);
  }
  final med = gaps.isEmpty ? 12.0 : _median(gaps);
  var tol = 0.4 * med;
  if (tol > 4.5) tol = 4.5;
  if (tol < 1.5) tol = 1.5;
  return pass(tol);
}

void _classify(_Line line) {
  final ws = List<PdfTok>.from(line.toks)..sort((a, b) => b.r.compareTo(a.r));
  if (ws.length >= 2 && _numberRe.hasMatch(ws.first.t)) {
    line.rowNo = ws.first;
    ws.removeAt(0);
  }
  final prices = <PdfTok>[];
  final text = <PdfTok>[];
  for (final w in ws) {
    if (_priceRe.hasMatch(w.t) || _placeholderRe.hasMatch(w.t)) {
      prices.add(w);
    } else {
      text.add(w);
    }
  }
  prices.sort((a, b) => a.cx.compareTo(b.cx));
  line.prices = prices;
  line.text = text;
}

String _joinRtl(List<PdfTok> ws, {bool header = false}) {
  final s = List<PdfTok>.from(ws)..sort((a, b) => b.cx.compareTo(a.cx));
  return s
      .map((w) => header ? w.t.replaceAll(RegExp(r'-+$'), '') : w.t)
      .where((t) => t.isNotEmpty)
      .join(' ')
      .trim();
}

String _cleanPrice(String t) => t.replaceAll(RegExp(r'^-+|-+$'), '');

List<_Tbl> _segment(List<_Line> lines) {
  final tables = <_Tbl>[];
  _Tbl? cur;
  final pending = <_Line>[];
  for (final l in lines) {
    if (!l.isData) {
      pending.add(l);
      continue;
    }
    final bool multi;
    if (l.prices.length >= 2) {
      multi = true;
    } else if (l.prices.length == 1) {
      multi = false;
    } else {
      multi = cur?.multi ?? false;
    }
    var pendingTokens = 0;
    for (final p in pending) {
      pendingTokens += p.toks.length;
    }
    final _Tbl? c = cur;
    final _Tbl target;
    if (c == null || c.multi != multi || (multi && pendingTokens >= 3)) {
      target = _Tbl(multi);
      target.header.addAll(pending);
      tables.add(target);
      cur = target;
    } else {
      target = c;
      target.lines.addAll(pending);
    }
    pending.clear();
    target.lines.add(l);
  }
  return tables;
}

List<List<String>>? _buildRows(_Tbl tb) {
  final data = tb.lines.where((l) => l.prices.isNotEmpty).toList();
  if (data.isEmpty) return null;

  List<double> cols;
  if (tb.multi) {
    final counts = <int, int>{};
    for (final l in data) {
      counts[l.prices.length] = (counts[l.prices.length] ?? 0) + 1;
    }
    var modeLen = 0;
    var best = -1;
    counts.forEach((k, v) {
      if (v > best || (v == best && k > modeLen)) {
        best = v;
        modeLen = k;
      }
    });
    final full = data.where((l) => l.prices.length == modeLen).toList();
    cols = [
      for (var i = 0; i < modeLen; i++)
        _median(full.map((l) => l.prices[i].cx).toList())
    ];
  } else {
    cols = [_median(data.map((l) => l.prices.first.cx).toList())];
  }
  final n = cols.length;
  final bounds = <double>[
    for (var i = 0; i + 1 < n; i++) (cols[i] + cols[i + 1]) / 2
  ];
  int colIdx(double x) {
    var c = 0;
    for (final b in bounds) {
      if (x > b) c++;
    }
    return c;
  }

  final lastR = _median(data
      .map((l) => tb.multi ? l.prices.last.r : l.prices.first.r)
      .toList());
  final priceEdge = lastR + 2;

  List<String> headerRow(List<PdfTok> ws) {
    final cells = List<List<PdfTok>>.generate(n, (_) => <PdfTok>[]);
    final title = <PdfTok>[];
    for (final w in ws) {
      if (w.cx > priceEdge) {
        title.add(w);
      } else {
        cells[colIdx(w.cx)].add(w);
      }
    }
    return [
      for (final c in cells) _joinRtl(c, header: true),
      _joinRtl(title, header: true),
      '',
    ];
  }

  final rows = <List<String>>[];
  final hw = <PdfTok>[];
  for (final h in tb.header) {
    hw.addAll(h.toks);
  }
  rows.add(hw.isEmpty ? [for (var i = 0; i < n + 2; i++) ''] : headerRow(hw));

  for (final l in tb.lines) {
    if (!l.isData) {
      rows.add(headerRow(l.toks));
      continue;
    }
    final cells = List<String>.filled(n, '');
    for (final w in l.prices) {
      if (_placeholderRe.hasMatch(w.t)) continue;
      cells[colIdx(w.cx)] = _cleanPrice(w.t);
    }
    rows.add([...cells, _joinRtl(l.text), l.rowNo?.t ?? '']);
  }
  return rows;
}

String _signature(List<List<String>> rows) =>
    rows.skip(1).map((r) => r.join('|')).join('\n');

/// ورودی: توکن‌های هر صفحه. خروجی: جدول‌های هم‌شکل Excel.
List<PdfTableData> buildPdfTables(List<List<PdfTok>> pages) {
  final out = <PdfTableData>[];
  final seen = <String>{};
  for (var p = 0; p < pages.length; p++) {
    if (pages[p].isEmpty) continue;
    final lines = _clusterLines(pages[p]);
    for (final l in lines) {
      _classify(l);
    }
    final tables = _segment(lines);
    var k = 0;
    for (final tb in tables) {
      final rows = _buildRows(tb);
      if (rows == null || rows.length < 2) continue;
      // بخش‌های تکراری (مثل جدول پایین هر صفحه) فقط یک‌بار می‌آیند.
      final sig = _signature(rows);
      if (!seen.add(sig)) continue;
      k++;
      final name = k == 1 ? 'صفحه ${p + 1}' : 'صفحه ${p + 1} - بخش $k';
      out.add(PdfTableData(name, rows));
    }
  }
  return out;
}
