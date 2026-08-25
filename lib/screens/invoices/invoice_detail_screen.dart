import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/invoice.dart';
import '../../models/customer.dart';
import '../../models/app_settings.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/customer_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/pdf_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final int invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _invoiceRepo = InvoiceRepository();
  final _customerRepo = CustomerRepository();
  final _settingsRepo = SettingsRepository();

  Invoice? _invoice;
  List<InvoiceItem> _items = [];
  List<SideCost> _sideCosts = [];
  Customer? _customer;
  AppSettings _settings = AppSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final invoice = await _invoiceRepo.getById(widget.invoiceId);
    if (invoice == null) {
      setState(() => _loading = false);
      return;
    }
    final items = await _invoiceRepo.getItems(widget.invoiceId);
    final sideCosts = await _invoiceRepo.getSideCosts(widget.invoiceId);
    final customer = invoice.customerId != null ? await _customerRepo.getById(invoice.customerId!) : null;
    final settings = await _settingsRepo.getSettings();
    if (!mounted) return;
    setState(() {
      _invoice = invoice;
      _items = items;
      _sideCosts = sideCosts;
      _customer = customer;
      _settings = settings;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_invoice == null) return const Scaffold(body: Center(child: Text('فاکتور یافت نشد')));
    final inv = _invoice!;

    return Scaffold(
      appBar: AppBar(title: Text('${inv.type.label} - ${PersianDateUtil.toPersianDigits(inv.invoiceNumber)}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_customer != null) _row('مشتری', _customer!.name),
              if (_customer != null) _row('موبایل', PersianDateUtil.toPersianDigits(_customer!.mobile)),
              _row('تاریخ صدور', PersianDateUtil.formatDate(inv.issueDate)),
              _row('نوع پرداخت', inv.paymentType.label),
              if ((inv.paymentAccountInfo ?? '').isNotEmpty) _row('حساب مقصد', inv.paymentAccountInfo!),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        const Text('اقلام فاکتور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ..._items.map((it) => Card(
              child: ListTile(
                leading: Icon(
                    it.itemType == InvoiceItemType.service ? Icons.build_outlined : Icons.inventory_2_outlined),
                title: Text(it.description),
                subtitle: Text(
                    '${PersianDateUtil.toPersianDigits('${it.quantity}')} × ${CurrencyFormatter.format(it.unitPrice, _settings.currency)}'),
                trailing: Text(CurrencyFormatter.format(it.total, _settings.currency)),
              ),
            )),
        if (_sideCosts.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('هزینه‌های جانبی', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._sideCosts.map((c) => ListTile(
                dense: true,
                title: Text(c.title),
                trailing: Text(CurrencyFormatter.format(c.amount, _settings.currency)),
              )),
        ],
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _totalRow('جمع اقلام', inv.itemsTotal),
              _totalRow('هزینه جانبی', inv.sideCosts),
              const Divider(),
              _totalRow('جمع فاکتور', inv.finalAmount, bold: true),
            ]),
          ),
        ),
        if ((inv.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('توضیحات: ${inv.notes}'),
        ],
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('پیش‌نمایش فاکتور'),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('پیش‌نمایش فاکتور')),
                body: PdfPreview(
                  build: (format) async {
                    final file = await PdfService.generateInvoicePdf(
                        invoice: inv, items: _items, sideCosts: _sideCosts, customer: _customer, settings: _settings);
                    return file.readAsBytes();
                  },
                  allowPrinting: true,
                  allowSharing: true,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                ),
              ),
            ));
          },
        ),
      ]),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _totalRow(String label, double amount, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: style),
        Text(CurrencyFormatter.format(amount, _settings.currency), style: style),
      ]),
    );
  }
}
