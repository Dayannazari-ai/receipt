/// تمام مقادیر ظاهری فاکتور PDF در همین‌جا متمرکز شده‌اند تا در آینده
/// بتوان یک صفحه‌ی «تنظیمات قالب فاکتور» با اسلایدر ساخت که همین مقادیر
/// را (بدون نیاز به تغییر کد) عوض کند. فعلاً فقط مقادیر پیش‌فرض استفاده
/// می‌شوند؛ pdf_service.dart هیچ عدد ثابتی مستقیم در خودش ندارد.
class InvoiceLayoutSettings {
  // ---------- سربرگ ----------
  final double headerLogoSize;
  final double headerCompanyNameFontSize;
  final double headerSubTitleFontSize;
  final double headerContactFontSize;
  final double headerSpacingAfter;

  // ---------- فاصله از لبه‌های کاغذ ----------
  final double pageMarginHorizontal;
  final double pageMarginVertical;

  // ---------- بخش مشتری ----------
  final double customerBoxFontSize;
  final double customerBoxPadding;
  final double spacingAfterCustomerBox;

  // ---------- جدول اقلام ----------
  final double tableMinRows;
  final double tableHeaderFontSize;
  final double tableCellFontSize;
  final double tableRowVerticalPadding;
  final double colWidthRow; // ستون ردیف
  final double colWidthDescription; // ستون شرح (عریض‌ترین)
  final double colWidthUnitPrice; // ستون قیمت واحد
  final double colWidthTotalPrice; // ستون قیمت کل
  final double spacingAfterTable;

  // ---------- جمع کل (خارج از جدول) ----------
  final double totalsFontSize;
  final double totalsBoldFontSize;
  final double spacingAfterTotals;

  // ---------- نکات مهم (دو ستونه) ----------
  final double termsTitleFontSize;
  final double termsFontSize;
  final double termsLineSpacing;
  final int termsColumnCount;
  final double spacingAfterTerms;

  // ---------- امضا و مهر ----------
  final double signatureLineWidth;
  final double signatureLabelFontSize;
  final double stampImageSize;

  const InvoiceLayoutSettings({
    this.headerLogoSize = 26,
    this.headerCompanyNameFontSize = 11,
    this.headerSubTitleFontSize = 7,
    this.headerContactFontSize = 7,
    this.headerSpacingAfter = 4,
    this.pageMarginHorizontal = 12,
    this.pageMarginVertical = 10,
    this.customerBoxFontSize = 8,
    this.customerBoxPadding = 4,
    this.spacingAfterCustomerBox = 6,
    this.tableMinRows = 15,
    this.tableHeaderFontSize = 7.5,
    this.tableCellFontSize = 7.5,
    this.tableRowVerticalPadding = 2,
    this.colWidthRow = 0.08,
    this.colWidthDescription = 0.52,
    this.colWidthUnitPrice = 0.20,
    this.colWidthTotalPrice = 0.20,
    this.spacingAfterTable = 6,
    this.totalsFontSize = 8,
    this.totalsBoldFontSize = 10,
    this.spacingAfterTotals = 6,
    this.termsTitleFontSize = 7.5,
    this.termsFontSize = 6.3,
    this.termsLineSpacing = 1.5,
    this.termsColumnCount = 2,
    this.spacingAfterTerms = 6,
    this.signatureLineWidth = 90,
    this.signatureLabelFontSize = 7.5,
    this.stampImageSize = 55,
  });
}
