import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../models/app_settings.dart';
import '../../models/finance_account.dart';
import '../../models/finance_transaction.dart';
import '../../repositories/finance_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/persian_date.dart';
import '../../utils/thousands_input_formatter.dart';

/// ثبت دستی یک ورودی یا خروجی در حساب فروش کالا. بعد از ثبت، تراکنش
/// ویرایش یا حذف نمی‌شود؛ فقط با اصلاحیه (تراکنش معکوس) قابل اصلاح است.
class FinanceTransactionFormScreen extends StatefulWidget {
  final FinanceAccount account;
  const FinanceTransactionFormScreen({super.key, required this.account});
  @override
  State<FinanceTransactionFormScreen> createState() => _FinanceTransactionFormScreenState();
}

class _FinanceTransactionFormScreenState extends State<FinanceTransactionFormScreen> {
  final _repo = FinanceRepository();
  final _settingsRepo = SettingsRepository();

  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _counterCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  FinanceTxType? _type;
  DateTime _dateTime = DateTime.now();
  Currency _currency = Currency.toman;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _settingsRepo.getSettings().then((s) {
      if (mounted) setState(() => _currency = s.currency);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _invoiceCtrl.dispose();
    _counterCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickDateTime() async {
    final jalali = await showPersianDatePicker(
      context: context,
      initialDate: Jalali.fromDateTime(_dateTime),
      firstDate: Jalali(1394, 1, 1),
      lastDate: Jalali(1450, 12, 29),
    );
    if (jalali == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dateTime));
    if (time == null) return;
    final g = jalali.toDateTime();
    setState(() => _dateTime = DateTime(g.year, g.month, g.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final type = _type;
    if (type == null) {
      _msg('نوع تراکنش را انتخاب کنید');
      return;
    }
    final amount = double.tryParse(ThousandsInputFormatter.unformat(_amountCtrl.text.trim()));
    if (amount == null || amount <= 0) {
      _msg('مبلغ باید بیشتر از صفر باشد');
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.addTransaction(
        accountId: widget.account.id!,
        type: type,
        amount: amount,
        occurredAt: _dateTime,
        description: _descCtrl.text,
        invoiceNumber: _invoiceCtrl.text,
        counterparty: _counterCtrl.text,
        notes: _notesCtrl.text,
      );
      if (mounted) {
        _msg('تراکنش ثبت شد');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _msg('خطا: ${financeErrorText(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<FinanceTxType>>[
      for (final t in FinanceTxType.manualInflow) DropdownMenuItem(value: t, child: Text('ورود: ${t.label}')),
      for (final t in FinanceTxType.manualOutflow) DropdownMenuItem(value: t, child: Text('خروج: ${t.label}')),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت تراکنش')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<FinanceTxType>(
          value: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'نوع تراکنش'),
          items: items,
          onChanged: (t) => setState(() => _type = t),
        ),
        if (_type != null) ...[
          const SizedBox(height: 6),
          Text(
            _type!.direction == FinanceDirection.inflow
                ? 'این تراکنش به موجودی حساب اضافه می‌شود.'
                : 'این تراکنش از موجودی حساب کم می‌شود.',
            style: TextStyle(
                fontSize: 12,
                color: _type!.direction == FinanceDirection.inflow ? Colors.green.shade700 : Colors.red.shade700),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _amountCtrl,
          decoration: InputDecoration(labelText: 'مبلغ', suffixText: _currency.label),
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsInputFormatter()],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickDateTime,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'تاریخ و زمان'),
            child: Text(PersianDateUtil.formatFullWithIcon(_dateTime)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'شرح (اختیاری)')),
        const SizedBox(height: 12),
        TextField(controller: _invoiceCtrl, decoration: const InputDecoration(labelText: 'شماره فاکتور مرتبط (اختیاری)')),
        const SizedBox(height: 12),
        TextField(controller: _counterCtrl, decoration: const InputDecoration(labelText: 'طرف حساب (اختیاری)')),
        const SizedBox(height: 12),
        TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'), maxLines: 2),
        const SizedBox(height: 8),
        const Text(
          'تراکنش ثبت‌شده قابل ویرایش یا حذف نیست؛ در صورت اشتباه، از صفحه‌ی گردش مالی «اصلاحیه» ثبت کنید.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('ثبت تراکنش'),
        ),
      ]),
    );
  }
}
