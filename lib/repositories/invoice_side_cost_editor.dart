import '../database/database_helper.dart';
import '../services/invoice_service.dart';

/// ویرایش هزینه‌های جانبی یک فاکتور (حتی بعد از صدور).
///
/// فقط جدول side_costs و دو ستون محاسباتی همان فاکتور (side_costs و
/// final_amount) تغییر می‌کنند. هیچ تراکنش یا چک مالی ساخته یا تغییر نمی‌کند.
///
/// قاعده‌ی مالی: دفتر «حساب فروش کالا» هرگز ویرایش نمی‌شود. هزینه‌ی جانبی
/// فقط در فاکتور فروش/خرید کالا وارد دفتر می‌شود (در فاکتور خدماتی هیچ اثری
/// ندارد). بنابراین اگر فاکتور کالا قبلاً در دفتر یا چک‌ها ثبت شده باشد،
/// ویرایش مستقیم هزینه‌ی جانبی مجاز نیست تا مانده و گزارش‌ها مغایرت پیدا
/// نکنند (اصلاح آن فقط با «اصلاحیه» در دفتر مالی است).
class InvoiceSideCostEditor {
  final _db = DatabaseHelper.instance;

  static const Set<String> _serviceTypes = {'electrical', 'mechanic', 'suspension'};

  /// null یعنی ویرایش مجاز است؛ در غیر این صورت متن دلیل را برمی‌گرداند.
  Future<String?> blockReason(int invoiceId) async {
    final db = await _db.database;
    final rows = await db.query('invoices',
        columns: ['type', 'is_draft'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (rows.isEmpty) return 'فاکتور یافت نشد';
    if ((rows.first['is_draft'] as int? ?? 0) == 1) return null;
    if (_serviceTypes.contains(rows.first['type'] as String?)) return null;

    final tx = await db.query('finance_transactions',
        columns: ['id'], where: 'invoice_id = ?', whereArgs: [invoiceId], limit: 1);
    final chq = await db.query('finance_cheques',
        columns: ['id'], where: 'invoice_id = ?', whereArgs: [invoiceId], limit: 1);
    if (tx.isNotEmpty || chq.isNotEmpty) {
      return 'هزینه‌ی جانبی این فاکتور کالا در حساب مالی فروش کالا ثبت شده است و '
          'دفتر مالی قابل ویرایش نیست. برای اصلاح، از صفحه‌ی «گردش مالی» اصلاحیه ثبت کنید.';
    }
    return null;
  }

  /// جایگزینی کامل هزینه‌های جانبی فاکتور با [lines] و محاسبه‌ی دوباره‌ی
  /// جمع هزینه‌ها و مبلغ نهایی، همه در یک تراکنش.
  /// مبلغ نهایی = جمع اقلام (بدون تغییر) + جمع هزینه‌های جانبی جدید.
  Future<void> replaceSideCosts({required int invoiceId, required List<SideCostLine> lines}) async {
    for (final l in lines) {
      if (l.title.trim().isEmpty) throw StateError('عنوان هزینه را وارد کنید');
      if (l.amount.isNaN || l.amount.isInfinite || l.amount <= 0) {
        throw StateError('مبلغ هزینه باید بیشتر از صفر باشد');
      }
    }
    final reason = await blockReason(invoiceId);
    if (reason != null) throw StateError(reason);

    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('invoices',
          columns: ['items_total'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (rows.isEmpty) throw StateError('فاکتور یافت نشد');
      final itemsTotal = (rows.first['items_total'] as num?)?.toDouble() ?? 0.0;
      final sum = lines.fold<double>(0.0, (s, l) => s + l.amount);

      await txn.delete('side_costs', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      for (final l in lines) {
        await txn.insert('side_costs', {
          'invoice_id': invoiceId,
          'title': l.title.trim(),
          'amount': l.amount,
        });
      }
      await txn.update(
        'invoices',
        {'side_costs': sum, 'final_amount': itemsTotal + sum},
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });
  }
}
