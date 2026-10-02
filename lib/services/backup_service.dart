import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/app_settings.dart';
import '../models/backup_models.dart';
import '../models/invoice_layout_settings.dart';
import '../repositories/invoice_repository.dart';
import 'invoice_layout_storage.dart';

/// نگاشت شناسه‌ی قدیمی (داخل فایل Backup) به شناسه‌ی جدید/موجود در دیتابیس
/// مقصد، برای برندها و مدل‌های خودرو.
class _RefMaps {
  final Map<int, int> brands = {};
  final Map<int, int> models = {};
}

/// سرویس پشتیبان‌گیری و بازیابی تفکیکی.
///
/// هر بخش (مشتریان، محصولات، خدمات، فاکتورها، تنظیمات) به‌صورت مستقل
/// Export/Import می‌شود و «کامل» همه را یکجا دارد. فرمت فایل JSON است؛
/// پسوند فقط برای تشخیص سریع نوع است، تشخیص واقعی همیشه از فیلد
/// backupType داخل خود فایل خوانده می‌شود.
///
/// دو حالت Restore وجود دارد:
/// - merge: افزودن به اطلاعات فعلی، با تشخیص رکورد تکراری بر اساس کلید
///   منطقی هر نوع (نه فقط id)، و Mapping شناسه‌های قدیمی به جدید تا روابط
///   (برند→مدل، مشتری→خودرو→فاکتور→ردیف) بعد از Import صحیح بمانند.
/// - replace: حذف اطلاعات فعلی همان بخش و جایگزینی کامل با Backup. در این
///   حالت شناسه‌های اصلی رکوردها حفظ می‌شوند تا ارجاع‌های موجود (اقلام
///   فاکتور، حرکت‌های موجودی و ...) سالم بمانند، و بررسی کلید خارجی تا
///   پایان تراکنش به تعویق می‌افتد.
///
/// تنظیمات (نوع settings): مقدار تنظیمات، قالب فاکتور و عکس مهر بازنویسی
/// می‌شوند و شماره کارت/شبایی که قبلاً نیست اضافه می‌شود؛ هیچ داده‌ی دیگری
/// تغییر نمی‌کند. رمز عبور برنامه هرگز جزو Backup نیست (فقط کلیدهای
/// شناخته‌شده‌ی AppSettings ذخیره می‌شوند).
class BackupService {
  final _db = DatabaseHelper.instance;

  // ==================== Export ====================

