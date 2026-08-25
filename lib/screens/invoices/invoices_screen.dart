import 'package:flutter/material.dart';
import '../../models/invoice.dart';
import '../../models/app_settings.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/customer_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import 'invoice_detail_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> with SingleTickerProviderStateMixin {
  final _invoiceRepo = InvoiceRepository();
  final _customerRepo = CustomerRepository();
  final _settingsRepo = SettingsRepository();
  late TabController _tab;
  List<Invoice> _invoices = [];
  Map<int, String> _customerNames = {};
  Currency _currency = Currency.toman;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _load();
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final invoices = await _invoiceRepo.getAll(
      onlySales: _tab.index == 0,
      onlyPurchases: _tab.index == 1,
    );
    final customers = await _customerRepo.getAll();
    final settings = await _settingsRepo.getSettings();
    if (!mounted) return;
    setState(() {
      _invoices = invoices;
      _customerNames = {for (final c in customers) c.id!: c.name};
      _currency = settings.currency;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // گروه‌بندی بر اساس تاریخ (روز)
    final Map<String, List<Invoice>> grouped = {};
    for (final inv in _invoices) {
      final day = inv.issueDate.substring(0, 10);
      grouped.putIfAbsent(day, () => []).add(inv);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('تراکنش‌ها'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'فاکتور فروش'), Tab(text: 'فاکتور خرید')]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invoices.isEmpty
              ? const Center(child: Text('فاکتوری ثبت نشده است'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: days.expand((day) {
                    final list = grouped[day]!;
                    return [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(PersianDateUtil.formatDateShort(day),
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                      ),
                      ...list.map((inv) => Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.green.shade50,
                                child: const Icon(Icons.receipt_long_outlined, color: Colors.green),
                              ),
                              title: Text('#${PersianDateUtil.toPersianDigits(inv.invoiceNumber)}  '
                                  '${inv.customerId != null ? _customerNames[inv.customerId] ?? '' : ''}'),
                              subtitle: Text(inv.type.label),
                              trailing:
                                  Text(CurrencyFormatter.format(inv.finalAmount, _currency), style: const TextStyle(fontWeight: FontWeight.bold)),
                              onTap: () => Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: inv.id!))),
                            ),
                          )),
                    ];
                  }).toList(),
                ),
    );
  }
}
