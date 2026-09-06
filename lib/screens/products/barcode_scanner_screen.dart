import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../models/app_settings.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _repo = ProductRepository();
  final _settingsRepo = SettingsRepository();
  final _searchCtrl = TextEditingController();
  List<Product> _products = [];
  Currency _currency = Currency.toman;
  bool _lowStockOnly = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    var list = _searchCtrl.text.trim().isEmpty
        ? await _repo.getAll()
        : await _repo.search(_searchCtrl.text.trim());
    if (_lowStockOnly) list = list.where((p) => p.isLowStock).toList();
    final settings = await _settingsRepo.getSettings();
    if (!mounted) return;
    setState(() {
      _products = list;
      _currency = settings.currency;
      _loading = false;
    });
  }

  Future<void> _openForm({Product? product}) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('انبار کالا'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(hintText: 'جستجوی کالا', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => _load(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilterChip(
              label: const Text('کمبود موجودی'),
              selected: _lowStockOnly,
              onSelected: (v) {
                setState(() => _lowStockOnly = v);
                _load();
              },
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? const Center(child: Text('کالایی یافت نشد'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _products.length,
                      itemBuilder: (context, i) {
                        final p = _products[i];
                        return Card(
                          color: p.isLowStock ? Colors.red.shade50 : null,
                          child: ListTile(
                            leading: CircleAvatar(
                                backgroundColor: p.isLowStock ? Colors.red.shade100 : null,
                                child: Icon(p.isLowStock ? Icons.warning_amber : Icons.inventory_2_outlined)),
                            title: Text(p.name),
                            subtitle: Text(
                                'موجودی: ${PersianDateUtil.toPersianDigits('${p.stock}')}'
                                '${p.barcode != null ? ' - بارکد: ${p.barcode}' : ''}'),
                            trailing: Text(CurrencyFormatter.format(p.sellPrice, _currency)),
                            onTap: () => _openForm(product: p),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('افزودن کالا'),
        onPressed: () => _openForm(),
      ),
    );
  }
}
