import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../models/app_settings.dart';
import '../../models/finance_cheque.dart';
import '../../models/finance_transaction.dart';
import '../../repositories/finance_invoice_posting.dart';
import '../../repositories/finance_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';

/// چک‌های فاکتورهای فروش/خرید کالا. تا «وصول»، چک روی مانده‌ی حساب اثر
/// ندارد؛ با وصول، تراکنش‌های واقعی فاکتور با تاریخ وصول در دفتر ثبت می‌شوند.
class FinanceChequesScreen extends StatefulWidget {
  const FinanceChequesScreen({super.key});

  @override
  State<FinanceChequesScreen> createState() => _FinanceChequesScreenState();
}

class _FinanceChequesScreenState extends State<FinanceChequesScreen> {
  final _settingsRepo = SettingsRepository();
  AppSettings _settings = AppSettings();
  List<FinanceCheque> _pending = [];
  List<FinanceCheque> _collected = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _settingsRepo.getSettings();
    final all = await FinanceInvoicePosting.listCheques();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _pending = all.where((c) => c.isPending).toList();
      _collected = all.where((c) => !c.isPending).toList();
      _loading = false;
    });
  }

  void _showMsg(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _collect(FinanceCheque cheque) async {
    final jalali = await showPersianDatePicker(
      context: context,
      initialDate: Jalali.fromDateTime(DateTime.now()),
      firstDate: Jalali(1394, 1, 1),
      lastDate: Jalali(1450, 12, 29),
    );
    if (jalali == null || !mounted) return;
    final collectedAt = jalali.toDateTime();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('وصول چک'),
        content: Text(
            'چک فاکتور ${PersianDateUtil.toPersianDigits(cheque.invoiceNumber ?? '')} به مبلغ ${CurrencyFormatter.format(cheque.amount, _settings.currency)} '
            'در تاریخ ${PersianDateUtil.formatDateNumeric(collectedAt.toIso8601String())} در دفتر ثبت شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت وصول')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await FinanceInvoicePosting.collectCheque(chequeId: cheque.id!, collectedAt: collectedAt);
      _showMsg('چک وصول و در دفتر ثبت شد');
      await _load();
    } catch (e) {
      _showMsg(financeErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isOverdue(FinanceCheque c) {
    if (!c.isPending || c.dueDate == null) return false;
    final due = DateTime.tryParse(c.dueDate!);
    if (due == null) return false;
    final now = DateTime.now();
    return due.isBefore(DateTime(now.year, now.month, now.day));
  }

  Widget _tile(FinanceCheque c) {
    final isIn = c.direction == FinanceDirection.inflow;
    final overdue = _isOverdue(c);
    final due = c.dueDate == null ? '—' : PersianDateUtil.formatDateNumeric(c.dueDate!);
    return Card(
      child: ListTile(
        leading: Icon(isIn ? Icons.south_west : Icons.north_east, color: isIn ? Colors.green : Colors.red),
        title: Text('فاکتور ${PersianDateUtil.toPersianDigits(c.invoiceNumber ?? '')}'),
        subtitle: Text(
          '${isIn ? 'چک دریافتی' : 'چک پرداختی'} • سررسید: $due${overdue ? ' (گذشته)' : ''}\n'
          '${CurrencyFormatter.format(c.amount, _settings.currency)}',
          style: TextStyle(color: overdue ? Colors.red : null),
        ),
        isThreeLine: true,
        trailing: c.isPending
            ? TextButton(onPressed: _busy ? null : () => _collect(c), child: const Text('وصول'))
            : const Icon(Icons.check_circle, color: Colors.green),
      ),
    );
  }

  Widget _list(List<FinanceCheque> items, String emptyText) {
    if (items.isEmpty) return Center(child: Text(emptyText));
    return ListView(padding: const EdgeInsets.all(12), children: items.map(_tile).toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('چک‌ها'),
          bottom: TabBar(tabs: [
            Tab(text: 'در انتظار (${PersianDateUtil.toPersianDigits('${_pending.length}')})'),
            Tab(text: 'وصول‌شده (${PersianDateUtil.toPersianDigits('${_collected.length}')})'),
          ]),
        ),
        body: TabBarView(children: [
          _list(_pending, 'چک در انتظاری وجود ندارد'),
          _list(_collected, 'چک وصول‌شده‌ای وجود ندارد'),
        ]),
      ),
    );
  }
}
