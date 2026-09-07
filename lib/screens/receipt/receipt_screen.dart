import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../repositories/product_repository.dart';
import '../../utils/validators.dart';
import '../products/barcode_scanner_screen.dart';

/// فرم افزودن/ویرایش کالا، به‌صورت صفحه‌ی مستقل تا هم از «انبار کالا» و هم
/// از «صدور فاکتور» (هنگام برخورد با بارکد ناشناخته) قابل استفاده باشد.
/// در صورت ثبت موفق، همان Product ذخیره‌شده را با Navigator.pop برمی‌گرداند.
class ProductFormScreen extends StatefulWidget {
  final Product? product;
  final String? initialBarcode;
  const ProductFormScreen({super.key, this.product, this.initialBarcode});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _repo = ProductRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _purchaseCtrl;
  late final TextEditingController _sellCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _minStockCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _codeCtrl = TextEditingController(text: p?.code ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? widget.initialBarcode ?? '');
    _purchaseCtrl = TextEditingController(text: p?.purchasePrice.toStringAsFixed(0) ?? '');
    _sellCtrl = TextEditingController(text: p?.sellPrice.toStringAsFixed(0) ?? '');
    _stockCtrl = TextEditingController(text: p?.stock.toString() ?? '0');
    _minStockCtrl = TextEditingController(text: p?.minStock.toString() ?? '0');
    _notesCtrl = TextEditingController(text: p?.notes ?? '');
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result != null) setState(() => _barcodeCtrl.text = result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final codeExists = await _repo.codeExists(_codeCtrl.text.trim(), excludeId: widget.product?.id);
    if (codeExists) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('این کد کالا قبلاً استفاده شده است')));
      }
      return;
    }

    final barcode = _barcodeCtrl.text.trim();
    if (barcode.isNotEmpty) {
      final barcodeDuplicate = await _repo.barcodeExists(barcode, excludeId: widget.product?.id);
      if (barcodeDuplicate) {
        final existing = (await _repo.getAll()).where((p) => p.barcode == barcode);
        if (mounted) {
          final goToExisting = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('بارکد تکراری'),
              content: const Text('این بارکد قبلاً ثبت شده است.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('بستن')),
                if (existing.isNotEmpty)
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('مشاهده کالای موجود')),
              ],
            ),
          );
          if (goToExisting == true && existing.isNotEmpty && mounted) {
            Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => ProductFormScreen(product: existing.first)));
          }
        }
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final newProduct = Product(
        id: widget.product?.id,
        name: _nameCtrl.text.trim(),
        code: _codeCtrl.text.trim(),
        barcode: barcode.isEmpty ? null : barcode,
        purchasePrice: double.parse(_purchaseCtrl.text.replaceAll(',', '')),
        sellPrice: double.parse(_sellCtrl.text.replaceAll(',', '')),
        stock: int.parse(_stockCtrl.text),
        minStock: int.parse(_minStockCtrl.text),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdAt: widget.product?.createdAt,
      );
      int savedId;
      if (_isEdit) {
        await _repo.update(newProduct);
        savedId = newProduct.id!;
      } else {
        savedId = await _repo.insert(newProduct);
      }
      final saved = await _repo.getById(savedId);
      if (mounted) Navigator.of(context).pop(saved);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف کالا'),
        content: const Text('آیا از حذف این کالا مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.softDelete(widget.product!.id!);
      if (mounted) Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'ویرایش کالا' : 'کالای جدید'),
        actions: [
          if (_isEdit) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'نام کالا'),
              validator: (v) => Validators.required(v, fieldName: 'نام کالا')),
          const SizedBox(height: 12),
          TextFormField(
              controller: _codeCtrl,
              decoration: const InputDecoration(labelText: 'کد کالا'),
              validator: (v) => Validators.required(v, fieldName: 'کد کالا')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _barcodeCtrl,
                decoration: const InputDecoration(labelText: 'بارکد (اختیاری)'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('اسکن'),
              onPressed: _scanBarcode,
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                  controller: _purchaseCtrl,
                  decoration: const InputDecoration(labelText: 'قیمت خرید'),
                  keyboardType: TextInputType.number,
                  validator: (v) => Validators.nonNegativeNumber(v, fieldName: 'قیمت خرید')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                  controller: _sellCtrl,
                  decoration: const InputDecoration(labelText: 'قیمت فروش'),
                  keyboardType: TextInputType.number,
                  validator: (v) => Validators.nonNegativeNumber(v, fieldName: 'قیمت فروش')),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                  controller: _stockCtrl,
                  decoration: const InputDecoration(labelText: 'موجودی'),
                  keyboardType: TextInputType.number,
                  validator: (v) => Validators.nonNegativeNumber(v, fieldName: 'موجودی')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                  controller: _minStockCtrl,
                  decoration: const InputDecoration(labelText: 'حداقل موجودی'),
                  keyboardType: TextInputType.number,
                  validator: (v) => Validators.nonNegativeNumber(v, fieldName: 'حداقل موجودی')),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEdit ? 'ذخیره تغییرات' : 'ثبت کالا'),
          ),
        ]),
      ),
    );
  }
}
