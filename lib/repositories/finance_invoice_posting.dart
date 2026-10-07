import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/finance_account.dart';
import '../models/finance_cheque.dart';
import '../models/finance_transaction.dart';
import 'finance_repository.dart';

/// اتصال فاکتورهای صادرشده به «حساب مالی فروش کالا».
///
/// قواعد:
/// - فقط «کالا» وارد حساب می‌شود؛ سهم خدمات هیچ اثری ندارد. این شامل
///   ردیف‌های کالا داخل فاکتور خدماتی (برق/مکانیک/جلوبندی) هم می‌شود؛ در
///   این فاکتورها هزینه‌ی جانبی وارد حساب کالا نمی‌شود.
/// - فاکتور فروش کالا (SL) همیشه ورودی می‌سازد. فاکتور خرید کالا (PR) فقط
///   وقتی خروجی می‌سازد که تیک «پرداخت از حساب فروش کالا» روشن باشد.
/// - هزینه‌های جانبی فروش = ورودی (سایر درآمدها)، خرید = خروجی (هزینه متفرقه).
/// - پرداخت با چک تا وصول وارد مانده نمی‌شود؛ فقط یک ردیف «چک در انتظار» ثبت
///   می‌شود و با [collectCheque] تراکنش‌های واقعی ساخته می‌شوند.
/// - اگر حساب تعریف نشده یا تاریخ فاکتور قبل از شروع حساب باشد، هیچ اثری ثبت
///   نمی‌شود (بی‌صدا).
/// - پیش‌فاکتور هیچ اثر مالی ندارد؛ اثر هنگام تبدیل به فاکتور اصلی ثبت می‌شود.
///
/// همه‌ی متدهای [Transaction] باید داخل همان تراکنش sqflite صدور فاکتور صدا
/// زده شوند تا یا همه چیز ثبت شود یا هیچ‌چیز.
class FinanceInvoicePosting {
  FinanceInvoicePosting._();

  static Future<FinanceAccount?> _account(DatabaseExecutor db) async {
    final rows = await db.query('finance_accounts',
        where: 'account_type = ?',
        whereArgs: [FinanceAccount.typeGoodsSales],
        orderBy: 'id ASC',
        limit: 1);
    return rows.isEmpty ? null : FinanceAccount.fromMap(rows.first);
  }

  static Future<double> _goodsTotal(DatabaseExecutor db, int invoiceId) async {
    final r = await db.rawQuery(
        "SELECT SUM(total) t FROM invoice_items WHERE invoice_id = ? AND item_type = 'product'",
        [invoiceId]);
    final v = r.first['t'];
    return v == null ? 0.0 : (v as num).toDouble();
  }

  static Future<String?> _customerName(DatabaseExecutor db, int? customerId) async {
    if (customerId == null) return null;
    final rows = await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (rows.isEmpty) return null;
    final n = (rows.first['name'] as String?)?.trim() ?? '';
    return n.isEmpty ? null : n;
  }

