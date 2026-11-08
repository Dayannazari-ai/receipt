import 'dart:io';
import 'package:excel/excel.dart';
import '../models/service.dart';
import '../repositories/service_group_repository.dart';
import '../repositories/service_repository.dart';
import '../repositories/vehicle_reference_repository.dart';

/// خطای ساختار فایل یا ردیف‌های نامعتبر. پیام برای نمایش مستقیم به کاربر است
/// و هیچ ورودی انجام نمی‌شود.
class ImportStructureException implements Exception {
  final String message;
  const ImportStructureException(this.message);
  @override
  String toString() => message;
}

/// انتخاب صریح کاربر برای مجموعه‌های ناموجودِ فایل.
/// create: ساخت مجموعه‌های جدید. skip: خدمات آن مجموعه‌ها بدون مجموعه وارد شوند.
enum GroupImportChoice { create, skip }

/// یک مجموعه‌ی دیده‌شده در فایل. status: exists | inactive | new
class ImportGroupLine {
  final String name;
  final String status;
  final int rows;
  const ImportGroupLine(this.name, this.status, this.rows);
}

/// نتیجه‌ی تحلیل فایل برای پیش‌نمایش (چیزی ذخیره نمی‌کند).
class ImportPreview {
  final String modeLabel;
  final int total;
  final List<Map<String, dynamic>> sample; // name, brand, model, price, voice, group
  final List<String> newBrands; // برندهایی که هنگام ورود ساخته می‌شوند
  final List<String> newModels; // «برند - مدل»هایی که ساخته می‌شوند
  final List<String> ignoredColumns;
  final bool hasGroupColumn;
  final List<ImportGroupLine> groups;
  final int rowsWithoutGroup;
  const ImportPreview({
    required this.modeLabel,
    required this.total,
    required this.sample,
    required this.newBrands,
    required this.newModels,
    required this.ignoredColumns,
    this.hasGroupColumn = false,
    this.groups = const [],
    this.rowsWithoutGroup = 0,
  });

  int get newGroupCount => groups.where((g) => g.status == 'new').length;
  int get inactiveGroupCount => groups.where((g) => g.status == 'inactive').length;
}

class _Entry {
  final String name;
  final String? brand;
  final String? model;
  final double price;
  final String? voiceLabel;
  final String? group;
  const _Entry(this.name, this.brand, this.model, this.price, this.voiceLabel, {this.group});
}

class _Extracted {
  final List<_Entry> entries = [];
  final Set<String> ignored = {};
  final List<String> errors = [];
  bool anyLong = false;
  bool anyWide = false;
  bool anyGroupColumn = false;
}

class _GroupPlan {
  final List<ImportGroupLine> lines;
  final Map<String, int> activeIdByKey; // فقط مجموعه‌های موجودِ فعال
  const _GroupPlan(this.lines, this.activeIdByKey);
}

class PriceListImportService {
  final _serviceRepo = ServiceRepository();
  final _vehicleRepo = VehicleReferenceRepository();

  // سرستون‌های حالت طولی (بعد از نرمال‌سازی؛ فقط تطبیق دقیق).
  static const Set<String> _serviceHeaders = {'نام خدمت', 'عنوان خدمت'};
  static const Set<String> _brandHeaders = {'برند خودرو', 'برند'};
  static const Set<String> _modelHeaders = {'مدل خودرو', 'مدل'};
  static const Set<String> _priceHeaders = {'قیمت'};
  static const Set<String> _voiceHeaders = {'برچسب جستجوی صوتی'};
  static const Set<String> _groupHeaders = {'مجموعه', 'مجموعه خدمات'};

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

