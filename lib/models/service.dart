class ServiceCategory {
  final int? id;
  final String name;
  final int isDeleted;
  final String? codePrefix; // بدون خط تیره، مثل B یا PDR

  ServiceCategory({this.id, required this.name, this.isDeleted = 0, this.codePrefix});

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'is_deleted': isDeleted, 'code_prefix': codePrefix};

  factory ServiceCategory.fromMap(Map<String, dynamic> map) => ServiceCategory(
        id: map['id'] as int?,
        name: map['name'] as String,
        isDeleted: map['is_deleted'] as int? ?? 0,
        codePrefix: map['code_prefix'] as String?,
      );
}

/// مجموعه خدمات: سطح میانی بین دسته‌بندی و خدمت (دسته ← مجموعه ← خدمت).
/// nameKey نام نرمال‌شده است و فقط برای جلوگیری از نام تکراری در یک دسته به‌کار می‌رود.
class ServiceGroup {
  final int? id;
  final int categoryId;
  final String name;
  final String nameKey;
  final int sortOrder;
  final int isActive;

  ServiceGroup({
    this.id,
    required this.categoryId,
    required this.name,
    this.nameKey = '',
    this.sortOrder = 0,
    this.isActive = 1,
  });

  bool get active => isActive == 1;

  Map<String, dynamic> toMap() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'name_key': nameKey,
        'sort_order': sortOrder,
        'is_active': isActive,
      };

  factory ServiceGroup.fromMap(Map<String, dynamic> map) => ServiceGroup(
        id: map['id'] as int?,
        categoryId: map['category_id'] as int,
        name: map['name'] as String,
        nameKey: (map['name_key'] as String?) ?? '',
        sortOrder: map['sort_order'] as int? ?? 0,
        isActive: map['is_active'] as int? ?? 1,
      );
}

/// هر خدمت اکنون تک‌قیمت است (نه سه‌نرخی). قیمت با ویرایش تغییر می‌کند
/// اما تاریخچه‌ی قیمت‌های قبلی در جدول service_price_history نگه داشته می‌شود.
/// برند/مدل خودرو اختیاری است: اگر مشخص شود، این قیمت فقط برای آن برند/مدل معتبر است؛
/// در غیر این صورت قیمت برای همه‌ی خودروها یکسان است.
/// serviceGroupId اختیاری است؛ خدمات قدیمی بدون مجموعه (null) می‌مانند.
class ServiceItem {
  final int? id;
  final String name;
  final String code;
  final int categoryId;
  final int? brandId;
  final int? modelId;
  final int? serviceGroupId;
  final double price;
  final String? notes;
  final String? voiceSearchLabel;
  final int isActive;
  final int isDeleted;

  ServiceItem({
    this.id,
    required this.name,
    required this.code,
    required this.categoryId,
    this.brandId,
    this.modelId,
    this.serviceGroupId,
    required this.price,
    this.notes,
    this.voiceSearchLabel,
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
        'service_group_id': serviceGroupId,
        'price': price,
        'notes': notes,
        'voice_search_label': voiceSearchLabel,
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
        serviceGroupId: map['service_group_id'] as int?,
        price: (map['price'] as num).toDouble(),
        notes: map['notes'] as String?,
        voiceSearchLabel: map['voice_search_label'] as String?,
        isActive: map['is_active'] as int? ?? 1,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );

  ServiceItem copyWith({double? price, String? voiceSearchLabel}) => ServiceItem(
        id: id,
        name: name,
        code: code,
        categoryId: categoryId,
        brandId: brandId,
        modelId: modelId,
        serviceGroupId: serviceGroupId,
        price: price ?? this.price,
        notes: notes,
        voiceSearchLabel: voiceSearchLabel ?? this.voiceSearchLabel,
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
