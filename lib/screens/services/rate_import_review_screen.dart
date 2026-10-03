import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../models/rate_import_models.dart';
import '../../models/service.dart';
import '../../repositories/settings_repository.dart';
import '../../services/rate_import/rate_commit_service.dart';
import '../../services/rate_import/rate_matcher.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/rate_text_utils.dart';

enum _EditAction { saved, deleted }

class RateImportReviewScreen extends StatefulWidget {
  const RateImportReviewScreen({
    super.key,
    required this.rows,
    required this.defaultCategoryId,
    required this.skippedNoTitle,
    required this.skippedNoPrice,
    required this.fileName,
  });

  final List<ExtractedRateRow> rows;
  final int defaultCategoryId;
  final int skippedNoTitle;
  final int skippedNoPrice;
  final String fileName;

  @override
  State<RateImportReviewScreen> createState() => _RateImportReviewScreenState();
}

class _RateImportReviewScreenState extends State<RateImportReviewScreen> {
  late List<ExtractedRateRow> _rows;
  RateMatcher? _matcher;
  Currency _currency = Currency.toman;
  PriceField _primary = PriceField.general;
  double _factor = 1;
  RateMatchStatus? _filter;
  bool _loading = true;
  bool _committing = false;
  String? _progress;
  late int _nextId;

  @override
  void initState() {
    super.initState();
    _rows = List.of(widget.rows);
    _nextId = _rows.fold<int>(0, (m, r) => r.localId > m ? r.localId : m) + 1;
    _primary = _defaultPrimary();
    _init();
  }

  PriceField _defaultPrimary() {
    for (final f in [PriceField.general, PriceField.minApproved, PriceField.negotiated, PriceField.special]) {
      if (_rows.any((r) => r.priceFor(f) != null)) return f;
    }
    return PriceField.general;
  }

  List<PriceField> get _availableFields {
    final list = PriceField.values.where((f) => _rows.any((r) => r.priceFor(f) != null)).toList();
    return list.isEmpty ? [PriceField.general] : list;
  }

  Future<void> _init() async {
    final matcher = await RateMatcher.load();
    final settings = await SettingsRepository().getSettings();
    if (!mounted) return;
    _matcher = matcher;
    _currency = settings.currency;
    _recompute(resetApproval: true);
    setState(() => _loading = false);
  }

  bool _eligible(ExtractedRateRow r) =>
      r.status == RateMatchStatus.newService || r.status == RateMatchStatus.priceChanged;

  void _recompute({bool resetApproval = false}) {
    _matcher!.evaluateAll(_rows, _primary, _factor);
    for (final r in _rows) {
      if (!_eligible(r)) {
        r.approved = false;
      } else if (resetApproval) {
        r.approved = true;
      }
    }
    if (mounted) setState(() {});
  }

  int _count(RateMatchStatus s) => _rows.where((r) => r.status == s).length;
  int get _approvedCount => _rows.where((r) => r.approved && _eligible(r)).length;

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('خروج بدون ثبت'),
        content: const Text('هیچ نرخی ثبت نشده است. با خروج، پیش‌نمایش و ویرایش‌های شما از بین می‌رود. خارج می‌شوید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ماندن')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('خروج', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _editRow(ExtractedRateRow row) async {
    final res = await showModalBottomSheet<_EditAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RowEditSheet(row: row, matcher: _matcher!),
    );
    if (res == _EditAction.deleted) {
      setState(() => _rows.remove(row));
    } else if (res == _EditAction.saved) {
      _recompute();
      row.approved = _eligible(row);
      setState(() {});
    }
  }