  String _norm(String s) => s
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('\u200c', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  /// کلید مقایسه‌ی سرستون: «(اختیاری)» حذف و متن نرمال می‌شود.
  String _hdrKey(String s) => _norm(s.replaceAll(RegExp(r'\(\s*اختیاری\s*\)'), ''));

  String _asciiDigits(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(r - 0x06F0 + 0x30);
      } else if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(r - 0x0660 + 0x30);
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// قیمت حالت طولی: ارقام فارسی/عربی و جداکننده‌ی هزارگان پذیرفته می‌شود.
  double? _parsePrice(CellValue? cv) {
    final t = _cellText(cv);
    if (t == null) return null;
    final s = _asciiDigits(t).replaceAll(RegExp(r'[,\u066C\u060C\s]'), '');
    final v = double.tryParse(s);
    if (v == null || v.isNaN || v.isInfinite) return null;
    return v;
  }

  (String, String?) _splitHeader(String text) {
    final i = text.indexOf('|');
    if (i < 0) return (text.trim(), null);
    final brand = text.substring(0, i).trim();
    final model = text.substring(i + 1).trim();
    if (brand.isEmpty) return (text.replaceAll('|', '').trim(), null);
    return (brand, model.isEmpty ? null : model);
  }

  // ---------------------------------------------------------------------
  // حالت عریض (برندها در ستون‌ها): منطق قبلی بدون هیچ تغییری
  // ---------------------------------------------------------------------
  List<(String, String?, String?, double)> _wideEntries(Sheet sheet) {
    final entries = <(String, String?, String?, double)>[];
    final header = sheet.row(0);

    int? serviceColIndex;
    for (var i = 0; i < header.length; i++) {
      final text = _cellText(header[i]?.value);
      if (text != null &&
          (text.contains('خدمات') ||
              text.contains('خدمت') ||
              text.contains('تعمیرات') ||
              text.contains('شرح') ||
              text.contains('عنوان'))) {
        serviceColIndex = i;
        break;
      }
    }
    if (serviceColIndex == null) return entries;

    final brandCols = <int, (String, String?)>{};
    for (var i = 0; i < serviceColIndex; i++) {
      final text = _cellText(header[i]?.value);
      if (text != null) brandCols[i] = _splitHeader(text);
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
        entries.add((name, null, null, price));
      } else {
        for (final entry in brandCols.entries) {
          if (row.length <= entry.key) continue;
          final price = _cellNumber(row[entry.key]?.value);
          if (price == null) continue;
          entries.add((name, entry.value.$1, entry.value.$2, price));
        }
      }
    }
    return entries;
  }

  // ---------------------------------------------------------------------
  // تشخیص ساختار از روی سرستون‌ها (برای هر شیت جدا) و خواندن
  // ---------------------------------------------------------------------
  _Extracted _extract(String path) {
    final bytes = File(path).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final out = _Extracted();

    for (final te in excel.tables.entries) {
      final sheetName = te.key;
      final sheet = te.value;
      if (sheet.maxRows == 0) continue;
      final header = sheet.row(0);

      final keys = <String>[];
      var hasPipe = false;
      for (final c in header) {
        final t = _cellText(c?.value);
        if (t != null && t.contains('|')) hasPipe = true;
        keys.add(t == null ? '' : _hdrKey(t));
      }
      List<int> indexesOf(Set<String> names) =>
          [for (var i = 0; i < keys.length; i++) if (names.contains(keys[i])) i];

      final brandI = indexesOf(_brandHeaders);
      final modelI = indexesOf(_modelHeaders);

      // بدون سرستون برند/مدل: مسیر عریض قبلی.
      if (brandI.isEmpty && modelI.isEmpty) {
        final wide = _wideEntries(sheet);
        if (wide.isNotEmpty) out.anyWide = true;
        for (final w in wide) {
          out.entries.add(_Entry(w.$1, w.$2, w.$3, w.$4, null));
        }
        continue;
      }

      // حالت طولی: چهار ستون ضروری و «مجموعه» (اختیاری) باید دقیقاً یک‌بار باشند.
      final serviceI = indexesOf(_serviceHeaders);
      final priceI = indexesOf(_priceHeaders);
      final voiceI = indexesOf(_voiceHeaders);
      final groupI = indexesOf(_groupHeaders);
      final sheetErrors = <String>[];
      if (hasPipe) {
        sheetErrors.add('ساختار مبهم است: هم ستون «برند/مدل» و هم سرستون‌هایی با علامت | وجود دارد');
      }
      void need(List<int> idx, String label) {
        if (idx.isEmpty) {
          sheetErrors.add('ستون «$label» پیدا نشد');
        } else if (idx.length > 1) {
          sheetErrors.add('ستون «$label» بیش از یک‌بار آمده است');
        }
      }

      need(serviceI, 'نام خدمت');
      need(brandI, 'برند خودرو');
      need(modelI, 'مدل خودرو');
      need(priceI, 'قیمت');
      if (voiceI.length > 1) sheetErrors.add('ستون «برچسب جستجوی صوتی» بیش از یک‌بار آمده است');
      if (groupI.length > 1) sheetErrors.add('ستون «مجموعه» بیش از یک‌بار آمده است');
      if (sheetErrors.isNotEmpty) {
        for (final m in sheetErrors) {
          out.errors.add('شیت «$sheetName»: $m');
        }
        continue;
      }

      out.anyLong = true;
      final sI = serviceI.first;
      final bI = brandI.first;
      final mI = modelI.first;
      final pI = priceI.first;
      final vI = voiceI.isEmpty ? null : voiceI.first;
      final gI = groupI.isEmpty ? null : groupI.first;
      final used = <int>{sI, bI, mI, pI};
      if (vI != null) used.add(vI);
      if (gI != null) {
        used.add(gI);
        out.anyGroupColumn = true;
      }
      for (var i = 0; i < header.length; i++) {
        final t = _cellText(header[i]?.value);
        if (t != null && !used.contains(i)) out.ignored.add(t);
      }

      var badRows = 0;
      final badMsgs = <String>[];
      for (var r = 1; r < sheet.maxRows; r++) {
        final row = sheet.row(r);
        CellValue? at(int i) => i < row.length ? row[i]?.value : null;
        final name = _cellText(at(sI));
        final brand = _cellText(at(bI));
        final model = _cellText(at(mI));
        final priceText = _cellText(at(pI));
        final voice = vI == null ? null : _cellText(at(vI));
        final group = gI == null ? null : _cellText(at(gI));
        // ردیف کاملاً خالی نادیده گرفته می‌شود.
        if (name == null &&
            brand == null &&
            model == null &&
            priceText == null &&
            voice == null &&
            group == null) {
          continue;
        }

        final price = _parsePrice(at(pI));
        final reasons = <String>[];
        if (name == null) reasons.add('نام خدمت خالی');
        if (brand == null) reasons.add('برند خالی');
        if (model == null) reasons.add('مدل خالی');
        if (price == null || price <= 0) reasons.add('قیمت نامعتبر');
        if (reasons.isNotEmpty) {
          badRows++;
          if (badMsgs.length < 5) badMsgs.add('ردیف ${r + 1}: ${reasons.join('، ')}');
          continue;
        }
        out.entries.add(_Entry(name!, brand!, model!, price!, voice, group: group));
      }
      if (badRows > 0) {
        out.errors.add('شیت «$sheetName»: $badRows ردیف نامعتبر است');
        for (final m in badMsgs) {
          out.errors.add('• $m');
        }
        if (badRows > badMsgs.length) {
          out.errors.add('• و ${badRows - badMsgs.length} ردیف نامعتبر دیگر');
        }
      }
    }
    return out;
  }

