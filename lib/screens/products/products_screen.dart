import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../models/app_settings.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import '../../utils/validators.dart';

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

  Future<void> _addOrEdit({Product? product}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final codeCtrl = TextEditingController(text: product?.code ?? '');
    final purchaseCtrl = TextEditingController(text: product?.purchasePrice.toStringAsFixed(0) ?? '');
    final sellCtrl = TextEditingController(text: product?.sellPrice.toStringAsFixed(0) ?? '');
    final stockCtrl = TextEditingController(text: product?.stock.toString() ?? '0');
    final minStockCtrl = TextEditingController(text: product?.minStock.toString() ?? '0');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(product == null ? 'کالای جدید' : 'ویرایش کالا',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'نام کالا'),
                  validator: (v) => Validators.required(v, fieldName: 'نام کالا')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'کد کالا'),
                  validator: (v) => Validators.required(v, fieldName: 'کد کالا')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                      controller: purchaseCtrl,
                      decoration: const InputDecoration(labelText: 'قیمت خرید'),
                      keyboardType: TextInputType.number,
                      validator: (v) => Validators.nonNegativeNumber(v, fieldName: 'قیمت خرید')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                      controller: sellCtrl,
                      decoration: const InputDecoration(labelText: 'قیمت فروش'),
                      keyboardType: TextInputType.number,
                      validator: (v) => Validators.nonNegativeNumber(v, fieldName: 'قیمت فروش')),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                      controller: stockCtrl,
                      decoration: const InputDecoration(labelText: 'موجودی'),
                      keyboardType: TextInputType.number,
                      validator: (v) => Validators.nonNegativeNumber(v, fieldName: 'موجودی')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                      controller: minStockCtrl,
                      decoration: const InputDecoration(labelText: 'حداقل موجودی'),
                      keyboardType: TextInputType.number,
                      validator: (v) => Validators.nonNegativeNumber(v, fieldName: 'حداقل موجودی')),
                ),
              ]),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final exists = await _repo.codeExists(codeCtrl.text.trim(), excludeId: product?.id);
                  if (exists) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx)
                          .showSnackBar(const SnackBar(content: Text('این کد کالا قبلاً استفاده شده است')));
                    }
                    return;
                  }
                  final p = Product(
                    id: product?.id,
                    name: nameCtrl.text.trim(),
                    code: codeCtrl.text.trim(),
                    purchasePrice: double.parse(purchaseCtrl.text.replaceAll(',', '')),
                    sellPrice: double.parse(sellCtrl.text.replaceAll(',', '')),
                    stock: int.parse(stockCtrl.text),
                    minStock: int.parse(minStockCtrl.text),
                    createdAt: product?.createdAt,
                  );
                  if (product == null) {
                    await _repo.insert(p);
                  } else {
                    await _repo.update(p);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: Text(product == null ? 'ثبت کالا' : 'ذخیره تغییرات'),
              ),
              if (product != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await _repo.softDelete(product.id!);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: const Text('حذف کالا', style: TextStyle(color: Colors.red)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
    if (saved == true) _load();
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
                            subtitle:
                                Text('موجودی: ${PersianDateUtil.toPersianDigits('${p.stock}')}'),
                            trailing: Text(CurrencyFormatter.format(p.sellPrice, _currency)),
                            onTap: () => _addOrEdit(product: p),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('افزودن کالا'),
        onPressed: () => _addOrEdit(),
      ),
    );
  }
}