  static Map<String, Object?> _txMap({
    required int accountId,
    required DateTime at,
    required FinanceTxType type,
    required double amount,
    required String description,
    required int invoiceId,
    required String invoiceNumber,
    String? counterparty,
  }) {
    return {
      'account_id': accountId,
      'occurred_at': at.toIso8601String(),
      'tx_type': type.key,
      'direction': type.direction.dbValue,
      'amount': amount,
      'description': description,
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
      'counterparty': counterparty,
      'notes': null,
      'reverses_id': null,
      'correction_reason': null,
      'backup_uid': FinanceRepository.generateUid(),
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  /// ثبت تراکنش‌های واقعی یک فاکتور: یک تراکنش برای سهم کالا + یک تراکنش
  /// برای هر هزینه‌ی جانبی. شناسه‌ی اولین تراکنش (سهم کالا) را برمی‌گرداند.
  static Future<int> _postEntries(
    Transaction txn, {
    required int accountId,
    required Map<String, Object?> inv,
    required bool isSale,
    required double goods,
    required List<Map<String, Object?>> sides,
    required DateTime at,
  }) async {
    final invoiceId = inv['id'] as int;
    final number = (inv['invoice_number'] as String?) ?? '';
    final counterparty = await _customerName(txn, inv['customer_id'] as int?);

    final goodsType = isSale ? FinanceTxType.saleReceipt : FinanceTxType.purchasePayment;
    final sideType = isSale ? FinanceTxType.otherIncome : FinanceTxType.miscShopCost;

    final firstId = await txn.insert(
      'finance_transactions',
      _txMap(
        accountId: accountId,
        at: at,
        type: goodsType,
        amount: goods,
        description: '${isSale ? 'فروش کالا' : 'خرید کالا'} - $number',
        invoiceId: invoiceId,
        invoiceNumber: number,
        counterparty: counterparty,
      ),
    );

    for (final s in sides) {
      final amount = (s['amount'] as num?)?.toDouble() ?? 0.0;
      if (amount <= 0) continue;
      final title = (s['title'] as String?)?.trim() ?? '';
      await txn.insert(
        'finance_transactions',
        _txMap(
          accountId: accountId,
          at: at,
          type: sideType,
          amount: amount,
          description: 'هزینه جانبی فاکتور $number${title.isEmpty ? '' : ': $title'}',
          invoiceId: invoiceId,
          invoiceNumber: number,
          counterparty: counterparty,
        ),
      );
    }
    return firstId;
  }

  /// بعد از صدور فاکتور اصلی (یا تبدیل پیش‌فاکتور) صدا زده می‌شود.
  static Future<void> onInvoiceIssued(Transaction txn, {required int invoiceId}) async {
    final rows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (rows.isEmpty) return;
    final inv = rows.first;
    if ((inv['is_draft'] as int? ?? 0) == 1) return;

    final type = inv['type'] as String?;
    final isPurchase = type == 'productPurchase';
    // فاکتور خدماتی که داخلش کالا هم هست: فقط سهم کالا مثل فروش وارد حساب می‌شود.
    final isServiceType = type == 'electrical' || type == 'mechanic' || type == 'suspension';
    final isSale = type == 'productSale' || isServiceType;
    if (!isSale && !isPurchase) return;
    if (isPurchase && (inv['finance_pay'] as int? ?? 0) != 1) return;

    final account = await _account(txn);
    if (account == null) return;
    final issuedAt = DateTime.tryParse((inv['issue_date'] as String?) ?? '');
    if (issuedAt == null || issuedAt.isBefore(account.startDateTime)) return;

    // جلوگیری از ثبت دوباره‌ی همان فاکتور.
    final dupTx =
        await txn.query('finance_transactions', where: 'invoice_id = ?', whereArgs: [invoiceId], limit: 1);
    if (dupTx.isNotEmpty) return;
    final dupChq =
        await txn.query('finance_cheques', where: 'invoice_id = ?', whereArgs: [invoiceId], limit: 1);
    if (dupChq.isNotEmpty) return;

    final goods = await _goodsTotal(txn, invoiceId);
    if (goods <= 0) return;
    final sides = isServiceType
        ? <Map<String, Object?>>[]
        : await txn.query('side_costs', where: 'invoice_id = ?', whereArgs: [invoiceId]);

    if (inv['payment_type'] == 'nonCash') {
      var total = goods;
      for (final s in sides) {
        total += (s['amount'] as num?)?.toDouble() ?? 0.0;
      }
      await txn.insert('finance_cheques', {
        'account_id': account.id,
        'invoice_id': invoiceId,
        'invoice_number': inv['invoice_number'],
        'direction': (isSale ? FinanceDirection.inflow : FinanceDirection.outflow).dbValue,
        'amount': total,
        'due_date': inv['check_due_date'],
        'status': FinanceCheque.statusPending,
        'collected_tx_id': null,
        'backup_uid': FinanceRepository.generateUid().replaceFirst('fin-', 'chq-'),
        'created_at': DateTime.now().toIso8601String(),
      });
      return;
    }

    await _postEntries(txn,
        accountId: account.id!, inv: inv, isSale: isSale, goods: goods, sides: sides, at: issuedAt);
  }

  // ==================== چک‌ها ====================

  static Future<List<FinanceCheque>> listCheques({String? status}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'finance_cheques',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status],
      orderBy: 'due_date ASC, id ASC',
    );
    return rows.map((r) => FinanceCheque.fromMap(r)).toList();
  }

  /// وصول چک: تراکنش‌های واقعی فاکتور با تاریخ وصول در دفتر ثبت می‌شوند و
  /// چک به وضعیت «وصول‌شده» می‌رود. همه در یک تراکنش دیتابیس.
  static Future<int> collectCheque({required int chequeId, required DateTime collectedAt}) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) async {
      final rows = await txn.query('finance_cheques', where: 'id = ?', whereArgs: [chequeId], limit: 1);
      if (rows.isEmpty) throw StateError('چک یافت نشد');
      final cheque = FinanceCheque.fromMap(rows.first);
      if (!cheque.isPending) throw StateError('این چک قبلاً وصول شده است');

      final accRows =
          await txn.query('finance_accounts', where: 'id = ?', whereArgs: [cheque.accountId], limit: 1);
      if (accRows.isEmpty) throw StateError('حساب مالی یافت نشد');
      final account = FinanceAccount.fromMap(accRows.first);
      if (collectedAt.isBefore(account.startDateTime)) {
        throw StateError('تاریخ وصول نمی‌تواند قبل از تاریخ شروع حساب باشد');
      }

      final invRows = cheque.invoiceId == null
          ? <Map<String, Object?>>[]
          : await txn.query('invoices', where: 'id = ?', whereArgs: [cheque.invoiceId], limit: 1);
      if (invRows.isEmpty) throw StateError('فاکتور این چک یافت نشد');
      final inv = invRows.first;
      final invType = inv['type'] as String?;
      final isSale = invType != 'productPurchase';
      final isGoodsInvoice = invType == 'productSale' || invType == 'productPurchase';

      final goods = await _goodsTotal(txn, cheque.invoiceId!);
      final sides = isGoodsInvoice
          ? await txn.query('side_costs', where: 'invoice_id = ?', whereArgs: [cheque.invoiceId])
          : <Map<String, Object?>>[];
      final firstId = await _postEntries(txn,
          accountId: account.id!, inv: inv, isSale: isSale, goods: goods, sides: sides, at: collectedAt);

      await txn.update(
        'finance_cheques',
        {'status': FinanceCheque.statusCollected, 'collected_tx_id': firstId},
        where: 'id = ?',
        whereArgs: [chequeId],
      );
      return firstId;
    });
  }
}
