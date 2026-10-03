/// نتیجه‌ی تبدیل یک متن به مبلغ.
class ParsedAmount {
  final double? value;

  /// 'rial' یا 'toman' یا null (اگر در متن واحد پول دیده نشد)
  final String? unit;

  /// اگر null نباشد یعنی عدد مشکوک است و باید کاربر بررسی کند.
  final String? problem;

  const ParsedAmount({this.value, this.unit, this.problem});
}

/// ابزارهای متنی مشترک برای ورود نرخ از فایل (Excel / PDF / OCR).
class RateText {
  RateText._();

  static const String _faDigits = '\u06F0\u06F1\u06F2\u06F3\u06F4\u06F5\u06F6\u06F7\u06F8\u06F9';
  static const String _arDigits = '\u0660\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668\u0669';

  /// تبدیل ارقام فارسی و عربی به انگلیسی.
  static String toLatinDigits(String input) {
    final sb = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final fa = _faDigits.indexOf(ch);
      if (fa >= 0) {
        sb.write(fa);
        continue;
      }
      final ar = _arDigits.indexOf(ch);
      if (ar >= 0) {
        sb.write(ar);
        continue;
      }
      sb.write(ch);
    }
    return sb.toString();
  }

  /// نرمال‌سازی متن برای مقایسه: یکسان‌سازی ی/ک/ه، حذف اعراب و نیم‌فاصله،
  /// تبدیل ارقام، حذف علائم و فاصله‌ی اضافه.
  static String normalize(String? input) {
    if (input == null) return '';
    var t = toLatinDigits(input);
    t = t
        .replaceAll('\u064A', '\u06CC') // ي -> ی
        .replaceAll('\u0649', '\u06CC') // ى -> ی
        .replaceAll('\u0643', '\u06A9') // ك -> ک
        .replaceAll('\u06C0', '\u0647') // ۀ -> ه
        .replaceAll('\u0629', '\u0647') // ة -> ه
        .replaceAll('\u0623', '\u0627') // أ -> ا
        .replaceAll('\u0625', '\u0627') // إ -> ا
        .replaceAll('\u0622', '\u0627') // آ -> ا
        .replaceAll('\u200C', ' ') // نیم‌فاصله
        .replaceAll('\u200F', '')
        .replaceAll('\u200E', '')
        .replaceAll('\u0640', ''); // کشیده
    t = t.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    t = t.toLowerCase();
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// تبدیل متن به مبلغ. پشتیبانی از:
  /// 1,500,000 / 1500000 / ۱٬۵۰۰٬۰۰۰ / ۱,۵۰۰,۰۰۰ / 1.500.000 / 1500000.0
  /// و واحدهای «تومان» و «ریال».
  static ParsedAmount parseAmount(String? raw) {
    if (raw == null) return const ParsedAmount();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const ParsedAmount();

    final n = normalize(trimmed);
    String? unit;
    if (n.contains('ریال') || n.contains('rial')) {
      unit = 'rial';
    } else if (n.contains('تومان') || n.contains('toman')) {
      unit = 'toman';
    }

    var t = toLatinDigits(trimmed);
    t = t.replaceAll(
        RegExp('(\u0631\u06CC\u0627\u0644|\u0631\u064A\u0627\u0644|\u062A\u0648\u0645\u0627\u0646|rial|toman|rls|irr|irt)', caseSensitive: false), ' ');
    t = t.replaceAll('\u066B', '.');
    t = t.replaceAll(RegExp(r'[,\u066C\u060C\s\u00A0\u202F]'), '');

    if (t.isEmpty) {
      return ParsedAmount(unit: unit, problem: 'مقدار عددی پیدا نشد: «$trimmed»');
    }

    double value;
    String? problem;
    if (RegExp(r'^\d+$').hasMatch(t)) {
      value = double.parse(t);
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
      value = double.parse(t.replaceAll('.', ''));
    } else if (RegExp(r'^\d+\.\d+$').hasMatch(t)) {
      value = double.parse(t);
      if (value != value.roundToDouble()) problem = 'قیمت اعشاری: «$trimmed»';
    } else {
      final m = RegExp(r'\d+(\.\d+)?').firstMatch(t);
      if (m == null) {
        return ParsedAmount(unit: unit, problem: 'عدد معتبر نیست: «$trimmed»');
      }
      value = double.parse(m.group(0)!);
      problem = 'متن اضافه کنار عدد: «$trimmed»';
    }

    if (value <= 0) problem = 'قیمت صفر یا منفی: «$trimmed»';
    return ParsedAmount(value: value, unit: unit, problem: problem);
  }

  /// نمایش عدد با جداکننده‌ی هزارگان انگلیسی.
  static String formatNumber(double v) {
    final isInt = v == v.roundToDouble();
    final s = isInt ? v.round().toString() : v.toString();
    final parts = s.split('.');
    final intPart = parts[0];
    final sb = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final fromEnd = intPart.length - i;
      sb.write(intPart[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) sb.write(',');
    }
    if (parts.length > 1) sb.write('.${parts[1]}');
    return sb.toString();
  }

  /// شباهت دو متن نرمال‌شده بر اساس کلمات مشترک (۰ تا ۱).
  static double tokenSimilarity(String a, String b) {
    final ta = a.split(' ').where((e) => e.isNotEmpty).toSet();
    final tb = b.split(' ').where((e) => e.isNotEmpty).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return inter / union;
  }
}
