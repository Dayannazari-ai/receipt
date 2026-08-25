import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/service.dart';
import '../../repositories/service_repository.dart';
import '../../services/price_list_import_service.dart';

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
  List<Map<String, dynamic>>? _preview;
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
      await _loadCategories();
      setState(() => _selectedCategoryId = id);
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
        _preview = null;
        _error = null;
      });
    }
  }

  Future<void> _doPreview() async {
    setState(() {
      _error = null;
      _preview = null;
      _busy = true;
    });
    try {
      final preview = await _importService.previewFile(_pathCtrl.text.trim());
      if (preview.isEmpty) {
        setState(() => _error = 'هیچ ردیف معتبری در فایل پیدا نشد. فرمت ستون‌ها را بررسی کنید.');
      } else {
        setState(() => _preview = preview);
      }
    } catch (e) {
      setState(() => _error = 'خطا در خواندن فایل: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _confirmImport() async {
    if (_selectedCategoryId == null) return;
    setState(() => _busy = true);
    try {
      final result = await _importService.importFromFile(
        path: _pathCtrl.text.trim(),
        categoryId: _selectedCategoryId!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${result.services} خدمت و ${result.brands} برند جدید وارد شد')));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = 'خطا در وارد کردن: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('وارد کردن نرخ‌نامه')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'فرمت هر ردیف: نام خدمت | برند (اختیاری) | مدل (اختیاری) | قیمت. ردیف اول (سرستون) نادیده گرفته می‌شود.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(controller: _pathCtrl, decoration: const InputDecoration(labelText: 'فایل انتخاب‌شده'), readOnly: true),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(icon: const Icon(Icons.folder_open), label: const Text('انتخاب فایل'), onPressed: _pickFile),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(labelText: 'دسته‌بندی مقصد'),
              items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _selectedCategoryId = v),
            ),
          ),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _addCategory),
        ]),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _doPreview,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('پیش‌نمایش فایل'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        if (_preview != null) ...[
          const SizedBox(height: 20),
          Text('پیش‌نمایش (${_preview!.length} ردیف اول):', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._preview!.map((r) => Card(
                child: ListTile(
                  title: Text(r['name'] as String),
                  subtitle: Text('برند: ${r['brand'] ?? 'همه'} - مدل: ${r['model'] ?? 'همه'}'),
                  trailing: Text('${r['price']}'),
                ),
              )),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy || _selectedCategoryId == null ? null : _confirmImport,
            child: const Text('تأیید و وارد کردن نهایی'),
          ),
        ],
      ]),
    );
  }
}
