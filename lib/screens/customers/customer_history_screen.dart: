import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../models/app_settings.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import '../invoices/invoice_detail_screen.dart';

/// نمایش سوابق فاکتورهای یک مشتری خاص. فاکتورها بر اساس شناسه‌ی واقعی
/// مشتری (customer_id) خوانده می‌شوند، نه نام - تا مشتریان هم‌نام با هم
/// قاطی نشوند. این صفحه فقط برای مشاهده است و هیچ فاکتوری را تغییر نمی‌دهد.
class CustomerHistoryScreen extends StatefulWidget {
  final Customer customer;
  const CustomerHistoryScreen({super.key, required this.customer});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final _invoiceRepo = InvoiceRepository();
  final _settingsRepo = SettingsRepository();
  List<Invoice> _invoices = [];
  AppSettings _settings = AppSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final invoices = await _invoiceRepo.getByCustomerId(widget.customer.id!);
    final settings = await _settingsRepo.getSettings();
    if (!mounted) return;
    setState(() {
      _invoices = invoices;
      _settings = settings;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('سوابق فاکتورهای ${widget.customer.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invoices.isEmpty
              ? const Center(child: Text('برای این مشتری فاکتور قبلی ثبت نشده است.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _invoices.length,
                  itemBuilder: (context, i) {
                    final inv = _invoices[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text('${inv.type.label} - ${PersianDateUtil.toPersianDigits(inv.invoiceNumber)}'),
                        subtitle: Text(
                            '${PersianDateUtil.formatDate(inv.issueDate)} - ${inv.paymentType.label}'),
                        trailing: Text(
                          CurrencyFormatter.format(inv.finalAmount, _settings.currency),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id!))),
                      ),
                    );
                  },
                ),
    );
  }
}
