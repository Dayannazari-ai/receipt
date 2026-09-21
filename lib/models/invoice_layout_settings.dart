/// تمام مقادیر ظاهری فاکتور PDF در همین‌جا متمرکز شده‌اند تا در آینده
/// بتوان یک صفحه‌ی «تنظیمات قالب فاکتور» با اسلایدر ساخت که همین مقادیر
/// را (بدون نیاز به تغییر کد) عوض کند. فعلاً فقط مقادیر پیش‌فرض استفاده
/// می‌شوند؛ pdf_service.dart هیچ عدد یا رنگ ثابتی مستقیم در خودش ندارد.
class InvoiceLayoutSettings {
  // ---------- رنگ‌بندی (کد رنگ ARGB/RGB به‌صورت int) ----------
  final int colorOrange;
  final int colorDarkGray;
  final int colorLightGray;
  final int colorWhite;

  // ---------- نوار تزئینی بالای سربرگ ----------
  final double topBarHeight;

  // ---------- سربرگ ----------
  final double logoPlaceholderSize;
  final double headerCompanyNameFontSize;
  final double headerSubTitleFontSize;
  final double headerContactFontSize;
  final double headerInfoFontSize;
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
  final double colWidthRow;
  final double colWidthDescription;
  final double colWidthUnitPrice;
  final double colWidthTotalPrice;
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
  final double termsBoxPadding;
  final double spacingAfterTerms;

  // ---------- امضا و مهر ----------
  final double signatureLineWidth;
  final double signatureLabelFontSize;
  final double stampImageSize;

  // ---------- نوار تزئینی پایین صفحه ----------
  final double bottomBarHeight;

  const InvoiceLayoutSettings({
    this.colorOrange = 0xFFE87722,
    this.colorDarkGray = 0xFF2B2B2B,
    this.colorLightGray = 0xFFF3F3F3,
    this.colorWhite = 0xFFFFFFFF,
    this.topBarHeight = 4,
    this.logoPlaceholderSize = 34,
    this.headerCompanyNameFontSize = 11,
    this.headerSubTitleFontSize = 7,
    this.headerContactFontSize = 7,
    this.headerInfoFontSize = 7.5,
    this.headerSpacingAfter = 5,
    this.pageMarginHorizontal = 12,
    this.pageMarginVertical = 0,
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
    this.termsLineSpacing = 3,
    this.termsColumnCount = 2,
    this.termsBoxPadding = 5,
    this.spacingAfterTerms = 6,
    this.signatureLineWidth = 90,
    this.signatureLabelFontSize = 7.5,
    this.stampImageSize = 50,
    this.bottomBarHeight = 4,
  });
}
