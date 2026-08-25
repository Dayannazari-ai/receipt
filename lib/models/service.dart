class ServiceCategory {
  final int? id;
  final String name;
  final int isDeleted;

  ServiceCategory({this.id, required this.name, this.isDeleted = 0});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'is_deleted': isDeleted};

  factory ServiceCategory.fromMap(Map<String, dynamic> map) => ServiceCategory(
        id: map['id'] as int?,
        name: map['name'] as String,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );
}

/// هر خدمت اکنون تک‌قیمت است (نه سه‌نرخی). قیمت با ویرایش تغییر می‌کند
/// اما تاریخچه‌ی قیمت‌های قبلی در جدول service_price_history نگه داشته می‌شود.
/// برند/مدل خودرو اختیاری است: اگر مشخص شود، این قیمت فقط برای آن برند/مدل معتبر است؛
/// در غیر این صورت قیمت برای همه‌ی خودروها یکسان است.
class ServiceItem {
  final int? id;
  final String name;
  final String code;
  final int categoryId;
  final int? brandId;
  final int? modelId;
  final double price;
  final String? notes;
  final int isActive;
  final int isDeleted;

  ServiceItem({
    this.id,
    required this.name,
    required this.code,
    required this.categoryId,
    this.brandId,
    this.modelId,
    required this.price,
    this.notes,
    this.isActive = 1,
    this.isDeleted = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'category_id': categoryId,
        'brand_id': brandId,
        'model_id': modelId,
        'price': price,
        'notes': notes,
        'is_active': isActive,
        'is_deleted': isDeleted,
      };

  factory ServiceItem.fromMap(Map<String, dynamic> map) => ServiceItem(
        id: map['id'] as int?,
        name: map['name'] as String,
        code: map['code'] as String,
        categoryId: map['category_id'] as int,
        brandId: map['brand_id'] as int?,
        modelId: map['model_id'] as int?,
        price: (map['price'] as num).toDouble(),
        notes: map['notes'] as String?,
        isActive: map['is_active'] as int? ?? 1,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );

  ServiceItem copyWith({double? price}) => ServiceItem(
        id: id,
        name: name,
        code: code,
        categoryId: categoryId,
        brandId: brandId,
        modelId: modelId,
        price: price ?? this.price,
        notes: notes,
        isActive: isActive,
        isDeleted: isDeleted,
      );
}

class ServicePriceHistory {
  final int? id;
  final int serviceId;
  final double oldPrice;
  final double newPrice;
  final String changedAt;

  ServicePriceHistory({
    this.id,
    required this.serviceId,
    required this.oldPrice,
    required this.newPrice,
    String? changedAt,
  }) : changedAt = changedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'service_id': serviceId,
        'old_price': oldPrice,
        'new_price': newPrice,
        'changed_at': changedAt,
      };

  factory ServicePriceHistory.fromMap(Map<String, dynamic> map) => ServicePriceHistory(
        id: map['id'] as int?,
        serviceId: map['service_id'] as int,
        oldPrice: (map['old_price'] as num).toDouble(),
        newPrice: (map['new_price'] as num).toDouble(),
        changedAt: map['changed_at'] as String?,
      );
}
