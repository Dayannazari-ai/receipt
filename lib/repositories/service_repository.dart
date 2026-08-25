import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/service.dart';

class ServiceCategoryRepository {
  final _db = DatabaseHelper.instance;

  Future<int> insert(ServiceCategory c) async {
    final db = await _db.database;
    return db.insert('service_categories', c.toMap()..remove('id'));
  }

  Future<List<ServiceCategory>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('service_categories', where: 'is_deleted = 0', orderBy: 'name');
    return rows.map((r) => ServiceCategory.fromMap(r)).toList();
  }

  Future<void> ensureDefaults() async {
    final existing = await getAll();
    if (existing.isNotEmpty) return;
    for (final name in ['برق خودرو', 'مکانیک', 'جلوبندی']) {
      await insert(ServiceCategory(name: name));
    }
  }
}

class ServiceRepository {
  final _db = DatabaseHelper.instance;

  Future<int> insert(ServiceItem s) async {
    final db = await _db.database;
    return db.insert('services', s.toMap()..remove('id'));
  }

  /// ویرایش خدمت. اگر قیمت تغییر کرده باشد، در تاریخچه ثبت می‌شود.
  Future<void> update(ServiceItem oldItem, ServiceItem newItem) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('services', newItem.toMap(), where: 'id = ?', whereArgs: [newItem.id]);
      if (oldItem.price != newItem.price) {
        await txn.insert(
            'service_price_history',
            {
              'service_id': newItem.id,
              'old_price': oldItem.price,
              'new_price': newItem.price,
              'changed_at': DateTime.now().toIso8601String(),
            });
      }
    });
  }

  Future<int> softDelete(int id) async {
    final db = await _db.database;
    return db.update('services', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
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

  Future<List<ServiceItem>> search(String q) async {
    final db = await _db.database;
    final like = '%$q%';
    final rows = await db.query('services',
        where: 'is_deleted = 0 AND (name LIKE ? OR code LIKE ?)', whereArgs: [like, like], orderBy: 'name');
    return rows.map((r) => ServiceItem.fromMap(r)).toList();
  }

  Future<bool> codeExists(String code, {int? excludeId}) async {
    final db = await _db.database;
    final rows = await db.query('services',
        where: excludeId == null ? 'code = ?' : 'code = ? AND id != ?',
        whereArgs: excludeId == null ? [code] : [code, excludeId]);
    return rows.isNotEmpty;
  }

  Future<List<ServicePriceHistory>> getPriceHistory(int serviceId) async {
    final db = await _db.database;
    final rows = await db.query('service_price_history',
        where: 'service_id = ?', whereArgs: [serviceId], orderBy: 'changed_at DESC');
    return rows.map((r) => ServicePriceHistory.fromMap(r)).toList();
  }

  /// یافتن خدمت با در نظر گرفتن برند/مدل خودروی انتخاب‌شده (در صورت وجود قیمت اختصاصی)
  Future<List<ServiceItem>> getByCategoryAndVehicle(
      int categoryId, int? brandId, int? modelId) async {
    final db = await _db.database;
    final rows = await db.query('services',
        where: 'category_id = ? AND is_deleted = 0 AND is_active = 1', whereArgs: [categoryId]);
    final all = rows.map((r) => ServiceItem.fromMap(r)).toList();

    // گروه‌بندی بر اساس نام: اگر نسخه‌ی مخصوص برند/مدل موجود باشد، همان انتخاب شود
    final Map<String, ServiceItem> byName = {};
    for (final s in all) {
      final matchesVehicle =
          (s.brandId == null) || (s.brandId == brandId && (s.modelId == null || s.modelId == modelId));
      if (!matchesVehicle) continue;
      final existing = byName[s.name];
      if (existing == null) {
        byName[s.name] = s;
      } else {
        // اولویت با نسخه‌ای که دقیق‌تر با برند/مدل مطابقت دارد
        final existingScore = (existing.brandId != null ? 1 : 0) + (existing.modelId != null ? 1 : 0);
        final newScore = (s.brandId != null ? 1 : 0) + (s.modelId != null ? 1 : 0);
        if (newScore > existingScore) byName[s.name] = s;
      }
    }
    return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
