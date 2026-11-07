import 'package:flutter/material.dart';
import '../../models/service.dart';
import '../../models/vehicle_reference.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/service_code_manager.dart';
import '../../repositories/service_group_repository.dart';
import 'category_prefix_dialog.dart';
import '../../repositories/vehicle_reference_repository.dart';
import '../voice_search_sheet.dart';
import '../../services/voice_search_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/thousands_input_formatter.dart';
import '../../repositories/settings_repository.dart';
import '../../models/app_settings.dart';

/// تبدیل ارقام فارسی/عربی به انگلیسی فقط برای مقایسهٔ کدها در مرتب‌سازی.
String _normDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(r - 0x06F0 + 0x30);
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(r - 0x0660 + 0x30);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// مقایسهٔ کدها: کدهای عددی به‌صورت عددی (۲ قبل از ۱۰)، سپس متنی.
int _compareCodes(String a, String b) {
  final na = _normDigits(a.trim());
  final nb = _normDigits(b.trim());
  final ia = int.tryParse(na);
  final ib = int.tryParse(nb);
  if (ia != null && ib != null) {
    final c = ia.compareTo(ib);
    if (c != 0) return c;
    return 0;
  }
  if (ia != null) return -1;
  if (ib != null) return 1;
  return na.compareTo(nb);
}

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _categoryRepo = ServiceCategoryRepository();
  final _groupRepo = ServiceGroupRepository();
  final _serviceRepo = ServiceRepository();
  final _settingsRepo = SettingsRepository();
  final _vehicleRepo = VehicleReferenceRepository();

  List<ServiceCategory> _categories = [];
  List<ServiceGroup> _groups = [];
  List<ServiceItem> _services = [];
  List<VehicleBrand> _brands = [];
  List<VehicleModel> _models = [];
  Map<int, String> _brandNames = {};
  Map<int, String> _modelNames = {};
  Currency _currency = Currency.toman;
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  int? _filterCategoryId;
  int? _filterGroupId;
  int? _filterBrandId;
  int? _filterModelId;
  String _sortBy = 'name'; // 'name' یا 'code'

  // حالت انتخاب گروهی (برای حذف دسته‌جمعی)
  bool _selecting = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _compareServices(ServiceItem a, ServiceItem b) {
    if (_sortBy == 'code') {
      final c = _compareCodes(a.code, b.code);
      if (c != 0) return c;
    }
    return a.name.compareTo(b.name);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final categories = await _categoryRepo.getAll();

    // فیلتر دسته‌بندی و مجموعه: اگر دیگر معتبر نباشند (مثلاً دسته بایگانی شده) بازنشانی می‌شوند.
    final int? catFilter = (_filterCategoryId != null && categories.any((c) => c.id == _filterCategoryId))
        ? _filterCategoryId
        : null;
    final List<ServiceGroup> groups =
        catFilter == null ? <ServiceGroup>[] : await _groupRepo.getByCategory(catFilter);
    final int? groupFilter =
        (catFilter != null && _filterGroupId != null && groups.any((g) => g.id == _filterGroupId))
            ? _filterGroupId
            : null;

    var services =
        _searchCtrl.text.trim().isEmpty ? await _serviceRepo.getAll() : await _serviceRepo.search(_searchCtrl.text.trim());
    if (catFilter != null) {
      services = services.where((s) => s.categoryId == catFilter).toList();
    }
    if (groupFilter != null) {
      services = services.where((s) => s.serviceGroupId == groupFilter).toList();
    }
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
      // فقط مواردی که الان در لیست دیده می‌شوند انتخاب بمانند
      // (با تغییر جستجو/فیلتر، مورد مخفی هرگز حذف نشود)
      final catIds = categories.map((c) => c.id).toSet();
      final visibleIds = services.where((s) => catIds.contains(s.categoryId)).map((s) => s.id).toSet();
      _selected.removeWhere((id) => !visibleIds.contains(id));
      _categories = categories;
      _filterCategoryId = catFilter;
      _filterGroupId = groupFilter;
      _groups = groups;
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
    final r = await askCategoryNameAndPrefix(context);
    if (r == null) return;
    try {
      await _categoryRepo.add(r.name, prefix: r.prefix);
    } on ServiceCategoryException catch (e) {
      if (mounted) await showCategoryError(context, e.message);
    }
    await _load();
  }

  /// مدیریت دسته‌بندی‌ها (تغییر نام، حذف/بایگانی، بازیابی، مجموعه‌ها). بعد از بسته شدن، فهرست خدمات تازه می‌شود.
  Future<void> _openCategoryManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CategoryManagerSheet(),
    );
    if (mounted) _load();
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

  Future<void> _showServiceActions(ServiceItem service) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('ویرایش'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.checklist),
            title: const Text('انتخاب گروهی'),
            onTap: () => Navigator.pop(ctx, 'select'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('حذف', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (action == 'edit') {
      _addOrEditService(service: service);
    } else if (action == 'select') {
      _enterSelection(service);
    } else if (action == 'delete') {
      _confirmDeleteService(service);
    }
  }

  Future<void> _confirmDeleteService(ServiceItem service) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف خدمت'),
        content: const Text('آیا از حذف این خدمت مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _serviceRepo.softDelete(service.id!);
      _load();
    }
  }

  // ---------- انتخاب گروهی و حذف دسته‌جمعی ----------

  /// خدماتی که واقعاً در لیست نمایش داده می‌شوند (دسته‌بندی‌شان موجود است).
  Iterable<ServiceItem> get _visibleServices {
    final catIds = _categories.map((c) => c.id).toSet();
    return _services.where((s) => catIds.contains(s.categoryId));
  }

  bool get _allSelected {
    final vis = _visibleServices.toList();
    return vis.isNotEmpty && vis.every((s) => _selected.contains(s.id));
  }

  void _enterSelection(ServiceItem? first) {
    setState(() {
      _selecting = true;
      _selected.clear();
      if (first?.id != null) _selected.add(first!.id!);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleService(ServiceItem s) {
    final id = s.id;
    if (id == null) return;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_visibleServices.map((s) => s.id!));
      }
    });
  }

  void _toggleCategory(List<ServiceItem> list) {
    final ids = list.map((s) => s.id!).toList();
    setState(() {
      if (ids.every(_selected.contains)) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف گروهی خدمات'),
        content: Text('$count خدمت حذف می‌شود.\nفاکتورهای قبلی و اقلام آن‌ها هیچ تغییری نمی‌کنند.\nادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    await _serviceRepo.softDeleteMany(_selected.toList());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count خدمت حذف شد')));
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _load();
  }

  AppBar _selectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'خروج از انتخاب',
        onPressed: _exitSelection,
      ),
      title: Text('${_selected.length} انتخاب شده'),
      actions: [
        IconButton(
          icon: Icon(_allSelected ? Icons.deselect : Icons.select_all),
          tooltip: _allSelected ? 'لغو انتخاب همه' : 'انتخاب همه',
          onPressed: _visibleServices.isEmpty ? null : _toggleAll,
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: _selected.isEmpty ? null : Colors.red),
          tooltip: 'حذف انتخاب‌شده‌ها',
          onPressed: _selected.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
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
    for (final l in grouped.values) {
      l.sort(_compareServices);
    }
    // اگر فیلتر دسته‌بندی انتخاب شده باشد، فقط همان دسته نمایش داده می‌شود.
    final shownCategories =
        _filterCategoryId == null ? _categories : _categories.where((c) => c.id == _filterCategoryId).toList();

    return Scaffold(
      appBar: _selecting
          ? _selectionAppBar()
          : AppBar(title: const Text('خدمات'), actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                tooltip: 'مرتب‌سازی',
                onSelected: (v) => setState(() => _sortBy = v),
                itemBuilder: (_) => [
                  CheckedPopupMenuItem<String>(
                    value: 'name',
                    checked: _sortBy == 'name',
                    child: const Text('بر اساس نام'),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'code',
                    checked: _sortBy == 'code',
                    child: const Text('بر اساس کد'),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: 'انتخاب گروهی',
                onPressed: () => _enterSelection(null),
              ),
              IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  tooltip: 'مدیریت دسته‌بندی‌ها',
                  onPressed: _openCategoryManager),
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
        // فیلتر دسته‌بندی و مجموعه خدمات: اول دسته، بعد مجموعه‌های همان دسته
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                key: ValueKey('fc-$_filterCategoryId-${_categories.length}'),
                value: _categories.any((c) => c.id == _filterCategoryId) ? _filterCategoryId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'فیلتر دسته‌بندی', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('همه دسته‌ها')),
                  ..._categories.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) {
                  setState(() {
                    _filterCategoryId = v;
                    _filterGroupId = null;
                    _groups = [];
                  });
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int?>(
                key: ValueKey('fg-$_filterCategoryId-$_filterGroupId-${_groups.length}'),
                value: _groups.any((g) => g.id == _filterGroupId) ? _filterGroupId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'فیلتر مجموعه خدمات', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('همه مجموعه‌ها')),
                  ..._groups.map((g) => DropdownMenuItem<int?>(
                      value: g.id, child: Text(g.active ? g.name : '${g.name} (غیرفعال)'))),
                ],
                onChanged: _filterCategoryId == null
                    ? null
                    : (v) {
                        setState(() => _filterGroupId = v);
                        _load();
                      },
              ),
            ),
          ]),
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
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                      children: shownCategories.map((cat) {
                        final list = grouped[cat.id] ?? [];
                        if (list.isEmpty &&
                            _filterCategoryId == null &&
                            (_searchCtrl.text.isNotEmpty || _filterBrandId != null)) {
                          return const SizedBox.shrink();
                        }
                        final selCount = list.where((s) => _selected.contains(s.id)).length;
                        return ExpansionTile(
                          leading: (_selecting && list.isNotEmpty)
                              ? Checkbox(
                                  tristate: true,
                                  value: selCount == 0 ? false : (selCount == list.length ? true : null),
                                  onChanged: (_) => _toggleCategory(list),
                                )
                              : null,
                          title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          children: list.isEmpty
                              ? [const ListTile(title: Text('خدمتی ثبت نشده'))]
                              : list.map((s) => GestureDetector(
                                        onLongPress: _selecting ? () => _toggleService(s) : () => _showServiceActions(s),
                                        child: ListTile(
                                          leading: _selecting
                                              ? Checkbox(
                                                  value: _selected.contains(s.id),
                                                  onChanged: (_) => _toggleService(s),
                                                )
                                              : null,
                                          selected: _selecting && _selected.contains(s.id),
                                          title: Text(s.name),
                                          subtitle: Text(_sortBy == 'code'
                                              ? 'کد: ${s.code} - ${_brandLabel(s)}'
                                              : _brandLabel(s)),
                                          trailing: Text(CurrencyFormatter.format(s.price, _currency)),
                                          onTap: _selecting ? () => _toggleService(s) : () => _addOrEditService(service: s),
                                        ),
                                      ))
                                  .toList(),
                        );
                      }).toList(),
                    ),
        ),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('خدمت جدید'),
              onPressed: () => _addOrEditService(),
            ),
    );
  }
}

