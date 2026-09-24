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
class PdfService {
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static pw.MemoryImage? _logoImage;
  static pw.MemoryImage? _bottomAccentImage;
  static pw.MemoryImage? _iconsRowImage;
  static pw.MemoryImage? _importantIconImage;
  static pw.MemoryImage? _locationIconImage;
  static pw.MemoryImage? _phoneIconImage;
  static bool _assetsLoaded = false;

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

  static Future<void> _loadImages() async {
    if (_assetsLoaded) return;
    _logoImage = await _tryLoadImage('assets/invoice_logo.png');
    _bottomAccentImage = await _tryLoadImage('assets/invoice_bottom_accent.png');
    _iconsRowImage = await _tryLoadImage('assets/invoice_icons_row.png');
    _importantIconImage = await _tryLoadImage('assets/invoice_important_icon.png');
    _locationIconImage = await _tryLoadImage('assets/invoice_location_icon.png');
    _phoneIconImage = await _tryLoadImage('assets/invoice_phone_icon.png');
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
  }) async {
    final l = layout ?? await InvoiceLayoutStorage.load();
    final c = _Palette(l);

    await _loadFonts();
    await _loadImages();
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
        header: (context) => _header(l, c, settings, invoice),
        footer: (context) => _bottomBar(l, c),
        build: (context) => [
          pw.Padding(
            padding: pw.EdgeInsets.fromLTRB(
                l.pageMarginLeft, l.pageMarginTop, l.pageMarginRight, l.pageMarginBottom),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              if (customer != null) _customerInfo(l, c, customer),
              pw.SizedBox(height: l.spacingAfterCustomerBox),
              _itemsTable(l, c, items),
              if (sideCosts.isNotEmpty) ..._sideCostsSection(l, c, sideCosts, settings),
              pw.SizedBox(height: l.spacingAfterTable),
              _totals(l, c, invoice, settings),
              if ((invoice.notes ?? '').isNotEmpty) ..._notesSection(l, c, invoice.notes!),
              pw.SizedBox(height: l.spacingAfterTotals),
              if (settings.termsText.isNotEmpty) _termsSection(l, c, settings.termsText),
              pw.SizedBox(height: l.spacingAfterTerms),
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

  /// سربرگ: نوار نارنجی بالا، سمت راست لوگوی تصویری + نام/تماس/آدرس پویا،
  /// سمت چپ آیکون‌های تصویری تاریخ/شماره/نوع فاکتور کنار متن پویا.
  static pw.Widget _header(
      InvoiceLayoutSettings l, _Palette c, AppSettings settings, Invoice invoice) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(height: l.topBarHeight, color: c.orange),
      pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(
            l.pageMarginLeft, l.headerPaddingTop, l.pageMarginRight, l.headerPaddingBottom),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            // سمت راست: لوگو + نام مجموعه + تماس/آدرس (اطلاعات واقعی از تنظیمات)
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _shift(
                _logoImage != null
                    ? pw.Image(_logoImage!, height: l.logoImageHeight)
                    : pw.Text(settings.shopName,
                        style: pw.TextStyle(
                            fontSize: l.headerCompanyNameFontSize,
                            fontWeight: pw.FontWeight.bold,
                            color: c.darkGray)),
                l.logoOffsetX,
                l.logoOffsetY,
              ),
              pw.SizedBox(height: l.headerLogoToContactSpacing),
              if (settings.contactNumber.isNotEmpty)
                pw.Row(children: [
                  if (_phoneIconImage != null) ...[
                    pw.Image(_phoneIconImage!, width: l.contactIconSize, height: l.contactIconSize),
                    pw.SizedBox(width: l.headerIconToTextSpacing),
                  ],
                  pw.Text(PersianDateUtil.toPersianDigits(settings.contactNumber),
                      style: pw.TextStyle(fontSize: l.headerContactFontSize, color: c.orange)),
                ]),
              if (settings.address.isNotEmpty)
                pw.Padding(
                  padding: pw.EdgeInsets.only(top: l.headerAddressTopPadding),
                  child: pw.Row(children: [
                    if (_locationIconImage != null) ...[
                      pw.Image(_locationIconImage!, width: l.contactIconSize, height: l.contactIconSize),
                      pw.SizedBox(width: l.headerIconToTextSpacing),
                    ],
                    pw.Flexible(
                      child: pw.Text(settings.address,
                          style: pw.TextStyle(fontSize: l.headerSubTitleFontSize, color: c.subtleText)),
                    ),
                  ]),
                ),
            ]),
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
                _shift(pw.Image(_iconsRowImage!, height: l.iconsRowImageHeight), l.iconsOffsetX,
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
        child: pw.Text('$label: $value', style: pw.TextStyle(fontSize: l.headerInfoFontSize, color: c.text)),
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

  static pw.Widget _customerInfo(InvoiceLayoutSettings l, _Palette c, Customer cust) {
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
        pw.Text('مشتری: ${cust.name}', style: pw.TextStyle(fontSize: l.customerBoxFontSize, color: c.text)),
        pw.Text('موبایل: ${PersianDateUtil.toPersianDigits(cust.mobile)}',
            style: pw.TextStyle(fontSize: l.customerBoxFontSize, color: c.text)),
      ]),
    );
  }

  /// جدول اقلام: فقط ۴ ستون (ردیف / شرح / قیمت واحد / قیمت کل)، بدون ستون تخفیف.
  /// نکته‌ی فنی: ویجت Table جهت RTL سند را برای ترتیب فیزیکی ستون‌ها در نظر
  /// نمی‌گیرد، پس ترتیب لیست دستی برعکس شده: ایندکس ۰ = چپ‌ترین (قیمت کل)،
  /// ایندکس ۳ = راست‌ترین (ردیف).
  static pw.Widget _itemsTable(InvoiceLayoutSettings l, _Palette c, List<InvoiceItem> items) {
    final rowCount = items.length > l.tableMinRows.toInt() ? items.length : l.tableMinRows.toInt();

    pw.Widget cell(String text) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(
              vertical: l.tableRowVerticalPadding, horizontal: l.tableCellHorizontalPadding),
          child: pw.Text(text,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: l.tableCellFontSize, color: c.text)),
        );

    pw.TableRow headerRow() => pw.TableRow(
          decoration: pw.BoxDecoration(color: c.darkGray),
          children: ['قیمت کل', 'قیمت واحد', 'شرح', 'ردیف']
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
        3: pw.FlexColumnWidth(l.colWidthRow),
      },
      children: [
        headerRow(),
        for (var i = 0; i < rowCount; i++)
          i < items.length
              ? dataRow([
                  CurrencyFormatter.formatPlain(items[i].total),
                  CurrencyFormatter.formatPlain(items[i].unitPrice),
                  items[i].description,
                  PersianDateUtil.toPersianDigits('${i + 1}'),
                ], i.isEven)
              : dataRow(['', '', '', PersianDateUtil.toPersianDigits('${i + 1}')], i.isEven),
      ],
    );
  }

  static List<pw.Widget> _sideCostsSection(
      InvoiceLayoutSettings l, _Palette c, List<SideCost> sideCosts, AppSettings settings) {
    return [
      pw.SizedBox(height: l.sideCostsTopSpacing),
      pw.Text('هزینه‌های جانبی',
          style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, fontSize: l.sideCostsTitleFontSize, color: c.darkGray)),
      ...sideCosts.map((sc) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(sc.title, style: pw.TextStyle(fontSize: l.sideCostsItemFontSize, color: c.text)),
              pw.Text(CurrencyFormatter.format(sc.amount, settings.currency),
                  style: pw.TextStyle(fontSize: l.sideCostsItemFontSize, color: c.text)),
            ],
          )),
    ];
  }

  static List<pw.Widget> _notesSection(InvoiceLayoutSettings l, _Palette c, String notes) {
    return [
      pw.SizedBox(height: l.notesTopSpacing),
      pw.Text('توضیحات: $notes', style: pw.TextStyle(fontSize: l.notesFontSize, color: c.text)),
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
          child: pw.Text('•  $text', style: pw.TextStyle(fontSize: l.termsFontSize, color: c.darkGray)),
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
