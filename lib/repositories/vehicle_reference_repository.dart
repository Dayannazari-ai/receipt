import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/vehicle_reference.dart';

class VehicleReferenceRepository {
  final _db = DatabaseHelper.instance;

  /// [includeDeleted] فقط برای نمایش نام برند در خودروها/فاکتورهای قدیمی است
  /// که برندشان بعداً حذف منطقی شده؛ در لیست‌های انتخاب هرگز true نشود.
  Future<List<VehicleBrand>> getAllBrands({bool includeDeleted = false}) async {
    final db = await _db.database;
    final rows = includeDeleted
        ? await db.query('vehicle_brands', orderBy: 'name')
        : await db.query('vehicle_brands', where: 'is_deleted = 0', orderBy: 'name');
    return rows.map((r) => VehicleBrand.fromMap(r)).toList();
  }

  Future<void> updateBrand(int id, String name) async {
    final db = await _db.database;
    await db.update('vehicle_brands', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// آیا نام برند (بدون حساسیت به فاصله‌ی اضافی/حروف) قبلاً وجود دارد؟
  Future<bool> brandNameExists(String name, {int? excludeId}) async {
    final target = name.trim().toLowerCase();
    final brands = await getAllBrands();
    return brands.any((b) => b.id != excludeId && b.name.trim().toLowerCase() == target);
  }

  /// بررسی می‌کند آیا این برند در جایی (مدل‌ها، خدمات یا خودروها) استفاده شده است.
  Future<bool> isBrandInUse(int brandId) async {
    final db = await _db.database;
    Future<int> count(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, [brandId])) ?? 0;
    final models = await count('SELECT COUNT(*) FROM vehicle_models WHERE brand_id = ?');
    final services = await count('SELECT COUNT(*) FROM services WHERE brand_id = ?');
    final vehicles = await count('SELECT COUNT(*) FROM vehicles WHERE brand_id = ?');
    return models > 0 || services > 0 || vehicles > 0;
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

  Future<void> updateModel(int id, String name) async {
    final db = await _db.database;
    await db.update('vehicle_models', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// آیا نام مدل، داخل همان برند، قبلاً وجود دارد؟
  Future<bool> modelNameExists(int brandId, String name, {int? excludeId}) async {
    final target = name.trim().toLowerCase();
    final models = await getModelsByBrand(brandId);
    return models.any((m) => m.id != excludeId && m.name.trim().toLowerCase() == target);
  }

  /// آیا این مدل توسط خدمات یا خودروها استفاده شده است؟
  Future<bool> isModelInUse(int modelId) async {
    final db = await _db.database;
    Future<int> count(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, [modelId])) ?? 0;
    final services = await count('SELECT COUNT(*) FROM services WHERE model_id = ?');
    final vehicles = await count('SELECT COUNT(*) FROM vehicles WHERE model_id = ?');
    return services > 0 || vehicles > 0;
  }

  /// جدول vehicle_models ستون is_deleted ندارد و برای حفظ داده‌ها
  /// ساختار دیتابیس را تغییر نمی‌دهیم. بنابراین فقط مدلی که جایی استفاده
  /// نشده حذف می‌شود. خروجی false یعنی مدل در حال استفاده است و حذف نشد.
  Future<bool> deleteModel(int id) async {
    if (await isModelInUse(id)) return false;
    final db = await _db.database;
    await db.delete('vehicle_models', where: 'id = ?', whereArgs: [id]);
    return true;
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
