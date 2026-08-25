import '../database/database_helper.dart';
import '../models/payment_account.dart';

class PaymentAccountRepository {
  final _db = DatabaseHelper.instance;

  Future<int> insert(PaymentAccount a) async {
    final db = await _db.database;
    return db.insert('payment_accounts', a.toMap()..remove('id'));
  }

  Future<int> softDelete(int id) async {
    final db = await _db.database;
    return db.update('payment_accounts', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PaymentAccount>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('payment_accounts', where: 'is_deleted = 0', orderBy: 'title');
    return rows.map((r) => PaymentAccount.fromMap(r)).toList();
  }
}
