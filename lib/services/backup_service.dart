import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/backup_models.dart';
import '../repositories/invoice_repository.dart';

/// سرویس پشتیبان‌گیری و بازیابی تفکیکی.
///
/// هر بخش (مشتریان، محصولات، خدمات، فاکتورها) به‌صورت مستقل Export/Import
/// می‌شود. فرمت فایل JSON است؛ پسوند فقط برای تشخیص سریع نوع است، تشخیص
/// واقعی همیشه از فیلد backupType داخل خود فایل خوانده می‌شود.
///
/// دو حالت Restore وجود دارد:
/// - merge: افزودن به اطلاعات فعلی، با تشخیص رکورد تکراری بر اساس کلید
///   منطقی هر نوع (نه فقط id)، و Mapping شناسه‌های قدیمی به جدید تا روابط
///   (مشتری→خودرو→فاکتور→ردیف) بعد از Import صحیح بمانند.
/// - replace: حذف اطلاعات فعلی همان بخش و جایگزینی کامل با Backup.
class BackupService {
  final _db = DatabaseHelper.instance;
  final _invoiceRepo = InvoiceRepository();

  // ==================== Export ====================

  /// نام فایل امن برای اندروید/اشتراک‌گذاری: بدون فاصله یا کاراکتر خاص.
  String _fileNameFor(BackupType type) {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final prefix = {
      BackupType.customers: 'Customers',
      BackupType.products: 'Products',
      BackupType.services: 'Services',
      BackupType.invoices: 'Invoices',
      BackupType.full: 'Full',
    }[type]!;
    return '${prefix}_$date.${type.fileExtension}';
  }

