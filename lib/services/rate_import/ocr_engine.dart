/// یک کلمهٔ تشخیص‌داده‌شده توسط OCR با مختصات روی تصویر.
/// دستگاه مختصات: مبدأ بالا-چپ و محور y رو به پایین (مثل hOCR).
class OcrWord {
  const OcrWord({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence = -1,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// ۰ تا ۱۰۰. اگر موتور اطمینان نداده باشد ۱- است.
  final double confidence;
}

/// نتیجهٔ OCR یک تصویر.
class OcrPage {
  const OcrPage({required this.words, required this.width, required this.height});
  final List<OcrWord> words;
  final double width;
  final double height;
}

/// خطای قابل‌نمایش به کاربر (پیام فارسی).
class OcrException implements Exception {
  OcrException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// رابط موتور OCR. بقیهٔ سیستم فقط به همین رابط وابسته است؛
/// موتور فعلی آفلاین است (OfflineOcrEngine) و بعداً قابل تعویض است.
abstract class OcrEngine {
  Future<OcrPage> recognizeImage(String imagePath);
}
