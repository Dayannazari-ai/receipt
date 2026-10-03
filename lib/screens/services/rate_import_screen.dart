import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/rate_import_models.dart';
import '../../models/service.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/vehicle_reference_repository.dart';
import '../../services/rate_import/rate_table_mapper.dart';
import '../../services/rate_import/rate_table_source.dart';
import '../../utils/rate_text_utils.dart';
import 'rate_import_review_screen.dart';

class RateImportScreen extends StatefulWidget {
  const RateImportScreen({super.key});
  @override
  State<RateImportScreen> createState() => _RateImportScreenState();
}

class _SheetCfg {
  _SheetCfg(this.table, this.mapping, this.enabled);
  final RawTable table;
  SheetMapping mapping;
  bool enabled;
}

class _RateImportScreenState extends State<RateImportScreen> {
  final _categoryRepo = ServiceCategoryRepository();
  final _vehicleRepo = VehicleReferenceRepository();
  final RateTableSource _source = ExcelRateTableSource();

  List<ServiceCategory> _categories = [];
  int? _categoryId;
  String? _fileName;
  List<_SheetCfg> _sheets = [];
  RateTableMapper _mapper = RateTableMapper();
  bool _busy = false;
  String? _status;
  String? _error;
  int _idCounter = 0;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    final cats = await _categoryRepo.getAll();
    final brands = await _vehicleRepo.getAllBrands();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _categoryId = cats.isNotEmpty ? cats.first.id : null;
      _mapper = RateTableMapper(knownBrandNorms: brands.map((b) => RateText.normalize(b.name)).toSet());
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
      final id = await _categoryRepo.insert(ServiceCategory(name: name));
      final cats = await _categoryRepo.getAll();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoryId = id;
      });
    }
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() {
      _busy = true;
      _status = 'در حال خواندن فایل...';
      _error = null;
      _sheets = [];
      _fileName = path.split(RegExp(r'[\\/]')).last;
    });
    try {
      final tables = await _source.read(path);
      final usable = tables.where((t) => t.rows.length >= 2).toList();
      if (!mounted) return;
      if (usable.isEmpty) {
        setState(() => _error = 'فایل خالی است یا شیتی با داده پیدا نشد.');
        return;
      }
      final cfgs = usable.map((t) {
        final m = _mapper.guessMapping(t);
        return _SheetCfg(t, m, m.hasTitle && m.hasPrice);
      }).toList();
      setState(() => _sheets = cfgs);
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا در خواندن فایل: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _buildPreview() async {
    final enabled = _sheets.where((s) => s.enabled).toList();
    if (enabled.isEmpty) {
      setState(() => _error = 'حداقل یک شیت را انتخاب کنید.');
      return;
    }
    for (final s in enabled) {
      if (!s.mapping.hasTitle || !s.mapping.hasPrice) {
        setState(() => _error =
            'در شیت «${s.table.name}» باید ستون «عنوان خدمت» و حداقل یک ستون قیمت مشخص شود.');
        return;
      }
    }
    if (_categoryId == null) {
      setState(() => _error = 'ابتدا یک دسته‌بندی مقصد انتخاب یا ایجاد کنید.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'در حال استخراج ردیف‌ها...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final rows = <ExtractedRateRow>[];
    var noTitle = 0;
    var noPrice = 0;
    for (final s in enabled) {
      final r = _mapper.extract(s.table, s.mapping, nextId: () => ++_idCounter);
      rows.addAll(r.rows);
      noTitle += r.skippedNoTitle;
      noPrice += r.skippedNoPrice;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = null;
    });
    if (rows.isEmpty) {
      setState(() => _error = 'هیچ ردیفی با عنوان و قیمت پیدا نشد. نقش ستون‌ها را بررسی کنید.');
      return;
    }
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RateImportReviewScreen(
          rows: rows,
          defaultCategoryId: _categoryId!,
          skippedNoTitle: noTitle,
          skippedNoPrice: noPrice,
          fileName: _fileName ?? '',
        ),
      ),
    );
    if (done == true && mounted) Navigator.pop(context, true);
  }

  String _sample(_SheetCfg s, ColumnConfig c) {
    final r = s.mapping.headerRow + 1;
    if (r >= s.table.rows.length) return '';
    final row = s.table.rows[r];
    return c.index < row.length ? row[c.index] : '';
  }

  Widget _sheetTile(_SheetCfg s) {
    final m = s.mapping;
    final maxHeader = s.table.rows.length < 15 ? s.table.rows.length : 15;
    return Card(
      child: ExpansionTile(
        leading: Checkbox(value: s.enabled, onChanged: (v) => setState(() => s.enabled = v ?? false)),
        title: Text(s.table.name),
        subtitle: Text('${s.table.rows.length} ردیف'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            const Text('سطر سرستون:'),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: m.headerRow + 1,
              items: [for (var i = 1; i <= maxHeader; i++) DropdownMenuItem(value: i, child: Text('$i'))],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  final fd = m.fillDown;
                  s.mapping = _mapper.guessMapping(s.table, headerRow: v - 1)..fillDown = fd;
                });
              },
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('پر کردن سلول‌های خالی برند/مدل/دسته/تیپ/سال از ردیف بالا',
                style: TextStyle(fontSize: 13)),
            subtitle: const Text('برای سلول‌های ادغام‌شده', style: TextStyle(fontSize: 11)),
            value: m.fillDown,
            onChanged: (v) => setState(() => m.fillDown = v),
          ),
          const Divider(),
          ...m.columns.map((c) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(c.header.isEmpty ? 'ستون ${c.index + 1}' : c.header),
                subtitle: Text('نمونه: ${_sample(s, c)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: SizedBox(
                  width: 160,
                  child: DropdownButton<ColumnRole>(
                    isExpanded: true,
                    isDense: true,
                    value: c.role,
                    items: ColumnRole.values
                        .map((r) => DropdownMenuItem(
                            value: r, child: Text(r.label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => c.role = v ?? ColumnRole.ignore),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ورود نرخ از فایل')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'فایل Excel (xlsx) را انتخاب کنید. نقش هر ستون به‌صورت خودکار حدس زده می‌شود و می‌توانید اصلاحش کنید. '
            'هیچ نرخی بدون بررسی و تأیید نهایی شما ثبت نمی‌شود.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.table_chart_outlined),
          label: Text(_fileName == null ? 'انتخاب فایل Excel' : 'فایل: $_fileName'),
          onPressed: _busy ? null : _pickFile,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'دسته‌بندی پیش‌فرض برای خدمات جدید'),
              items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _addCategory),
        ]),
        if (_busy) ...[
          const SizedBox(height: 16),
          Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(_status ?? 'در حال پردازش...'),
          ]),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        if (_sheets.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('شیت‌ها و ستون‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._sheets.map(_sheetTile),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _buildPreview,
            child: const Text('ساخت پیش‌نمایش و بررسی'),
          ),
        ],
      ]),
    );
  }
}
