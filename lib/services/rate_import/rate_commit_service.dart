import 'package:shamsi_date/shamsi_date.dart';

import '../../models/rate_import_models.dart';
import '../../models/service.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/vehicle_reference_repository.dart';
import '../../utils/rate_text_utils.dart';

class RateCommitResult {
  int added = 0;
  int updated = 0;
  int skipped = 0;
  int brandsAdded = 0;
  int modelsAdded = 0;
  final List<String> failures = [];
}

/// متن ساختاریافته‌ی توضیحات برای خدمت جدید. خط اول ثابت است تا بعداً
/// بتوان این اطلاعات را در صورت توسعه‌ی دیتابیس دوباره استخراج کرد.
String buildRateNotes(ExtractedRateRow row, double factor, {required String finalCode}) {
  String fmt(double v) => RateText.formatNumber((v * factor).roundToDouble());
  final j = Jalali.now();
  final date = '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  final lines = <String>['وارد‌شده از فایل نرخ‌نامه'];
  if (row.minApproved != null) lines.add('حداقل مصوب: ${fmt(row.minApproved!)}');
  if (row.negotiated != null) lines.add('توافقی: ${fmt(row.negotiated!)}');
  if (row.special != null) lines.add('ویژه: ${fmt(row.special!)}');
  if (row.general != null) lines.add('قیمت: ${fmt(row.general!)}');
  if ((row.type ?? '').isNotEmpty) lines.add('تیپ: ${row.type}');
  if ((row.year ?? '').isNotEmpty) lines.add('سال: ${row.year}');
  if (row.unitLabel != null) lines.add('واحد فایل: ${row.unitLabel}');
  if (factor != 1) lines.add('ضریب تبدیل واحد اعمال‌شده: ${factor == 0.1 ? 'ریال به تومان' : 'تومان به ریال'}');
  if ((row.vehicleText ?? '').isNotEmpty) lines.add('خودرو (فایل): ${row.vehicleText}');
  if ((row.categoryText ?? '').isNotEmpty && row.categoryId == null) {
    lines.add('دسته‌بندی فایل: ${row.categoryText}');
  }
  final fileCode = row.code?.trim() ?? '';
  if (fileCode.isNotEmpty && fileCode != finalCode) lines.add('کد فایل: $fileCode');
  if ((row.notes ?? '').isNotEmpty) lines.add('توضیحات: ${row.notes}');
  lines.add('منبع: ${row.sourceLabel}');
  lines.add('تاریخ ورود: $date');
  return lines.join('\n');
}

/// ثبت نهایی فقط از مسیر Repositoryهای فعلی انجام می‌شود:
/// خدمت جدید با ServiceRepository.insert و تغییر قیمت با ServiceRepository.update
/// (که خودش قیمت قبلی را در service_price_history ثبت می‌کند).
class RateCommitService {
  final _serviceRepo = ServiceRepository();
  final _vehicleRepo = VehicleReferenceRepository();
  int _codeCounter = 1;

  Future<String> _uniqueCode(String? preferred) async {
    final p = preferred?.trim() ?? '';
    if (p.isNotEmpty && !await _serviceRepo.codeExists(p)) return p;
    while (true) {
      final c = 'IMP-${_codeCounter.toString().padLeft(4, '0')}';
      _codeCounter++;
      if (!await _serviceRepo.codeExists(c)) return c;
    }
  }

  Future<RateCommitResult> commit({
    required List<ExtractedRateRow> rows,
    required PriceField primary,
    required double factor,
    required int defaultCategoryId,
    void Function(int done, int total)? onProgress,
  }) async {
    final result = RateCommitResult();
    _codeCounter = (await _serviceRepo.getAll()).length + 1;

    final brands = await _vehicleRepo.getAllBrands();
    final brandIds = <String, int>{for (final b in brands) RateText.normalize(b.name): b.id!};
    final modelIds = <String, int>{};
    for (final b in brands) {
      for (final m in await _vehicleRepo.getModelsByBrand(b.id!)) {
        modelIds['${b.id}|${RateText.normalize(m.name)}'] = m.id!;
      }
    }

    var done = 0;
    for (final row in rows) {
      try {
        final price = row.effectivePrice(primary, factor);
        if (price == null) throw StateError('قیمت اصلی وجود ندارد');

        if (row.status == RateMatchStatus.newService) {
          int? brandId = row.brandId;
          int? modelId = row.modelId;
          final brandText = row.brandText?.trim() ?? '';
          if (brandId == null && brandText.isNotEmpty) {
            final key = RateText.normalize(brandText);
            brandId = brandIds[key];
            if (brandId == null) {
              brandId = await _vehicleRepo.insertBrand(brandText);
              brandIds[key] = brandId;
              result.brandsAdded++;
            }
          }
          final modelText = row.modelText?.trim() ?? '';
          if (modelId == null && modelText.isNotEmpty && brandId != null) {
            final key = '$brandId|${RateText.normalize(modelText)}';
            modelId = modelIds[key];
            if (modelId == null) {
              modelId = await _vehicleRepo.insertModel(brandId, modelText);
              modelIds[key] = modelId;
              result.modelsAdded++;
            }
          }
          final code = await _uniqueCode(row.code);
          await _serviceRepo.insert(ServiceItem(
            name: row.title.trim(),
            code: code,
            categoryId: row.categoryId ?? defaultCategoryId,
            brandId: brandId,
            modelId: modelId,
            price: price,
            notes: buildRateNotes(row, factor, finalCode: code),
          ));
          result.added++;
        } else if (row.status == RateMatchStatus.priceChanged && row.matched?.id != null) {
          // آخرین وضعیت را از دیتابیس می‌خوانیم؛ ممکن است بعد از Preview تغییر کرده باشد.
          final fresh = await _serviceRepo.getById(row.matched!.id!);
          if (fresh == null || fresh.isDeleted == 1) throw StateError('خدمت موجود دیگر وجود ندارد');
          if ((fresh.price - price).abs() < 0.5) {
            result.skipped++;
          } else {
            await _serviceRepo.update(fresh, fresh.copyWith(price: price));
            result.updated++;
          }
        } else {
          result.skipped++;
        }
      } catch (e) {
        result.failures.add('«${row.title}»: $e');
      }
      done++;
      onProgress?.call(done, rows.length);
    }
    return result;
  }
}