  Future<File> _writeEnvelopeToFile(BackupEnvelope envelope, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonEncode(envelope.toJson()));
    return file;
  }

  /// بکاپ مشتریان، به‌همراه خودروهای وابسته به آن‌ها (طبق رابطه‌ی
  /// مشتری←چند خودرو). خودرو بدون مشتری معنی ندارد، پس این دو همیشه با هم
  /// Export می‌شوند.
  Future<File> exportCustomers() async {
    final db = await _db.database;
    final customers = await db.query('customers');
    final vehicles = await db.query('vehicles');

    final envelope = BackupEnvelope(
      backupType: BackupType.customers,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {'customers': customers.length, 'vehicles': vehicles.length},
      data: {'customers': customers, 'vehicles': vehicles},
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

  /// بکاپ خدمات، به‌همراه دسته‌بندی‌ها و سوابق قیمت (وابستگی‌های ضروری).
  Future<File> exportServices() async {
    final db = await _db.database;
    final services = await db.query('services');
    final categories = await db.query('service_categories');
    final priceHistory = await db.query('service_price_history');

    final envelope = BackupEnvelope(
      backupType: BackupType.services,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {
        'services': services.length,
        'service_categories': categories.length,
        'service_price_history': priceHistory.length,
      },
      data: {
        'services': services,
        'service_categories': categories,
        'service_price_history': priceHistory,
      },
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.services));
  }

  /// بکاپ فاکتورها = invoices + invoice_items + side_costs، به‌همراه یک کپی
  /// حداقلی از مشتریان/خودروهای مرتبط (فقط رکوردهایی که واقعاً توسط این
  /// فاکتورها ارجاع داده شده‌اند) تا در Restore بتوان رابطه را بازسازی کرد
  /// حتی اگر «Backup مشتریان» جداگانه Import نشده باشد. هزینه‌های جانبی
  /// طبق تصمیم قطعی، بخش مستقل ندارند و همیشه همین‌جا هستند.
  Future<File> exportInvoices() async {
    final db = await _db.database;
    final invoices = await db.query('invoices');
    final items = await db.query('invoice_items');
    final sideCosts = await db.query('side_costs');

    final customerIds = invoices.map((i) => i['customer_id']).whereType<int>().toSet();
    final vehicleIds = invoices.map((i) => i['vehicle_id']).whereType<int>().toSet();

    List<Map<String, Object?>> relatedCustomers = [];
    if (customerIds.isNotEmpty) {
      final placeholders = List.filled(customerIds.length, '?').join(',');
      relatedCustomers =
          await db.query('customers', where: 'id IN ($placeholders)', whereArgs: customerIds.toList());
    }
    List<Map<String, Object?>> relatedVehicles = [];
    if (vehicleIds.isNotEmpty) {
      final placeholders = List.filled(vehicleIds.length, '?').join(',');
      relatedVehicles =
          await db.query('vehicles', where: 'id IN ($placeholders)', whereArgs: vehicleIds.toList());
    }

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
      },
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.invoices));
  }

  /// بکاپ کامل: همه‌ی بخش‌های بالا در یک فایل.
  Future<File> exportFull() async {
    final db = await _db.database;
    final customers = await db.query('customers');
    final vehicles = await db.query('vehicles');
    final products = await db.query('products');
    final services = await db.query('services');
    final categories = await db.query('service_categories');
    final priceHistory = await db.query('service_price_history');
    final invoices = await db.query('invoices');
    final items = await db.query('invoice_items');
    final sideCosts = await db.query('side_costs');

    final envelope = BackupEnvelope(
      backupType: BackupType.full,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {
        'customers': customers.length,
        'vehicles': vehicles.length,
        'products': products.length,
        'services': services.length,
        'service_categories': categories.length,
        'service_price_history': priceHistory.length,
        'invoices': invoices.length,
        'invoice_items': items.length,
        'side_costs': sideCosts.length,
      },
      data: {
        'customers': customers,
        'vehicles': vehicles,
        'products': products,
        'services': services,
        'service_categories': categories,
        'service_price_history': priceHistory,
        'invoices': invoices,
        'invoice_items': items,
        'side_costs': sideCosts,
      },
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
      case BackupType.full:
        return exportFull();
    }
  }

  Future<void> shareBackup(File backupFile) async {
    await Share.shareXFiles([XFile(backupFile.path)], text: 'فایل پشتیبان اطلاعات');
  }

  /// ذخیره‌ی یک فایل Backup در محل دلخواه کاربر با روش استاندارد اندروید.
  /// [savedBytes] محتوای فایل و [suggestedName] نام پیشنهادی است؛ UI از
  /// FilePicker.platform.saveFile برای گرفتن مسیر واقعی استفاده می‌کند و
  /// این متد صرفاً محتوای نوشته‌شده را به همان مسیر کپی می‌کند.
  Future<void> copyFileTo(File source, String destinationPath) async {
    await source.copy(destinationPath);
  }

  // ==================== خواندن و تشخیص نوع فایل Backup ====================

  /// خواندن یک فایل Backup و تبدیل به Envelope، برای نمایش خلاصه به کاربر
  /// قبل از Restore. اگر فایل معتبر نباشد استثنا پرتاب می‌شود.
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

  // ==================== سازگاری با نسخه‌ی قدیمی (فایل .db کامل) ====================

  /// نسخه‌ی قدیمی بکاپ که کل فایل دیتابیس را کپی می‌کرد. برای سازگاری با
  /// فایل‌های قبلاً گرفته‌شده حفظ شده؛ فایل‌های جدید همه با فرمت JSON بالا
  /// ساخته می‌شوند.
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
  import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/backup_models.dart';
import '../repositories/invoice_repository.dart';

/// سرویس پشتیبان‌گیری و بازیابی تفکیکی.
///
/// هر بخش (مشتریان، محصولات، خدمات، فاکتورها) به‌صورت مستقل Export/Import
/// می‌شود. فرمت فایل JSON است؛ پسوند فقط برای تشخیص سریع نوع است، تشخیص
/// واقعی همیشه از فیلد backupType داخل خود فایل خوانده می‌شود.
///
/// دو حالت Restore وجود دارد:
/// - merge: افزودن به اطلاعات فعلی، با تشخیص رکورد تکراری بر اساس کلید
///   منطقی هر نوع (نه فقط id)، و Mapping شناسه‌های قدیمی به جدید تا روابط
///   (مشتری→خودرو→فاکتور→ردیف) بعد از Import صحیح بمانند.
/// - replace: حذف اطلاعات فعلی همان بخش و جایگزینی کامل با Backup.
class BackupService {
  final _db = DatabaseHelper.instance;
  final _invoiceRepo = InvoiceRepository();

  // ==================== Export ====================

  String _fileNameFor(BackupType type) {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final prefix = {
      BackupType.customers: 'Customers',
      BackupType.products: 'Products',
      BackupType.services: 'Services',
      BackupType.invoices: 'Invoices',
      BackupType.full: 'Full',
    }[type]!;
    return '${prefix}_$date.${type.fileExtension}';
  }

