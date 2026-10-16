import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/app_settings.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../services/pdf_service.dart';
import '../../utils/persian_date.dart';

/// پیش‌نمایش فاکتور قبل از صدور نهایی.
///
/// هیچ چیزی در دیتابیس نوشته نمی‌شود؛ فقط PDF از روی آبجکت‌های موقت ساخته
/// می‌شود. خروجی صفحه: true = «تأیید و صدور نهایی»، false/null = «بازگشت و
/// اصلاح» (فرم رسید با همه‌ی اطلاعاتش دست‌نخورده می‌ماند).
class InvoicePreviewScreen extends StatelessWidget {
  final Invoice invoice;
  final List<InvoiceItem> items;
  final List<SideCost> sideCosts;
  final Customer? customer;
  final AppSettings settings;
  final String vehicleLabel;

  const InvoicePreviewScreen({
    super.key,
    required this.invoice,
    required this.items,
    required this.sideCosts,
    required this.customer,
    required this.settings,
    this.vehicleLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final payText = invoice.paymentType == PaymentType.nonCash && invoice.checkDueDate != null
        ? '${invoice.paymentType.label} (سررسید ${PersianDateUtil.formatDateNumeric(invoice.checkDueDate!)})'
        : invoice.paymentType.label;

    return Scaffold(
      appBar: AppBar(title: const Text('پیش‌نمایش قبل از صدور')),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: primary.withOpacity(0.10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'شماره فاکتور: ${PersianDateUtil.toPersianDigits(invoice.invoiceNumber)}   |   نوع پرداخت: $payText',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if ((invoice.paymentAccountInfo ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('حساب مقصد: ${invoice.paymentAccountInfo}', style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 2),
            const Text('این فقط پیش‌نمایش است؛ تا تأیید نهایی چیزی ثبت نمی‌شود.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
        Expanded(
          child: PdfPreview(
            build: (format) async {
              final file = await PdfService.generateInvoicePdf(
                invoice: invoice,
                items: items,
                sideCosts: sideCosts,
                customer: customer,
                settings: settings,
                vehicleLabel: vehicleLabel,
              );
              return file.readAsBytes();
            },
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('بازگشت و اصلاح'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('تأیید و صدور نهایی'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
