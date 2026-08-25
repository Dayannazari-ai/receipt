import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/invoice.dart';
import 'settings_repository.dart';

class InvoiceRepository {
  final _db = DatabaseHelper.instance;
  final _settingsRepo = SettingsRepository();

  /// شماره فاکتور را با پیشوند نوع فاکتور می‌سازد تا خرید/فروش/خدمات از هم
  /// با یک ممیز قابل تفکیک باشند (مثلاً «خد/۱۰۰۱»، «فک/۱۰۰۱»، «خر/۱۰۰۱»).
  String _prefixFor(InvoiceType type) {
    switch (type) {
      case InvoiceType.electrical:
      case InvoiceType.mechanic:
      case InvoiceType.suspension:
        return 'خد';
      case InvoiceType.productSale:
        return 'فک';
      case InvoiceType.productPurchase:
        return 'خر';
    }
  }

  Future<String> getNextInvoiceNumber(InvoiceType type) async {
    final db = await _db.database;
    final settings = await _settingsRepo.getSettings();
    final prefix = _prefixFor(type);
    final rows = await db.query('invoices', where: 'invoice_number LIKE ?', whereArgs: ['$prefix/%']);
    int maxNum = settings.invoiceStartNumber - 1;
    for (final row in rows) {
      final numStr = (row['invoice_number'] as String).split('/').last;
      final n = int.tryParse(numStr);
      if (n != null && n > maxNum) maxNum = n;
    }
    return '$prefix/${maxNum + 1}';
  }

  /// صدور فاکتور: قیمت هر ردیف فریز می‌شود، موجودی کالا (در صورت فروش/خرید) به‌روزرسانی می‌شود.
  Future<int> createInvoice({
    required Invoice invoice,
    required List<InvoiceItem> items,
    required List<SideCost> sideCosts,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final existing =
          await txn.query('invoices', where: 'invoice_number = ?', whereArgs: [invoice.invoiceNumber]);
      if (existing.isNotEmpty) throw StateError('شماره فاکتور تکراری است');

      final invoiceId = await txn.insert('invoices', invoice.toMap()..remove('id'));

      for (final item in items) {
        await txn.insert('invoice_items', item.toMap()..remove('id')..['invoice_id'] = invoiceId);

        if (item.itemType == InvoiceItemType.product && item.productId != null) {
          final rows = await txn.query('products', where: 'id = ?', whereArgs: [item.productId]);
          if (rows.isEmpty) throw StateError('کالا یافت نشد');
          final currentStock = rows.first['stock'] as int;
          // فروش کالا => کاهش موجودی / خرید کالا => افزایش موجودی
          final delta = invoice.type.isProductPurchase ? item.quantity : -item.quantity;
          final nextStock = currentStock + delta;
          if (nextStock < 0) {
            throw StateError('موجودی کافی برای «${item.description}» وجود ندارد (موجودی: $currentStock)');
          }
          await txn.update('products', {'stock': nextStock}, where: 'id = ?', whereArgs: [item.productId]);
          await txn.insert('stock_movements', {
            'product_id': item.productId,
            'type': delta >= 0 ? 'increase' : 'decrease',
            'quantity': item.quantity,
            'reason': 'invoice',
            'invoice_id': invoiceId,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      for (final cost in sideCosts) {
        await txn.insert('side_costs', cost.toMap()..remove('id')..['invoice_id'] = invoiceId);
      }

      return invoiceId;
    });
  }

  Future<Invoice?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Invoice.fromMap(rows.first);
  }

  Future<List<InvoiceItem>> getItems(int invoiceId) async {
    final db = await _db.database;
    final rows = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
    return rows.map((r) => InvoiceItem.fromMap(r)).toList();
  }

  Future<List<SideCost>> getSideCosts(int invoiceId) async {
    final db = await _db.database;
    final rows = await db.query('side_costs', where: 'invoice_id = ?', whereArgs: [invoiceId]);
    return rows.map((r) => SideCost.fromMap(r)).toList();
  }

  Future<List<Invoice>> getAll({InvoiceType? typeFilter, bool onlySales = false, bool onlyPurchases = false}) async {
    final db = await _db.database;
    String where = 'is_deleted = 0';
    List<Object?> args = [];
    if (typeFilter != null) {
      where += ' AND type = ?';
      args.add(typeFilter.dbValue);
    } else if (onlySales) {
      where += ' AND type != ?';
      args.add(InvoiceType.productPurchase.dbValue);
    } else if (onlyPurchases) {
      where += ' AND type = ?';
      args.add(InvoiceType.productPurchase.dbValue);
    }
    final rows =
        await db.query('invoices', where: where, whereArgs: args, orderBy: 'issue_date DESC, id DESC');
    return rows.map((r) => Invoice.fromMap(r)).toList();
  }

  Future<List<Invoice>> getByCustomer(int customerId) async {
    final db = await _db.database;
    final rows = await db.query('invoices',
        where: 'customer_id = ? AND is_deleted = 0', whereArgs: [customerId], orderBy: 'issue_date DESC');
    return rows.map((r) => Invoice.fromMap(r)).toList();
  }

  Future<List<Invoice>> getRecent({int limit = 5}) async {
    final db = await _db.database;
    final rows =
        await db.query('invoices', where: 'is_deleted = 0', orderBy: 'issue_date DESC, id DESC', limit: limit);
    return rows.map((r) => Invoice.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> searchWithDetails(String q) async {
    final db = await _db.database;
    final like = '%$q%';
    return db.rawQuery('''
      SELECT i.*, c.name as customer_name
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customer_id
      WHERE i.is_deleted = 0 AND (i.invoice_number LIKE ? OR c.name LIKE ?)
      ORDER BY i.issue_date DESC
    ''', [like, like]);
  }

  // ----------------- گزارش‌ها -----------------
  Future<double> getTotalSales(String fromIso, String toIso) async {
    final db = await _db.database;
    final r = await db.rawQuery(
        "SELECT SUM(final_amount) t FROM invoices WHERE is_deleted = 0 AND type != 'productPurchase' AND issue_date BETWEEN ? AND ?",
        [fromIso, toIso]);
    final v = r.first['t'];
    return v == null ? 0.0 : (v as num).toDouble();
  }

  Future<int> countInvoices(String fromIso, String toIso) async {
    final db = await _db.database;
    final r = await db.rawQuery(
        'SELECT COUNT(*) c FROM invoices WHERE is_deleted = 0 AND issue_date BETWEEN ? AND ?',
        [fromIso, toIso]);
    return Sqflite.firstIntValue(r) ?? 0;
  }
}