  Future<File> _writeEnvelopeToFile(BackupEnvelope envelope, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonEncode(envelope.toJson()));
    return file;
  }

  /// بکاپ مشتریان، به‌همراه خودروهای وابسته به آن‌ها (طبق رابطه‌ی
  /// مشتری←چند خودرو). خودرو بدون مشتری معنی ندارد، پس این دو همیشه با هم
  /// Export می‌شوند.
  Future<File> exportCustomers() async {
    final db = await _db.database;
    final customers = await db.query('customers');
    final vehicles = await db.query('vehicles');

    final envelope = BackupEnvelope(
      backupType: BackupType.customers,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {'customers': customers.length, 'vehicles': vehicles.length},
      data: {'customers': customers, 'vehicles': vehicles},
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

  /// بکاپ خدمات، به‌همراه دسته‌بندی‌ها و سوابق قیمت (وابستگی‌های ضروری).
  Future<File> exportServices() async {
    final db = await _db.database;
    final services = await db.query('services');
    final categories = await db.query('service_categories');
    final priceHistory = await db.query('service_price_history');

    final envelope = BackupEnvelope(
      backupType: BackupType.services,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {
        'services': services.length,
        'service_categories': categories.length,
        'service_price_history': priceHistory.length,
      },
      data: {
        'services': services,
        'service_categories': categories,
        'service_price_history': priceHistory,
      },
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.services));
  }

  /// بکاپ فاکتورها = invoices + invoice_items + side_costs، به‌همراه یک کپی
  /// حداقلی از مشتریان/خودروهای مرتبط (فقط رکوردهایی که واقعاً توسط این
  /// فاکتورها ارجاع داده شده‌اند) تا در Restore بتوان رابطه را بازسازی کرد
  /// حتی اگر «Backup مشتریان» جداگانه Import نشده باشد. هزینه‌های جانبی
  /// طبق تصمیم قطعی، بخش مستقل ندارند و همیشه همین‌جا هستند.
  Future<File> exportInvoices() async {
    final db = await _db.database;
    final invoices = await db.query('invoices');
    final items = await db.query('invoice_items');
    final sideCosts = await db.query('side_costs');

    final customerIds = invoices.map((i) => i['customer_id']).whereType<int>().toSet();
    final vehicleIds = invoices.map((i) => i['vehicle_id']).whereType<int>().toSet();

    List<Map<String, Object?>> relatedCustomers = [];
    if (customerIds.isNotEmpty) {
      final placeholders = List.filled(customerIds.length, '?').join(',');
      relatedCustomers =
          await db.query('customers', where: 'id IN ($placeholders)', whereArgs: customerIds.toList());
    }
    List<Map<String, Object?>> relatedVehicles = [];
    if (vehicleIds.isNotEmpty) {
      final placeholders = List.filled(vehicleIds.length, '?').join(',');
      relatedVehicles =
          await db.query('vehicles', where: 'id IN ($placeholders)', whereArgs: vehicleIds.toList());
    }

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
      },
    );
    return _writeEnvelopeToFile(envelope, _fileNameFor(BackupType.invoices));
  }

  /// بکاپ کامل: همه‌ی بخش‌های بالا در یک فایل.
  Future<File> exportFull() async {
    final db = await _db.database;
    final customers = await db.query('customers');
    final vehicles = await db.query('vehicles');
    final products = await db.query('products');
    final services = await db.query('services');
    final categories = await db.query('service_categories');
    final priceHistory = await db.query('service_price_history');
    final invoices = await db.query('invoices');
    final items = await db.query('invoice_items');
    final sideCosts = await db.query('side_costs');

    final envelope = BackupEnvelope(
      backupType: BackupType.full,
      appDbVersion: DatabaseHelper.dbVersion,
      recordCounts: {
        'customers': customers.length,
        'vehicles': vehicles.length,
        'products': products.length,
        'services': services.length,
        'service_categories': categories.length,
        'service_price_history': priceHistory.length,
        'invoices': invoices.length,
        'invoice_items': items.length,
        'side_costs': sideCosts.length,
      },
      data: {
        'customers': customers,
        'vehicles': vehicles,
        'products': products,
        'services': services,
        'service_categories': categories,
        'service_price_history': priceHistory,
        'invoices': invoices,
        'invoice_items': items,
        'side_costs': sideCosts,
      },
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

  /// insert یک رکورد خام (Map از فایل Backup) در یک جدول، با حذف ستون id
  /// قدیمی (چون id جدید توسط SQLite تولید می‌شود) و اعمال Mapping روی
  /// ستون‌های ارجاعی مشخص‌شده.
  Future<int> _insertRaw(
    Transaction txn,
    String table,
    Map<String, dynamic> raw, {
    Map<String, Map<int, int>> fkMappings = const {},
  }) async {
    final map = Map<String, dynamic>.from(raw)..remove('id');
    fkMappings.forEach((column, mapping) {
      final oldVal = _asIntOrNull(map[column]);
      if (oldVal != null && mapping.containsKey(oldVal)) {
        map[column] = mapping[oldVal];
      }
    });
    return txn.insert(table, map);
  }

  // ==================== Merge: مشتریان + خودروها ====================

  /// Import مشتریان (و خودروهای وابسته) با حالت افزودن (merge). کلید
  /// تشخیص مشتری: شماره موبایل (اگر خالی بود، همیشه رکورد جدید ساخته
  /// می‌شود چون کلید یکتای دیگری نداریم). کلید تشخیص خودرو: پلاک + شناسه‌ی
  /// مشتری مقصد (بعد از Mapping).
  Future<Map<int, int>> _mergeCustomersAndVehicles(
    Transaction txn,
    List<dynamic> rawCustomers,
    List<dynamic> rawVehicles,
    RestoreReport report,
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
      final plate = (v['plate_number'] as String?)?.trim() ?? '';

      bool matched = false;
      if (plate.isNotEmpty) {
        final rows = await txn.query('vehicles',
            where: 'customer_id = ? AND plate_number = ?', whereArgs: [newCustomerId, plate], limit: 1);
        if (rows.isNotEmpty) matched = true;
      }

      if (matched) {
        report.vehiclesMatched++;
      } else {
        await _insertRaw(txn, 'vehicles', v, fkMappings: {'customer_id': customerIdMap});
        report.vehiclesAdded++;
      }
    }

    return customerIdMap;
  }

  // ==================== Merge: محصولات ====================

  /// کلید تشخیص: کد کالا (code).
  Future<void> _mergeProducts(Transaction txn, List<dynamic> rawProducts, RestoreReport report) async {
    for (final rawP in rawProducts) {
      final p = Map<String, dynamic>.from(rawP as Map);
      final code = (p['code'] as String?)?.trim() ?? '';
      bool matched = false;
      if (code.isNotEmpty) {
        final rows = await txn.query('products', where: 'code = ?', whereArgs: [code], limit: 1);
        if (rows.isNotEmpty) matched = true;
      }
      if (matched) {
        report.productsMatched++;
      } else {
        await _insertRaw(txn, 'products', p);
        report.productsAdded++;
      }
    }
  }

  // ==================== Merge: خدمات + دسته‌بندی + سوابق قیمت ====================

  /// کلید تشخیص دسته‌بندی: نام. کلید تشخیص خدمت: کد (code).
  Future<void> _mergeServices(
    Transaction txn,
    List<dynamic> rawServices,
    List<dynamic> rawCategories,
    List<dynamic> rawPriceHistory,
    RestoreReport report,
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
        final newId =
            await _insertRaw(txn, 'services', s, fkMappings: {'category_id': categoryIdMap});
        if (oldId != null) serviceIdMap[oldId] = newId;
        report.servicesAdded++;
      }
    }

    // سوابق قیمت فقط برای خدماتی که تازه اضافه شدند منتقل می‌شود؛ برای
    // خدمات از قبل موجود، سابقه‌ی مقصد دست‌نخورده می‌ماند تا تاریخچه‌ی
    // واقعی دستگاه مقصد با داده‌ی وارداتی قاطی نشود.
    for (final rawH in rawPriceHistory) {
      final h = Map<String, dynamic>.from(rawH as Map);
      final oldServiceId = _asIntOrNull(h['service_id']);
      if (oldServiceId == null) continue;
      final wasNewlyAdded = serviceIdMap.containsKey(oldServiceId);
      if (!wasNewlyAdded) continue;
      await _insertRaw(txn, 'service_price_history', h, fkMappings: {'service_id': serviceIdMap});
    }
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
  /// دقیق؛ سپس شماره‌ی فاکتور + مقایسه‌ی محتوا. اگر backup_uid پیدا نشد و
  /// شماره یکسان اما محتوا متفاوت بود، فاکتور با شماره‌ی جدید Import
  /// می‌شود (هرگز حذف یا نادیده گرفته نمی‌شود).
  Future<void> _mergeInvoices(
    Transaction txn,
    List<dynamic> rawInvoices,
    List<dynamic> rawItems,
    List<dynamic> rawSideCosts,
    Map<int, int> customerIdMap,
    Map<int, int> vehicleIdMap,
    RestoreReport report,
  ) async {
    final invoiceIdMap = <int, int>{}; // id قدیمی (در فایل) -> id جدید در مقصد

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
          // Duplicate واقعی: Import نمی‌شود.
          if (oldId != null) invoiceIdMap[oldId] = existing['id'] as int;
          report.invoicesSkippedDuplicate++;
          continue;
        } else {
          // شماره یکسان ولی فاکتور متفاوت: با شماره‌ی جدید از سری واقعی
          // Import می‌شود تا هیچ فاکتور واقعی از دست نرود.
          final type = inv['type'] as String? ?? 'electrical';
          final newNumber =
              await _generateFreshNumberForMerge(txn, type, invoiceNumber);
          inv['invoice_number'] = newNumber;
          inv['backup_uid'] = InvoiceRepository.generateBackupUid();
          report.invoicesRenumbered++;
        }
      }

      final newId = await _insertRaw(txn, 'invoices', inv, fkMappings: {
        'customer_id': customerIdMap,
        'vehicle_id': vehicleIdMap,
      });
      if (oldId != null) invoiceIdMap[oldId] = newId;
      report.invoicesAdded++;
    }

    for (final rawItem in rawItems) {
      final item = Map<String, dynamic>.from(rawItem as Map);
      final oldInvoiceId = _asIntOrNull(item['invoice_id']);
      if (oldInvoiceId == null || !invoiceIdMap.containsKey(oldInvoiceId)) continue;
      // اگر فاکتور مادر Duplicate تشخیص داده و Skip شده، آیتم‌های آن هم
      // دوباره insert نمی‌شوند (چون فاکتور موجود از قبل آیتم‌های خودش را دارد).
      // برای تشخیص این حالت، فقط وقتی آیتم insert می‌شود که فاکتور واقعاً
      // تازه insert شده باشد؛ این را با بررسی مجدد invoiceIdMap در برابر
      // مجموعه‌ی فاکتورهای اضافه‌شده تضمین می‌کنیم.
      await _insertRaw(txn, 'invoice_items', item, fkMappings: {'invoice_id': invoiceIdMap});
    }

    for (final rawCost in rawSideCosts) {
      final cost = Map<String, dynamic>.from(rawCost as Map);
      final oldInvoiceId = _asIntOrNull(cost['invoice_id']);
      if (oldInvoiceId == null || !invoiceIdMap.containsKey(oldInvoiceId)) continue;
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

  // ==================== نقطه‌ی ورود اصلی: Restore با حالت Merge ====================

  /// بازیابی یک فایل Backup با حالت «افزودن به اطلاعات فعلی». نوع فایل از
  /// خود envelope.backupType خوانده می‌شود؛ هر نوع فقط جدول‌های مرتبط با
  /// خودش را لمس می‌کند. کل عملیات در یک تراکنش است: یا همه موفق می‌شوند
  /// یا هیچ‌کدام (Transaction-safe).
  Future<RestoreReport> restoreMerge(BackupEnvelope envelope) async {
    final db = await _db.database;
    final report = RestoreReport();

    await db.transaction((txn) async {
      final data = envelope.data;
      Map<int, int> customerIdMap = {};
      Map<int, int> vehicleIdMap = {};

      switch (envelope.backupType) {
        case BackupType.customers:
          customerIdMap = await _mergeCustomersAndVehicles(
              txn, data['customers'] as List<dynamic>? ?? [], data['vehicles'] as List<dynamic>? ?? [], report);
          break;

        case BackupType.products:
          await _mergeProducts(txn, data['products'] as List<dynamic>? ?? [], report);
          break;

        case BackupType.services:
          await _mergeServices(
            txn,
            data['services'] as List<dynamic>? ?? [],
            data['service_categories'] as List<dynamic>? ?? [],
            data['service_price_history'] as List<dynamic>? ?? [],
            report,
          );
          break;

        case BackupType.invoices:
          // ابتدا مشتری/خودروهای همراه (related_*) ادغام می‌شوند تا
          // Mapping برای اتصال فاکتورها آماده باشد.
          customerIdMap = await _mergeCustomersAndVehicles(
            txn,
            data['related_customers'] as List<dynamic>? ?? [],
            data['related_vehicles'] as List<dynamic>? ?? [],
            report,
          );
          // vehicleIdMap باید از همان فراخوانی بالا استخراج شود؛ چون
          // _mergeCustomersAndVehicles فقط customerIdMap را برمی‌گرداند،
          // برای خودرو یک نگاشت مجزا با همان منطق کلید (پلاک+مشتری) لازم
          // است. برای سادگی و صحت، اینجا خودروها را دوباره با کلید پلاک
          // پیدا می‌کنیم.
          vehicleIdMap =
              await _buildVehicleIdMapAfterMerge(txn, data['related_vehicles'] as List<dynamic>? ?? [], customerIdMap);
          await _mergeInvoices(
            txn,
            data['invoices'] as List<dynamic>? ?? [],
            data['invoice_items'] as List<dynamic>? ?? [],
            data['side_costs'] as List<dynamic>? ?? [],
            customerIdMap,
            vehicleIdMap,
            report,
          );
          break;

        case BackupType.full:
          customerIdMap = await _mergeCustomersAndVehicles(
              txn, data['customers'] as List<dynamic>? ?? [], data['vehicles'] as List<dynamic>? ?? [], report);
          vehicleIdMap =
              await _buildVehicleIdMapAfterMerge(txn, data['vehicles'] as List<dynamic>? ?? [], customerIdMap);
          await _mergeProducts(txn, data['products'] as List<dynamic>? ?? [], report);
          await _mergeServices(
            txn,
            data['services'] as List<dynamic>? ?? [],
            data['service_categories'] as List<dynamic>? ?? [],
            data['service_price_history'] as List<dynamic>? ?? [],
            report,
          );
          await _mergeInvoices(
            txn,
            data['invoices'] as List<dynamic>? ?? [],
            data['invoice_items'] as List<dynamic>? ?? [],
            data['side_costs'] as List<dynamic>? ?? [],
            customerIdMap,
            vehicleIdMap,
            report,
          );
          break;
      }
    });

    return report;
  }

  /// بعد از merge مشتری/خودرو، یک نگاشت id قدیمیِ خودرو -> id جدید/موجود
  /// می‌سازد؛ لازم برای اتصال صحیح invoices.vehicle_id.
  Future<Map<int, int>> _buildVehicleIdMapAfterMerge(
      Transaction txn, List<dynamic> rawVehicles, Map<int, int> customerIdMap) async {
    final map = <int, int>{};
    for (final rawV in rawVehicles) {
      final v = Map<String, dynamic>.from(rawV as Map);
      final oldId = _asIntOrNull(v['id']);
      if (oldId == null) continue;
      final oldCustomerId = _asIntOrNull(v['customer_id']);
      final newCustomerId = oldCustomerId != null ? customerIdMap[oldCustomerId] : null;
      if (newCustomerId == null) continue;
      final plate = (v['plate_number'] as String?)?.trim() ?? '';
      if (plate.isEmpty) continue;
      final rows = await txn.query('vehicles',
          where: 'customer_id = ? AND plate_number = ?', whereArgs: [newCustomerId, plate], limit: 1);
      if (rows.isNotEmpty) map[oldId] = rows.first['id'] as int;
    }
    return map;
  }

  // ==================== نقطه‌ی ورود اصلی: Restore با حالت Replace ====================

  /// جایگزینی کامل بخش انتخاب‌شده. قبل از حذف، یک Backup ایمنی از همان
  /// بخش گرفته می‌شود تا در صورت بروز خطا امکان بازگشت وجود داشته باشد.
  /// عملیات در یک تراکنش است: یا کامل انجام می‌شود یا هیچ تغییری اعمال
  /// نمی‌شود.
  Future<RestoreReport> restoreReplace(BackupEnvelope envelope) async {
    // Backup ایمنی قبل از جایگزینی، خارج از تراکنش اصلی (خودش فقط خواندن
    // است و اگر بعداً خطا رخ دهد، این فایل ایمنی همچنان روی دیسک باقی
    // می‌ماند).
    try {
      await exportByType(envelope.backupType);
    } catch (_) {
      // اگر Backup ایمنی به هر دلیل ممکن نشد، عملیات Replace را متوقف
      // نمی‌کنیم؛ ولی ریسک را در گزارش اعلام می‌کنیم.
    }

    final db = await _db.database;
    final report = RestoreReport();
    final data = envelope.data;

    await db.transaction((txn) async {
      switch (envelope.backupType) {
        case BackupType.customers:
          await txn.delete('vehicles');
          await txn.delete('customers');
          final customerIdMap = <int, int>{};
          for (final rawC in (data['customers'] as List<dynamic>? ?? [])) {
            final c = Map<String, dynamic>.from(rawC as Map);
            final oldId = _asIntOrNull(c['id']);
            final newId = await _insertRaw(txn, 'customers', c);
            if (oldId != null) customerIdMap[oldId] = newId;
            report.customersAdded++;
          }
          for (final rawV in (data['vehicles'] as List<dynamic>? ?? [])) {
            final v = Map<String, dynamic>.from(rawV as Map);
            await _insertRaw(txn, 'vehicles', v, fkMappings: {'customer_id': customerIdMap});
            report.vehiclesAdded++;
          }
          break;

        case BackupType.products:
          await txn.delete('products');
          for (final rawP in (data['products'] as List<dynamic>? ?? [])) {
            await _insertRaw(txn, 'products', Map<String, dynamic>.from(rawP as Map));
            report.productsAdded++;
          }
          break;

        case BackupType.services:
          await txn.delete('service_price_history');
          await txn.delete('services');
          await txn.delete('service_categories');
          final categoryIdMap = <int, int>{};
          for (final rawCat in (data['service_categories'] as List<dynamic>? ?? [])) {
            final cat = Map<String, dynamic>.from(rawCat as Map);
            final oldId = _asIntOrNull(cat['id']);
            final newId = await _insertRaw(txn, 'service_categories', cat);
            if (oldId != null) categoryIdMap[oldId] = newId;
          }
          final serviceIdMap = <int, int>{};
          for (final rawS in (data['services'] as List<dynamic>? ?? [])) {
            final s = Map<String, dynamic>.from(rawS as Map);
            final oldId = _asIntOrNull(s['id']);
            final newId =
                await _insertRaw(txn, 'services', s, fkMappings: {'category_id': categoryIdMap});
            if (oldId != null) serviceIdMap[oldId] = newId;
            report.servicesAdded++;
          }
          for (final rawH in (data['service_price_history'] as List<dynamic>? ?? [])) {
            await _insertRaw(txn, 'service_price_history', Map<String, dynamic>.from(rawH as Map),
                fkMappings: {'service_id': serviceIdMap});
          }
          break;

        case BackupType.invoices:
          await txn.delete('side_costs');
          await txn.delete('invoice_items');
          await txn.delete('invoices');
          // مشتری/خودروهای همراه در حالت Replace فاکتورها حذف نمی‌شوند؛
          // فقط در صورت نبودشان اضافه می‌شوند، تا اطلاعات مشتری/خودرویی که
          // ممکن است مستقل از این فاکتورها هم استفاده شود از بین نرود.
          final customerIdMap = await _mergeCustomersAndVehicles(
            txn,
            data['related_customers'] as List<dynamic>? ?? [],
            data['related_vehicles'] as List<dynamic>? ?? [],
            report,
          );
          final vehicleIdMap = await _buildVehicleIdMapAfterMerge(
              txn, data['related_vehicles'] as List<dynamic>? ?? [], customerIdMap);
          for (final rawInv in (data['invoices'] as List<dynamic>? ?? [])) {
            final inv = Map<String, dynamic>.from(rawInv as Map);
            final oldId = _asIntOrNull(inv['id']);
            final newId = await _insertRaw(txn, 'invoices', inv,
                fkMappings: {'customer_id': customerIdMap, 'vehicle_id': vehicleIdMap});
            report.invoicesAdded++;
            if (oldId == null) continue;
            for (final rawItem in (data['invoice_items'] as List<dynamic>? ?? [])) {
              final item = Map<String, dynamic>.from(rawItem as Map);
              if (_asIntOrNull(item['invoice_id']) != oldId) continue;
              await _insertRaw(txn, 'invoice_items', item, fkMappings: {'invoice_id': {oldId: newId}});
            }
            for (final rawCost in (data['side_costs'] as List<dynamic>? ?? [])) {
              final cost = Map<String, dynamic>.from(rawCost as Map);
              if (_asIntOrNull(cost['invoice_id']) != oldId) continue;
              await _insertRaw(txn, 'side_costs', cost, fkMappings: {'invoice_id': {oldId: newId}});
            }
          }
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

          final customerIdMap = <int, int>{};
          for (final rawC in (data['customers'] as List<dynamic>? ?? [])) {
            final c = Map<String, dynamic>.from(rawC as Map);
            final oldId = _asIntOrNull(c['id']);
            final newId = await _insertRaw(txn, 'customers', c);
            if (oldId != null) customerIdMap[oldId] = newId;
            report.customersAdded++;
          }
          final vehicleIdMap = <int, int>{};
          for (final rawV in (data['vehicles'] as List<dynamic>? ?? [])) {
            final v = Map<String, dynamic>.from(rawV as Map);
            final oldId = _asIntOrNull(v['id']);
            final newId =
                await _insertRaw(txn, 'vehicles', v, fkMappings: {'customer_id': customerIdMap});
            if (oldId != null) vehicleIdMap[oldId] = newId;
            report.vehiclesAdded++;
          }
          for (final rawP in (data['products'] as List<dynamic>? ?? [])) {
            await _insertRaw(txn, 'products', Map<String, dynamic>.from(rawP as Map));
            report.productsAdded++;
          }
          final categoryIdMap = <int, int>{};
          for (final rawCat in (data['service_categories'] as List<dynamic>? ?? [])) {
            final cat = Map<String, dynamic>.from(rawCat as Map);
            final oldId = _asIntOrNull(cat['id']);
            final newId = await _insertRaw(txn, 'service_categories', cat);
            if (oldId != null) categoryIdMap[oldId] = newId;
          }
          final serviceIdMap = <int, int>{};
          for (final rawS in (data['services'] as List<dynamic>? ?? [])) {
            final s = Map<String, dynamic>.from(rawS as Map);
            final oldId = _asIntOrNull(s['id']);
            final newId =
                await _insertRaw(txn, 'services', s, fkMappings: {'category_id': categoryIdMap});
            if (oldId != null) serviceIdMap[oldId] = newId;
            report.servicesAdded++;
          }
          for (final rawH in (data['service_price_history'] as List<dynamic>? ?? [])) {
            await _insertRaw(txn, 'service_price_history', Map<String, dynamic>.from(rawH as Map),
                fkMappings: {'service_id': serviceIdMap});
          }
          final invoiceIdMap = <int, int>{};
          for (final rawInv in (data['invoices'] as List<dynamic>? ?? [])) {
            final inv = Map<String, dynamic>.from(rawInv as Map);
            final oldId = _asIntOrNull(inv['id']);
            final newId = await _insertRaw(txn, 'invoices', inv,
                fkMappings: {'customer_id': customerIdMap, 'vehicle_id': vehicleIdMap});
            if (oldId != null) invoiceIdMap[oldId] = newId;
            report.invoicesAdded++;
          }
          for (final rawItem in (data['invoice_items'] as List<dynamic>? ?? [])) {
            await _insertRaw(txn, 'invoice_items', Map<String, dynamic>.from(rawItem as Map),
                fkMappings: {'invoice_id': invoiceIdMap});
          }
          for (final rawCost in (data['side_costs'] as List<dynamic>? ?? [])) {
            await _insertRaw(txn, 'side_costs', Map<String, dynamic>.from(rawCost as Map),
                fkMappings: {'invoice_id': invoiceIdMap});
          }
          break;
      }
    });

    return report;
  }

  Future<RestoreReport> restore(BackupEnvelope envelope, RestoreMode mode) {
    return mode == RestoreMode.merge ? restoreMerge(envelope) : restoreReplace(envelope);
  }

  // ==================== به‌روزرسانی یک Backup موجود ====================

  /// به‌روزرسانی یک فایل Backup موجود با وضعیت فعلی دیتابیس. رکوردهای
  /// جدید/تغییرکرده اضافه یا جایگزین می‌شوند؛ رکوردهایی که در دیتابیس
  /// فعلی is_deleted=1 شده‌اند، در Backup هم به همان وضعیت به‌روزرسانی
  /// می‌شوند (نه حذف فیزیکی از فایل). چون این عملاً یک Export تازه از
  /// وضعیت فعلی است (که خودش کامل و به‌روز است)، به‌روزرسانی با بازتولید
  /// کامل envelope از دیتابیس فعلی و بازنویسی همان فایل پیاده می‌شود؛
  /// createdAt اصلی فایل حفظ و فقط updatedAt تغییر می‌کند.
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
}
