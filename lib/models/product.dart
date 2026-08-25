class Product {
  final int? id;
  final String name;
  final String code;
  final double purchasePrice;
  final double sellPrice;
  final int stock;
  final int minStock;
  final String? notes;
  final int isDeleted;
  final String createdAt;

  Product({
    this.id,
    required this.name,
    required this.code,
    required this.purchasePrice,
    required this.sellPrice,
    this.stock = 0,
    this.minStock = 0,
    this.notes,
    this.isDeleted = 0,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  bool get isLowStock => stock <= minStock;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'purchase_price': purchasePrice,
        'sell_price': sellPrice,
        'stock': stock,
        'min_stock': minStock,
        'notes': notes,
        'is_deleted': isDeleted,
        'created_at': createdAt,
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as int?,
        name: map['name'] as String,
        code: map['code'] as String,
        purchasePrice: (map['purchase_price'] as num).toDouble(),
        sellPrice: (map['sell_price'] as num).toDouble(),
        stock: map['stock'] as int? ?? 0,
        minStock: map['min_stock'] as int? ?? 0,
        notes: map['notes'] as String?,
        isDeleted: map['is_deleted'] as int? ?? 0,
        createdAt: map['created_at'] as String?,
      );

  Product copyWith({
    String? name,
    String? code,
    double? purchasePrice,
    double? sellPrice,
    int? stock,
    int? minStock,
    String? notes,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        code: code ?? this.code,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        sellPrice: sellPrice ?? this.sellPrice,
        stock: stock ?? this.stock,
        minStock: minStock ?? this.minStock,
        notes: notes ?? this.notes,
        isDeleted: isDeleted,
        createdAt: createdAt,
      );
}
