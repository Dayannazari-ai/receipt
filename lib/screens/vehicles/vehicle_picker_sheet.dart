import 'package:flutter/material.dart';
import '../../models/vehicle.dart';
import '../../models/vehicle_reference.dart';
import '../../repositories/vehicle_repository.dart';
import '../../repositories/vehicle_reference_repository.dart';

/// انتخاب یا افزودن خودرو برای یک مشتری مشخص.
///
/// فقط خودروهای همان مشتری نمایش داده می‌شوند؛ پس امکان انتخاب اشتباه
/// خودروی مشتری دیگر وجود ندارد. اگر مشتری هنوز ذخیره نشده باشد
/// ([customerId] برابر null)، این Sheet نباید باز شود؛ فراخوانی‌کننده باید
/// قبلاً این شرط را بررسی کند.
///
/// خروجی: [VehiclePickerResult] با خودروی انتخاب‌شده، یا با vehicle=null
/// اگر کاربر «بدون خودرو» را بزند. بستن Sheet بدون انتخاب، null برمی‌گرداند.
class VehiclePickerResult {
  final Vehicle? vehicle;
  const VehiclePickerResult(this.vehicle);
}

class VehiclePickerSheet extends StatefulWidget {
  final int customerId;
  const VehiclePickerSheet({super.key, required this.customerId});

  @override
  State<VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<VehiclePickerSheet> {
  final _vehicleRepo = VehicleRepository();
  final _refRepo = VehicleReferenceRepository();
  List<Vehicle> _vehicles = [];
  Map<int, String> _brandNames = {};
  Map<int, String> _modelNames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vehicles = await _vehicleRepo.getByCustomer(widget.customerId);
    // includeDeleted: نام برندِ حذف‌منطقی‌شده هم برای خودروهای قدیمی نمایش داده شود.
    final brands = await _refRepo.getAllBrands(includeDeleted: true);
    final brandNames = {for (final b in brands) b.id!: b.name};
    final Map<int, String> modelNames = {};
    for (final b in brands) {
      final ms = await _refRepo.getModelsByBrand(b.id!);
      for (final m in ms) {
        modelNames[m.id!] = m.name;
      }
    }
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      _brandNames = brandNames;
      _modelNames = modelNames;
      _loading = false;
    });
  }

  String _label(Vehicle v) {
    final parts = <String>[];
    if (v.brandId != null) parts.add(_brandNames[v.brandId] ?? '');
    if (v.modelId != null) parts.add(_modelNames[v.modelId] ?? '');
    final text = parts.where((p) => p.isNotEmpty).join(' ');
    return text.isEmpty ? 'خودروی بدون مشخصات' : text;
  }

  Future<void> _addOrEdit({Vehicle? vehicle}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VehicleFormSheet(customerId: widget.customerId, vehicle: vehicle),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Vehicle v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف خودرو'),
        content: const Text('آیا از حذف این خودرو مطمئن هستید؟ فاکتورهای قبلی این خودرو دست‌نخورده می‌مانند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _vehicleRepo.softDelete(v.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text('انتخاب خودرو', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('افزودن خودرو'),
                onPressed: () => _addOrEdit(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.do_not_disturb_alt_outlined),
                label: const Text('بدون خودرو'),
                onPressed: () => Navigator.of(context).pop(const VehiclePickerResult(null)),
              ),
            ),
          ]),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _vehicles.isEmpty
                    ? const Center(child: Text('این مشتری خودرویی ثبت‌شده ندارد'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _vehicles.length,
                        itemBuilder: (context, i) {
                          final v = _vehicles[i];
                          final notes = (v.notes ?? '').trim();
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.directions_car_outlined)),
                            title: Text(_label(v)),
                            subtitle: notes.isEmpty ? null : Text(notes, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                                onPressed: () => _addOrEdit(vehicle: v),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _delete(v),
                              ),
                            ]),
                            onTap: () => Navigator.of(context).pop(VehiclePickerResult(v)),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

/// فرم افزودن/ویرایش یک خودرو برای مشتری مشخص.
/// فیلد پلاک از این فرم حذف شده است. مقدار plate_number خودروهای قدیمی در
/// دیتابیس دست‌نخورده می‌ماند (copyWith آن را حفظ می‌کند).
class _VehicleFormSheet extends StatefulWidget {
  final int customerId;
  final Vehicle? vehicle;
  const _VehicleFormSheet({required this.customerId, this.vehicle});

