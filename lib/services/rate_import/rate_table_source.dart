import 'dart:io';

import 'package:excel/excel.dart';
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

List<RawTable> _readExcelSync(String path) {
  final bytes = File(path).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final result = <RawTable>[];
  for (final entry in excel.tables.entries) {
    final sheet = entry.value;
    final rows = <List<String>>[];
    for (var r = 0; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      rows.add(row.map((d) => d?.value?.toString().trim() ?? '').toList());
    }
    while (rows.isNotEmpty && rows.last.every((c) => c.isEmpty)) {
      rows.removeLast();
    }
    if (rows.isNotEmpty) result.add(RawTable(entry.key, rows));
  }
  return result;
}
