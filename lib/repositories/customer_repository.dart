import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';

class CustomerRepository {
  final _db = DatabaseHelper.instance;

  Future<int> insert(Customer c) async {
    final db = await _db.database;
    return db.insert('customers', c.toMap()..remove('id'));
  }

  Future<int> update(Customer c) async {
    final db = await _db.database;
    return db.update('customers', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<int> softDelete(int id) async {
    final db = await _db.database;
    return db.update('customers', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Customer?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<List<Customer>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('customers', where: 'is_deleted = 0', orderBy: 'name');
    return rows.map((r) => Customer.fromMap(r)).toList();
  }

  Future<List<Customer>> search(String q) async {
    final db = await _db.database;
    final like = '%$q%';
    final rows = await db.query('customers',
        where: 'is_deleted = 0 AND (name LIKE ? OR mobile LIKE ?)',
        whereArgs: [like, like],
        orderBy: 'name');
    return rows.map((r) => Customer.fromMap(r)).toList();
  }

  Future<int> count() async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM customers WHERE is_deleted = 0');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// مشتریانی که حداقل یک فاکتور با نوع پرداخت «چک» دارند (بدهکار).
  Future<List<Customer>> getDebtors() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT c.* FROM customers c
      JOIN invoices i ON i.customer_id = c.id
      WHERE c.is_deleted = 0 AND i.is_deleted = 0 AND i.payment_type = 'nonCash'
      ORDER BY c.name
    ''');
    return rows.map((r) => Customer.fromMap(r)).toList();
  }
}
