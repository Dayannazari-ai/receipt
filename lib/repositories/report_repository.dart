import '../database/database_helper.dart';
import '../models/finance_transaction.dart';
import '../models/service_expense.dart';
import 'finance_repository.dart';

/// جمع فاکتورهای اصلی یک نوع در یک بازه.
class InvoiceTypeTotal {
  final String type;
  final int count;
  final double total;
  const InvoiceTypeTotal({required this.type, required this.count, required this.total});
}

/// درآمد خدمات (فقط ردیف‌های «خدمت») به تفکیک نوع فاکتور.
class ServiceIncomeRow {
  final String type;
  final int invoiceCount;
  final double total;
  final double nonCash; // سهم فاکتورهای غیرنقد (چک)
  const ServiceIncomeRow({
    required this.type,
    required this.invoiceCount,
    required this.total,
    required this.nonCash,
  });
}

/// گزارش حساب فروش کالا در یک بازه، محاسبه‌شده از روی دفتر.
/// موجودی اول دوره + ورودی‌ها − خروجی‌ها = موجودی پایان دوره.
class FinancePeriodReport {
  final double opening;
  final double closing;
  final Map<String, double> inflow; // کلید نوع تراکنش -> مبلغ خالص
  final Map<String, double> outflow;
  final int txCount;
  const FinancePeriodReport({
    required this.opening,
    required this.closing,
    required this.inflow,
    required this.outflow,
    required this.txCount,
  });

  double get totalIn => inflow.values.fold<double>(0.0, (a, b) => a + b);
  double get totalOut => outflow.values.fold<double>(0.0, (a, b) => a + b);
  double get net => totalIn - totalOut;
}

/// کوئری‌های گزارش‌ها. هیچ داده‌ای را تغییر نمی‌دهد، به‌جز ثبت/حذف
/// «هزینه‌ی خدماتی».
class ReportRepository {
  final _db = DatabaseHelper.instance;

  // ==================== فاکتورها ====================

  Future<List<InvoiceTypeTotal>> invoiceSummary(DateTime from, DateTime to) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT type, COUNT(*) AS c, SUM(final_amount) AS t FROM invoices '
      'WHERE is_deleted = 0 AND is_draft = 0 AND issue_date BETWEEN ? AND ? GROUP BY type',
      [from.toIso8601String(), to.toIso8601String()],
    );
    return rows
        .map((r) => InvoiceTypeTotal(
              type: (r['type'] as String?) ?? '',
              count: (r['c'] as num?)?.toInt() ?? 0,
              total: (r['t'] as num?)?.toDouble() ?? 0.0,
            ))
        .toList();
  }

  // ==================== خدمات ====================

  /// درآمد خدمات: جمع ردیف‌های «خدمت» فاکتورهای اصلی، بر اساس تاریخ صدور.
  Future<List<ServiceIncomeRow>> serviceIncome(DateTime from, DateTime to) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT i.type AS type, COUNT(DISTINCT i.id) AS c, SUM(it.total) AS t, '
      'SUM(CASE WHEN i.payment_type = ? THEN it.total ELSE 0 END) AS nc '
      'FROM invoice_items it JOIN invoices i ON i.id = it.invoice_id '
      'WHERE it.item_type = ? AND i.is_deleted = 0 AND i.is_draft = 0 '
      'AND i.issue_date BETWEEN ? AND ? GROUP BY i.type',
      ['nonCash', 'service', from.toIso8601String(), to.toIso8601String()],
    );
    return rows
        .map((r) => ServiceIncomeRow(
              type: (r['type'] as String?) ?? '',
              invoiceCount: (r['c'] as num?)?.toInt() ?? 0,
              total: (r['t'] as num?)?.toDouble() ?? 0.0,
              nonCash: (r['nc'] as num?)?.toDouble() ?? 0.0,
            ))
        .toList();
  }

  Future<List<ServiceExpense>> serviceExpenses(DateTime from, DateTime to) async {
    final db = await _db.database;
    final rows = await db.query(
      'service_expenses',
      where: 'expense_date BETWEEN ? AND ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'expense_date DESC, id DESC',
    );
    return rows.map((r) => ServiceExpense.fromMap(r)).toList();
  }

  Future<int> addServiceExpense({
    required DateTime date,
    required String title,
    required double amount,
    required String category,
    String? notes,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw StateError('عنوان هزینه را وارد کنید');
    if (amount.isNaN || amount.isInfinite || amount <= 0) {
      throw StateError('مبلغ باید بیشتر از صفر باشد');
    }
    final cleanNotes = (notes ?? '').trim();
    final db = await _db.database;
    return db.insert('service_expenses', {
      'expense_date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'title': cleanTitle,
      'amount': amount,
      'category': ServiceExpense.categories.containsKey(category) ? category : 'other',
      'notes': cleanNotes.isEmpty ? null : cleanNotes,
      'backup_uid': FinanceRepository.generateUid().replaceFirst('fin-', 'sexp-'),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteServiceExpense(int id) async {
    final db = await _db.database;
    await db.delete('service_expenses', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== حساب فروش کالا ====================

  /// چک‌های در انتظار وصول (روی مانده اثر ندارند)، به تفکیک جهت.
  /// هر سطر: direction ('in' یا 'out')، c (تعداد)، t (جمع مبلغ).
  Future<List<Map<String, Object?>>> pendingCheques() async {
    final db = await _db.database;
    return db.rawQuery(
      'SELECT direction, COUNT(*) AS c, SUM(amount) AS t FROM finance_cheques '
      'WHERE status = ? GROUP BY direction',
      ['pending'],
    );
  }

  /// محاسبه‌ی گزارش بازه از روی سطرهای دفتر (به ترتیب زمانی صعودی). اصلاحیه‌ها
  /// از همان نوعِ تراکنش اصلی کم/زیاد می‌شوند تا جمع هر دسته خالص باشد.
  static FinancePeriodReport computeFinance(List<FinanceLedgerRow> rows, DateTime from, DateTime to) {
    final byId = <int, FinanceTransaction>{
      for (final r in rows)
        if (r.tx.id != null) r.tx.id!: r.tx,
    };
    var opening = 0.0;
    var closing = 0.0;
    var count = 0;
    final inflow = <String, double>{};
    final outflow = <String, double>{};

    for (final r in rows) {
      final t = r.tx;
      final d = t.dateTime;
      if (d.isBefore(from)) {
        opening = r.balanceAfter;
        closing = r.balanceAfter;
        continue;
      }
      if (d.isAfter(to)) continue;
      count++;
      closing = r.balanceAfter;

      final orig = t.isReversal && t.reversesId != null ? byId[t.reversesId!] : null;
      final base = orig ?? t;
      final key = base.txType;
      if (base.direction == FinanceDirection.inflow) {
        inflow[key] = (inflow[key] ?? 0.0) + t.signedAmount;
      } else {
        outflow[key] = (outflow[key] ?? 0.0) - t.signedAmount;
      }
    }

    return FinancePeriodReport(
      opening: opening,
      closing: closing,
      inflow: inflow,
      outflow: outflow,
      txCount: count,
    );
  }
}