  String _brandLabel(_Entry e) => e.brand == null
      ? 'همه برندها'
      : (e.model == null ? e.brand! : '${e.brand} - ${e.model}');

  /// برندها و مدل‌هایی که هنگام ورود ساخته می‌شوند (فقط می‌خواند).
  Future<({List<String> brands, List<String> models})> _newVehicleInfo(List<_Entry> entries) async {
    final brands = await _vehicleRepo.getAllBrands();
    final brandIdByKey = <String, int>{for (final b in brands) _norm(b.name): b.id!};
    final modelKeysByBrandId = <int, Set<String>>{};
    final newBrands = <String>[];
    final newModels = <String>[];
    final seenBrand = <String>{};
    final seenPair = <String>{};

    for (final e in entries) {
      final bn = e.brand;
      if (bn == null) continue;
      final bKey = _norm(bn);
      final bId = brandIdByKey[bKey];
      if (bId == null && seenBrand.add(bKey)) newBrands.add(bn);
      final mn = e.model;
      if (mn == null) continue;
      if (!seenPair.add('$bKey|${_norm(mn)}')) continue;
      if (bId == null) {
        newModels.add('$bn - $mn');
        continue;
      }
      var keys = modelKeysByBrandId[bId];
      if (keys == null) {
        final list = await _vehicleRepo.getModelsByBrand(bId);
        keys = {for (final m in list) _norm(m.name)};
        modelKeysByBrandId[bId] = keys;
      }
      if (!keys.contains(_norm(mn))) newModels.add('$bn - $mn');
    }
    return (brands: newBrands, models: newModels);
  }

