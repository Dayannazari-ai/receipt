import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ocr_engine.dart';

/// OCR کاملاً آفلاین با Tesseract (مدل فارسی fas). بدون اینترنت، بدون حساب، بدون API key.
/// مدل باید در assets/tessdata/fas.traineddata باشد و در assets/tessdata_config.json ثبت شده باشد.
class OfflineOcrEngine implements OcrEngine {
  OfflineOcrEngine({this.language = 'fas', this.psm = 6});

  final String language;

  /// حالت تحلیل صفحه در Tesseract. ۶ = یک بلوک یکنواخت (مناسب جدول).
  final int psm;

  @override
  Future<OcrPage> recognizeImage(String imagePath) async {
    String? prepared;
    try {
      try {
        prepared = await _preprocess(imagePath);
      } catch (_) {
        prepared = null; // اگر پیش‌پردازش شکست خورد، با تصویر اصلی ادامه می‌دهیم
      }
      final input = prepared ?? imagePath;
      final hocr = await FlutterTesseractOcr.extractHocr(
        input,
        language: language,
        args: {'psm': '$psm', 'preserve_interword_spaces': '1'},
      );
      final page = parseHocr(hocr);
      if (page.words.isEmpty) {
        throw OcrException(
            'OCR هیچ متنی از تصویر نخواند. اگر مدل فارسی (fas.traineddata) داخل برنامه نیست یا تصویر خیلی تار است، همین نتیجه را می‌دهد.');
      }
      return page;
    } on OcrException {
      rethrow;
    } catch (e) {
      throw OcrException('خطا در OCR آفلاین: $e');
    } finally {
      if (prepared != null) {
        try {
          await File(prepared).delete();
        } catch (_) {}
      }
    }
  }

  /// خاکستری، کمی کنتراست بیشتر، سفید کردن زمینهٔ شفاف و بزرگ‌کردن تصاویر کوچک
  /// (فقط با dart:ui؛ بدون پکیج اضافه تا با بقیهٔ وابستگی‌ها تداخل نکند).
  Future<String> _preprocess(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final w = src.width;
    final h = src.height;

    var scale = 1.0;
    if (w < 1800) {
      scale = math.min(2.0, 1800 / w);
    } else if (math.max(w, h) > 4000) {
      scale = 4000 / math.max(w, h);
    }
    final tw = (w * scale).round();
    final th = (h * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    const c = 1.25; // کنتراست
    const off = 128 * (1 - c);
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.high
      ..colorFilter = const ui.ColorFilter.matrix(<double>[
        c * 0.299, c * 0.587, c * 0.114, 0, off, //
        c * 0.299, c * 0.587, c * 0.114, 0, off,
        c * 0.299, c * 0.587, c * 0.114, 0, off,
        0, 0, 0, 1, 0,
      ]);
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(tw, th);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    out.dispose();
    codec.dispose();
    if (data == null) throw OcrException('پیش‌پردازش تصویر ناموفق بود.');

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'ocr_${DateTime.now().microsecondsSinceEpoch}.png'));
    await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    return file.path;
  }
}

// ---------------------------------------------------------------------------
// تجزیهٔ hOCR (تابع عمومی و مستقل از Tesseract تا جداگانه قابل تست باشد)
// ---------------------------------------------------------------------------

final RegExp _wordTagRe = RegExp('''(<span[^>]*class=["']ocrx_word["'][^>]*>)(.*?)</span>''', dotAll: true);
final RegExp _bboxRe = RegExp(r'bbox\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)');
final RegExp _confRe = RegExp(r'x_wconf\s+(-?\d+(?:\.\d+)?)');
final RegExp _pageRe = RegExp(r'''class=["']ocr_page["'][^>]*bbox\s+-?\d+\s+-?\d+\s+(\d+)\s+(\d+)''');
final RegExp _tagRe = RegExp(r'<[^>]*>');

String _codeToString(int? code) {
  if (code == null || code < 0 || code > 0x10FFFF) return '?';
  return String.fromCharCode(code);
}

String _decodeEntities(String s) {
  return s
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => _codeToString(int.tryParse(m[1]!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => _codeToString(int.tryParse(m[1]!)))
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

OcrPage parseHocr(String hocr) {
  final words = <OcrWord>[];
  var maxX = 0.0;
  var maxY = 0.0;
  for (final m in _wordTagRe.allMatches(hocr)) {
    final tag = m.group(1)!;
    final box = _bboxRe.firstMatch(tag);
    if (box == null) continue;
    final text = _decodeEntities(m.group(2)!.replaceAll(_tagRe, '')).trim();
    if (text.isEmpty) continue;
    final x0 = double.parse(box.group(1)!);
    final y0 = double.parse(box.group(2)!);
    final x1 = double.parse(box.group(3)!);
    final y1 = double.parse(box.group(4)!);
    final conf = _confRe.firstMatch(tag);
    words.add(OcrWord(
      text: text,
      left: math.min(x0, x1),
      top: math.min(y0, y1),
      right: math.max(x0, x1),
      bottom: math.max(y0, y1),
      confidence: conf == null ? -1 : double.parse(conf.group(1)!),
    ));
    if (x1 > maxX) maxX = x1;
    if (y1 > maxY) maxY = y1;
  }
  final pg = _pageRe.firstMatch(hocr);
  final width = pg == null ? maxX : double.parse(pg.group(1)!);
  final height = pg == null ? maxY : double.parse(pg.group(2)!);
  return OcrPage(words: words, width: width, height: height);
}