  Future<void> _addRow() async {
    final row = ExtractedRateRow(localId: _nextId++, sourceLabel: 'افزوده‌شده دستی')..userConfirmed = true;
    final res = await showModalBottomSheet<_EditAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RowEditSheet(row: row, matcher: _matcher!),
    );
    if (res == _EditAction.saved) {
      _rows.add(row);
      _recompute();
      row.approved = _eligible(row);
      setState(() {});
    }
  }

  String _price(double v) => CurrencyFormatter.format(v, _currency);

  String _vehicleLabel(ExtractedRateRow r) {
    final b = r.brandText ?? '';
    final m = r.modelText ?? '';
    final v = r.vehicleText ?? '';
    if (b.isEmpty && m.isEmpty && v.isEmpty) return 'همه برندها';
    final parts = <String>[];
    if (v.isNotEmpty) parts.add(v);
    if (b.isNotEmpty) parts.add(r.newBrand ? '$b (برند جدید)' : b);
    if (m.isNotEmpty) parts.add(r.newModel ? '$m (مدل جدید)' : m);
    return parts.join(' / ');
  }

  (String, Color) _badge(RateMatchStatus s) {
    switch (s) {
      case RateMatchStatus.newService:
        return ('جدید', Colors.green);
      case RateMatchStatus.priceChanged:
        return ('تغییر قیمت', Colors.blue);
      case RateMatchStatus.unchanged:
        return ('بدون تغییر', Colors.grey);
      case RateMatchStatus.uncertain:
        return ('نیازمند بررسی', Colors.orange);
    }
  }

  Future<void> _finish() async {
    final selected = _rows.where((r) => r.approved && _eligible(r)).toList();
    if (selected.isEmpty) return;
    final newCount = selected.where((r) => r.status == RateMatchStatus.newService).length;
    final changedCount = selected.where((r) => r.status == RateMatchStatus.priceChanged).length;
    final newBrands = selected
        .where((r) => r.status == RateMatchStatus.newService && r.newBrand)
        .map((r) => RateText.normalize(r.brandText))
        .toSet()
        .length;
    final newModels = selected
        .where((r) => r.status == RateMatchStatus.newService && r.newModel)
        .map((r) => '${RateText.normalize(r.brandText)}|${RateText.normalize(r.modelText)}')
        .toSet()
        .length;
    final unchanged = _count(RateMatchStatus.unchanged);
    final uncertain = _count(RateMatchStatus.uncertain);
    final eligibleNotSelected =
        _rows.where((r) => _eligible(r) && !r.approved).length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأیید نهایی'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('قیمت اصلی: ${_primary.label}'),
            const SizedBox(height: 8),
            Text('خدمت جدید: $newCount'),
            Text('تغییر قیمت خدمت موجود: $changedCount'),
            if (newBrands > 0) Text('برند جدید: $newBrands'),
            if (newModels > 0) Text('مدل جدید: $newModels'),
            const Divider(),
            Text('ثبت نمی‌شوند: بدون تغییر $unchanged، نیازمند بررسی $uncertain، انتخاب‌نشده $eligibleNotSelected',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            const Text(
              'قیمت قبلی هر خدمت در تاریخچه‌ی قیمت می‌ماند و فاکتورهای قبلی تغییر نمی‌کنند.',
              style: TextStyle(fontSize: 12),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ثبت نهایی')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _committing = true;
      _progress = 'در حال ثبت...';
    });
    final result = await RateCommitService().commit(
      rows: selected,
      primary: _primary,
      factor: _factor,
      defaultCategoryId: widget.defaultCategoryId,
      onProgress: (d, t) {
        if (mounted) setState(() => _progress = 'در حال ثبت... $d از $t');
      },
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('نتیجه‌ی ثبت'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('خدمت جدید: ${result.added}'),
            Text('قیمت به‌روز شد: ${result.updated}'),
            if (result.skipped > 0) Text('بدون تغییر: ${result.skipped}'),
            if (result.brandsAdded > 0) Text('برند جدید: ${result.brandsAdded}'),
            if (result.modelsAdded > 0) Text('مدل جدید: ${result.modelsAdded}'),
            if (result.failures.isNotEmpty) ...[
              const Divider(),
              Text('ناموفق: ${result.failures.length}', style: const TextStyle(color: Colors.red)),
              ...result.failures.take(10).map((f) => Text(f, style: const TextStyle(fontSize: 12))),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('باشه'))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Widget _chip(String label, RateMatchStatus? s, int count) {
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: _filter == s,
      onSelected: (_) => setState(() => _filter = s),
    );
  }

  Widget _card(ExtractedRateRow r) {
    final (label, color) = _badge(r.status);
    final eligible = _eligible(r);
    final newPrice = r.effectiveNewPrice;
    return Card(
      child: InkWell(
        onTap: () => _editRow(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(
              value: r.approved,
              onChanged: eligible ? (v) => setState(() => r.approved = v ?? false) : null,
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(_vehicleLabel(r), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (newPrice != null)
                  Text(
                    r.matched != null
                        ? 'قیمت: ${_price(r.matched!.price)}  ←  ${_price(newPrice)}'
                        : 'قیمت: ${_price(newPrice)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
                ),
                ...r.issues.map((i) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('• $i', style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
                    )),
                Text(r.sourceLabel, style: const TextStyle(fontSize: 10, color: Colors.black38)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter == null ? _rows : _rows.where((r) => r.status == _filter).toList();
    final hasUnitInfo = _rows.any((r) => r.unit != null);
    final fileUnits = _rows.map((r) => r.unitLabel).whereType<String>().toSet();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _committing) return;
        final leave = await _confirmDiscard();
        if (leave && mounted) Navigator.pop(context, false);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('بررسی و تأیید نرخ‌های استخراج‌شده')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _committing
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(_progress ?? ''),
                  ]))
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<PriceField>(
                            value: _availableFields.contains(_primary) ? _primary : _availableFields.first,
                            decoration: const InputDecoration(labelText: 'قیمت اصلی (price)', isDense: true),
                            items: _availableFields
                                .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              _primary = v;
                              _recompute(resetApproval: true);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<double>(
                            value: _factor,
                            decoration: const InputDecoration(labelText: 'تبدیل واحد', isDense: true),
                            items: const [
                              DropdownMenuItem(value: 1.0, child: Text('بدون تبدیل')),
                              DropdownMenuItem(value: 0.1, child: Text('ریال ← تومان')),
                              DropdownMenuItem(value: 10.0, child: Text('تومان ← ریال')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              _factor = v;
                              _recompute(resetApproval: true);
                            },
                          ),
                        ),
                      ]),
                    ),
                    if (hasUnitInfo && _factor == 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Text(
                          'واحد تشخیص‌داده‌شده در فایل: ${fileUnits.join(' و ')}. اگر واحد قیمت‌های برنامه با فایل فرق دارد، «تبدیل واحد» را انتخاب کنید.',
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                        ),
                      ),
                    if (widget.skippedNoTitle > 0 || widget.skippedNoPrice > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Text(
                          'نادیده‌گرفته‌شده در فایل: ${widget.skippedNoPrice} ردیف بدون قیمت، ${widget.skippedNoTitle} ردیف بدون عنوان',
                          style: const TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Wrap(spacing: 6, runSpacing: 0, children: [
                        _chip('همه', null, _rows.length),
                        _chip('جدید', RateMatchStatus.newService, _count(RateMatchStatus.newService)),
                        _chip('تغییر قیمت', RateMatchStatus.priceChanged, _count(RateMatchStatus.priceChanged)),
                        _chip('بدون تغییر', RateMatchStatus.unchanged, _count(RateMatchStatus.unchanged)),
                        _chip('نیازمند بررسی', RateMatchStatus.uncertain, _count(RateMatchStatus.uncertain)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        TextButton(
                          onPressed: () => setState(() {
                            for (final r in _rows) {
                              r.approved = _eligible(r);
                            }
                          }),
                          child: const Text('انتخاب همه‌ی معتبرها'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            for (final r in _rows) {
                              r.approved = false;
                            }
                          }),
                          child: const Text('لغو انتخاب همه'),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('ردیفی برای نمایش نیست'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _card(filtered[i]),
                            ),
                    ),
                  ]),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: (_loading || _committing)
            ? null
            : FloatingActionButton.small(
                tooltip: 'افزودن ردیف',
                onPressed: _addRow,
                child: const Icon(Icons.add),
              ),
        bottomNavigationBar: (_loading || _committing)
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton(
                    onPressed: _approvedCount == 0 ? null : _finish,
                    child: Text('بررسی نهایی و ثبت ($_approvedCount ردیف)'),
                  ),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ویرایش یک ردیف
// ---------------------------------------------------------------------------

class _RowEditSheet extends StatefulWidget {
  const _RowEditSheet({required this.row, required this.matcher});
  final ExtractedRateRow row;
  final RateMatcher matcher;

  @override
  State<_RowEditSheet> createState() => _RowEditSheetState();
}

class _RowEditSheetState extends State<_RowEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _code;
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _type;
  late final TextEditingController _year;
  late final TextEditingController _notes;
  final Map<PriceField, TextEditingController> _prices = {};
  String? _categoryName;
  String? _initialCategoryName;
  String? _unit;
  bool _confirmed = false;
  bool _forceNew = false;
  int? _linkedId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _title = TextEditingController(text: r.title);
    _code = TextEditingController(text: r.code ?? '');
    _brand = TextEditingController(text: r.brandText ?? '');
    _model = TextEditingController(text: r.modelText ?? '');
    _type = TextEditingController(text: r.type ?? '');
    _year = TextEditingController(text: r.year ?? '');
    _notes = TextEditingController(text: r.notes ?? '');
    for (final f in PriceField.values) {
      final v = r.priceFor(f);
      _prices[f] = TextEditingController(text: v == null ? '' : RateText.formatNumber(v));
    }
    _initialCategoryName = widget.matcher.categoryByName(r.categoryText)?.name;
    _categoryName = _initialCategoryName;
    _unit = r.unit;
    _confirmed = r.userConfirmed;
    _forceNew = r.forceNew;
    _linkedId = r.linkedServiceId;
  }

  String? _nz(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _pickService() async {
    final s = await showDialog<ServiceItem>(
      context: context,
      builder: (_) => _ServicePickerDialog(matcher: widget.matcher),
    );
    if (s != null) {
      setState(() {
        _linkedId = s.id;
        _forceNew = false;
      });
    }
  }

  void _save() {
    final r = widget.row;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'عنوان خدمت نمی‌تواند خالی باشد.');
      return;
    }
    final parsed = <PriceField, double?>{};
    for (final f in PriceField.values) {
      final text = _prices[f]!.text.trim();
      final pa = RateText.parseAmount(text);
      if (text.isNotEmpty && pa.value == null) {
        setState(() => _error = 'مقدار «${f.label}» نامعتبر است.');
        return;
      }
      parsed[f] = pa.value;
    }
    for (final f in PriceField.values) {
      final nv = parsed[f];
      if (nv != r.priceFor(f)) {
        r.extractionFlags.removeWhere((x) => x.startsWith('قیمت «${f.label}»'));
      }
      r.setPrice(f, nv);
    }
    r.title = title;
    r.code = _nz(_code.text);
    r.brandText = _nz(_brand.text);
    r.modelText = _nz(_model.text);
    if (r.brandText != null || r.modelText != null) r.vehicleText = null;
    r.type = _nz(_type.text);
    r.year = _nz(_year.text);
    r.notes = _nz(_notes.text);
    r.unit = _unit;
    if (_categoryName != _initialCategoryName) r.categoryText = _categoryName;
    r.linkedServiceId = _linkedId;
    r.forceNew = _forceNew;
    r.userConfirmed = _confirmed;
    Navigator.pop(context, _EditAction.saved);
  }

  Widget _field(TextEditingController c, String label, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label)),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final linked = _linkedId == null ? null : widget.matcher.serviceById(_linkedId!);
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('ویرایش ردیف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(r.sourceLabel, style: const TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 12),
          _field(_title, 'عنوان خدمت'),
          _field(_code, 'کد خدمت'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<String?>(
              value: _categoryName,
              decoration: const InputDecoration(labelText: 'دسته‌بندی'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('پیش‌فرض (دسته‌ی انتخاب‌شده در ورود)')),
                ...widget.matcher.categories.map((c) => DropdownMenuItem<String?>(value: c.name, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _categoryName = v),
            ),
          ),
          if ((r.vehicleText ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('خودرو در فایل: ${r.vehicleText} (برند و مدل را جداگانه وارد کنید)',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
            ),
          _field(_brand, 'برند'),
          _field(_model, 'مدل'),
          _field(_type, 'تیپ'),
          _field(_year, 'سال'),
          const Divider(),
          for (final f in PriceField.values) _field(_prices[f]!, 'قیمت: ${f.label}', type: TextInputType.number),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<String?>(
              value: _unit,
              decoration: const InputDecoration(labelText: 'واحد قیمت در فایل'),
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('نامشخص')),
                DropdownMenuItem<String?>(value: 'toman', child: Text('تومان')),
                DropdownMenuItem<String?>(value: 'rial', child: Text('ریال')),
              ],
              onChanged: (v) => setState(() => _unit = v),
            ),
          ),
          _field(_notes, 'توضیحات'),
          const Divider(),
          Text(
            linked != null
                ? 'تطبیق دستی با: ${linked.name} (${widget.matcher.scopeLabel(linked)})'
                : _forceNew
                    ? 'به‌عنوان خدمت جدید ثبت می‌شود'
                    : (r.matched != null ? 'تطبیق خودکار با: ${r.matched!.name}' : 'خدمت جدید (تطبیقی پیدا نشد)'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: _pickService, child: const Text('تطبیق با خدمت موجود...')),
            OutlinedButton(
              onPressed: () => setState(() {
                _forceNew = true;
                _linkedId = null;
              }),
              child: const Text('ثبت به‌عنوان جدید'),
            ),
            if (_forceNew || _linkedId != null)
              TextButton(
                onPressed: () => setState(() {
                  _forceNew = false;
                  _linkedId = null;
                }),
                child: const Text('تطبیق خودکار'),
              ),
          ]),
          if (r.issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...r.issues.map((i) => Text('• $i', style: TextStyle(fontSize: 12, color: Colors.orange.shade800))),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('بررسی کردم و موارد هشدار را تأیید می‌کنم', style: TextStyle(fontSize: 13)),
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _save, child: const Text('ذخیره')),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(context, _EditAction.deleted),
            child: const Text('حذف این ردیف از لیست', style: TextStyle(color: Colors.red)),
          ),
        ]),
      ),
    );
  }
}

class _ServicePickerDialog extends StatefulWidget {
  const _ServicePickerDialog({required this.matcher});
  final RateMatcher matcher;

  @override
  State<_ServicePickerDialog> createState() => _ServicePickerDialogState();
}

class _ServicePickerDialogState extends State<_ServicePickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = RateText.normalize(_q);
    final list = widget.matcher.services
        .where((s) => q.isEmpty || RateText.normalize(s.name).contains(q) || s.code.toLowerCase().contains(q))
        .take(100)
        .toList();
    return AlertDialog(
      title: const Text('انتخاب خدمت موجود'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(hintText: 'جستجوی نام یا کد', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i];
                return ListTile(
                  dense: true,
                  title: Text(s.name),
                  subtitle: Text('${s.code} · ${widget.matcher.scopeLabel(s)}'),
                  onTap: () => Navigator.pop(context, s),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف'))],
    );
  }
}
