import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'finance_invoice_posting.dart';
import 'finance_repository.dart';

/// روش‌های پرداخت یک ردیف (invoice_payments.method).
class PaymentMethods {
  PaymentMethods._();
  static const String cash = 'cash';
  static const String card = 'card';
  static const String bankTransfer = 'bank_transfer';
  static const String cardToCard = 'card_to_card';
  static const String cheque = 'cheque';
  static const String promise = 'promise';

  /// روش‌هایی که همان لحظه پرداخت‌شده حساب می‌شوند.
  static const Set<String> immediate = {cash, card, bankTransfer, cardToCard};

  static const Map<String, String> labels = {
    cash: 'نقدی',
    card: 'کارت‌خوان',
    bankTransfer: 'انتقال بانکی',
    cardToCard: 'کارت به کارت',
    cheque: 'چک',
    promise: 'پرداخت توافقی',
  };

  static String label(String m) => labels[m] ?? m;
  static bool needsDueDate(String m) => m == cheque || m == promise;
}

/// یک ردیف پرداخت (هم برای فرم، هم برای خواندن از دیتابیس).
class PaymentLine {
  final int? id;
  String method;
  double amount;

  /// تاریخ پرداخت (روش‌های آنی) یا سررسید (چک و پرداخت توافقی).
  DateTime? date;
  String notes;
  String status; // 'pending' | 'paid'
  DateTime? paidDate;

  PaymentLine({
    this.id,
    required this.method,
    required this.amount,
    this.date,
    this.notes = '',
    this.status = 'pending',
    this.paidDate,
  });

  bool get isPaid => status == 'paid';

  factory PaymentLine.fromRow(Map<String, Object?> r) => PaymentLine(
        id: (r['id'] as num?)?.toInt(),
        method: (r['method'] as String?) ?? PaymentMethods.cash,
        amount: (r['amount'] as num?)?.toDouble() ?? 0.0,
        date: DateTime.tryParse((r['due_date'] as String?) ?? ''),
        notes: (r['notes'] as String?) ?? '',
        status: (r['status'] as String?) ?? 'pending',
        paidDate: DateTime.tryParse((r['paid_date'] as String?) ?? ''),
      );

  /// null = معتبر. مجموع ردیف‌ها نباید از مبلغ فاکتور بیشتر باشد؛ کمتر بودن
  /// مجاز است و اختلاف «مانده‌ی تسویه‌نشده» نمایش داده می‌شود.
  static String? validate(List<PaymentLine> lines, double total) {
    if (lines.isEmpty) return 'برای پرداخت ترکیبی حداقل یک ردیف پرداخت اضافه کنید';
    var sum = 0.0;
    for (final l in lines) {
      if (l.amount.isNaN || l.amount.isInfinite || l.amount <= 0) {
        return 'مبلغ هر ردیف پرداخت باید بیشتر از صفر باشد';
      }
      if (PaymentMethods.needsDueDate(l.method) && l.date == null) {
        return 'برای چک و پرداخت توافقی، تاریخ سررسید را مشخص کنید';
      }
      sum += l.amount;
    }
    if (sum > total + 0.5) return 'مجموع پرداخت‌ها از مبلغ فاکتور بیشتر است';
    return null;
  }
}

/// یک چک یا پرداخت توافقیِ پرداخت‌نشده (برای یادآوری).
class ChequeReminder {
  final int paymentId;
  final int invoiceId;
  final String invoiceNumber;
  final String customerName;
  final double amount;
  final DateTime dueDate;
  final String method; // 'cheque' | 'promise'

  const ChequeReminder({
    required this.paymentId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.customerName,
    required this.amount,
    required this.dueDate,
    this.method = PaymentMethods.cheque,
  });

  bool get isPromise => method == PaymentMethods.promise;

  /// تعداد روز تا سررسید (اختلاف تقویمی)؛ ۰ = امروز، منفی = گذشته.
  int daysLeft(DateTime now) {
    final a = DateTime.utc(dueDate.year, dueDate.month, dueDate.day);
    final b = DateTime.utc(now.year, now.month, now.day);
    return a.difference(b).inDays;
  }
}

