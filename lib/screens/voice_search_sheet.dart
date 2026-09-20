import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/service.dart';
import '../repositories/product_repository.dart';
import '../repositories/service_repository.dart';
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
/// نتایج نزدیک/فازی. اگر تشخیص گفتار در دسترس نبود، پیام مناسب نشان
/// می‌دهد و برنامه کرش نمی‌کند.
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
  bool _listening = false;
  String? _recognizedText;
  String? _errorMessage;
  List<Product> _productResults = [];
  List<ServiceItem> _serviceResults = [];

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

  @override
  Widget build(BuildContext context) {
    final hasResults = _productResults.isNotEmpty || _serviceResults.isNotEmpty;
    final primary = Theme.of(context).colorScheme.primary;
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
          const SizedBox(height: 12),
          Expanded(
            child: !hasResults
                ? const SizedBox.shrink()
                : ListView(
                    controller: scrollController,
                    children: [
                      ..._serviceResults.map((s) => ListTile(
                            leading: const Icon(Icons.build_outlined),
                            title: Text(s.name),
                            onTap: () => Navigator.pop(context, VoiceSearchResult.service(s)),
                          )),
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
