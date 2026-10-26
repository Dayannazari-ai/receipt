import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'finance_invoice_posting.dart';
import 'finance_repository.dart';

/// یک چکِ پرداخت‌نشده‌ی فاکتور (برای یادآوری).
class ChequeReminder {
  final int paymentId;
  final int invoiceId;
  final String invoiceNumber;
  final String customerName;
  final double amount;
  final DateTime dueDate;

  const ChequeReminder({
    required this.paymentId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.customerName,
    required this.amount,
    required this.dueDate,
  });

  /// تعداد روز تا سررسید (اختلاف تقویمی)؛ ۰ = امروز، منفی = گذشته.
  int daysLeft(DateTime now) {
    final a = DateTime.utc(dueDate.year, dueDate.month, dueDate.day);
    final b = DateTime.utc(now.year, now.month, now.day);
    return a.difference(b).inDays;
  }
}

/// پرداخت‌ها/چک‌های هر فاکتور (جدول invoice_payments، دیتابیس نسخه ۱۱).
/// هر چک یک ردیف مستقل دارد؛ پرداخت یک چک ردیف چک دیگر را تغییر نمی‌دهد.
/// فاکتورهای قبل از نسخه ۱۱ ردیف ندارند و پیگیری نمی‌شوند (تصمیم کاربر).
class InvoicePaymentRepository {
  static const String methodCheque = 'cheque';
  static const String statusPending = 'pending';
  static const String statusPaid = 'paid';

  final _db = DatabaseHelper.instance;

  /// بعد از صدور فاکتور اصلی (یا تبدیل پیش‌فاکتور) داخل همان تراکنش صدا زده
  /// می‌شود. فقط برای فاکتور «چکی» با تاریخ سررسید ردیف می‌سازد.
  static Future<void> createForIssuedInvoice(Transaction txn, {required int invoiceId}) async {
    final rows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (rows.isEmpty) return;
    final inv = rows.first;
    if ((inv['is_draft'] as int? ?? 0) == 1) return;
    if (inv['payment_type'] != 'nonCash') return;
    final due = (inv['check_due_date'] as String?)?.trim() ?? '';
    if (due.isEmpty) return;
    final dup = await txn.query('invoice_payments',
        where: 'invoice_id = ? AND method = ?', whereArgs: [invoiceId, methodCheque], limit: 1);
    if (dup.isNotEmpty) return;
    await txn.insert('invoice_payments', {
      'invoice_id': invoiceId,
      'method': methodCheque,
      'amount': (inv['final_amount'] as num?)?.toDouble() ?? 0.0,
      'due_date': due,
      'status': statusPending,
      'paid_date': null,
      'notes': null,
      'backup_uid': FinanceRepository.generateUid().replaceFirst('fin-', 'ipay-'),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// همه‌ی چک‌های پرداخت‌نشده‌ی فاکتورهای اصلیِ باطل‌نشده، به ترتیب سررسید.
  Future<List<ChequeReminder>> pendingCheques() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT p.id AS payment_id, p.invoice_id AS invoice_id, p.amount AS amount, p.due_date AS due_date, '
      'i.invoice_number AS invoice_number, c.name AS customer_name '
      'FROM invoice_payments p '
      'JOIN invoices i ON i.id = p.invoice_id '
      'LEFT JOIN customers c ON c.id = i.customer_id '
      'WHERE p.method = ? AND p.status = ? AND i.is_deleted = 0 AND i.is_draft = 0 '
      'ORDER BY p.due_date ASC, p.id ASC',
      [methodCheque, statusPending],
    );
    final out = <ChequeReminder>[];
    for (final r in rows) {
      final due = DateTime.tryParse((r['due_date'] as String?) ?? '');
      if (due == null) continue;
      out.add(ChequeReminder(
        paymentId: (r['payment_id'] as num).toInt(),
        invoiceId: (r['invoice_id'] as num).toInt(),
        invoiceNumber: (r['invoice_number'] as String?) ?? '',
        customerName: ((r['customer_name'] as String?) ?? '').trim(),
        amount: (r['amount'] as num?)?.toDouble() ?? 0.0,
        dueDate: DateTime(due.year, due.month, due.day),
      ));
    }
    return out;
  }

  /// ثبت پرداخت یک چک. اگر برای همان فاکتور چکِ در انتظارِ حساب مالی فروش
  /// کالا هست، از همان «وصول چک» فعلی استفاده می‌شود (تراکنش‌های دفتر ثبت
  /// می‌شوند و ردیف این جدول هم در همان تراکنش پرداخت‌شده می‌شود).
  Future<void> markPaid({required int paymentId, required DateTime paidAt}) async {
    final db = await _db.database;
    final rows = await db.query('invoice_payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
    if (rows.isEmpty) throw StateError('این چک یافت نشد');
    if (rows.first['status'] != statusPending) {
      throw StateError('این چک قبلاً پرداخت‌شده ثبت شده است');
    }
    final invoiceId = (rows.first['invoice_id'] as num).toInt();

    final fin = await db.query('finance_cheques',
        where: 'invoice_id = ? AND status = ?', whereArgs: [invoiceId, 'pending'], limit: 1);
    if (fin.isNotEmpty) {
      await FinanceInvoicePosting.collectCheque(
          chequeId: (fin.first['id'] as num).toInt(), collectedAt: paidAt);
    }
    await db.update(
      'invoice_payments',
      {'status': statusPaid, 'paid_date': paidAt.toIso8601String()},
      where: 'id = ? AND status = ?',
      whereArgs: [paymentId, statusPending],
    );
  }
}
