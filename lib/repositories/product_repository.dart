import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/product.dart';

class ProductRepository {
  final _db = DatabaseHelper.instance;

  Future<int> insert(Product p) async {
    final db = await _db.database;
    return db.insert('products', p.toMap()..remove('id'));
  }

  Future<int> update(Product p) async {
    final db = await _db.database;
    return db.update('products', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  Future<int> softDelete(int id) async {
    final db = await _db.database;
    return db.update('products', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Product?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<List<Product>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('products', where: 'is_deleted = 0', orderBy: 'name');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<List<Product>> search(String q) async {
    final db = await _db.database;
    final like = '%$q%';
    final rows = await db.query('products',
        where: 'is_deleted = 0 AND (name LIKE ? OR code LIKE ?)', whereArgs: [like, like], orderBy: 'name');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<List<Product>> getLowStock() async {
    final db = await _db.database;
    final rows =
        await db.query('products', where: 'is_deleted = 0 AND stock <= min_stock', orderBy: 'stock ASC');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<bool> codeExists(String code, {int? excludeId}) async {
    final db = await _db.database;
    final rows = await db.query('products',
        where: excludeId == null ? 'code = ?' : 'code = ? AND id != ?',
        whereArgs: excludeId == null ? [code] : [code, excludeId]);
    return rows.isNotEmpty;
  }

  Future<int> count() async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM products WHERE is_deleted = 0');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> adjustStock(int productId, int deltaQuantity,
      {required String reason, int? invoiceId}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('products', where: 'id = ?', whereArgs: [productId]);
      if (rows.isEmpty) throw StateError('کالا یافت نشد');
      final current = rows.first['stock'] as int;
      final next = current + deltaQuantity;
      if (next < 0) {
        throw StateError('موجودی کافی نیست (موجودی فعلی: $current)');
      }
      await txn.update('products', {'stock': next}, where: 'id = ?', whereArgs: [productId]);
      await txn.insert('stock_movements', {
        'product_id': productId,
        'type': deltaQuantity >= 0 ? 'increase' : 'decrease',
        'quantity': deltaQuantity.abs(),
        'reason': reason,
        'invoice_id': invoiceId,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }
}
