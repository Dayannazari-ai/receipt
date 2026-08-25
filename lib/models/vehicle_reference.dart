/// جدول مرجع برند خودرو - فقط برای انتخاب سریع (کلیکی) هنگام قیمت‌گذاری خدمات.
/// هیچ پرونده یا سابقه‌ای برای خودروی مشتری نگه‌داری نمی‌شود.
class VehicleBrand {
  final int? id;
  final String name;

  VehicleBrand({this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory VehicleBrand.fromMap(Map<String, dynamic> map) =>
      VehicleBrand(id: map['id'] as int?, name: map['name'] as String);
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
