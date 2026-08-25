class Validators {
  static String? required(String? value, {String fieldName = 'این فیلد'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName نباید خالی باشد';
    return null;
  }

  static String? mobile(String? value) {
    if (value == null || value.trim().isEmpty) return 'شماره موبایل نباید خالی باشد';
    final digits = value.trim().replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^0?9\d{9}$').hasMatch(digits)) return 'شماره موبایل معتبر نیست';
    return null;
  }

  static String? nonNegativeNumber(String? value, {String fieldName = 'مبلغ'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName نباید خالی باشد';
    final n = double.tryParse(value.replaceAll(',', ''));
    if (n == null) return '$fieldName باید عدد باشد';
    if (n < 0) return '$fieldName نباید منفی باشد';
    return null;
  }

  static String? positiveInteger(String? value, {String fieldName = 'تعداد'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName نباید خالی باشد';
    final n = int.tryParse(value.replaceAll(',', ''));
    if (n == null) return '$fieldName باید عدد صحیح باشد';
    if (n <= 0) return '$fieldName باید معتبر و بزرگ‌تر از صفر باشد';
    return null;
  }
}
