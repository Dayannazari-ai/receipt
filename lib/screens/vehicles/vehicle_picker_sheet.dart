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
/// خروجی: [Vehicle] انتخاب‌شده، یا null اگر کاربر «بدون خودرو» را بزند،
/// یا Sheet را ببندد. برای تشخیص این دو حالت، مقدار بازگشتی `_NoVehicle`
/// استفاده می‌شود.
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
    final brands = await _refRepo.getAllBrands();
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
    final vehicleName = parts.where((p) => p.isNotEmpty).join(' ');
    final plate = (v.plateNumber ?? '').isEmpty ? '' : ' - ${v.plateNumber}';
    final text = '$vehicleName$plate'.trim();
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
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.directions_car_outlined)),
                            title: Text(_label(v)),
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
  late final TextEditingController _plateCtrl;
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
    _plateCtrl = TextEditingController(text: v?.plateNumber ?? '');
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final plate = _plateCtrl.text.trim();
      final notes = _notesCtrl.text.trim();
      if (_isEdit) {
        await _vehicleRepo.update(widget.vehicle!.copyWith(
          brandId: _brandId,
          modelId: _modelId,
          plateNumber: plate.isEmpty ? null : plate,
          notes: notes.isEmpty ? null : notes,
        ));
      } else {
        await _vehicleRepo.insert(Vehicle(
          customerId: widget.customerId,
          brandId: _brandId,
          modelId: _modelId,
          plateNumber: plate.isEmpty ? null : plate,
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
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_isEdit ? 'ویرایش خودرو' : 'خودروی جدید',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            value: _brandId,
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
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: _modelId,
            decoration: const InputDecoration(labelText: 'مدل خودرو'),
            items: [
              const DropdownMenuItem(value: null, child: Text('انتخاب نشده')),
              ..._models.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
            ],
            onChanged: _brandId == null ? null : (v) => setState(() => _modelId = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: _plateCtrl, decoration: const InputDecoration(labelText: 'پلاک')),
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
