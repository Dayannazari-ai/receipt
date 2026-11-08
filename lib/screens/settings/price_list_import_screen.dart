import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/service.dart';
import '../../repositories/service_repository.dart';
import '../../services/price_list_import_service.dart';
import '../services/category_prefix_dialog.dart';
import 'service_group_assign_screen.dart';

String _fmtPrice(num p) => p == p.roundToDouble() ? p.toInt().toString() : p.toString();

class PriceListImportScreen extends StatefulWidget {
  const PriceListImportScreen({super.key});
  @override
  State<PriceListImportScreen> createState() => _PriceListImportScreenState();
}

class _PriceListImportScreenState extends State<PriceListImportScreen> {
  final _importService = PriceListImportService();
  final _categoryRepo = ServiceCategoryRepository();
  final _pathCtrl = TextEditingController();

  List<ServiceCategory> _categories = [];
  int? _selectedCategoryId;
  ImportPreview? _pv;
  GroupImportChoice? _groupChoice; // null = هنوز انتخاب نشده
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await _categoryRepo.getAll();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _selectedCategoryId = cats.isNotEmpty ? cats.first.id : null;
    });
  }

  Future<void> _addCategory() async {
    final r = await askCategoryNameAndPrefix(context);
    if (r == null) return;
    try {
      final id = await _categoryRepo.add(r.name, prefix: r.prefix);
      await _loadCategories();
      if (mounted) {
        setState(() {
          _selectedCategoryId = id;
          _pv = null;
          _groupChoice = null;
        });
      }
    } on ServiceCategoryException catch (e) {
      if (mounted) await showCategoryError(context, e.message);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pathCtrl.text = result.files.single.path!;
        _pv = null;
        _groupChoice = null;
        _error = null;
      });
    }
  }

  Future<void> _doPreview() async {
    setState(() {
      _error = null;
      _pv = null;
      _groupChoice = null;
      _busy = true;
    });
    try {
      final pv = await _importService.analyzeFile(_pathCtrl.text.trim(), categoryId: _selectedCategoryId);
      if (mounted) setState(() => _pv = pv);
    } on ImportStructureException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا در خواندن فایل: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canImport {
    final pv = _pv;
    if (pv == null || _busy || _selectedCategoryId == null) return false;
    if (pv.inactiveGroupCount > 0) return false;
    if (pv.newGroupCount > 0 && _groupChoice == null) return false;
    return true;
  }

  Future<void> _confirmImport() async {
    if (_selectedCategoryId == null || _pv == null) return;
    setState(() => _busy = true);
    try {
      final result = await _importService.importFromFile(
        path: _pathCtrl.text.trim(),
        categoryId: _selectedCategoryId!,
        groupChoice: _groupChoice,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${result.services} خدمت، ${result.brands} برند جدید و ${result.groups} مجموعه‌ی جدید وارد شد')));
        Navigator.pop(context);
      }
    } on ImportStructureException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا در وارد کردن: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _noteBox(Color color, List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  String _statusLabel(String s) => s == 'exists' ? 'موجود' : (s == 'inactive' ? 'غیرفعال' : 'جدید');
  Color _statusColor(String s) => s == 'exists' ? Colors.green : (s == 'inactive' ? Colors.red : Colors.orange);

  @override
  Widget build(BuildContext context) {
    final pv = _pv;
    return Scaffold(
      appBar: AppBar(title: const Text('وارد کردن نرخ‌نامه')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'دو ساختار پشتیبانی می‌شود و از روی سرستون‌ها تشخیص داده می‌شود:\n'
            '۱) فایل عریض: برندها در ستون‌ها و خدمات در سطرها، با سرستون نام خدمت شامل کلمه‌ی «خدمات».\n'
            '۲) فایل طولی: هر ردیف یک خدمت برای یک برند و مدل، با سرستون‌های «نام خدمت»، «برند خودرو»، «مدل خودرو»، «قیمت» '
            'و اختیاری «برچسب جستجوی صوتی» و «مجموعه». ستون‌های کد خدمت و دسته‌بندی نادیده گرفته می‌شوند و کد خودکار ساخته می‌شود.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _pathCtrl, decoration: const InputDecoration(labelText: 'فایل انتخاب‌شده'), readOnly: true),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
              icon: const Icon(Icons.folder_open), label: const Text('انتخاب فایل'), onPressed: _pickFile),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(labelText: 'دسته‌بندی مقصد'),
              items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() {
                _selectedCategoryId = v;
                _pv = null;
                _groupChoice = null;
              }),
            ),
          ),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _addCategory),
        ]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('انتساب مجموعه به خدمات موجود'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ServiceGroupAssignScreen())),
          ),
        ),
        if (_categories.isEmpty) ...[
          const SizedBox(height: 8),
          const Text('هیچ دسته‌بندی فعالی وجود ندارد. با دکمه‌ی + یک دسته‌بندی بسازید؛ تا آن موقع وارد کردن نرخ‌نامه ممکن نیست.',
              style: TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy || _pathCtrl.text.isEmpty ? null : _doPreview,
          child: _busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('پیش‌نمایش فایل'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        if (pv != null) ...[
          const SizedBox(height: 20),
          _noteBox(Colors.green.shade50, [
            Text('ساختار فایل: ${pv.modeLabel}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('تعداد کل ردیف‌های معتبر: ${pv.total}'),
            if (pv.ignoredColumns.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('ستون‌های نادیده‌گرفته‌شده: ${pv.ignoredColumns.join('، ')}',
                  style: const TextStyle(fontSize: 12)),
            ],
          ]),
          if (pv.newBrands.isNotEmpty)
            _noteBox(Colors.orange.shade50, [
              Text('برندهای جدید که ساخته می‌شوند (${pv.newBrands.length}):',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(pv.newBrands.join('، '), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              const Text('اگر این برند قبلاً با نام دیگری در برنامه هست، نام را در فایل اصلاح کنید و دوباره پیش‌نمایش بزنید.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          if (pv.newModels.isNotEmpty)
            _noteBox(Colors.orange.shade50, [
              Text('مدل‌های جدید که ساخته می‌شوند (${pv.newModels.length}):',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  pv.newModels.take(12).join('، ') +
                      (pv.newModels.length > 12 ? ' و ${pv.newModels.length - 12} مورد دیگر' : ''),
                  style: const TextStyle(fontSize: 12)),
            ]),
          if (pv.hasGroupColumn) ...[
            const Text('مجموعه‌های فایل:', style: TextStyle(fontWeight: FontWeight.bold)),
            if (pv.rowsWithoutGroup > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('ردیف‌های بدون مجموعه: ${pv.rowsWithoutGroup} (بدون مجموعه وارد می‌شوند)',
                    style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 4),
            for (final g in pv.groups)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(g.name),
                subtitle: Text('${g.rows} ردیف در فایل', style: const TextStyle(fontSize: 12)),
                trailing: Text(_statusLabel(g.status),
                    style: TextStyle(color: _statusColor(g.status), fontWeight: FontWeight.bold)),
              ),
            if (pv.inactiveGroupCount > 0)
              _noteBox(Colors.red.shade50, [
                const Text('مجموعه‌ی غیرفعال در فایل هست و ورود ممکن نیست.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 4),
                const Text('ابتدا آن را فعال کنید یا نام مجموعه را در فایل عوض کنید و دوباره پیش‌نمایش بزنید.',
                    style: TextStyle(fontSize: 12)),
              ]),
            if (pv.newGroupCount > 0)
              _noteBox(Colors.orange.shade50, [
                Text('${pv.newGroupCount} مجموعه در این دسته وجود ندارد. قبل از ادامه یکی را انتخاب کنید:',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('ساخت مجموعه‌های جدید'),
                    selected: _groupChoice == GroupImportChoice.create,
                    onSelected: (_) => setState(() => _groupChoice = GroupImportChoice.create),
                  ),
                  ChoiceChip(
                    label: const Text('ورود بدون مجموعه'),
                    selected: _groupChoice == GroupImportChoice.skip,
                    onSelected: (_) => setState(() => _groupChoice = GroupImportChoice.skip),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text('«ورود بدون مجموعه» فقط برای ردیف‌های مجموعه‌ی جدید است؛ ردیف‌های مجموعه‌ی موجود به مجموعه‌شان وصل می‌شوند.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
          ],
          const SizedBox(height: 4),
          Text('نمونه‌ی ${pv.sample.length} ردیف اول:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...pv.sample.map((r) {
            final lines = <String>['برند: ${r['brand']}'];
            if (r['model'] != null) lines.add('مدل: ${r['model']}');
            if (r['group'] != null) lines.add('مجموعه: ${r['group']}');
            if (r['voice'] != null) lines.add('برچسب صوتی: ${r['voice']}');
            return Card(
              child: ListTile(
                isThreeLine: lines.length > 2,
                title: Text(r['name'] as String),
                subtitle: Text(lines.join('\n'), style: const TextStyle(fontSize: 12)),
                trailing: Text(_fmtPrice(r['price'] as num)),
              ),
            );
          }),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _canImport ? _confirmImport : null,
            child: Text('تأیید و وارد کردن نهایی (${pv.total} ردیف)'),
          ),
        ],
      ]),
    );
  }
}
