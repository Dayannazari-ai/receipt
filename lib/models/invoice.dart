enum InvoiceType { electrical, mechanic, suspension, productSale, productPurchase }

extension InvoiceTypeX on InvoiceType {
  String get label {
    switch (this) {
      case InvoiceType.electrical:
        return 'برق خودرو';
      case InvoiceType.mechanic:
        return 'مکانیک';
      case InvoiceType.suspension:
        return 'جلوبندی';
      case InvoiceType.productSale:
        return 'فروش کالا';
      case InvoiceType.productPurchase:
        return 'خرید کالا';
    }
  }

  bool get isServiceType =>
      this == InvoiceType.electrical || this == InvoiceType.mechanic || this == InvoiceType.suspension;
  bool get isProductPurchase => this == InvoiceType.productPurchase;

  String get dbValue => name;
  static InvoiceType fromDb(String v) =>
      InvoiceType.values.firstWhere((e) => e.name == v, orElse: () => InvoiceType.electrical);
}

enum PaymentType { cash, nonCash, cardToCard, onlinePayment, bankTransfer }

extension PaymentTypeX on PaymentType {
  String get label {
    switch (this) {
      case PaymentType.cash:
        return 'نقدی';
      case PaymentType.nonCash:
        return 'چک';
      case PaymentType.cardToCard:
        return 'کارت به کارت';
      case PaymentType.onlinePayment:
        return `کارتخوان مغازه';
      case PaymentType.bankTransfer:
        return 'انتقال بانکی';
    }
  }

  String get dbValue => name;
  static PaymentType fromDb(String v) =>
      PaymentType.values.firstWhere((e) => e.name == v, orElse: () => PaymentType.cash);
}

enum InvoiceItemType { service, product }

extension InvoiceItemTypeX on InvoiceItemType {
  String get dbValue => name;
  static InvoiceItemType fromDb(String v) => InvoiceItemType.values.firstWhere((e) => e.name == v);
}

class Invoice {
  final int? id;
  final String invoiceNumber;
  final InvoiceType type;
  final int? customerId;
  final String issueDate;
  final double itemsTotal;
  final double sideCosts;
  final double finalAmount;
  final PaymentType paymentType;
  final String? paymentAccountInfo; // شماره کارت/شبا انتخاب‌شده
  final String? notes;
  final int isDeleted;
  final String createdAt;

  Invoice({
    this.id,
    required this.invoiceNumber,
    required this.type,
    this.customerId,
    required this.issueDate,
    required this.itemsTotal,
    required this.sideCosts,
    required this.finalAmount,
    required this.paymentType,
    this.paymentAccountInfo,
    this.notes,
    this.isDeleted = 0,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'invoice_number': invoiceNumber,
        'type': type.dbValue,
        'customer_id': customerId,
        'issue_date': issueDate,
        'items_total': itemsTotal,
        'side_costs': sideCosts,
        'final_amount': finalAmount,
        'payment_type': paymentType.dbValue,
        'payment_account_info': paymentAccountInfo,
        'notes': notes,
        'is_deleted': isDeleted,
        'created_at': createdAt,
      };

  factory Invoice.fromMap(Map<String, dynamic> map) => Invoice(
        id: map['id'] as int?,
        invoiceNumber: map['invoice_number'] as String,
        type: InvoiceTypeX.fromDb(map['type'] as String),
        customerId: map['customer_id'] as int?,
        issueDate: map['issue_date'] as String,
        itemsTotal: (map['items_total'] as num).toDouble(),
        sideCosts: (map['side_costs'] as num).toDouble(),
        finalAmount: (map['final_amount'] as num).toDouble(),
        paymentType: PaymentTypeX.fromDb(map['payment_type'] as String),
        paymentAccountInfo: map['payment_account_info'] as String?,
        notes: map['notes'] as String?,
        isDeleted: map['is_deleted'] as int? ?? 0,
        createdAt: map['created_at'] as String?,
      );
}

/// ردیف فاکتور. قیمت واحد در لحظه‌ی صدور فریز می‌شود و با تغییر قیمت خدمت/کالا
/// در آینده، این مقدار دیگر تغییر نمی‌کند.
class InvoiceItem {
  final int? id;
  final int invoiceId;
  final InvoiceItemType itemType;
  final int? serviceId;
  final int? productId;
  final String description;
  final int quantity;
  final double unitPrice;
  final double total;

  InvoiceItem({
    this.id,
    required this.invoiceId,
    required this.itemType,
    this.serviceId,
    this.productId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'invoice_id': invoiceId,
        'item_type': itemType.dbValue,
        'service_id': serviceId,
        'product_id': productId,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total': total,
      };

  factory InvoiceItem.fromMap(Map<String, dynamic> map) => InvoiceItem(
        id: map['id'] as int?,
        invoiceId: map['invoice_id'] as int,
        itemType: InvoiceItemTypeX.fromDb(map['item_type'] as String),
        serviceId: map['service_id'] as int?,
        productId: map['product_id'] as int?,
        description: map['description'] as String,
        quantity: map['quantity'] as int,
        unitPrice: (map['unit_price'] as num).toDouble(),
        total: (map['total'] as num).toDouble(),
      );
}

/// هزینه‌های جانبی هر فاکتور (مثلاً حمل‌ونقل، بسته‌بندی و ...)
class SideCost {
  final int? id;
  final int invoiceId;
  final String title;
  final double amount;

  SideCost({this.id, required this.invoiceId, required this.title, required this.amount});

  Map<String, dynamic> toMap() => {
        'id': id,
        'invoice_id': invoiceId,
        'title': title,
        'amount': amount,
      };

  factory SideCost.fromMap(Map<String, dynamic> map) => SideCost(
        id: map['id'] as int?,
        invoiceId: map['invoice_id'] as int,
        title: map['title'] as String,
        amount: (map['amount'] as num).toDouble(),
      );
}
