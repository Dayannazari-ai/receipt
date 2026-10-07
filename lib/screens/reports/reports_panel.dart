import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../models/app_settings.dart';
import '../../models/finance_account.dart';
import '../../models/finance_transaction.dart';
import '../../models/service_expense.dart';
import '../../repositories/finance_repository.dart';
import '../../repositories/report_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import '../../utils/report_period.dart';
import '../../utils/thousands_input_formatter.dart';
import '../finance/finance_account_setup_screen.dart';
import '../finance/finance_ledger_screen.dart';

/// محتوای تب «گزارش»: انتخاب بازه + دو بخش «گزارش فاکتورها» و «گزارش مالی».
/// گزارش مالی همان دفتر «حساب مالی فروش کالا» (FinanceRepository) را می‌خواند؛
/// سیستم موازی ساخته نشده است.
class ReportsPanel extends StatefulWidget {
  const ReportsPanel({super.key});
  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel> {
  final _repo = ReportRepository();
  final _financeRepo = FinanceRepository();
  final _settingsRepo = SettingsRepository();

  ReportPeriod _period = ReportPeriod.of(PeriodKind.monthly, DateTime.now());
  int _section = 0; // 0 = گزارش فاکتورها، 1 = گزارش مالی
  Currency _currency = Currency.toman;
  bool _loading = true;

  List<InvoiceTypeTotal> _invoiceRows = [];
  FinanceAccount? _account;
  FinancePeriodReport? _finance;
  List<Map<String, Object?>> _pending = [];
  List<ServiceIncomeRow> _serviceIncome = [];
  List<ServiceExpense> _expenses = [];

  static const Map<String, String> _typeLabels = {
    'productSale': 'فروش کالا',
    'productPurchase': 'خرید کالا',
    'electrical': 'برق خودرو',
    'mechanic': 'مکانیک',
    'suspension': 'جلوبندی',
  };
  static const List<String> _serviceTypes = ['electrical', 'mechanic', 'suspension'];

  static const Map<String, List<String>> _inGroups = {
    'فروش کالا': ['sale_receipt'],
    'واریز به حساب': ['deposit'],
    'برگشت وجه': ['refund_in'],
    'سایر درآمدها (از جمله هزینه‌ی جانبی فاکتور فروش)': ['other_income'],
    'موجودی اولیه (ثبت‌شده در همین بازه)': ['opening_balance'],
  };
  static const Map<String, List<String>> _outGroups = {
    'خرید کالا': ['purchase_payment'],
    'هزینه‌های فروشگاه (حمل، بسته‌بندی، متفرقه)': ['shipping_cost', 'packaging_cost', 'misc_shop_cost'],
    'برداشت و انتقال': ['withdrawal', 'transfer_out'],
    'سایر هزینه‌ها': ['other_expense'],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _money(double v) {
    final s = CurrencyFormatter.format(v.abs(), _currency);
    return v < 0 ? '−$s' : s;
  }

  String _n(int v) => PersianDateUtil.toPersianDigits('$v');

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final settings = await _settingsRepo.getSettings();
      final inv = await _repo.invoiceSummary(_period.from, _period.to);
      final account = await _financeRepo.getGoodsSalesAccount();
      FinancePeriodReport? fin;
      if (account != null) {
        final rows = await _financeRepo.loadLedger(account.id!);
        fin = ReportRepository.computeFinance(rows, _period.from, _period.to);
      }
      final pending = await _repo.pendingCheques();
      final income = await _repo.serviceIncome(_period.from, _period.to);
      final exps = await _repo.serviceExpenses(_period.from, _period.to);
      if (!mounted) return;
      setState(() {
        _currency = settings.currency;
        _invoiceRows = inv;
        _account = account;
        _finance = fin;
        _pending = pending;
        _serviceIncome = income;
        _expenses = exps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _msg('خطا در بارگذاری گزارش: ${financeErrorText(e)}');
    }
  }

  // ==================== بازه‌ی زمانی ====================

  String _kindLabel(PeriodKind k) {
    switch (k) {
      case PeriodKind.daily:
        return 'روزانه';
      case PeriodKind.weekly:
        return 'هفتگی';
      case PeriodKind.monthly:
        return 'ماهانه';
      case PeriodKind.yearly:
        return 'سالانه';
      case PeriodKind.custom:
        return 'سفارشی';
    }
  }

  void _selectKind(PeriodKind k) {
    setState(() {
      _period = k == PeriodKind.custom
          ? ReportPeriod.custom(_period.from, _period.to)
          : ReportPeriod.of(k, DateTime.now());
    });
    _load();
  }

  void _shift(int dir) {
    setState(() => _period = _period.shift(dir));
    _load();
  }

  Future<DateTime?> _pickDate(DateTime initial) async {
    final j = await showPersianDatePicker(
      context: context,
      initialDate: Jalali.fromDateTime(initial),
      firstDate: Jalali(1394, 1, 1),
      lastDate: Jalali(1450, 12, 29),
    );
    return j?.toDateTime();
  }

  Future<void> _pickFrom() async {
    final d = await _pickDate(_period.from);
    if (d == null) return;
    final from = DateTime(d.year, d.month, d.day);
    final to = from.isAfter(_period.to) ? from : _period.to;
    setState(() => _period = ReportPeriod.custom(from, to));
    _load();
  }

  Future<void> _pickTo() async {
    final d = await _pickDate(_period.to);
    if (d == null) return;
    final to = DateTime(d.year, d.month, d.day);
    final from = to.isBefore(_period.from) ? to : _period.from;
    setState(() => _period = ReportPeriod.custom(from, to));
    _load();
  }

  Widget _periodBar() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final k in PeriodKind.values)
          ChoiceChip(
            label: Text(_kindLabel(k)),
            selected: _period.kind == k,
            onSelected: (_) => _selectKind(k),
          ),
      ]),
      const SizedBox(height: 6),
      if (_period.kind == PeriodKind.custom)
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _pickFrom,
              child: Text('از: ${PersianDateUtil.formatDate(_period.from.toIso8601String())}',
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _pickTo,
              child: Text('تا: ${PersianDateUtil.formatDate(_period.to.toIso8601String())}',
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        ])
      else
        Row(children: [
          IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'قبلی', onPressed: () => _shift(-1)),
          Expanded(
            child: Center(
              child: Text(_period.label, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'بعدی', onPressed: () => _shift(1)),
        ]),
    ]);
  }

  // ==================== ویجت‌های کمکی ====================

  Widget _kv(String k, String v, {Color? color, bool bold = false, double indent = 0}) => Padding(
        padding: EdgeInsetsDirectional.only(start: indent, top: 3, bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(k,
                style: TextStyle(
                    fontSize: bold ? 14 : 13,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                    color: indent > 0 ? Colors.grey.shade700 : null)),
          ),
          const SizedBox(width: 8),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
        ]),
      );

  Widget _card(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  // ==================== گزارش فاکتورها ====================

  Widget _invoiceSection() {
    if (_invoiceRows.isEmpty) {
      return _card('گزارش فاکتورها', [
        const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('در این بازه فاکتوری ثبت نشده است'))),
      ]);
    }
    final byType = {for (final r in _invoiceRows) r.type: r};
    double tot(List<String> ts) => ts.fold<double>(0.0, (a, t) => a + (byType[t]?.total ?? 0.0));
    int cnt(List<String> ts) => ts.fold<int>(0, (a, t) => a + (byType[t]?.count ?? 0));

    const sales = ['productSale'];
    const purchases = ['productPurchase'];
    final allSales = [...sales, ..._serviceTypes];
    final allTypes = [...allSales, ...purchases];

    final green = Colors.green.shade700;
    final red = Colors.red.shade700;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _card('خلاصه‌ی فاکتورها', [
        _kv('تعداد کل فاکتورها', _n(cnt(allTypes))),
        _kv('جمع فاکتورهای فروش (کالا + خدمات)', _money(tot(allSales)), color: green, bold: true),
        _kv('جمع فاکتورهای خرید کالا', _money(tot(purchases)), color: red, bold: true),
      ]),
      _card('فروش کالا', [
        _kv('تعداد فاکتور', _n(cnt(sales))),
        _kv('جمع مبلغ', _money(tot(sales)), bold: true),
      ]),
      _card('خرید کالا', [
        _kv('تعداد فاکتور', _n(cnt(purchases))),
        _kv('جمع مبلغ', _money(tot(purchases)), bold: true),
      ]),
      _card('خدمات', [
        _kv('تعداد فاکتور', _n(cnt(_serviceTypes))),
        _kv('جمع مبلغ', _money(tot(_serviceTypes)), bold: true),
        for (final t in _serviceTypes)
          if (byType[t] != null)
            _kv('${_typeLabels[t]} — ${_n(byType[t]!.count)} فاکتور', _money(byType[t]!.total), indent: 12),
      ]),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text('مبالغ بر اساس مبلغ نهایی فاکتورهای اصلی (بدون پیش‌فاکتور) و تاریخ صدور محاسبه شده است.',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    ]);
  }

  // ==================== گزارش مالی ====================

  List<Widget> _flowRows(Map<String, double> flow, Map<String, List<String>> groups) {
    final used = <String>{};
    final out = <Widget>[];
    groups.forEach((label, keys) {
      var sum = 0.0;
      for (final k in keys) {
        used.add(k);
        sum += flow[k] ?? 0.0;
      }
      if (sum != 0) out.add(_kv(label, _money(sum), indent: 12));
    });
    var rest = 0.0;
    flow.forEach((k, v) {
      if (!used.contains(k)) rest += v;
    });
    if (rest != 0) out.add(_kv('سایر موارد', _money(rest), indent: 12));
    return out;
  }

  Future<void> _openLedger() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FinanceLedgerScreen()));
    _load();
  }

  Future<void> _openAccountSetup() async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const FinanceAccountSetupScreen()));
    if (changed == true) _load();
  }

  Widget _goodsCard() {
    final account = _account;
    final f = _finance;
    if (account == null || f == null) {
      return _card('حساب فروش کالا', [
        const Text('هنوز حساب مالی فروش کالا تعریف نشده است.', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _openAccountSetup, child: const Text('تعریف حساب مالی فروش کالا')),
      ]);
    }
    final green = Colors.green.shade700;
    final red = Colors.red.shade700;

    final pendingIn = _pending.where((r) => r['direction'] == 'in').toList();
    final pendingOut = _pending.where((r) => r['direction'] == 'out').toList();
    String pendingText(List<Map<String, Object?>> l) {
      if (l.isEmpty) return '';
      final c = (l.first['c'] as num?)?.toInt() ?? 0;
      final t = (l.first['t'] as num?)?.toDouble() ?? 0.0;
      return '${_n(c)} چک — ${_money(t)}';
    }

    return _card('حساب فروش کالا — ${account.name}', [
      _kv('موجودی اول دوره', _money(f.opening)),
      const Divider(),
      _kv('مجموع ورودی‌ها', _money(f.totalIn), color: green, bold: true),
      ..._flowRows(f.inflow, _inGroups),
      const SizedBox(height: 4),
      _kv('مجموع خروجی‌ها', _money(f.totalOut), color: red, bold: true),
      ..._flowRows(f.outflow, _outGroups),
      const Divider(),
      _kv('گردش خالص', _money(f.net), bold: true),
      _kv('موجودی پایان دوره', _money(f.closing), color: f.closing < 0 ? Colors.red : null, bold: true),
      _kv('تعداد تراکنش در بازه', _n(f.txCount), indent: 12),
      if (_pending.isNotEmpty) ...[
        const Divider(),
        const Text('چک‌های در انتظار وصول (روی مانده اثر ندارند)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        if (pendingIn.isNotEmpty) _kv('دریافتنی', pendingText(pendingIn), indent: 12),
        if (pendingOut.isNotEmpty) _kv('پرداختنی', pendingText(pendingOut), indent: 12),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('مشاهده‌ی دفتر کامل گردش'),
        onPressed: _openLedger,
      ),
    ]);
  }

  Future<void> _addExpense() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var category = 'part';
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('ثبت هزینه‌ی خدماتی'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'عنوان (مثلاً خرید قطعه یا ابزار)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                decoration: InputDecoration(labelText: 'مبلغ', suffixText: _currency.label),
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'دسته'),
                items: ServiceExpense.categories.entries
                    .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setDlg(() => category = v ?? 'other'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () async {
                  final d = await _pickDate(date);
                  if (d != null) setDlg(() => date = d);
                },
                child: Text('تاریخ: ${PersianDateUtil.formatDate(date.toIso8601String())}'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
                maxLines: 2,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(ThousandsInputFormatter.unformat(amountCtrl.text.trim()));
    if (amount == null) {
      _msg('مبلغ معتبر نیست');
      return;
    }
    try {
      await _repo.addServiceExpense(
        date: date,
        title: titleCtrl.text,
        amount: amount,
        category: category,
        notes: notesCtrl.text,
      );
      _msg('هزینه ثبت شد');
      await _load();
    } catch (e) {
      _msg('خطا: ${financeErrorText(e)}');
    }
  }

  Future<void> _deleteExpense(ServiceExpense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف هزینه'),
        content: Text('هزینه‌ی «${e.title}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || e.id == null) return;
    try {
      await _repo.deleteServiceExpense(e.id!);
      await _load();
    } catch (err) {
      _msg('خطا: ${financeErrorText(err)}');
    }
  }

  Widget _serviceCard() {
    final green = Colors.green.shade700;
    final red = Colors.red.shade700;
    final incomeTotal = _serviceIncome.fold<double>(0.0, (a, r) => a + r.total);
    final nonCash = _serviceIncome.fold<double>(0.0, (a, r) => a + r.nonCash);
    final expTotal = _expenses.fold<double>(0.0, (a, e) => a + e.amount);
    final byCat = <String, double>{};
    for (final e in _expenses) {
      byCat[e.category] = (byCat[e.category] ?? 0.0) + e.amount;
    }
    final incomeByType = {for (final r in _serviceIncome) r.type: r};

    return _card('گزارش مالی خدمات', [
      _kv('درآمد خدمات', _money(incomeTotal), color: green, bold: true),
      for (final t in _serviceTypes)
        if (incomeByType[t] != null)
          _kv('${_typeLabels[t]} — ${_n(incomeByType[t]!.invoiceCount)} فاکتور', _money(incomeByType[t]!.total), indent: 12),
      if (nonCash > 0) _kv('از این مبلغ، غیرنقد (چک)', _money(nonCash), indent: 12),
      const Divider(),
      _kv('هزینه‌های خدماتی', _money(expTotal), color: red, bold: true),
      for (final entry in ServiceExpense.categories.entries)
        if ((byCat[entry.key] ?? 0.0) > 0) _kv(entry.value, _money(byCat[entry.key]!), indent: 12),
      const Divider(),
      _kv('سود خالص خدمات', _money(incomeTotal - expTotal), color: incomeTotal - expTotal < 0 ? Colors.red : null, bold: true),
      const SizedBox(height: 4),
      const Text('درآمد خدمات بر اساس تاریخ صدور فاکتور و فقط از ردیف‌های «خدمت» محاسبه می‌شود (سهم کالا در حساب فروش کالا می‌آید).',
          style: TextStyle(fontSize: 11, color: Colors.grey)),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('ثبت هزینه‌ی خدماتی'),
        onPressed: _addExpense,
      ),
      if (_expenses.isNotEmpty) ...[
        const Divider(),
        for (final e in _expenses)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(e.title),
            subtitle: Text(
                '${PersianDateUtil.formatDate(e.expenseDate)} — ${ServiceExpense.categoryLabel(e.category)}'
                '${(e.notes ?? '').isEmpty ? '' : ' — ${e.notes}'}',
                style: const TextStyle(fontSize: 11)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(CurrencyFormatter.format(e.amount, _currency), style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                tooltip: 'حذف',
                onPressed: () => _deleteExpense(e),
              ),
            ]),
          ),
      ],
    ]);
  }

  // ==================== ساخت صفحه ====================

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _periodBar(),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 0, label: Text('گزارش فاکتورها')),
              ButtonSegment<int>(value: 1, label: Text('گزارش مالی')),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() => _section = s.first),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(),
          if (_section == 0) _invoiceSection() else ...[_goodsCard(), _serviceCard()],
        ],
      ),
    );
  }
}
