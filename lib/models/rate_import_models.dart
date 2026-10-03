import 'service.dart';

/// کدام قیمت به‌عنوان price اصلی خدمت ثبت شود.
enum PriceField { general, minApproved, negotiated, special }

extension PriceFieldX on PriceField {
  String get label {
    switch (this) {
      case PriceField.general:
        return 'قیمت';
      case PriceField.minApproved:
        return 'حداقل مصوب';
      case PriceField.negotiated:
        return 'توافقی';
      case PriceField.special:
        return 'ویژه';
    }
  }
}

enum RateMatchStatus { newService, priceChanged, unchanged, uncertain }

/// جدول خام استخراج‌شده از هر منبع (Excel، PDF متنی، OCR).
/// هر منبع فقط باید به این ساختار تبدیل شود؛ بقیه‌ی سیستم مستقل از منبع است.
class RawTable {
  final String name;
  final List<List<String>> rows;
  const RawTable(this.name, this.rows);
}

/// یک ردیف نرخ استخراج‌شده (مدل استاندارد). تا قبل از تأیید نهایی کاربر
/// فقط در حافظه است و هیچ‌چیز در دیتابیس نوشته نمی‌شود.
class ExtractedRateRow {
  ExtractedRateRow({required this.localId, this.title = '', this.sourceLabel = ''});

  final int localId;
  String title;
  String? code;
  String? categoryText;
  String? brandText;
  String? modelText;

  /// خودرو به‌صورت ترکیبی (مثلاً «پژو 206») که هنوز به برند/مدل تفکیک نشده.
  String? vehicleText;
  String? type;
  String? year;
  double? minApproved;
  double? negotiated;
  double? special;
  double? general;

  /// 'rial' | 'toman' | null
  String? unit;
  String? notes;
  String sourceLabel;

  /// موارد مشکوک در زمان استخراج (مثلاً عدد نامعتبر).
  final List<String> extractionFlags = [];

  // ---- نتیجه‌ی تطبیق (توسط RateMatcher محاسبه می‌شود) ----
  RateMatchStatus status = RateMatchStatus.uncertain;
  ServiceItem? matched;
  int? categoryId;
  int? brandId;
  int? modelId;
  bool newBrand = false;
  bool newModel = false;
  List<String> issues = [];
  double? effectiveNewPrice;

  // ---- تصمیم‌های کاربر ----
  bool approved = false;
  bool userConfirmed = false;
  bool forceNew = false;
  int? linkedServiceId;

  double? priceFor(PriceField f) {
    switch (f) {
      case PriceField.general:
        return general;
      case PriceField.minApproved:
        return minApproved;
      case PriceField.negotiated:
        return negotiated;
      case PriceField.special:
        return special;
    }
  }

  void setPrice(PriceField f, double? v) {
    switch (f) {
      case PriceField.general:
        general = v;
        break;
      case PriceField.minApproved:
        minApproved = v;
        break;
      case PriceField.negotiated:
        negotiated = v;
        break;
      case PriceField.special:
        special = v;
        break;
    }
  }

  bool get hasAnyPrice => PriceField.values.any((f) => priceFor(f) != null);

  /// قیمت نهایی بعد از انتخاب فیلد اصلی و تبدیل واحد (گرد شده).
  double? effectivePrice(PriceField f, double factor) {
    final v = priceFor(f);
    if (v == null) return null;
    return (v * factor).roundToDouble();
  }

  String? get unitLabel {
    if (unit == 'rial') return 'ریال';
    if (unit == 'toman') return 'تومان';
    return null;
  }
}
