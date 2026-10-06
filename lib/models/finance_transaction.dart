/// جهت تراکنش: ورود پول به حساب یا خروج پول از حساب.
enum FinanceDirection { inflow, outflow }

extension FinanceDirectionX on FinanceDirection {
  String get dbValue => this == FinanceDirection.inflow ? 'in' : 'out';
  String get label => this == FinanceDirection.inflow ? 'ورود' : 'خروج';
  FinanceDirection get opposite =>
      this == FinanceDirection.inflow ? FinanceDirection.outflow : FinanceDirection.inflow;
  static FinanceDirection fromDb(String? v) => v == 'out' ? FinanceDirection.outflow : FinanceDirection.inflow;
}

/// نوع تراکنش. هر تراکنش باید یک نوع مشخص داشته باشد.
/// [manual] یعنی کاربر می‌تواند آن را دستی ثبت کند. «موجودی اولیه» و
/// «اصلاحیه» فقط از مسیر مخصوص خودشان ثبت می‌شوند.
class FinanceTxType {
  final String key;
  final String label;
  final FinanceDirection direction;
  final bool manual;
  const FinanceTxType._(this.key, this.label, this.direction, this.manual);

  // ---- ورودی ----
  static const openingBalance =
      FinanceTxType._('opening_balance', 'موجودی اولیه', FinanceDirection.inflow, false);
  static const saleReceipt =
      FinanceTxType._('sale_receipt', 'دریافت بابت فروش کالا', FinanceDirection.inflow, true);
  static const deposit =
      FinanceTxType._('deposit', 'واریز به حساب فروش کالا', FinanceDirection.inflow, true);
  static const refundIn =
      FinanceTxType._('refund_in', 'برگشت وجه به حساب', FinanceDirection.inflow, true);
  static const otherIncome =
      FinanceTxType._('other_income', 'سایر درآمدهای مرتبط با فروشگاه', FinanceDirection.inflow, true);

  // ---- خروجی ----
  static const purchasePayment =
      FinanceTxType._('purchase_payment', 'پرداخت بابت خرید کالا', FinanceDirection.outflow, true);
  static const shippingCost =
      FinanceTxType._('shipping_cost', 'هزینه حمل', FinanceDirection.outflow, true);
  static const packagingCost =
      FinanceTxType._('packaging_cost', 'هزینه بسته‌بندی', FinanceDirection.outflow, true);
  static const miscShopCost =
      FinanceTxType._('misc_shop_cost', 'هزینه متفرقه فروشگاه', FinanceDirection.outflow, true);
  static const withdrawal =
      FinanceTxType._('withdrawal', 'برداشت از حساب فروش کالا', FinanceDirection.outflow, true);
  static const transferOut =
      FinanceTxType._('transfer_out', 'انتقال وجه از حساب فروش کالا', FinanceDirection.outflow, true);
  static const otherExpense =
      FinanceTxType._('other_expense', 'سایر هزینه‌های مرتبط', FinanceDirection.outflow, true);

  // ---- اصلاحیه (جهت آن همیشه برعکس تراکنش اصلی است) ----
  static const reversal =
      FinanceTxType._('reversal', 'اصلاحیه (تراکنش معکوس)', FinanceDirection.outflow, false);

  static final List<FinanceTxType> manualInflow = [saleReceipt, deposit, refundIn, otherIncome];
  static final List<FinanceTxType> manualOutflow = [
    purchasePayment,
    shippingCost,
    packagingCost,
    miscShopCost,
    withdrawal,
    transferOut,
    otherExpense,
  ];
  static final List<FinanceTxType> all = [
    openingBalance,
    ...manualInflow,
    ...manualOutflow,
    reversal,
  ];

  static FinanceTxType fromKey(String key) {
    for (final t in all) {
      if (t.key == key) return t;
    }
    // نوع ناشناخته (مثلاً از نسخه‌ی جدیدتر برنامه): برچسب همان کلید.
    return FinanceTxType._(key, key, FinanceDirection.inflow, false);
  }
}

class FinanceTransaction {
  final int? id;
  final int accountId;
  final String occurredAt; // ISO
  final String txType;
  final FinanceDirection direction;
  final double amount; // همیشه مثبت؛ جهت از direction می‌آید
  final String description;
  final int? invoiceId;
  final String? invoiceNumber;
  final String? counterparty;
  final String? notes;
  final int? reversesId; // اگر این تراکنش اصلاحیه است: شناسه‌ی تراکنش اصلاح‌شده
  final String? correctionReason;
  final String backupUid;
  final String createdAt;

