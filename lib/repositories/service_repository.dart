import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/service.dart';

/// وقتی کد خدمت از قبل برای خدمت دیگری (فعال یا حذف‌شده) ثبت شده باشد.
/// هم از بررسی داخل برنامه و هم از قید یکتایی خود دیتابیس پرتاب می‌شود.
class DuplicateServiceCodeException implements Exception {
  final String code;
  const DuplicateServiceCodeException(this.code);

  String get message =>
      'کد «$code» قبلاً برای یک خدمت (فعال یا حذف‌شده) ثبت شده است؛ کد دیگری انتخاب کنید';

  @override
  String toString() => message;
}

/// خطای قابل‌فهم برای کاربر در مدیریت دسته‌بندی‌ها (نام خالی، نام تکرار، بازیابی ناممکن، ...).
class ServiceCategoryException implements Exception {
  final String message;
  const ServiceCategoryException(this.message);

  @override
  String toString() => message;
}

/// نتیجه‌ی حذف یک دسته‌بندی: حذف قطعی (بدون سابقه) یا بایگانی (دارای خدمت).
enum CategoryRemoval { deleted, archived }

class ServiceCategoryRepository {
  final _db = DatabaseHelper.instance;

  /// دسته‌های پیش‌فرض برنامه.
  static const List<String> defaultNames = ['برق خودرو', 'مکانیک', 'جلوبندی'];

  Future<int> insert(ServiceCategory c) async {
    final db = await _db.database;
    return db.insert('service_categories', c.toMap()..remove('id'));
  }

