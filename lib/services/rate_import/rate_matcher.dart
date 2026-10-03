import '../../models/rate_import_models.dart';
import '../../models/service.dart';
import '../../models/vehicle_reference.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/vehicle_reference_repository.dart';
import '../../utils/rate_text_utils.dart';

/// تطبیق ردیف‌های استخراج‌شده با خدمات، برندها و مدل‌های موجود.
/// این کلاس فقط می‌خواند و هیچ‌چیز در دیتابیس نمی‌نویسد.
class RateMatcher {
  RateMatcher({
    required this.services,
    required this.brands,
    required this.modelsByBrand,
    required this.categories,
  }) {
    for (final b in brands) {
      _brandByNorm[RateText.normalize(b.name)] = b;
      final map = <String, VehicleModel>{};
      for (final m in modelsByBrand[b.id!] ?? const <VehicleModel>[]) {
        map[RateText.normalize(m.name)] = m;
        _modelNames[m.id!] = m.name;
      }
      _modelsNormByBrand[b.id!] = map;
    }
    for (final c in categories) {
      _categoryByNorm[RateText.normalize(c.name)] = c;
    }
    for (final s in services) {
      _serviceNorm[s.id!] = RateText.normalize(s.name);
      _codeIndex.putIfAbsent(s.code.trim().toLowerCase(), () => []).add(s);
    }
  }

  final List<ServiceItem> services;
  final List<VehicleBrand> brands;
  final Map<int, List<VehicleModel>> modelsByBrand;
  final List<ServiceCategory> categories;

  final Map<String, VehicleBrand> _brandByNorm = {};
  final Map<int, Map<String, VehicleModel>> _modelsNormByBrand = {};
  final Map<int, String> _modelNames = {};
  final Map<String, ServiceCategory> _categoryByNorm = {};
  final Map<int, String> _serviceNorm = {};
  final Map<String, List<ServiceItem>> _codeIndex = {};

  static Future<RateMatcher> load() async {
    final services = await ServiceRepository().getAll();
    final vehicleRepo = VehicleReferenceRepository();
    final brands = await vehicleRepo.getAllBrands();
    final models = <int, List<VehicleModel>>{};
    for (final b in brands) {
      models[b.id!] = await vehicleRepo.getModelsByBrand(b.id!);
    }
    final categories = await ServiceCategoryRepository().getAll();
    return RateMatcher(services: services, brands: brands, modelsByBrand: models, categories: categories);
  }

  ServiceItem? serviceById(int id) {
    for (final s in services) {
      if (s.id == id) return s;
    }
    return null;
  }

  ServiceCategory? categoryByName(String? name) {
    if (name == null) return null;
    return _categoryByNorm[RateText.normalize(name)];
  }

  /// برچسب برند/مدل یک خدمت موجود برای نمایش.
  String scopeLabel(ServiceItem s) {
    if (s.brandId == null) return 'همه برندها';
    String brandName = '؟';
    for (final b in brands) {
      if (b.id == s.brandId) brandName = b.name;
    }
    if (s.modelId == null) return brandName;
    return '$brandName / ${_modelNames[s.modelId!] ?? '؟'}';
  }

  /// ارزیابی همه‌ی ردیف‌ها، همراه با تشخیص ردیف‌های تکراری داخل فایل.
  void evaluateAll(List<ExtractedRateRow> rows, PriceField primary, double factor) {
    final seen = <String>{};
    for (final row in rows) {
      evaluate(row, primary, factor);
      if (row.status == RateMatchStatus.uncertain) continue;
      final key = row.matched != null
          ? 'S${row.matched!.id}'
          : 'N|${RateText.normalize(row.title)}|${row.brandId ?? RateText.normalize(row.brandText)}|${row.modelId ?? RateText.normalize(row.modelText)}';
      if (seen.contains(key) && !row.userConfirmed) {
        row.issues = [...row.issues, 'ردیف تکراری در همین فایل (همان خدمت قبلاً آمده است)'];
        row.status = RateMatchStatus.uncertain;
      } else {
        seen.add(key);
      }
    }
  }

