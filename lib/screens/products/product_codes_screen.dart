import 'package:flutter/material.dart';
import '../../repositories/product_repository.dart';
import '../../utils/persian_date.dart';

/// «مدیریت کدهای کالا»: آخرین شماره، تعداد کالاهای دارای کد، کدهای آزاد،
/// کدهای غیرقابل استفاده و کد پیشنهادی برای کالای جدید. فقط نمایش است و
/// هیچ داده‌ای را تغییر نمی‌دهد.
class ProductCodesScreen extends StatefulWidget {
  const ProductCodesScreen({super.key});
  @override
  State<ProductCodesScreen> createState() => _ProductCodesScreenState();
}

class _ProductCodesScreenState extends State<ProductCodesScreen> {
  final _repo = ProductRepository();
  ProductCodeInfo? _info;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _repo.loadCodeInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _n(int v) => PersianDateUtil.toPersianDigits('$v');

  Widget _kv(String k, String v, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(v,
                style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
          ),
        ]),
      );

  Widget _chips(List<String> codes, {Color? color}) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in codes)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Chip(
                label: Text(c, style: const TextStyle(fontSize: 12)),
                backgroundColor: color,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت کدهای کالا'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : info == null
              ? Center(child: Text(_error ?? 'خطا در بارگذاری'))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _kv('آخرین شماره‌ی ثبت‌شده', info.lastCode ?? '—', bold: true),
                        _kv('تعداد کالاهای دارای کد', _n(info.productsWithCode)),
                        _kv('تعداد کدهای آزاد', _n(info.freeCodes.length)),
                        const Divider(),
                        _kv('کد پیشنهادی برای کالای جدید', info.suggested, color: primary, bold: true),
                        const SizedBox(height: 4),
                        Text(
                          info.freeCodes.isEmpty
                              ? 'کد آزادی نیست؛ شماره‌ی بعد از آخرین کد پیشنهاد می‌شود.'
                              : 'کوچک‌ترین کد آزاد پیشنهاد می‌شود.',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ]),
                    ),
                  ),
                  if (info.duplicateCodes.isNotEmpty)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Text('هشدار: کد تکراریِ از قبل موجود',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          const SizedBox(height: 6),
                          const Text('این کدها بین چند کالای فعال مشترک‌اند. کد یکی از کالاها را ویرایش کنید.',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 6),
                          _chips(info.duplicateCodes, color: Colors.red.shade100),
                        ]),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('کدهای آزاد (${_n(info.freeCodes.length)})',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        if (info.freeCodes.isEmpty)
                          const Text('کد آزادی وجود ندارد', style: TextStyle(color: Colors.grey))
                        else
                          _chips(info.freeCodes, color: Colors.green.shade50),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('کدهای غیرقابل استفاده (${_n(info.unusableCodes.length)})',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text(
                          'این کدها آزاد نمی‌شوند، چون استفاده‌ی دوباره‌شان سوابق فاکتور یا انبار را قاطی می‌کند.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        if (info.unusableCodes.isEmpty)
                          const Text('موردی نیست', style: TextStyle(color: Colors.grey))
                        else
                          for (final u in info.unusableCodes)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(children: [
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(u.code, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(u.reason, style: const TextStyle(fontSize: 12, color: Colors.grey))),
                              ]),
                            ),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
