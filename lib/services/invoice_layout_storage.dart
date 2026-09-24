import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/invoice_layout_settings.dart';

/// ذخیره، بارگذاری و بازنشانی تنظیمات قالب فاکتور.
///
/// تنظیمات به‌صورت یک رشته‌ی JSON در shared_preferences نگه‌داری می‌شوند و
/// هیچ ارتباطی با دیتابیس برنامه (sqflite) ندارند.
///
/// اگر تنظیمات ذخیره‌شده‌ای وجود نداشته باشد، یا JSON خراب باشد، همیشه
/// مقادیر پیش‌فرض ([InvoiceLayoutSettings.defaults]) برگردانده می‌شود، پس
/// فراخوانی‌کننده هرگز با خطا یا مقدار null روبه‌رو نمی‌شود.
class InvoiceLayoutStorage {
  static const String _storageKey = 'invoice_layout_settings_v1';

  /// بارگذاری تنظیمات ذخیره‌شده. در هر حالت خطا، مقادیر پیش‌فرض برمی‌گردد.
  static Future<InvoiceLayoutSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return InvoiceLayoutSettings.defaults;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return InvoiceLayoutSettings.defaults;
      return InvoiceLayoutSettings.fromJson(decoded);
    } catch (_) {
      return InvoiceLayoutSettings.defaults;
    }
  }

  /// ذخیره‌ی تنظیمات. اگر ذخیره موفق باشد true برمی‌گردد.
  static Future<bool> save(InvoiceLayoutSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_storageKey, jsonEncode(settings.toJson()));
    } catch (_) {
      return false;
    }
  }

  /// بازنشانی همه‌ی تنظیمات به مقادیر پیش‌فرض (حذف مقدار ذخیره‌شده).
  static Future<bool> resetAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_storageKey);
    } catch (_) {
      return false;
    }
  }
}