  String _fileNameFor(BackupType type) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}';
    final time = '${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
    final prefix = {
      BackupType.customers: 'Customers',
      BackupType.products: 'Products',
      BackupType.services: 'Services',
      BackupType.invoices: 'Invoices',
      BackupType.settings: 'Settings',
      BackupType.full: 'Full',
    }[type]!;
    return '${prefix}_${date}_$time.${type.fileExtension}';
  }

  Future<File> _writeEnvelopeToFile(BackupEnvelope envelope, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonEncode(envelope.toJson()));
    return file;
  }

  Future<List<Map<String, Object?>>> _queryByIds(DatabaseExecutor db, String table, Set<int> ids) async {
    if (ids.isEmpty) return [];
    final list = ids.toList();
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < list.length; i += 500) {
      final end = i + 500 > list.length ? list.length : i + 500;
      final chunk = list.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      out.addAll(await db.query(table, where: 'id IN ($placeholders)', whereArgs: chunk));
    }
    return out;
  }

  /// برندها و مدل‌هایی که توسط رکوردهای داده‌شده (خودرو یا خدمت) ارجاع
  /// شده‌اند، تا در Restore روی دستگاه دیگر بتوان رابطه را با نام بازسازی کرد.
  Future<Map<String, List<Map<String, Object?>>>> _referencedBrandsAndModels(
      DatabaseExecutor db, Iterable<Map<String, Object?>> rows) async {
    final brandIds = <int>{};
    final modelIds = <int>{};
    for (final r in rows) {
      final b = r['brand_id'];
      final m = r['model_id'];
      if (b is int) brandIds.add(b);
      if (m is int) modelIds.add(m);
    }
    final models = await _queryByIds(db, 'vehicle_models', modelIds);
    for (final m in models) {
      final b = m['brand_id'];
      if (b is int) brandIds.add(b);
    }
    final brands = await _queryByIds(db, 'vehicle_brands', brandIds);
    return {'vehicle_brands': brands, 'vehicle_models': models};
  }

  /// فقط کلیدهای شناخته‌شده‌ی AppSettings (بدون مسیر عکس مهر). هر کلید دیگری
  /// که در جدول settings باشد (مثلاً مربوط به رمز عبور) عمداً ذخیره نمی‌شود.
  Future<Map<String, String>> _readAppSettingsMap(DatabaseExecutor db) async {
    final allowed = AppSettings().toKeyValueMap().keys.toSet()..remove('stamp_image_path');
    final rows = await db.query('settings');
    final map = <String, String>{};
    for (final r in rows) {
      final k = r['key'] as String;
      if (allowed.contains(k)) map[k] = (r['value'] as String?) ?? '';
    }
    return map;
  }

  /// محتوای فایل عکس مهر/امضا (در صورت وجود) به‌صورت base64، تا روی دستگاه
  /// دیگر هم قابل بازیابی باشد.
  Future<Map<String, String>?> _readStampImage(DatabaseExecutor db) async {
    try {
      final rows = await db.query('settings', where: 'key = ?', whereArgs: ['stamp_image_path'], limit: 1);
      if (rows.isEmpty) return null;
      final path = (rows.first['value'] as String?)?.trim() ?? '';
      if (path.isEmpty) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return {'fileName': p.basename(path), 'base64': base64Encode(bytes)};
    } catch (_) {
      return null;
    }
  }

  /// داده‌های بخش «تنظیمات»: مقادیر تنظیمات، حساب‌های پرداخت، قالب فاکتور
  /// (که در shared_preferences است) و عکس مهر.
  Future<Map<String, dynamic>> _collectSettingsData(DatabaseExecutor db) async {
    final data = <String, dynamic>{};
    data['app_settings'] = await _readAppSettingsMap(db);
    data['payment_accounts'] = await db.query('payment_accounts');
    final layout = await InvoiceLayoutStorage.load();
    data['invoice_layout'] = layout.toJson();
    final stamp = await _readStampImage(db);
    if (stamp != null) data['stamp_image'] = stamp;
    return data;
  }

  Map<String, int> _settingsCounts(Map<String, dynamic> d) => {
        'app_settings': (d['app_settings'] as Map).length,
        'payment_accounts': (d['payment_accounts'] as List).length,
        'invoice_layout': d['invoice_layout'] == null ? 0 : 1,
        'stamp_image': d.containsKey('stamp_image') ? 1 : 0,
      };

  /// بکاپ مشتریان، به‌همراه خودروهای وابسته به آن‌ها (طبق رابطه‌ی
  /// مشتری←چند خودرو) و برند/مدل‌هایی که این خودروها به آن‌ها اشاره می‌کنند.
  Future<File> exportCustomers() async {
    final db = await _db.database;
    final customers = await db.query('customers');
    final vehicles = await db.query('vehicles');
    final refs = await _referencedBrandsAndModels(db, vehicles);

    final envelope = BackupEnvelope(
      backupType: BackupType.customers,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {
        'customers': customers.length,
        'vehicles': vehicles.length,
        'vehicle_brands': refs['vehicle_brands']!.length,
        'vehicle_models': refs['vehicle_models']!.length,
      },
      data: {
        'customers': customers,
        'vehicles': vehicles,
        'vehicle_brands': refs['vehicle_brands'],
        'vehicle_models': refs['vehicle_models'],
      },
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.customers));
  }

  /// بکاپ محصولات. طبق تصمیم قطعی: stock_movements همراه نمی‌شود؛ فقط
  /// موجودی فعلی (stock) و اطلاعات اصلی محصول.
  Future<File> exportProducts() async {
    final db = await _db.database;
    final products = await db.query('products');

    final envelope = BackupEnvelope(
      backupType: BackupType.products,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {'products': products.length},
      data: {'products': products},
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.products));
  }

  /// بکاپ خدمات، به‌همراه دسته‌بندی‌ها، سوابق قیمت و برند/مدل‌های ارجاع‌شده.
  Future<File> exportServices() async {
    final db = await _db.database;
    final services = await db.query('services');
    final categories = await db.query('service_categories');
    final priceHistory = await db.query('service_price_history');
    final refs = await _referencedBrandsAndModels(db, services);

    final envelope = BackupEnvelope(
      backupType: BackupType.services,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {
        'services': services.length,
        'service_categories': categories.length,
        'service_price_history': priceHistory.length,
        'vehicle_brands': refs['vehicle_brands']!.length,
        'vehicle_models': refs['vehicle_models']!.length,
      },
      data: {
        'services': services,
        'service_categories': categories,
        'service_price_history': priceHistory,
        'vehicle_brands': refs['vehicle_brands'],
        'vehicle_models': refs['vehicle_models'],
      },
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.services));
  }

  /// بکاپ فاکتورها = invoices + invoice_items + side_costs، به‌همراه یک کپی
  /// حداقلی از مشتریان/خودروهای مرتبط (و برند/مدل آن خودروها) تا در Restore
  /// بتوان رابطه را بازسازی کرد. هزینه‌های جانبی بخش مستقل ندارند.
  Future<File> exportInvoices() async {
    final db = await _db.database;
    final invoices = await db.query('invoices');
    final items = await db.query('invoice_items');
    final sideCosts = await db.query('side_costs');

    final customerIds = invoices.map((i) => i['customer_id']).whereType<int>().toSet();
    final vehicleIds = invoices.map((i) => i['vehicle_id']).whereType<int>().toSet();

    final relatedCustomers = await _queryByIds(db, 'customers', customerIds);
    final relatedVehicles = await _queryByIds(db, 'vehicles', vehicleIds);
    final refs = await _referencedBrandsAndModels(db, relatedVehicles);

    final envelope = BackupEnvelope(
      backupType: BackupType.invoices,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {
        'invoices': invoices.length,
        'invoice_items': items.length,
        'side_costs': sideCosts.length,
      },
      data: {
        'invoices': invoices,
        'invoice_items': items,
        'side_costs': sideCosts,
        'related_customers': relatedCustomers,
        'related_vehicles': relatedVehicles,
        'vehicle_brands': refs['vehicle_brands'],
        'vehicle_models': refs['vehicle_models'],
      },
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.invoices));
  }

  /// بکاپ مستقل تنظیمات.
  Future<File> exportSettings() async {
    final db = await _db.database;
    final data = await _collectSettingsData(db);
    final envelope = BackupEnvelope(
      backupType: BackupType.settings,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: _settingsCounts(data),
      data: data,
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.settings));
  }

  /// بکاپ کامل: همه‌ی بخش‌های بالا + همه‌ی برندها و مدل‌ها + تنظیمات.
  Future<File> exportFull() async {
    final db = await _db.database;
    final customers = await db.query('customers');
    final vehicles = await db.query('vehicles');
    final brands = await db.query('vehicle_brands');
    final models = await db.query('vehicle_models');
    final products = await db.query('products');
    final services = await db.query('services');
    final categories = await db.query('service_categories');
    final priceHistory = await db.query('service_price_history');
    final invoices = await db.query('invoices');
    final items = await db.query('invoice_items');
    final sideCosts = await db.query('side_costs');
    final settingsData = await _collectSettingsData(db);

    final counts = <String, int>{
      'customers': customers.length,
      'vehicles': vehicles.length,
      'vehicle_brands': brands.length,
      'vehicle_models': models.length,
      'products': products.length,
      'services': services.length,
      'service_categories': categories.length,
      'service_price_history': priceHistory.length,
      'invoices': invoices.length,
      'invoice_items': items.length,
      'side_costs': sideCosts.length,
    }..addAll(_settingsCounts(settingsData));

    final data = <String, dynamic>{
      'customers': customers,
      'vehicles': vehicles,
      'vehicle_brands': brands,
      'vehicle_models': models,
      'products': products,
      'services': services,
      'service_categories': categories,
      'service_price_history': priceHistory,
      'invoices': invoices,
      'invoice_items': items,
      'side_costs': sideCosts,
    }..addAll(settingsData);

    final envelope = BackupEnvelope(
      backupType: BackupType.full,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: counts,
      data: data,
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.full));
  }

  Future<File> exportByType(BackupType type) {
    switch (type) {
      case BackupType.customers:
        return exportCustomers();
      case BackupType.products:
        return exportProducts();
      case BackupType.services:
        return exportServices();
      case BackupType.invoices:
        return exportInvoices();
      case BackupType.settings:
        return exportSettings();
      case BackupType.full:
        return exportFull();
    }
  }

  Future<void> shareBackup(File backupFile) async {
    await Share.shareXFiles([XFile(backupFile.path)], text: 'فایل پشتیبان اطلاعات');
  }

  Future<void> copyFileTo(File source, String destinationPath) async {
    await source.copy(destinationPath);
  }

  // ==================== خواندن و تشخیص نوع فایل Backup ====================

  Future<BackupEnvelope> readBackupFile(String path) async {
    final file = File(path);
    if (!await file.exists()) throw StateError('فایل یافت نشد');
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('فایل Backup معتبر نیست');
    }
    return BackupEnvelope.fromJson(decoded);
  }

  // ==================== توابع کمکی مشترک Import ====================

  /// تبدیل ایمن یک مقدار به int یا null (برای عبور دادن id از JSON که ممکن
  /// است به‌صورت num دیکد شده باشد).
  int? _asIntOrNull(dynamic v) => v == null ? null : (v as num).toInt();

  List<dynamic> _list(Map<String, dynamic> data, String key) => data[key] as List<dynamic>? ?? [];

  /// insert یک رکورد خام (Map از فایل Backup) در یک جدول و اعمال Mapping روی
  /// ستون‌های ارجاعی مشخص‌شده. اگر [keepId] درست باشد، شناسه‌ی اصلی رکورد
  /// حفظ می‌شود (فقط در Replace، بعد از خالی شدن جدول)؛ وگرنه شناسه‌ی جدید
  /// توسط SQLite ساخته می‌شود.
  Future<int> _insertRaw(
    Transaction txn,
    String table,
    Map<String, dynamic> raw, {
    Map<String, Map<int, int>> fkMappings = const {},
    bool keepId = false,
  }) async {
    final map = Map<String, dynamic>.from(raw);
    if (!keepId) map.remove('id');
    fkMappings.forEach((column, mapping) {
      final oldVal = _asIntOrNull(map[column]);
      if (oldVal != null && mapping.containsKey(oldVal)) {
        map[column] = mapping[oldVal];
      }
    });
    return txn.insert(table, map);
  }

  // ==================== Merge: برندها و مدل‌ها ====================

  /// کلید تشخیص برند: نام. کلید تشخیص مدل: نام داخل همان برند (بعد از
  /// Mapping). اگر برند موجود حذف منطقی شده ولی در Backup فعال است، دوباره
  /// فعال می‌شود تا خودروها/خدماتِ واردشده به برند مخفی وصل نشوند.
  Future<_RefMaps> _mergeBrandsAndModels(
    Transaction txn,
    List<dynamic> rawBrands,
    List<dynamic> rawModels,
    RestoreReport report,
  ) async {
    final maps = _RefMaps();

    for (final rawB in rawBrands) {
      final b = Map<String, dynamic>.from(rawB as Map);
      final oldId = _asIntOrNull(b['id']);
      final name = (b['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;

      final rows = await txn.query('vehicle_brands',
          where: 'TRIM(name) = ?', whereArgs: [name], orderBy: 'is_deleted ASC', limit: 1);
      if (rows.isNotEmpty) {
        final existing = rows.first;
        final existingId = existing['id'] as int;
        final backupDeleted = (_asIntOrNull(b['is_deleted']) ?? 0) == 1;
        if ((existing['is_deleted'] as int? ?? 0) == 1 && !backupDeleted) {
          await txn.update('vehicle_brands', {'is_deleted': 0}, where: 'id = ?', whereArgs: [existingId]);
        }
        if (oldId != null) maps.brands[oldId] = existingId;
        report.brandsMatched++;
      } else {
        final newId = await _insertRaw(txn, 'vehicle_brands', b);
        if (oldId != null) maps.brands[oldId] = newId;
        report.brandsAdded++;
      }
    }

    for (final rawM in rawModels) {
      final m = Map<String, dynamic>.from(rawM as Map);
      final oldId = _asIntOrNull(m['id']);
      final oldBrandId = _asIntOrNull(m['brand_id']);
      final newBrandId = oldBrandId != null ? maps.brands[oldBrandId] : null;
      final name = (m['name'] as String?)?.trim() ?? '';
      if (newBrandId == null || name.isEmpty) {
        report.notes.add('یک مدل خودرو به دلیل نبود برند متناظر نادیده گرفته شد.');
        continue;
      }
      final rows = await txn.query('vehicle_models',
          where: 'brand_id = ? AND TRIM(name) = ?', whereArgs: [newBrandId, name], limit: 1);
      if (rows.isNotEmpty) {
        if (oldId != null) maps.models[oldId] = rows.first['id'] as int;
        report.modelsMatched++;
      } else {
        final newId = await _insertRaw(txn, 'vehicle_models', m, fkMappings: {'brand_id': maps.brands});
        if (oldId != null) maps.models[oldId] = newId;
        report.modelsAdded++;
      }
    }

    return maps;
  }

  // ==================== Merge: مشتریان + خودروها ====================

  /// پیدا کردن خودروی معادل در دیتابیس مقصد. کلید تشخیص: مشتری مقصد + برند
  /// + مدل (بعد از Mapping) + پلاک قدیمی (برای داده‌های قبلی) + توضیحات.
  Future<int?> _findMatchingVehicleId(
      DatabaseExecutor txn, int customerId, Map<String, dynamic> v, _RefMaps refMaps) async {
    final rawBrand = _asIntOrNull(v['brand_id']);
    final rawModel = _asIntOrNull(v['model_id']);
    final brandId = rawBrand == null ? null : (refMaps.brands[rawBrand] ?? rawBrand);
    final modelId = rawModel == null ? null : (refMaps.models[rawModel] ?? rawModel);
    final plate = (v['plate_number'] as String?)?.trim() ?? '';
    final notes = (v['notes'] as String?)?.trim() ?? '';
    final rows = await txn.query(
      'vehicles',
      where: "customer_id = ? AND COALESCE(brand_id, -1) = ? AND COALESCE(model_id, -1) = ? "
          "AND TRIM(COALESCE(plate_number, '')) = ? AND TRIM(COALESCE(notes, '')) = ?",
      whereArgs: [customerId, brandId ?? -1, modelId ?? -1, plate, notes],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Import مشتریان (و خودروهای وابسته) با حالت افزودن (merge). کلید
  /// تشخیص مشتری: شماره موبایل (اگر خالی بود، همیشه رکورد جدید ساخته
  /// می‌شود چون کلید یکتای دیگری نداریم).
  Future<Map<int, int>> _mergeCustomersAndVehicles(
    Transaction txn,
    List<dynamic> rawCustomers,
    List<dynamic> rawVehicles,
    RestoreReport report,
    _RefMaps refMaps,
  ) async {
    final customerIdMap = <int, int>{}; // id قدیمی -> id جدید/موجود

    for (final rawC in rawCustomers) {
      final c = Map<String, dynamic>.from(rawC as Map);
      final oldId = _asIntOrNull(c['id']);
      final mobile = (c['mobile'] as String?)?.trim() ?? '';

      int? matchedId;
      if (mobile.isNotEmpty) {
        final rows = await txn.query('customers', where: 'mobile = ?', whereArgs: [mobile], limit: 1);
        if (rows.isNotEmpty) matchedId = rows.first['id'] as int?;
      }

      if (matchedId != null) {
        if (oldId != null) customerIdMap[oldId] = matchedId;
        report.customersMatched++;
      } else {
        final newId = await _insertRaw(txn, 'customers', c);
        if (oldId != null) customerIdMap[oldId] = newId;
        report.customersAdded++;
      }
    }

    for (final rawV in rawVehicles) {
      final v = Map<String, dynamic>.from(rawV as Map);
      final oldCustomerId = _asIntOrNull(v['customer_id']);
      final newCustomerId = oldCustomerId != null ? customerIdMap[oldCustomerId] : null;
      if (newCustomerId == null) {
        report.notes.add('یک خودرو به دلیل نبود مشتری متناظر، نادیده گرفته شد.');
        continue;
      }
      final matchedVehicleId = await _findMatchingVehicleId(txn, newCustomerId, v, refMaps);
      if (matchedVehicleId != null) {
        report.vehiclesMatched++;
      } else {
        await _insertRaw(txn, 'vehicles', v, fkMappings: {
          'customer_id': customerIdMap,
          'brand_id': refMaps.brands,
          'model_id': refMaps.models,
        });
        report.vehiclesAdded++;
      }
    }

    return customerIdMap;
  }

  /// بعد از merge مشتری/خودرو، یک نگاشت id قدیمیِ خودرو -> id جدید/موجود
  /// می‌سازد؛ لازم برای اتصال صحیح invoices.vehicle_id.
  Future<Map<int, int>> _buildVehicleIdMapAfterMerge(
      Transaction txn, List<dynamic> rawVehicles, Map<int, int> customerIdMap, _RefMaps refMaps) async {
    final map = <int, int>{};
    for (final rawV in rawVehicles) {
      final v = Map<String, dynamic>.from(rawV as Map);
      final oldId = _asIntOrNull(v['id']);
      if (oldId == null) continue;
      final oldCustomerId = _asIntOrNull(v['customer_id']);
      final newCustomerId = oldCustomerId != null ? customerIdMap[oldCustomerId] : null;
      if (newCustomerId == null) continue;
      final matchedId = await _findMatchingVehicleId(txn, newCustomerId, v, refMaps);
      if (matchedId != null) map[oldId] = matchedId;
    }
    return map;
  }

  // ==================== Merge: محصولات ====================

  /// کلید تشخیص: کد کالا (code). خروجی: نگاشت id قدیمی -> id جدید/موجود.
  Future<Map<int, int>> _mergeProducts(Transaction txn, List<dynamic> rawProducts, RestoreReport report) async {
    final productIdMap = <int, int>{};
    for (final rawP in rawProducts) {
      final prod = Map<String, dynamic>.from(rawP as Map);
      final oldId = _asIntOrNull(prod['id']);
      final code = (prod['code'] as String?)?.trim() ?? '';
      int? matchedId;
      if (code.isNotEmpty) {
        final rows = await txn.query('products', where: 'code = ?', whereArgs: [code], limit: 1);
        if (rows.isNotEmpty) matchedId = rows.first['id'] as int?;
      }
      if (matchedId != null) {
        if (oldId != null) productIdMap[oldId] = matchedId;
        report.productsMatched++;
      } else {
        final newId = await _insertRaw(txn, 'products', prod);
        if (oldId != null) productIdMap[oldId] = newId;
        report.productsAdded++;
      }
    }
    return productIdMap;
  }

  // ==================== Merge: خدمات + دسته‌بندی + سوابق قیمت ====================

  /// کلید تشخیص دسته‌بندی: نام. کلید تشخیص خدمت: کد (code).
  /// خروجی: نگاشت id قدیمی -> id جدید/موجود خدمات.
  Future<Map<int, int>> _mergeServices(
    Transaction txn,
    List<dynamic> rawServices,
    List<dynamic> rawCategories,
    List<dynamic> rawPriceHistory,
    RestoreReport report,
    _RefMaps refMaps,
  ) async {
    final categoryIdMap = <int, int>{};
    for (final rawCat in rawCategories) {
      final cat = Map<String, dynamic>.from(rawCat as Map);
      final oldId = _asIntOrNull(cat['id']);
      final name = (cat['name'] as String?)?.trim() ?? '';
      int? matchedId;
      if (name.isNotEmpty) {
        final rows = await txn.query('service_categories', where: 'name = ?', whereArgs: [name], limit: 1);
        if (rows.isNotEmpty) matchedId = rows.first['id'] as int?;
      }
      if (matchedId != null) {
        if (oldId != null) categoryIdMap[oldId] = matchedId;
      } else {
        final newId = await _insertRaw(txn, 'service_categories', cat);
        if (oldId != null) categoryIdMap[oldId] = newId;
      }
    }

    final serviceIdMap = <int, int>{};
    final newlyAddedServiceIds = <int>{}; // id قدیمی خدماتی که تازه اضافه شدند
    for (final rawS in rawServices) {
      final s = Map<String, dynamic>.from(rawS as Map);
      final oldId = _asIntOrNull(s['id']);
      final code = (s['code'] as String?)?.trim() ?? '';
      int? matchedId;
      if (code.isNotEmpty) {
        final rows = await txn.query('services', where: 'code = ?', whereArgs: [code], limit: 1);
        if (rows.isNotEmpty) matchedId = rows.first['id'] as int?;
      }
      if (matchedId != null) {
        if (oldId != null) serviceIdMap[oldId] = matchedId;
        report.servicesMatched++;
      } else {
        final newId = await _insertRaw(txn, 'services', s, fkMappings: {
          'category_id': categoryIdMap,
          'brand_id': refMaps.brands,
          'model_id': refMaps.models,
        });
        if (oldId != null) {
          serviceIdMap[oldId] = newId;
          newlyAddedServiceIds.add(oldId);
        }
        report.servicesAdded++;
      }
    }

    // سوابق قیمت فقط برای خدماتی که تازه اضافه شدند منتقل می‌شود؛ برای
    // خدمات از قبل موجود، سابقه‌ی مقصد دست‌نخورده می‌ماند تا تاریخچه‌ی
    // واقعی دستگاه مقصد با داده‌ی وارداتی قاطی نشود.
    for (final rawH in rawPriceHistory) {
      final h = Map<String, dynamic>.from(rawH as Map);
      final oldServiceId = _asIntOrNull(h['service_id']);
      if (oldServiceId == null || !newlyAddedServiceIds.contains(oldServiceId)) continue;
      await _insertRaw(txn, 'service_price_history', h, fkMappings: {'service_id': serviceIdMap});
    }

    return serviceIdMap;
  }

  // ==================== Merge: فاکتورها ====================

  /// مقایسه‌ی محتوایی دو فاکتور برای تشخیص «همان فاکتور» وقتی شماره یکسان
  /// است ولی backup_uid موجود نیست یا تطابق ندارد.
  bool _invoiceContentEquals(Map<String, dynamic> a, Map<String, Object?> b) {
    return a['type'] == b['type'] &&
        a['issue_date'] == b['issue_date'] &&
        (a['final_amount'] as num?)?.toDouble() == (b['final_amount'] as num?)?.toDouble() &&
        a['payment_type'] == b['payment_type'];
  }

  /// Import فاکتورها با حالت افزودن. اولویت تشخیص «همان فاکتور»: backup_uid
  /// دقیق؛ سپس شماره‌ی فاکتور + مقایسه‌ی محتوا. اگر شماره یکسان اما محتوا
  /// متفاوت بود، فاکتور با شماره‌ی جدید Import می‌شود (هرگز حذف یا نادیده
  /// گرفته نمی‌شود). اقلام و هزینه‌های جانبی فقط برای فاکتورهایی منتقل
  /// می‌شوند که واقعاً تازه درج شده‌اند.
  Future<void> _mergeInvoices(
    Transaction txn,
    List<dynamic> rawInvoices,
    List<dynamic> rawItems,
    List<dynamic> rawSideCosts,
    Map<int, int> customerIdMap,
    Map<int, int> vehicleIdMap,
    Map<int, int> productIdMap,
    Map<int, int> serviceIdMap,
    RestoreReport report,
  ) async {
    final invoiceIdMap = <int, int>{}; // id قدیمی (در فایل) -> id جدید در مقصد
    final freshlyInsertedOldIds = <int>{};

    for (final rawInv in rawInvoices) {
      final inv = Map<String, dynamic>.from(rawInv as Map);
      final oldId = _asIntOrNull(inv['id']);
      final backupUid = (inv['backup_uid'] as String?)?.trim();
      final invoiceNumber = (inv['invoice_number'] as String?)?.trim() ?? '';

      Map<String, Object?>? existing;
      if (backupUid != null && backupUid.isNotEmpty) {
        final rows =
            await txn.query('invoices', where: 'backup_uid = ?', whereArgs: [backupUid], limit: 1);
        if (rows.isNotEmpty) existing = rows.first;
      }
      existing ??= (await txn.query('invoices',
              where: 'invoice_number = ?', whereArgs: [invoiceNumber], limit: 1))
          .firstOrNull;

      if (existing != null) {
        final sameContent = backupUid != null && backupUid.isNotEmpty
            ? true // تطابق backup_uid یعنی قطعاً همان فاکتور است
            : _invoiceContentEquals(inv, existing);

        if (sameContent) {
          // Duplicate واقعی: Import نمی‌شود (و اقلامش هم وارد نمی‌شود).
          report.invoicesSkippedDuplicate++;
          continue;
        } else {
          // شماره یکسان ولی فاکتور متفاوت: با شماره‌ی جدید از سری واقعی
          // Import می‌شود تا هیچ فاکتور واقعی از دست نرود.
          final type = inv['type'] as String? ?? 'electrical';
          final newNumber = await _generateFreshNumberForMerge(txn, type, invoiceNumber);
          inv['invoice_number'] = newNumber;
          inv['backup_uid'] = InvoiceRepository.generateBackupUid();
          report.invoicesRenumbered++;
        }
      }

      final newId = await _insertRaw(txn, 'invoices', inv, fkMappings: {
        'customer_id': customerIdMap,
        'vehicle_id': vehicleIdMap,
      });
      if (oldId != null) {
        invoiceIdMap[oldId] = newId;
        freshlyInsertedOldIds.add(oldId);
      }
      report.invoicesAdded++;
    }

    for (final rawItem in rawItems) {
      final item = Map<String, dynamic>.from(rawItem as Map);
      final oldInvoiceId = _asIntOrNull(item['invoice_id']);
      if (oldInvoiceId == null || !freshlyInsertedOldIds.contains(oldInvoiceId)) continue;
      await _insertRaw(txn, 'invoice_items', item, fkMappings: {
        'invoice_id': invoiceIdMap,
        'product_id': productIdMap,
        'service_id': serviceIdMap,
      });
    }

    for (final rawCost in rawSideCosts) {
      final cost = Map<String, dynamic>.from(rawCost as Map);
      final oldInvoiceId = _asIntOrNull(cost['invoice_id']);
      if (oldInvoiceId == null || !freshlyInsertedOldIds.contains(oldInvoiceId)) continue;
      await _insertRaw(txn, 'side_costs', cost, fkMappings: {'invoice_id': invoiceIdMap});
    }
  }

  Future<String> _generateFreshNumberForMerge(Transaction txn, String type, String fallbackPrefix) async {
    // پیشوند را از خود شماره‌ی قدیمی استخراج می‌کنیم (قسمت قبل از '/')
    final prefix = fallbackPrefix.contains('/') ? fallbackPrefix.split('/').first : 'B';
    final rows = await txn.query('invoices', where: 'invoice_number LIKE ?', whereArgs: ['$prefix/%']);
    int maxNum = 1000;
    for (final row in rows) {
      final numStr = (row['invoice_number'] as String).split('/').last;
      final n = int.tryParse(numStr);
      if (n != null && n > maxNum) maxNum = n;
    }
    return '$prefix/${maxNum + 1}';
  }

  // ==================== تنظیمات (مشترک بین Merge/Replace/نوع settings) ====================

  /// بخش دیتابیسیِ تنظیمات، داخل تراکنش:
  /// - [overwriteValues]: مقادیر تنظیمات (فقط کلیدهای شناخته‌شده) بازنویسی شوند.
  /// - [replaceAccounts]: حساب‌های پرداخت کاملاً جایگزین شوند (وگرنه فقط
  ///   حساب‌هایی که قبلاً نیستند اضافه می‌شوند).
  Future<void> _restoreSettingsPart(
    Transaction txn,
    Map<String, dynamic> data,
    RestoreReport report, {
    required bool overwriteValues,
    required bool replaceAccounts,
  }) async {
    if (overwriteValues) {
      final raw = data['app_settings'];
      if (raw is Map) {
        final allowed = AppSettings().toKeyValueMap().keys.toSet()..remove('stamp_image_path');
        var n = 0;
        for (final entry in raw.entries) {
          final key = entry.key.toString();
          if (!allowed.contains(key)) continue;
          await txn.insert('settings', {'key': key, 'value': entry.value?.toString() ?? ''},
              conflictAlgorithm: ConflictAlgorithm.replace);
          n++;
        }
        if (n > 0) report.settingsRestored = true;
      }
    }

    final rawAccounts = data['payment_accounts'];
    if (rawAccounts is List) {
      if (replaceAccounts) await txn.delete('payment_accounts');
      for (final rawA in rawAccounts) {
        final a = Map<String, dynamic>.from(rawA as Map);
        if (replaceAccounts) {
          await _insertRaw(txn, 'payment_accounts', a, keepId: true);
          report.accountsAdded++;
          continue;
        }
        final title = (a['title'] as String?)?.trim() ?? '';
        final number = (a['number'] as String?)?.trim() ?? '';
        if (title.isEmpty && number.isEmpty) continue;
        final rows = await txn.query('payment_accounts',
            where: 'TRIM(title) = ? AND TRIM(number) = ?', whereArgs: [title, number], limit: 1);
        if (rows.isNotEmpty) {
          report.accountsMatched++;
        } else {
          await _insertRaw(txn, 'payment_accounts', a);
          report.accountsAdded++;
        }
      }
    }
  }

  /// بخش‌های خارج از دیتابیس (قالب فاکتور در shared_preferences و فایل عکس
  /// مهر). بعد از موفقیت تراکنش اجرا می‌شود؛ خطای این بخش‌ها Restore را
  /// ناموفق نمی‌کند و فقط در گزارش می‌آید.
  Future<void> _applySettingsExtras(Map<String, dynamic> data, RestoreReport report) async {
    final layoutRaw = data['invoice_layout'];
    if (layoutRaw is Map) {
      try {
        final ok = await InvoiceLayoutStorage.save(
            InvoiceLayoutSettings.fromJson(Map<String, dynamic>.from(layoutRaw)));
        if (ok) {
          report.layoutRestored = true;
        } else {
          report.notes.add('قالب فاکتور بازیابی نشد.');
        }
      } catch (_) {
        report.notes.add('قالب فاکتور بازیابی نشد.');
      }
    }

    final stamp = data['stamp_image'];
    if (stamp is Map) {
      try {
        final b64 = stamp['base64']?.toString() ?? '';
        if (b64.isNotEmpty) {
          final dir = await getApplicationDocumentsDirectory();
          final ext = p.extension(stamp['fileName']?.toString() ?? '');
          final path = p.join(dir.path, 'stamp_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '.png' : ext}');
          await File(path).writeAsBytes(base64Decode(b64));
          final db = await _db.database;
          await db.insert('settings', {'key': 'stamp_image_path', 'value': path},
              conflictAlgorithm: ConflictAlgorithm.replace);
          report.stampRestored = true;
        }
      } catch (_) {
        report.notes.add('عکس مهر/امضا بازیابی نشد.');
      }
    }
  }

  // ==================== نقطه‌ی ورود اصلی: Restore با حالت Merge ====================

  /// بازیابی یک فایل Backup با حالت «افزودن به اطلاعات فعلی». نوع فایل از
  /// خود envelope.backupType خوانده می‌شود؛ هر نوع فقط جدول‌های مرتبط با
  /// خودش را لمس می‌کند. کل عملیات در یک تراکنش است: یا همه موفق می‌شوند
  /// یا هیچ‌کدام (Transaction-safe).
  ///
  /// نکته: در حالت افزودن برای نوع «کامل»، مقادیر تنظیمات/قالب/مهر تغییر
  /// نمی‌کنند (فقط شماره کارت/شبای جدید اضافه می‌شود). برای نوع «تنظیمات» این
  /// بازنویسی انجام می‌شود.
  Future<RestoreReport> restoreMerge(BackupEnvelope envelope) async {
    final db = await _db.database;
    final report = RestoreReport();
    final data = envelope.data;

    await db.transaction((txn) async {
      switch (envelope.backupType) {
        case BackupType.customers:
          final refMaps = await _mergeBrandsAndModels(
              txn, _list(data, 'vehicle_brands'), _list(data, 'vehicle_models'), report);
          await _mergeCustomersAndVehicles(
              txn, _list(data, 'customers'), _list(data, 'vehicles'), report, refMaps);
          break;

        case BackupType.products:
          await _mergeProducts(txn, _list(data, 'products'), report);
          break;

        case BackupType.services:
          final refMaps = await _mergeBrandsAndModels(
              txn, _list(data, 'vehicle_brands'), _list(data, 'vehicle_models'), report);
          await _mergeServices(
            txn,
            _list(data, 'services'),
            _list(data, 'service_categories'),
            _list(data, 'service_price_history'),
            report,
            refMaps,
          );
          break;

        case BackupType.invoices:
          final refMaps = await _mergeBrandsAndModels(
              txn, _list(data, 'vehicle_brands'), _list(data, 'vehicle_models'), report);
          // ابتدا مشتری/خودروهای همراه (related_*) ادغام می‌شوند تا
          // Mapping برای اتصال فاکتورها آماده باشد.
          final customerIdMap = await _mergeCustomersAndVehicles(
              txn, _list(data, 'related_customers'), _list(data, 'related_vehicles'), report, refMaps);
          final vehicleIdMap = await _buildVehicleIdMapAfterMerge(
              txn, _list(data, 'related_vehicles'), customerIdMap, refMaps);
          await _mergeInvoices(
            txn,
            _list(data, 'invoices'),
            _list(data, 'invoice_items'),
            _list(data, 'side_costs'),
            customerIdMap,
            vehicleIdMap,
            const {},
            const {},
            report,
          );
          break;

        case BackupType.settings:
          await _restoreSettingsPart(txn, data, report, overwriteValues: true, replaceAccounts: false);
          break;

        case BackupType.full:
          final refMaps = await _mergeBrandsAndModels(
              txn, _list(data, 'vehicle_brands'), _list(data, 'vehicle_models'), report);
          final customerIdMap = await _mergeCustomersAndVehicles(
              txn, _list(data, 'customers'), _list(data, 'vehicles'), report, refMaps);
          final vehicleIdMap =
              await _buildVehicleIdMapAfterMerge(txn, _list(data, 'vehicles'), customerIdMap, refMaps);
          final productIdMap = await _mergeProducts(txn, _list(data, 'products'), report);
          final serviceIdMap = await _mergeServices(
            txn,
            _list(data, 'services'),
            _list(data, 'service_categories'),
            _list(data, 'service_price_history'),
            report,
            refMaps,
          );
          await _mergeInvoices(
            txn,
            _list(data, 'invoices'),
            _list(data, 'invoice_items'),
            _list(data, 'side_costs'),
            customerIdMap,
            vehicleIdMap,
            productIdMap,
            serviceIdMap,
            report,
          );
          await _restoreSettingsPart(txn, data, report, overwriteValues: false, replaceAccounts: false);
          report.notes.add('در حالت «افزودن»، تنظیمات برنامه تغییر نکرد.');
          break;
      }
    });

    if (envelope.backupType == BackupType.settings) {
      await _applySettingsExtras(data, report);
    }
    return report;
  }

  // ==================== نقطه‌ی ورود اصلی: Restore با حالت Replace ====================

  /// جایگزینی کامل بخش انتخاب‌شده. قبل از حذف، یک Backup ایمنی از همان
  /// بخش گرفته می‌شود. عملیات در یک تراکنش است: یا کامل انجام می‌شود یا
  /// هیچ تغییری اعمال نمی‌شود. شناسه‌های اصلی رکوردها حفظ می‌شوند و بررسی
  /// کلید خارجی تا لحظه‌ی Commit به تعویق می‌افتد؛ اگر در پایان رکوردی به
  /// داده‌ی ناموجود اشاره کند، کل عملیات لغو می‌شود.
  Future<RestoreReport> restoreReplace(BackupEnvelope envelope) async {
    // Backup ایمنی قبل از جایگزینی، خارج از تراکنش اصلی (نام فایل شامل
    // ساعت است و روی بکاپ‌های قبلی نمی‌نویسد).
    try {
      await exportByType(envelope.backupType);
    } catch (_) {
      // (مرحله‌ی بعدی: شکست بکاپ ایمنی باید Replace را متوقف کند.)
    }

    final db = await _db.database;
    final report = RestoreReport();
    final data = envelope.data;

    try {
      await db.transaction((txn) async {
        await txn.execute('PRAGMA defer_foreign_keys = ON');

        switch (envelope.backupType) {
          case BackupType.customers:
            await txn.delete('vehicles');
            await txn.delete('customers');
            final refMaps = await _mergeBrandsAndModels(
                txn, _list(data, 'vehicle_brands'), _list(data, 'vehicle_models'), report);
            for (final rawC in _list(data, 'customers')) {
              await _insertRaw(txn, 'customers', Map<String, dynamic>.from(rawC as Map), keepId: true);
              report.customersAdded++;
            }
            for (final rawV in _list(data, 'vehicles')) {
              await _insertRaw(txn, 'vehicles', Map<String, dynamic>.from(rawV as Map),
                  keepId: true, fkMappings: {'brand_id': refMaps.brands, 'model_id': refMaps.models});
              report.vehiclesAdded++;
            }
            break;

          case BackupType.products:
            await txn.delete('products');
            for (final rawP in _list(data, 'products')) {
              await _insertRaw(txn, 'products', Map<String, dynamic>.from(rawP as Map), keepId: true);
              report.productsAdded++;
            }
            await _cleanupOrphanStockMovements(txn, report);
            break;

          case BackupType.services:
            await txn.delete('service_price_history');
            await txn.delete('services');
            await txn.delete('service_categories');
            final refMaps = await _mergeBrandsAndModels(
                txn, _list(data, 'vehicle_brands'), _list(data, 'vehicle_models'), report);
            for (final rawCat in _list(data, 'service_categories')) {
              await _insertRaw(txn, 'service_categories', Map<String, dynamic>.from(rawCat as Map), keepId: true);
            }
            for (final rawS in _list(data, 'services')) {
              await _insertRaw(txn, 'services', Map<String, dynamic>.from(rawS as Map),
                  keepId: true, fkMappings: {'brand_id': refMaps.brands, 'model_id': refMaps.models});
              report.servicesAdded++;
            }
            for (final rawH in _list(data, 'service_price_history')) {
              await _insertRaw(txn, 'service_price_history', Map<String, dynamic>.from(rawH as Map));
            }
            break;

          case BackupType.invoices:
            await txn.delete('side_costs');
            await txn.delete('invoice_items');
            await txn.delete('invoices');
            // مشتری/خودروهای همراه در حالت Replace فاکتورها حذف نمی‌شوند؛
            // فقط در صورت نبودشان اضافه می‌شوند.
            final refMaps = await _mergeBrandsAndModels(
                txn, _list(data, 'vehicle_brands'), _list(data, 'vehicle_models'), report);
            final customerIdMap = await _mergeCustomersAndVehicles(
                txn, _list(data, 'related_customers'), _list(data, 'related_vehicles'), report, refMaps);
            final vehicleIdMap = await _buildVehicleIdMapAfterMerge(
                txn, _list(data, 'related_vehicles'), customerIdMap, refMaps);
            for (final rawInv in _list(data, 'invoices')) {
              await _insertRaw(txn, 'invoices', Map<String, dynamic>.from(rawInv as Map),
                  keepId: true, fkMappings: {'customer_id': customerIdMap, 'vehicle_id': vehicleIdMap});
              report.invoicesAdded++;
            }
            for (final rawItem in _list(data, 'invoice_items')) {
              await _insertRaw(txn, 'invoice_items', Map<String, dynamic>.from(rawItem as Map));
            }
            for (final rawCost in _list(data, 'side_costs')) {
              await _insertRaw(txn, 'side_costs', Map<String, dynamic>.from(rawCost as Map));
            }
            break;

          case BackupType.settings:
            await _restoreSettingsPart(txn, data, report, overwriteValues: true, replaceAccounts: false);
            break;

          case BackupType.full:
            // ترتیب حذف: از وابسته‌ترین به مستقل‌ترین.
            await txn.delete('side_costs');
            await txn.delete('invoice_items');
            await txn.delete('invoices');
            await txn.delete('service_price_history');
            await txn.delete('services');
            await txn.delete('service_categories');
            await txn.delete('products');
            await txn.delete('vehicles');
            await txn.delete('customers');
            // برند/مدل فقط وقتی جایگزین می‌شوند که خود Backup آن‌ها را دارد
            // (Backupهای نسخه‌ی ۱ برند/مدل ندارند).
            final hasRefData = data['vehicle_brands'] is List;
            if (hasRefData) {
              await txn.delete('vehicle_models');
              await txn.delete('vehicle_brands');
              for (final rawB in _list(data, 'vehicle_brands')) {
                await _insertRaw(txn, 'vehicle_brands', Map<String, dynamic>.from(rawB as Map), keepId: true);
                report.brandsAdded++;
              }
              for (final rawM in _list(data, 'vehicle_models')) {
                await _insertRaw(txn, 'vehicle_models', Map<String, dynamic>.from(rawM as Map), keepId: true);
                report.modelsAdded++;
              }
            }
            for (final rawC in _list(data, 'customers')) {
              await _insertRaw(txn, 'customers', Map<String, dynamic>.from(rawC as Map), keepId: true);
              report.customersAdded++;
            }
            for (final rawV in _list(data, 'vehicles')) {
              await _insertRaw(txn, 'vehicles', Map<String, dynamic>.from(rawV as Map), keepId: true);
              report.vehiclesAdded++;
            }
            for (final rawP in _list(data, 'products')) {
              await _insertRaw(txn, 'products', Map<String, dynamic>.from(rawP as Map), keepId: true);
              report.productsAdded++;
            }
            for (final rawCat in _list(data, 'service_categories')) {
              await _insertRaw(txn, 'service_categories', Map<String, dynamic>.from(rawCat as Map), keepId: true);
            }
            for (final rawS in _list(data, 'services')) {
              await _insertRaw(txn, 'services', Map<String, dynamic>.from(rawS as Map), keepId: true);
              report.servicesAdded++;
            }
            for (final rawH in _list(data, 'service_price_history')) {
              await _insertRaw(txn, 'service_price_history', Map<String, dynamic>.from(rawH as Map));
            }
            for (final rawInv in _list(data, 'invoices')) {
              await _insertRaw(txn, 'invoices', Map<String, dynamic>.from(rawInv as Map), keepId: true);
              report.invoicesAdded++;
            }
            for (final rawItem in _list(data, 'invoice_items')) {
              await _insertRaw(txn, 'invoice_items', Map<String, dynamic>.from(rawItem as Map));
            }
            for (final rawCost in _list(data, 'side_costs')) {
              await _insertRaw(txn, 'side_costs', Map<String, dynamic>.from(rawCost as Map));
            }
            await _cleanupOrphanStockMovements(txn, report);
            await _restoreSettingsPart(txn, data, report, overwriteValues: true, replaceAccounts: true);
            break;
        }
      });
    } on DatabaseException catch (e) {
      if (e.toString().toUpperCase().contains('FOREIGN KEY')) {
        throw StateError('جایگزینی انجام نشد و هیچ تغییری اعمال نشد: بعضی اطلاعات فعلی '
            '(مثل فاکتورها یا موجودی) به رکوردهایی اشاره می‌کنند که در این Backup نیستند. '
            'حالت «افزودن» را امتحان کنید یا Backup کامل را بازیابی کنید.');
      }
      rethrow;
    }

    if (envelope.backupType == BackupType.full) {
      await _applySettingsExtras(data, report);
    }
    return report;
  }

  /// حرکت‌های موجودی که کالایشان دیگر وجود ندارد (بعد از جایگزینی محصولات).
  Future<void> _cleanupOrphanStockMovements(Transaction txn, RestoreReport report) async {
    final n = await txn.rawDelete('DELETE FROM stock_movements WHERE product_id NOT IN (SELECT id FROM products)');
    if (n > 0) report.notes.add('$n حرکت موجودی مربوط به کالاهای حذف‌شده پاک شد.');
  }

  Future<RestoreReport> restore(BackupEnvelope envelope, RestoreMode mode) {
    // بازیابی تنظیمات حالت افزودن/جایگزینی ندارد و همیشه یک رفتار دارد.
    if (envelope.backupType == BackupType.settings) return restoreMerge(envelope);
    return mode == RestoreMode.merge ? restoreMerge(envelope) : restoreReplace(envelope);
  }

  // ==================== به‌روزرسانی یک Backup موجود ====================

  /// به‌روزرسانی یک فایل Backup موجود با وضعیت فعلی دیتابیس: Export تازه از
  /// وضعیت فعلی و بازنویسی همان فایل؛ createdAt اصلی حفظ و فقط updatedAt
  /// تغییر می‌کند.
  Future<File> updateExistingBackup(String existingFilePath) async {
    final oldEnvelope = await readBackupFile(existingFilePath);
    final fresh = await exportByType(oldEnvelope.backupType);
    final freshContent = await fresh.readAsString();
    final freshJson = jsonDecode(freshContent) as Map<String, dynamic>;
    final freshEnvelope = BackupEnvelope.fromJson(freshJson);

    final merged = BackupEnvelope(
      backupType: freshEnvelope.backupType,
      appDbVersion: freshEnvelope.appDbVersion,
      createdAt: oldEnvelope.createdAt, // تاریخ ایجاد اصلی حفظ می‌شود
      updatedAt: DateTime.now().toIso8601String(),
      recordCounts: freshEnvelope.recordCounts,
      data: freshEnvelope.data,
    );

    await File(existingFilePath).writeAsString(jsonEncode(merged.toJson()));
    // فایل موقت exportByType دیگر لازم نیست.
    try {
      await fresh.delete();
    } catch (_) {}
    return File(existingFilePath);
  }

  // ==================== سازگاری با نسخه‌ی قدیمی (فایل .db کامل) ====================

  Future<File> createLegacyFullDbBackup() async {
    await _db.database;
    final dbPath = await _db.getDbFilePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) throw StateError('فایل دیتابیس یافت نشد');
    final backupDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '${backupDir.path}/receipt_backup_$timestamp.db';
    return dbFile.copy(backupPath);
  }

  Future<void> restoreLegacyFullDbFromPath(String pickedPath) async {
    final dbPath = await _db.getDbFilePath();
    await _db.close();
    final pickedFile = File(pickedPath);
    if (!await pickedFile.exists()) throw StateError('فایل یافت نشد');
    await pickedFile.copy(dbPath);
    await _db.database;
  }
}
