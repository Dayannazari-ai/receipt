import 'package:intl/intl.dart';
import '../models/app_settings.dart';
import 'persian_date.dart';

class CurrencyFormatter {
  static final NumberFormat _formatter = NumberFormat('#,###');

  static String format(num amount, Currency currency) {
    final formatted = _formatter.format(amount.round());
    return PersianDateUtil.toPersianDigits('$formatted ${currency.label}');
  }

  static String formatPlain(num amount) {
    return PersianDateUtil.toPersianDigits(_formatter.format(amount.round()));
  }
}
