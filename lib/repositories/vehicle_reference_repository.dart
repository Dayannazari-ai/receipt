import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/vehicle_reference.dart';

class VehicleReferenceRepository {
  final _db = DatabaseHelper.instance;

  Future<List<VehicleBrand>> getAllBrands() async {
    final db = await _db.database;
    final rows = await db.query('vehicle_brands', where: 'is_deleted = 0', orderBy: 'name');
    return rows.map((r) => VehicleBrand.fromMap(r)).toList();
  }

  Future<void> updateBrand(int id, String name) async {
    final db = await _db.database;
    await db.update('vehicle_brands', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// بررسی می‌کند آیا این برند در جایی (مدل‌ها یا خدمات) استفاده شده است.
  Future<bool> isBrandInUse(int brandId) async {
    final db = await _db.database;
    final modelsCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM vehicle_models WHERE brand_id = ?', [brandId])) ??
        0;
    final servicesCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM services WHERE brand_id = ?', [brandId])) ??
        0;
    return modelsCount > 0 || servicesCount > 0;
  }

  /// اگر برند جایی استفاده نشده، کاملاً حذف می‌شود؛ در غیر این صورت فقط
  /// حذف منطقی (Soft Delete) می‌شود تا سوابق قبلی خراب نشوند.
  Future<void> deleteBrand(int id) async {
    final db = await _db.database;
    final inUse = await isBrandInUse(id);
    if (inUse) {
      await db.update('vehicle_brands', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
    } else {
      await db.delete('vehicle_brands', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<int> insertBrand(String name) async {
    final db = await _db.database;
    return db.insert('vehicle_brands', {'name': name});
  }

  Future<List<VehicleModel>> getModelsByBrand(int brandId) async {
    final db = await _db.database;
    final rows =
        await db.query('vehicle_models', where: 'brand_id = ?', whereArgs: [brandId], orderBy: 'name');
    return rows.map((r) => VehicleModel.fromMap(r)).toList();
  }

  Future<int> insertModel(int brandId, String name) async {
    final db = await _db.database;
    return db.insert('vehicle_models', {'brand_id': brandId, 'name': name});
  }

  /// در صورت خالی بودن جدول، برندهای متداول را (برگرفته از نرخ‌نامه اتحادیه) اضافه می‌کند.
  Future<void> ensureDefaults() async {
    final existing = await getAllBrands();
    if (existing.isNotEmpty) return;
    final defaults = <String, List<String>>{
      'پژو': ['206', '405', 'پارس', 'پارس ELX'],
      'سمند': ['سمند', 'دنا', 'دنا EF7'],
      'پراید': ['پراید', 'تیبا', 'ساینا', 'کوییک'],
      'رنو': ['ال90', 'مگان', 'ساندرو'],
      'سایپا': ['ریو'],
    };
    for (final entry in defaults.entries) {
      final brandId = await insertBrand(entry.key);
      for (final model in entry.value) {
        await insertModel(brandId, model);
      }
    }
  }
}
