import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../models/app_settings.dart';
import '../../repositories/invoice_payment_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import '../../utils/thousands_input_formatter.dart';

String _dateText(DateTime d) => PersianDateUtil.formatDateNumeric(d.toIso8601String());

/// ویرایشگر ردیف‌های «پرداخت ترکیبی» داخل فرم رسید. فهرست را خودش نگه
/// نمی‌دارد؛ هر تغییر را با [onChanged] به صفحه می‌دهد.
class PaymentLinesEditor extends StatelessWidget {
  final List<PaymentLine> lines;
  final double total;
  final Currency currency;
  final ValueChanged<List<PaymentLine>> onChanged;

  const PaymentLinesEditor({
    super.key,
    required this.lines,
    required this.total,
    required this.currency,
    required this.onChanged,
  });

  double get _sum => lines.fold(0.0, (s, l) => s + l.amount);

  Future<void> _edit(BuildContext context, {int? index}) async {
    final existing = index == null ? null : lines[index];
    var method = existing?.method ?? PaymentMethods.cash;
    DateTime? date = existing?.date;
    final remaining = total - _sum + (existing?.amount ?? 0);
    final amountCtrl = TextEditingController(
        text: (existing?.amount ?? (remaining > 0 ? remaining : 0)).toStringAsFixed(0));
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? 'افزودن پرداخت' : 'ویرایش پرداخت'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: method,
                decoration: const InputDecoration(labelText: 'نوع پرداخت'),
                items: PaymentMethods.labels.entries
                    .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setDlg(() => method = v ?? PaymentMethods.cash),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                decoration: InputDecoration(labelText: 'مبلغ', suffixText: currency.label),
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () async {
                  final j = await showPersianDatePicker(
                    context: ctx,
                    initialDate: Jalali.fromDateTime(date ?? DateTime.now()),
                    firstDate: Jalali(1394, 1, 1),
                    lastDate: Jalali(1450, 12, 29),
                  );
                  if (j != null) setDlg(() => date = j.toDateTime());
                },
                child: Text(
                  PaymentMethods.needsDueDate(method)
                      ? (date == null ? 'تاریخ سررسید (الزامی)' : 'سررسید: ${_dateText(date!)}')
                      : (date == null ? 'تاریخ پرداخت (پیش‌فرض: تاریخ فاکتور)' : 'تاریخ پرداخت: ${_dateText(date!)}'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
                maxLines: 2,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            TextButton(
              onPressed: () {
                final a = double.tryParse(ThousandsInputFormatter.unformat(amountCtrl.text.trim()));
                if (a == null || a <= 0) {
                  setDlg(() => error = 'مبلغ باید بیشتر از صفر باشد');
                  return;
                }
                if (PaymentMethods.needsDueDate(method) && date == null) {
                  setDlg(() => error = 'برای چک و پرداخت توافقی، تاریخ سررسید لازم است');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final line = PaymentLine(
      method: method,
      amount: double.parse(ThousandsInputFormatter.unformat(amountCtrl.text.trim())),
      date: date,
      notes: notesCtrl.text.trim(),
    );
    final next = [...lines];
    if (index == null) {
      next.add(line);
    } else {
      next[index] = line;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final sum = _sum;
    final diff = total - sum;
    final over = diff < -0.5;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('ردیف‌های پرداخت', style: TextStyle(fontWeight: FontWeight.bold))),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('افزودن پرداخت'),
            onPressed: () => _edit(context),
          ),
        ]),
        if (lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text('هنوز پرداختی اضافه نشده است', style: TextStyle(color: Colors.grey))),
          ),
        for (var i = 0; i < lines.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text('${PaymentMethods.label(lines[i].method)} — ${CurrencyFormatter.format(lines[i].amount, currency)}'),
              subtitle: Text([
                if (lines[i].date != null)
                  '${PaymentMethods.needsDueDate(lines[i].method) ? 'سررسید' : 'تاریخ'}: ${_dateText(lines[i].date!)}',
                if (lines[i].notes.isNotEmpty) lines[i].notes,
              ].join(' • ')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
                    onPressed: () => _edit(context, index: i)),
                IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    onPressed: () => onChanged([...lines]..removeAt(i))),
              ]),
            ),
          ),
        const Divider(),
        _row('مبلغ فاکتور', CurrencyFormatter.format(total, currency)),
        _row('جمع پرداخت‌ها', CurrencyFormatter.format(sum, currency)),
        if (over)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('مجموع پرداخت‌ها از مبلغ فاکتور بیشتر است؛ ردیف‌ها را اصلاح کنید.',
                style: TextStyle(color: Colors.red, fontSize: 12)),
          )
        else
          _row('مانده‌ی تسویه‌نشده', CurrencyFormatter.format(diff < 0 ? 0 : diff, currency),
              color: diff > 0.5 ? Colors.red : Colors.green.shade700),
        const SizedBox(height: 4),
        const Text(
          'نقدی، کارت‌خوان و انتقال همان لحظه دریافت‌شده حساب می‌شوند؛ چک و پرداخت توافقی تا پرداخت واقعی دریافت‌شده نیستند.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ]),
    );
  }

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(fontSize: 13)),
          Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
      );
}

/// خلاصه‌ی ردیف‌های پرداخت یک فاکتور ترکیبی (برای صفحه‌ی جزئیات فاکتور).
class PaymentLinesSummary extends StatefulWidget {
  final int invoiceId;
  final double finalAmount;
  final Currency currency;
  const PaymentLinesSummary({
    super.key,
    required this.invoiceId,
    required this.finalAmount,
    required this.currency,
  });

  @override
  State<PaymentLinesSummary> createState() => _PaymentLinesSummaryState();
}

class _PaymentLinesSummaryState extends State<PaymentLinesSummary> {
  late Future<List<PaymentLine>> _future;

  @override
  void initState() {
    super.initState();
    _future = InvoicePaymentRepository().getLines(widget.invoiceId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PaymentLine>>(
      future: _future,
      builder: (context, snap) {
        final lines = snap.data;
        if (lines == null || lines.isEmpty) return const SizedBox.shrink();
        final cur = widget.currency;
        final paid = lines.where((l) => l.isPaid).fold(0.0, (s, l) => s + l.amount);
        final pending = lines.where((l) => !l.isPaid).fold(0.0, (s, l) => s + l.amount);
        final unsettled = widget.finalAmount - paid - pending;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('ردیف‌های پرداخت', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(l.isPaid ? Icons.check_circle : Icons.schedule,
                        size: 18, color: l.isPaid ? Colors.green : Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${PaymentMethods.label(l.method)} — ${CurrencyFormatter.format(l.amount, cur)}\n'
                        '${l.isPaid ? 'پرداخت‌شده${l.paidDate == null ? '' : ' ${_dateText(l.paidDate!)}'}' : 'در انتظار${l.date == null ? '' : ' • سررسید ${_dateText(l.date!)}'}'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              const Divider(),
              _kv('دریافت‌شده', CurrencyFormatter.format(paid, cur), Colors.green.shade700),
              _kv('در انتظار (چک / توافقی)', CurrencyFormatter.format(pending, cur), Colors.orange.shade800),
              if (unsettled > 0.5) _kv('مانده‌ی تسویه‌نشده', CurrencyFormatter.format(unsettled, cur), Colors.red),
            ]),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(fontSize: 13)),
          Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ]),
      );
}
