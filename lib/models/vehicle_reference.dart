/// جدول مرجع برند خودرو - فقط برای انتخاب سریع (کلیکی) هنگام قیمت‌گذاری خدمات.
/// هیچ پرونده یا سابقه‌ای برای خودروی مشتری نگه‌داری نمی‌شود.
class VehicleBrand {
  final int? id;
  final String name;
  final int isDeleted;

  VehicleBrand({this.id, required this.name, this.isDeleted = 0});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'is_deleted': isDeleted};

  factory VehicleBrand.fromMap(Map<String, dynamic> map) => VehicleBrand(
        id: map['id'] as int?,
        name: map['name'] as String,
        isDeleted: map['is_deleted'] as int? ?? 0,
      );
}

/// مدل خودرو، وابسته به یک برند.
class VehicleModel {
  final int? id;
  final int brandId;
  final String name;

  VehicleModel({this.id, required this.brandId, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'brand_id': brandId, 'name': name};

  factory VehicleModel.fromMap(Map<String, dynamic> map) => VehicleModel(
        id: map['id'] as int?,
        brandId: map['brand_id'] as int,
        name: map['name'] as String,
      );
}
