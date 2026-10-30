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

  /// شناسه‌ی مشتریانی که حداقل یک خودروی حذف‌نشده مطابق شرط‌ها دارند.
  /// فقط خواندن است و هیچ داده‌ای تغییر نمی‌کند.
  /// - [brandId] / [modelId]: فیلتر دقیق برند و مدل.
  /// - [text]: متن جستجو؛ هر کلمه‌ی آن باید در «برند + مدل» خودرو بیاید
  ///   (مثلاً «پژو 206» یا «206» یا «پژو»).
  Future<Set<int>> customerIdsByVehicle({int? brandId, int? modelId, String? text}) async {
    final db = await _db.database;
    final where = <String>['v.is_deleted = 0'];
    final args = <Object?>[];
    if (brandId != null) {
      where.add('v.brand_id = ?');
      args.add(brandId);
    }
    if (modelId != null) {
      where.add('v.model_id = ?');
      args.add(modelId);
    }
    final tokens = (text ?? '').trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    for (final t in tokens) {
      where.add("(IFNULL(b.name, '') || ' ' || IFNULL(m.name, '')) LIKE ?");
      args.add('%$t%');
    }
    final rows = await db.rawQuery('''
      SELECT DISTINCT v.customer_id AS cid FROM vehicles v
      LEFT JOIN vehicle_brands b ON b.id = v.brand_id
      LEFT JOIN vehicle_models m ON m.id = v.model_id
      WHERE ${where.join(' AND ')}
    ''', args);
    return rows.map((r) => (r['cid'] as num).toInt()).toSet();
  }

  /// مشتریان بدهکار:
  /// - فاکتور با نوع پرداخت «چک» (مثل قبل). فقط اگر چکِ آن در جدول
  ///   پرداخت‌ها «پرداخت‌شده» ثبت شده باشد، دیگر بدهی حساب نمی‌شود؛ چک‌های
  ///   قدیمی که ردیفی ندارند مثل قبل بدهی می‌مانند.
  /// - فاکتور «پرداخت ترکیبی» (غیرپیش‌فاکتور) که هنوز ردیفِ در انتظار
  ///   (چک / پرداخت توافقی) دارد یا مبلغ فاکتور از جمع ردیف‌های پرداخت
  ///   بیشتر است (مانده‌ی تسویه‌نشده).
  Future<List<Customer>> getDebtors() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT c.* FROM customers c
      JOIN invoices i ON i.customer_id = c.id
      WHERE c.is_deleted = 0 AND i.is_deleted = 0 AND (
        (i.payment_type = 'nonCash' AND NOT EXISTS (
          SELECT 1 FROM invoice_payments p
          WHERE p.invoice_id = i.id AND p.method = 'cheque' AND p.status = 'paid'))
        OR
        (i.payment_type = 'combined' AND i.is_draft = 0 AND (
          EXISTS (SELECT 1 FROM invoice_payments p WHERE p.invoice_id = i.id AND p.status = 'pending')
          OR i.final_amount - COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0) > 0.5))
      )
      ORDER BY c.name
    ''');
    return rows.map((r) => Customer.fromMap(r)).toList();
  }
}
