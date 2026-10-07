/// هزینه‌ی خدماتی (خرید قطعات تعمیرات، ابزار و ...). ثبت دستی و مستقل از
/// حساب فروش کالا.
class ServiceExpense {
  final int? id;
  final String expenseDate; // ISO
  final String title;
  final double amount; // همیشه مثبت
  final String category; // part / tool / other
  final String? notes;
  final String backupUid;
  final String createdAt;

  ServiceExpense({
    this.id,
    required this.expenseDate,
    required this.title,
    required this.amount,
    this.category = 'other',
    this.notes,
    this.backupUid = '',
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  static const Map<String, String> categories = {
    'part': 'قطعه',
    'tool': 'ابزار',
    'other': 'سایر',
  };

  static String categoryLabel(String key) => categories[key] ?? 'سایر';

  DateTime get dateTime => DateTime.tryParse(expenseDate) ?? DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> toMap() => {
        'id': id,
        'expense_date': expenseDate,
        'title': title,
        'amount': amount,
        'category': category,
        'notes': notes,
        'backup_uid': backupUid,
        'created_at': createdAt,
      };

  factory ServiceExpense.fromMap(Map<String, dynamic> map) => ServiceExpense(
        id: map['id'] as int?,
        expenseDate: map['expense_date'] as String,
        title: (map['title'] as String?) ?? '',
        amount: (map['amount'] as num).toDouble(),
        category: (map['category'] as String?) ?? 'other',
        notes: map['notes'] as String?,
        backupUid: (map['backup_uid'] as String?) ?? '',
        createdAt: map['created_at'] as String?,
      );
}
