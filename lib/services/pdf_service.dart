import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/app_settings.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/invoice_layout_settings.dart';
import '../utils/currency_formatter.dart';
import '../utils/persian_date.dart';
import 'invoice_layout_storage.dart';
import 'visit_comparison.dart';

/// رنگ‌های PDF که از [InvoiceLayoutSettings] ساخته می‌شوند.
class _Palette {
  final PdfColor orange;
  final PdfColor darkGray;
  final PdfColor lightGray;
  final PdfColor white;
  final PdfColor border;
  final PdfColor borderStrong;
  final PdfColor subtleText;
  final PdfColor text;

  _Palette(InvoiceLayoutSettings l)
      : orange = PdfColor.fromInt(l.colorOrange),
        darkGray = PdfColor.fromInt(l.colorDarkGray),
        lightGray = PdfColor.fromInt(l.colorLightGray),
        white = PdfColor.fromInt(l.colorWhite),
        border = PdfColor.fromInt(l.colorBorder),
        borderStrong = PdfColor.fromInt(l.colorBorderStrong),
        subtleText = PdfColor.fromInt(l.colorSubtleText),
        text = PdfColor.fromInt(l.colorText);
}

/// تولید فاکتور PDF فارسی/RTL در سایز A5 عمودی، با هویت بصری واقعی
/// (لوگو و آیکون‌های تصویری از assets/) طبق تصویر مرجع.
///
/// تمام اندازه‌ها، فاصله‌ها، ضخامت‌ها و رنگ‌ها از [InvoiceLayoutSettings]
/// خوانده می‌شوند و هیچ عدد ظاهری‌ای در این فایل hard-code نشده است.
///
/// جدول اقلام هیچ سقف تعداد ردیف ندارد و هرگز با ردیف خالی پر نمی‌شود؛
/// تعداد ردیف دقیقاً برابر تعداد اقلام واقعی فاکتور است. جدول اقلام و جدول
/// هزینه‌های جانبی دو آیتم مستقل در بدنه‌ی سند هستند، به همین دلیل
/// pw.MultiPage هرگز هزینه‌های جانبی را قبل از پایان کامل اقلام اصلی شروع
/// نمی‌کند و صفحه‌بندی بر اساس فضای واقعی هر صفحه انجام می‌شود.
///
/// ⚠️ برای نمایش صحیح فارسی، حتماً این دو فایل باید در assets/fonts وجود
/// داشته باشند: Vazirmatn-Regular.ttf و Vazirmatn-Bold.ttf
///
/// تصاویر هویت بصری (در صورت نبودن هرکدام، به‌جایش یک بدیل ساده نمایش داده
/// می‌شود و برنامه هرگز کرش نمی‌کند):
///   assets/invoice_logo.png
///   assets/invoice_bottom_accent.png
///   assets/invoice_icons_row.png
///   assets/invoice_important_icon.png
///   assets/invoice_location_icon.png
///   assets/invoice_phone_icon.png
///   assets/invoice_instagram_icon.png
class PdfService {
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static pw.MemoryImage? _logoImage;
  static pw.MemoryImage? _bottomAccentImage;
  static pw.MemoryImage? _iconsRowImage;
  static pw.MemoryImage? _importantIconImage;
  static pw.MemoryImage? _locationIconImage;
  static pw.MemoryImage? _phoneIconImage;
  static pw.MemoryImage? _instagramIconImage;
  static bool _assetsLoaded = false;

  // ---- ثابت‌های چیدمان بخش میانی سربرگ (فقط ظاهر؛ هیچ داده‌ای ثابت نیست) ----
  static const double _headerSubtitleExtraFontSize = 1.5;
  static const double _headerSubtitleDashWidth = 14;
  static const double _headerSubtitleDashThickness = 1.2;
  static const double _headerNameToSubtitleGap = 3;
  static const double _headerSubtitleToContactGap = 6;
  /// ضریب بزرگ‌کردن ستون آیکون‌های سمت چپ سربرگ (تاریخ/شماره/نوع) تا فاصله‌ی
  /// آیکون‌ها با فاصله‌ی سه خط متن کنارشان هم‌تراز شود. تصویر با همین نسبت
  /// بزرگ می‌شود و کج یا کشیده نمی‌شود.
  static const double _headerIconsRowScale = 1.12;

