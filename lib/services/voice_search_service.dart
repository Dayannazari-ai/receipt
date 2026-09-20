import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// سرویس تشخیص گفتار برای جستجوی صوتی کالا/خدمت.
///
/// طراحی‌شده تا هرگز برنامه را کرش نکند: اگر تشخیص گفتار فارسی روی دستگاه
/// در دسترس نباشد (پک زبان نصب نشده، دستگاه پشتیبانی نمی‌کند، یا هر خطای
/// دیگر)، فقط null برمی‌گرداند تا لایه‌ی بالاتر پیام مناسب نشان دهد و
/// جستجوی دستی معمولی بدون مشکل ادامه یابد.
///
/// هیچ فایل صوتی ذخیره نمی‌شود؛ فقط متن نهایی تشخیص‌داده‌شده برگردانده می‌شود.
class VoiceSearchService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  /// شروع گوش‌دادن و برگرداندن متن نهایی تشخیص‌داده‌شده.
  /// در صورت هرگونه خطا یا عدم دسترسی، null برمی‌گرداند (بدون Crash).
  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 6)}) async {
    final ok = await _ensureInitialized();
    if (!ok) return null;

    String? result;
    final completer = Completer<String?>();
    try {
      await _speech.listen(
        localeId: 'fa_IR',
        onResult: (r) {
          if (r.finalResult && !completer.isCompleted) {
            completer.complete(r.recognizedWords);
          }
        },
        listenFor: timeout,
      );
      result = await completer.future.timeout(
        timeout + const Duration(seconds: 3),
        onTimeout: () => null,
      );
    } catch (_) {
      result = null;
    } finally {
      try {
        await _speech.stop();
      } catch (_) {}
    }
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }

  bool get isListening => _speech.isListening;
}