  /// وضعیت مجموعه‌های فایل نسبت به دسته‌ی مقصد (فقط می‌خواند).
  /// ترتیب: به ترتیب اولین ظهور در فایل. نام نمایشی: اولین نوشتار در فایل.
  Future<_GroupPlan> _planGroups(List<_Entry> entries, int categoryId) async {
    final dbGroups = await ServiceGroupRepository().getByCategory(categoryId);
    final byKey = {for (final g in dbGroups) ServiceGroupRepository.nameKey(g.name): g};
    final order = <String>[];
    final names = <String, String>{};
    final rows = <String, int>{};
    for (final e in entries) {
      final g = e.group;
      if (g == null) continue;
      final k = ServiceGroupRepository.nameKey(g);
      if (!names.containsKey(k)) {
        names[k] = g;
        order.add(k);
      }
      rows[k] = (rows[k] ?? 0) + 1;
    }
    final lines = <ImportGroupLine>[];
    final activeIds = <String, int>{};
    for (final k in order) {
      final ex = byKey[k];
      final status = ex == null ? 'new' : (ex.active ? 'exists' : 'inactive');
      if (ex != null && ex.active) activeIds[k] = ex.id!;
      lines.add(ImportGroupLine(names[k]!, status, rows[k]!));
    }
    return _GroupPlan(lines, activeIds);
  }

  /// تحلیل فایل برای پیش‌نمایش. اگر ساختار مبهم یا ناقص باشد یا ردیف نامعتبر
  /// وجود داشته باشد، [ImportStructureException] پرتاب می‌شود.
  /// اگر فایل ستون «مجموعه» دارد، [categoryId] لازم است.
  Future<ImportPreview> analyzeFile(String path, {int? categoryId}) async {
    final x = _extract(path);
    if (x.errors.isNotEmpty) throw ImportStructureException(x.errors.join('\n'));
    if (x.entries.isEmpty) {
      throw const ImportStructureException(
          'هیچ ردیف معتبری در فایل پیدا نشد. فایل طولی باید سرستون‌های «نام خدمت»، «برند خودرو»، «مدل خودرو» و «قیمت» داشته باشد؛ '
          'فایل عریض باید در سرستون نام خدمت یکی از کلمه‌های «خدمات»، «خدمت»، «تعمیرات» یا «شرح» را داشته باشد.');
    }
    final vi = await _newVehicleInfo(x.entries);

    var groups = <ImportGroupLine>[];
    var withoutGroup = 0;
    if (x.anyGroupColumn) {
      if (categoryId == null) {
        throw const ImportStructureException('برای تشخیص مجموعه‌ها، ابتدا دسته‌بندی مقصد را انتخاب کنید');
      }
      groups = (await _planGroups(x.entries, categoryId)).lines;
      withoutGroup = x.entries.where((e) => e.group == null).length;
    }

    final mode = x.anyLong && x.anyWide
        ? 'ترکیبی (شیت‌هایی با ساختار متفاوت)'
        : (x.anyLong ? 'طولی (هر ردیف: یک خدمت برای یک برند و مدل)' : 'عریض (برندها در ستون‌ها)');
    final sample = x.entries
        .take(15)
        .map((e) => <String, dynamic>{
              'name': e.name,
              'brand': e.brand ?? 'همه برندها',
              'model': e.model,
              'price': e.price,
              'voice': e.voiceLabel,
              'group': e.group,
            })
        .toList();
    return ImportPreview(
      modeLabel: mode,
      total: x.entries.length,
      sample: sample,
      newBrands: vi.brands,
      newModels: vi.models,
      ignoredColumns: x.ignored.toList(),
      hasGroupColumn: x.anyGroupColumn,
      groups: groups,
      rowsWithoutGroup: withoutGroup,
    );
  }

  // نگه‌داشته شده برای سازگاری با فراخوانی‌های قبلی.
  Future<List<Map<String, dynamic>>> previewFile(String path) async {
    final x = _extract(path);
    if (x.errors.isNotEmpty) throw ImportStructureException(x.errors.join('\n'));
    return x.entries
        .take(15)
        .map((e) => <String, dynamic>{'name': e.name, 'brand': _brandLabel(e), 'price': e.price})
        .toList();
  }

  Future<int> countEntries(String path) async => _extract(path).entries.length;