  Future<List<ServiceCategory>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('service_categories', where: 'is_deleted = 0', orderBy: 'name');
    return rows.map((r) => ServiceCategory.fromMap(r)).toList();
  }

  /// کلید علامتِ «دسته‌های پیش‌فرض یک‌بار ساخته شده‌اند» در جدول settings.
  static const String _seedFlagKey = 'service_categories_defaults_seeded';

  /// دسته‌های پیش‌فرض را فقط «یک‌بار در عمر هر دیتابیس» می‌سازد (کل کار در یک تراکنش):
  ///  - اگر علامت قبلاً ثبت شده باشد، هیچ کاری نمی‌کند؛ پس دسته‌ای که کاربر
  ///    حذف، بایگانی یا تغییر نام داده، هرگز دوباره ساخته نمی‌شود.
  ///  - اگر جدول service_categories کاملاً خالی باشد، سه دسته‌ی پیش‌فرض ساخته می‌شوند.
  ///  - اگر حتی یک ردیف وجود داشته باشد (نصب‌های قبلی)، چیزی ساخته نمی‌شود.
  ///  - در هر دو حالت علامت ثبت می‌شود.
  /// هیچ دسته‌ی موجودی تغییر یا حذف نمی‌شود. ستون یا جدول جدیدی لازم نیست.
  Future<void> ensureDefaults() async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final flag = await txn.query('settings', where: 'key = ?', whereArgs: [_seedFlagKey], limit: 1);
      if (flag.isNotEmpty) return;
      final any = await txn.query('service_categories', columns: ['id'], limit: 1);
      if (any.isEmpty) {
        for (final name in defaultNames) {
          await txn.insert('service_categories', {'name': name, 'is_deleted': 0});
        }
      }
      await txn.insert('settings', {'key': _seedFlagKey, 'value': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  // ---------------------------------------------------------------------
  // مدیریت دسته‌بندی‌ها: افزودن، تغییر نام، حذف/بایگانی، بازیابی
  // «بایگانی» همان is_deleted = 1 است؛ ردیف دسته و همه‌ی خدمات و سوابق آن
  // دست‌نخورده می‌ماند و فقط از فهرست‌های عادی پنهان می‌شود.
  // ---------------------------------------------------------------------

  /// آیا در بین دسته‌های «فعال» نامی هم‌ارز [name] هست؟ (ی/ي، ک/ك، نیم‌فاصله و فاصله‌ی اضافی نادیده گرفته می‌شود)
  Future<bool> _activeNameTaken(DatabaseExecutor ex, String name, {int? excludeId}) async {
    final key = ServiceRepository.normalizeName(name).toLowerCase();
    final rows = await ex.query('service_categories', columns: ['id', 'name'], where: 'is_deleted = 0');
    for (final r in rows) {
      if (excludeId != null && (r['id'] as num).toInt() == excludeId) continue;
      if (ServiceRepository.normalizeName((r['name'] as String?) ?? '').toLowerCase() == key) return true;
    }
    return false;
  }

  /// افزودن دسته‌ی جدید. نام خالی یا تکراریِ دسته‌های فعال رد می‌شود
  /// ([ServiceCategoryException]).
  Future<int> add(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const ServiceCategoryException('نام دسته‌بندی نباید خالی باشد');
    final db = await _db.database;
    return db.transaction((txn) async {
      if (await _activeNameTaken(txn, clean)) {
        throw ServiceCategoryException('دسته‌بندی «$clean» از قبل وجود دارد');
      }
      return txn.insert('service_categories', {'name': clean, 'is_deleted': 0});
    });
  }

  /// تغییر نام یک دسته‌ی فعال. فقط ستون name عوض می‌شود؛ خدمات، قیمت‌ها و فاکتورها
  /// و کدهای قبلی خدمات تغییر نمی‌کنند.
  Future<void> rename(int id, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) throw const ServiceCategoryException('نام دسته‌بندی نباید خالی باشد');
    final db = await _db.database;
    await db.transaction((txn) async {
      if (await _activeNameTaken(txn, clean, excludeId: id)) {
        throw ServiceCategoryException('دسته‌بندی «$clean» از قبل وجود دارد');
      }
      await txn.update('service_categories', {'name': clean},
          where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    });
  }

  /// تعداد همه‌ی خدمات وابسته به این دسته، «حتی خدمات حذف‌شده» (is_deleted = 1)؛
  /// وجود هر خدمتی یعنی دسته سابقه دارد.
  Future<int> serviceCount(int categoryId) async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) FROM services WHERE category_id = ?', [categoryId]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// حذف یا بایگانی (با تأیید کاربر در صفحه، قبل از صدا زدن این متد):
  ///  - هیچ خدمتی وابسته نیست: حذف قطعی ردیف دسته.
  ///  - حتی یک خدمت وابسته است: فقط is_deleted = 1 (بایگانی)؛ هیچ ردیف دیگری لمس نمی‌شود.
  /// شمارش و عملیات در یک تراکنش است، پس بین شمارش و حذف خدمتی اضافه نمی‌شود.
  Future<CategoryRemoval> removeOrArchive(int id) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final r = await txn.rawQuery('SELECT COUNT(*) FROM services WHERE category_id = ?', [id]);
      final n = Sqflite.firstIntValue(r) ?? 0;
      if (n == 0) {
        await txn.delete('service_categories', where: 'id = ?', whereArgs: [id]);
        return CategoryRemoval.deleted;
      }
      await txn.update('service_categories', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
      return CategoryRemoval.archived;
    });
  }

  /// دسته‌های بایگانی‌شده.
  Future<List<ServiceCategory>> getArchived() async {
    final db = await _db.database;
    final rows = await db.query('service_categories', where: 'is_deleted = 1', orderBy: 'name');
    return rows.map((r) => ServiceCategory.fromMap(r)).toList();
  }

  /// بازیابی یک دسته‌ی بایگانی‌شده: فقط is_deleted دوباره ۰ می‌شود. اگر هم‌اکنون
  /// دسته‌ی فعالی با همان نام وجود داشته باشد، بازیابی رد می‌شود ([ServiceCategoryException]).
  Future<void> restore(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('service_categories',
          columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw const ServiceCategoryException('این دسته‌بندی پیدا نشد');
      final name = (rows.first['name'] as String?) ?? '';
      if (await _activeNameTaken(txn, name, excludeId: id)) {
        throw ServiceCategoryException(
            'بازیابی ممکن نیست: یک دسته‌بندی فعال با نام «$name» وجود دارد. '
            'ابتدا نام آن را تغییر دهید یا آن را حذف کنید.');
      }
      await txn.update('service_categories', {'is_deleted': 0}, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// آیا این دسته وجود دارد و فعال (بایگانی‌نشده) است؟
  Future<bool> isActive(int id) async {
    final db = await _db.database;
    final rows = await db.query('service_categories',
        columns: ['id'], where: 'id = ? AND is_deleted = 0', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }
}

class ServiceRepository {
  final _db = DatabaseHelper.instance;

  // ---------------------------------------------------------------------
  // کد یکتا
  // ---------------------------------------------------------------------
  // کد خدمت باید در کل جدول یکتا باشد، «شامل خدمات حذف‌شده» (حذف نرم فقط
  // is_deleted را ۱ می‌کند و ردیف می‌ماند؛ پس کد آن هرگز آزاد نمی‌شود).
  // دو لایه: ۱) بررسی داخل همین تراکنش، ۲) قید دیتابیس (index یکتا یا trigger،
  // به migration نسخه‌ی ۱۳ در database_helper نگاه کنید).

  static bool _isDuplicateCodeError(DatabaseException e) =>
      e.isUniqueConstraintError() || e.toString().contains('DUPLICATE_SERVICE_CODE');

  Future<bool> _codeTaken(DatabaseExecutor ex, String code, {int? excludeId}) async {
    final rows = await ex.query('services',
        columns: ['id'],
        where: excludeId == null ? 'code = ?' : 'code = ? AND id != ?',
        whereArgs: excludeId == null ? [code] : [code, excludeId],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// ثبت خدمت جدید. اگر کد تکراری باشد (حتی کدِ یک خدمت حذف‌شده)،
  /// [DuplicateServiceCodeException] پرتاب می‌شود و چیزی ثبت نمی‌شود.
  Future<int> insert(ServiceItem s) async {
    final db = await _db.database;
    final code = s.code.trim();
    try {
      return await db.transaction((txn) async {
        if (await _codeTaken(txn, code)) throw DuplicateServiceCodeException(code);
        final map = s.toMap()
          ..remove('id')
          ..['code'] = code;
        return txn.insert('services', map);
      });
    } on DatabaseException catch (e) {
      if (_isDuplicateCodeError(e)) throw DuplicateServiceCodeException(code);
      rethrow;
    }
  }

  /// ویرایش خدمت. اگر قیمت تغییر کرده باشد، در تاریخچه ثبت می‌شود (سوابق قبلی هرگز
  /// حذف نمی‌شوند). قیمت قبلی از خود دیتابیس خوانده می‌شود، نه از شیء احتمالاً
  /// قدیمیِ صفحه، تا تاریخچه همیشه درست باشد. اگر کد عوض شده و تکراری باشد،
  /// [DuplicateServiceCodeException] پرتاب می‌شود. اگر کد تغییری نکرده، بررسی
  /// تکراری انجام نمی‌شود (ویرایش قیمت و نام یک خدمتِ قدیمی هیچ‌وقت به‌خاطر کد گیر نمی‌کند).
  Future<void> update(ServiceItem oldItem, ServiceItem newItem) async {
    final db = await _db.database;
    final code = newItem.code.trim();
    try {
      await db.transaction((txn) async {
        final cur = await txn.query('services',
            columns: ['code', 'price'], where: 'id = ?', whereArgs: [newItem.id], limit: 1);
        final currentCode = cur.isEmpty ? null : cur.first['code'] as String?;
        final oldPrice = cur.isEmpty ? oldItem.price : (cur.first['price'] as num).toDouble();

        if (currentCode != code && await _codeTaken(txn, code, excludeId: newItem.id)) {
          throw DuplicateServiceCodeException(code);
        }
        // is_deleted عمداً نوشته نمی‌شود: وضعیت حذف فقط با softDelete/softDeleteMany
        // عوض می‌شود. وگرنه ذخیره‌ی یک ویرایشِ قدیمی (که isDeleted پیش‌فرض ۰ دارد)
        // خدمتِ حذف‌شده را بی‌صدا برمی‌گرداند.
        final map = newItem.toMap()
          ..['code'] = code
          ..remove('is_deleted');
        await txn.update('services', map, where: 'id = ?', whereArgs: [newItem.id]);
        if (oldPrice != newItem.price) {
          await txn.insert('service_price_history', {
            'service_id': newItem.id,
            'old_price': oldPrice,
            'new_price': newItem.price,
            'changed_at': DateTime.now().toIso8601String(),
          });
        }
      });
    } on DatabaseException catch (e) {
      if (_isDuplicateCodeError(e)) throw DuplicateServiceCodeException(code);
      rethrow;
    }
  }

  /// حذف نرم تکی: فقط ستون is_deleted همین خدمت ۱ می‌شود. به فاکتورها، اقلام
  /// فاکتور و تاریخچه‌ی قیمت دست نمی‌زند، و کد خدمت همچنان رزرو می‌ماند.
  Future<int> softDelete(int id) async {
    final db = await _db.database;
    return db.update('services', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// حذف نرم گروهی: فقط ستون is_deleted همین خدمات ۱ می‌شود (مثل حذف تکی).
  /// به جدول فاکتورها و اقلام آن‌ها و تاریخچه قیمت دست نمی‌زند.
  /// همه در یک تراکنش انجام می‌شود: یا همه حذف می‌شوند یا هیچ‌کدام.
  Future<int> softDeleteMany(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await _db.database;
    return db.transaction((txn) async {
      var affected = 0;
      const chunkSize = 500;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
        final chunk = ids.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        affected += await txn.rawUpdate(
            'UPDATE services SET is_deleted = 1 WHERE id IN ($placeholders)', chunk);
      }
      return affected;
    });
  }

  Future<ServiceItem?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('services', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ServiceItem.fromMap(rows.first);
  }

  Future<List<ServiceItem>> getAll({bool onlyActive = false}) async {
    final db = await _db.database;
    String where = 'is_deleted = 0';
    if (onlyActive) where += ' AND is_active = 1';
    final rows = await db.query('services', where: where, orderBy: 'name');
    return rows.map((r) => ServiceItem.fromMap(r)).toList();
  }

  Future<List<ServiceItem>> getByCategory(int categoryId) async {
    final db = await _db.database;
    final rows = await db.query('services',
        where: 'category_id = ? AND is_deleted = 0', whereArgs: [categoryId], orderBy: 'name');
    return rows.map((r) => ServiceItem.fromMap(r)).toList();
  }

  /// جستجوی عادی (نام یا کد).
  Future<List<ServiceItem>> search(String q) async {
    final db = await _db.database;
    final like = '%$q%';
    final rows = await db.query('services',
        where: 'is_deleted = 0 AND (name LIKE ? OR code LIKE ?)', whereArgs: [like, like], orderBy: 'name');
    return rows.map((r) => ServiceItem.fromMap(r)).toList();
  }

  /// جستجوی فازی/نزدیک برای جستجوی صوتی خدمات.
  Future<List<ServiceItem>> searchFuzzy(String query) async {
    final db = await _db.database;
    final tokens = query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return [];
    final whereParts = <String>[];
    final args = <String>[];
    for (final t in tokens) {
      whereParts.add('(name LIKE ? OR voice_search_label LIKE ?)');
      args.add('%$t%');
      args.add('%$t%');
    }
    final rows = await db.query('services',
        where: 'is_deleted = 0 AND (${whereParts.join(' AND ')})', whereArgs: args, orderBy: 'name');
    return rows.map((r) => ServiceItem.fromMap(r)).toList();
  }

  /// آیا این کد قبلاً برای هر خدمتی (فعال یا حذف‌شده) ثبت شده است؟
  /// [excludeId]: خود خدمتِ در حال ویرایش.
  Future<bool> codeExists(String code, {int? excludeId}) async {
    final db = await _db.database;
    return _codeTaken(db, code, excludeId: excludeId);
  }

  /// گزارش کدهای تکراریِ قدیمی که از نسخه‌های قبلی در دیتابیس مانده‌اند.
  /// فقط می‌خواند؛ هیچ کدی تغییر نمی‌کند.
  Future<List<Map<String, Object?>>> findDuplicateCodes() async {
    final db = await _db.database;
    return db.rawQuery(
        'SELECT code, COUNT(*) AS cnt FROM services GROUP BY code HAVING COUNT(*) > 1 ORDER BY code');
  }

  // ---------------------------------------------------------------------
  // شماره‌گذاری خودکار کد: سری‌های جداگانه‌ی B (برق خودرو)، M (مکانیک)،
  // J (جلوبندی) و IMP (سایر دسته‌ها). هر سری شماره‌ی جدا دارد.
  // ---------------------------------------------------------------------

  /// سری پیش‌فرض کد خودکار (برای دسته‌هایی که سری اختصاصی ندارند).
  static const String defaultSeriesPrefix = 'IMP-';

  /// قالب نهایی کد: پیشوند + شماره‌ی چهار رقمی، مثل B-0001.
  static String formatAutoCode(String prefix, int n) => '$prefix${n.toString().padLeft(4, '0')}';

  /// نرمال‌سازی نام فقط برای مقایسه (ی/ي، ک/ك، نیم‌فاصله، فاصله‌ی اضافی).
  static String normalizeName(String s) => s
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('\u200c', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// پیشوند سری کد بر اساس نام دسته: جلوبندی = J، مکانیک = M، برق خودرو = B.
  /// هر دسته‌ی دیگر در سری پیش‌فرض IMP می‌ماند.
  static String seriesPrefixForName(String categoryName) {
    final n = normalizeName(categoryName);
    if (n.contains('جلوبندی')) return 'J-';
    if (n.contains('مکانیک')) return 'M-';
    if (n.contains('برق')) return 'B-';
    return defaultSeriesPrefix;
  }

  /// پیشوند سری کد برای یک دسته (فقط می‌خواند).
  Future<String> autoCodePrefixForCategory(int? categoryId) async {
    if (categoryId == null) return defaultSeriesPrefix;
    final db = await _db.database;
    final rows = await db.query('service_categories',
        columns: ['name'], where: 'id = ?', whereArgs: [categoryId], limit: 1);
    if (rows.isEmpty) return defaultSeriesPrefix;
    return seriesPrefixForName((rows.first['name'] as String?) ?? '');
  }

  /// بزرگ‌ترین شماره‌ی موجود در یک سری (مثلاً برای B- همه‌ی کدهای B-0001، B-0002، ...).
  /// خدمات حذف‌شده هم حساب می‌شوند تا هیچ کدی دوباره استفاده نشود. فقط می‌خواند.
  Future<int> maxAutoNumber(String prefix) async {
    final db = await _db.database;
    final rows = await db.rawQuery('SELECT code FROM services WHERE code LIKE ?', ['$prefix%']);
    var maxNum = 0;
    for (final r in rows) {
      final code = (r['code'] as String?) ?? '';
      if (code.length <= prefix.length) continue;
      final n = int.tryParse(code.substring(prefix.length));
      if (n != null && n > maxNum) maxNum = n;
    }
    return maxNum;
  }

  /// کد خودکار بعدی برای یک دسته: B-0001، B-0002، ... (برق خودرو)،
  /// M-0001، ... (مکانیک)، J-0001، ... (جلوبندی)؛ هر سری شماره‌گذاری جدا دارد.
  /// چیزی ذخیره نمی‌کند. اگر کد پیشنهادی به هر دلیل از قبل وجود داشته باشد،
  /// به شماره‌ی بعدی می‌رود.
  Future<String> nextAutoCode({int? categoryId}) async {
    final prefix = await autoCodePrefixForCategory(categoryId);
    var next = (await maxAutoNumber(prefix)) + 1;
    while (await codeExists(formatAutoCode(prefix, next))) {
      next++;
    }
    return formatAutoCode(prefix, next);
  }

  // ---------------------------------------------------------------------
  // تاریخچه‌ی قیمت (فقط خواندن؛ ثبت آن داخل update() انجام می‌شود)
  // ---------------------------------------------------------------------

  Future<List<ServicePriceHistory>> getPriceHistory(int serviceId) async {
    final db = await _db.database;
    final rows = await db.query('service_price_history',
        where: 'service_id = ?', whereArgs: [serviceId], orderBy: 'changed_at DESC');
    return rows.map((r) => ServicePriceHistory.fromMap(r)).toList();
  }

  // ---------------------------------------------------------------------
  // تطبیق خدمات با برند/مدل خودرو
  // ---------------------------------------------------------------------

  /// آیا این خدمت برای خودروی داده‌شده معتبر است؟
  ///  - خدمت اختصاصی یک مدل: فقط برای همان مدل (برای هیچ خودروی دیگر، حتی هم‌برند).
  ///  - خدمت اختصاصی یک برند (بدون مدل): فقط برای خودروهای همان برند.
  ///  - خدمت عمومی (بدون برند و مدل): برای همه.
  static bool matchesVehicle(ServiceItem s, int? brandId, int? modelId) {
    if (s.modelId != null) {
      if (modelId == null || s.modelId != modelId) return false;
      return s.brandId == null || brandId == null || s.brandId == brandId;
    }
    if (s.brandId != null) return brandId != null && s.brandId == brandId;
    return true;
  }

  static int _specificity(ServiceItem s) => (s.brandId != null ? 1 : 0) + (s.modelId != null ? 1 : 0);

  /// خدمات یک دسته برای خودروی انتخاب‌شده. اگر یک خدمت هم‌نام هم نسخه‌ی عمومی و هم
  /// نسخه‌ی اختصاصی داشته باشد، نسخه‌ی دقیق‌تر (مدل، بعد برند، بعد عمومی) نمایش داده می‌شود.
  Future<List<ServiceItem>> getByCategoryAndVehicle(int categoryId, int? brandId, int? modelId) async {
    final db = await _db.database;
    final rows = await db.query('services',
        where: 'category_id = ? AND is_deleted = 0 AND is_active = 1',
        whereArgs: [categoryId],
        orderBy: 'id');
    final all = rows.map((r) => ServiceItem.fromMap(r)).toList();

    final Map<String, ServiceItem> byName = {};
    for (final s in all) {
      if (!matchesVehicle(s, brandId, modelId)) continue;
      final existing = byName[s.name];
      if (existing == null || _specificity(s) > _specificity(existing)) byName[s.name] = s;
    }
    return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