/// پرداخت‌ها/چک‌های هر فاکتور (جدول invoice_payments).
/// - فاکتور «چکی» (قدیمی): یک ردیف cheque به مبلغ کل فاکتور.
/// - فاکتور «پرداخت ترکیبی»: هر ردیف مستقل؛ روش‌های آنی همان لحظه‌ی صدور
///   پرداخت‌شده و وارد حساب می‌شوند، چک و پرداخت توافقی تا پرداخت واقعی نه.
/// سهم کالاییِ هر پرداخت واقعی (به نسبت مبلغ) در حساب فروش کالا ثبت می‌شود.
class InvoicePaymentRepository {
  static const String methodCheque = PaymentMethods.cheque;
  static const String statusPending = 'pending';
  static const String statusPaid = 'paid';

  final _db = DatabaseHelper.instance;

  static String _newUid() => FinanceRepository.generateUid().replaceFirst('fin-', 'ipay-');

  static String _dateIso(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();

  // ==================== ردیف‌های فاکتور ====================

  /// جایگزینی کامل ردیف‌های یک فاکتور (فقط هنگام ساخت یا ویرایش پیش‌فاکتور؛
  /// همه به‌صورت «در انتظار» ذخیره می‌شوند و اثر مالی ندارند).
  static Future<void> saveLines(Transaction txn, int invoiceId, List<PaymentLine> lines) async {
    await txn.delete('invoice_payments', where: 'invoice_id = ?', whereArgs: [invoiceId]);
    for (final l in lines) {
      await txn.insert('invoice_payments', {
        'invoice_id': invoiceId,
        'method': l.method,
        'amount': l.amount,
        'due_date': l.date == null ? null : _dateIso(l.date!),
        'status': statusPending,
        'paid_date': null,
        'notes': l.notes.trim().isEmpty ? null : l.notes.trim(),
        'backup_uid': _newUid(),
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<PaymentLine>> getLines(int invoiceId) async {
    final db = await _db.database;
    final rows = await db.query('invoice_payments',
        where: 'invoice_id = ?', whereArgs: [invoiceId], orderBy: 'id ASC');
    return rows.map(PaymentLine.fromRow).toList();
  }

  // ==================== بعد از صدور فاکتور ====================

  /// بعد از صدور فاکتور اصلی (یا تبدیل پیش‌فاکتور) داخل همان تراکنش صدا
  /// زده می‌شود.
  static Future<void> createForIssuedInvoice(Transaction txn, {required int invoiceId}) async {
    final rows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (rows.isEmpty) return;
    final inv = rows.first;
    if ((inv['is_draft'] as int? ?? 0) == 1) return;

    final pt = inv['payment_type'];
    if (pt == 'combined') {
      await _processCombined(txn, inv);
      return;
    }
    if (pt != 'nonCash') return;
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
      'backup_uid': _newUid(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// فاکتور ترکیبی: ردیف‌های آنی پرداخت‌شده می‌شوند و سهم کالاییشان وارد
  /// حساب می‌شود؛ چک و پرداخت توافقی «در انتظار» می‌مانند.
  static Future<void> _processCombined(Transaction txn, Map<String, Object?> inv) async {
    final invoiceId = (inv['id'] as num).toInt();
    final finalAmount = (inv['final_amount'] as num?)?.toDouble() ?? 0.0;
    final lines = await txn.query('invoice_payments',
        where: 'invoice_id = ?', whereArgs: [invoiceId], orderBy: 'id ASC');
    if (lines.isEmpty) throw StateError('برای پرداخت ترکیبی حداقل یک ردیف پرداخت لازم است');

    var sum = 0.0;
    var paidSoFar = 0.0;
    for (final l in lines) {
      final a = (l['amount'] as num?)?.toDouble() ?? 0.0;
      sum += a;
      if (l['status'] == statusPaid) paidSoFar += a;
    }
    if (sum > finalAmount + 0.5) {
      throw StateError('مجموع پرداخت‌ها از مبلغ فاکتور بیشتر است؛ ردیف‌های پرداخت را اصلاح کنید');
    }

    final issuedAt = DateTime.tryParse((inv['issue_date'] as String?) ?? '') ?? DateTime.now();
    for (final l in lines) {
      if (l['status'] == statusPaid) continue;
      final method = (l['method'] as String?) ?? PaymentMethods.cash;
      if (!PaymentMethods.immediate.contains(method)) continue;
      final amount = (l['amount'] as num?)?.toDouble() ?? 0.0;
      final paidAt = DateTime.tryParse((l['due_date'] as String?) ?? '') ?? issuedAt;
      paidSoFar += amount;
      await txn.update(
        'invoice_payments',
        {'status': statusPaid, 'paid_date': paidAt.toIso8601String()},
        where: 'id = ?',
        whereArgs: [l['id']],
      );
      await FinanceInvoicePosting.postPaymentShare(txn,
          invoiceId: invoiceId, paidTotalAfter: paidSoFar, at: paidAt, label: PaymentMethods.label(method));
    }
  }

  /// ثبت یک پرداخت تازه برای مانده‌ی تسویه‌نشده‌ی فاکتور «پرداخت ترکیبی»ِ
  /// صادرشده. روش‌های آنی همان لحظه دریافت‌شده حساب و سهم کالاییشان وارد
  /// حساب می‌شود؛ چک و پرداخت توافقی «در انتظار» می‌مانند. جمع ردیف‌ها نباید
  /// از مبلغ فاکتور بیشتر شود.
  Future<void> addPayment({required int invoiceId, required PaymentLine line}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (rows.isEmpty) throw StateError('فاکتور یافت نشد');
      final inv = rows.first;
      if (inv['payment_type'] != 'combined') throw StateError('این کار فقط برای فاکتور پرداخت ترکیبی ممکن است');
      if ((inv['is_draft'] as int? ?? 0) == 1) {
        throw StateError('پرداخت‌های پیش‌فاکتور را از صفحه‌ی ویرایش پیش‌فاکتور تغییر دهید');
      }
      if ((inv['is_deleted'] as int? ?? 0) == 1) throw StateError('این فاکتور باطل شده است');
      final finalAmount = (inv['final_amount'] as num?)?.toDouble() ?? 0.0;

      if (line.amount.isNaN || line.amount <= 0) throw StateError('مبلغ باید بیشتر از صفر باشد');
      if (PaymentMethods.needsDueDate(line.method) && line.date == null) {
        throw StateError('برای چک و پرداخت توافقی، تاریخ سررسید لازم است');
      }
      final sumRows = await txn.rawQuery(
          'SELECT SUM(amount) t FROM invoice_payments WHERE invoice_id = ?', [invoiceId]);
      final existing = (sumRows.first['t'] as num?)?.toDouble() ?? 0.0;
      if (existing + line.amount > finalAmount + 0.5) {
        throw StateError('مبلغ از مانده‌ی تسویه‌نشده‌ی فاکتور بیشتر است');
      }

      final immediate = PaymentMethods.immediate.contains(line.method);
      final paidAt = line.date ?? DateTime.now();
      await txn.insert('invoice_payments', {
        'invoice_id': invoiceId,
        'method': line.method,
        'amount': line.amount,
        'due_date': line.date == null ? null : _dateIso(line.date!),
        'status': immediate ? statusPaid : statusPending,
        'paid_date': immediate ? paidAt.toIso8601String() : null,
        'notes': line.notes.trim().isEmpty ? null : line.notes.trim(),
        'backup_uid': _newUid(),
        'created_at': DateTime.now().toIso8601String(),
      });
      if (immediate) {
        final paid = await txn.rawQuery(
            'SELECT SUM(amount) t FROM invoice_payments WHERE invoice_id = ? AND status = ?',
            [invoiceId, statusPaid]);
        await FinanceInvoicePosting.postPaymentShare(txn,
            invoiceId: invoiceId,
            paidTotalAfter: (paid.first['t'] as num?)?.toDouble() ?? 0.0,
            at: paidAt,
            label: PaymentMethods.label(line.method));
      }
    });
  }

  // ==================== یادآوری و ثبت پرداخت ====================

  /// همه‌ی چک‌ها و پرداخت‌های توافقیِ پرداخت‌نشده‌ی فاکتورهای اصلیِ
  /// باطل‌نشده، به ترتیب سررسید.
  Future<List<ChequeReminder>> pendingCheques() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT p.id AS payment_id, p.invoice_id AS invoice_id, p.amount AS amount, p.due_date AS due_date, '
      'p.method AS method, i.invoice_number AS invoice_number, c.name AS customer_name '
      'FROM invoice_payments p '
      'JOIN invoices i ON i.id = p.invoice_id '
      'LEFT JOIN customers c ON c.id = i.customer_id '
      "WHERE p.method IN ('cheque', 'promise') AND p.status = ? AND i.is_deleted = 0 AND i.is_draft = 0 "
      'ORDER BY p.due_date ASC, p.id ASC',
      [statusPending],
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
        method: (r['method'] as String?) ?? PaymentMethods.cheque,
      ));
    }
    return out;
  }

  /// ثبت پرداخت یک ردیف.
  /// - فاکتور ترکیبی: ردیف پرداخت‌شده و سهم کالاییِ آن وارد حساب می‌شود.
  ///   پرداخت جزئی فقط برای «پرداخت توافقی» مجاز است ([amount] کمتر از مبلغ
  ///   ردیف): ردیف فعلی به مانده کاهش می‌یابد و یک ردیف پرداخت‌شده ساخته
  ///   می‌شود. چک فقط کامل پرداخت می‌شود.
  /// - فاکتور چکیِ قدیمی: اگر چکِ در انتظارِ حساب کالا هست از همان «وصول چک»
  ///   فعلی استفاده می‌شود.
  Future<void> markPaid({required int paymentId, required DateTime paidAt, double? amount}) async {
    final db = await _db.database;
    final rows = await db.query('invoice_payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
    if (rows.isEmpty) throw StateError('این ردیف پرداخت یافت نشد');
    if (rows.first['status'] != statusPending) {
      throw StateError('این پرداخت قبلاً ثبت شده است');
    }
    final invoiceId = (rows.first['invoice_id'] as num).toInt();
    final inv = await db.query('invoices', columns: ['payment_type'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    final isCombined = inv.isNotEmpty && inv.first['payment_type'] == 'combined';

    if (isCombined) {
      await _markCombinedPaid(db, paymentId: paymentId, paidAt: paidAt, amount: amount);
      return;
    }

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

  Future<void> _markCombinedPaid(Database db,
      {required int paymentId, required DateTime paidAt, double? amount}) async {
    await db.transaction((txn) async {
      final rows = await txn.query('invoice_payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
      if (rows.isEmpty) throw StateError('این ردیف پرداخت یافت نشد');
      final row = rows.first;
      if (row['status'] != statusPending) throw StateError('این پرداخت قبلاً ثبت شده است');
      final invoiceId = (row['invoice_id'] as num).toInt();
      final method = (row['method'] as String?) ?? PaymentMethods.cash;
      final lineAmount = (row['amount'] as num?)?.toDouble() ?? 0.0;
      final pay = amount ?? lineAmount;
      if (pay.isNaN || pay <= 0 || pay > lineAmount + 0.5) throw StateError('مبلغ پرداخت معتبر نیست');

      if (pay < lineAmount - 0.5) {
        if (method != PaymentMethods.promise) {
          throw StateError('چک را فقط به‌صورت کامل می‌توان پرداخت‌شده ثبت کرد');
        }
        await txn.update('invoice_payments', {'amount': lineAmount - pay},
            where: 'id = ?', whereArgs: [paymentId]);
        await txn.insert('invoice_payments', {
          'invoice_id': invoiceId,
          'method': method,
          'amount': pay,
          'due_date': row['due_date'],
          'status': statusPaid,
          'paid_date': paidAt.toIso8601String(),
          'notes': row['notes'],
          'backup_uid': _newUid(),
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        await txn.update(
          'invoice_payments',
          {'status': statusPaid, 'paid_date': paidAt.toIso8601String()},
          where: 'id = ?',
          whereArgs: [paymentId],
        );
      }

      final paid = await txn.rawQuery(
          'SELECT SUM(amount) t FROM invoice_payments WHERE invoice_id = ? AND status = ?',
          [invoiceId, statusPaid]);
      final paidTotal = (paid.first['t'] as num?)?.toDouble() ?? 0.0;
      await FinanceInvoicePosting.postPaymentShare(txn,
          invoiceId: invoiceId,
          paidTotalAfter: paidTotal,
          at: paidAt,
          label: PaymentMethods.label(method));
    });
  }
}
