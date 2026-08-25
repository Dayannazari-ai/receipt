import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/app_settings.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../utils/currency_formatter.dart';
import '../utils/persian_date.dart';

/// تولید فاکتور PDF فارسی/RTL در سایز A5.
///
/// ⚠️ برای نمایش صحیح فارسی، حتماً این دو فایل باید در مسیر زیر همین پروژه
/// (نه پروژه‌ی قدیمی!) وجود داشته باشند، وگرنه متن به‌صورت مربع/باکس دیده می‌شود:
///   assets/fonts/Vazirmatn-Regular.ttf
///   assets/fonts/Vazirmatn-Bold.ttf
class PdfService {
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

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
        margin: const pw.EdgeInsets.all(20),
        header: (context) => _header(settings, invoice),
        build: (context) => [
          pw.SizedBox(height: 8),
          if (customer != null) _customerInfo(customer),
          pw.SizedBox(height: 12),
          pw.Text('اقلام فاکتور', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 4),
          _itemsTable(items),
          if (sideCosts.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('هزینه‌های جانبی', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            ...sideCosts.map((c) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text(c.title, style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(CurrencyFormatter.format(c.amount, settings.currency), style: const pw.TextStyle(fontSize: 9))],
                )),
          ],
          pw.SizedBox(height: 10),
          _totals(invoice, settings),
          if ((invoice.notes ?? '').isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text('توضیحات:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(invoice.notes!, style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 16),
          if (settings.termsText.isNotEmpty) ...[
            pw.Divider(),
            pw.Text('نکات مهم:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text(settings.termsText, style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 10),
          ],
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('امضای مشتری:', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 24),
              pw.Container(width: 120, height: 0.5, color: PdfColors.grey600),
            ]),
            if (stampImage != null)
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('مهر و امضای کارگاه:', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Image(stampImage, width: 80, height: 80),
              ]),
          ]),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final safeNumber = invoice.invoiceNumber.replaceAll('/', '-');
    final file = File('${dir.path}/invoice_$safeNumber.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static pw.Widget _header(AppSettings settings, Invoice invoice) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('${invoice.type.label} - شماره ${PersianDateUtil.toPersianDigits(invoice.invoiceNumber)}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.Text('تاریخ: ${PersianDateUtil.formatDateNumeric(invoice.issueDate)}',
              style: const pw.TextStyle(fontSize: 10)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(settings.shopName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          if (settings.contactNumber.isNotEmpty)
            pw.Text(settings.contactNumber, style: const pw.TextStyle(fontSize: 9)),
        ]),
      ]),
      pw.SizedBox(height: 6),
      pw.Divider(),
    ]);
  }

  static pw.Widget _customerInfo(Customer c) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
      child: pw.Row(children: [
        pw.Text('مشتری: ${c.name}   ', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('موبایل: ${PersianDateUtil.toPersianDigits(c.mobile)}', style: const pw.TextStyle(fontSize: 9)),
      ]),
    );
  }

  static pw.Widget _itemsTable(List<InvoiceItem> items) {
    return pw.TableHelper.fromTextArray(
      headers: ['ردیف', 'شرح', 'تعداد', 'قیمت واحد', 'مبلغ کل'],
      data: List.generate(items.length, (i) {
        final it = items[i];
        return [
          PersianDateUtil.toPersianDigits('${i + 1}'),
          it.description,
          PersianDateUtil.toPersianDigits('${it.quantity}'),
          CurrencyFormatter.formatPlain(it.unitPrice),
          CurrencyFormatter.formatPlain(it.total),
        ];
      }),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.center,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    );
  }

  static pw.Widget _totals(Invoice invoice, AppSettings settings) {
    pw.Widget row(String label, double amount, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(CurrencyFormatter.format(amount, settings.currency),
                style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ]),
        );
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      row('جمع اقلام', invoice.itemsTotal),
      row('هزینه جانبی', invoice.sideCosts),
      pw.Divider(),
      row('جمع فاکتور', invoice.finalAmount, bold: true),
      pw.SizedBox(height: 3),
      pw.Text('نوع پرداخت: ${invoice.paymentType.label}', style: const pw.TextStyle(fontSize: 9)),
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
