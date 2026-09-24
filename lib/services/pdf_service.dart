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
  static const _layout = InvoiceLayoutSettings();

  static pw.MemoryImage? _logoImage;
  static pw.MemoryImage? _bottomAccentImage;
  static pw.MemoryImage? _iconsRowImage;
  static pw.MemoryImage? _importantIconImage;
  static pw.MemoryImage? _locationIconImage;
  static pw.MemoryImage? _phoneIconImage;
  static bool _assetsLoaded = false;

  static PdfColor get _orange => PdfColor.fromInt(_layout.colorOrange);
  static PdfColor get _darkGray => PdfColor.fromInt(_layout.colorDarkGray);
  static PdfColor get _lightGray => PdfColor.fromInt(_layout.colorLightGray);
  static PdfColor get _white => PdfColor.fromInt(_layout.colorWhite);
  static PdfColor get _border => PdfColor.fromInt(_layout.colorBorder);
  static PdfColor get _borderStrong => PdfColor.fromInt(_layout.colorBorderStrong);
  static PdfColor get _subtleText => PdfColor.fromInt(_layout.colorSubtleText);

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

  static Future<File> generateInvoicePdf({
    required Invoice invoice,
    required List<InvoiceItem> items,
    required List<SideCost> sideCosts,
    Customer? customer,
    required AppSettings settings,
  }) async {
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
        header: (context) => _header(settings, invoice),
        footer: (context) => _bottomBar(),
        build: (context) => [
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(
                horizontal: _layout.pageMarginHorizontal, vertical: _layout.pageMarginVertical),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              if (customer != null) _customerInfo(customer),
              pw.SizedBox(height: _layout.spacingAfterCustomerBox),
              _itemsTable(items),
              if (sideCosts.isNotEmpty) ..._sideCostsSection(sideCosts, settings),
              pw.SizedBox(height: _layout.spacingAfterTable),
              _totals(invoice, settings),
              if ((invoice.notes ?? '').isNotEmpty) ..._notesSection(invoice.notes!),
              pw.SizedBox(height: _layout.spacingAfterTotals),
              if (settings.termsText.isNotEmpty) _termsSection(settings.termsText),
              pw.SizedBox(height: _layout.spacingAfterTerms),
              _signatureRow(stampImage),
              pw.SizedBox(height: _layout.pageBottomExtraSpacing),
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
  static pw.Widget _header(AppSettings settings, Invoice invoice) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(height: _layout.topBarHeight, color: _orange),
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(
            horizontal: _layout.pageMarginHorizontal, vertical: _layout.headerSpacingAfter),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            // سمت راست: لوگو + نام مجموعه + تماس/آدرس (اطلاعات واقعی از تنظیمات)
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _logoImage != null
                  ? pw.Image(_logoImage!, height: _layout.logoImageHeight)
                  : pw.Text(settings.shopName,
                      style: pw.TextStyle(
                          fontSize: _layout.headerCompanyNameFontSize,
                          fontWeight: pw.FontWeight.bold,
                          color: _darkGray)),
              pw.SizedBox(height: _layout.headerLogoToContactSpacing),
              if (settings.contactNumber.isNotEmpty)
                pw.Row(children: [
                  if (_phoneIconImage != null) ...[
                    pw.Image(_phoneIconImage!, width: _layout.contactIconSize, height: _layout.contactIconSize),
                    pw.SizedBox(width: _layout.headerIconToTextSpacing),
                  ],
                  pw.Text(PersianDateUtil.toPersianDigits(settings.contactNumber),
                      style: pw.TextStyle(fontSize: _layout.headerContactFontSize, color: _orange)),
                ]),
              if (settings.address.isNotEmpty)
                pw.Padding(
                  padding: pw.EdgeInsets.only(top: _layout.headerAddressTopPadding),
                  child: pw.Row(children: [
                    if (_locationIconImage != null) ...[
                      pw.Image(_locationIconImage!,
                          width: _layout.contactIconSize, height: _layout.contactIconSize),
                      pw.SizedBox(width: _layout.headerIconToTextSpacing),
                    ],
                    pw.Flexible(
                      child: pw.Text(settings.address,
                          style: pw.TextStyle(fontSize: _layout.headerSubTitleFontSize, color: _subtleText)),
                    ),
                  ]),
                ),
            ]),
            // سمت چپ: آیکون‌های تصویری + اطلاعات فاکتور (تاریخ/شماره/نوع - داده واقعی)
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                _headerInfoLine('تاریخ', PersianDateUtil.formatDateNumeric(invoice.issueDate)),
                _headerInfoLine('شماره فاکتور', PersianDateUtil.toPersianDigits(invoice.invoiceNumber)),
                _headerInfoLine('نوع فاکتور', invoice.type.label),
              ]),
              if (_iconsRowImage != null) ...[
                pw.SizedBox(width: _layout.headerInfoToIconsRowSpacing),
                pw.Image(_iconsRowImage!, height: _layout.iconsRowImageHeight),
              ],
            ]),
          ],
        ),
      ),
      pw.Container(height: _layout.headerBottomLineThickness, color: _darkGray),
    ]);
  }

  static pw.Widget _headerInfoLine(String label, String value) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: _layout.headerInfoLineVerticalPadding),
        child: pw.Text('$label: $value', style: pw.TextStyle(fontSize: _layout.headerInfoFontSize)),
      );

  /// نوار پایین صفحه: تصویر تزئینی واقعی در صورت وجود، وگرنه بدیل رنگی ساده.
  static pw.Widget _bottomBar() {
    if (_bottomAccentImage != null) {
      return pw.SizedBox(
          width: double.infinity,
          height: _layout.bottomAccentHeight,
          child: pw.Image(_bottomAccentImage!, fit: pw.BoxFit.fill));
    }
    return pw.SizedBox(
      height: _layout.bottomAccentHeight,
      child: pw.Stack(children: [
        pw.Container(width: double.infinity, height: _layout.bottomAccentHeight, color: _darkGray),
        pw.Positioned(
            bottom: 0,
            left: 0,
            child: pw.Container(
                width: _layout.bottomAccentFallbackOrangeWidth,
                height: _layout.bottomAccentHeight,
                color: _orange)),
      ]),
    );
  }

  static pw.Widget _customerInfo(Customer c) {
    return pw.Container(
      padding: pw.EdgeInsets.all(_layout.customerBoxPadding),
      decoration: pw.BoxDecoration(
        color: _lightGray,
        border: pw.Border.all(color: _border, width: _layout.customerBoxBorderWidth),
        borderRadius: pw.BorderRadius.circular(_layout.customerBoxCornerRadius),
      ),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('مشتری: ${c.name}', style: pw.TextStyle(fontSize: _layout.customerBoxFontSize)),
        pw.Text('موبایل: ${PersianDateUtil.toPersianDigits(c.mobile)}',
            style: pw.TextStyle(fontSize: _layout.customerBoxFontSize)),
      ]),
    );
  }

  /// جدول اقلام: فقط ۴ ستون (ردیف / شرح / قیمت واحد / قیمت کل)، بدون ستون تخفیف.
  /// نکته‌ی فنی: ویجت Table جهت RTL سند را برای ترتیب فیزیکی ستون‌ها در نظر
  /// نمی‌گیرد، پس ترتیب لیست دستی برعکس شده: ایندکس ۰ = چپ‌ترین (قیمت کل)،
  /// ایندکس ۳ = راست‌ترین (ردیف).
  static pw.Widget _itemsTable(List<InvoiceItem> items) {
    final rowCount = items.length > _layout.tableMinRows.toInt() ? items.length : _layout.tableMinRows.toInt();

    pw.Widget cell(String text) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(
              vertical: _layout.tableRowVerticalPadding, horizontal: _layout.tableCellHorizontalPadding),
          child: pw.Text(text,
              textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: _layout.tableCellFontSize)),
        );

    pw.TableRow headerRow() => pw.TableRow(
          decoration: pw.BoxDecoration(color: _darkGray),
          children: ['قیمت کل', 'قیمت واحد', 'شرح', 'ردیف']
              .map((v) => pw.Container(
                    alignment: pw.Alignment.center,
                    padding: pw.EdgeInsets.symmetric(
                        vertical: _layout.tableRowVerticalPadding + _layout.tableHeaderExtraVerticalPadding),
                    child: pw.Text(v,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: _layout.tableHeaderFontSize,
                            fontWeight: pw.FontWeight.bold,
                            color: _white)),
                  ))
              .toList(),
        );

    pw.TableRow dataRow(List<String> values, bool isEven) => pw.TableRow(
          decoration: pw.BoxDecoration(color: isEven ? _lightGray : _white),
          children: values.map(cell).toList(),
        );

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: _layout.tableBorderWidth),
      columnWidths: {
        0: pw.FlexColumnWidth(_layout.colWidthTotalPrice),
        1: pw.FlexColumnWidth(_layout.colWidthUnitPrice),
        2: pw.FlexColumnWidth(_layout.colWidthDescription),
        3: pw.FlexColumnWidth(_layout.colWidthRow),
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

  static List<pw.Widget> _sideCostsSection(List<SideCost> sideCosts, AppSettings settings) {
    return [
      pw.SizedBox(height: _layout.sideCostsTopSpacing),
      pw.Text('هزینه‌های جانبی',
          style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, fontSize: _layout.sideCostsTitleFontSize, color: _darkGray)),
      ...sideCosts.map((c) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(c.title, style: pw.TextStyle(fontSize: _layout.sideCostsItemFontSize)),
              pw.Text(CurrencyFormatter.format(c.amount, settings.currency),
                  style: pw.TextStyle(fontSize: _layout.sideCostsItemFontSize)),
            ],
          )),
    ];
  }

  static List<pw.Widget> _notesSection(String notes) {
    return [
      pw.SizedBox(height: _layout.notesTopSpacing),
      pw.Text('توضیحات: $notes', style: pw.TextStyle(fontSize: _layout.notesFontSize)),
    ];
  }

  static pw.Widget _totals(Invoice invoice, AppSettings settings) {
    return pw.Row(children: [
      pw.Container(width: _layout.totalsAccentBarWidth, height: _layout.totalsAccentBarHeight, color: _orange),
      pw.SizedBox(width: _layout.totalsAccentBarSpacing),
      pw.Expanded(
        child: pw.Container(
          padding: pw.EdgeInsets.symmetric(
              horizontal: _layout.totalsBoxHorizontalPadding, vertical: _layout.totalsBoxVerticalPadding),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _borderStrong, width: _layout.totalsBoxBorderWidth),
            color: _lightGray,
          ),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('جمع کل فاکتور',
                style: pw.TextStyle(
                    fontSize: _layout.totalsBoldFontSize, fontWeight: pw.FontWeight.bold, color: _darkGray)),
            pw.Text(CurrencyFormatter.format(invoice.finalAmount, settings.currency),
                style: pw.TextStyle(
                    fontSize: _layout.totalsBoldFontSize, fontWeight: pw.FontWeight.bold, color: _orange)),
          ]),
        ),
      ),
    ]);
  }

  static pw.Widget _termsSection(String termsText) {
    final lines = termsText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return pw.SizedBox();

    final columnCount = _layout.termsColumnCount.clamp(1, 3);
    final perColumn = (lines.length / columnCount).ceil();
    final columns = <List<String>>[];
    for (var i = 0; i < columnCount; i++) {
      final start = i * perColumn;
      if (start >= lines.length) break;
      final end = (start + perColumn).clamp(0, lines.length);
      columns.add(lines.sublist(start, end));
    }

    pw.Widget bullet(String text) => pw.Padding(
          padding: pw.EdgeInsets.only(bottom: _layout.termsLineSpacing),
          child: pw.Text('•  $text', style: pw.TextStyle(fontSize: _layout.termsFontSize, color: _darkGray)),
        );

    final columnWidgets = <pw.Widget>[];
    for (var i = 0; i < columns.length; i++) {
      if (i > 0) {
        columnWidgets.add(pw.Container(
            width: _layout.termsColumnDividerWidth,
            color: _border,
            margin: pw.EdgeInsets.symmetric(horizontal: _layout.termsColumnDividerMargin)));
      }
      columnWidgets.add(pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: columns[i].map(bullet).toList()),
      ));
    }

    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(_layout.termsBoxPadding),
      decoration: pw.BoxDecoration(
        color: _lightGray,
        border: pw.Border.all(color: _border, width: _layout.termsBoxBorderWidth),
        borderRadius: pw.BorderRadius.circular(_layout.termsBoxCornerRadius),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(children: [
          if (_importantIconImage != null)
            pw.Padding(
              padding: pw.EdgeInsets.only(left: _layout.termsIconLeftPadding),
              child: pw.Image(_importantIconImage!,
                  width: _layout.importantIconSize, height: _layout.importantIconSize),
            )
          else ...[
            pw.Container(
                width: _layout.termsFallbackBarWidth, height: _layout.termsFallbackBarHeight, color: _orange),
            pw.SizedBox(width: _layout.termsFallbackBarSpacing),
          ],
          pw.Text('نکات مهم:',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: _layout.termsTitleFontSize, color: _darkGray)),
        ]),
        pw.SizedBox(height: _layout.termsTitleToContentSpacing),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: columnWidgets),
      ]),
    );
  }

  static pw.Widget _signatureRow(pw.MemoryImage? stampImage) {
    pw.Widget signatureBox(String label) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Container(
            height: _layout.signatureBoxHeight,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderStrong, width: _layout.signatureBoxBorderWidth)),
          ),
          pw.SizedBox(height: _layout.signatureLabelTopSpacing),
          pw.Text(label,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: _layout.signatureLabelFontSize, color: _darkGray)),
        ]);

    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(child: signatureBox('امضای مشتری')),
      pw.SizedBox(width: _layout.signatureBetweenBoxesSpacing),
      pw.Expanded(
        child: stampImage != null
            ? pw.Column(children: [
                pw.Container(
                  height: _layout.stampImageSize,
                  alignment: pw.Alignment.center,
                  child: pw.Image(stampImage, height: _layout.stampImageSize),
                ),
                pw.SizedBox(height: _layout.signatureLabelTopSpacing),
                pw.Text('مهر و امضای کارگاه',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: _layout.signatureLabelFontSize, color: _darkGray)),
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
