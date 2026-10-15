import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/invoice.dart';
import '../../models/customer.dart';
import '../../models/vehicle.dart';
import '../../models/app_settings.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/invoice_side_cost_editor.dart';
import '../../repositories/customer_repository.dart';
import '../../repositories/vehicle_repository.dart';
import '../../repositories/vehicle_reference_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/pdf_service.dart';
import '../../services/invoice_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import '../../utils/thousands_input_formatter.dart';
import 'edit_draft_invoice_screen.dart';
import '../../repositories/invoice_void_repository.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final int invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final _invoiceRepo = InvoiceRepository();
  final _customerRepo = CustomerRepository();
  final _vehicleRepo = VehicleRepository();
  final _settingsRepo = SettingsRepository();
  final _invoiceService = InvoiceService();
  final _sideCostEditor = InvoiceSideCostEditor();

  Invoice? _invoice;
  List<InvoiceItem> _items = [];
  List<SideCost> _sideCosts = [];
  Customer? _customer;
  Vehicle? _vehicle;
  String _vehicleLabel = '';
  AppSettings _settings = AppSettings();
  bool _loading = true;
  bool _converting = false;
  bool _voiding = false;
  final _voidRepo = InvoiceVoidRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _buildVehicleLabel(Vehicle v) async {
    final refRepo = VehicleReferenceRepository();
    final brands = await refRepo.getAllBrands(includeDeleted: true);
    final brandNames = {for (final b in brands) b.id!: b.name};
    String modelName = '';
    if (v.brandId != null && v.modelId != null) {
      final ms = await refRepo.getModelsByBrand(v.brandId!);
      final match = ms.where((m) => m.id == v.modelId);
      if (match.isNotEmpty) modelName = match.first.name;
    }
    final parts = <String>[
      if (v.brandId != null) brandNames[v.brandId] ?? '',
      modelName,
    ].where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? 'خودروی بدون مشخصات' : parts.join(' - ');
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
    Vehicle? vehicle;
    String vehicleLabel = '';
    if (invoice.vehicleId != null) {
      vehicle = await _vehicleRepo.getById(invoice.vehicleId!);
      if (vehicle != null) vehicleLabel = await _buildVehicleLabel(vehicle);
    }
    final settings = await _settingsRepo.getSettings();
    if (!mounted) return;
    setState(() {
      _invoice = invoice;
      _items = items;
      _sideCosts = sideCosts;
      _customer = customer;
      _vehicle = vehicle;
      _vehicleLabel = vehicleLabel;
      _settings = settings;
      _loading = false;
    });
  }

  void _showMsg(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _editDraft() async {
    final inv = _invoice!;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditDraftInvoiceScreen(invoice: inv, items: _items, sideCosts: _sideCosts),
      ),
    );
    if (result == true) _load();
  }

  /// ویرایش هزینه‌های جانبی (افزودن، ویرایش عنوان/مبلغ، حذف) حتی بعد از صدور.
  /// فقط جدول side_costs و جمع‌های همین فاکتور تغییر می‌کند؛ هیچ تراکنش مالی
  /// ساخته نمی‌شود. اگر فاکتور کالا در دفتر مالی ثبت شده باشد، ویرایش مجاز نیست.
  Future<void> _editSideCosts() async {
    final inv = _invoice!;
    final reason = await _sideCostEditor.blockReason(inv.id!);
    if (reason != null) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ویرایش هزینه‌های جانبی ممکن نیست'),
          content: Text(reason),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه'))],
        ),
      );
      return;
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<List<SideCostLine>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SideCostsEditorSheet(initial: _sideCosts, currency: _settings.currency),
    );
    if (result == null) return;
    try {
      await _sideCostEditor.replaceSideCosts(invoiceId: inv.id!, lines: result);
      if (mounted) _showMsg('هزینه‌های جانبی ذخیره شد');
      await _load();
    } catch (e) {
      _showMsg('خطا در ذخیره‌ی هزینه‌های جانبی: ${e is StateError ? e.message : e}');
    }
  }
    Future<void> _confirmVoid() async {
    final inv = _invoice!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ابطال فاکتور'),
        content: Text(
            'فاکتور ${PersianDateUtil.toPersianDigits(inv.invoiceNumber)} (${inv.type.label}) به مبلغ ${CurrencyFormatter.format(inv.finalAmount, _settings.currency)} باطل شود؟\n\n'
            'موجودی کالا برگردانده، تراکنش‌های مالی با اصلاحیه خنثی و چک آن حذف می‌شود. شماره‌ی فاکتور آزاد می‌شود. این کار قابل بازگشت نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ابطال فاکتور', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _voiding = true);
    try {
      final number = await _voidRepo.voidInvoice(inv.id!);
      if (!mounted) return;
      _showMsg('فاکتور ${PersianDateUtil.toPersianDigits(number)} باطل شد');
      Navigator.of(context).pop();
    } catch (e) {
      _showMsg('خطا در ابطال: ${e is StateError ? e.message : e}');
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  Future<void> _confirmConvertToInvoice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تبدیل به فاکتور اصلی'),
        content: const Text(
            'آیا این پیش‌فاکتور را به فاکتور اصلی تبدیل می‌کنید؟\nپس از تبدیل، ویرایش عادی فاکتور غیرفعال خواهد شد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('تبدیل به فاکتور اصلی')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _converting = true);
    try {
      final newNumber = await _invoiceService.convertDraftToInvoice(_invoice!.id!);
      if (mounted) {
        _showMsg('فاکتور با شماره ${PersianDateUtil.toPersianDigits(newNumber)} صادر شد');
        await _load();
      }
    } catch (e) {
      _showMsg('خطا در تبدیل به فاکتور اصلی: $e');
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_invoice == null) return const Scaffold(body: Center(child: Text('فاکتور یافت نشد')));
    final inv = _invoice!;
    final isDraft = inv.isDraft == 1;

    return Scaffold(
            appBar: AppBar(
        title: Text('${inv.type.label} - ${PersianDateUtil.toPersianDigits(inv.invoiceNumber)}'),
        actions: [
          if (!isDraft)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'ابطال فاکتور',
              onPressed: _voiding ? null : _confirmVoid,
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (isDraft)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.edit_note_outlined, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                  child: Text('این یک پیش‌فاکتور است و هنوز فاکتور اصلی محسوب نمی‌شود.',
                      style: TextStyle(fontSize: 13))),
            ]),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_customer != null) _row('مشتری', _customer!.name),
              if (_customer != null) _row('موبایل', PersianDateUtil.toPersianDigits(_customer!.mobile)),
              if (_vehicle != null) _row('خودرو', _vehicleLabel),
              if (inv.mileageKm != null) _row('کیلومتر مراجعه خودرو', CurrencyFormatter.formatPlain(inv.mileageKm!)),
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
                    '${(it.itemCode != null && it.itemCode!.isNotEmpty) ? 'کد: ${it.itemCode}  ' : ''}${PersianDateUtil.toPersianDigits('${it.quantity}')} × ${CurrencyFormatter.format(it.unitPrice, _settings.currency)}'),
                trailing: Text(CurrencyFormatter.format(it.total, _settings.currency)),
              ),
            )),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('هزینه‌های جانبی', style: TextStyle(fontWeight: FontWeight.bold)),
          TextButton.icon(
            icon: Icon(_sideCosts.isEmpty ? Icons.add : Icons.edit_outlined, size: 18),
            label: Text(_sideCosts.isEmpty ? 'افزودن هزینه' : 'ویرایش'),
            onPressed: _editSideCosts,
          ),
        ]),
        if (_sideCosts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('بدون هزینه‌ی جانبی', style: TextStyle(fontSize: 12, color: Colors.grey)),
          )
        else
          ..._sideCosts.map((c) => ListTile(
                dense: true,
                title: Text(c.title),
                trailing: Text(CurrencyFormatter.format(c.amount, _settings.currency)),
              )),
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
        if (isDraft) ...[
          ElevatedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('ویرایش پیش‌فاکتور'),
            onPressed: _converting ? null : _editDraft,
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            icon: _converting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline),
            label: const Text('تبدیل به فاکتور اصلی'),
            onPressed: _converting ? null : _confirmConvertToInvoice,
          ),
        ] else
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
                          invoice: inv, items: _items, sideCosts: _sideCosts, customer: _customer, settings: _settings, vehicleLabel: _vehicleLabel);
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
          Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
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

