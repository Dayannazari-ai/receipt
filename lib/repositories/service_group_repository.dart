import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/service.dart';
import 'service_repository.dart';

/// نتیجه‌ی حذف یک مجموعه: حذف قطعی (بدون خدمت) یا غیرفعال‌شدن (دارای خدمت).
enum GroupRemoval { deleted, deactivated }

class ServiceGroupRepository {
  final _db = DatabaseHelper.instance;

  /// کلید مقایسه‌ی نام: ی/ي، ک/ك، نیم‌فاصله، فاصله‌ی اضافی، حروف کوچک.
  static String nameKey(String name) => ServiceRepository.normalizeName(name).toLowerCase();

  static String _dupMessage(String name) =>
      'مجموعه «$name» در این دسته‌بندی از قبل وجود دارد (ممکن است غیرفعال باشد)';

  Future<bool> _keyTaken(DatabaseExecutor ex, int categoryId, String key, {int? excludeId}) async {
    final rows = await ex.query('service_groups',
        columns: ['id'],
        where: excludeId == null ? 'category_id = ? AND name_key = ?' : 'category_id = ? AND name_key = ? AND id != ?',
        whereArgs: excludeId == null ? [categoryId, key] : [categoryId, key, excludeId],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// مجموعه‌های یک دسته، به ترتیب نمایش. پیش‌فرض: فعال و غیرفعال.
  Future<List<ServiceGroup>> getByCategory(int categoryId, {bool onlyActive = false}) async {
    final db = await _db.database;
    final rows = await db.query('service_groups',
        where: onlyActive ? 'category_id = ? AND is_active = 1' : 'category_id = ?',
        whereArgs: [categoryId],
        orderBy: 'sort_order, id');
    return rows.map((r) => ServiceGroup.fromMap(r)).toList();
  }

  Future<List<ServiceGroup>> getAll({bool onlyActive = false}) async {
    final db = await _db.database;
    final rows = await db.query('service_groups',
        where: onlyActive ? 'is_active = 1' : null, orderBy: 'category_id, sort_order, id');
    return rows.map((r) => ServiceGroup.fromMap(r)).toList();
  }

  Future<ServiceGroup?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('service_groups', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ServiceGroup.fromMap(rows.first);
  }

  /// افزودن مجموعه‌ی جدید به یک دسته‌ی فعال. نام خالی یا تکراری (حتی با مجموعه‌ی غیرفعال) رد می‌شود.
  Future<int> add(int categoryId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const ServiceCategoryException('نام مجموعه نباید خالی باشد');
    final key = nameKey(clean);
    final db = await _db.database;
    try {
      return await db.transaction((txn) async {
        final cat = await txn.query('service_categories',
            columns: ['id'], where: 'id = ? AND is_deleted = 0', whereArgs: [categoryId], limit: 1);
        if (cat.isEmpty) throw const ServiceCategoryException('دسته‌بندی پیدا نشد یا بایگانی شده است');
        if (await _keyTaken(txn, categoryId, key)) throw ServiceCategoryException(_dupMessage(clean));
        final maxRow = await txn.rawQuery(
            'SELECT COALESCE(MAX(sort_order), 0) FROM service_groups WHERE category_id = ?', [categoryId]);
        final next = (Sqflite.firstIntValue(maxRow) ?? 0) + 1;
        return txn.insert('service_groups', {
          'category_id': categoryId,
          'name': clean,
          'name_key': key,
          'sort_order': next,
          'is_active': 1,
        });
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw ServiceCategoryException(_dupMessage(clean));
      rethrow;
    }
  }

  /// تغییر نام. فقط name و name_key عوض می‌شود؛ خدمات و دسته دست‌نخورده می‌مانند.
  Future<void> rename(int id, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) throw const ServiceCategoryException('نام مجموعه نباید خالی باشد');
    final key = nameKey(clean);
    final db = await _db.database;
    try {
      await db.transaction((txn) async {
        final rows = await txn.query('service_groups',
            columns: ['category_id'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) throw const ServiceCategoryException('این مجموعه پیدا نشد');
        final categoryId = (rows.first['category_id'] as num).toInt();
        if (await _keyTaken(txn, categoryId, key, excludeId: id)) {
          throw ServiceCategoryException(_dupMessage(clean));
        }
        await txn.update('service_groups', {'name': clean, 'name_key': key}, where: 'id = ?', whereArgs: [id]);
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw ServiceCategoryException(_dupMessage(clean));
      rethrow;
    }
  }

  /// جابه‌جایی ترتیب نمایش یک مجموعه داخل دسته‌ی خودش (بالا یا پایین).
  Future<void> move(int id, {required bool up}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final row = await txn.query('service_groups',
          columns: ['category_id'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (row.isEmpty) return;
      final categoryId = (row.first['category_id'] as num).toInt();
      final rows = await txn.query('service_groups',
          columns: ['id'], where: 'category_id = ?', whereArgs: [categoryId], orderBy: 'sort_order, id');
      final ids = rows.map((r) => (r['id'] as num).toInt()).toList();
      final i = ids.indexOf(id);
      final j = up ? i - 1 : i + 1;
      if (i < 0 || j < 0 || j >= ids.length) return;
      final tmp = ids[i];
      ids[i] = ids[j];
      ids[j] = tmp;
      for (var k = 0; k < ids.length; k++) {
        await txn.update('service_groups', {'sort_order': k}, where: 'id = ?', whereArgs: [ids[k]]);
      }
    });
  }

  /// فعال/غیرفعال‌کردن. به خدمات و فاکتورها دست نمی‌زند.
  Future<void> setActive(int id, bool active) async {
    final db = await _db.database;
    await db.update('service_groups', {'is_active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// تعداد همه‌ی خدمات این مجموعه، حتی خدمات حذف‌شده.
  Future<int> serviceCount(int id) async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) FROM services WHERE service_group_id = ?', [id]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// بدون خدمت: حذف قطعی. با حتی یک خدمت (فعال یا حذف‌شده): فقط غیرفعال.
  Future<GroupRemoval> removeOrDeactivate(int id) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final r = await txn.rawQuery('SELECT COUNT(*) FROM services WHERE service_group_id = ?', [id]);
      final n = Sqflite.firstIntValue(r) ?? 0;
      if (n == 0) {
        await txn.delete('service_groups', where: 'id = ?', whereArgs: [id]);
        return GroupRemoval.deleted;
      }
      await txn.update('service_groups', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
      return GroupRemoval.deactivated;
    });
  }

  /// کنترل مجموعه‌ی یک خدمت هنگام ثبت/ویرایش، داخل همان تراکنش.
  /// - null مجاز است (خدمت بدون مجموعه).
  /// - مجموعه باید وجود داشته باشد و متعلق به همان دسته‌ی خدمت باشد.
  /// - مجموعه‌ی غیرفعال فقط وقتی مجاز است که خدمت از قبل همان را داشته باشد ([currentGroupId]).
  static Future<void> validateForService(DatabaseExecutor ex, int? groupId, int categoryId,
      {int? currentGroupId}) async {
    if (groupId == null) return;
    final rows = await ex.query('service_groups',
        columns: ['category_id', 'is_active', 'name'], where: 'id = ?', whereArgs: [groupId], limit: 1);
    if (rows.isEmpty) throw const ServiceCategoryException('مجموعه‌ی انتخاب‌شده پیدا نشد');
    final name = (rows.first['name'] as String?) ?? '';
    if ((rows.first['category_id'] as num).toInt() != categoryId) {
      throw ServiceCategoryException('مجموعه‌ی «$name» متعلق به این دسته‌بندی نیست');
    }
    final active = ((rows.first['is_active'] as num?)?.toInt() ?? 1) == 1;
    if (!active && groupId != currentGroupId) {
      throw ServiceCategoryException('مجموعه‌ی «$name» غیرفعال است؛ ابتدا آن را فعال کنید');
    }
  }
}
