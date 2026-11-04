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

  /// هر دسته‌ی پیش‌فرض «مستقل از بقیه» ساخته می‌شود: اگر یکی موجود باشد، دسته‌های
  /// دیگری که نیستند باز هم ساخته می‌شوند.
  ///
  /// یک دسته‌ی پیش‌فرض ساخته نمی‌شود اگر:
  ///  - دسته‌ای با همان نام (با نرمال‌سازی ی/ي، ک/ك، نیم‌فاصله و فاصله‌ی اضافی) وجود دارد، یا
  ///  - دسته‌ای هم‌سری با آن وجود دارد (مثلاً دسته‌ی «برق» برای «برق خودرو»)، تا دسته‌ی تکراری ساخته نشود.
  /// دسته‌هایی که قبلاً «حذف منطقی» شده‌اند هم موجود حساب می‌شوند؛ پس دسته‌ای که
  /// کاربر عمداً حذف کرده با هر بار باز شدن برنامه دوباره ساخته نمی‌شود.
  /// هیچ دسته‌ی موجودی تغییر یا حذف نمی‌شود. کل کار داخل یک تراکنش است.
  Future<void> ensureDefaults() async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('service_categories', columns: ['name']);
      final names = <String>{};
      final series = <String>{};
      for (final r in rows) {
        final name = (r['name'] as String?) ?? '';
        names.add(ServiceRepository.normalizeName(name));
        series.add(ServiceRepository.seriesPrefixForName(name));
      }
      for (final name in defaultNames) {
        final key = ServiceRepository.normalizeName(name);
        final prefix = ServiceRepository.seriesPrefixForName(name);
        final present = names.contains(key) ||
            (prefix != ServiceRepository.defaultSeriesPrefix && series.contains(prefix));
        if (present) continue;
        await txn.insert('service_categories', {'name': name, 'is_deleted': 0});
        names.add(key);
        series.add(prefix);
      }
    });
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
