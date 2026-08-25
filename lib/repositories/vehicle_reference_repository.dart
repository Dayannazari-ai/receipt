import '../database/database_helper.dart';
import '../models/vehicle_reference.dart';

class VehicleReferenceRepository {
  final _db = DatabaseHelper.instance;

  Future<List<VehicleBrand>> getAllBrands() async {
    final db = await _db.database;
    final rows = await db.query('vehicle_brands', orderBy: 'name');
    return rows.map((r) => VehicleBrand.fromMap(r)).toList();
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
