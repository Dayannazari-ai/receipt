import 'package:flutter/material.dart';
import '../../models/service.dart';
import '../../models/vehicle_reference.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/vehicle_reference_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../repositories/settings_repository.dart';
import '../../models/app_settings.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _categoryRepo = ServiceCategoryRepository();
  final _serviceRepo = ServiceRepository();
  final _settingsRepo = SettingsRepository();
  final _vehicleRepo = VehicleReferenceRepository();

  List<ServiceCategory> _categories = [];
  List<ServiceItem> _services = [];
  List<VehicleBrand> _brands = [];
  List<VehicleModel> _models = [];
  Map<int, String> _brandNames = {};
  Map<int, String> _modelNames = {};
  Currency _currency = Currency.toman;
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  int? _filterBrandId;
  int? _filterModelId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final categories = await _categoryRepo.getAll();
    var services =
        _searchCtrl.text.trim().isEmpty ? await _serviceRepo.getAll() : await _serviceRepo.search(_searchCtrl.text.trim());
    if (_filterBrandId != null) {
      services = services.where((s) => s.brandId == _filterBrandId).toList();
    }
    if (_filterModelId != null) {
      services = services.where((s) => s.modelId == _filterModelId).toList();
    }
    final brands = await _vehicleRepo.getAllBrands();
    final settings = await _settingsRepo.getSettings();

    // نگاشت شناسه برند/مدل به نام واقعی برای نمایش صحیح در لیست
    final brandNames = {for (final b in brands) b.id!: b.name};
    final Map<int, String> modelNames = {};
    for (final b in brands) {
      final ms = await _vehicleRepo.getModelsByBrand(b.id!);
      for (final m in ms) {
        modelNames[m.id!] = m.name;
      }
    }

    List<VehicleModel> models = [];
    if (_filterBrandId != null) {
      models = await _vehicleRepo.getModelsByBrand(_filterBrandId!);
    }

    if (!mounted) return;
    setState(() {
      _categories = categories;
      _services = services;
      _brands = brands;
      _models = models;
      _brandNames = brandNames;
      _modelNames = modelNames;
      _currency = settings.currency;
      _loading = false;
    });
  }

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('دسته‌بندی جدید'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'نام دسته‌بندی')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('افزودن')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _categoryRepo.insert(ServiceCategory(name: name));
      _load();
    }
  }

  Future<void> _addOrEditService({ServiceItem? service}) async {
    if (_categories.isEmpty) {
      await _addCategory();
      if (_categories.isEmpty) return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ServiceFormSheet(categories: _categories, service: service),
    );
    if (saved == true) _load();
  }

  String _brandLabel(ServiceItem s) {
    if (s.brandId == null) return 'همه برندها';
    final name = _brandNames[s.brandId] ?? '؟';
    if (s.modelId != null) {
      final model = _modelNames[s.modelId] ?? '';
      return model.isEmpty ? name : '$name / $model';
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final Map<int, List<ServiceItem>> grouped = {};
    for (final s in _services) {
      grouped.putIfAbsent(s.categoryId, () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('خدمات'), actions: [
        IconButton(icon: const Icon(Icons.create_new_folder_outlined), onPressed: _addCategory),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(hintText: 'جستجوی خدمت', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => _load(),
          ),
        ),
        // فیلتر جداگانه برند و مدل - طبق درخواست، جدا از هم برای جستجوی دقیق‌تر
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: _filterBrandId,
                decoration: const InputDecoration(labelText: 'فیلتر برند', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('همه برندها')),
                  ..._brands.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                ],
                onChanged: (v) {
                  setState(() {
                    _filterBrandId = v;
                    _filterModelId = null;
                  });
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: _filterModelId,
                decoration: const InputDecoration(labelText: 'فیلتر مدل', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('همه مدل‌ها')),
                  ..._models.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
                ],
                onChanged: _filterBrandId == null
                    ? null
                    : (v) {
                        setState(() => _filterModelId = v);
                        _load();
                      },
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _categories.isEmpty
                  ? const Center(child: Text('ابتدا یک دسته‌بندی ایجاد کنید'))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: _categories.map((cat) {
                        final list = grouped[cat.id] ?? [];
                        if (list.isEmpty && (_searchCtrl.text.isNotEmpty || _filterBrandId != null)) {
                          return const SizedBox.shrink();
                        }
                        return ExpansionTile(
                          title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          children: list.isEmpty
                              ? [const ListTile(title: Text('خدمتی ثبت نشده'))]
                              : list
                                  .map((s) => ListTile(
                                        title: Text(s.name),
                                        subtitle: Text(_brandLabel(s)),
                                        trailing: Text(CurrencyFormatter.format(s.price, _currency)),
                                        onTap: () => _addOrEditService(service: s),
                                      ))
                                  .toList(),
                        );
                      }).toList(),
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('خدمت جدید'),
        onPressed: () => _addOrEditService(),
      ),
    );
  }
}

/// فرم افزودن/ویرایش خدمت با انتخاب کلیکی دسته‌بندی، برند و مدل از بانک اطلاعات.
class _ServiceFormSheet extends StatefulWidget {
  final List<ServiceCategory> categories;
  final ServiceItem? service;
  const _ServiceFormSheet({required this.categories, this.service});

