/// شماره کارت / شبا / حساب‌های تعمیرگاه که هنگام صدور فاکتور قابل انتخاب هستند.
class PaymentAccount {
  final int? id;
  final String title; // مثلا "کارت ملی بانک X"
  final String number; // شماره کارت یا شبا
  final int isDeleted;

  PaymentAccount({this.id, required this.title, required this.number, this.isDeleted = 0});

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'number': number,
        'is_deleted': isDeleted,
      };

  factory PaymentAccount.fromMap(Map<String, dynamic> map) => PaymentAccount(
        id: map['id'] as int?,
        title: map['title'] as String,
        number: map['number'] as String,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );
}
