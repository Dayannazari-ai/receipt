import '../database/database_helper.dart';
import '../models/vehicle.dart';

class VehicleRepository {
  final _db = DatabaseHelper.instance;

  Future<int> insert(Vehicle v) async {
    final db = await _db.database;
    return db.insert('vehicles', v.toMap()..remove('id'));
  }

  Future<int> update(Vehicle v) async {
    final db = await _db.database;
    return db.update('vehicles', v.toMap(), where: 'id = ?', whereArgs: [v.id]);
  }

  /// حذف منطقی؛ فاکتورهای قدیمی که به این خودرو وصل‌اند دست‌نخورده می‌مانند
  /// چون invoices.vehicle_id فقط ارجاع می‌دهد و به‌صورت آبشاری حذف نمی‌شود.
  Future<int> softDelete(int id) async {
    final db = await _db.database;
    return db.update('vehicles', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Vehicle?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('vehicles', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Vehicle.fromMap(rows.first);
  }

  /// همه‌ی خودروهای فعال یک مشتری خاص؛ برای جلوگیری از انتخاب اشتباه
  /// خودروی مشتری دیگر هنگام صدور فاکتور استفاده می‌شود.
  Future<List<Vehicle>> getByCustomer(int customerId) async {
    final db = await _db.database;
    final rows = await db.query('vehicles',
        where: 'customer_id = ? AND is_deleted = 0', whereArgs: [customerId], orderBy: 'created_at DESC');
    return rows.map((r) => Vehicle.fromMap(r)).toList();
  }

  Future<List<Vehicle>> getAll({bool includeDeleted = false}) async {
    final db = await _db.database;
    final rows = includeDeleted
        ? await db.query('vehicles')
        : await db.query('vehicles', where: 'is_deleted = 0');
    return rows.map((r) => Vehicle.fromMap(r)).toList();
  }

  Future<int> count() async {
    final db = await _db.database;
    final rows = await db.query('vehicles', where: 'is_deleted = 0');
    return rows.length;
  }
}
