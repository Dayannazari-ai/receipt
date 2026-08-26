import 'dart:io';
import 'package:excel/excel.dart';
import '../models/service.dart';
import '../repositories/service_repository.dart';
import '../repositories/vehicle_reference_repository.dart';

class PriceListImportService {
  final _serviceRepo = ServiceRepository();
  final _vehicleRepo = VehicleReferenceRepository();

  String? _cellText(CellValue? cv) {
    if (cv == null) return null;
    final s = cv.toString().trim();
    return s.isEmpty ? null : s;
  }

  double? _cellNumber(CellValue? cv) {
    final text = _cellText(cv);
    if (text == null) return null;
    return double.tryParse(text.replaceAll(',', ''));
  }

  List<(String, String?, double)> _extractEntries(String path) {
    final bytes = File(path).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final entries = <(String, String?, double)>[];

    for (final sheet in excel.tables.values) {
      if (sheet.maxRows == 0) continue;
      final header = sheet.row(0);

      int? serviceColIndex;
      for (var i = 0; i < header.length; i++) {
        final text = _cellText(header[i]?.value);
        if (text != null && (text.contains('خدمات') || text.contains('خدمت'))) {
          serviceColIndex = i;
          break;
        }
      }
      if (serviceColIndex == null) continue;

      final brandCols = <int, String>{};
      for (var i = 0; i < serviceColIndex; i++) {
        final text = _cellText(header[i]?.value);
        if (text != null) brandCols[i] = text;
      }
      final isFlat = brandCols.length <= 1;

      for (var r = 1; r < sheet.maxRows; r++) {
        final row = sheet.row(r);
        if (row.length <= serviceColIndex) continue;
        final name = _cellText(row[serviceColIndex]?.value);
        if (name == null) continue;

        if (isFlat) {
          if (brandCols.isEmpty) continue;
          final priceIdx = brandCols.keys.first;
          if (row.length <= priceIdx) continue;
          final price = _cellNumber(row[priceIdx]?.value);
          if (price == null) continue;
          entries.add((name, null, price));
        } else {
          for (final entry in brandCols.entries) {
            if (row.length <= entry.key) continue;
            final price = _cellNumber(row[entry.key]?.value);
            if (price == null) continue;
            entries.add((name, entry.value, price));
          }
        }
      }
    }
    return entries;
  }

  Future<List<Map<String, dynamic>>> previewFile(String path) async {
    final entries = _extractEntries(path);
    return entries
        .take(15)
        .map((e) => {'name': e.$1, 'brand': e.$2 ?? 'همه برندها', 'price': e.$3})
        .toList();
  }

  Future<int> countEntries(String path) async => _extractEntries(path).length;

  Future<({int services, int brands})> importFromFile({
    required String path,
    required int categoryId,
  }) async {
    final entries = _extractEntries(path);
    if (entries.isEmpty) {
      throw StateError(
          'هیچ ردیف معتبری در فایل پیدا نشد. مطمئن شوید سرستون یکی از سلول‌های سطر اول شامل کلمه‌ی «خدمات» یا «خدمت» است.');
    }

    final existingBrands = await _vehicleRepo.getAllBrands();
    final Map<String, int> brandIdByName = {for (final b in existingBrands) b.name: b.id!};
    int brandsAdded = 0;

    final existingServices = await _serviceRepo.getAll();
    int counter = existingServices.length + 1;
    int servicesAdded = 0;

    for (final entry in entries) {
      final (name, brandName, price) = entry;
      int? brandId;
      if (brandName != null) {
        if (!brandIdByName.containsKey(brandName)) {
          final id = await _vehicleRepo.insertBrand(brandName);
          brandIdByName[brandName] = id;
          brandsAdded++;
        }
        brandId = brandIdByName[brandName];
      }

      final code = 'IMP-${counter.toString().padLeft(4, '0')}';
      counter++;
      await _serviceRepo.insert(ServiceItem(
        name: name,
        code: code,
        categoryId: categoryId,
        brandId: brandId,
        modelId: null,
        price: price,
        notes: 'وارد‌شده از فایل نرخ‌نامه',
      ));
      servicesAdded++;
    }

    return (services: servicesAdded, brands: brandsAdded);
  }
}
