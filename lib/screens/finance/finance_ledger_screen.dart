import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../models/app_settings.dart';
import '../../models/finance_account.dart';
import '../../models/finance_transaction.dart';
import '../../repositories/finance_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import '../../utils/thousands_input_formatter.dart';
import 'finance_account_setup_screen.dart';
import 'finance_cheques_screen.dart';
import 'finance_transaction_form_screen.dart';

/// صفحه‌ی «گردش مالی فروش کالا». مانده، موجودی قبل و موجودی بعد همگی
/// هنگام نمایش از روی تراکنش‌ها محاسبه می‌شوند و هیچ‌کدام ذخیره نشده‌اند.
class FinanceLedgerScreen extends StatefulWidget {
  const FinanceLedgerScreen({super.key});
  @override
  State<FinanceLedgerScreen> createState() => _FinanceLedgerScreenState();
}

class _FinanceLedgerScreenState extends State<FinanceLedgerScreen> {
  final _repo = FinanceRepository();
  final _settingsRepo = SettingsRepository();
  final _searchCtrl = TextEditingController();

  FinanceAccount? _account;
  List<FinanceLedgerRow> _rows = []; // ترتیب زمانی صعودی
  Currency _currency = Currency.toman;
  bool _loading = true;

  String? _typeFilter; // کلید نوع تراکنش
  DateTime? _from;
  DateTime? _to; // پایان همان روز

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsRepo.getSettings();
    final account = await _repo.getGoodsSalesAccount();
    final rows = account == null ? <FinanceLedgerRow>[] : await _repo.loadLedger(account.id!);
    if (!mounted) return;
    setState(() {
      _currency = settings.currency;
      _account = account;
      _rows = rows;
      _loading = false;
    });
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _money(double v) {
    final s = CurrencyFormatter.format(v.abs(), _currency);
    return v < 0 ? '−$s' : s;
  }

  bool get _hasActiveOpening => _rows.any((r) => r.tx.isOpening && !r.isReversed);
  bool get _hasFilter => _typeFilter != null || _from != null || _to != null || _searchCtrl.text.trim().isNotEmpty;

  /// سطرهای فیلترشده، جدیدترین اول.
  List<FinanceLedgerRow> get _filtered {
    final q = _searchCtrl.text.trim();
    final list = _rows.where((r) {
      final t = r.tx;
      if (_typeFilter != null && t.txType != _typeFilter) return false;
      if (_from != null && t.dateTime.isBefore(_from!)) return false;
      if (_to != null && t.dateTime.isAfter(_to!)) return false;
      if (q.isNotEmpty) {
        final hay =
            '${t.description} ${t.counterparty ?? ''} ${t.notes ?? ''} ${t.invoiceNumber ?? ''} ${t.correctionReason ?? ''}';
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    return list.reversed.toList();
  }

  Future<DateTime?> _pickDate(DateTime? initial) async {
    final j = await showPersianDatePicker(
      context: context,
      initialDate: Jalali.fromDateTime(initial ?? DateTime.now()),
      firstDate: Jalali(1394, 1, 1),
      lastDate: Jalali(1450, 12, 29),
    );
    return j?.toDateTime();
  }

  Future<void> _pickFrom() async {
    final d = await _pickDate(_from);
    if (d == null) return;
    setState(() => _from = DateTime(d.year, d.month, d.day));
  }

  Future<void> _pickTo() async {
    final d = await _pickDate(_to);
    if (d == null) return;
    setState(() => _to = DateTime(d.year, d.month, d.day, 23, 59, 59));
  }

  void _clearFilters() {
    setState(() {
      _typeFilter = null;
      _from = null;
      _to = null;
      _searchCtrl.clear();
    });
  }

  Future<void> _openSetup() async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const FinanceAccountSetupScreen()));
    if (changed == true) _load();
  }

