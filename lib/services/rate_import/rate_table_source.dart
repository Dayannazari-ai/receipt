import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/foundation.dart';

import '../../models/rate_import_models.dart';

/// هر منبع ورودی (Excel، PDF متنی، OCR) باید خروجی خود را به جدول خام تبدیل کند.
/// در مراحل بعد، پیاده‌سازی‌های PDF و OCR با همین رابط اضافه می‌شوند و
/// بقیه‌ی سیستم (نگاشت ستون، تطبیق، Preview، ثبت) تغییری نمی‌کند.
abstract class RateTableSource {
  Future<List<RawTable>> read(String path);
}

/// خواندن مستقیم فایل Excel (بدون OCR). پردازش سنگین در Isolate جدا انجام می‌شود.
class ExcelRateTableSource implements RateTableSource {
  @override
  Future<List<RawTable>> read(String path) => compute(_readExcelSync, path);
}

/// متن سلول. برای سلول‌های فرمول‌دار، نتیجهٔ محاسبه‌شده‌ای که خود Excel در فایل ذخیره کرده
/// خوانده می‌شود (همان عددی که در Excel دیده می‌شود)، نه متن فرمول.
String _cellText(Data? d) {
  final v = d?.value;
  if (v == null) return '';
  if (v is FormulaCellValue) return (v.cachedValue ?? '').trim();
  return v.toString().trim();
}

List<RawTable> _readExcelSync(String path) {
  final bytes = File(path).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final result = <RawTable>[];
  for (final entry in excel.tables.entries) {
    final sheet = entry.value;
    final rows = <List<String>>[];
    for (var r = 0; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      rows.add(row.map(_cellText).toList());
    }
    while (rows.isNotEmpty && rows.last.every((c) => c.isEmpty)) {
      rows.removeLast();
    }
    if (rows.isNotEmpty) result.add(RawTable(entry.key, rows));
  }
  return result;
}
