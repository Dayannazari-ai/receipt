import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/invoice.dart';
import 'settings_repository.dart';

class InvoiceRepository {
  final _db = DatabaseHelper.instance;
  final _settingsRepo = SettingsRepository();

  /// پیشوند سری پیش‌فاکتور. کاملاً جدا از پیشوندهای فاکتور اصلی، تا هیچ
  /// شماره‌ای از سری اصلی توسط پیش‌فاکتور مصرف نشود.
  static const String _draftPrefix = 'DRAFT';

  /// شماره فاکتور با پیشوند انگلیسی نوع فاکتور، با ممیز جدا می‌شود.
  /// B = برق خودرو، M = مکانیک, J = جلوبندی، SL = فروش کالا, PR = خرید کالا
  String _prefixFor(InvoiceType type) {
    switch (type) {
      case InvoiceType.electrical:
       return 'B';
      case InvoiceType.mechanic:
       return 'M';
      case InvoiceType.suspension:
        return 'J';
      case InvoiceType.productSale:
        return 'SL';
      case InvoiceType.productPurchase:
        return 'PR';
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

  /// شماره‌ی سری پیش‌فاکتور (مثلاً DRAFT/1، DRAFT/2). کاملاً مستقل از سری
  /// فاکتورهای اصلی؛ هیچ عددی از سری اصلی را مصرف نمی‌کند.
  Future<String> getNextDraftNumber() async {
    final db = await _db.database;
    final rows = await db.query('invoices', where: 'invoice_number LIKE ?', whereArgs: ['$_draftPrefix/%']);
    int maxNum = 0;
    for (final row in rows) {
      final numStr = (row['invoice_number'] as String).split('/').last;
      final n = int.tryParse(numStr);
      if (n != null && n > maxNum) maxNum = n;
    }
    return '$_draftPrefix/${maxNum + 1}';
  }

  /// اعمال اثر یک آیتم کالا روی موجودی (کاهش برای فروش/خدمات، افزایش برای
  /// خرید کالا) و ثبت آن در stock_movements. این دقیقاً همان منطقی است که
  /// قبلاً فقط داخل createInvoice بود؛ اکنون قابل استفاده‌ی مجدد در
  /// convertDraftToInvoice هم هست تا هیچ منطق موازی/متفاوتی اختراع نشود.
  Future<void> _applyStockEffect(
    Transaction txn, {
    required InvoiceItem item,
    required InvoiceType invoiceType,
    required int invoiceId,
  }) async {
    if (item.itemType != InvoiceItemType.product || item.productId == null) return;

    final rows = await txn.query('products', where: 'id = ?', whereArgs: [item.productId]);
    if (rows.isEmpty) throw StateError('کالا یافت نشد');
    final currentStock = rows.first['stock'] as int;
    // فروش کالا => کاهش موجودی / خرید کالا => افزایش موجودی
    final delta = invoiceType.isProductPurchase ? item.quantity : -item.quantity;
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

  /// صدور فاکتور یا ثبت پیش‌فاکتور.
  ///
  /// وقتی [isDraft] برابر true باشد:
  /// - رکورد با is_draft = 1 ذخیره می‌شود.
  /// - هیچ اثری روی موجودی کالا یا stock_movements گذاشته نمی‌شود؛ این اثر
  ///   فقط هنگام تبدیل به فاکتور اصلی (convertDraftToInvoice) اعمال می‌شود.
  ///
  /// وقتی [isDraft] برابر false باشد (پیش‌فرض)، رفتار دقیقاً مثل قبل است:
  /// قیمت هر ردیف فریز می‌شود و موجودی بلافاصله به‌روزرسانی می‌شود.
  Future<int> createInvoice({
    required Invoice invoice,
    required List<InvoiceItem> items,
    required List<SideCost> sideCosts,
    bool isDraft = false,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final existing =
          await txn.query('invoices', where: 'invoice_number = ?', whereArgs: [invoice.invoiceNumber]);
      if (existing.isNotEmpty) throw StateError('شماره فاکتور تکراری است');

      final invoiceId = await txn.insert('invoices', invoice.toMap()..remove('id'));

      for (final item in items) {
        await txn.insert('invoice_items', item.toMap()..remove('id')..['invoice_id'] = invoiceId);

        if (!isDraft) {
          await _applyStockEffect(txn, item: item, invoiceType: invoice.type, invoiceId: invoiceId);
        }
      }

      for (final cost in sideCosts) {
        await txn.insert('side_costs', cost.toMap()..remove('id')..['invoice_id'] = invoiceId);
      }

      return invoiceId;
    });
  }

  /// تبدیل اتمیک یک پیش‌فاکتور به فاکتور اصلی.
  ///
  /// فقط رکوردی که is_draft = 1 است قابل تبدیل است (شرط داخل خود کوئری
  /// UPDATE اعمال می‌شود)، پس تبدیل دوباره‌ی یک فاکتور که قبلاً تبدیل شده
  /// امکان‌پذیر نیست. شماره‌ی جدید از سری اصلی (بر اساس [type]) گرفته
  /// می‌شود؛ سپس همان منطق موجودی که در createInvoice استفاده می‌شود
  /// (_applyStockEffect) برای اولین و تنها بار روی آیتم‌های این فاکتور
  /// اجرا می‌شود. تمام این مراحل در یک تراکنش هستند: یا همه انجام می‌شوند
  /// یا هیچ‌کدام.
  ///
  /// در صورت موفقیت، شماره‌ی نهایی فاکتور را برمی‌گرداند.
  /// در صورتی که رکورد پیش‌فاکتور نباشد یا قبلاً تبدیل شده باشد، استثنا
  /// پرتاب می‌شود.
  Future<String> convertDraftToInvoice(int invoiceId) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
      if (rows.isEmpty) throw StateError('فاکتور یافت نشد');
      final invoice = Invoice.fromMap(rows.first);

      if (invoice.isDraft != 1) {
        throw StateError('این رکورد پیش‌فاکتور نیست یا قبلاً به فاکتور اصلی تبدیل شده است');
      }

      // شماره‌ی جدید از سری اصلی، با همان منطق getNextInvoiceNumber ولی
      // داخل همین تراکنش (تا با فراخوانی همزمان تداخل نکند).
      final settings = await _settingsRepo.getSettings();
      final prefix = _prefixFor(invoice.type);
      final numberRows =
          await txn.query('invoices', where: 'invoice_number LIKE ?', whereArgs: ['$prefix/%']);
      int maxNum = settings.invoiceStartNumber - 1;
      for (final row in numberRows) {
        final numStr = (row['invoice_number'] as String).split('/').last;
        final n = int.tryParse(numStr);
        if (n != null && n > maxNum) maxNum = n;
      }
      final newNumber = '$prefix/${maxNum + 1}';

      final updated = await txn.update(
        'invoices',
        {'invoice_number': newNumber, 'is_draft': 0},
        where: 'id = ? AND is_draft = 1',
        whereArgs: [invoiceId],
      );
      if (updated == 0) {
        // رقابت همزمان: بین خواندن و نوشتن، یک فراخوانی دیگر همین رکورد را
        // تبدیل کرده است. تراکنش با استثنا لغو می‌شود.
        throw StateError('این پیش‌فاکتور توسط عملیات دیگری قبلاً تبدیل شده است');
      }

      final itemRows = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      final items = itemRows.map((r) => InvoiceItem.fromMap(r)).toList();
      for (final item in items) {
        await _applyStockEffect(txn, item: item, invoiceType: invoice.type, invoiceId: invoiceId);
      }

      return newNumber;
    });
  }

  /// ویرایش کامل یک پیش‌فاکتور: فیلدهای اصلی فاکتور به‌روزرسانی می‌شوند و
  /// اقلام/هزینه‌های جانبی قبلی حذف و با لیست جدید جایگزین می‌شوند.
  ///
  /// فقط روی رکوردی با is_draft = 1 عمل می‌کند. اگر رکورد پیش‌فاکتور نباشد
  /// (یعنی قبلاً به فاکتور اصلی تبدیل شده)، استثنا پرتاب می‌شود و هیچ
  /// تغییری اعمال نمی‌شود. هیچ اثری روی موجودی کالا یا stock_movements
  /// ندارد.
  Future<void> updateDraftInvoice({
    required int invoiceId,
    required Invoice invoice,
    required List<InvoiceItem> items,
    required List<SideCost> sideCosts,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
      if (rows.isEmpty) throw StateError('فاکتور یافت نشد');
      final current = Invoice.fromMap(rows.first);
      if (current.isDraft != 1) {
        throw StateError('فقط پیش‌فاکتور قابل ویرایش است؛ این فاکتور قبلاً به فاکتور اصلی تبدیل شده است');
      }

      final map = invoice.toMap()
        ..remove('id')
        ..['is_draft'] = 1
        ..['invoice_number'] = current.invoiceNumber; // شماره‌ی پیش‌فاکتور با ویرایش تغییر نمی‌کند
      await txn.update('invoices', map, where: 'id = ?', whereArgs: [invoiceId]);

      await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      for (final item in items) {
        await txn.insert('invoice_items', item.toMap()..remove('id')..['invoice_id'] = invoiceId);
      }

      await txn.delete('side_costs', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      for (final cost in sideCosts) {
        await txn.insert('side_costs', cost.toMap()..remove('id')..['invoice_id'] = invoiceId);
      }
    });
  }

  Future<Invoice?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Invoice.fromMap(rows.first);
  }
  /// همه‌ی فاکتورهای یک مشتری خاص، بر اساس شناسه‌ی واقعی مشتری (نه نام).
  /// جدیدترین فاکتور اول نمایش داده می‌شود.
  Future<List<Invoice>> getByCustomerId(int customerId) async {
    final db = await _db.database;
    final rows = await db.query('invoices',
        where: 'customer_id = ? AND is_deleted = 0',
        whereArgs: [customerId],
        orderBy: 'issue_date DESC');
    return rows.map((r) => Invoice.fromMap(r)).toList();
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

  /// [onlyDrafts]: وقتی true باشد فقط پیش‌فاکتورها (is_draft = 1) برگردانده
  /// می‌شوند. وقتی مشخص نشود یا false باشد، رفتار دقیقاً مثل قبل است: فقط
  /// فاکتورهای اصلی (is_draft = 0) برگردانده می‌شوند و هیچ فراخوانی موجود
  /// (بدون این پارامتر) تغییر رفتار نمی‌دهد.
  Future<List<Invoice>> getAll({
    InvoiceType? typeFilter,
    bool onlySales = false,
    bool onlyPurchases = false,
    bool onlyDrafts = false,
  }) async {
    final db = await _db.database;
    String where = 'is_deleted = 0';
    List<Object?> args = [];
    if (onlyDrafts) {
      where += ' AND is_draft = 1';
    } else {
      where += ' AND is_draft = 0';
    }
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
