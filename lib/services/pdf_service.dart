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

/// تولید فاکتور PDF فارسی/RTL در سایز A5 عمودی، با هویت بصری نارنجی/خاکستری تیره.
///
/// تمام اندازه‌ها، فاصله‌ها و رنگ‌ها از [InvoiceLayoutSettings] خوانده می‌شوند
/// تا در آینده بدون تغییر این فایل، از داخل برنامه قابل تنظیم باشند.
///
/// ⚠️ برای نمایش صحیح فارسی، حتماً این دو فایل باید در مسیر زیر همین پروژه
/// وجود داشته باشند، وگرنه متن به‌صورت مربع/باکس دیده می‌شود:
///   assets/fonts/Vazirmatn-Regular.ttf
///   assets/fonts/Vazirmatn-Bold.ttf
class PdfService {
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;
  static const _layout = InvoiceLayoutSettings();

  static PdfColor get _orange => PdfColor.fromInt(_layout.colorOrange);
  static PdfColor get _darkGray => PdfColor.fromInt(_layout.colorDarkGray);
  static PdfColor get _lightGray => PdfColor.fromInt(_layout.colorLightGray);

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

  static Future<File> generateInvoicePdf({
    required Invoice invoice,
    required List<InvoiceItem> items,
    required List<SideCost> sideCosts,
    Customer? customer,
    required AppSettings settings,
  }) async {
    await _loadFonts();
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
              pw.SizedBox(height: 6),
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

  /// سربرگ: نوار نارنجی بالا، سمت راست لوگو (جای رزرو‌شده) + نام مجموعه،
  /// سمت چپ اطلاعات فاکتور (تاریخ/شماره/نوع).
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
            // سمت راست: جای لوگو (رزرو‌شده) + نام مجموعه
            pw.Row(children: [
              pw.Container(
                width: _layout.logoPlaceholderSize,
                height: _layout.logoPlaceholderSize,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _orange, width: 1),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                alignment: pw.Alignment.center,
                child: pw.Text('لوگو',
                    style: pw.TextStyle(fontSize: 6, color: PdfColors.grey500)),
              ),
              pw.SizedBox(width: 8),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(settings.shopName,
                    style: pw.TextStyle(
                        fontSize: _layout.headerCompanyNameFontSize,
                        fontWeight: pw.FontWeight.bold,
                        color: _darkGray)),
                if (settings.contactNumber.isNotEmpty)
                  pw.Text(PersianDateUtil.toPersianDigits(settings.contactNumber),
                      style: pw.TextStyle(fontSize: _layout.headerContactFontSize, color: _orange)),
                if (settings.address.isNotEmpty)
                  pw.Text(settings.address,
                      style: pw.TextStyle(fontSize: _layout.headerSubTitleFontSize, color: PdfColors.grey700)),
              ]),
            ]),
            // سمت چپ: اطلاعات فاکتور
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              _headerInfoLine('تاریخ', PersianDateUtil.formatDateNumeric(invoice.issueDate)),
              _headerInfoLine('شماره فاکتور', PersianDateUtil.toPersianDigits(invoice.invoiceNumber)),
              _headerInfoLine('نوع فاکتور', invoice.type.label),
            ]),
          ],
        ),
      ),
      pw.Container(height: 1.2, color: _darkGray),
    ]);
  }

  static pw.Widget _headerInfoLine(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Text('$label: $value', style: const pw.TextStyle(fontSize: 7.5)),
      );

 static pw.Widget _bottomBar() => pw.SizedBox(
        height: 10,
        child: pw.Stack(children: [
          pw.Container(width: double.infinity, height: 10, color: _darkGray),
          pw.Positioned(bottom: 0, left: 0, child: pw.Container(width: 70, height: 10, color: _orange)),
        ]),
      );

  static pw.Widget _customerInfo(Customer c) {
    return pw.Container(
      padding: pw.EdgeInsets.all(_layout.customerBoxPadding),
      decoration: pw.BoxDecoration(
        color: _lightGray,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('مشتری: ${c.name}', style: pw.TextStyle(fontSize: _layout.customerBoxFontSize)),
        pw.Text('موبایل: ${PersianDateUtil.toPersianDigits(c.mobile)}',
            style: pw.TextStyle(fontSize: _layout.customerBoxFontSize)),
      ]),
    );
  }

  /// جدول اقلام: فقط ۴ ستون (ردیف / شرح / قیمت واحد / قیمت کل)، بدون ستون تخفیف.
  /// هدر جدول با پس‌زمینه‌ی خاکستری تیره هماهنگ با هویت بصری.
  static pw.Widget _itemsTable(List<InvoiceItem> items) {
    final rowCount = items.length > _layout.tableMinRows.toInt() ? items.length : _layout.tableMinRows.toInt();

    pw.Widget cell(String text) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: _layout.tableRowVerticalPadding, horizontal: 2),
          child: pw.Text(text,
              textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: _layout.tableCellFontSize)),
        );

    pw.TableRow headerRow() => pw.TableRow(
          decoration: pw.BoxDecoration(color: _darkGray),
          children: ['قیمت کل', 'قیمت واحد', 'شرح', 'ردیف']
              .map((v) => pw.Container(
                    alignment: pw.Alignment.center,
                    padding: pw.EdgeInsets.symmetric(vertical: _layout.tableRowVerticalPadding + 2),
                    child: pw.Text(v,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: _layout.tableHeaderFontSize,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white)),
                  ))
              .toList(),
        );

    pw.TableRow dataRow(List<String> values, bool isEven) => pw.TableRow(
          decoration: pw.BoxDecoration(color: isEven ? _lightGray : PdfColors.white),
          children: values.map(cell).toList(),
        );

    // نکته‌ی فنی مهم: ویجت Table جهت RTL سند را برای ترتیب فیزیکی ستون‌ها
    // در نظر نمی‌گیرد (فقط جهت متن داخل هر سلول را درست می‌کند). برای اینکه
    // «ردیف» فیزیکی سمت راست کاغذ و «قیمت کل» سمت چپ باشد، ترتیب لیست را
    // دستی برعکس می‌کنیم: ایندکس ۰ = چپ‌ترین ستون (قیمت کل)، ایندکس ۳ = راست‌ترین (ردیف).
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
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
      pw.SizedBox(height: 4),
      pw.Text('هزینه‌های جانبی', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: _darkGray)),
      ...sideCosts.map((c) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(c.title, style: const pw.TextStyle(fontSize: 7.5)),
              pw.Text(CurrencyFormatter.format(c.amount, settings.currency),
                  style: const pw.TextStyle(fontSize: 7.5)),
            ],
          )),
    ];
  }

  static List<pw.Widget> _notesSection(String notes) {
    return [
      pw.SizedBox(height: 4),
      pw.Text('توضیحات: $notes', style: const pw.TextStyle(fontSize: 7)),
    ];
  }

  /// جمع کل فاکتور، مستقل و خارج از جدول اقلام، با نوار نارنجی کنار آن.
  static pw.Widget _totals(Invoice invoice, AppSettings settings) {
    return pw.Row(children: [
      pw.Container(width: 4, height: 26, color: _orange),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
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

  /// نکات مهم به‌صورت دو‌ستونه‌ی واقعی با جداکننده‌ی عمودی، تا متن‌ها هرگز
  /// روی هم نیفتند. ارتفاع بخش خودکار بر اساس تعداد خطوط واقعی محاسبه می‌شود
  /// (چون پهنای هر ستون خودش تعیین می‌کند چند خط لازم است).
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
        columnWidgets.add(pw.Container(width: 0.7, color: PdfColors.grey400, margin: const pw.EdgeInsets.symmetric(horizontal: 6)));
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
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(children: [
          pw.Container(width: 3, height: 9, color: _orange),
          pw.SizedBox(width: 4),
          pw.Text('نکات مهم:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: _layout.termsTitleFontSize, color: _darkGray)),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: columnWidgets),
      ]),
    );
  }

  static pw.Widget _signatureRow(pw.MemoryImage? stampImage) {
    pw.Widget signatureBox(String label) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Container(
            height: 28,
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.6)),
          ),
          pw.SizedBox(height: 2),
          pw.Text(label,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: _layout.signatureLabelFontSize, color: _darkGray)),
        ]);

    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(child: signatureBox('امضای مشتری')),
      pw.SizedBox(width: 10),
      pw.Expanded(
        child: stampImage != null
            ? pw.Column(children: [
                pw.Container(
                  height: _layout.stampImageSize,
                  alignment: pw.Alignment.center,
                  child: pw.Image(stampImage, height: _layout.stampImageSize),
                ),
                pw.SizedBox(height: 2),
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