  /// موتور PDF نیم‌فاصله (ZWNJ) را درست رسم نمی‌کند و حرف‌های دو طرفش روی هم
  /// می‌افتند (مثل «می‌باشد»، «شرف‌الدین»). پیش از چاپ، نیم‌فاصله با فاصله‌ی
  /// معمولی جایگزین می‌شود. فقط متنِ چاپ‌شده در PDF عوض می‌شود، نه داده‌ی ذخیره‌شده.
  static String _fa(String s) => s.replaceAll('\u200C', ' ');

  static Future<void> _loadFonts() async {
    if (_regularFont != null) return;
    try {
      final regularData = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
      _regularFont = pw.Font.ttf(regularData);
      final boldData = await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf');
      _boldFont = pw.Font.ttf(boldData);
    } catch (_) {
      _regularFont = null;
      _boldFont = null;
    }
  }

  static Future<pw.MemoryImage?> _tryLoadImage(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// خواندن تصویر انتخاب‌شده‌ی کاربر از حافظه‌ی گوشی. اگر مسیر خالی یا
  /// فایل ناموجود/خراب باشد، null برمی‌گردد و تصویر پیش‌فرض استفاده می‌شود.
  static Future<pw.MemoryImage?> _tryLoadFileImage(String path) async {
    if (path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return pw.MemoryImage(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<void> _loadImages() async {
    if (_assetsLoaded) return;
    _logoImage = await _tryLoadImage('assets/invoice_logo.png');
    _bottomAccentImage = await _tryLoadImage('assets/invoice_bottom_accent.png');
    _iconsRowImage = await _tryLoadImage('assets/invoice_icons_row.png');
    _importantIconImage = await _tryLoadImage('assets/invoice_important_icon.png');
    _locationIconImage = await _tryLoadImage('assets/invoice_location_icon.png');
    _phoneIconImage = await _tryLoadImage('assets/invoice_phone_icon.png');
    _instagramIconImage = await _tryLoadImage('assets/invoice_instagram_icon.png');
    _assetsLoaded = true;
  }

  /// جابه‌جایی یک ویجت. اگر هر دو مقدار صفر باشند، خود ویجت بدون تغییر برمی‌گردد
  /// تا در حالت پیش‌فرض هیچ اثری روی چیدمان نداشته باشد.
  static pw.Widget _shift(pw.Widget child, double dx, double dy) {
    if (dx == 0 && dy == 0) return child;
    return pw.Transform.translate(offset: PdfPoint(dx, -dy), child: child);
  }

  static Future<File> generateInvoicePdf({
    required Invoice invoice,
    required List<InvoiceItem> items,
    required List<SideCost> sideCosts,
    Customer? customer,
    required AppSettings settings,
    InvoiceLayoutSettings? layout,
    String vehicleLabel = '',
  }) async {
    final l = layout ?? await InvoiceLayoutStorage.load();
    final c = _Palette(l);

    await _loadFonts();
    await _loadImages();
    final visit = await VisitComparison.load(invoice);

    // لوگو و آیکون اینستاگرام: انتخاب کاربر در صورت وجود، وگرنه پیش‌فرض assets.
    final headerLogo = await _tryLoadFileImage(l.logoCustomPath) ?? _logoImage;
    final instagramIcon =
        await _tryLoadFileImage(l.instagramIconCustomPath) ?? _instagramIconImage;

    final doc = pw.Document();
    final theme = _regularFont != null
        ? pw.ThemeData.withFont(base: _regularFont!, bold: _boldFont ?? _regularFont!)
        : pw.ThemeData.base();

    pw.MemoryImage? stampImage;
    if (settings.stampImagePath != null) {
      try {
        final bytes = await File(settings.stampImagePath!).readAsBytes();
        stampImage = pw.MemoryImage(bytes);
      } catch (_) {
        stampImage = null;
      }
    }

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a5,
        margin: pw.EdgeInsets.zero,
        header: (context) => _header(l, c, settings, invoice, headerLogo, instagramIcon),
        footer: (context) => _bottomBar(l, c),
        build: (context) => [
          // اطلاعات مشتری، خارج از جدول‌ها، یک آیتم مستقل.
          pw.Padding(
            padding: pw.EdgeInsets.fromLTRB(l.pageMarginLeft, l.pageMarginTop, l.pageMarginRight, 0),
            child: customer != null
                ? pw.Column(children: [
                    _customerInfoRow(l, c, customer, vehicleLabel, invoice.mileageKm),
                    pw.SizedBox(height: l.spacingAfterCustomerBox),
                  ])
                : pw.SizedBox(),
          ),
          // جدول اقلام اصلی: آیتم مستقل، بدون هیچ ردیف خالی؛ تعداد ردیف
          // دقیقاً برابر تعداد اقلام واقعی است و pw.Table خودش بین صفحات
          // بر اساس فضای واقعی می‌شکند.
          pw.Padding(
            padding: pw.EdgeInsets.fromLTRB(l.pageMarginLeft, 0, l.pageMarginRight, 0),
            child: _itemsTable(l, c, items),
          ),
          // جدول هزینه‌های جانبی: فقط اگر وجود داشته باشد، و همیشه به‌عنوان
          // آیتم بعدیِ کامل، بعد از پایان کامل جدول اقلام اصلی.
          if (sideCosts.isNotEmpty)
            pw.Padding(
              padding: pw.EdgeInsets.fromLTRB(l.pageMarginLeft, l.sideCostsTopSpacing, l.pageMarginRight, 0),
              child: _sideCostsTable(l, c, sideCosts, settings),
            ),
          // بخش پایانی: جمع کل + توضیحات + نکات مهم + امضا، همیشه بعد از
          // پایان کامل هزینه‌های جانبی.
          pw.Padding(
            padding: pw.EdgeInsets.fromLTRB(l.pageMarginLeft, l.spacingAfterTable, l.pageMarginRight, l.pageMarginBottom),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              _totals(l, c, invoice, settings),
              if ((invoice.notes ?? '').isNotEmpty) ..._notesSection(l, c, invoice.notes!),
              pw.SizedBox(height: l.spacingAfterTotals),
              if (settings.termsText.isNotEmpty) _termsSection(l, c, settings.termsText),
              pw.SizedBox(height: l.spacingAfterTerms),
                            if (visit != null) ...[
                visit.build(
                    borderColor: c.border,
                    textColor: c.darkGray,
                    horizontalPadding: l.tableCellHorizontalPadding),
                pw.SizedBox(height: l.signatureLabelTopSpacing * 2),
              ],
              _shift(_signatureRow(l, c, stampImage), l.signatureOffsetX, l.signatureOffsetY),
              pw.SizedBox(height: l.pageBottomExtraSpacing),
            ]),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final safeNumber = invoice.invoiceNumber.replaceAll('/', '-');
    final file = File('${dir.path}/invoice_$safeNumber.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  /// خط جداکننده‌ی عمودی بین بخش‌های سربرگ.
  static pw.Widget _headerDivider(InvoiceLayoutSettings l, _Palette c) => pw.Container(
        width: l.headerDividerWidth,
        height: l.headerDividerHeight,
        color: c.border,
      );

  /// سربرگ: نوار نارنجی بالا، و زیر آن یک ردیف سه‌بخشی (از راست به چپ):
  /// ۱) لوگوی کارگاه و زیر آن آدرس فروشگاه با آیکون مکان‌یاب
  /// ۲) بخش میانی: نام فروشگاه، عبارت «تعمیرگاه تخصصی خودرو» و ردیف تماس
  ///    (اینستاگرام | تلفن، با خط عمودی بین آن‌ها)
  /// ۳) تاریخ/شماره/نوع فاکتور کنار آیکون‌های تصویری (بدون تغییر).
  ///
  /// نام فروشگاه، عبارت زیر آن، تلفن، آدرس و اینستاگرام همگی از تنظیمات خوانده می‌شوند.
  /// اگر عبارت زیر نام فروشگاه خالی باشد، آن ردیف (با دو خط نارنجی) نمایش داده نمی‌شود.
  static pw.Widget _header(InvoiceLayoutSettings l, _Palette c, AppSettings settings,
      Invoice invoice, pw.MemoryImage? logo, pw.MemoryImage? instagramIcon) {
    // تلفن و آدرس: مقدار واردشده در تنظیمات قالب؛ اگر خالی بود از تنظیمات برنامه.
    final phone = l.headerPhoneOverride.trim().isNotEmpty
        ? l.headerPhoneOverride.trim()
        : settings.contactNumber;
    final address = l.headerAddressOverride.trim().isNotEmpty
        ? l.headerAddressOverride.trim()
        : settings.address;
    final instagramUser = l.instagramUsername.trim();
    final showInstagram = l.instagramEnabled && instagramUser.isNotEmpty;
    final igIcon = instagramIcon;
    final shopName = settings.shopName.trim();
    final subtitle = settings.headerSubtitle.trim();

    // ---- بخش میانی: ردیف تماس (آیکون سمت چپِ متن، مطابق طرح مرجع) ----
    pw.Widget instagramPart() => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Text(instagramUser,
              textDirection: pw.TextDirection.ltr,
              style: pw.TextStyle(fontSize: l.headerContactFontSize, color: c.darkGray)),
          if (l.instagramIconVisible && igIcon != null) ...[
            pw.SizedBox(width: l.headerIconToTextSpacing),
            pw.Image(igIcon,
                width: l.instagramIconSize, height: l.instagramIconSize, fit: pw.BoxFit.contain),
          ],
        ]);

    pw.Widget phonePart() => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Text(PersianDateUtil.toPersianDigits(phone),
              style: pw.TextStyle(fontSize: l.headerContactFontSize, color: c.darkGray)),
          if (_phoneIconImage != null) ...[
            pw.SizedBox(width: l.headerIconToTextSpacing),
            pw.Image(_phoneIconImage!, width: l.contactIconSize, height: l.contactIconSize),
          ],
        ]);

    // ترتیب در سند RTL: اولین عنصر در راست‌ترین جا قرار می‌گیرد (اینستاگرام راست، تلفن چپ).
    final contactParts = <pw.Widget>[
      if (showInstagram) instagramPart(),
      if (phone.isNotEmpty) phonePart(),
    ];
    final contactChildren = <pw.Widget>[];
    for (var i = 0; i < contactParts.length; i++) {
      if (i > 0) {
        contactChildren.addAll([
          pw.SizedBox(width: l.headerSectionGap),
          pw.Container(width: l.headerDividerWidth, height: l.contactIconSize * 1.6, color: c.border),
          pw.SizedBox(width: l.headerSectionGap),
        ]);
      }
      contactChildren.add(contactParts[i]);
    }

    pw.Widget subtitleDash() => pw.Container(
        width: _headerSubtitleDashWidth, height: _headerSubtitleDashThickness, color: c.orange);

    // ---- بخش سمت راست: لوگو + آدرس فروشگاه زیر آن ----
    final rightSection = pw.Expanded(
      flex: 5,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          if (logo != null)
            _shift(pw.Image(logo, height: l.logoImageHeight), l.logoOffsetX, l.logoOffsetY),
          if (address.isNotEmpty)
            pw.Padding(
              padding: pw.EdgeInsets.only(top: l.headerAddressTopPadding),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (_locationIconImage != null) ...[
                  pw.Image(_locationIconImage!, width: l.contactIconSize, height: l.contactIconSize),
                  pw.SizedBox(width: l.headerIconToTextSpacing),
                ],
                pw.Expanded(
                  child: pw.Text(_fa(address),
                      style: pw.TextStyle(fontSize: l.headerSubTitleFontSize, color: c.subtleText)),
                ),
              ]),
            ),
        ],
      ),
    );

    // ---- بخش میانی: نام فروشگاه، زیرعنوان (از تنظیمات)، ردیف تماس ----
    final middleSection = pw.Expanded(
      flex: 8,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (shopName.isNotEmpty)
            pw.Text(_fa(shopName),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: l.headerCompanyNameFontSize,
                    fontWeight: pw.FontWeight.bold,
                    color: c.darkGray)),
          if (subtitle.isNotEmpty) ...[
            if (shopName.isNotEmpty) pw.SizedBox(height: _headerNameToSubtitleGap),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
              subtitleDash(),
              pw.SizedBox(width: l.headerIconToTextSpacing * 2),
              pw.Text(_fa(subtitle),
                  style: pw.TextStyle(
                      fontSize: l.headerSubTitleFontSize + _headerSubtitleExtraFontSize,
                      color: c.darkGray)),
              pw.SizedBox(width: l.headerIconToTextSpacing * 2),
              subtitleDash(),
            ]),
          ],
          if (contactChildren.isNotEmpty) ...[
            if (shopName.isNotEmpty || subtitle.isNotEmpty) pw.SizedBox(height: _headerSubtitleToContactGap),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: contactChildren),
          ],
        ],
      ),
    );

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(height: l.topBarHeight, color: c.orange),
      pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(
            l.pageMarginLeft, l.headerPaddingTop, l.pageMarginRight, l.headerPaddingBottom),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // سمت راست: لوگو + آدرس
            rightSection,
            pw.SizedBox(width: l.headerSectionGap),
            _headerDivider(l, c),
            pw.SizedBox(width: l.headerSectionGap),
            // بخش میانی: نام فروشگاه، زیرعنوان، تماس
            middleSection,
            pw.SizedBox(width: l.headerSectionGap),
            _headerDivider(l, c),
            pw.SizedBox(width: l.headerSectionGap),
            // سمت چپ: آیکون‌های تصویری + اطلاعات فاکتور (تاریخ/شماره/نوع - داده واقعی)
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                _headerInfoLine(l, c, 'تاریخ', PersianDateUtil.formatDateNumeric(invoice.issueDate)),
                _headerInfoLine(
                    l, c, 'شماره فاکتور', PersianDateUtil.toPersianDigits(invoice.invoiceNumber)),
                _headerInfoLine(l, c, 'نوع فاکتور', invoice.type.label),
              ]),
              if (_iconsRowImage != null) ...[
                pw.SizedBox(width: l.headerInfoToIconsRowSpacing),
                _shift(pw.Image(_iconsRowImage!, height: l.iconsRowImageHeight * _headerIconsRowScale), l.iconsOffsetX,
                    l.iconsOffsetY),
              ],
            ]),
          ],
        ),
      ),
      pw.Container(height: l.headerBottomLineThickness, color: c.darkGray),
    ]);
  }

  static pw.Widget _headerInfoLine(InvoiceLayoutSettings l, _Palette c, String label, String value) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: l.headerInfoLineVerticalPadding),
        child: pw.Text(_fa('$label: $value'), style: pw.TextStyle(fontSize: l.headerInfoFontSize, color: c.text)),
      );

  /// نوار پایین صفحه: تصویر تزئینی واقعی در صورت وجود، وگرنه بدیل رنگی ساده.
  static pw.Widget _bottomBar(InvoiceLayoutSettings l, _Palette c) {
    if (_bottomAccentImage != null) {
      return pw.SizedBox(
          width: double.infinity,
          height: l.bottomAccentHeight,
          child: pw.Image(_bottomAccentImage!, fit: pw.BoxFit.fill));
    }
    return pw.SizedBox(
      height: l.bottomAccentHeight,
      child: pw.Stack(children: [
        pw.Container(width: double.infinity, height: l.bottomAccentHeight, color: c.darkGray),
        pw.Positioned(
            bottom: 0,
            left: 0,
            child: pw.Container(
                width: l.bottomAccentFallbackOrangeWidth, height: l.bottomAccentHeight, color: c.orange)),
      ]),
    );
  }

  /// ردیف اطلاعات مشتری: جدول تک‌ردیفه‌ی بدون سرتیتر با حداکثر ۴ خانه‌ی جدا
  /// (از راست: مشتری، موبایل، خودرو، کیلومتر). خانه‌های خالی نمایش داده نمی‌شوند.
  static pw.Widget _customerInfoRow(
      InvoiceLayoutSettings l, _Palette c, Customer cust, String vehicleLabel, int? mileageKm) {
    // ترتیب لیست از چپ به راست فیزیکی است (جدول، RTL را خودکار نمی‌چرخاند).
    final cells = <MapEntry<String, double>>[
      if (mileageKm != null) MapEntry('کیلومتر مراجعه: ${CurrencyFormatter.formatPlain(mileageKm)}', 1.0),
      if (vehicleLabel.trim().isNotEmpty) MapEntry('خودرو: ${vehicleLabel.trim().replaceAll(' - ', ' ')}', 1.3),
      MapEntry('موبایل: ${PersianDateUtil.toPersianDigits(cust.mobile)}', 1.1),
      MapEntry('مشتری: ${cust.name}', 1.3),
    ];
    pw.Widget cell(String text) => pw.Container(
          height: l.customerBoxHeight > 0 ? l.customerBoxHeight : null,
          alignment: pw.Alignment.center,
          padding: pw.EdgeInsets.symmetric(
              horizontal: l.tableCellHorizontalPadding, vertical: l.customerBoxPadding),
          child: pw.Text(_fa(text),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: l.customerBoxFontSize, color: c.text)),
        );
    return pw.Table(
      border: pw.TableBorder.all(color: c.border, width: l.customerBoxBorderWidth),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: {
        for (var i = 0; i < cells.length; i++) i: pw.FlexColumnWidth(cells[i].value),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: c.lightGray),
          children: cells.map((e) => cell(e.key)).toList(),
        ),
      ],
    );
  }

  static pw.Widget _customerInfo(InvoiceLayoutSettings l, _Palette c, Customer cust, int? mileageKm) {
    return pw.Container(
      height: l.customerBoxHeight > 0 ? l.customerBoxHeight : null,
      alignment: l.customerBoxHeight > 0 ? pw.Alignment.center : null,
      padding: pw.EdgeInsets.all(l.customerBoxPadding),
      decoration: pw.BoxDecoration(
        color: c.lightGray,
        border: pw.Border.all(color: c.border, width: l.customerBoxBorderWidth),
        borderRadius: pw.BorderRadius.circular(l.customerBoxCornerRadius),
      ),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(_fa('مشتری: ${cust.name}'), style: pw.TextStyle(fontSize: l.customerBoxFontSize, color: c.text)),
        pw.Text('موبایل: ${PersianDateUtil.toPersianDigits(cust.mobile)}',
            style: pw.TextStyle(fontSize: l.customerBoxFontSize, color: c.text)),
        if (mileageKm != null)
          pw.Text('کیلومتر مراجعه: ${CurrencyFormatter.formatPlain(mileageKm)}',
              style: pw.TextStyle(fontSize: l.customerBoxFontSize, color: c.text)),
      ]),
    );
  }

  /// جدول اقلام: ۵ ستون (ردیف / کد کالا‌خدمت / شرح / قیمت واحد / قیمت کل)،
  /// بدون ستون تخفیف. تعداد ردیف دقیقاً برابر تعداد اقلام واقعی است؛ هیچ
  /// ردیف خالی برای رساندن به یک عدد ثابت اضافه نمی‌شود، پس فاکتورهای کم‌قلم
  /// جمع‌وجور می‌مانند و فاکتورهای پرقلم بدون سقف به صفحات بعد ادامه می‌یابند.
  ///
  /// نکته‌ی فنی: ویجت Table جهت RTL سند را برای ترتیب فیزیکی ستون‌ها در نظر
  /// نمی‌گیرد، پس ترتیب لیست دستی برعکس شده: ایندکس ۰ = چپ‌ترین (قیمت کل)،
  /// ایندکس ۴ = راست‌ترین (ردیف).
  static pw.Widget _itemsTable(InvoiceLayoutSettings l, _Palette c, List<InvoiceItem> items) {
    pw.Widget cell(String text) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(
              vertical: l.tableRowVerticalPadding, horizontal: l.tableCellHorizontalPadding),
          child: pw.Text(_fa(text),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: l.tableCellFontSize, color: c.text)),
        );

    pw.TableRow headerRow() => pw.TableRow(
          decoration: pw.BoxDecoration(color: c.darkGray),
          children: ['قیمت کل', 'قیمت واحد', 'شرح', 'کد', 'ردیف']
              .map((v) => pw.Container(
                    alignment: pw.Alignment.center,
                    padding: pw.EdgeInsets.symmetric(
                        vertical: l.tableRowVerticalPadding + l.tableHeaderExtraVerticalPadding),
                    child: pw.Text(v,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: l.tableHeaderFontSize,
                            fontWeight: pw.FontWeight.bold,
                            color: c.white)),
                  ))
              .toList(),
        );

    pw.TableRow dataRow(List<String> values, bool isEven) => pw.TableRow(
          decoration: pw.BoxDecoration(color: isEven ? c.lightGray : c.white),
          children: values.map(cell).toList(),
        );

    return pw.Table(
      border: pw.TableBorder.all(color: c.border, width: l.tableBorderWidth),
      columnWidths: {
        0: pw.FlexColumnWidth(l.colWidthTotalPrice),
        1: pw.FlexColumnWidth(l.colWidthUnitPrice),
        2: pw.FlexColumnWidth(l.colWidthDescription),
        3: pw.FlexColumnWidth(l.colWidthItemCode),
        4: pw.FlexColumnWidth(l.colWidthRow),
      },
      children: [
        headerRow(),
        for (var i = 0; i < items.length; i++)
          dataRow([
            CurrencyFormatter.formatPlain(items[i].total),
            CurrencyFormatter.formatPlain(items[i].unitPrice),
            items[i].description,
            (items[i].itemCode == null || items[i].itemCode!.isEmpty)
                ? '—'
                : PersianDateUtil.toPersianDigits(items[i].itemCode!),
            PersianDateUtil.toPersianDigits('${i + 1}'),
          ], i.isEven),
      ],
    );
  }

  /// جدول مستقل هزینه‌های جانبی: ردیف / شرح هزینه / مبلغ. همیشه بعد از
  /// پایان کامل جدول اقلام اصلی می‌آید، هرگز بین اقلام اصلی قرار نمی‌گیرد،
  /// چون خودش یک آیتم مستقل در لیست build سند است.
  static pw.Widget _sideCostsTable(
      InvoiceLayoutSettings l, _Palette c, List<SideCost> sideCosts, AppSettings settings) {
    pw.Widget cell(String text) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(
              vertical: l.tableRowVerticalPadding, horizontal: l.tableCellHorizontalPadding),
          child: pw.Text(_fa(text),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: l.sideCostsItemFontSize, color: c.text)),
        );

    pw.TableRow headerRow() => pw.TableRow(
          decoration: pw.BoxDecoration(color: c.darkGray),
          children: ['مبلغ', 'شرح هزینه', 'ردیف']
              .map((v) => pw.Container(
                    alignment: pw.Alignment.center,
                    padding: pw.EdgeInsets.symmetric(
                        vertical: l.tableRowVerticalPadding + l.tableHeaderExtraVerticalPadding),
                    child: pw.Text(v,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: l.sideCostsTitleFontSize,
                            fontWeight: pw.FontWeight.bold,
                            color: c.white)),
                  ))
              .toList(),
        );

    pw.TableRow dataRow(List<String> values, bool isEven) => pw.TableRow(
          decoration: pw.BoxDecoration(color: isEven ? c.lightGray : c.white),
          children: values.map(cell).toList(),
        );

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Text(_fa('هزینه‌های جانبی'),
          style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, fontSize: l.sideCostsTitleFontSize, color: c.darkGray)),
      pw.SizedBox(height: 3),
      pw.Table(
        border: pw.TableBorder.all(color: c.border, width: l.tableBorderWidth),
        columnWidths: const {
          0: pw.FlexColumnWidth(0.30), // مبلغ
          1: pw.FlexColumnWidth(0.55), // شرح هزینه
          2: pw.FlexColumnWidth(0.15), // ردیف
        },
        children: [
          headerRow(),
          for (var i = 0; i < sideCosts.length; i++)
            dataRow([
              CurrencyFormatter.format(sideCosts[i].amount, settings.currency),
              sideCosts[i].title,
              PersianDateUtil.toPersianDigits('${i + 1}'),
            ], i.isEven),
        ],
      ),
    ]);
  }

  static List<pw.Widget> _notesSection(InvoiceLayoutSettings l, _Palette c, String notes) {
    return [
      pw.SizedBox(height: l.notesTopSpacing),
      pw.Text(_fa('توضیحات: $notes'), style: pw.TextStyle(fontSize: l.notesFontSize, color: c.text)),
    ];
  }

  static pw.Widget _totals(InvoiceLayoutSettings l, _Palette c, Invoice invoice, AppSettings settings) {
    return pw.Row(children: [
      pw.Container(width: l.totalsAccentBarWidth, height: l.totalsAccentBarHeight, color: c.orange),
      pw.SizedBox(width: l.totalsAccentBarSpacing),
      pw.Expanded(
        child: pw.Container(
          padding: pw.EdgeInsets.symmetric(
              horizontal: l.totalsBoxHorizontalPadding, vertical: l.totalsBoxVerticalPadding),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: c.borderStrong, width: l.totalsBoxBorderWidth),
            color: c.lightGray,
          ),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('جمع کل فاکتور',
                style: pw.TextStyle(
                    fontSize: l.totalsBoldFontSize, fontWeight: pw.FontWeight.bold, color: c.darkGray)),
            pw.Text(CurrencyFormatter.format(invoice.finalAmount, settings.currency),
                style: pw.TextStyle(
                    fontSize: l.totalsBoldFontSize, fontWeight: pw.FontWeight.bold, color: c.orange)),
          ]),
        ),
      ),
    ]);
  }

  static pw.Widget _termsSection(InvoiceLayoutSettings l, _Palette c, String termsText) {
    final lines = termsText.split('\n').where((x) => x.trim().isNotEmpty).toList();
    if (lines.isEmpty) return pw.SizedBox();

    final columnCount = l.termsColumnCount.clamp(1, 3);
    final perColumn = (lines.length / columnCount).ceil();
    final columns = <List<String>>[];
    for (var i = 0; i < columnCount; i++) {
      final start = i * perColumn;
      if (start >= lines.length) break;
      final end = (start + perColumn).clamp(0, lines.length);
      columns.add(lines.sublist(start, end));
    }

    pw.Widget bullet(String text) => pw.Padding(
          padding: pw.EdgeInsets.only(bottom: l.termsLineSpacing),
          child: pw.Text(_fa('•  $text'), style: pw.TextStyle(fontSize: l.termsFontSize, color: c.darkGray)),
        );

    final columnWidgets = <pw.Widget>[];
    for (var i = 0; i < columns.length; i++) {
      if (i > 0) {
        columnWidgets.add(pw.Container(
            width: l.termsColumnDividerWidth,
            color: c.border,
            margin: pw.EdgeInsets.symmetric(horizontal: l.termsColumnDividerMargin)));
      }
      columnWidgets.add(pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: columns[i].map(bullet).toList()),
      ));
    }

    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(l.termsBoxPadding),
      decoration: pw.BoxDecoration(
        color: c.lightGray,
        border: pw.Border.all(color: c.border, width: l.termsBoxBorderWidth),
        borderRadius: pw.BorderRadius.circular(l.termsBoxCornerRadius),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(children: [
          if (_importantIconImage != null)
            pw.Padding(
              padding: pw.EdgeInsets.only(left: l.termsIconLeftPadding),
              child: pw.Image(_importantIconImage!, width: l.importantIconSize, height: l.importantIconSize),
            )
          else ...[
            pw.Container(width: l.termsFallbackBarWidth, height: l.termsFallbackBarHeight, color: c.orange),
            pw.SizedBox(width: l.termsFallbackBarSpacing),
          ],
          pw.Text('نکات مهم:',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: l.termsTitleFontSize, color: c.darkGray)),
        ]),
        pw.SizedBox(height: l.termsTitleToContentSpacing),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: columnWidgets),
      ]),
    );
  }

  static pw.Widget _signatureRow(InvoiceLayoutSettings l, _Palette c, pw.MemoryImage? stampImage) {
    pw.Widget signatureBox(String label) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Container(
            height: l.signatureBoxHeight,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: c.borderStrong, width: l.signatureBoxBorderWidth)),
          ),
          pw.SizedBox(height: l.signatureLabelTopSpacing),
          pw.Text(label,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: l.signatureLabelFontSize, color: c.darkGray)),
        ]);

    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(child: signatureBox('امضای مشتری')),
      pw.SizedBox(width: l.signatureBetweenBoxesSpacing),
      pw.Expanded(
        child: stampImage != null
            ? pw.Column(children: [
                pw.Container(
                  height: l.stampImageSize,
                  alignment: pw.Alignment.center,
                  child: pw.Image(stampImage, height: l.stampImageSize),
                ),
                pw.SizedBox(height: l.signatureLabelTopSpacing),
                pw.Text('مهر و امضای کارگاه',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: l.signatureLabelFontSize, color: c.darkGray)),
              ])
            : signatureBox('مهر و امضای کارگاه'),
      ),
    ]);
  }

  static Future<void> printInvoice(File pdfFile) async {
    await Printing.layoutPdf(onLayout: (format) => pdfFile.readAsBytes());
  }

  static Future<void> shareInvoice(File pdfFile, String invoiceNumber) async {
    final safeNumber = invoiceNumber.replaceAll('/', '-');
    await Printing.sharePdf(bytes: await pdfFile.readAsBytes(), filename: 'invoice_$safeNumber.pdf');
  }
}
