import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/service.dart';
import '../repositories/product_repository.dart';
import '../repositories/service_repository.dart';
import '../repositories/service_group_repository.dart';
import '../services/voice_search_service.dart';

enum VoiceSearchScope { services, products }

/// نتیجه‌ی انتخاب‌شده از پنجره‌ی جستجوی صوتی: یا یک کالا، یا یک خدمت.
class VoiceSearchResult {
  final Product? product;
  final ServiceItem? service;
  VoiceSearchResult.product(Product p)
      : product = p,
        service = null;
  VoiceSearchResult.service(ServiceItem s)
      : service = s,
        product = null;
}

/// پنجره‌ی جستجوی صوتی: دکمه‌ی میکروفون، نمایش متن تشخیص‌داده‌شده و لیست
/// نتایج نزدیک/فازی. در جستجوی خدمات، نتایج زیر عنوان «مجموعه خدمات» گروه‌بندی
/// می‌شوند و یک فیلتر مجموعه هم هست. اگر تشخیص گفتار در دسترس نبود، پیام مناسب
/// نشان می‌دهد و برنامه کرش نمی‌کند.
class VoiceSearchSheet extends StatefulWidget {
  final VoiceSearchScope scope;
  const VoiceSearchSheet({super.key, required this.scope});

  @override
  State<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends State<VoiceSearchSheet> {
  final _voiceService = VoiceSearchService();
  final _productRepo = ProductRepository();
  final _serviceRepo = ServiceRepository();
  final _groupRepo = ServiceGroupRepository();
  final _categoryRepo = ServiceCategoryRepository();
  bool _listening = false;
  String? _recognizedText;
  String? _errorMessage;
  List<Product> _productResults = [];
  List<ServiceItem> _serviceResults = [];

  // مجموعه‌ها (فقط برای جستجوی خدمات)
  List<ServiceGroup> _allGroups = [];
  Map<int, String> _categoryNames = {};
  int? _filterGroupId;

  @override
  void initState() {
    super.initState();
    if (widget.scope == VoiceSearchScope.services) _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await _groupRepo.getAll();
      final cats = await _categoryRepo.getAll();
      if (!mounted) return;
      setState(() {
        _allGroups = groups;
        _categoryNames = {for (final c in cats) if (c.id != null) c.id!: c.name};
      });
    } catch (_) {
      // بدون مجموعه هم جستجو کار می‌کند.
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _listening = true;
      _errorMessage = null;
      _recognizedText = null;
      _productResults = [];
      _serviceResults = [];
    });
    final text = await _voiceService.listenOnce();
    if (!mounted) return;
    if (text == null) {
      setState(() {
        _listening = false;
        _errorMessage =
            'تشخیص گفتار در دسترس نیست یا صدایی شناسایی نشد. می‌توانید به‌صورت دستی جستجو کنید.';
      });
      return;
    }
    setState(() {
      _recognizedText = text;
      _listening = false;
    });
    await _search(text);
  }

  Future<void> _search(String text) async {
    List<Product> products = [];
    List<ServiceItem> services = [];
    if (widget.scope == VoiceSearchScope.products) {
      products = await _productRepo.searchFuzzy(text);
    } else {
      services = await _serviceRepo.searchFuzzy(text);
    }
    if (!mounted) return;
    setState(() {
      _productResults = products;
      _serviceResults = services;
    });
  }

  List<ServiceGroup> get _filterGroups =>
      _allGroups.where((g) => g.active && _categoryNames.containsKey(g.categoryId)).toList();

  String _groupLabel(ServiceGroup g) {
    final cat = _categoryNames[g.categoryId];
    return cat == null ? g.name : '$cat - ${g.name}';
  }

  Widget _heading(String text, int count) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        child: Text('$text ($count)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );

  /// نتایج خدمات، گروه‌بندی‌شده بر اساس مجموعه (خدمات بدون مجموعه آخر).
  List<Widget> _serviceWidgets() {
    final visible = _filterGroupId == null
        ? _serviceResults
        : _serviceResults.where((s) => s.serviceGroupId == _filterGroupId).toList();
    if (_serviceResults.isNotEmpty && visible.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('در این مجموعه نتیجه‌ای نیست. فیلتر را روی «همه مجموعه‌ها» بگذارید.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        )
      ];
    }
    final byGroup = <int?, List<ServiceItem>>{};
    for (final s in visible) {
      byGroup.putIfAbsent(s.serviceGroupId, () => []).add(s);
    }
    final order = <int?>[
      for (final g in _allGroups)
        if (byGroup.containsKey(g.id)) g.id,
    ];
    for (final id in byGroup.keys) {
      if (id != null && !order.contains(id)) order.add(id);
    }
    if (byGroup.containsKey(null)) order.add(null);

    final widgets = <Widget>[];
    for (final id in order) {
      final list = byGroup[id]!;
      final group = id == null ? null : _allGroups.where((g) => g.id == id).firstOrNull;
      widgets.add(_heading(group == null ? 'بدون مجموعه' : _groupLabel(group), list.length));
      for (final s in list) {
        widgets.add(ListTile(
          leading: const Icon(Icons.build_outlined),
          title: Text(s.name),
          onTap: () => Navigator.pop(context, VoiceSearchResult.service(s)),
        ));
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _productResults.isNotEmpty || _serviceResults.isNotEmpty;
    final primary = Theme.of(context).colorScheme.primary;
    final groups = _filterGroups;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text('جستجوی صوتی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _listening ? null : _startListening,
            child: CircleAvatar(
              radius: 36,
              backgroundColor: _listening ? Colors.red : primary,
              child: Icon(_listening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: 12),
          if (_listening) const Text('در حال شنیدن...'),
          if (_recognizedText != null) Text('متن تشخیص‌داده‌شده: «$_recognizedText»'),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
            ),
          if (widget.scope == VoiceSearchScope.services && groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: groups.any((g) => g.id == _filterGroupId) ? _filterGroupId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'فیلتر مجموعه خدمات', isDense: true),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('همه مجموعه‌ها')),
                ...groups.map((g) => DropdownMenuItem<int?>(
                      value: g.id,
                      child: Text(_groupLabel(g), overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setState(() => _filterGroupId = v),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: !hasResults
                ? const SizedBox.shrink()
                : ListView(
                    controller: scrollController,
                    children: [
                      ..._serviceWidgets(),
                      ..._productResults.map((p) => ListTile(
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(p.name),
                            onTap: () => Navigator.pop(context, VoiceSearchResult.product(p)),
                          )),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}
