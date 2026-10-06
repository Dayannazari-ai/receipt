import 'dart:math';
import '../database/database_helper.dart';
import '../models/finance_account.dart';
import '../models/finance_transaction.dart';

/// متن خطای قابل‌نمایش به کاربر (بدون پیشوند «Bad state»).
String financeErrorText(Object e) => e is StateError ? e.message : e.toString();

/// دفتر مالی «حساب مالی فروش کالا».
///
/// قواعد:
/// - مانده هرگز ذخیره نمی‌شود؛ همیشه از روی تراکنش‌ها محاسبه می‌شود.
/// - تراکنش ثبت‌شده ویرایش یا حذف نمی‌شود. اصلاح فقط با «تراکنش معکوس» و
///   ثبت دلیل انجام می‌شود.
/// - موجودی اولیه فقط به‌صورت اولین تراکنش دفتر ثبت می‌شود.
class FinanceRepository {
  final _db = DatabaseHelper.instance;
  static final Random _random = Random();

  /// شناسه‌ی پایدار یکتا برای هر تراکنش (برای Backup/Restore).
  static String generateUid() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final rnd = _random.nextInt(0x7FFFFFFF);
    return 'fin-${micros.toRadixString(36)}-${rnd.toRadixString(36)}';
  }

  Map<String, Object?> _newTxMap({
    required int accountId,
    required DateTime occurredAt,
    required String txType,
    required FinanceDirection direction,
    required double amount,
    required String description,
    String? invoiceNumber,
    String? counterparty,
    String? notes,
    int? reversesId,
    String? correctionReason,
  }) {
    final now = DateTime.now().toIso8601String();
    return {
      'account_id': accountId,
      'occurred_at': occurredAt.toIso8601String(),
      'tx_type': txType,
      'direction': direction.dbValue,
      'amount': amount,
      'description': description,
      'invoice_id': null,
      'invoice_number': invoiceNumber,
      'counterparty': counterparty,
      'notes': notes,
      'reverses_id': reversesId,
      'correction_reason': correctionReason,
      'backup_uid': generateUid(),
      'created_at': now,
    };
  }

  String? _clean(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  bool _badAmount(double a) => a.isNaN || a.isInfinite;

  // ==================== حساب ====================

  Future<FinanceAccount?> getGoodsSalesAccount() async {
    final db = await _db.database;
    final rows = await db.query('finance_accounts',
        where: 'account_type = ?',
        whereArgs: [FinanceAccount.typeGoodsSales],
        orderBy: 'id ASC',
        limit: 1);
    return rows.isEmpty ? null : FinanceAccount.fromMap(rows.first);
  }

  /// تعریف حساب فروش کالا + ثبت موجودی اولیه به‌عنوان اولین تراکنش، هر دو
  /// در یک تراکنش دیتابیس (یا هر دو انجام می‌شوند یا هیچ‌کدام).
  Future<int> createGoodsSalesAccount({
    required String name,
    String? cardNumber,
    required DateTime startDate,
    String? notes,
    required double openingBalance,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw StateError('نام حساب را وارد کنید');
    if (_badAmount(openingBalance) || openingBalance < 0) {
      throw StateError('موجودی اولیه معتبر نیست');
    }
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final db = await _db.database;
    return db.transaction((txn) async {
      final existing = await txn.query('finance_accounts',
          where: 'account_type = ?', whereArgs: [FinanceAccount.typeGoodsSales], limit: 1);
      if (existing.isNotEmpty) throw StateError('حساب مالی فروش کالا قبلاً تعریف شده است');

      final accountId = await txn.insert('finance_accounts', {
        'name': cleanName,
        'account_type': FinanceAccount.typeGoodsSales,
        'card_number': _clean(cardNumber),
        'start_date': start.toIso8601String(),
        'notes': _clean(notes),
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.insert(
        'finance_transactions',
        _newTxMap(
          accountId: accountId,
          occurredAt: start,
          txType: FinanceTxType.openingBalance.key,
          direction: FinanceDirection.inflow,
          amount: openingBalance,
          description: 'موجودی اولیه حساب',
        ),
      );
      return accountId;
    });
  }

  /// فقط نام، شماره کارت و توضیحات قابل ویرایش‌اند. تاریخ شروع و موجودی
  /// اولیه از این مسیر تغییر نمی‌کنند (موجودی اولیه فقط با اصلاحیه).
  Future<void> updateAccountInfo({
    required int id,
    required String name,
    String? cardNumber,
    String? notes,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw StateError('نام حساب را وارد کنید');
    final db = await _db.database;
    await db.update(
      'finance_accounts',
      {'name': cleanName, 'card_number': _clean(cardNumber), 'notes': _clean(notes)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== ثبت تراکنش ====================

  /// ثبت موجودی اولیه (فقط وقتی هیچ موجودی اولیه‌ی فعال، یعنی اصلاح‌نشده،
  /// وجود ندارد؛ مثلاً بعد از اصلاح موجودی اولیه‌ی قبلی).
  Future<int> addOpeningBalance({required int accountId, required double amount}) async {
    if (_badAmount(amount) || amount < 0) throw StateError('موجودی اولیه معتبر نیست');
    final db = await _db.database;
    return db.transaction((txn) async {
      final acc = await txn.query('finance_accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
      if (acc.isEmpty) throw StateError('حساب مالی یافت نشد');
      final active = await txn.rawQuery(
        'SELECT t.id FROM finance_transactions t '
        'WHERE t.account_id = ? AND t.tx_type = ? '
        'AND NOT EXISTS (SELECT 1 FROM finance_transactions r WHERE r.reverses_id = t.id)',
        [accountId, FinanceTxType.openingBalance.key],
      );
      if (active.isNotEmpty) {
        throw StateError('موجودی اولیه‌ی فعال وجود دارد. برای تغییر، ابتدا آن را اصلاح کنید.');
      }
      final account = FinanceAccount.fromMap(acc.first);
      return txn.insert(
        'finance_transactions',
        _newTxMap(
          accountId: accountId,
          occurredAt: account.startDateTime,
          txType: FinanceTxType.openingBalance.key,
          direction: FinanceDirection.inflow,
          amount: amount,
          description: 'موجودی اولیه حساب',
        ),
      );
    });
  }

  /// ثبت دستی یک ورودی یا خروجی. جهت از روی نوع تراکنش تعیین می‌شود.
  Future<int> addTransaction({
    required int accountId,
    required FinanceTxType type,
    required double amount,
    required DateTime occurredAt,
    String? description,
    String? invoiceNumber,
    String? counterparty,
    String? notes,
  }) async {
    if (!type.manual) throw StateError('این نوع تراکنش از این مسیر قابل ثبت نیست');
    if (_badAmount(amount) || amount <= 0) throw StateError('مبلغ باید بیشتر از صفر باشد');
    final db = await _db.database;
    return db.transaction((txn) async {
      final acc = await txn.query('finance_accounts', where: 'id = ?', whereArgs: [accountId], limit: 1);
      if (acc.isEmpty) throw StateError('حساب مالی یافت نشد');
      final account = FinanceAccount.fromMap(acc.first);
      if (occurredAt.isBefore(account.startDateTime)) {
        throw StateError('تاریخ تراکنش نمی‌تواند قبل از تاریخ شروع حساب باشد');
      }
      return txn.insert(
        'finance_transactions',
        _newTxMap(
          accountId: accountId,
          occurredAt: occurredAt,
          txType: type.key,
          direction: type.direction,
          amount: amount,
          description: _clean(description) ?? type.label,
          invoiceNumber: _clean(invoiceNumber),
          counterparty: _clean(counterparty),
          notes: _clean(notes),
        ),
      );
    });
  }

  /// اصلاح یک تراکنش با ثبت تراکنش معکوس هم‌مبلغ و خلاف‌جهت + دلیل اصلاح.
  /// تراکنش اصلی دست‌نخورده می‌ماند. هر تراکنش فقط یک بار قابل اصلاح است و
  /// خود اصلاحیه قابل اصلاح نیست. برای اصلاح مبلغ، بعد از اصلاحیه تراکنش
  /// درست را جدید ثبت کنید.
  Future<int> reverseTransaction({required int txId, required String reason}) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw StateError('دلیل اصلاح را وارد کنید');
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query('finance_transactions', where: 'id = ?', whereArgs: [txId], limit: 1);
      if (rows.isEmpty) throw StateError('تراکنش یافت نشد');
      final orig = FinanceTransaction.fromMap(rows.first);
      if (orig.isReversal) throw StateError('اصلاحیه را نمی‌توان دوباره اصلاح کرد');
      final already =
          await txn.query('finance_transactions', where: 'reverses_id = ?', whereArgs: [txId], limit: 1);
      if (already.isNotEmpty) throw StateError('این تراکنش قبلاً اصلاح شده است');

      final now = DateTime.now();
      final at = now.isBefore(orig.dateTime) ? orig.dateTime : now;
      return txn.insert(
        'finance_transactions',
        _newTxMap(
          accountId: orig.accountId,
          occurredAt: at,
          txType: FinanceTxType.reversal.key,
          direction: orig.direction.opposite,
          amount: orig.amount,
          description: 'اصلاحیه: ${orig.description}',
          invoiceNumber: orig.invoiceNumber,
          counterparty: orig.counterparty,
          reversesId: orig.id,
          correctionReason: cleanReason,
        ),
      );
    });
  }

  // ==================== خواندن دفتر ====================

  /// کل دفتر یک حساب، به ترتیب زمانی صعودی، با موجودی قبل/بعد هر سطر که
  /// همین‌جا از روی تراکنش‌ها محاسبه می‌شود (هیچ مانده‌ای ذخیره نشده است).
  Future<List<FinanceLedgerRow>> loadLedger(int accountId) async {
    final db = await _db.database;
    final rows = await db.query('finance_transactions',
        where: 'account_id = ?', whereArgs: [accountId], orderBy: 'id ASC');
    final txs = rows.map((r) => FinanceTransaction.fromMap(r)).toList();
    txs.sort((a, b) {
      final c = a.dateTime.compareTo(b.dateTime);
      if (c != 0) return c;
      final ao = a.isOpening ? 0 : 1;
      final bo = b.isOpening ? 0 : 1;
      if (ao != bo) return ao.compareTo(bo);
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    final reversedIds = <int>{
      for (final t in txs)
        if (t.reversesId != null) t.reversesId!,
    };
    var running = 0.0;
    final out = <FinanceLedgerRow>[];
    for (final t in txs) {
      final before = running;
      running += t.signedAmount;
      out.add(FinanceLedgerRow(
        tx: t,
        balanceBefore: before,
        balanceAfter: running,
        isReversed: t.id != null && reversedIds.contains(t.id),
      ));
    }
    return out;
  }
}