  Future<({int services, int brands, int groups})> importFromFile({
    required String path,
    required int categoryId,
    GroupImportChoice? groupChoice,
  }) async {
    // قبل از شروع، فعال بودن دسته‌ی مقصد را از دیتابیس چک می‌کنیم (ممکن است بعد از باز شدن صفحه بایگانی شده باشد).
    if (!await ServiceCategoryRepository().isActive(categoryId)) {
      throw const ServiceCategoryException(
          'دسته‌بندی مقصد وجود ندارد یا بایگانی شده است؛ یک دسته‌بندی فعال انتخاب کنید');
    }
    // همان اعتبارسنجی پیش‌نمایش؛ اگر ساختار یا ردیفی ایراد داشته باشد، هیچ چیزی وارد نمی‌شود.
    final x = _extract(path);
    if (x.errors.isNotEmpty) throw ImportStructureException(x.errors.join('\n'));
    final entries = x.entries;
    if (entries.isEmpty) {
      throw StateError(
          'هیچ ردیف معتبری در فایل پیدا نشد. مطمئن شوید سرستون یکی از سلول‌های سطر اول شامل کلمه‌ی «خدمات»، «خدمت»، «تعمیرات» یا «شرح» است.');
    }

    // مجموعه‌ها: قبل از هر نوشتن بررسی می‌شود.
    final gp = await _planGroups(entries, categoryId);
    final inactive = [for (final l in gp.lines) if (l.status == 'inactive') l.name];
    if (inactive.isNotEmpty) {
      throw ImportStructureException(
          'مجموعه‌ی غیرفعال در فایل: ${inactive.join('، ')}. ابتدا آن را فعال کنید یا نام را در فایل عوض کنید. هیچ چیزی وارد نشد.');
    }
    final hasNew = gp.lines.any((l) => l.status == 'new');
    if (hasNew && groupChoice == null) {
      throw const ImportStructureException(
          'برای مجموعه‌های جدید یکی از «ساخت مجموعه‌های جدید» یا «ورود بدون مجموعه» را انتخاب کنید. هیچ چیزی وارد نشد.');
    }
    final groupIdByKey = Map<String, int>.from(gp.activeIdByKey);
    var groupsCreated = 0;
    if (hasNew && groupChoice == GroupImportChoice.create) {
      final groupRepo = ServiceGroupRepository();
      for (final l in gp.lines) {
        if (l.status != 'new') continue;
        final id = await groupRepo.add(categoryId, l.name);
        groupIdByKey[ServiceGroupRepository.nameKey(l.name)] = id;
        groupsCreated++;
      }
    }

    final existingBrands = await _vehicleRepo.getAllBrands();
    final Map<String, int> brandIdByName = {
      for (final b in existingBrands) _norm(b.name): b.id!
    };
    final Map<int, Map<String, int>> modelIdByBrand = {};
    int brandsAdded = 0;

    Future<Map<String, int>> modelsOf(int brandId) async {
      final cached = modelIdByBrand[brandId];
      if (cached != null) return cached;
      final list = await _vehicleRepo.getModelsByBrand(brandId);
      final map = <String, int>{for (final m in list) _norm(m.name): m.id!};
      modelIdByBrand[brandId] = map;
      return map;
    }

    final codePrefix = await _serviceRepo.autoCodePrefixForCategory(categoryId);
    var codeNumber = (await _serviceRepo.maxAutoNumber(codePrefix)) + 1;
    int servicesAdded = 0;

    for (final entry in entries) {
      final name = entry.name;
      final brandName = entry.brand;
      final modelName = entry.model;
      final price = entry.price;
      int? brandId;
      int? modelId;

      if (brandName != null) {
        final bKey = _norm(brandName);
        if (!brandIdByName.containsKey(bKey)) {
          final id = await _vehicleRepo.insertBrand(brandName);
          brandIdByName[bKey] = id;
          brandsAdded++;
        }
        brandId = brandIdByName[bKey];

        if (modelName != null && brandId != null) {
          final models = await modelsOf(brandId);
          final mKey = _norm(modelName);
          var mid = models[mKey];
          if (mid == null) {
            mid = await _vehicleRepo.insertModel(brandId, modelName);
            models[mKey] = mid;
          }
          modelId = mid;
        }
      }

      var code = ServiceRepository.formatAutoCode(codePrefix, codeNumber);
      while (await _serviceRepo.codeExists(code)) {
        codeNumber++;
        code = ServiceRepository.formatAutoCode(codePrefix, codeNumber);
      }
      codeNumber++;

      final g = entry.group;
      final groupId = g == null ? null : groupIdByKey[ServiceGroupRepository.nameKey(g)];

      await _serviceRepo.insert(ServiceItem(
        name: name,
        code: code,
        categoryId: categoryId,
        brandId: brandId,
        modelId: modelId,
        serviceGroupId: groupId,
        price: price,
        notes: 'وارد‌شده از فایل نرخ‌نامه',
        voiceSearchLabel: entry.voiceLabel,
      ));
      servicesAdded++;
    }

    return (services: servicesAdded, brands: brandsAdded, groups: groupsCreated);
  }
}
