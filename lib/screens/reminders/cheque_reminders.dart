import 'dart:async';
import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../models/app_settings.dart';
import '../../repositories/finance_repository.dart';
import '../../repositories/invoice_payment_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import '../invoices/invoice_detail_screen.dart';

String _statusText(int d) {
  if (d > 0) return '${PersianDateUtil.toPersianDigits('$d')} روز تا سررسید';
  if (d == 0) return 'سررسید امروز';
  return 'سررسید گذشته — ${PersianDateUtil.toPersianDigits('${-d}')} روز';
}

Color _statusColor(int d) {
  if (d < 0) return Colors.red.shade700;
  if (d == 0) return Colors.deepOrange.shade700;
  if (d <= 2) return Colors.orange.shade800;
  return Colors.grey.shade700;
}

String _message(ChequeReminder c, int d) {
  final name = c.customerName.isEmpty ? 'بدون نام' : c.customerName;
  final date = PersianDateUtil.formatDateNumeric(c.dueDate.toIso8601String());
  if (d < 0) {
    return 'چک مشتری $name با سررسید $date هنوز پرداخت نشده است. لطفاً برای پیگیری پرداخت تماس بگیرید.';
  }
  if (d == 0) {
    return 'امروز سررسید چک مشتری $name است. لطفاً برای پیگیری پرداخت همین امروز اقدام کنید.';
  }
  return 'یادآوری چک: سررسید چک مشتری $name نزدیک است. لطفاً برای پیگیری پرداخت با مشتری تماس بگیرید.';
}

/// ثبت پرداخت یک چک (فقط همان چک). true = ثبت شد.
Future<bool> _confirmAndMarkPaid(BuildContext context, ChequeReminder c, Currency currency) async {
  final jalali = await showPersianDatePicker(
    context: context,
    initialDate: Jalali.fromDateTime(DateTime.now()),
    firstDate: Jalali(1394, 1, 1),
    lastDate: Jalali(1450, 12, 29),
  );
  if (jalali == null || !context.mounted) return false;
  final paidAt = jalali.toDateTime();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ثبت پرداخت چک'),
      content: Text(
          'چک فاکتور ${PersianDateUtil.toPersianDigits(c.invoiceNumber)} به مبلغ ${CurrencyFormatter.format(c.amount, currency)} '
          'در تاریخ ${PersianDateUtil.formatDateNumeric(paidAt.toIso8601String())} پرداخت‌شده ثبت شود؟\n'
          'فقط یادآوری همین چک برداشته می‌شود.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت پرداخت')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await InvoicePaymentRepository().markPaid(paymentId: c.paymentId, paidAt: paidAt);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(financeErrorText(e))));
    }
    return false;
  }
}

class _ReminderTile extends StatelessWidget {
  final ChequeReminder item;
  final Currency currency;
  final Future<void> Function() onChanged;
  const _ReminderTile({required this.item, required this.currency, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final d = item.daysLeft(DateTime.now());
    final color = _statusColor(d);
    final name = item.customerName.isEmpty ? 'بدون نام' : item.customerName;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: d <= 2 ? color.withOpacity(0.6) : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: item.invoiceId)));
          await onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
              Text(_statusText(d), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
            const SizedBox(height: 4),
            Text(_message(item, d), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              'فاکتور ${PersianDateUtil.toPersianDigits(item.invoiceNumber)} • '
              'سررسید ${PersianDateUtil.formatDateNumeric(item.dueDate.toIso8601String())} • '
              '${CurrencyFormatter.format(item.amount, currency)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('ثبت پرداخت'),
                onPressed: () async {
                  final done = await _confirmAndMarkPaid(context, item, currency);
                  if (done) await onChanged();
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// کادر «یادآوری چک‌ها» بالای صفحه‌ی رسید. فقط وقتی نمایش داده می‌شود که چک
/// پرداخت‌نشده‌ای ۲ روز یا کمتر به سررسیدش مانده یا سررسیدش گذشته باشد. هیچ
/// دکمه‌ی بستن ندارد؛ فقط با ثبت پرداخت همان چک (یا ابطال فاکتور) برداشته
/// می‌شود. همه‌چیز از دیتابیس خوانده می‌شود، پس با بستن/باز کردن برنامه و
/// خاموش/روشن شدن گوشی دوباره ساخته می‌شود.
class ChequeRemindersCard extends StatefulWidget {
  const ChequeRemindersCard({super.key});
  @override
  State<ChequeRemindersCard> createState() => _ChequeRemindersCardState();
}

class _ChequeRemindersCardState extends State<ChequeRemindersCard> with WidgetsBindingObserver {
  final _repo = InvoicePaymentRepository();
  final _settingsRepo = SettingsRepository();
  List<ChequeReminder> _items = [];
  Currency _currency = Currency.toman;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // تازه‌سازی دوره‌ای: چک جدید، پرداخت، و تغییر روز (نیمه‌شب) بدون نیاز به
    // بستن برنامه اعمال می‌شود.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.pendingCheques();
      final settings = await _settingsRepo.getSettings();
      if (!mounted) return;
      setState(() {
        _items = items;
        _currency = settings.currency;
      });
    } catch (_) {}
  }

  Future<void> _openAll() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChequeRemindersScreen()));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final due = _items.where((c) => c.daysLeft(now) <= 2).toList();
    if (due.isEmpty) return const SizedBox.shrink();
    final shown = due.take(3).toList();
    final accent = due.any((c) => c.daysLeft(now) < 0) ? Colors.red : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        border: Border.all(color: accent.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.notifications_active_outlined, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text('یادآوری چک‌ها (${PersianDateUtil.toPersianDigits('${due.length}')})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        for (final c in shown) _ReminderTile(item: c, currency: _currency, onChanged: _load),
        if (_items.length > shown.length)
          TextButton(
            onPressed: _openAll,
            child: Text('مشاهده‌ی همه‌ی چک‌های پیگیری‌نشده (${PersianDateUtil.toPersianDigits('${_items.length}')})'),
          ),
      ]),
    );
  }
}

/// فهرست کامل چک‌های پرداخت‌نشده (از جمله آن‌هایی که سررسیدشان دورتر است).
class ChequeRemindersScreen extends StatefulWidget {
  const ChequeRemindersScreen({super.key});
  @override
  State<ChequeRemindersScreen> createState() => _ChequeRemindersScreenState();
}

class _ChequeRemindersScreenState extends State<ChequeRemindersScreen> {
  final _repo = InvoicePaymentRepository();
  final _settingsRepo = SettingsRepository();
  List<ChequeReminder> _items = [];
  Currency _currency = Currency.toman;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.pendingCheques();
      final settings = await _settingsRepo.getSettings();
      if (!mounted) return;
      setState(() {
        _items = items;
        _currency = settings.currency;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('چک‌های پیگیری‌نشده')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 200),
                    Center(child: Text('چک پیگیری‌نشده‌ای وجود ندارد')),
                  ])
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final c in _items) _ReminderTile(item: c, currency: _currency, onChanged: _load),
                    ],
                  ),
      ),
    );
  }
}
