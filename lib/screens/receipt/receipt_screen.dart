import 'package:flutter/material.dart';
import '../../models/invoice.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/service.dart';
import '../../models/vehicle_reference.dart';
import '../../models/payment_account.dart';
import '../../models/app_settings.dart';
import '../../repositories/customer_repository.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/vehicle_reference_repository.dart';
import '../../repositories/payment_account_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/invoice_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import '../invoices/invoice_detail_screen.dart';

/// صفحه‌ی اصلی «رسید»: صدور فاکتور با انتخاب نوع، مشتری، اقلام، هزینه جانبی و نوع پرداخت.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key});
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _customerRepo = CustomerRepository();
  final _productRepo = ProductRepository();
  final _serviceRepo = ServiceRepository();
  final _paymentRepo = PaymentAccountRepository();
  final _settingsRepo = SettingsRepository();
  final _invoiceService = InvoiceService();

  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  InvoiceType _type = InvoiceType.electrical;
  PaymentType _paymentType = PaymentType.cash;
  PaymentAccount? _selectedAccount;
  List<PaymentAccount> _accounts = [];
  AppSettings _settings = AppSettings();
  int? _selectedCustomerId;

  final List<InvoiceCartLine> _lines = [];
  final List<SideCostLine> _sideCosts = [];
  bool _issuing = false;
  bool _loadingInitial = true;
  String _nextInvoiceNumber = '';
  DateTime _issueDateTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await _settingsRepo.getSettings();
    final accounts = await _paymentRepo.getAll();
    final nextNum = await _invoiceService.nextInvoiceNumber(_type);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _accounts = accounts;
      _nextInvoiceNumber = nextNum;
      _loadingInitial = false;
    });
  }

  Future<void> _refreshInvoiceNumber() async {
    final nextNum = await _invoiceService.nextInvoiceNumber(_type);
    if (mounted) setState(() => _nextInvoiceNumber = nextNum);
  }

  double get _itemsTotal => _lines.fold(0.0, (s, l) => s + l.total);
  double get _sideCostsTotal => _sideCosts.fold(0.0, (s, c) => s + c.amount);
  double get _finalAmount => _itemsTotal + _sideCostsTotal;

  Future<void> _pickIssueDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _issueDateTime,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_issueDateTime),
    );
    if (time == null) return;
    setState(() {
      _issueDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _showMsg(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickCustomer() async {
    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CustomerPickerSheet(),
    );
    if (selected != null) {
      setState(() {
        _selectedCustomerId = selected.id;
        _nameCtrl.text = selected.name;
        _mobileCtrl.text = selected.mobile;
      });
    }
  }

  Future<void> _addItemManually() async {
    if (_type.isServiceType) {
      final result = await showModalBottomSheet<InvoiceCartLine>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ServicePickerSheet(invoiceType: _type),
      );
      if (result != null) setState(() => _lines.add(result));
    } else {
      final result = await showModalBottomSheet<InvoiceCartLine>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _ProductPickerSheet(),
      );
      if (result != null) setState(() => _lines.add(result));
    }
  }

  Future<void> _editLinePrice(int index) async {
    final line = _lines[index];
    final priceCtrl = TextEditingController(text: line.unitPrice.toStringAsFixed(0));
    final qtyCtrl = TextEditingController(text: line.quantity.toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.description),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'تعداد'), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'قیمت واحد'), keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (saved == true) {
      final newQty = int.tryParse(qtyCtrl.text) ?? line.quantity;
      final newPrice = double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? line.unitPrice;
      setState(() {
        _lines[index].quantity = newQty;
        _lines[index].unitPrice = newPrice;
      });
    }
  }

  Future<void> _addSideCost() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final result = await showModalBottomSheet<SideCostLine>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('افزودن هزینه جانبی', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'عنوان هزینه')),
          const SizedBox(height: 12),
          TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'مبلغ'), keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
              if (titleCtrl.text.trim().isEmpty || amount <= 0) return;
              Navigator.pop(ctx, SideCostLine(title: titleCtrl.text.trim(), amount: amount));
            },
            child: const Text('افزودن'),
          ),
        ]),
      ),
    );
    if (result != null) setState(() => _sideCosts.add(result));
  }

  Future<void> _issue() async {
    if (_lines.isEmpty) {
      _showMsg('حداقل یک قلم اضافه کنید');
      return;
    }
    if ((_paymentType == PaymentType.cardToCard || _paymentType == PaymentType.bankTransfer) &&
        _selectedAccount == null &&
        _accounts.isNotEmpty) {
      _showMsg('لطفاً حساب مقصد را انتخاب کنید');
      return;
    }

    setState(() => _issuing = true);
    try {
      int? customerId = _selectedCustomerId;
      if (customerId == null && _nameCtrl.text.trim().isNotEmpty) {
        if (_mobileCtrl.text.trim().isNotEmpty) {
          final existing = await _customerRepo.search(_mobileCtrl.text.trim());
          final match = existing.where((c) => c.mobile == _mobileCtrl.text.trim());
          if (match.isNotEmpty) {
            customerId = match.first.id;
          }
        }
        customerId ??= await _customerRepo.insert(
            Customer(name: _nameCtrl.text.trim(), mobile: _mobileCtrl.text.trim()));
      }

      final invoiceId = await _invoiceService.issueInvoice(
        type: _type,
        customerId: customerId,
        lines: _lines,
        sideCosts: _sideCosts,
        paymentType: _paymentType,
        paymentAccountInfo:
            _selectedAccount != null ? '${_selectedAccount!.title}: ${_selectedAccount!.number}' : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        issueDateTime: _issueDateTime,
      );
      if (mounted) {
        setState(() {
          _lines.clear();
          _sideCosts.clear();
          _nameCtrl.clear();
          _mobileCtrl.clear();
          _notesCtrl.clear();
          _selectedCustomerId = null;
        });
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: invoiceId)));
        _init();
      }
    } catch (e) {
      _showMsg('خطا در صدور فاکتور: $e');
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  void _clearDraft() {
    setState(() {
      _lines.clear();
      _sideCosts.clear();
      _nameCtrl.clear();
      _mobileCtrl.clear();
      _notesCtrl.clear();
      _selectedAccount = null;
      _selectedCustomerId = null;
      _paymentType = PaymentType.cash;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInitial) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('رسید'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton(
              style: TextButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, shape: const StadiumBorder()),
              onPressed: _issuing ? null : _issue,
              child: const Text('انتشار'),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: primary.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(_settings.shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Chip(label: Text(PersianDateUtil.formatDateNumeric(DateTime.now().toIso8601String()))),
              Chip(label: Text('فاکتور ${PersianDateUtil.toPersianDigits(_nextInvoiceNumber)}')),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<InvoiceType>(
          value: _type,
          decoration: const InputDecoration(labelText: 'نوع فاکتور'),
          items: InvoiceType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
          onChanged: (t) {
            if (t != null) {
              setState(() => _type = t);
              _refreshInvoiceNumber();
            }
          },
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('مشتری', style: TextStyle(fontWeight: FontWeight.w600)),
          TextButton.icon(icon: const Icon(Icons.person_search, size: 18), label: const Text('انتخاب از لیست'), onPressed: _pickCustomer),
        ]),
        Container(
          decoration: BoxDecoration(color: const Color(0xFFEFEFF1), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'نام مشتری', border: InputBorder.none, filled: false),
              onChanged: (_) => setState(() => _selectedCustomerId = null),
            ),
            const Divider(height: 1),
            TextField(
              controller: _mobileCtrl,
              decoration: const InputDecoration(labelText: 'شماره تماس', border: InputBorder.none, filled: false),
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() => _selectedCustomerId = null),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('اقلام فاکتور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.mic_none, size: 18),
              label: const Text('دستور صوتی'),
              onPressed: () => _showMsg('دستور صوتی به‌زودی اضافه می‌شود'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('اسکن'),
              onPressed: () => _showMsg('اسکن کالا به‌زودی اضافه می‌شود'),
            ),
          ]),
        ]),
        TextButton.icon(icon: const Icon(Icons.add), label: const Text('افزودن'), onPressed: _addItemManually),
        const SizedBox(height: 8),
        if (_lines.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(color: const Color(0xFFEFEFF1), borderRadius: BorderRadius.circular(16)),
            child: const Center(child: Text('لیست فاکتور خالی است')),
          ),
        ..._lines.asMap().entries.map((entry) {
          final i = entry.key;
          final line = entry.value;
          return Card(
            child: ListTile(
              title: Text(line.description),
              subtitle: Text(
                  '${PersianDateUtil.toPersianDigits('${line.quantity}')} × ${CurrencyFormatter.format(line.unitPrice, _settings.currency)} = ${CurrencyFormatter.format(line.total, _settings.currency)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                  onPressed: () => _editLinePrice(i),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => setState(() => _lines.removeAt(i)),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('هزینه‌های جانبی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          TextButton.icon(icon: const Icon(Icons.add), label: const Text('افزودن هزینه'), onPressed: _addSideCost),
        ]),
        if (_sideCosts.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(color: const Color(0xFFEFEFF1), borderRadius: BorderRadius.circular(16)),
            child: const Center(child: Text('بدون هزینه')),
          )
        else
          ..._sideCosts.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            return ListTile(
              dense: true,
              title: Text(c.title),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(CurrencyFormatter.format(c.amount, _settings.currency)),
                IconButton(
                    icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _sideCosts.removeAt(i))),
              ]),
            );
          }),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: primary), borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('جمع فاکتور:', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
            Text(CurrencyFormatter.format(_finalAmount, _settings.currency),
                style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<PaymentType>(
          value: _paymentType,
          decoration: const InputDecoration(labelText: 'نوع پرداخت'),
          items: PaymentType.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
          onChanged: (p) => setState(() => _paymentType = p!),
        ),
        const SizedBox(height: 12),
        if (_paymentType == PaymentType.cardToCard || _paymentType == PaymentType.bankTransfer)
          DropdownButtonFormField<PaymentAccount>(
            value: _selectedAccount,
            decoration: const InputDecoration(labelText: 'شماره کارت و شبا'),
            items: _accounts.map((a) => DropdownMenuItem(value: a, child: Text('${a.title} - ${a.number}'))).toList(),
            onChanged: (a) => setState(() => _selectedAccount = a),
          ),
        const SizedBox(height: 12),
        TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'توضیحات'), maxLines: 2),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _issuing ? null : _issue,
          child: _issuing
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('انتشار'),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: _clearDraft, child: const Text('پاک کردن پیش‌نویس', style: TextStyle(color: Colors.red))),
      ]),
    );
  }
}