/// فرم افزودن/ویرایش خدمت با انتخاب کلیکی دسته‌بندی، مجموعه، برند و مدل از بانک اطلاعات.
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
  final _groupRepo = ServiceGroupRepository();
  final _codeMgr = ServiceCodeManager();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _voiceLabelCtrl;
  int? _categoryId;
  int? _groupId;
  int? _brandId;
  int? _modelId;
  List<ServiceGroup> _groups = [];
  List<VehicleBrand> _brands = [];
  List<VehicleModel> _models = [];
  bool _saving = false;
  // آخرین کدی که خودکار در فیلد گذاشته شده
  String? _autoCode;
  String? _codeNotice;

  bool get _isEdit => widget.service != null;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _codeCtrl = TextEditingController(text: s?.code ?? '');
    _priceCtrl = TextEditingController(text: s?.price.toStringAsFixed(0) ?? '');
    _voiceLabelCtrl = TextEditingController(text: s?.voiceSearchLabel ?? '');
    _categoryId = s?.categoryId ?? widget.categories.first.id;
    _groupId = s?.serviceGroupId;
    _brandId = s?.brandId;
    _modelId = s?.modelId;
    if (s == null) _prefillNextCode();
    _loadGroups();
    _loadBrands();
  }

  /// مجموعه‌های قابل انتخاب برای دسته‌ی فعلی: فقط فعال‌ها؛ در ویرایش، مجموعه‌ی
  /// غیرفعالِ فعلیِ خود خدمت هم نگه داشته می‌شود. اگر مجموعه‌ی انتخاب‌شده
  /// در این فهرست نباشد (نامربوط به دسته)، پاک می‌شود.
  Future<void> _loadGroups() async {
    final cat = _categoryId;
    if (cat == null) {
      if (mounted) {
        setState(() {
          _groups = [];
          _groupId = null;
        });
      }
      return;
    }
    final all = await _groupRepo.getByCategory(cat);
    if (!mounted || _categoryId != cat) return;
    final keep = widget.service?.serviceGroupId;
    final list = all.where((g) => g.active || (_isEdit && g.id == keep)).toList();
    setState(() {
      _groups = list;
      if (_groupId != null && !list.any((g) => g.id == _groupId)) _groupId = null;
    });
  }

  /// کد پیشنهادی (کوچک‌ترین کد آزاد؛ اگر نبود، شماره‌ی بعد از آخرین) برای سری دسته‌ی داده‌شده.
  Future<void> _suggestFor(int? categoryId) async {
    try {
      final info = await _codeMgr.loadCodeInfo(categoryId: categoryId);
      if (!mounted || _categoryId != categoryId) return;
      setState(() {
        _autoCode = info.suggested;
        _codeCtrl.text = info.suggested;
        _codeNotice = null;
      });
    } on ServiceCategoryException catch (e) {
      if (!mounted || _categoryId != categoryId) return;
      setState(() {
        _autoCode = null;
        _codeCtrl.text = '';
        _codeNotice = e.message;
      });
    } catch (_) {}
  }

  Future<void> _prefillNextCode() => _suggestFor(_categoryId);

  /// با عوض شدن دسته، مجموعه‌ی نامربوط پاک می‌شود (در ویرایش، با برگشت به دسته‌ی
  /// اصلی مجموعه‌ی قبلیِ خدمت برمی‌گردد) و کد به سری همان دسته می‌رود.
  /// در ویرایش خدمت هیچ کدی عوض نمی‌شود.
  Future<void> _onCategoryChanged(int? v) async {
    setState(() {
      _categoryId = v;
      _groups = [];
      _groupId = (_isEdit && v != null && v == widget.service!.categoryId) ? widget.service!.serviceGroupId : null;
    });
    await _loadGroups();
    if (_isEdit || v == null) return;
    await _suggestFor(v);
  }

  /// آیکون کنار فیلد کد: فهرست کدهای آزاد این دسته، برای انتخاب.
  Future<void> _pickFreeCode() async {
    if (_isEdit) return;
    final ServiceCodeInfo info;
    try {
      info = await _codeMgr.loadCodeInfo(categoryId: _categoryId);
    } on ServiceCategoryException catch (e) {
      await _showError(e.message);
      return;
    }
    if (!mounted) return;
    Widget codeText(String c) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Directionality(textDirection: TextDirection.ltr, child: Text(c)));
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('انتخاب کد خدمت', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          if (info.freeCodes.isEmpty) ...[
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('کد آزادی وجود ندارد؛ کد بعدی خودکار اختصاص داده می‌شود.')),
            ListTile(
                title: codeText(info.suggested),
                selected: info.suggested == _autoCode,
                onTap: () => Navigator.pop(ctx, info.suggested)),
          ] else ...[
            const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('کدهای آزاد (خدمات حذف‌شده‌ی بدون سابقه‌ی فاکتور)',
                    style: TextStyle(fontSize: 12, color: Colors.grey))),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final c in info.freeCodes)
                  ListTile(title: codeText(c), selected: c == _autoCode, onTap: () => Navigator.pop(ctx, c)),
              ]),
            ),
          ],
        ]),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _autoCode = picked;
        _codeCtrl.text = picked;
        _codeNotice = null;
      });
    }
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

  List<_PickerItem> _brandItems() => [
        const _PickerItem(id: null, label: 'همه برندها'),
        ..._brands.map((b) => _PickerItem(id: b.id, label: b.name)),
      ];

  List<_PickerItem> _modelItems() => [
        const _PickerItem(id: null, label: 'همه مدل‌های این برند'),
        ..._models.map((m) => _PickerItem(id: m.id, label: m.name)),
      ];

  Future<void> _pickBrand() async {
    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => _PickerSheet(
        title: 'انتخاب برند',
        items: _brandItems(),
        deleteTitle: 'حذف برند',
        deleteMessage:
            'آیا از حذف این برند مطمئن هستید؟ اگر در مدل‌ها، خدمات یا خودروها استفاده شده باشد، فقط از لیست‌ها مخفی می‌شود و سوابق قبلی حفظ می‌ماند.',
        reloadItems: () async {
          await _loadBrands();
          return _brandItems();
        },
        onAddNew: (name) async {
          final id = await _vehicleRepo.insertBrand(name);
          await _loadBrands();
          return id;
        },
        onEdit: (id, newName) async {
          await _vehicleRepo.updateBrand(id, newName);
          await _loadBrands();
        },
        onDelete: (id) async {
          await _vehicleRepo.deleteBrand(id);
          await _loadBrands();
          if (_brandId == id) {
            setState(() {
              _brandId = null;
              _modelId = null;
              _models = [];
            });
          }
          return null;
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
    final brandId = _brandId!;
    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => _PickerSheet(
        title: 'انتخاب مدل',
        items: _modelItems(),
        deleteTitle: 'حذف مدل',
        deleteMessage: 'آیا از حذف این مدل مطمئن هستید؟',
        reloadItems: () async {
          await _loadModels(brandId);
          return _modelItems();
        },
        onAddNew: (name) async {
          final id = await _vehicleRepo.insertModel(brandId, name);
          await _loadModels(brandId);
          return id;
        },
        onEdit: (id, newName) async {
          await _vehicleRepo.updateModel(id, newName);
          await _loadModels(brandId);
        },
        onDelete: (id) async {
          // مدلی که در خدمات یا خودروها استفاده شده حذف نمی‌شود تا هیچ
          // سابقه‌ای خراب نشود؛ در این حالت پیام خطا برمی‌گردد.
          final deleted = await _vehicleRepo.deleteModel(id);
          if (!deleted) return 'این مدل در خدمات یا خودروها استفاده شده و قابل حذف نیست. فقط می‌توانید نام آن را ویرایش کنید.';
          await _loadModels(brandId);
          if (_modelId == id) setState(() => _modelId = null);
          return null;
        },
      ),
    );
    setState(() => _modelId = selected);
  }

  Future<void> _recordVoiceLabel() async {
    final text = await VoiceSearchService().listenOnce();
    if (text == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تشخیص گفتار در دسترس نیست یا صدایی شناسایی نشد.')));
      }
      return;
    }
    setState(() => _voiceLabelCtrl.text = text);
  }

  /// پیام خطا وسط صفحه. چون داخل خود برگه نمایش داده می‌شود، زیر آن پنهان نمی‌ماند.
  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ثبت انجام نشد'),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه'))],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    try {
      if (_nameCtrl.text.trim().isEmpty) {
        await _showError('نام خدمت را وارد کنید.');
        return;
      }
      // خدمت جدید با کد خالی: کد پیشنهادی سیستم جایگزین می‌شود.
      if (!_isEdit && _codeCtrl.text.trim().isEmpty) {
        _codeCtrl.text = await _serviceRepo.nextAutoCode(categoryId: _categoryId);
      }
      final code = _codeCtrl.text.trim();
      if (code.isEmpty) {
        await _showError('کد خدمت خالی است.');
        return;
      }
      final price = double.tryParse(ThousandsInputFormatter.unformat(_priceCtrl.text));
      if (price == null || price < 0) {
        await _showError('قیمت را درست وارد کنید.');
        return;
      }
      if (_categoryId == null) {
        await _showError('دسته‌بندی را انتخاب کنید.');
        return;
      }
      // در ویرایش، فقط اگر کد عوض شده باشد تکراری‌بودن بررسی می‌شود.
      final codeChanged = !_isEdit || code != widget.service!.code.trim();
      if (codeChanged && await _serviceRepo.codeExists(code, excludeId: widget.service?.id)) {
        await _showError('کد «$code» تکراری است و قبلاً برای خدمت دیگری ثبت شده؛ کد دیگری انتخاب کنید.');
        return;
      }

      setState(() => _saving = true);
      final newItem = ServiceItem(
        id: widget.service?.id,
        name: _nameCtrl.text.trim(),
        code: code,
        categoryId: _categoryId!,
        brandId: _brandId,
        modelId: _modelId,
        serviceGroupId: _groupId,
        price: price,
        voiceSearchLabel: _voiceLabelCtrl.text.trim().isEmpty ? null : _voiceLabelCtrl.text.trim(),
      );
      if (_isEdit) {
        await _serviceRepo.update(widget.service!, newItem);
      } else {
        await _serviceRepo.insert(newItem);
      }
      if (mounted) Navigator.pop(context, true);
    } on DuplicateServiceCodeException catch (e) {
      await _showError('کد «${e.code}» تکراری است و همزمان برای خدمت دیگری گرفته شده؛ کد دیگری انتخاب کنید.');
    } on ServiceCategoryException catch (e) {
      await _showError(e.message);
    } catch (e) {
      await _showError('ثبت انجام نشد. دلیل فنی: $e');
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
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
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'نام خدمت')),
          const SizedBox(height: 12),
          TextField(
              controller: _codeCtrl,
              readOnly: true,
              decoration: InputDecoration(
                  labelText: 'کد خدمت',
                  errorText: _codeNotice,
                  helperText: _isEdit
                      ? 'کد خدمت قابل تغییر نیست'
                      : 'کد خودکار تعیین می‌شود؛ برای انتخاب کد آزاد روی آیکون بزن',
                  suffixIcon: _isEdit
                      ? null
                      : IconButton(
                          tooltip: 'انتخاب از کدهای آزاد',
                          icon: const Icon(Icons.auto_fix_high),
                          onPressed: _pickFreeCode))),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _categoryId,
            decoration: const InputDecoration(labelText: 'دسته‌بندی'),
            items: widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: _onCategoryChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            key: ValueKey('grp-$_categoryId-${_groups.length}-$_groupId'),
            value: _groups.any((g) => g.id == _groupId) ? _groupId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'مجموعه خدمات'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('بدون مجموعه')),
              ..._groups.map((g) =>
                  DropdownMenuItem<int?>(value: g.id, child: Text(g.active ? g.name : '${g.name} (غیرفعال)'))),
            ],
            onChanged: (v) => setState(() => _groupId = v),
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
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _voiceLabelCtrl,
                decoration: const InputDecoration(labelText: 'برچسب جستجوی صوتی (اختیاری)'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.mic_none),
              label: const Text('ضبط'),
              onPressed: _recordVoiceLabel,
            ),
          ]),
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

