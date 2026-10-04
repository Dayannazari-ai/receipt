import 'package:flutter/foundation.dart';

import '../../models/rate_import_models.dart';
import 'ocr_engine.dart';
import 'offline_ocr_engine.dart';
import 'rate_pdf_source.dart';
import 'rate_table_source.dart';

/// گزارش کیفیت OCR برای نمایش به کاربر. هیچ داده‌ای از نمونه‌ها داخل کد نیست؛
/// همه‌چیز در زمان اجرا از خروجی OCR ساخته می‌شود.
class OcrReport {
  const OcrReport({
    required this.words,
    required this.lowConfidence,
    required this.suspectNumbers,
    required this.droppedTitleWords,
    required this.blankedCells,
  });

  final int words;
  final int lowConfidence;

  /// عددهایی که شبیه قیمت بودند ولی ساختار معتبر نداشتند (خالی گذاشته شدند، حدس زده نشدند).
  final List<String> suspectNumbers;

  /// کلمه‌های درشتِ عنوان جدول (مثل «خدمات کولر») که از سرستون‌ها کنار گذاشته شد.
  final int droppedTitleWords;

  /// متن‌های نامفهوم لابه‌لای قیمت‌ها که خالی شدند.
  final int blankedCells;

  bool get needsAttention => lowConfidence > 0 || suspectNumbers.isNotEmpty || blankedCells > 0;

  String get summary {
    final parts = <String>['OCR: $words کلمه خوانده شد'];
    if (lowConfidence > 0) parts.add('$lowConfidence کلمه با اطمینان پایین');
    if (suspectNumbers.isNotEmpty) {
      final shown = suspectNumbers.take(6).join('، ');
      parts.add('${suspectNumbers.length} عدد مشکوک خالی گذاشته شد ($shown)');
    }
    if (blankedCells > 0) parts.add('$blankedCells سلول نامفهوم خالی شد');
    parts.add('پیش‌نمایش را با دقت بررسی کنید.');
    return parts.join(' · ');
  }
}

class PreparedOcr {
  const PreparedOcr(this.tokens, this.report);
  final List<PdfTok> tokens;
  final OcrReport report;
}

// ---------------------------------------------------------------------------
// نرمال‌سازی کلمه‌ها
// ---------------------------------------------------------------------------

const double _lowConfidence = 60;
const String _placeholder = '/////';

const Map<String, String> _fixMap = {
  '\u06BE': '\u0647', // ھ -> ه
  '\u06C1': '\u0647', // ہ -> ه
  '\u064A': '\u06CC', // ي -> ی
  '\u0649': '\u06CC', // ى -> ی
  '\u0643': '\u06A9', // ك -> ک
};