// ---------------- Customer picker ----------------

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet();
  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _repo = CustomerRepository();
  final _searchCtrl = TextEditingController();
  List<Customer> _results = [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final list = q.isEmpty ? await _repo.getAll() : await _repo.search(q);
    if (mounted) setState(() => _results = list);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text('انتخاب مشتری', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(hintText: 'جستجوی مشتری...', prefixIcon: Icon(Icons.search)),
            onChanged: _search,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('مشتری‌ای یافت نشد'))
                : ListView.builder(
                    controller: scrollController,
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final c = _results[i];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(c.name),
                        subtitle: Text(c.mobile),
                        onTap: () => Navigator.of(context).pop(c),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Service picker with separate brand/model filters ----------------

class _ServicePickerSheet extends StatefulWidget {
  final InvoiceType invoiceType;
  const _ServicePickerSheet({required this.invoiceType});
  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  final _serviceRepo = ServiceRepository();
  final _vehicleRepo = VehicleReferenceRepository();
  final _searchCtrl = TextEditingController();
  List<ServiceItem> _allResults = [];
  List<ServiceItem> _results = [];
  List<VehicleBrand> _brands = [];
  List<VehicleModel> _models = [];
  Map<int, String> _brandNames = {};
  Map<int, String> _modelNames = {};
  int? _filterBrandId;
  int? _filterModelId;
  ServiceItem? _selected;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBrands();
    _search('');
  }

  Future<void> _loadBrands() async {
    final brands = await _vehicleRepo.getAllBrands();
    final Map<int, String> brandNames = {for (final b in brands) b.id!: b.name};
    final Map<int, String> modelNames = {};
    for (final b in brands) {
      final ms = await _vehicleRepo.getModelsByBrand(b.id!);
      for (final m in ms) {
        modelNames[m.id!] = m.name;
      }
    }
    if (mounted) setState(() {
      _brands = brands;
      _brandNames = brandNames;
      _modelNames = modelNames;
    });
  }

  Future<void> _onBrandFilterChanged(int? brandId) async {
    setState(() {
      _filterBrandId = brandId;
      _filterModelId = null;
      _models = [];
    });
    if (brandId != null) {
      final models = await _vehicleRepo.getModelsByBrand(brandId);
      if (mounted) setState(() => _models = models);
    }
    _applyFilter();
  }

  void _applyFilter() {
    var list = _allResults;
    if (_filterBrandId != null) {
      list = list.where((s) => s.brandId == null || s.brandId == _filterBrandId).toList();
    }
    if (_filterModelId != null) {
      list = list.where((s) => s.modelId == null || s.modelId == _filterModelId).toList();
    }
    setState(() => _results = list);
  }

  Future<void> _search(String q) async {
    final list = q.isEmpty ? await _serviceRepo.getAll(onlyActive: true) : await _serviceRepo.search(q);
    if (!mounted) return;
    setState(() => _allResults = list);
    _applyFilter();
  }

  String _brandModelLabel(ServiceItem s) {
    if (s.brandId == null) return 'همه برندها';
    final brand = _brandNames[s.brandId] ?? '؟';
    if (s.modelId != null) {
      final model = _modelNames[s.modelId] ?? '';
      return model.isEmpty ? brand : '$brand / $model';
    }
    return brand;
  }

  void _select(ServiceItem s) {
    setState(() {
      _selected = s;
      _priceCtrl.text = s.price.toStringAsFixed(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: _selected == null
            ? Column(children: [
                const Text('افزودن خدمت', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(hintText: 'جستجوی خدمت...', prefixIcon: Icon(Icons.search)),
                    onChanged: _search),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _filterBrandId,
                      decoration: const InputDecoration(labelText: 'برند', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('همه برندها')),
                        ..._brands.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                      ],
                      onChanged: _onBrandFilterChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _filterModelId,
                      decoration: const InputDecoration(labelText: 'مدل', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('همه مدل‌ها')),
                        ..._models.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
                      ],
                      onChanged: _filterBrandId == null
                          ? null
                          : (v) {
                              setState(() => _filterModelId = v);
                              _applyFilter();
                            },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: _results.isEmpty
                      ? const Center(child: Text('خدمتی یافت نشد'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final s = _results[i];
                            return ListTile(
                              title: Text(s.name),
                              subtitle: Text(_brandModelLabel(s)),
                              trailing: Text(CurrencyFormatter.formatPlain(s.price)),
                              onTap: () => _select(s),
                            );
                          },
                        ),
                ),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  title: Text(_selected!.name),
                  subtitle: Text(_brandModelLabel(_selected!)),
                  trailing: TextButton(onPressed: () => setState(() => _selected = null), child: const Text('تغییر')),
                ),
                Row(children: [
                  Expanded(
                    child: TextField(controller: _qtyCtrl, decoration: const InputDecoration(labelText: 'تعداد'), keyboardType: TextInputType.number),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(controller: _priceCtrl, decoration: const InputDecoration(labelText: 'قیمت واحد (قابل ویرایش)'), keyboardType: TextInputType.number),
                  ),
                ]),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
                    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '')) ?? _selected!.price;
                    Navigator.pop(
                        context,
                        InvoiceCartLine(
                            itemType: InvoiceItemType.service,
                            serviceId: _selected!.id,
                            description: _selected!.name,
                            quantity: qty,
                            unitPrice: price));
                  },
                  child: const Text('افزودن به فاکتور'),
                ),
              ]),
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _repo = ProductRepository();
  final _searchCtrl = TextEditingController();
  List<Product> _results = [];
  Product? _selected;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final list = q.isEmpty ? await _repo.getAll() : await _repo.search(q);
    if (mounted) setState(() => _results = list);
  }

  void _select(Product p) {
    setState(() {
      _selected = p;
      _priceCtrl.text = p.sellPrice.toStringAsFixed(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: _selected == null
            ? Column(children: [
                const Text('افزودن کالا', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(hintText: 'جستجوی کالا...', prefixIcon: Icon(Icons.search)),
                    onChanged: _search),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final p = _results[i];
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text('موجودی: ${p.stock}'),
                        trailing: Text(CurrencyFormatter.formatPlain(p.sellPrice)),
                        onTap: () => _select(p),
                      );
                    },
                  ),
                ),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  title: Text(_selected!.name),
                  subtitle: Text('موجودی: ${_selected!.stock}'),
                  trailing: TextButton(onPressed: () => setState(() => _selected = null), child: const Text('تغییر')),
                ),
                Row(children: [
                  Expanded(
                    child: TextField(controller: _qtyCtrl, decoration: const InputDecoration(labelText: 'تعداد'), keyboardType: TextInputType.number),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(controller: _priceCtrl, decoration: const InputDecoration(labelText: 'قیمت واحد (قابل ویرایش)'), keyboardType: TextInputType.number),
                  ),
                ]),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
                    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '')) ?? _selected!.sellPrice;
                    if (qty > _selected!.stock) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('موجودی کافی نیست (موجودی: ${_selected!.stock})')));
                      return;
                    }
                    Navigator.pop(
                        context,
                        InvoiceCartLine(
                            itemType: InvoiceItemType.product,
                            productId: _selected!.id,
                            description: _selected!.name,
                            quantity: qty,
                            unitPrice: price));
                  },
                  child: const Text('افزودن به فاکتور'),
                ),
              ]),
      ),
    );
  }
}
