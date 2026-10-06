import 'finance_transaction.dart';

/// چکِ در انتظار وصول (یا وصول‌شده) که از فاکتور فروش/خرید کالا ساخته شده.
/// تا وصول، هیچ اثری روی مانده‌ی حساب ندارد. با «وصول چک»، تراکنش‌های واقعی
/// در دفتر ثبت می‌شوند و [collectedTxId] به اولین تراکنش اشاره می‌کند.
class FinanceCheque {
  static const String statusPending = 'pending';
  static const String statusCollected = 'collected';

  final int? id;
  final int accountId;
  final int? invoiceId;
  final String? invoiceNumber;
  final FinanceDirection direction; // in = چک دریافتی از مشتری، out = چک پرداختی
  final double amount; // جمع سهم کالا + هزینه‌های جانبی (بدون سهم خدمات)
  final String? dueDate; // ISO
  final String status;
  final int? collectedTxId;
  final String backupUid;
  final String createdAt;

  FinanceCheque({
    this.id,
    required this.accountId,
    this.invoiceId,
    this.invoiceNumber,
    required this.direction,
    required this.amount,
    this.dueDate,
    this.status = statusPending,
    this.collectedTxId,
    this.backupUid = '',
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  bool get isPending => status == statusPending;

  Map<String, dynamic> toMap() => {
        'id': id,
        'account_id': accountId,
        'invoice_id': invoiceId,
        'invoice_number': invoiceNumber,
        'direction': direction.dbValue,
        'amount': amount,
        'due_date': dueDate,
        'status': status,
        'collected_tx_id': collectedTxId,
        'backup_uid': backupUid,
        'created_at': createdAt,
      };

  factory FinanceCheque.fromMap(Map<String, dynamic> map) => FinanceCheque(
        id: map['id'] as int?,
        accountId: map['account_id'] as int,
        invoiceId: map['invoice_id'] as int?,
        invoiceNumber: map['invoice_number'] as String?,
        direction: FinanceDirectionX.fromDb(map['direction'] as String?),
        amount: (map['amount'] as num).toDouble(),
        dueDate: map['due_date'] as String?,
        status: (map['status'] as String?) ?? statusPending,
        collectedTxId: map['collected_tx_id'] as int?,
        backupUid: (map['backup_uid'] as String?) ?? '',
        createdAt: map['created_at'] as String?,
      );
}