final RegExp _invisible = RegExp('[\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _digitChar = RegExp(r'[0-9\u06F0-\u06F9\u0660-\u0669]');
final RegExp _onlyNumberChars = RegExp(r'^[0-9\u06F0-\u06F9\u0660-\u0669,]+$');
final RegExp _edgeJunk = RegExp(r'^[|\-\u2013\u2014_~=+*\u2022\u00B7\[\]{}<>()]+|[|\-\u2013\u2014_~=+*\u2022\u00B7\[\]{}<>()]+$');
final RegExp _sepChars = RegExp(r"[.\u066B\u066C\u060C/\\'\u2019`:;]");
final RegExp _pureJunk = RegExp(r'^[|_\-\u2013\u2014.:;~=+*\u2022\u00B7\[\]{}<>()]+$');

const String _dig = r'[0-9\u06F0-\u06F9\u0660-\u0669]';
final RegExp _priceLike = RegExp('^(?:$_dig{1,3}(?:,$_dig{3})+|$_dig{4,})\$');

String _normText(String s) {
  final cleaned = s.replaceAll(_invisible, '');
  final sb = StringBuffer();
  for (final ch in cleaned.split('')) {
    sb.write(_fixMap[ch] ?? ch);
  }
  return sb.toString().trim();
}

/// اگر کلمه فقط عدد و جداکننده باشد، شکل استاندارد (با ویرگول هزارگان) را برمی‌گرداند؛
/// وگرنه null. اعداد کمتر از ۴ رقم بدون جداکننده (شمارهٔ ردیف و …) دست‌نخورده می‌مانند.
String? _asNumberCandidate(String raw) {
  var t = raw.replaceAll(_spaces, '').replaceAll(_edgeJunk, '');
  if (t.isEmpty) return null;
  t = t.replaceAll(_sepChars, ',').replaceAll(RegExp(r'\u066C|\u060C'), ',');
  t = t.replaceAll(RegExp(r',{2,}'), ',').replaceAll(RegExp(r'^,+|,+$'), '');
  if (t.isEmpty || !_onlyNumberChars.hasMatch(t)) return null;
  final digits = _digitChar.allMatches(t).length;
  final hasSep = t.contains(',');
  if (digits >= 4 || (hasSep && digits >= 3)) return t;
  return null;
}

class _W {
  _W(this.text, this.l, this.r, this.b, this.t, this.conf);
  String text;
  final double l;
  final double r;
  final double b;
  final double t;
  final double conf;
  bool isNum = false;
  bool isPlaceholder = false;
  bool suspect = false;
  double get cx => (l + r) / 2;
  double get cy => (b + t) / 2;
  double get h => t - b;
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// خروجی OCR را به همان «توکن با مختصات»ی تبدیل می‌کند که سازندهٔ جدول PDF می‌فهمد.
///  - مختصات به مقیاس PDF (ارتفاع متن ≈ ۱۰) و محور y رو به بالا برده می‌شود.
///  - اعداد با جداکننده‌های مختلف به شکل استاندارد درمی‌آیند.
///  - «توافقی» و متن‌های نامفهومِ بین قیمت‌ها = سلول بدون قیمت.
///  - عدد مشکوک هرگز حدس زده نمی‌شود؛ خالی می‌ماند و در گزارش می‌آید.
PreparedOcr prepareOcrTokens(OcrPage page) {
  final ws = <_W>[];
  var low = 0;
  for (final w in page.words) {
    final text = _normText(w.text);
    if (text.isEmpty || _pureJunk.hasMatch(text)) continue;
    if (w.confidence >= 0 && w.confidence < _lowConfidence) low++;
    ws.add(_W(text, w.left, w.right, w.top, w.bottom, w.confidence));
  }
  if (ws.isEmpty) {
    return const PreparedOcr(
      <PdfTok>[],
      OcrReport(words: 0, lowConfidence: 0, suspectNumbers: <String>[], droppedTitleWords: 0, blankedCells: 0),
    );
  }

  // مقیاس‌دهی: میانهٔ ارتفاع کلمه‌ها = ۱۰ (هم‌مقیاس با PDF) و برگرداندن محور y.
  final rawMedH = _median([for (final w in ws) w.t - w.b]);
  final s = rawMedH > 0 ? 10.0 / rawMedH : 1.0;
  final H = page.height;
  final items = <_W>[
    for (final w in ws) _W(w.text, w.l * s, w.r * s, (H - w.t) * s, (H - w.b) * s, w.conf),
  ];

  final suspects = <String>[];
  for (final w in items) {
    if (w.text == 'توافقی') {
      w.text = _placeholder;
      w.isPlaceholder = true;
      continue;
    }
    final n = _asNumberCandidate(w.text);
    if (n == null) continue;
    if (_priceLike.hasMatch(n)) {
      w.text = n;
      w.isNum = true;
    } else {
      suspects.add(w.text);
      w.text = _placeholder;
      w.isPlaceholder = true;
      w.suspect = true;
    }
  }

  final medAll = _median([for (final w in items) w.h]);
  final cells = items.where((w) => w.isNum || w.isPlaceholder).toList();
  final nums = items.where((w) => w.isNum).toList();

  // عنوان درشتِ جدول (مثل «خدمات کولر») بالاتر از همهٔ قیمت‌ها: از سرستون‌ها حذف می‌شود.
  var dropped = 0;
  final kept = <_W>[];
  if (nums.isNotEmpty) {
    var topNumCy = nums.first.cy;
    for (final n in nums) {
      if (n.cy > topNumCy) topNumCy = n.cy;
    }
    for (final w in items) {
      if (!w.isNum && !w.isPlaceholder && w.h > 1.6 * medAll && w.cy > topNumCy) {
        dropped++;
        continue;
      }
      kept.add(w);
    }
  } else {
    kept.addAll(items);
  }

  // متن نامفهوم «بین» قیمت‌های هم‌ردیف = سلول خراب‌شده؛ به عنوان خدمت نمی‌چسبد.
  var blanked = 0;
  for (final w in kept) {
    if (w.isNum || w.isPlaceholder) continue;
    var minCx = double.infinity;
    var maxCx = -double.infinity;
    var count = 0;
    for (final c in cells) {
      if ((c.cy - w.cy).abs() <= 0.5 * medAll) {
        count++;
        if (c.cx < minCx) minCx = c.cx;
        if (c.cx > maxCx) maxCx = c.cx;
      }
    }
    if (count >= 2 && w.cx > minCx && w.cx < maxCx) {
      w.text = _placeholder;
      w.isPlaceholder = true;
      blanked++;
    }
  }

  final tokens = <PdfTok>[for (final w in kept) PdfTok(w.text, w.l, w.r, w.b, w.t)];
  return PreparedOcr(
    tokens,
    OcrReport(
      words: kept.length,
      lowConfidence: low,
      suspectNumbers: suspects,
      droppedTitleWords: dropped,
      blankedCells: blanked,
    ),
  );
}

// ---------------------------------------------------------------------------
// منبع جدول از تصویر
// ---------------------------------------------------------------------------

/// تصویر (عکس، اسکرین‌شات) → OCR آفلاین → جدول خام هم‌شکل Excel/PDF.
/// ساخت جدول از مختصات با همان سازندهٔ PDF انجام می‌شود؛ بنابراین ساختارهای مختلف
/// (چند ستون خودرو، فقط «خدمت + مبلغ»، چند بخش در یک تصویر) بدون قالب ثابت پشتیبانی می‌شوند.
class OcrRateTableSource implements RateTableSource {
  OcrRateTableSource({OcrEngine? engine}) : _engine = engine ?? OfflineOcrEngine();

  final OcrEngine _engine;

  /// گزارش آخرین خواندن (برای نمایش در صفحه).
  OcrReport? lastReport;

  @override
  Future<List<RawTable>> read(String path) async {
    lastReport = null;
    final page = await _engine.recognizeImage(path);
    final prepared = prepareOcrTokens(page);
    lastReport = prepared.report;
    if (prepared.tokens.length < 5) {
      throw OcrException('از این تصویر متن کافی خوانده نشد. تصویر واضح‌تر یا برش‌خورده‌تر امتحان کنید.');
    }
    final built = await compute(buildPdfTables, <List<PdfTok>>[prepared.tokens]);
    final result = <RawTable>[];
    for (final t in built) {
      final rows = [for (final r in t.rows) List<String>.from(r)];
      // در خروجی سازنده، ستون ماقبل آخر همیشه «عنوان خدمت» است (آخری شمارهٔ ردیف).
      // سرستونِ این ستون در تصویر معمولاً ترکیبی است («نوع خودرو / نوع خدمات») و نباید نقش را اشتباه کند.
      if (rows.isNotEmpty && rows.first.length >= 2) {
        rows.first[rows.first.length - 2] = 'عنوان خدمت';
      }
      result.add(RawTable(t.name.replaceFirst('صفحه', 'تصویر'), rows));
    }
    if (result.isEmpty) {
      throw OcrException('در این تصویر جدولی با قیمت پیدا نشد.');
    }
    return result;
  }
}
