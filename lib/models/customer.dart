class Customer {
  final int? id;
  final String name;
  final String mobile;
  final String? notes;
  final String createdAt;
  final int isDeleted;

  Customer({
    this.id,
    required this.name,
    required this.mobile,
    this.notes,
    String? createdAt,
    this.isDeleted = 0,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'mobile': mobile,
        'notes': notes,
        'created_at': createdAt,
        'is_deleted': isDeleted,
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as int?,
        name: map['name'] as String,
        mobile: map['mobile'] as String,
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String?,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );
}
