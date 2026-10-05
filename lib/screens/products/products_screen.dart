import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../models/app_settings.dart';
import '../../repositories/product_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/persian_date.dart';
import 'product_form_screen.dart';

/// تبدیل ارقام فارسی/عربی به انگلیسی فقط برای مقایسهٔ کدها در مرتب‌سازی.
String _normDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(r - 0x06F0 + 0x30);
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(r - 0x0660 + 0x30);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// مقایسهٔ کدها: کدهای عددی به‌صورت عددی (۲ قبل از ۱۰)، سپس متنی.
int _compareCodes(String a, String b) {
  final na = _normDigits(a.trim());
  final nb = _normDigits(b.trim());
  final ia = int.tryParse(na);
  final ib = int.tryParse(nb);
  if (ia != null && ib != null) {
    final c = ia.compareTo(ib);
    if (c != 0) return c;
    return 0;
  }
  if (ia != null) return -1;
  if (ib != null) return 1;
  return na.compareTo(nb);
}

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
  String _sortBy = 'name'; // 'name' یا 'code'

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Product> _sorted(List<Product> src) {
    final l = List<Product>.of(src);
    l.sort((a, b) {
      if (_sortBy == 'code') {
        final c = _compareCodes(a.code, b.code);
        if (c != 0) return c;
      }
      return a.name.compareTo(b.name);
    });
    return l;
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
      _products = _sorted(list);
      _currency = settings.currency;
      _loading = false;
    });
  }

  Future<void> _openForm({Product? product}) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)));
    _load();
  }
  Future<void> _showProductActions(Product product) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('ویرایش'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('حذف', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (action == 'edit') {
      _openForm(product: product);
    } else if (action == 'delete') {
      _confirmDeleteProduct(product);
    }
  }

  Future<void> _confirmDeleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف کالا'),
        content: const Text('آیا از حذف این کالا مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.softDelete(product.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('انبار کالا'), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          tooltip: 'مرتب‌سازی',
          onSelected: (v) {
            setState(() {
              _sortBy = v;
              _products = _sorted(_products);
            });
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem<String>(
              value: 'name',
              checked: _sortBy == 'name',
              child: const Text('بر اساس نام'),
            ),
            CheckedPopupMenuItem<String>(
              value: 'code',
              checked: _sortBy == 'code',
              child: const Text('بر اساس کد'),
            ),
          ],
        ),
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
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      itemCount: _products.length,
                      itemBuilder: (context, i) {
                        final p = _products[i];
                        final codePrefix = _sortBy == 'code' ? 'کد: ${p.code} - ' : '';
                        return GestureDetector(
                          onLongPress: () => _showProductActions(p),
                          child: Card(
                            color: p.isLowStock ? Colors.red.shade50 : null,
                            child: ListTile(
                              leading: CircleAvatar(
                                  backgroundColor: p.isLowStock ? Colors.red.shade100 : null,
                                  child: Icon(p.isLowStock ? Icons.warning_amber : Icons.inventory_2_outlined)),
                              title: Text(p.name),
                              subtitle: Text(
                                  '${codePrefix}موجودی: ${PersianDateUtil.toPersianDigits('${p.stock}')}'
                                  '${p.barcode != null ? ' - بارکد: ${p.barcode}' : ''}'),
                              trailing: Text(CurrencyFormatter.format(p.sellPrice, _currency)),
                              onTap: () => _openForm(product: p),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('افزودن کالا'),
        onPressed: () => _openForm(),
      ),
    );
  }
}
