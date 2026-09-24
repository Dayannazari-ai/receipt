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
  final int colorText; // رنگ متن اصلی

  // ---------- تصاویر سربرگ/فوتر ----------
  final double logoImageHeight;
  final double logoOffsetX; // جابه‌جایی افقی لوگو (۰ = جای فعلی)
  final double logoOffsetY; // جابه‌جایی عمودی لوگو (۰ = جای فعلی)
  final double iconsRowImageHeight;
  final double iconsOffsetX; // جابه‌جایی افقی ستون آیکون‌های تاریخ/شماره/نوع
  final double iconsOffsetY; // جابه‌جایی عمودی ستون آیکون‌های تاریخ/شماره/نوع
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
  final double headerPaddingTop; // فاصله‌ی بالای محتوای سربرگ (معادل فعلی: ۵)
  final double headerPaddingBottom; // فاصله‌ی پایین محتوای سربرگ (معادل فعلی: ۵)
  final double headerLogoToContactSpacing; // فاصله‌ی لوگو تا خط تماس
  final double headerAddressTopPadding; // فاصله‌ی بالای خط آدرس
  final double headerIconToTextSpacing; // فاصله‌ی آیکون (تلفن/لوکیشن) تا متن
  final double headerInfoToIconsRowSpacing; // فاصله‌ی متن‌های تاریخ/شماره تا ستون آیکون‌ها
  final double headerBottomLineThickness; // ضخامت خط زیر سربرگ

  // ---------- حاشیه‌ی صفحه ----------
  final double pageMarginHorizontal;
  final double pageMarginVertical;
  final double pageMarginTop; // حاشیه‌ی بالای بدنه (معادل فعلی: ۰)
  final double pageMarginBottom; // حاشیه‌ی پایین بدنه (معادل فعلی: ۰)
  final double pageMarginLeft; // حاشیه‌ی چپ (معادل فعلی: ۱۲)
  final double pageMarginRight; // حاشیه‌ی راست (معادل فعلی: ۱۲)
  final double pageBottomExtraSpacing; // فاصله‌ی انتهای بدنه، بعد از امضا

  // ---------- بخش مشتری ----------
  final double customerBoxFontSize;
  final double customerBoxPadding;
  final double customerBoxBorderWidth;
  final double customerBoxCornerRadius;
  final double customerBoxHeight; // ۰ = خودکار (ارتفاع فعلی)
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
  final double totalsBoxScale; // ضریب اندازه‌ی کادر جمع کل (۱ = اندازه‌ی فعلی)
  final double spacingAfterTotals;

  // ---------- نکات مهم ----------
  final double termsTitleFontSize;
  final double termsFontSize;
  final double termsLineSpacing;
  final int termsColumnCount;
  final double termsBoxPadding;
  final double termsBoxBorderWidth;
  final double termsBoxCornerRadius;
  final double termsBoxMinHeight; // ۰ = خودکار (ارتفاع فعلی)
  final double termsColumnDividerWidth; // ضخامت خط جداکننده‌ی دو ستون
  final double termsColumnDividerMargin; // فاصله‌ی دو طرف خط جداکننده
  final double termsTitleToContentSpacing;
  final double termsFallbackBarWidth; // نوار نارنجی کنار عنوان (وقتی آیکون نیست)
  final double termsFallbackBarHeight;
  final double termsFallbackBarSpacing;
  final double termsIconLeftPadding; // فاصله‌ی آیکون «مهم» از متن
  final double spacingAfterTerms;

  // ---------- امضا و مهر ----------
  final double signatureLineWidth;
  final double signatureBoxHeight;
  final double signatureBoxBorderWidth;
  final double signatureLabelTopSpacing;
  final double signatureLabelFontSize;
  final double signatureBetweenBoxesSpacing;
  final double signatureOffsetX; // جابه‌جایی افقی ردیف امضا و مهر
  final double signatureOffsetY; // جابه‌جایی عمودی ردیف امضا و مهر
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
    this.colorText = 0xFF000000,
    // تصاویر
    this.logoImageHeight = 40,
    this.logoOffsetX = 0,
    this.logoOffsetY = 0,
    this.iconsRowImageHeight = 34,
    this.iconsOffsetX = 0,
    this.iconsOffsetY = 0,
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
    this.headerPaddingTop = 5,
    this.headerPaddingBottom = 5,
    this.headerLogoToContactSpacing = 2,
    this.headerAddressTopPadding = 1,
    this.headerIconToTextSpacing = 3,
    this.headerInfoToIconsRowSpacing = 6,
    this.headerBottomLineThickness = 1.2,
    // حاشیه
    this.pageMarginHorizontal = 12,
    this.pageMarginVertical = 0,
    this.pageMarginTop = 0,
    this.pageMarginBottom = 0,
    this.pageMarginLeft = 12,
    this.pageMarginRight = 12,
    this.pageBottomExtraSpacing = 6,
    // مشتری
    this.customerBoxFontSize = 8,
    this.customerBoxPadding = 4,
    this.customerBoxBorderWidth = 0.6,
    this.customerBoxCornerRadius = 3,
    this.customerBoxHeight = 0,
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
    this.totalsBoxScale = 1,
    this.spacingAfterTotals = 6,
    // نکات مهم
    this.termsTitleFontSize = 7.5,
    this.termsFontSize = 6.3,
    this.termsLineSpacing = 3,
    this.termsColumnCount = 2,
    this.termsBoxPadding = 5,
    this.termsBoxBorderWidth = 0.5,
    this.termsBoxCornerRadius = 3,
    this.termsBoxMinHeight = 0,
    this.termsColumnDividerWidth = 0.7,
    this.termsColumnDividerMargin = 6,
    this.termsTitleToContentSpacing = 4,
    this.termsFallbackBarWidth = 3,
    this.termsFallbackBarHeight = 9,
    this.termsFallbackBarSpacing = 4,
    this.termsIconLeftPadding = 4,
    this.spacingAfterTerms = 6,
    // امضا و مهر
    this.signatureLineWidth = 90,
    this.signatureBoxHeight = 28,
    this.signatureBoxBorderWidth = 0.6,
    this.signatureLabelTopSpacing = 2,
    this.signatureLabelFontSize = 7.5,
    this.signatureBetweenBoxesSpacing = 10,
    this.signatureOffsetX = 0,
    this.signatureOffsetY = 0,
    this.stampImageSize = 50,
  });

  /// مقادیر پیش‌فرض (معادل ظاهر فعلی فاکتور).
  static const InvoiceLayoutSettings defaults = InvoiceLayoutSettings();

  /// ساخت از JSON. اگر فیلدی وجود نداشت یا نوعش نامعتبر بود، مقدار پیش‌فرض
  /// همان فیلد استفاده می‌شود (سازگاری با داده‌های قدیمی).
  factory InvoiceLayoutSettings.fromJson(Map<String, dynamic> json) {
    const d = InvoiceLayoutSettings();

    double dbl(String key, double fallback) {
      final v = json[key];
      return v is num ? v.toDouble() : fallback;
    }

    int integer(String key, int fallback) {
      final v = json[key];
      return v is num ? v.toInt() : fallback;
    }

    return InvoiceLayoutSettings(
      colorOrange: integer('colorOrange', d.colorOrange),
      colorDarkGray: integer('colorDarkGray', d.colorDarkGray),
      colorLightGray: integer('colorLightGray', d.colorLightGray),
      colorWhite: integer('colorWhite', d.colorWhite),
      colorBorder: integer('colorBorder', d.colorBorder),
      colorBorderStrong: integer('colorBorderStrong', d.colorBorderStrong),
      colorSubtleText: integer('colorSubtleText', d.colorSubtleText),
      colorText: integer('colorText', d.colorText),
      logoImageHeight: dbl('logoImageHeight', d.logoImageHeight),
      logoOffsetX: dbl('logoOffsetX', d.logoOffsetX),
      logoOffsetY: dbl('logoOffsetY', d.logoOffsetY),
      iconsRowImageHeight: dbl('iconsRowImageHeight', d.iconsRowImageHeight),
      iconsOffsetX: dbl('iconsOffsetX', d.iconsOffsetX),
      iconsOffsetY: dbl('iconsOffsetY', d.iconsOffsetY),
      contactIconSize: dbl('contactIconSize', d.contactIconSize),
      importantIconSize: dbl('importantIconSize', d.importantIconSize),
      bottomAccentHeight: dbl('bottomAccentHeight', d.bottomAccentHeight),
      bottomAccentFallbackOrangeWidth:
          dbl('bottomAccentFallbackOrangeWidth', d.bottomAccentFallbackOrangeWidth),
      topBarHeight: dbl('topBarHeight', d.topBarHeight),
      headerCompanyNameFontSize: dbl('headerCompanyNameFontSize', d.headerCompanyNameFontSize),
      headerSubTitleFontSize: dbl('headerSubTitleFontSize', d.headerSubTitleFontSize),
      headerContactFontSize: dbl('headerContactFontSize', d.headerContactFontSize),
      headerInfoFontSize: dbl('headerInfoFontSize', d.headerInfoFontSize),
      headerInfoLineVerticalPadding:
          dbl('headerInfoLineVerticalPadding', d.headerInfoLineVerticalPadding),
      headerSpacingAfter: dbl('headerSpacingAfter', d.headerSpacingAfter),
      headerPaddingTop: dbl('headerPaddingTop', d.headerPaddingTop),
      headerPaddingBottom: dbl('headerPaddingBottom', d.headerPaddingBottom),
      headerLogoToContactSpacing: dbl('headerLogoToContactSpacing', d.headerLogoToContactSpacing),
      headerAddressTopPadding: dbl('headerAddressTopPadding', d.headerAddressTopPadding),
      headerIconToTextSpacing: dbl('headerIconToTextSpacing', d.headerIconToTextSpacing),
      headerInfoToIconsRowSpacing:
          dbl('headerInfoToIconsRowSpacing', d.headerInfoToIconsRowSpacing),
      headerBottomLineThickness: dbl('headerBottomLineThickness', d.headerBottomLineThickness),
      pageMarginHorizontal: dbl('pageMarginHorizontal', d.pageMarginHorizontal),
      pageMarginVertical: dbl('pageMarginVertical', d.pageMarginVertical),
      pageMarginTop: dbl('pageMarginTop', d.pageMarginTop),
      pageMarginBottom: dbl('pageMarginBottom', d.pageMarginBottom),
      pageMarginLeft: dbl('pageMarginLeft', d.pageMarginLeft),
      pageMarginRight: dbl('pageMarginRight', d.pageMarginRight),
      pageBottomExtraSpacing: dbl('pageBottomExtraSpacing', d.pageBottomExtraSpacing),
      customerBoxFontSize: dbl('customerBoxFontSize', d.customerBoxFontSize),
      customerBoxPadding: dbl('customerBoxPadding', d.customerBoxPadding),
      customerBoxBorderWidth: dbl('customerBoxBorderWidth', d.customerBoxBorderWidth),
      customerBoxCornerRadius: dbl('customerBoxCornerRadius', d.customerBoxCornerRadius),
      customerBoxHeight: dbl('customerBoxHeight', d.customerBoxHeight),
      spacingAfterCustomerBox: dbl('spacingAfterCustomerBox', d.spacingAfterCustomerBox),
      tableMinRows: dbl('tableMinRows', d.tableMinRows),
      tableHeaderFontSize: dbl('tableHeaderFontSize', d.tableHeaderFontSize),
      tableCellFontSize: dbl('tableCellFontSize', d.tableCellFontSize),
      tableRowVerticalPadding: dbl('tableRowVerticalPadding', d.tableRowVerticalPadding),
      tableHeaderExtraVerticalPadding:
          dbl('tableHeaderExtraVerticalPadding', d.tableHeaderExtraVerticalPadding),
      tableCellHorizontalPadding: dbl('tableCellHorizontalPadding', d.tableCellHorizontalPadding),
      tableBorderWidth: dbl('tableBorderWidth', d.tableBorderWidth),
      colWidthRow: dbl('colWidthRow', d.colWidthRow),
      colWidthDescription: dbl('colWidthDescription', d.colWidthDescription),
      colWidthUnitPrice: dbl('colWidthUnitPrice', d.colWidthUnitPrice),
      colWidthTotalPrice: dbl('colWidthTotalPrice', d.colWidthTotalPrice),
      spacingAfterTable: dbl('spacingAfterTable', d.spacingAfterTable),
      sideCostsTopSpacing: dbl('sideCostsTopSpacing', d.sideCostsTopSpacing),
      sideCostsTitleFontSize: dbl('sideCostsTitleFontSize', d.sideCostsTitleFontSize),
      sideCostsItemFontSize: dbl('sideCostsItemFontSize', d.sideCostsItemFontSize),
      notesTopSpacing: dbl('notesTopSpacing', d.notesTopSpacing),
      notesFontSize: dbl('notesFontSize', d.notesFontSize),
      totalsFontSize: dbl('totalsFontSize', d.totalsFontSize),
      totalsBoldFontSize: dbl('totalsBoldFontSize', d.totalsBoldFontSize),
      totalsAccentBarWidth: dbl('totalsAccentBarWidth', d.totalsAccentBarWidth),
      totalsAccentBarHeight: dbl('totalsAccentBarHeight', d.totalsAccentBarHeight),
      totalsAccentBarSpacing: dbl('totalsAccentBarSpacing', d.totalsAccentBarSpacing),
      totalsBoxHorizontalPadding: dbl('totalsBoxHorizontalPadding', d.totalsBoxHorizontalPadding),
      totalsBoxVerticalPadding: dbl('totalsBoxVerticalPadding', d.totalsBoxVerticalPadding),
      totalsBoxBorderWidth: dbl('totalsBoxBorderWidth', d.totalsBoxBorderWidth),
      totalsBoxScale: dbl('totalsBoxScale', d.totalsBoxScale),
      spacingAfterTotals: dbl('spacingAfterTotals', d.spacingAfterTotals),
      termsTitleFontSize: dbl('termsTitleFontSize', d.termsTitleFontSize),
      termsFontSize: dbl('termsFontSize', d.termsFontSize),
      termsLineSpacing: dbl('termsLineSpacing', d.termsLineSpacing),
      termsColumnCount: integer('termsColumnCount', d.termsColumnCount),
      termsBoxPadding: dbl('termsBoxPadding', d.termsBoxPadding),
      termsBoxBorderWidth: dbl('termsBoxBorderWidth', d.termsBoxBorderWidth),
      termsBoxCornerRadius: dbl('termsBoxCornerRadius', d.termsBoxCornerRadius),
      termsBoxMinHeight: dbl('termsBoxMinHeight', d.termsBoxMinHeight),
      termsColumnDividerWidth: dbl('termsColumnDividerWidth', d.termsColumnDividerWidth),
      termsColumnDividerMargin: dbl('termsColumnDividerMargin', d.termsColumnDividerMargin),
      termsTitleToContentSpacing: dbl('termsTitleToContentSpacing', d.termsTitleToContentSpacing),
      termsFallbackBarWidth: dbl('termsFallbackBarWidth', d.termsFallbackBarWidth),
      termsFallbackBarHeight: dbl('termsFallbackBarHeight', d.termsFallbackBarHeight),
      termsFallbackBarSpacing: dbl('termsFallbackBarSpacing', d.termsFallbackBarSpacing),
      termsIconLeftPadding: dbl('termsIconLeftPadding', d.termsIconLeftPadding),
      spacingAfterTerms: dbl('spacingAfterTerms', d.spacingAfterTerms),
      signatureLineWidth: dbl('signatureLineWidth', d.signatureLineWidth),
      signatureBoxHeight: dbl('signatureBoxHeight', d.signatureBoxHeight),
      signatureBoxBorderWidth: dbl('signatureBoxBorderWidth', d.signatureBoxBorderWidth),
      signatureLabelTopSpacing: dbl('signatureLabelTopSpacing', d.signatureLabelTopSpacing),
      signatureLabelFontSize: dbl('signatureLabelFontSize', d.signatureLabelFontSize),
      signatureBetweenBoxesSpacing:
          dbl('signatureBetweenBoxesSpacing', d.signatureBetweenBoxesSpacing),
      signatureOffsetX: dbl('signatureOffsetX', d.signatureOffsetX),
      signatureOffsetY: dbl('signatureOffsetY', d.signatureOffsetY),
      stampImageSize: dbl('stampImageSize', d.stampImageSize),
    );
  }

  /// تبدیل به JSON برای ذخیره‌سازی.
  Map<String, dynamic> toJson() => {
        'colorOrange': colorOrange,
        'colorDarkGray': colorDarkGray,
        'colorLightGray': colorLightGray,
        'colorWhite': colorWhite,
        'colorBorder': colorBorder,
        'colorBorderStrong': colorBorderStrong,
        'colorSubtleText': colorSubtleText,
        'colorText': colorText,
        'logoImageHeight': logoImageHeight,
        'logoOffsetX': logoOffsetX,
        'logoOffsetY': logoOffsetY,
        'iconsRowImageHeight': iconsRowImageHeight,
        'iconsOffsetX': iconsOffsetX,
        'iconsOffsetY': iconsOffsetY,
        'contactIconSize': contactIconSize,
        'importantIconSize': importantIconSize,
        'bottomAccentHeight': bottomAccentHeight,
        'bottomAccentFallbackOrangeWidth': bottomAccentFallbackOrangeWidth,
        'topBarHeight': topBarHeight,
        'headerCompanyNameFontSize': headerCompanyNameFontSize,
        'headerSubTitleFontSize': headerSubTitleFontSize,
        'headerContactFontSize': headerContactFontSize,
        'headerInfoFontSize': headerInfoFontSize,
        'headerInfoLineVerticalPadding': headerInfoLineVerticalPadding,
        'headerSpacingAfter': headerSpacingAfter,
        'headerPaddingTop': headerPaddingTop,
        'headerPaddingBottom': headerPaddingBottom,
        'headerLogoToContactSpacing': headerLogoToContactSpacing,
        'headerAddressTopPadding': headerAddressTopPadding,
        'headerIconToTextSpacing': headerIconToTextSpacing,
        'headerInfoToIconsRowSpacing': headerInfoToIconsRowSpacing,
        'headerBottomLineThickness': headerBottomLineThickness,
        'pageMarginHorizontal': pageMarginHorizontal,
        'pageMarginVertical': pageMarginVertical,
        'pageMarginTop': pageMarginTop,
        'pageMarginBottom': pageMarginBottom,
        'pageMarginLeft': pageMarginLeft,
        'pageMarginRight': pageMarginRight,
        'pageBottomExtraSpacing': pageBottomExtraSpacing,
        'customerBoxFontSize': customerBoxFontSize,
        'customerBoxPadding': customerBoxPadding,
        'customerBoxBorderWidth': customerBoxBorderWidth,
        'customerBoxCornerRadius': customerBoxCornerRadius,
        'customerBoxHeight': customerBoxHeight,
        'spacingAfterCustomerBox': spacingAfterCustomerBox,
        'tableMinRows': tableMinRows,
        'tableHeaderFontSize': tableHeaderFontSize,
        'tableCellFontSize': tableCellFontSize,
        'tableRowVerticalPadding': tableRowVerticalPadding,
        'tableHeaderExtraVerticalPadding': tableHeaderExtraVerticalPadding,
        'tableCellHorizontalPadding': tableCellHorizontalPadding,
        'tableBorderWidth': tableBorderWidth,
        'colWidthRow': colWidthRow,
        'colWidthDescription': colWidthDescription,
        'colWidthUnitPrice': colWidthUnitPrice,
        'colWidthTotalPrice': colWidthTotalPrice,
        'spacingAfterTable': spacingAfterTable,
        'sideCostsTopSpacing': sideCostsTopSpacing,
        'sideCostsTitleFontSize': sideCostsTitleFontSize,
        'sideCostsItemFontSize': sideCostsItemFontSize,
        'notesTopSpacing': notesTopSpacing,
        'notesFontSize': notesFontSize,
        'totalsFontSize': totalsFontSize,
        'totalsBoldFontSize': totalsBoldFontSize,
        'totalsAccentBarWidth': totalsAccentBarWidth,
        'totalsAccentBarHeight': totalsAccentBarHeight,
        'totalsAccentBarSpacing': totalsAccentBarSpacing,
        'totalsBoxHorizontalPadding': totalsBoxHorizontalPadding,
        'totalsBoxVerticalPadding': totalsBoxVerticalPadding,
        'totalsBoxBorderWidth': totalsBoxBorderWidth,
        'totalsBoxScale': totalsBoxScale,
        'spacingAfterTotals': spacingAfterTotals,
        'termsTitleFontSize': termsTitleFontSize,
        'termsFontSize': termsFontSize,
        'termsLineSpacing': termsLineSpacing,
        'termsColumnCount': termsColumnCount,
        'termsBoxPadding': termsBoxPadding,
        'termsBoxBorderWidth': termsBoxBorderWidth,
        'termsBoxCornerRadius': termsBoxCornerRadius,
        'termsBoxMinHeight': termsBoxMinHeight,
        'termsColumnDividerWidth': termsColumnDividerWidth,
        'termsColumnDividerMargin': termsColumnDividerMargin,
        'termsTitleToContentSpacing': termsTitleToContentSpacing,
        'termsFallbackBarWidth': termsFallbackBarWidth,
        'termsFallbackBarHeight': termsFallbackBarHeight,
        'termsFallbackBarSpacing': termsFallbackBarSpacing,
        'termsIconLeftPadding': termsIconLeftPadding,
        'spacingAfterTerms': spacingAfterTerms,
        'signatureLineWidth': signatureLineWidth,
        'signatureBoxHeight': signatureBoxHeight,
        'signatureBoxBorderWidth': signatureBoxBorderWidth,
        'signatureLabelTopSpacing': signatureLabelTopSpacing,
        'signatureLabelFontSize': signatureLabelFontSize,
        'signatureBetweenBoxesSpacing': signatureBetweenBoxesSpacing,
        'signatureOffsetX': signatureOffsetX,
        'signatureOffsetY': signatureOffsetY,
        'stampImageSize': stampImageSize,
      };

  /// ساخت نسخه‌ی جدید با تغییر فقط بعضی فیلدها.
  InvoiceLayoutSettings copyWith({
    int? colorOrange,
    int? colorDarkGray,
    int? colorLightGray,
    int? colorWhite,
    int? colorBorder,
    int? colorBorderStrong,
    int? colorSubtleText,
    int? colorText,
    double? logoImageHeight,
    double? logoOffsetX,
    double? logoOffsetY,
    double? iconsRowImageHeight,
    double? iconsOffsetX,
    double? iconsOffsetY,
    double? contactIconSize,
    double? importantIconSize,
    double? bottomAccentHeight,
    double? bottomAccentFallbackOrangeWidth,
    double? topBarHeight,
    double? headerCompanyNameFontSize,
    double? headerSubTitleFontSize,
    double? headerContactFontSize,
    double? headerInfoFontSize,
    double? headerInfoLineVerticalPadding,
    double? headerSpacingAfter,
    double? headerPaddingTop,
    double? headerPaddingBottom,
    double? headerLogoToContactSpacing,
    double? headerAddressTopPadding,
    double? headerIconToTextSpacing,
    double? headerInfoToIconsRowSpacing,
    double? headerBottomLineThickness,
    double? pageMarginHorizontal,
    double? pageMarginVertical,
    double? pageMarginTop,
    double? pageMarginBottom,
    double? pageMarginLeft,
    double? pageMarginRight,
    double? pageBottomExtraSpacing,
    double? customerBoxFontSize,
    double? customerBoxPadding,
    double? customerBoxBorderWidth,
    double? customerBoxCornerRadius,
    double? customerBoxHeight,
    double? spacingAfterCustomerBox,
    double? tableMinRows,
    double? tableHeaderFontSize,
    double? tableCellFontSize,
    double? tableRowVerticalPadding,
    double? tableHeaderExtraVerticalPadding,
    double? tableCellHorizontalPadding,
    double? tableBorderWidth,
    double? colWidthRow,
    double? colWidthDescription,
    double? colWidthUnitPrice,
    double? colWidthTotalPrice,
    double? spacingAfterTable,
    double? sideCostsTopSpacing,
    double? sideCostsTitleFontSize,
    double? sideCostsItemFontSize,
    double? notesTopSpacing,
    double? notesFontSize,
    double? totalsFontSize,
    double? totalsBoldFontSize,
    double? totalsAccentBarWidth,
    double? totalsAccentBarHeight,
    double? totalsAccentBarSpacing,
    double? totalsBoxHorizontalPadding,
    double? totalsBoxVerticalPadding,
    double? totalsBoxBorderWidth,
    double? totalsBoxScale,
    double? spacingAfterTotals,
    double? termsTitleFontSize,
    double? termsFontSize,
    double? termsLineSpacing,
    int? termsColumnCount,
    double? termsBoxPadding,
    double? termsBoxBorderWidth,
    double? termsBoxCornerRadius,
    double? termsBoxMinHeight,
    double? termsColumnDividerWidth,
    double? termsColumnDividerMargin,
    double? termsTitleToContentSpacing,
    double? termsFallbackBarWidth,
    double? termsFallbackBarHeight,
    double? termsFallbackBarSpacing,
    double? termsIconLeftPadding,
    double? spacingAfterTerms,
    double? signatureLineWidth,
    double? signatureBoxHeight,
    double? signatureBoxBorderWidth,
    double? signatureLabelTopSpacing,
    double? signatureLabelFontSize,
    double? signatureBetweenBoxesSpacing,
    double? signatureOffsetX,
    double? signatureOffsetY,
    double? stampImageSize,
  }) {
    return InvoiceLayoutSettings(
      colorOrange: colorOrange ?? this.colorOrange,
      colorDarkGray: colorDarkGray ?? this.colorDarkGray,
      colorLightGray: colorLightGray ?? this.colorLightGray,
      colorWhite: colorWhite ?? this.colorWhite,
      colorBorder: colorBorder ?? this.colorBorder,
      colorBorderStrong: colorBorderStrong ?? this.colorBorderStrong,
      colorSubtleText: colorSubtleText ?? this.colorSubtleText,
      colorText: colorText ?? this.colorText,
      logoImageHeight: logoImageHeight ?? this.logoImageHeight,
      logoOffsetX: logoOffsetX ?? this.logoOffsetX,
      logoOffsetY: logoOffsetY ?? this.logoOffsetY,
      iconsRowImageHeight: iconsRowImageHeight ?? this.iconsRowImageHeight,
      iconsOffsetX: iconsOffsetX ?? this.iconsOffsetX,
      iconsOffsetY: iconsOffsetY ?? this.iconsOffsetY,
      contactIconSize: contactIconSize ?? this.contactIconSize,
      importantIconSize: importantIconSize ?? this.importantIconSize,
      bottomAccentHeight: bottomAccentHeight ?? this.bottomAccentHeight,
      bottomAccentFallbackOrangeWidth:
          bottomAccentFallbackOrangeWidth ?? this.bottomAccentFallbackOrangeWidth,
      topBarHeight: topBarHeight ?? this.topBarHeight,
      headerCompanyNameFontSize: headerCompanyNameFontSize ?? this.headerCompanyNameFontSize,
      headerSubTitleFontSize: headerSubTitleFontSize ?? this.headerSubTitleFontSize,
      headerContactFontSize: headerContactFontSize ?? this.headerContactFontSize,
      headerInfoFontSize: headerInfoFontSize ?? this.headerInfoFontSize,
      headerInfoLineVerticalPadding:
          headerInfoLineVerticalPadding ?? this.headerInfoLineVerticalPadding,
      headerSpacingAfter: headerSpacingAfter ?? this.headerSpacingAfter,
      headerPaddingTop: headerPaddingTop ?? this.headerPaddingTop,
      headerPaddingBottom: headerPaddingBottom ?? this.headerPaddingBottom,
      headerLogoToContactSpacing: headerLogoToContactSpacing ?? this.headerLogoToContactSpacing,
      headerAddressTopPadding: headerAddressTopPadding ?? this.headerAddressTopPadding,
      headerIconToTextSpacing: headerIconToTextSpacing ?? this.headerIconToTextSpacing,
      headerInfoToIconsRowSpacing:
          headerInfoToIconsRowSpacing ?? this.headerInfoToIconsRowSpacing,
      headerBottomLineThickness: headerBottomLineThickness ?? this.headerBottomLineThickness,
      pageMarginHorizontal: pageMarginHorizontal ?? this.pageMarginHorizontal,
      pageMarginVertical: pageMarginVertical ?? this.pageMarginVertical,
      pageMarginTop: pageMarginTop ?? this.pageMarginTop,
      pageMarginBottom: pageMarginBottom ?? this.pageMarginBottom,
      pageMarginLeft: pageMarginLeft ?? this.pageMarginLeft,
      pageMarginRight: pageMarginRight ?? this.pageMarginRight,
      pageBottomExtraSpacing: pageBottomExtraSpacing ?? this.pageBottomExtraSpacing,
      customerBoxFontSize: customerBoxFontSize ?? this.customerBoxFontSize,
      customerBoxPadding: customerBoxPadding ?? this.customerBoxPadding,
      customerBoxBorderWidth: customerBoxBorderWidth ?? this.customerBoxBorderWidth,
      customerBoxCornerRadius: customerBoxCornerRadius ?? this.customerBoxCornerRadius,
      customerBoxHeight: customerBoxHeight ?? this.customerBoxHeight,
      spacingAfterCustomerBox: spacingAfterCustomerBox ?? this.spacingAfterCustomerBox,
      tableMinRows: tableMinRows ?? this.tableMinRows,
      tableHeaderFontSize: tableHeaderFontSize ?? this.tableHeaderFontSize,
      tableCellFontSize: tableCellFontSize ?? this.tableCellFontSize,
      tableRowVerticalPadding: tableRowVerticalPadding ?? this.tableRowVerticalPadding,
      tableHeaderExtraVerticalPadding:
          tableHeaderExtraVerticalPadding ?? this.tableHeaderExtraVerticalPadding,
      tableCellHorizontalPadding: tableCellHorizontalPadding ?? this.tableCellHorizontalPadding,
      tableBorderWidth: tableBorderWidth ?? this.tableBorderWidth,
      colWidthRow: colWidthRow ?? this.colWidthRow,
      colWidthDescription: colWidthDescription ?? this.colWidthDescription,
      colWidthUnitPrice: colWidthUnitPrice ?? this.colWidthUnitPrice,
      colWidthTotalPrice: colWidthTotalPrice ?? this.colWidthTotalPrice,
      spacingAfterTable: spacingAfterTable ?? this.spacingAfterTable,
      sideCostsTopSpacing: sideCostsTopSpacing ?? this.sideCostsTopSpacing,
      sideCostsTitleFontSize: sideCostsTitleFontSize ?? this.sideCostsTitleFontSize,
      sideCostsItemFontSize: sideCostsItemFontSize ?? this.sideCostsItemFontSize,
      notesTopSpacing: notesTopSpacing ?? this.notesTopSpacing,
      notesFontSize: notesFontSize ?? this.notesFontSize,
      totalsFontSize: totalsFontSize ?? this.totalsFontSize,
      totalsBoldFontSize: totalsBoldFontSize ?? this.totalsBoldFontSize,
      totalsAccentBarWidth: totalsAccentBarWidth ?? this.totalsAccentBarWidth,
      totalsAccentBarHeight: totalsAccentBarHeight ?? this.totalsAccentBarHeight,
      totalsAccentBarSpacing: totalsAccentBarSpacing ?? this.totalsAccentBarSpacing,
      totalsBoxHorizontalPadding: totalsBoxHorizontalPadding ?? this.totalsBoxHorizontalPadding,
      totalsBoxVerticalPadding: totalsBoxVerticalPadding ?? this.totalsBoxVerticalPadding,
      totalsBoxBorderWidth: totalsBoxBorderWidth ?? this.totalsBoxBorderWidth,
      totalsBoxScale: totalsBoxScale ?? this.totalsBoxScale,
      spacingAfterTotals: spacingAfterTotals ?? this.spacingAfterTotals,
      termsTitleFontSize: termsTitleFontSize ?? this.termsTitleFontSize,
      termsFontSize: termsFontSize ?? this.termsFontSize,
      termsLineSpacing: termsLineSpacing ?? this.termsLineSpacing,
      termsColumnCount: termsColumnCount ?? this.termsColumnCount,
      termsBoxPadding: termsBoxPadding ?? this.termsBoxPadding,
      termsBoxBorderWidth: termsBoxBorderWidth ?? this.termsBoxBorderWidth,
      termsBoxCornerRadius: termsBoxCornerRadius ?? this.termsBoxCornerRadius,
      termsBoxMinHeight: termsBoxMinHeight ?? this.termsBoxMinHeight,
      termsColumnDividerWidth: termsColumnDividerWidth ?? this.termsColumnDividerWidth,
      termsColumnDividerMargin: termsColumnDividerMargin ?? this.termsColumnDividerMargin,
      termsTitleToContentSpacing: termsTitleToContentSpacing ?? this.termsTitleToContentSpacing,
      termsFallbackBarWidth: termsFallbackBarWidth ?? this.termsFallbackBarWidth,
      termsFallbackBarHeight: termsFallbackBarHeight ?? this.termsFallbackBarHeight,
      termsFallbackBarSpacing: termsFallbackBarSpacing ?? this.termsFallbackBarSpacing,
      termsIconLeftPadding: termsIconLeftPadding ?? this.termsIconLeftPadding,
      spacingAfterTerms: spacingAfterTerms ?? this.spacingAfterTerms,
      signatureLineWidth: signatureLineWidth ?? this.signatureLineWidth,
      signatureBoxHeight: signatureBoxHeight ?? this.signatureBoxHeight,
      signatureBoxBorderWidth: signatureBoxBorderWidth ?? this.signatureBoxBorderWidth,
      signatureLabelTopSpacing: signatureLabelTopSpacing ?? this.signatureLabelTopSpacing,
      signatureLabelFontSize: signatureLabelFontSize ?? this.signatureLabelFontSize,
      signatureBetweenBoxesSpacing:
          signatureBetweenBoxesSpacing ?? this.signatureBetweenBoxesSpacing,
      signatureOffsetX: signatureOffsetX ?? this.signatureOffsetX,
      signatureOffsetY: signatureOffsetY ?? this.signatureOffsetY,
      stampImageSize: stampImageSize ?? this.stampImageSize,
    );
  }
}
