/// تمام مقادیر ظاهری فاکتور PDF در همین‌جا متمرکز شده‌اند تا در آینده
/// بتوان یک صفحه‌ی «تنظیمات قالب فاکتور» با اسلایدر ساخت که همین مقادیر
/// را (بدون نیاز به تغییر کد) عوض کند.
///
/// نکته: هیچ عدد ظاهری (اندازه، فاصله، فونت، رنگ، ضخامت) نباید مستقیم داخل
/// pdf_service.dart نوشته شود؛ همه‌چیز باید از این کلاس خوانده شود.
class InvoiceLayoutSettings {
  // ---------- رنگ‌بندی ----------
  final int colorOrange;
  final int colorDarkGray;
  final int colorLightGray;
  final int colorWhite;
  final int colorBorder; // حاشیه‌ی کادرها و جدول
  final int colorBorderStrong; // حاشیه‌ی پررنگ‌تر (جمع کل و امضا)
  final int colorSubtleText; // متن کم‌رنگ (آدرس)

  // ---------- تصاویر سربرگ/فوتر ----------
  final double logoImageHeight;
  final double iconsRowImageHeight;
  final double contactIconSize;
  final double importantIconSize;
  final double bottomAccentHeight;
  final double bottomAccentFallbackOrangeWidth; // عرض بخش نارنجی نوار پایین (وقتی عکس نیست)

  // ---------- سربرگ ----------
  final double topBarHeight;
  final double headerCompanyNameFontSize;
  final double headerSubTitleFontSize;
  final double headerContactFontSize;
  final double headerInfoFontSize;
  final double headerInfoLineVerticalPadding; // فاصله‌ی عمودی هر خط تاریخ/شماره/نوع
  final double headerSpacingAfter;
  final double headerLogoToContactSpacing; // فاصله‌ی لوگو تا خط تماس
  final double headerAddressTopPadding; // فاصله‌ی بالای خط آدرس
  final double headerIconToTextSpacing; // فاصله‌ی آیکون (تلفن/لوکیشن) تا متن
  final double headerInfoToIconsRowSpacing; // فاصله‌ی متن‌های تاریخ/شماره تا ستون آیکون‌ها
  final double headerBottomLineThickness; // ضخامت خط زیر سربرگ

  // ---------- حاشیه‌ی صفحه ----------
  final double pageMarginHorizontal;
  final double pageMarginVertical;
  final double pageBottomExtraSpacing; // فاصله‌ی انتهای بدنه، بعد از امضا

  // ---------- بخش مشتری ----------
  final double customerBoxFontSize;
  final double customerBoxPadding;
  final double customerBoxBorderWidth;
  final double customerBoxCornerRadius;
  final double spacingAfterCustomerBox;

  // ---------- جدول اقلام ----------
  final double tableMinRows;
  final double tableHeaderFontSize;
  final double tableCellFontSize;
  final double tableRowVerticalPadding;
  final double tableHeaderExtraVerticalPadding; // اضافه‌ی ارتفاع ردیف هدر نسبت به ردیف‌های عادی
  final double tableCellHorizontalPadding;
  final double tableBorderWidth;
  final double colWidthRow;
  final double colWidthDescription;
  final double colWidthUnitPrice;
  final double colWidthTotalPrice;
  final double spacingAfterTable;

  // ---------- هزینه‌های جانبی و توضیحات ----------
  final double sideCostsTopSpacing;
  final double sideCostsTitleFontSize;
  final double sideCostsItemFontSize;
  final double notesTopSpacing;
  final double notesFontSize;

  // ---------- جمع کل ----------
  final double totalsFontSize;
  final double totalsBoldFontSize;
  final double totalsAccentBarWidth; // نوار نارنجی کنار جمع کل
  final double totalsAccentBarHeight;
  final double totalsAccentBarSpacing; // فاصله‌ی نوار تا کادر
  final double totalsBoxHorizontalPadding;
  final double totalsBoxVerticalPadding;
  final double totalsBoxBorderWidth;
  final double spacingAfterTotals;

  // ---------- نکات مهم ----------
  final double termsTitleFontSize;
  final double termsFontSize;
  final double termsLineSpacing;
  final int termsColumnCount;
  final double termsBoxPadding;
  final double termsBoxBorderWidth;
  final double termsBoxCornerRadius;
  final double termsColumnDividerWidth; // ضخامت خط جداکننده‌ی دو ستون
  final double termsColumnDividerMargin; // فاصله‌ی دو طرف خط جداکننده
  final double termsTitleToContentSpacing;
  final double termsFallbackBarWidth; // نوار نارنجی کنار عنوان (وقتی آیکون نیست)
  final double termsFallbackBarHeight;
  final double termsFallbackBarSpacing;
  final double termsIconLeftPadding; // فاصله‌ی آیکون «مهم» از متن

