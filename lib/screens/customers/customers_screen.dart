import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/vehicle_reference.dart';
import '../../repositories/customer_repository.dart';
import '../../repositories/vehicle_reference_repository.dart';
import '../../utils/persian_date.dart';
import 'customer_history_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _repo = CustomerRepository();
  final _searchCtrl = TextEditingController();
  List<Customer> _customers = [];
  bool _loading = true;
  bool _debtorsOnly = false;

  // فیلتر خودرو (برند و مدل)
  int? _filterBrandId;
  int? _filterModelId;
  String _filterLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = _searchCtrl.text.trim();
    List<Customer> list;
    if (_debtorsOnly) {
      list = await _repo.getDebtors();
      if (q.isNotEmpty) {
        final byVehicle = await _repo.customerIdsByVehicle(text: q);
        list = list
            .where((c) => c.name.contains(q) || c.mobile.contains(q) || byVehicle.contains(c.id))
            .toList();
      }
    } else {
      list = q.isEmpty ? await _repo.getAll() : await _repo.search(q);
      if (q.isNotEmpty) {
        // علاوه بر نام و شماره تماس، مشتریانی که برند یا مدل خودرویشان با متن می‌خواند.
        final byVehicle = await _repo.customerIdsByVehicle(text: q);
        if (byVehicle.isNotEmpty) {
          final have = list.map((c) => c.id).toSet();
          final extra = (await _repo.getAll()).where((c) => byVehicle.contains(c.id) && !have.contains(c.id));
          list = [...list, ...extra]..sort((a, b) => a.name.compareTo(b.name));
        }
      }
    }
    if (_filterBrandId != null) {
      final ids = await _repo.customerIdsByVehicle(brandId: _filterBrandId, modelId: _filterModelId);
      list = list.where((c) => ids.contains(c.id)).toList();
    }
    if (!mounted) return;
    setState(() {
      _customers = list;
      _loading = false;
    });
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<_VehicleFilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VehicleFilterSheet(brandId: _filterBrandId, modelId: _filterModelId),
    );
    if (result == null) return;
    setState(() {
      _filterBrandId = result.brandId;
      _filterModelId = result.modelId;
      _filterLabel = result.label;
    });
    _load();
  }

  void _clearFilter() {
    setState(() {
      _filterBrandId = null;
      _filterModelId = null;
      _filterLabel = '';
    });
    _load();
  }

  Future<void> _addOrEdit({Customer? customer}) async {
    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final mobileCtrl = TextEditingController(text: customer?.mobile ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(customer == null ? 'مشتری جدید' : 'ویرایش مشتری',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام مشتری')),
          const SizedBox(height: 12),
          TextField(
              controller: mobileCtrl,
              decoration: const InputDecoration(labelText: 'شماره تماس'),
              keyboardType: TextInputType.phone),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              if (customer == null) {
                await _repo.insert(Customer(name: nameCtrl.text.trim(), mobile: mobileCtrl.text.trim()));
              } else {
                await _repo.update(Customer(
                    id: customer.id,
                    name: nameCtrl.text.trim(),
                    mobile: mobileCtrl.text.trim(),
                    createdAt: customer.createdAt));
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: Text(customer == null ? 'ثبت مشتری' : 'ذخیره تغییرات'),
          ),
          if (customer != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await _repo.softDelete(customer.id!);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('حذف مشتری', style: TextStyle(color: Colors.red)),
            ),
          ],
        ]),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final filterActive = _filterBrandId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('مشتریان'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(hintText: 'جستجوی مشتری', prefixIcon: Icon(Icons.search)),
                onChanged: (_) => _load(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'فیلتر خودرو',
              icon: Icon(
                filterActive ? Icons.filter_alt : Icons.filter_alt_outlined,
                color: filterActive ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: _openFilter,
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilterChip(
              label: const Text('مشتریان بدهکار'),
              avatar: const Icon(Icons.warning_amber, size: 18, color: Colors.red),
              selected: _debtorsOnly,
              onSelected: (v) {
                setState(() => _debtorsOnly = v);
                _load();
              },
            ),
          ),
        ),
        if (filterActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: InputChip(
                avatar: const Icon(Icons.directions_car_outlined, size: 18),
                label: Text('خودرو: $_filterLabel'),
                onDeleted: _clearFilter,
                deleteButtonTooltipMessage: 'پاک کردن فیلتر',
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _customers.isEmpty
                  ? Center(
                      child: Text(filterActive
                          ? 'مشتری‌ای با این خودرو یافت نشد'
                          : (_debtorsOnly ? 'مشتری بدهکاری ثبت نشده است' : 'مشتری ثبت نشده است')))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                      itemCount: _customers.length,
                      itemBuilder: (context, i) {
                        final c = _customers[i];
                        return Card(
                          color: _debtorsOnly ? Colors.red.shade50 : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _debtorsOnly ? Colors.red.shade100 : null,
                              child: Icon(_debtorsOnly ? Icons.warning_amber : Icons.person),
                            ),
                            title: Text(c.name),
                            subtitle: Text(PersianDateUtil.toPersianDigits(c.mobile)),
                            trailing: IconButton(
                              icon: const Icon(Icons.receipt_long_outlined),
                              tooltip: 'سوابق فاکتورها',
                              onPressed: () => Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => CustomerHistoryScreen(customer: c))),
                            ),
                            onTap: () => _addOrEdit(customer: c),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('افزودن مشتری'),
        onPressed: () => _addOrEdit(),
      ),
    );
  }
}