  Future<void> _openCheques() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FinanceChequesScreen()));
    _load();
  }

  Future<void> _openForm() async {
    final account = _account;
    if (account == null) return;
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => FinanceTransactionFormScreen(account: account)));
    if (saved == true) _load();
  }

  Future<void> _addOpening() async {
    final account = _account;
    if (account == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ثبت موجودی اولیه'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: 'موجودی اولیه', suffixText: _currency.label),
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsInputFormatter()],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(ThousandsInputFormatter.unformat(ctrl.text.trim()));
    if (amount == null || amount < 0) {
      _msg('موجودی اولیه معتبر نیست');
      return;
    }
    try {
      await _repo.addOpeningBalance(accountId: account.id!, amount: amount);
      _msg('موجودی اولیه ثبت شد');
      await _load();
    } catch (e) {
      _msg('خطا: ${financeErrorText(e)}');
    }
  }

  Future<void> _reverse(FinanceTransaction t) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ثبت اصلاحیه'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'یک تراکنش معکوس به مبلغ ${_money(t.amount)} ثبت می‌شود. تراکنش اصلی حذف یا ویرایش نمی‌شود. '
            'برای اصلاح مبلغ، بعد از اصلاحیه تراکنش درست را جدید ثبت کنید.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(labelText: 'دلیل اصلاح (الزامی)'),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت اصلاحیه')),
        ],
      ),
    );
    if (ok != true) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      _msg('دلیل اصلاح الزامی است');
      return;
    }
    try {
      await _repo.reverseTransaction(txId: t.id!, reason: reason);
      _msg('اصلاحیه ثبت شد');
      await _load();
    } catch (e) {
      _msg('خطا: ${financeErrorText(e)}');
    }
  }

  // ==================== جزئیات تراکنش ====================

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(width: 12),
          Flexible(child: Text(v, textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w600, color: color))),
        ]),
      );

  void _showDetails(FinanceLedgerRow r) {
    final t = r.tx;
    final isIn = t.direction == FinanceDirection.inflow;
    final canReverse = !t.isReversal && !r.isReversed && t.id != null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('جزئیات تراکنش', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            _kv('نوع', t.type.label),
            _kv('جهت', t.direction.label, color: isIn ? Colors.green.shade700 : Colors.red.shade700),
            _kv('مبلغ', _money(t.amount)),
            _kv('تاریخ و زمان', PersianDateUtil.formatFullWithIcon(t.dateTime)),
            if (t.description.isNotEmpty) _kv('شرح', t.description),
            if ((t.invoiceNumber ?? '').isNotEmpty) _kv('شماره فاکتور', PersianDateUtil.toPersianDigits(t.invoiceNumber!)),
            if ((t.counterparty ?? '').isNotEmpty) _kv('طرف حساب', t.counterparty!),
            if ((t.notes ?? '').isNotEmpty) _kv('توضیحات', t.notes!),
            const Divider(),
            _kv('موجودی قبل از تراکنش', _money(r.balanceBefore)),
            _kv('موجودی بعد از تراکنش', _money(r.balanceAfter)),
            if (t.isReversal) ...[
              const Divider(),
              _kv('اصلاحیه برای تراکنش شماره', PersianDateUtil.toPersianDigits('${t.reversesId ?? '-'}')),
              _kv('دلیل اصلاح', t.correctionReason ?? ''),
            ],
            if (r.isReversed) ...[
              const Divider(),
              const Text('این تراکنش قبلاً با یک اصلاحیه معکوس شده است.', style: TextStyle(color: Colors.orange)),
            ],
            const SizedBox(height: 12),
            if (canReverse)
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('ثبت اصلاحیه (تراکنش معکوس)'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _reverse(t);
                },
              ),
          ]),
        ),
      ),
    );
  }

  // ==================== ویجت‌ها ====================

  Widget _badge(String text, Color color) => Container(
        margin: const EdgeInsetsDirectional.only(start: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _rowCard(FinanceLedgerRow r) {
    final t = r.tx;
    final isIn = t.direction == FinanceDirection.inflow;
    final color = isIn ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetails(r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(isIn ? Icons.south_west : Icons.north_east, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(t.type.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (t.isReversal) _badge('اصلاحیه', Colors.blueGrey),
                  if (r.isReversed) _badge('اصلاح‌شده', Colors.orange),
                ]),
              ),
              Text('${isIn ? '+' : '−'} ${CurrencyFormatter.format(t.amount, _currency)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ]),
            if (t.description.isNotEmpty && t.description != t.type.label) ...[
              const SizedBox(height: 4),
              Text(t.description, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 4),
            Text(PersianDateUtil.formatFullWithIcon(t.dateTime), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if ((t.invoiceNumber ?? '').isNotEmpty)
              Text('فاکتور: ${PersianDateUtil.toPersianDigits(t.invoiceNumber!)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Text('موجودی قبل: ${_money(r.balanceBefore)}  ←  بعد: ${_money(r.balanceAfter)}',
                style: TextStyle(fontSize: 12, color: r.balanceAfter < 0 ? Colors.red : Colors.grey.shade700)),
          ]),
        ),
      ),
    );
  }

  Widget _summaryCard(FinanceAccount account, FinanceSummary s) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: primary.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(account.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('موجودی فعلی', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
        Text(_money(s.balance),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: s.balance < 0 ? Colors.red : primary)),
        const Divider(),
        _kv('موجودی اولیه', _money(s.opening)),
        _kv('مجموع ورودی‌ها', _money(s.totalIn), color: Colors.green.shade700),
        _kv('مجموع خروجی‌ها', _money(s.totalOut), color: Colors.red.shade700),
        _kv('گردش خالص', _money(s.net)),
      ]),
    );
  }

  Widget _filters() {
    String dateLabel(String title, DateTime? d) =>
        d == null ? title : '$title: ${PersianDateUtil.formatDate(d.toIso8601String())}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _searchCtrl,
        decoration: const InputDecoration(hintText: 'جستجو در شرح، طرف حساب و فاکتور', prefixIcon: Icon(Icons.search)),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        value: _typeFilter,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'نوع تراکنش', isDense: true),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('همه انواع')),
          ...FinanceTxType.all.map((t) => DropdownMenuItem<String?>(value: t.key, child: Text(t.label))),
        ],
        onChanged: (v) => setState(() => _typeFilter = v),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _pickFrom, child: Text(dateLabel('از', _from), overflow: TextOverflow.ellipsis))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton(onPressed: _pickTo, child: Text(dateLabel('تا', _to), overflow: TextOverflow.ellipsis))),
        if (_hasFilter) IconButton(icon: const Icon(Icons.clear), tooltip: 'حذف فیلترها', onPressed: _clearFilters),
      ]),
    ]);
  }

  Widget _header(FinanceAccount account, FinanceSummary summary, List<FinanceLedgerRow> list) {
    var fIn = 0.0;
    var fOut = 0.0;
    for (final r in list) {
      if (r.tx.direction == FinanceDirection.inflow) {
        fIn += r.tx.amount;
      } else {
        fOut += r.tx.amount;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!_hasActiveOpening)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(width: 8),
            const Expanded(child: Text('موجودی اولیه‌ی فعال ثبت نشده است.', style: TextStyle(fontSize: 13))),
            TextButton(onPressed: _addOpening, child: const Text('ثبت موجودی اولیه')),
          ]),
        ),
      _summaryCard(account, summary),
      const SizedBox(height: 12),
      _filters(),
      const SizedBox(height: 8),
      Text(
        _hasFilter
            ? '${PersianDateUtil.toPersianDigits('${list.length}')} تراکنش در فیلتر — ورود: ${_money(fIn)}، خروج: ${_money(fOut)}'
            : '${PersianDateUtil.toPersianDigits('${list.length}')} تراکنش',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      const SizedBox(height: 4),
      if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('تراکنشی یافت نشد'))),
    ]);
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final account = _account;
    if (account == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('هنوز حساب مالی فروش کالا تعریف نشده است.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _openSetup, child: const Text('تعریف حساب مالی فروش کالا')),
          ]),
        ),
      );
    }
    final summary = FinanceSummary.fromRows(_rows);
    final list = _filtered;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: list.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _header(account, summary, list);
        return _rowCard(list[i - 1]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('گردش مالی فروش کالا'), actions: [
        if (_account != null)
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'تنظیم حساب', onPressed: _openSetup),
        if (_account != null)
          IconButton(icon: const Icon(Icons.receipt_long_outlined), tooltip: 'چک‌ها', onPressed: _openCheques),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _body(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _account == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('ثبت تراکنش'),
              onPressed: _openForm,
            ),
    );
  }
}