  @override
  State<_VehicleFormSheet> createState() => _VehicleFormSheetState();
}

class _VehicleFormSheetState extends State<_VehicleFormSheet> {
  final _vehicleRepo = VehicleRepository();
  final _refRepo = VehicleReferenceRepository();
  late final TextEditingController _notesCtrl;
  int? _brandId;
  int? _modelId;
  List<VehicleBrand> _brands = [];
  List<VehicleModel> _models = [];
  bool _saving = false;

  bool get _isEdit => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _notesCtrl = TextEditingController(text: v?.notes ?? '');
    _brandId = v?.brandId;
    _modelId = v?.modelId;
    _loadBrands();
  }

  Future<void> _loadBrands() async {
    final brands = await _refRepo.getAllBrands();
    if (!mounted) return;
    setState(() => _brands = brands);
    if (_brandId != null) _loadModels(_brandId!);
  }

  Future<void> _loadModels(int brandId) async {
    final models = await _refRepo.getModelsByBrand(brandId);
    if (!mounted) return;
    setState(() => _models = models);
  }

  // ---------------- مدیریت برندها ----------------
  Future<void> _manageBrands() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReferenceManagerSheet(
        title: 'مدیریت برندها',
        deleteHint:
            'اگر این برند در مدل‌ها، خدمات یا خودروها استفاده شده باشد، فقط از لیست‌ها مخفی می‌شود و سوابق قبلی حفظ می‌ماند.',
        loadItems: () async =>
            (await _refRepo.getAllBrands()).map((b) => _RefItem(b.id!, b.name)).toList(),
        onAdd: (name) async {
          if (await _refRepo.brandNameExists(name)) return 'این برند قبلاً ثبت شده است';
          await _refRepo.insertBrand(name);
          return null;
        },
        onEdit: (id, name) async {
          if (await _refRepo.brandNameExists(name, excludeId: id)) return 'این برند قبلاً ثبت شده است';
          await _refRepo.updateBrand(id, name);
          return null;
        },
        onDelete: (id) async {
          await _refRepo.deleteBrand(id);
          return null;
        },
      ),
    );
    await _refreshAfterBrandManage();
  }

  Future<void> _refreshAfterBrandManage() async {
    final brands = await _refRepo.getAllBrands();
    if (!mounted) return;
    final stillExists = _brandId != null && brands.any((b) => b.id == _brandId);
    setState(() {
      _brands = brands;
      if (_brandId != null && !stillExists) {
        // برندِ انتخاب‌شده همین الان حذف شده؛ انتخاب پاک می‌شود.
        _brandId = null;
        _modelId = null;
        _models = [];
      }
    });
    if (_brandId != null) await _loadModels(_brandId!);
  }

  // ---------------- مدیریت مدل‌ها (وابسته به برند انتخاب‌شده) ----------------
  Future<void> _manageModels() async {
    final brandId = _brandId;
    if (brandId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReferenceManagerSheet(
        title: 'مدیریت مدل‌ها',
        deleteHint: 'مدلی که در خدمات یا خودروها استفاده شده باشد قابل حذف نیست (نامش را می‌توانید ویرایش کنید).',
        loadItems: () async =>
            (await _refRepo.getModelsByBrand(brandId)).map((m) => _RefItem(m.id!, m.name)).toList(),
        onAdd: (name) async {
          if (await _refRepo.modelNameExists(brandId, name)) return 'این مدل در این برند قبلاً ثبت شده است';
          await _refRepo.insertModel(brandId, name);
          return null;
        },
        onEdit: (id, name) async {
          if (await _refRepo.modelNameExists(brandId, name, excludeId: id)) {
            return 'این مدل در این برند قبلاً ثبت شده است';
          }
          await _refRepo.updateModel(id, name);
          return null;
        },
        onDelete: (id) async {
          final deleted = await _refRepo.deleteModel(id);
          return deleted ? null : 'این مدل در خدمات یا خودروها استفاده شده و قابل حذف نیست';
        },
      ),
    );
    await _loadModels(brandId);
    if (!mounted) return;
    if (_modelId != null && !_models.any((m) => m.id == _modelId)) {
      setState(() => _modelId = null);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final notes = _notesCtrl.text.trim();
      if (_isEdit) {
        await _vehicleRepo.update(widget.vehicle!.copyWith(
          brandId: _brandId,
          modelId: _modelId,
          notes: notes.isEmpty ? null : notes,
        ));
      } else {
        await _vehicleRepo.insert(Vehicle(
          customerId: widget.customerId,
          brandId: _brandId,
          modelId: _modelId,
          notes: notes.isEmpty ? null : notes,
        ));
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // اگر برند/مدلِ ذخیره‌شده‌ی یک خودروی قدیمی دیگر در لیست نیست، Dropdown
    // نباید Crash کند؛ فقط «انتخاب نشده» نمایش داده می‌شود و مقدار ذخیره‌شده
    // تا زمانی که کاربر تغییر ندهد دست‌نخورده می‌ماند.
    final brandValue = _brands.any((b) => b.id == _brandId) ? _brandId : null;
    final modelValue = _models.any((m) => m.id == _modelId) ? _modelId : null;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_isEdit ? 'ویرایش خودرو' : 'خودروی جدید',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: brandValue,
                decoration: const InputDecoration(labelText: 'برند خودرو'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('انتخاب نشده')),
                  ..._brands.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                ],
                onChanged: (v) {
                  setState(() {
                    _brandId = v;
                    _modelId = null;
                    _models = [];
                  });
                  if (v != null) _loadModels(v);
                },
              ),
            ),
            IconButton(
              tooltip: 'مدیریت برندها',
              icon: const Icon(Icons.edit_note),
              onPressed: _manageBrands,
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: modelValue,
                decoration: const InputDecoration(labelText: 'مدل خودرو'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('انتخاب نشده')),
                  ..._models.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
                ],
                onChanged: _brandId == null ? null : (v) => setState(() => _modelId = v),
              ),
            ),
            IconButton(
              tooltip: 'مدیریت مدل‌ها',
              icon: const Icon(Icons.edit_note),
              onPressed: _brandId == null ? null : _manageModels,
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
              maxLines: 2),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEdit ? 'ذخیره تغییرات' : 'ثبت خودرو'),
          ),
        ]),
      ),
    );
  }
}

