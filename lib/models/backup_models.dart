/// انواع Backup پشتیبانی‌شده. هر نوع در یک فایل JSON مستقل ذخیره می‌شود.
enum BackupType {
  customers, // مشتریان + خودروهای وابسته به آن‌ها
  products, // محصولات + سوابق (فعلاً بدون stock_movements)
  services, // خدمات + دسته‌بندی‌ها + سوابق قیمت
  invoices, // فاکتورها + اقلام + هزینه‌های جانبی (شامل ارجاع مشتری/خودرو)
  full, // همه‌ی بخش‌های بالا با هم
}

extension BackupTypeX on BackupType {
  String get key {
    switch (this) {
      case BackupType.customers:
        return 'customers';
      case BackupType.products:
        return 'products';
      case BackupType.services:
        return 'services';
      case BackupType.invoices:
        return 'invoices';
      case BackupType.full:
        return 'full';
    }
  }

  /// عنوان فارسی برای UI.
  String get label {
    switch (this) {
      case BackupType.customers:
        return 'مشتریان (و خودروها)';
      case BackupType.products:
        return 'محصولات';
      case BackupType.services:
        return 'خدمات';
      case BackupType.invoices:
        return 'فاکتورها';
      case BackupType.full:
        return 'کامل';
    }
  }

  /// پسوند فایل اختصاصی. محتوای فایل همچنان JSON استاندارد است؛ این پسوند
  /// فقط برای تشخیص سریع نوع فایل توسط کاربر/سیستم است. نوع واقعی همیشه
  /// از فیلد backupType داخل خود فایل خوانده می‌شود.
  String get fileExtension {
    switch (this) {
      case BackupType.customers:
        return 'customerbackup';
      case BackupType.products:
        return 'productbackup';
      case BackupType.services:
        return 'servicebackup';
      case BackupType.invoices:
        return 'invoicebackup';
      case BackupType.full:
        return 'fullbackup';
    }
  }

  static BackupType fromKey(String key) {
    return BackupType.values.firstWhere((t) => t.key == key, orElse: () => BackupType.full);
  }
}

/// ساختار کلی هر فایل Backup، مستقل از نوع محتوای داخلش.
class BackupEnvelope {
  static const int currentVersion = 1;

  final BackupType backupType;
  final int backupVersion;
  final int appDbVersion;
  final String createdAt;
  final String updatedAt;
  final Map<String, int> recordCounts;
  final Map<String, dynamic> data;

  BackupEnvelope({
    required this.backupType,
    this.backupVersion = currentVersion,
    required this.appDbVersion,
    String? createdAt,
    String? updatedAt,
    required this.recordCounts,
    required this.data,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toJson() => {
        'backupType': backupType.key,
        'backupVersion': backupVersion,
        'appDbVersion': appDbVersion,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'recordCounts': recordCounts,
        'data': data,
      };

  factory BackupEnvelope.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['recordCounts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      rawCounts.forEach((k, v) {
        if (v is num) counts[k.toString()] = v.toInt();
      });
    }
    return BackupEnvelope(
      backupType: BackupTypeX.fromKey(json['backupType']?.toString() ?? 'full'),
      backupVersion: (json['backupVersion'] as num?)?.toInt() ?? 1,
      appDbVersion: (json['appDbVersion'] as num?)?.toInt() ?? 1,
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
      recordCounts: counts,
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }
}

/// حالت بازیابی.
enum RestoreMode {
  merge, // افزودن به اطلاعات فعلی، بدون تکراری‌سازی
  replace, // جایگزینی کامل همان بخش
}

/// گزارش نتیجه‌ی یک عملیات Import، برای نمایش خلاصه به کاربر.
class RestoreReport {
  int customersAdded = 0;
  int customersMatched = 0;
  int vehiclesAdded = 0;
  int vehiclesMatched = 0;
  int productsAdded = 0;
  int productsMatched = 0;
  int servicesAdded = 0;
  int servicesMatched = 0;
  int invoicesAdded = 0;
  int invoicesSkippedDuplicate = 0;
  int invoicesRenumbered = 0;
  final List<String> notes = [];

  String summary() {
    final b = StringBuffer();
    if (customersAdded > 0 || customersMatched > 0) {
      b.writeln('مشتریان: $customersAdded جدید، $customersMatched قبلاً موجود');
    }
    if (vehiclesAdded > 0 || vehiclesMatched > 0) {
      b.writeln('خودروها: $vehiclesAdded جدید، $vehiclesMatched قبلاً موجود');
    }
    if (productsAdded > 0 || productsMatched > 0) {
      b.writeln('محصولات: $productsAdded جدید، $productsMatched قبلاً موجود');
    }
    if (servicesAdded > 0 || servicesMatched > 0) {
      b.writeln('خدمات: $servicesAdded جدید، $servicesMatched قبلاً موجود');
    }
    if (invoicesAdded > 0 || invoicesSkippedDuplicate > 0 || invoicesRenumbered > 0) {
      b.writeln('فاکتورها: $invoicesAdded جدید، $invoicesSkippedDuplicate تکراری (رد شد)'
          '${invoicesRenumbered > 0 ? '، $invoicesRenumbered با شماره‌ی جدید' : ''}');
    }
    for (final n in notes) {
      b.writeln(n);
    }
    return b.toString().trim();
  }
}
