enum Currency { toman, rial }

extension CurrencyX on Currency {
  String get label => this == Currency.toman ? 'تومان' : 'ریال';
  String get dbValue => name;
  static Currency fromDb(String? v) => v == 'rial' ? Currency.rial : Currency.toman;
}

class AppSettings {
  final String shopName;
  final String contactNumber;
  final String address;
  final int invoiceStartNumber;
  final Currency currency;
  final int lowStockThreshold;
  final String primaryColorHex; // رنگ اصلی تم، قابل تغییر توسط کاربر
  final String termsText; // نکات مهم / شرایط که زیر همه فاکتورها چاپ می‌شود
  final String? stampImagePath; // مسیر عکس مهر/امضای کارگاه

  AppSettings({
    this.shopName = 'تعمیرگاه من',
    this.contactNumber = '',
    this.address = '',
    this.invoiceStartNumber = 1001,
    this.currency = Currency.toman,
    this.lowStockThreshold = 5,
    this.primaryColorHex = '#FF7A1A',
    this.termsText = '',
    this.stampImagePath,
  });

  Map<String, String> toKeyValueMap() => {
        'shop_name': shopName,
        'contact_number': contactNumber,
        'address': address,
        'invoice_start_number': invoiceStartNumber.toString(),
        'currency': currency.dbValue,
        'low_stock_threshold': lowStockThreshold.toString(),
        'primary_color_hex': primaryColorHex,
        'terms_text': termsText,
        'stamp_image_path': stampImagePath ?? '',
      };

  factory AppSettings.fromKeyValueMap(Map<String, String> map) => AppSettings(
        shopName: map['shop_name'] ?? 'تعمیرگاه من',
        contactNumber: map['contact_number'] ?? '',
        address: map['address'] ?? '',
        invoiceStartNumber: int.tryParse(map['invoice_start_number'] ?? '') ?? 1001,
        currency: CurrencyX.fromDb(map['currency']),
        lowStockThreshold: int.tryParse(map['low_stock_threshold'] ?? '') ?? 5,
        primaryColorHex: map['primary_color_hex'] ?? '#FF7A1A',
        termsText: map['terms_text'] ?? '',
        stampImagePath: (map['stamp_image_path'] ?? '').isEmpty ? null : map['stamp_image_path'],
      );

  AppSettings copyWith({
    String? shopName,
    String? contactNumber,
    String? address,
    int? invoiceStartNumber,
    Currency? currency,
    int? lowStockThreshold,
    String? primaryColorHex,
    String? termsText,
    String? stampImagePath,
  }) =>
      AppSettings(
        shopName: shopName ?? this.shopName,
        contactNumber: contactNumber ?? this.contactNumber,
        address: address ?? this.address,
        invoiceStartNumber: invoiceStartNumber ?? this.invoiceStartNumber,
        currency: currency ?? this.currency,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        primaryColorHex: primaryColorHex ?? this.primaryColorHex,
        termsText: termsText ?? this.termsText,
        stampImagePath: stampImagePath ?? this.stampImagePath,
      );
}
