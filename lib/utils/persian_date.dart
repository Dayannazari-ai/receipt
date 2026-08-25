import 'package:shamsi_date/shamsi_date.dart';

class PersianDateUtil {
  static const _months = [
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
  ];
  static const _weekDays = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'];
  static const _persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  static String toPersianDigits(String input) {
    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buffer.write(_persianDigits[code - 48]);
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  static Jalali _toJalali(DateTime dt) => Jalali.fromDateTime(dt);

  static String formatDate(String isoDate) {
    try {
      final j = _toJalali(DateTime.parse(isoDate));
      return toPersianDigits('${j.day} ${_months[j.month - 1]} ${j.year}');
    } catch (_) {
      return isoDate;
    }
  }

  static String formatDateShort(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final j = _toJalali(dt);
      return toPersianDigits('${_weekDays[j.weekDay - 1]} ${j.day} ${_months[j.month - 1]}');
    } catch (_) {
      return isoDate;
    }
  }

  static String formatDateNumeric(String isoDate) {
    try {
      final j = _toJalali(DateTime.parse(isoDate));
      final mm = j.month.toString().padLeft(2, '0');
      final dd = j.day.toString().padLeft(2, '0');
      return toPersianDigits('${j.year}/$mm/$dd');
    } catch (_) {
      return isoDate;
    }
  }

  static String formatDateTime(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final j = _toJalali(dt);
      final hh = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return toPersianDigits('${j.day} ${_months[j.month - 1]} ${j.year} - $hh:$min');
    } catch (_) {
      return isoDate;
    }
  }

  static DateTime startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime endOfToday() =>
      startOfToday().add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

  static DateTime startOfWeek() {
    final j = _toJalali(DateTime.now());
    final startJalali = j.addDays(-(j.weekDay - 1));
    final g = startJalali.toDateTime();
    return DateTime(g.year, g.month, g.day);
  }

  static DateTime startOfMonth() {
    final j = _toJalali(DateTime.now());
    final g = Jalali(j.year, j.month, 1).toDateTime();
    return DateTime(g.year, g.month, g.day);
  }
}