/// نتیجه‌ی صفحه‌ی فیلتر. brandId خالی یعنی فیلتر پاک شده است.
class _VehicleFilterResult {
  final int? brandId;
  final int? modelId;
  final String label;
  const _VehicleFilterResult({this.brandId, this.modelId, this.label = ''});
}

/// انتخاب برند و بعد مدل‌های همان برند. فقط برای فیلتر است و چیزی ذخیره نمی‌کند.
class _VehicleFilterSheet extends StatefulWidget {
  final int? brandId;
  final int? modelId;
  const _VehicleFilterSheet({this.brandId, this.modelId});

  @override
  State<_VehicleFilterSheet> createState() => _VehicleFilterSheetState();
}

class _VehicleFilterSheetState extends State<_VehicleFilterSheet> {
  final _refRepo = VehicleReferenceRepository();
  List<VehicleBrand> _brands = [];
  List<VehicleModel> _models = [];
  int? _brandId;
  int? _modelId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _brandId = widget.brandId;
    _modelId = widget.modelId;
    _init();
  }

  Future<void> _init() async {
    final brands = await _refRepo.getAllBrands();
    // اگر برند ذخیره‌شده‌ی قبلی دیگر در فهرست نیست، فیلتر قبلی نادیده گرفته می‌شود.
    if (_brandId != null && !brands.any((b) => b.id == _brandId)) {
      _brandId = null;
      _modelId = null;
    }
    final models = _brandId == null ? <VehicleModel>[] : await _refRepo.getModelsByBrand(_brandId!);
    if (_modelId != null && !models.any((m) => m.id == _modelId)) _modelId = null;
    if (!mounted) return;
    setState(() {
      _brands = brands;
      _models = models;
      _loading = false;
    });
  }

  Future<void> _onBrandChanged(int? id) async {
    setState(() {
      _brandId = id;
      _modelId = null;
      _models = [];
    });
    if (id != null) {
      final models = await _refRepo.getModelsByBrand(id);
      if (!mounted) return;
      setState(() => _models = models);
    }
  }

  void _apply() {
    if (_brandId == null) {
      Navigator.pop(context, const _VehicleFilterResult());
      return;
    }
    final brand = _brands.where((b) => b.id == _brandId);
    final model = _models.where((m) => m.id == _modelId);
    final parts = <String>[
      if (brand.isNotEmpty) brand.first.name,
      if (model.isNotEmpty) model.first.name,
    ];
    Navigator.pop(
        context, _VehicleFilterResult(brandId: _brandId, modelId: _modelId, label: parts.join(' / ')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: _loading
          ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('فیلتر بر اساس خودرو',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  value: _brandId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'برند خودرو'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('انتخاب برند')),
                    ..._brands.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                  ],
                  onChanged: _onBrandChanged,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: _modelId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'مدل خودرو'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('همه مدل‌های این برند')),
                    ..._models.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
                  ],
                  onChanged: _brandId == null ? null : (v) => setState(() => _modelId = v),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, const _VehicleFilterResult()),
                      child: const Text('پاک کردن فیلتر'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _apply,
                      child: const Text('اعمال فیلتر'),
                    ),
                  ),
                ]),
              ]),
            ),
    );
  }
}