// ---------------- ویرایشگر هزینه‌های جانبی ----------------

class _EditableCostRow {
  final TextEditingController title;
  final TextEditingController amount;
  _EditableCostRow(String t, String a)
      : title = TextEditingController(text: t),
        amount = TextEditingController(text: a);
  void dispose() {
    title.dispose();
    amount.dispose();
  }
}

class _SideCostsEditorSheet extends StatefulWidget {
  final List<SideCost> initial;
  final Currency currency;
  const _SideCostsEditorSheet({required this.initial, required this.currency});

  @override
  State<_SideCostsEditorSheet> createState() => _SideCostsEditorSheetState();
}

class _SideCostsEditorSheetState extends State<_SideCostsEditorSheet> {
  late final List<_EditableCostRow> _rows;
  final List<_EditableCostRow> _removedRows = []; // کنترلرهای ردیف‌های حذف‌شده؛ در dispose بسته می‌شوند
  String? _error;

  @override
  void initState() {
    super.initState();
    _rows = widget.initial.map((c) => _EditableCostRow(c.title, c.amount.toStringAsFixed(0))).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    for (final r in _removedRows) {
      r.dispose();
    }
    super.dispose();
  }

  double _parse(String text) => double.tryParse(ThousandsInputFormatter.unformat(text.trim())) ?? 0.0;

