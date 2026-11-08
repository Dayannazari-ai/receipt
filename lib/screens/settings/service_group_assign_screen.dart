import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/service.dart';
import '../../repositories/service_repository.dart';
import '../../services/price_list_import_service.dart' show ImportStructureException;
import '../../services/service_group_assign_service.dart';

class ServiceGroupAssignScreen extends StatefulWidget {
  const ServiceGroupAssignScreen({super.key});
  @override
  State<ServiceGroupAssignScreen> createState() => _ServiceGroupAssignScreenState();
}

class _ServiceGroupAssignScreenState extends State<ServiceGroupAssignScreen> {
  final _service = ServiceGroupAssignService();
  final _categoryRepo = ServiceCategoryRepository();
  final _pathCtrl = TextEditingController();

  List<ServiceCategory> _categories = [];
  int? _categoryId;
  AssignPreview? _pv;
  bool? _createMissing; // null = هنوز انتخاب نشده
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
      _categoryId = cats.isNotEmpty ? cats.first.id : null;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pathCtrl.text = result.files.single.path!;
        _pv = null;
        _createMissing = null;
        _error = null;
      });
    }
  }

  String _msg(Object e) {
    if (e is ImportStructureException) return e.message;
    if (e is ServiceCategoryException) return e.message;
    return 'خطا: $e';
  }

  Future<void> _analyze() async {
    if (_categoryId == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _pv = null;
      _createMissing = null;
    });
    try {
      final pv = await _service.analyze(_pathCtrl.text.trim(), _categoryId!);
      if (mounted) setState(() => _pv = pv);
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _effectiveCount {
    final pv = _pv;
    if (pv == null) return 0;
    return pv.toAssignExisting + (_createMissing == true ? pv.toAssignNew : 0);
  }

  bool get _canApply {
    final pv = _pv;
    if (pv == null || _busy) return false;
    if (pv.newGroupCount > 0 && _createMissing == null) return false;
    return _effectiveCount > 0;
  }

  Future<void> _apply() async {
    final pv = _pv;
    if (pv == null || _categoryId == null) return;
    final create = _createMissing == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأیید انتساب'),
        content: Text('$_effectiveCount خدمت به مجموعه‌ها وصل می‌شود'
            '${create && pv.newGroupCount > 0 ? ' و ${pv.newGroupCount} مجموعه‌ی جدید ساخته می‌شود' : ''}.\n'
            'قیمت، کد، برند و مدل، برچسب صوتی و فاکتورها تغییر نمی‌کنند و مجموعه‌ی قبلیِ هیچ خدمتی بازنویسی نمی‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ادامه')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _service.apply(
          path: _pathCtrl.text.trim(), categoryId: _categoryId!, createMissing: create);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('انجام شد'),
          content: Text('${r.assigned} خدمت به مجموعه وصل شد و ${r.created} مجموعه‌ی جدید ساخته شد.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه'))],
        ),
      );
      if (mounted) {
        setState(() {
          _pv = null;
          _createMissing = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'انتساب انجام نشد و هیچ تغییری اعمال نشد. ${_msg(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _box(Color color, List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _sample(String title, int count, List<String> sample) {
    if (count == 0) return const SizedBox.shrink();
    return _box(Colors.orange.shade50, [
      Text('$title: $count', style: const TextStyle(fontWeight: FontWeight.bold)),
      for (final s in sample) Text('• $s', style: const TextStyle(fontSize: 12)),
      if (count > sample.length)
        Text('و ${count - sample.length} مورد دیگر', style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  String _statusLabel(String s) => s == 'exists' ? 'موجود' : (s == 'inactive' ? 'غیرفعال' : 'جدید');
  Color _statusColor(String s) => s == 'exists' ? Colors.green : (s == 'inactive' ? Colors.red : Colors.orange);

  @override
  Widget build(BuildContext context) {
    final pv = _pv;
    return Scaffold(
      appBar: AppBar(title: const Text('انتساب مجموعه به خدمات موجود')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'فایل نرخ‌نامه‌ی طولی با سرستون‌های «نام خدمت»، «برند خودرو»، «مدل خودرو» و «مجموعه» را انتخاب کنید. '
              'هر ردیف با خدمت هم‌نام، هم‌برند و هم‌مدل در دسته‌ی انتخاب‌شده تطبیق داده می‌شود و فقط مجموعه‌ی آن خدمت '
              'ثبت می‌شود. قیمت و کد و بقیه‌ی اطلاعات تغییر نمی‌کند و خدمتی که از قبل مجموعه دارد بازنویسی نمی‌شود.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                  controller: _pathCtrl, readOnly: true, decoration: const InputDecoration(labelText: 'فایل انتخاب‌شده')),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
                icon: const Icon(Icons.folder_open), label: const Text('انتخاب فایل'), onPressed: _pickFile),
          ]),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _categoryId,
            decoration: const InputDecoration(labelText: 'دسته‌بندی خدمات'),
            items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: (v) => setState(() {
              _categoryId = v;
              _pv = null;
              _createMissing = null;
            }),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy || _pathCtrl.text.isEmpty || _categoryId == null ? null : _analyze,
            child: _busy
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('تحلیل فایل'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (pv != null) ...[
            const SizedBox(height: 16),
            _box(Colors.green.shade50, [
              Text('ردیف‌های فایل: ${pv.totalRows}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('وصل‌شدنی به مجموعه‌های موجود: ${pv.toAssignExisting}'),
              Text('وصل‌شدنی فقط با ساخت مجموعه‌ی جدید: ${pv.toAssignNew}'),
              Text('از قبل در همین مجموعه: ${pv.alreadySame}'),
              if (pv.inactiveGroupRows > 0) Text('رد می‌شود (مجموعه‌ی غیرفعال): ${pv.inactiveGroupRows}'),
            ]),
            _sample('خدمت با مجموعه‌ی دیگر (بازنویسی نمی‌شود)', pv.otherGroup, pv.otherGroupSample),
            _sample('پیدا نشد در دیتابیس', pv.unmatched, pv.unmatchedSample),
            _sample('چند خدمت با یک ردیف تطبیق دارند (رد می‌شود)', pv.ambiguous, pv.ambiguousSample),
            const Text('مجموعه‌های فایل:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final g in pv.groups)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(g.name),
                subtitle: Text('${g.rows} ردیف در فایل • ${g.toAssign} انتساب', style: const TextStyle(fontSize: 12)),
                trailing: Text(_statusLabel(g.status),
                    style: TextStyle(color: _statusColor(g.status), fontWeight: FontWeight.bold)),
              ),
            if (pv.newGroupCount > 0) ...[
              const SizedBox(height: 8),
              _box(Colors.orange.shade50, [
                Text('${pv.newGroupCount} مجموعه در این دسته وجود ندارد. قبل از ادامه یکی را انتخاب کنید:',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('ساخت مجموعه‌های جدید و انتساب'),
                    selected: _createMissing == true,
                    onSelected: (_) => setState(() => _createMissing = true),
                  ),
                  ChoiceChip(
                    label: const Text('فقط مجموعه‌های موجود'),
                    selected: _createMissing == false,
                    onSelected: (_) => setState(() => _createMissing = false),
                  ),
                ]),
              ]),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _canApply ? _apply : null,
              child: Text('انجام انتساب ($_effectiveCount خدمت)'),
            ),
          ],
        ]),
      ),
    );
  }
}