  @override
  State<_ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends State<_ServiceFormSheet> {
  final _vehicleRepo = VehicleReferenceRepository();
  final _serviceRepo = ServiceRepository();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _priceCtrl;
  int? _categoryId;
  int? _brandId;
  int? _modelId;
  List<VehicleBrand> _brands = [];
  List<VehicleModel> _models = [];
  bool _saving = false;

  bool get _isEdit => widget.service != null;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _codeCtrl = TextEditingController(text: s?.code ?? '');
    _priceCtrl = TextEditingController(text: s?.price.toStringAsFixed(0) ?? '');
    _categoryId = s?.categoryId ?? widget.categories.first.id;
    _brandId = s?.brandId;
    _modelId = s?.modelId;
    _loadBrands();
  }

  Future<void> _loadBrands() async {
    final brands = await _vehicleRepo.getAllBrands();
    if (!mounted) return;
    setState(() => _brands = brands);
    if (_brandId != null) _loadModels(_brandId!);
  }

  Future<void> _loadModels(int brandId) async {
    final models = await _vehicleRepo.getModelsByBrand(brandId);
    if (!mounted) return;
    setState(() => _models = models);
  }

  Future<void> _pickBrand() async {
    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => _PickerSheet(
        title: 'انتخاب برند',
        items: [
          const _PickerItem(id: null, label: 'همه برندها'),
          ..._brands.map((b) => _PickerItem(id: b.id, label: b.name)),
        ],
        onAddNew: (name) async {
          final id = await _vehicleRepo.insertBrand(name);
          await _loadBrands();
          return id;
        },
      ),
    );
    if (selected != _brandId) {
      setState(() {
        _brandId = selected;
        _modelId = null;
        _models = [];
      });
      if (selected != null) _loadModels(selected);
    }
  }

  Future<void> _pickModel() async {
    if (_brandId == null) return;
    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => _PickerSheet(
        title: 'انتخاب مدل',
        items: [
          const _PickerItem(id: null, label: 'همه مدل‌های این برند'),
          ..._models.map((m) => _PickerItem(id: m.id, label: m.name)),
        ],
        onAddNew: (name) async {
          final id = await _vehicleRepo.insertModel(_brandId!, name);
          await _loadModels(_brandId!);
          return id;
        },
      ),
    );
    setState(() => _modelId = selected);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _codeCtrl.text.trim().isEmpty) return;
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null || price < 0) return;

    final codeExists = await _serviceRepo.codeExists(_codeCtrl.text.trim(), excludeId: widget.service?.id);
    if (codeExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('این کد قبلاً استفاده شده است')));
      }
      return;
    }

    setState(() => _saving = true);
    final newItem = ServiceItem(
      id: widget.service?.id,
      name: _nameCtrl.text.trim(),
      code: _codeCtrl.text.trim(),
      categoryId: _categoryId!,
      brandId: _brandId,
      modelId: _modelId,
      price: price,
    );
    if (_isEdit) {
      await _serviceRepo.update(widget.service!, newItem);
    } else {
      await _serviceRepo.insert(newItem);
    }
    if (mounted) Navigator.pop(context, true);
  }

  String _brandLabel() {
    if (_brandId == null) return 'همه برندها';
    final b = _brands.where((x) => x.id == _brandId);
    return b.isEmpty ? 'انتخاب شده' : b.first.name;
  }

  String _modelLabel() {
    if (_modelId == null) return 'همه مدل‌ها';
    final m = _models.where((x) => x.id == _modelId);
    return m.isEmpty ? 'انتخاب شده' : m.first.name;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_isEdit ? 'ویرایش خدمت' : 'خدمت جدید', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'نام خدمت')),
          const SizedBox(height: 12),
          TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'کد خدمت')),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _categoryId,
            decoration: const InputDecoration(labelText: 'دسته‌بندی'),
            items: widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: const Color(0xFFEFEFF1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('برند خودرو'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(_brandLabel()), const Icon(Icons.chevron_left)]),
            onTap: _pickBrand,
          ),
          const SizedBox(height: 10),
          ListTile(
            tileColor: const Color(0xFFEFEFF1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('مدل خودرو'),
            enabled: _brandId != null,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(_modelLabel()), const Icon(Icons.chevron_left)]),
            onTap: _pickModel,
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'قیمت'),
              keyboardType: TextInputType.number),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEdit ? 'ذخیره تغییرات' : 'ثبت خدمت'),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await _serviceRepo.softDelete(widget.service!.id!);
                if (mounted) Navigator.pop(context, true);
              },
              child: const Text('حذف خدمت', style: TextStyle(color: Colors.red)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _PickerItem {
  final int? id;
  final String label;
  const _PickerItem({required this.id, required this.label});
}

class _PickerSheet extends StatefulWidget {
  final String title;
  final List<_PickerItem> items;
  final Future<int> Function(String name) onAddNew;
  const _PickerSheet({required this.title, required this.items, required this.onAddNew});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _newCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _newCtrl,
                decoration: const InputDecoration(hintText: 'افزودن مورد جدید...'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green),
              onPressed: () async {
                final name = _newCtrl.text.trim();
                if (name.isEmpty) return;
                final id = await widget.onAddNew(name);
                if (context.mounted) Navigator.pop(context, id);
              },
            ),
          ]),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: widget.items.length,
              itemBuilder: (context, i) {
                final item = widget.items[i];
                return ListTile(
                  title: Text(item.label),
                  onTap: () => Navigator.pop(context, item.id),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