// ======================= مدیریت عمومی برند/مدل =======================

class _RefItem {
  final int id;
  final String name;
  const _RefItem(this.id, this.name);
}

/// Sheet عمومی برای افزودن/ویرایش/حذف آیتم‌های یک لیست (هم برای برند، هم
/// برای مدل). هر callback یا null (موفق) یا پیام خطا برمی‌گرداند. پیام خطا
/// داخل خود Sheet نمایش داده می‌شود (SnackBar زیر Bottom Sheet پنهان می‌ماند).
class _ReferenceManagerSheet extends StatefulWidget {
  final String title;
  final String deleteHint;
  final Future<List<_RefItem>> Function() loadItems;
  final Future<String?> Function(String name) onAdd;
  final Future<String?> Function(int id, String name) onEdit;
  final Future<String?> Function(int id) onDelete;

  const _ReferenceManagerSheet({
    required this.title,
    required this.deleteHint,
    required this.loadItems,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ReferenceManagerSheet> createState() => _ReferenceManagerSheetState();
}

class _ReferenceManagerSheetState extends State<_ReferenceManagerSheet> {
  final _addCtrl = TextEditingController();
  List<_RefItem> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await widget.loadItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _run(Future<String?> Function() action, {bool clearAddField = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final err = await action();
      if (!mounted) return;
      if (err != null) {
        setState(() => _error = err);
      } else {
        if (clearAddField) _addCtrl.clear();
        await _reload();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = _addCtrl.text.trim();
    if (name.isEmpty) return;
    await _run(() => widget.onAdd(name), clearAddField: true);
  }

  Future<void> _edit(_RefItem item) async {
    final ctrl = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویرایش نام'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('ذخیره')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == item.name) return;
    await _run(() => widget.onEdit(item.id, newName));
  }

  Future<void> _delete(_RefItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف «${item.name}»'),
        content: Text(widget.deleteHint),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    await _run(() => widget.onDelete(item.id));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                decoration: const InputDecoration(hintText: 'افزودن مورد جدید...'),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
              onPressed: _busy ? null : _add,
            ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('موردی ثبت نشده است'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          return ListTile(
                            title: Text(item.name),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                                onPressed: _busy ? null : () => _edit(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: _busy ? null : () => _delete(item),
                              ),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