  FinanceTransaction({
    this.id,
    required this.accountId,
    required this.occurredAt,
    required this.txType,
    required this.direction,
    required this.amount,
    this.description = '',
    this.invoiceId,
    this.invoiceNumber,
    this.counterparty,
    this.notes,
    this.reversesId,
    this.correctionReason,
    this.backupUid = '',
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  double get signedAmount => direction == FinanceDirection.inflow ? amount : -amount;
  bool get isReversal => txType == FinanceTxType.reversal.key;
  bool get isOpening => txType == FinanceTxType.openingBalance.key;
  FinanceTxType get type => FinanceTxType.fromKey(txType);
  DateTime get dateTime => DateTime.tryParse(occurredAt) ?? DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> toMap() => {
        'id': id,
        'account_id': accountId,
        'occurred_at': occurredAt,
        'tx_type': txType,
        'direction': direction.dbValue,
        'amount': amount,
        'description': description,
        'invoice_id': invoiceId,
        'invoice_number': invoiceNumber,
        'counterparty': counterparty,
        'notes': notes,
        'reverses_id': reversesId,
        'correction_reason': correctionReason,
        'backup_uid': backupUid,
        'created_at': createdAt,
      };

  factory FinanceTransaction.fromMap(Map<String, dynamic> map) => FinanceTransaction(
        id: map['id'] as int?,
        accountId: map['account_id'] as int,
        occurredAt: map['occurred_at'] as String,
        txType: map['tx_type'] as String,
        direction: FinanceDirectionX.fromDb(map['direction'] as String?),
        amount: (map['amount'] as num).toDouble(),
        description: (map['description'] as String?) ?? '',
        invoiceId: map['invoice_id'] as int?,
        invoiceNumber: map['invoice_number'] as String?,
        counterparty: map['counterparty'] as String?,
        notes: map['notes'] as String?,
        reversesId: map['reverses_id'] as int?,
        correctionReason: map['correction_reason'] as String?,
        backupUid: (map['backup_uid'] as String?) ?? '',
        createdAt: map['created_at'] as String?,
      );
}

/// یک سطر دفتر: تراکنش + موجودی قبل و بعد از آن. این دو مقدار هرگز
/// ذخیره نمی‌شوند و هر بار از روی کل دفتر محاسبه می‌شوند.
class FinanceLedgerRow {
  final FinanceTransaction tx;
  final double balanceBefore;
  final double balanceAfter;

  /// آیا این تراکنش قبلاً با یک اصلاحیه معکوس شده است؟
  final bool isReversed;

  const FinanceLedgerRow({
    required this.tx,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.isReversed,
  });
}

/// خلاصه‌ی حساب، محاسبه‌شده از سطرهای دفتر (به ترتیب زمانی صعودی).
/// «موجودی اولیه» شامل تراکنش موجودی اولیه و اصلاحیه‌های آن است؛ بنابراین
/// همیشه: موجودی فعلی = موجودی اولیه + مجموع ورودی‌ها − مجموع خروجی‌ها.
class FinanceSummary {
  final double opening;
  final double totalIn;
  final double totalOut;
  final double balance;

  const FinanceSummary({
    required this.opening,
    required this.totalIn,
    required this.totalOut,
    required this.balance,
  });

  double get net => totalIn - totalOut;

  factory FinanceSummary.fromRows(List<FinanceLedgerRow> rows) {
    final openingIds = <int>{
      for (final r in rows)
        if (r.tx.isOpening && r.tx.id != null) r.tx.id!,
    };
    var opening = 0.0;
    var totalIn = 0.0;
    var totalOut = 0.0;
    for (final r in rows) {
      final t = r.tx;
      final relatedToOpening = t.isOpening || (t.reversesId != null && openingIds.contains(t.reversesId));
      if (relatedToOpening) {
        opening += t.signedAmount;
      } else if (t.direction == FinanceDirection.inflow) {
        totalIn += t.amount;
      } else {
        totalOut += t.amount;
      }
    }
    final balance = rows.isEmpty ? 0.0 : rows.last.balanceAfter;
    return FinanceSummary(opening: opening, totalIn: totalIn, totalOut: totalOut, balance: balance);
  }
}
