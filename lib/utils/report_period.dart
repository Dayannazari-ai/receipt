import 'package:shamsi_date/shamsi_date.dart';
import 'persian_date.dart';

enum PeriodKind { daily, weekly, monthly, yearly, custom }

/// یک بازه‌ی زمانی گزارش (روزانه، هفتگی، ماهانه، سالانه یا سفارشی) بر اساس
/// تقویم شمسی. [from] ابتدای بازه و [to] پایان بازه (شامل آخرین لحظه) است.
class ReportPeriod {
  final PeriodKind kind;
  final DateTime anchor;
  final DateTime from;
  final DateTime to;

  const ReportPeriod._(this.kind, this.anchor, this.from, this.to);

  static const List<String> _months = [
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
  ];

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  /// بازه‌ای از نوع [kind] که [anchor] داخل آن است.
  factory ReportPeriod.of(PeriodKind kind, DateTime anchor) {
    if (kind == PeriodKind.weekly) {
      final j = Jalali.fromDateTime(anchor);
      final s = j.addDays(-(j.weekDay - 1)).toDateTime();
      final from = _day(s);
      final to = _endOfDay(DateTime(from.year, from.month, from.day + 6));
      return ReportPeriod._(kind, anchor, from, to);
    }
    if (kind == PeriodKind.monthly) {
      final j = Jalali.fromDateTime(anchor);
      final from = _day(Jalali(j.year, j.month, 1).toDateTime());
      final next = j.month == 12 ? Jalali(j.year + 1, 1, 1) : Jalali(j.year, j.month + 1, 1);
      final to = _day(next.toDateTime()).subtract(const Duration(milliseconds: 1));
      return ReportPeriod._(kind, anchor, from, to);
    }
    if (kind == PeriodKind.yearly) {
      final j = Jalali.fromDateTime(anchor);
      final from = _day(Jalali(j.year, 1, 1).toDateTime());
      final to = _day(Jalali(j.year + 1, 1, 1).toDateTime()).subtract(const Duration(milliseconds: 1));
      return ReportPeriod._(kind, anchor, from, to);
    }
    // روزانه (و پیش‌فرض)
    return ReportPeriod._(kind, anchor, _day(anchor), _endOfDay(anchor));
  }

  factory ReportPeriod.custom(DateTime from, DateTime to) =>
      ReportPeriod._(PeriodKind.custom, from, _day(from), _endOfDay(to));

  /// یک بازه به عقب (-۱) یا جلو (+۱). بازه‌ی سفارشی جابه‌جا نمی‌شود.
  ReportPeriod shift(int dir) {
    if (kind == PeriodKind.daily) {
      return ReportPeriod.of(kind, DateTime(anchor.year, anchor.month, anchor.day + dir));
    }
    if (kind == PeriodKind.weekly) {
      return ReportPeriod.of(kind, DateTime(anchor.year, anchor.month, anchor.day + 7 * dir));
    }
    if (kind == PeriodKind.monthly) {
      final j = Jalali.fromDateTime(anchor);
      final idx = j.year * 12 + (j.month - 1) + dir;
      return ReportPeriod.of(kind, Jalali(idx ~/ 12, idx % 12 + 1, 1).toDateTime());
    }
    if (kind == PeriodKind.yearly) {
      final j = Jalali.fromDateTime(anchor);
      return ReportPeriod.of(kind, Jalali(j.year + dir, 1, 1).toDateTime());
    }
    return this;
  }

  String get label {
    if (kind == PeriodKind.daily) {
      return PersianDateUtil.formatDate(from.toIso8601String());
    }
    if (kind == PeriodKind.monthly) {
      final j = Jalali.fromDateTime(from);
      return PersianDateUtil.toPersianDigits('${_months[j.month - 1]} ${j.year}');
    }
    if (kind == PeriodKind.yearly) {
      final j = Jalali.fromDateTime(from);
      return PersianDateUtil.toPersianDigits('سال ${j.year}');
    }
    return 'از ${PersianDateUtil.formatDate(from.toIso8601String())} تا ${PersianDateUtil.formatDate(to.toIso8601String())}';
  }
}