  double get _total => _rows.fold<double>(0.0, (s, r) => s + _parse(r.amount.text));

  void _addRow() => setState(() => _rows.add(_EditableCostRow('', '')));

  void _removeRow(int i) {
    setState(() => _removedRows.add(_rows.removeAt(i)));
  }

  void _save() {
    final out = <SideCostLine>[];
    for (final r in _rows) {
      final title = r.title.text.trim();
      final amountText = r.amount.text.trim();
      if (title.isEmpty && amountText.isEmpty) continue; // ردیف خالی نادیده گرفته می‌شود
      if (title.isEmpty) {
        setState(() => _error = 'عنوان همه‌ی هزینه‌ها را وارد کنید');
        return;
      }
      final amount = double.tryParse(ThousandsInputFormatter.unformat(amountText));
      if (amount == null || amount <= 0) {
        setState(() => _error = 'مبلغ هر هزینه باید بیشتر از صفر باشد');
        return;
      }
      out.add(SideCostLine(title: title, amount: amount));
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('ویرایش هزینه‌های جانبی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            TextButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('افزودن هزینه'), onPressed: _addRow),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('هزینه‌ای وجود ندارد'))
                : ListView.builder(
                    controller: scrollController,
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      return Padding(
                        key: ObjectKey(r),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            flex: 3,
                            child: TextField(controller: r.title, decoration: const InputDecoration(labelText: 'عنوان هزینه')),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: r.amount,
                              decoration: InputDecoration(labelText: 'مبلغ', suffixText: widget.currency.label),
                              keyboardType: TextInputType.number,
                              inputFormatters: [ThousandsInputFormatter()],
                              onChanged: (_) => setState(() => _error = null),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'حذف',
                            onPressed: () => _removeRow(i),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('جمع هزینه‌های جانبی', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(CurrencyFormatter.format(_total, widget.currency), style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف'))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(onPressed: _save, child: const Text('ذخیره'))),
          ]),
        ]),
      ),
    );
  }
}
