}
import 'dart:io';
import 'package:excel/excel.dart';
import '../models/service.dart';
import '../repositories/service_repository.dart';
import '../repositories/vehicle_reference_repository.dart';

/// وارد کردن دستی نرخ‌نامه از فایل اکسل. برخلاف نسخه‌ی قبلی، هیچ داده‌ی
/// از‌پیش‌آماده‌ای وجود ندارد - کاربر خودش فایل و دسته‌بندی مقصد را انتخاب می‌کند.
///
/// فرمت مورد انتظار فایل اکسل (شیت اول)، هر ردیف یک خدمت:
///   ستون A: نام خدمت (الزامی)
///   ستون B: برند خودرو (اختیاری - خالی یعنی برای همه برندها)
///   ستون C: مدل خودرو (اختیاری)
///   ستون D: قیمت (الزامی، فقط عدد)
/// ردیف اول (سرستون) نادیده گرفته می‌شود.
class PriceListImportService {
  final _serviceRepo = ServiceRepository();
  final _vehicleRepo = VehicleReferenceRepository();

  /// پیش‌نمایش فایل قبل از وارد کردن نهایی: تعداد ردیف‌های معتبر و چند نمونه.
  Future<List<Map<String, dynamic>>> previewFile(String path) async {
    final rows = _readRows(path);
    return rows.take(10).map((r) => {'name': r.$1, 'brand': r.$2, 'model': r.$3, 'price': r.$4}).toList();
  }

  /// استخراج ایمن مقدار متنی از یک سلول اکسل، صرف‌نظر از نوع داخلی آن (متن/عدد/...).
  String? _cellText(CellValue? cv) {
    if (cv == null) return null;
    final s = cv.toString().trim();
    return s.isEmpty ? null : s;
  }

  List<(String, String?, String?, double)> _readRows(String path) {
    final bytes = File(path).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first]!;
    final result = <(String, String?, String?, double)>[];
    for (var i = 1; i < sheet.maxRows; i++) {
      final row = sheet.row(i);
      if (row.isEmpty) continue;
      final name = row.isNotEmpty ? _cellText(row[0]?.value) : null;
      if (name == null || name.isEmpty) continue;
      final brand = row.length > 1 ? _cellText(row[1]?.value) : null;
      final model = row.length > 2 ? _cellText(row[2]?.value) : null;
      final priceText = row.length > 3 ? _cellText(row[3]?.value) : null;
      final price = priceText == null ? null : double.tryParse(priceText.replaceAll(',', ''));
      if (price == null) continue;
      result.add((name, brand, model, price));
    }
    return result;
  }

  /// وارد کردن نهایی. کاربر دسته‌بندی مقصد را مشخص می‌کند (مثلاً «مکانیک» یا «برق خودرو»).
  Future<({int services, int brands})> importFromFile({
    required String path,
    required int categoryId,
  }) async {
    final rows = _readRows(path);
    if (rows.isEmpty) {
      throw StateError('هیچ ردیف معتبری در فایل پیدا نشد. فرمت فایل را بررسی کنید.');
    }

    final existingBrands = await _vehicleRepo.getAllBrands();
    final Map<String, int> brandIdByName = {for (final b in existingBrands) b.name: b.id!};
    int brandsAdded = 0;

    final existingServices = await _serviceRepo.getAll();
    int counter = existingServices.length + 1;
    int servicesAdded = 0;

    for (final row in rows) {
      final (name, brandName, modelName, price) = row;
      int? brandId;
      if (brandName != null) {
        if (!brandIdByName.containsKey(brandName)) {
          final id = await _vehicleRepo.insertBrand(brandName);
          brandIdByName[brandName] = id;
          brandsAdded++;
        }
        brandId = brandIdByName[brandName];
      }
      int? modelId;
      if (modelName != null && brandId != null) {
        final models = await _vehicleRepo.getModelsByBrand(brandId);
        final match = models.where((m) => m.name == modelName);
        if (match.isNotEmpty) {
          modelId = match.first.id;
        } else {
          modelId = await _vehicleRepo.insertModel(brandId, modelName);
        }
      }

      final code = 'IMP-${counter.toString().padLeft(3, '0')}';
      counter++;
      await _serviceRepo.insert(ServiceItem(
        name: name,
        code: code,
        categoryId: categoryId,
        brandId: brandId,
        modelId: modelId,
        price: price,
        notes: 'وارد‌شده از فایل نرخ‌نامه',
      ));
      servicesAdded++;
    }

    return (services: servicesAdded, brands: brandsAdded);
  }
}