  // ---------- امضا و مهر ----------
  final double signatureLineWidth;
  final double signatureBoxHeight;
  final double signatureBoxBorderWidth;
  final double signatureLabelTopSpacing;
  final double signatureLabelFontSize;
  final double signatureBetweenBoxesSpacing;
  final double stampImageSize;

  const InvoiceLayoutSettings({
    // رنگ‌ها
    this.colorOrange = 0xFFE87722,
    this.colorDarkGray = 0xFF2B2B2B,
    this.colorLightGray = 0xFFF3F3F3,
    this.colorWhite = 0xFFFFFFFF,
    this.colorBorder = 0xFFBDBDBD, // معادل PdfColors.grey400
    this.colorBorderStrong = 0xFF9E9E9E, // معادل PdfColors.grey500
    this.colorSubtleText = 0xFF616161, // معادل PdfColors.grey700
    // تصاویر
    this.logoImageHeight = 40,
    this.iconsRowImageHeight = 34,
    this.contactIconSize = 8,
    this.importantIconSize = 10,
    this.bottomAccentHeight = 10,
    this.bottomAccentFallbackOrangeWidth = 70,
    // سربرگ
    this.topBarHeight = 4,
    this.headerCompanyNameFontSize = 11,
    this.headerSubTitleFontSize = 7,
    this.headerContactFontSize = 7,
    this.headerInfoFontSize = 7.5,
    this.headerInfoLineVerticalPadding = 1,
    this.headerSpacingAfter = 5,
    this.headerLogoToContactSpacing = 2,
    this.headerAddressTopPadding = 1,
    this.headerIconToTextSpacing = 3,
    this.headerInfoToIconsRowSpacing = 6,
    this.headerBottomLineThickness = 1.2,
    // حاشیه
    this.pageMarginHorizontal = 12,
    this.pageMarginVertical = 0,
    this.pageBottomExtraSpacing = 6,
    // مشتری
    this.customerBoxFontSize = 8,
    this.customerBoxPadding = 4,
    this.customerBoxBorderWidth = 0.6,
    this.customerBoxCornerRadius = 3,
    this.spacingAfterCustomerBox = 6,
    // جدول
    this.tableMinRows = 15,
    this.tableHeaderFontSize = 7.5,
    this.tableCellFontSize = 7.5,
    this.tableRowVerticalPadding = 2,
    this.tableHeaderExtraVerticalPadding = 2,
    this.tableCellHorizontalPadding = 2,
    this.tableBorderWidth = 0.5,
    this.colWidthRow = 0.08,
    this.colWidthDescription = 0.52,
    this.colWidthUnitPrice = 0.20,
    this.colWidthTotalPrice = 0.20,
    this.spacingAfterTable = 6,
    // هزینه‌های جانبی و توضیحات
    this.sideCostsTopSpacing = 4,
    this.sideCostsTitleFontSize = 8,
    this.sideCostsItemFontSize = 7.5,
    this.notesTopSpacing = 4,
    this.notesFontSize = 7,
    // جمع کل
    this.totalsFontSize = 8,
    this.totalsBoldFontSize = 10,
    this.totalsAccentBarWidth = 4,
    this.totalsAccentBarHeight = 26,
    this.totalsAccentBarSpacing = 6,
    this.totalsBoxHorizontalPadding = 8,
    this.totalsBoxVerticalPadding = 5,
    this.totalsBoxBorderWidth = 0.7,
    this.spacingAfterTotals = 6,
    // نکات مهم
    this.termsTitleFontSize = 7.5,
    this.termsFontSize = 6.3,
    this.termsLineSpacing = 3,
    this.termsColumnCount = 2,
    this.termsBoxPadding = 5,
    this.termsBoxBorderWidth = 0.5,
    this.termsBoxCornerRadius = 3,
    this.termsColumnDividerWidth = 0.7,
    this.termsColumnDividerMargin = 6,
    this.termsTitleToContentSpacing = 4,
    this.termsFallbackBarWidth = 3,
    this.termsFallbackBarHeight = 9,
    this.termsFallbackBarSpacing = 4,
    this.termsIconLeftPadding = 4,
    // امضا و مهر
    this.signatureLineWidth = 90,
    this.signatureBoxHeight = 28,
    this.signatureBoxBorderWidth = 0.6,
    this.signatureLabelTopSpacing = 2,
    this.signatureLabelFontSize = 7.5,
    this.signatureBetweenBoxesSpacing = 10,
    this.stampImageSize = 50,
  });
}
