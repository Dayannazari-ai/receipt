import '../database/database_helper.dart';
import 'finance_repository.dart';

/// ابطال امن یک فاکتور نهایی (مرحله‌ی ۱ اصلاح فرایند صدور فاکتور).
///
/// همه‌ی کارها در یک تراکنش دیتابیس انجام می‌شود: یا همه اعمال می‌شود یا
/// هیچ‌کدام. حذف فیزیکی انجام نمی‌شود؛ فاکتور با is_deleted = 1 باطل می‌شود
/// و همه‌ی کوئری‌های موجود (فهرست، گزارش، بدهکاران، جست‌وجو) آن را نادیده
/// می‌گیرند.
///
/// آزاد شدن شماره: شماره‌ی فاکتور باطل‌شده به شکل یکتا تغییر نام می‌دهد
/// (مثلاً SL/125 ← SL/125~باطل-17). چون بخش بعد از «/» دیگر عدد نیست،
/// getNextInvoiceNumber آن را در محاسبه‌ی بزرگ‌ترین شماره نادیده می‌گیرد و
/// اگر آخرین شماره باطل شود، همان شماره دوباره قابل صدور است. فاکتور جدید
/// شناسه‌ی داخلی مستقل دارد و به تراکنش/موجودی/چک فاکتور قبلی وصل نمی‌شود.
///
/// نکته: داخل تراکنش فقط از txn کوئری می‌زنیم (بن‌بست دائمی در غیر این صورت).
class InvoiceVoidRepository {
  final _db = DatabaseHelper.instance;

  /// شماره‌ی اصلی فاکتور باطل‌شده را برمی‌گرداند.
  Future<String> voidInvoice(int invoiceId) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (rows.isEmpty) throw StateError('فاکتور یافت نشد');
      final inv = rows.first;
      if ((inv['is_draft'] as int? ?? 0) == 1) {
        throw StateError('پیش‌فاکتور با این روش باطل نمی‌شود');
      }
      if ((inv['is_deleted'] as int? ?? 0) == 1) {
        throw StateError('این فاکتور قبلاً باطل شده است');
      }
      final number = inv['invoice_number'] as String;
      final isPurchase = inv['type'] == 'productPurchase';
      final nowIso = DateTime.now().toIso8601String();

      // ---- ۱) برگشت موجودی (دقیقاً عکس اثر زمان صدور) ----
      final items = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      for (final item in items) {
        if (item['item_type'] != 'product' || item['product_id'] == null) continue;
        final productId = item['product_id'] as int;
        final qty = (item['quantity'] as num).toInt();
        final prod = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
        if (prod.isEmpty) throw StateError('کالای «${item['description']}» یافت نشد؛ ابطال انجام نشد.');
        final current = (prod.first['stock'] as num).toInt();
        // خرید کالا موجودی را زیاد کرده بود ← کم می‌شود؛ فروش/خدمات کم کرده بود ← زیاد می‌شود.
        final delta = isPurchase ? -qty : qty;
        final next = current + delta;
        if (next < 0) {
          throw StateError('ابطال ممکن نیست: موجودی «${item['description']}» برای برگشت این خرید کافی نیست '
              '(موجودی: $current، لازم: $qty). هیچ تغییری اعمال نشد.');
        }
        await txn.update('products', {'stock': next}, where: 'id = ?', whereArgs: [productId]);
        await txn.insert('stock_movements', {
          'product_id': productId,
          'type': delta >= 0 ? 'increase' : 'decrease',
          'quantity': qty,
          'reason': 'invoice_void',
          'invoice_id': invoiceId,
          'created_at': nowIso,
        });
      }

      // ---- ۲) اصلاحیه‌ی تراکنش‌های مالی (هر تراکنش فقط یک بار) ----
      final txs = await txn.rawQuery(
        'SELECT t.* FROM finance_transactions t '
        'WHERE t.invoice_id = ? AND t.reverses_id IS NULL AND t.tx_type != ? '
        'AND NOT EXISTS (SELECT 1 FROM finance_transactions r WHERE r.reverses_id = t.id) '
        'ORDER BY t.id ASC',
        [invoiceId, 'reversal'],
      );
      for (final t in txs) {
        final origAt = DateTime.tryParse((t['occurred_at'] as String?) ?? '');
        final now = DateTime.now();
        final at = (origAt != null && now.isBefore(origAt)) ? origAt : now;
        await txn.insert('finance_transactions', {
          'account_id': t['account_id'],
          'occurred_at': at.toIso8601String(),
          'tx_type': 'reversal',
          'direction': t['direction'] == 'in' ? 'out' : 'in',
          'amount': t['amount'],
          'description': 'اصلاحیه: ${t['description'] ?? ''}',
          'invoice_id': null,
          'invoice_number': number,
          'counterparty': t['counterparty'],
          'notes': null,
          'reverses_id': t['id'],
          'correction_reason': 'ابطال فاکتور $number',
          'backup_uid': FinanceRepository.generateUid(),
          'created_at': nowIso,
        });
      }

      // ---- ۳) چک این فاکتور (چک در انتظار اثری روی مانده نداشت؛ چک
      // وصول‌شده هم تراکنش‌هایش در بند ۲ اصلاح شد) ----
      await txn.delete('finance_cheques', where: 'invoice_id = ?', whereArgs: [invoiceId]);

      // ---- ۴) ابطال و آزاد کردن شماره ----
      await txn.update(
        'invoices',
        {'is_deleted': 1, 'invoice_number': '$number~باطل-$invoiceId'},
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      return number;
    });
  }
}