  void evaluate(ExtractedRateRow row, PriceField primary, double factor) {
    final issues = <String>[...row.extractionFlags];
    row.matched = null;
    row.newBrand = false;
    row.newModel = false;
    row.brandId = null;
    row.modelId = null;

    // دسته‌بندی (اگر در فایل بود و در بانک پیدا شد)
    row.categoryId = categoryByName(row.categoryText)?.id;

    _resolveVehicle(row, issues);

    final newPrice = row.effectivePrice(primary, factor);
    row.effectiveNewPrice = newPrice;

    final titleNorm = RateText.normalize(row.title);
    final scopeUnknown = row.newBrand || row.newModel;
    ServiceItem? matched;
    var ambiguous = false;

    if (row.forceNew) {
      matched = null;
    } else if (row.linkedServiceId != null) {
      matched = serviceById(row.linkedServiceId!);
    } else {
      final code = row.code?.trim() ?? '';
      if (code.isNotEmpty) {
        final byCode = _codeIndex[code.toLowerCase()] ?? const <ServiceItem>[];
        if (byCode.length == 1) {
          matched = byCode.first;
          final sim = RateText.tokenSimilarity(titleNorm, _serviceNorm[matched.id!] ?? '');
          if (sim < 0.5) {
            ambiguous = true;
            issues.add('کد «$code» متعلق به «${matched.name}» است ولی نام‌ها فرق دارند');
          }
        }
      }
      if (matched == null && !scopeUnknown) {
        final cands = services
            .where((s) =>
                _serviceNorm[s.id!] == titleNorm && s.brandId == row.brandId && s.modelId == row.modelId)
            .toList();
        if (cands.length == 1) {
          matched = cands.first;
        } else if (cands.length > 1) {
          ambiguous = true;
          issues.add('چند خدمت با همین نام و خودرو در بانک وجود دارد');
        } else {
          ServiceItem? best;
          var bestSim = 0.0;
          for (final s in services) {
            if (s.brandId != row.brandId || s.modelId != row.modelId) continue;
            final sim = RateText.tokenSimilarity(titleNorm, _serviceNorm[s.id!] ?? '');
            if (sim > bestSim) {
              bestSim = sim;
              best = s;
            }
          }
          if (best != null && bestSim >= 0.75) {
            ambiguous = true;
            issues.add('شبیه خدمت «${best.name}» است؛ تطبیق را مشخص کنید');
          }
        }
      }
      if (matched != null && !scopeUnknown && (matched.brandId != row.brandId || matched.modelId != row.modelId)) {
        issues.add('برند/مدل ردیف با خدمت موجود «${matched.name}» (${scopeLabel(matched)}) فرق دارد');
      }
    }

    final noPrice = newPrice == null;
    if (noPrice) issues.add('قیمت اصلی («${primary.label}») برای این ردیف وجود ندارد');
    if (matched != null && newPrice != null && matched.price > 0) {
      final ratio = newPrice / matched.price;
      if (ratio > 3 || ratio < 1 / 3) {
        issues.add(
            'تغییر قیمت غیرعادی: از ${RateText.formatNumber(matched.price)} به ${RateText.formatNumber(newPrice)}');
      }
    }

    row.matched = matched;
    row.issues = issues;

    if (noPrice || ambiguous) {
      row.status = RateMatchStatus.uncertain;
    } else if (issues.isNotEmpty && !row.userConfirmed) {
      row.status = RateMatchStatus.uncertain;
    } else if (matched == null) {
      row.status = RateMatchStatus.newService;
    } else if ((newPrice! - matched.price).abs() < 0.5) {
      row.status = RateMatchStatus.unchanged;
    } else {
      row.status = RateMatchStatus.priceChanged;
    }
  }

  void _resolveVehicle(ExtractedRateRow row, List<String> issues) {
    final brandT = row.brandText?.trim() ?? '';
    final modelT = row.modelText?.trim() ?? '';
    final vehT = row.vehicleText?.trim() ?? '';
    if (brandT.isEmpty && modelT.isEmpty && vehT.isNotEmpty) {
      _splitCombined(row, vehT, issues);
    }
    final b = row.brandText?.trim() ?? '';
    final m = row.modelText?.trim() ?? '';
    if (b.isNotEmpty) {
      final hit = _brandByNorm[RateText.normalize(b)];
      if (hit != null) {
        row.brandId = hit.id;
      } else {
        row.newBrand = true;
      }
    }
    if (m.isNotEmpty) {
      if (b.isEmpty) {
        issues.add('مدل «$m» بدون برند مشخص شده است');
      } else if (row.brandId != null) {
        final mm = _modelsNormByBrand[row.brandId!]?[RateText.normalize(m)];
        if (mm != null) {
          row.modelId = mm.id;
        } else {
          row.newModel = true;
        }
      } else {
        row.newModel = true;
      }
    }
  }

  void _splitCombined(ExtractedRateRow row, String text, List<String> issues) {
    final tokens = text.split(RegExp(r'\s+'));
    for (var k = tokens.length; k >= 1; k--) {
      final prefix = tokens.take(k).join(' ');
      final hit = _brandByNorm[RateText.normalize(prefix)];
      if (hit != null) {
        row.brandText = hit.name;
        final rest = tokens.skip(k).join(' ').trim();
        row.modelText = rest.isEmpty ? null : rest;
        row.vehicleText = null;
        return;
      }
    }
    final n = RateText.normalize(text);
    final hits = <(VehicleBrand, VehicleModel)>[];
    for (final b in brands) {
      final mm = _modelsNormByBrand[b.id!]?[n];
      if (mm != null) hits.add((b, mm));
    }
    if (hits.length == 1) {
      row.brandText = hits.first.$1.name;
      row.modelText = hits.first.$2.name;
      row.vehicleText = null;
      return;
    }
    if (hits.length > 1) {
      issues.add('خودرو «$text» با چند برند تطبیق دارد؛ برند را مشخص کنید');
    } else {
      issues.add('خودرو «$text» در بانک برند/مدل پیدا نشد؛ برند و مدل را وارد کنید');
    }
  }
}
