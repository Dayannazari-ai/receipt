/// خودروی متعلق به یک مشتری. هر مشتری می‌تواند چند خودرو داشته باشد.
/// برند/مدل به همان جدول‌های مرجع موجود (VehicleBrand/VehicleModel) اشاره
/// می‌کنند تا داده‌ی تکراری ساخته نشود.
class Vehicle {
  final int? id;
  final int customerId;
  final int? brandId;
  final int? modelId;
  final String? plateNumber;
  final String? notes;
  final int isDeleted;
  final String createdAt;

  Vehicle({
    this.id,
    required this.customerId,
    this.brandId,
    this.modelId,
    this.plateNumber,
    this.notes,
    this.isDeleted = 0,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'customer_id': customerId,
        'brand_id': brandId,
        'model_id': modelId,
        'plate_number': plateNumber,
        'notes': notes,
        'is_deleted': isDeleted,
        'created_at': createdAt,
      };

  factory Vehicle.fromMap(Map<String, dynamic> map) => Vehicle(
        id: map['id'] as int?,
        customerId: map['customer_id'] as int,
        brandId: map['brand_id'] as int?,
        modelId: map['model_id'] as int?,
        plateNumber: map['plate_number'] as String?,
        notes: map['notes'] as String?,
        isDeleted: map['is_deleted'] as int? ?? 0,
        createdAt: map['created_at'] as String?,
      );

  Vehicle copyWith({
    int? brandId,
    int? modelId,
    String? plateNumber,
    String? notes,
  }) =>
      Vehicle(
        id: id,
        customerId: customerId,
        brandId: brandId ?? this.brandId,
        modelId: modelId ?? this.modelId,
        plateNumber: plateNumber ?? this.plateNumber,
        notes: notes ?? this.notes,
        isDeleted: isDeleted,
        createdAt: createdAt,
      );
}
