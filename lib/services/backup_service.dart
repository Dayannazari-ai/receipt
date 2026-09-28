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
}