/// Sheet انتخاب با امکان افزودن (دکمه‌ی +) و ویرایش/حذف (نگه‌داشتن طولانی
/// روی هر آیتم). onDelete اگر null برگرداند یعنی حذف موفق بود، و اگر متن
/// برگرداند یعنی حذف انجام نشد و آن متن به کاربر نشان داده می‌شود.
/// reloadItems اگر داده شود، لیست بعد از ویرایش/حذف در همان Sheet تازه می‌شود.
class _PickerSheet extends StatefulWidget {
  final String title;
  final List<_PickerItem> items;
  final Future<int> Function(String name) onAddNew;
  final Future<void> Function(int id, String newName)? onEdit;
  final Future<String?> Function(int id)? onDelete;
  final Future<List<_PickerItem>> Function()? reloadItems;
  final String deleteTitle;
  final String deleteMessage;
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.onAddNew,
    this.onEdit,
    this.onDelete,
    this.reloadItems,
    this.deleteTitle = 'حذف',
    this.deleteMessage = 'آیا از حذف مطمئن هستید؟',
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _newCtrl = TextEditingController();
  late List<_PickerItem> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
  }

  Future<void> _refresh() async {
    final reload = widget.reloadItems;
    if (reload == null) {
      if (mounted) setState(() {});
      return;
    }
    final fresh = await reload();
    if (!mounted) return;
    setState(() => _items = fresh);
  }

  Future<void> _showItemActions(BuildContext context, _PickerItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('ویرایش'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
          if (widget.onDelete != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ]),
      ),
    );
    if (action == 'edit' && widget.onEdit != null) {
      final ctrl = TextEditingController(text: item.label);
      final newName = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('ویرایش نام'),
          content: TextField(controller: ctrl),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('ذخیره')),
          ],
        ),
      );
      if (newName != null && newName.isNotEmpty) {
        await widget.onEdit!(item.id!, newName);
        await _refresh();
      }
    } else if (action == 'delete' && widget.onDelete != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(widget.deleteTitle),
          content: Text(widget.deleteMessage),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm == true) {
        final error = await widget.onDelete!(item.id!);
        if (!context.mounted) return;
        if (error != null) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              content: Text(error),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('باشه'))],
            ),
          );
          return;
        }
        if (widget.reloadItems != null) {
          await _refresh();
        } else {
          Navigator.pop(context, null);
        }
      }
    }
  }

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
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                final canManage = item.id != null && (widget.onEdit != null || widget.onDelete != null);
                return ListTile(
                  title: Text(item.label),
                  onTap: () => Navigator.pop(context, item.id),
                  onLongPress: canManage ? () => _showItemActions(context, item) : null,
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// مدیریت دسته‌بندی‌ها: افزودن (با پیشوند کد)، تغییر نام، تعیین پیشوند، مجموعه‌های خدمات،
/// حذف/بایگانی و بازیابی. به خدمات، قیمت‌ها و فاکتورها دست نمی‌زند.
class _CategoryManagerSheet extends StatefulWidget {
  const _CategoryManagerSheet();
  @override
  State<_CategoryManagerSheet> createState() => _CategoryManagerSheetState();
}

class _CategoryManagerSheetState extends State<_CategoryManagerSheet> {
  final _repo = ServiceCategoryRepository();
  List<ServiceCategory> _active = [];
  List<ServiceCategory> _archived = [];
  Map<int, int> _counts = {};
  bool _loading = true;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final active = await _repo.getAll();
    final archived = await _repo.getArchived();
    final counts = <int, int>{};
    for (final c in active) {
      if (c.id != null) counts[c.id!] = await _repo.serviceCount(c.id!);
    }
    if (!mounted) return;
    setState(() {
      _active = active;
      _archived = archived;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _showError(Object e) async {
    final msg = e is ServiceCategoryException ? e.message : 'خطا: $e';
    if (!mounted) return;
    await showCategoryError(context, msg);
  }

  Future<String?> _askName(String title, String initial, String okLabel) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'نام دسته‌بندی')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(okLabel)),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final r = await askCategoryNameAndPrefix(context);
    if (r == null) return;
    try {
      await _repo.add(r.name, prefix: r.prefix);
      _notice = 'دسته‌بندی «${r.name}» با پیشوند ${r.prefix} اضافه شد';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  Future<void> _rename(ServiceCategory c) async {
    final name = await _askName('تغییر نام دسته‌بندی', c.name, 'ذخیره');
    if (name == null || name.isEmpty || name == c.name) return;
    try {
      await _repo.rename(c.id!, name);
      _notice = 'نام تغییر کرد. پیشوند و کدهای قبلی خدمات عوض نمی‌شوند.';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  Future<void> _editPrefix(ServiceCategory c) async {
    final p = await askCategoryPrefix(context, initial: c.codePrefix ?? '');
    if (p == null) return;
    try {
      await _repo.setPrefix(c.id!, p);
      _notice = 'پیشوند دسته‌بندی «${c.name}» ثبت شد: $p';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  /// مدیریت مجموعه‌های خدمات یک دسته (افزودن، تغییر نام، ترتیب، فعال/غیرفعال).
  Future<void> _openGroups(ServiceCategory c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupManagerSheet(category: c),
    );
  }

  Future<void> _remove(ServiceCategory c) async {
    final n = await _repo.serviceCount(c.id!);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == 0 ? 'حذف دسته‌بندی' : 'بایگانی دسته‌بندی'),
        content: Text(n == 0
            ? 'دسته‌بندی «${c.name}» هیچ خدمتی ندارد و برای همیشه حذف می‌شود. ادامه می‌دهید؟'
            : 'دسته‌بندی «${c.name}» دارای $n خدمت ثبت‌شده است (فعال یا حذف‌شده) و حذف قطعی نمی‌شود، بلکه بایگانی می‌شود.\n'
                'از فهرست‌ها و ثبت خدمت جدید پنهان می‌شود ولی خدمات، قیمت‌ها و فاکتورهای قبلی دست‌نخورده می‌مانند. '
                'هر وقت خواستید از بخش «بایگانی» بازیابی‌اش کنید. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(n == 0 ? 'حذف' : 'بایگانی', style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _repo.removeOrArchive(c.id!);
      _notice = r == CategoryRemoval.deleted ? 'دسته‌بندی حذف شد' : 'دسته‌بندی بایگانی شد';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  Future<void> _restore(ServiceCategory c) async {
    try {
      await _repo.restore(c.id!);
      _notice = 'دسته‌بندی «${c.name}» بازیابی شد';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('مدیریت دسته‌بندی‌ها', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                      icon: const Icon(Icons.add, size: 18), label: const Text('دسته‌بندی جدید'), onPressed: _add),
                ]),
                if (_notice != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(_notice!, style: const TextStyle(fontSize: 12, color: Colors.green)),
                  ),
                ],
                const Divider(),
                Expanded(
                  child: ListView(controller: scrollController, children: [
                    if (_active.isEmpty)
                      const Padding(padding: EdgeInsets.all(12), child: Text('دسته‌بندی فعالی وجود ندارد')),
                    ..._active.map((c) {
                      final n = _counts[c.id] ?? 0;
                      final hasPrefix = (c.codePrefix ?? '').trim().isNotEmpty;
                      return ListTile(
                        title: Text(c.name),
                        subtitle: Text(
                            hasPrefix ? '$n خدمت • پیشوند کد: ${c.codePrefix}' : '$n خدمت • پیشوند کد تعیین نشده',
                            style: TextStyle(fontSize: 12, color: hasPrefix ? null : Colors.red)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'rename') {
                              _rename(c);
                            } else if (v == 'prefix') {
                              _editPrefix(c);
                            } else if (v == 'groups') {
                              _openGroups(c);
                            } else {
                              _remove(c);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'rename', child: Text('تغییر نام')),
                            const PopupMenuItem(value: 'groups', child: Text('مجموعه‌های خدمات')),
                            if (!hasPrefix || n == 0)
                              PopupMenuItem(
                                  value: 'prefix', child: Text(hasPrefix ? 'تغییر پیشوند کد' : 'تعیین پیشوند کد')),
                            const PopupMenuItem(
                                value: 'remove', child: Text('حذف / بایگانی', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                    }),
                    if (_archived.isNotEmpty)
                      ExpansionTile(
                        title: Text('دسته‌های بایگانی‌شده (${_archived.length})'),
                        children: _archived
                            .map((c) => ListTile(
                                  title: Text(c.name),
                                  subtitle: Text('پیشوند کد: ${c.codePrefix ?? '—'}',
                                      style: const TextStyle(fontSize: 12)),
                                  trailing: TextButton(onPressed: () => _restore(c), child: const Text('بازیابی')),
                                ))
                            .toList(),
                      ),
                  ]),
                ),
              ]),
      ),
    );
  }
}

/// مدیریت مجموعه‌های خدمات یک دسته: افزودن، تغییر نام، جابه‌جایی ترتیب (بالا/پایین)،
/// فعال/غیرفعال و حذف (فقط مجموعه‌ی بدون خدمت). به خدمات، قیمت‌ها و فاکتورها دست نمی‌زند.
class _GroupManagerSheet extends StatefulWidget {
  final ServiceCategory category;
  const _GroupManagerSheet({required this.category});
  @override
  State<_GroupManagerSheet> createState() => _GroupManagerSheetState();
}

class _GroupManagerSheetState extends State<_GroupManagerSheet> {
  final _repo = ServiceGroupRepository();
  List<ServiceGroup> _groups = [];
  Map<int, int> _counts = {};
  bool _loading = true;
  String? _notice;

  int get _categoryId => widget.category.id!;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final groups = await _repo.getByCategory(_categoryId);
    final counts = <int, int>{};
    for (final g in groups) {
      if (g.id != null) counts[g.id!] = await _repo.serviceCount(g.id!);
    }
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _showError(Object e) async {
    final msg = e is ServiceCategoryException ? e.message : 'خطا: $e';
    if (!mounted) return;
    await showCategoryError(context, msg);
  }

  Future<String?> _askName(String title, String initial, String okLabel) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'نام مجموعه')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(okLabel)),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final name = await _askName('مجموعه‌ی جدید', '', 'افزودن');
    if (name == null) return;
    try {
      await _repo.add(_categoryId, name);
      _notice = 'مجموعه «$name» اضافه شد';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  Future<void> _rename(ServiceGroup g) async {
    final name = await _askName('تغییر نام مجموعه', g.name, 'ذخیره');
    if (name == null || name.isEmpty || name == g.name) return;
    try {
      await _repo.rename(g.id!, name);
      _notice = 'نام مجموعه تغییر کرد';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  Future<void> _move(ServiceGroup g, bool up) async {
    try {
      await _repo.move(g.id!, up: up);
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  Future<void> _toggle(ServiceGroup g) async {
    try {
      await _repo.setActive(g.id!, !g.active);
      _notice = g.active ? 'مجموعه «${g.name}» غیرفعال شد' : 'مجموعه «${g.name}» فعال شد';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  Future<void> _remove(ServiceGroup g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف مجموعه'),
        content: Text('مجموعه «${g.name}» هیچ خدمتی ندارد و برای همیشه حذف می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _repo.removeOrDeactivate(g.id!);
      _notice = r == GroupRemoval.deleted ? 'مجموعه حذف شد' : 'مجموعه خدمت دارد و فقط غیرفعال شد';
    } catch (e) {
      await _showError(e);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(
                    child: Text('مجموعه‌های «${widget.category.name}»',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  TextButton.icon(
                      icon: const Icon(Icons.add, size: 18), label: const Text('مجموعه جدید'), onPressed: _add),
                ]),
                if (_notice != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(_notice!, style: const TextStyle(fontSize: 12, color: Colors.green)),
                  ),
                ],
                const Divider(),
                Expanded(
                  child: ListView(controller: scrollController, children: [
                    if (_groups.isEmpty)
                      const Padding(padding: EdgeInsets.all(12), child: Text('هنوز مجموعه‌ای ثبت نشده')),
                    ..._groups.asMap().entries.map((e) {
                      final i = e.key;
                      final g = e.value;
                      final n = _counts[g.id] ?? 0;
                      return ListTile(
                        title: Text(g.active ? g.name : '${g.name} (غیرفعال)',
                            style: TextStyle(color: g.active ? null : Colors.grey)),
                        subtitle: Text('$n خدمت', style: const TextStyle(fontSize: 12)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'بالا',
                            icon: const Icon(Icons.arrow_upward, size: 20),
                            onPressed: i == 0 ? null : () => _move(g, true),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'پایین',
                            icon: const Icon(Icons.arrow_downward, size: 20),
                            onPressed: i == _groups.length - 1 ? null : () => _move(g, false),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'rename') {
                                _rename(g);
                              } else if (v == 'toggle') {
                                _toggle(g);
                              } else {
                                _remove(g);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'rename', child: Text('تغییر نام')),
                              PopupMenuItem(value: 'toggle', child: Text(g.active ? 'غیرفعال کردن' : 'فعال کردن')),
                              if (n == 0)
                                const PopupMenuItem(
                                    value: 'remove', child: Text('حذف', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        ]),
                      );
                    }),
                  ]),
                ),
              ]),
      ),
    );
  }
}
