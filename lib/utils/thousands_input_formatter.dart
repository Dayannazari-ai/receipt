import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// جداکننده‌ی هزارگان زنده هنگام تایپ در فیلدهای مبلغی (ارقام لاتین).
/// مقدار واقعی (بدون کاما) با حذف کاما از متن قابل استخراج است.
class ThousandsInputFormatter extends TextInputFormatter {
  static final NumberFormat _formatter = NumberFormat('#,###');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final newText = _formatter.format(int.parse(digitsOnly));

    // تعداد ارقام قبل از کرسر در متن جدید (پیش از فرمت) را می‌شماریم
    // تا بعد از فرمت، کرسر را به‌درستی بعد از همان تعداد رقم قرار دهیم.
    final digitsBeforeCursor =
        newValue.text.substring(0, newValue.selection.end).replaceAll(RegExp(r'[^0-9]'), '').length;

    int seen = 0;
    int newCursor = newText.length;
    for (var i = 0; i < newText.length; i++) {
      if (RegExp(r'[0-9]').hasMatch(newText[i])) {
        seen++;
        if (seen == digitsBeforeCursor) {
          newCursor = i + 1;
          break;
        }
      }
    }
    if (digitsBeforeCursor == 0) newCursor = 0;

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// حذف جداکننده برای استخراج مقدار واقعی قبل از parse.
  static String unformat(String text) => text.replaceAll(',', '');
}
