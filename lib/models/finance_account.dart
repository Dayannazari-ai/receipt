/// حساب مالی (فعلاً فقط «حساب مالی فروش کالا»). ستون account_type برای
/// حساب‌های آینده (خدمات، بانکی، صندوق نقدی) رزرو شده است.
///
/// موجودی اولیه اینجا ذخیره نمی‌شود؛ فقط به‌عنوان اولین تراکنش دفتر ثبت
/// می‌شود. مانده‌ی حساب هم هرگز ذخیره نمی‌شود.
class FinanceAccount {
  static const String typeGoodsSales = 'goods_sales';

  final int? id;
  final String name;
  final String accountType;
  final String? cardNumber;
  final String startDate; // ISO، ابتدای روز شروع
  final String? notes;
  final String createdAt;

  FinanceAccount({
    this.id,
    required this.name,
    this.accountType = typeGoodsSales,
    this.cardNumber,
    required this.startDate,
    this.notes,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  DateTime get startDateTime => DateTime.tryParse(startDate) ?? DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'account_type': accountType,
        'card_number': cardNumber,
        'start_date': startDate,
        'notes': notes,
        'created_at': createdAt,
      };

  factory FinanceAccount.fromMap(Map<String, dynamic> map) => FinanceAccount(
        id: map['id'] as int?,
        name: map['name'] as String,
        accountType: (map['account_type'] as String?) ?? typeGoodsSales,
        cardNumber: map['card_number'] as String?,
        startDate: map['start_date'] as String,
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String?,
      );
}
