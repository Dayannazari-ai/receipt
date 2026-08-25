import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/app_settings.dart';
import '../../models/payment_account.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/payment_account_repository.dart';
import '../../services/backup_service.dart';
import '../../services/seed_service.dart';
import '../../main.dart';
import 'price_list_import_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = SettingsRepository();
  final _paymentRepo = PaymentAccountRepository();
  final _backupService = BackupService();
  final _seedService = SeedService();

  late TextEditingController _shopName;
  late TextEditingController _contactNumber;
  late TextEditingController _address;
  late TextEditingController _startNumber;
  late TextEditingController _lowStock;
  late TextEditingController _termsText;
  late TextEditingController _stampPathCtrl;
  Currency _currency = Currency.toman;
  String _colorHex = '#FF7A1A';
  String? _stampImagePath;
  List<PaymentAccount> _accounts = [];
  bool _loading = true;
  bool _busy = false;

  final _colorOptions = ['#FF7A1A', '#1E5F74', '#2E8B57', '#D64545', '#6B4EFF', '#00838F'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _repo.getSettings();
    final accounts = await _paymentRepo.getAll();
    _shopName = TextEditingController(text: settings.shopName);
    _contactNumber = TextEditingController(text: settings.contactNumber);
    _address = TextEditingController(text: settings.address);
    _startNumber = TextEditingController(text: settings.invoiceStartNumber.toString());
    _lowStock = TextEditingController(text: settings.lowStockThreshold.toString());
    _termsText = TextEditingController(text: settings.termsText);
    _stampPathCtrl = TextEditingController(text: settings.stampImagePath ?? '');
    if (!mounted) return;
    setState(() {
      _currency = settings.currency;
      _colorHex = settings.primaryColorHex;
      _stampImagePath = settings.stampImagePath;
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final stampPath = _stampPathCtrl.text.trim();
      await _repo.saveSettings(AppSettings(
        shopName: _shopName.text.trim(),
        contactNumber: _contactNumber.text.trim(),
        address: _address.text.trim(),
        invoiceStartNumber: int.tryParse(_startNumber.text.trim()) ?? 1001,
        currency: _currency,
        lowStockThreshold: int.tryParse(_lowStock.text.trim()) ?? 5,
        primaryColorHex: _colorHex,
        termsText: _termsText.text.trim(),
        stampImagePath: stampPath.isEmpty ? null : stampPath,
      ));
      setState(() => _stampImagePath = stampPath.isEmpty ? null : stampPath);
      ReceiptApp.of(context)?.updateColor(_colorHex);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات ذخیره شد')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAccount() async {
    final titleCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('افزودن شماره کارت/شبا', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'عنوان (مثلاً کارت بانک ملی)')),
          const SizedBox(height: 12),
          TextField(controller: numberCtrl, decoration: const InputDecoration(labelText: 'شماره کارت یا شبا')),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty || numberCtrl.text.trim().isEmpty) return;
              await _paymentRepo.insert(PaymentAccount(title: titleCtrl.text.trim(), number: numberCtrl.text.trim()));
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('ثبت'),
          ),
        ]),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _doBackup() async {
    setState(() => _busy = true);
    try {
      final file = await _backupService.createBackup();
      await _backupService.shareBackup(file);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRestore() async {
    final pathCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بازیابی از فایل پشتیبان'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('فایل .db را با فایل‌منیجر گوشی به پوشه Documents برنامه منتقل کنید و مسیر آن را وارد کنید.'),
          const SizedBox(height: 12),
          TextField(controller: pathCtrl, decoration: const InputDecoration(labelText: 'مسیر فایل .db')),
          const SizedBox(height: 8),
          const Text('هشدار: اطلاعات فعلی جایگزین می‌شود.', style: TextStyle(color: Colors.red, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('بازیابی', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true || pathCtrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await _backupService.restoreFromPath(pathCtrl.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بازیابی انجام شد. برنامه را دوباره باز کنید.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('اطلاعات فروشگاه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          TextField(controller: _shopName, decoration: const InputDecoration(labelText: 'نام فروشگاه/تعمیرگاه')),
          const SizedBox(height: 12),
          TextField(controller: _contactNumber, decoration: const InputDecoration(labelText: 'شماره تماس'), keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'آدرس'), maxLines: 2),
          const SizedBox(height: 20),

          const Text('رنگ اصلی برنامه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: _colorOptions.map((hex) {
              final selected = hex == _colorHex;
              return GestureDetector(
                onTap: () => setState(() => _colorHex = hex),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16)),
                    shape: BoxShape.circle,
                    border: selected ? Border.all(color: Colors.black, width: 3) : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          const Text('فاکتور و موجودی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          TextField(controller: _startNumber, decoration: const InputDecoration(labelText: 'شماره شروع فاکتور'), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          TextField(controller: _lowStock, decoration: const InputDecoration(labelText: 'آستانه کمبود موجودی'), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          DropdownButtonFormField<Currency>(
            value: _currency,
            decoration: const InputDecoration(labelText: 'واحد پولی'),
            items: Currency.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
            onChanged: (c) => setState(() => _currency = c!),
          ),
          const SizedBox(height: 20),

          const Text('نکات مهم و شرایط (زیر همه فاکتورها چاپ می‌شود)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          TextField(
            controller: _termsText,
            decoration: const InputDecoration(labelText: 'متن نکات مهم / شرایط و قوانین', alignLabelWithHint: true),
            maxLines: 5,
          ),
          const SizedBox(height: 20),

          const Text('مهر و امضای کارگاه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('عکس مهر/امضا را با فایل‌منیجر گوشی به پوشه Documents برنامه منتقل کنید و مسیر آن را وارد کنید.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(controller: _stampPathCtrl, decoration: const InputDecoration(labelText: 'مسیر فایل عکس مهر/امضا')),
          if (_stampImagePath != null && File(_stampImagePath!).existsSync()) ...[
            const SizedBox(height: 10),
            Image.file(File(_stampImagePath!), height: 80),
          ],
          const SizedBox(height: 20),

          ElevatedButton(onPressed: _save, child: const Text('ذخیره تنظیمات')),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          const Text('شماره کارت و شبا', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          ..._accounts.map((a) => Card(
                child: ListTile(
                  leading: const Icon(Icons.credit_card),
                  title: Text(a.title),
                  subtitle: Text(a.number),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      await _paymentRepo.softDelete(a.id!);
                      _load();
                    },
                  ),
                ),
              )),
          OutlinedButton.icon(icon: const Icon(Icons.add), label: const Text('افزودن کارت/شبا'), onPressed: _addAccount),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          const Text('وارد کردن نرخ‌نامه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('فایل اکسل نرخ‌نامه‌ی خودتان را وارد کنید و دسته‌بندی مقصد را خودتان انتخاب می‌کنید.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('وارد کردن نرخ‌نامه از فایل'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PriceListImportScreen())),
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          const Text('پشتیبان‌گیری', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          OutlinedButton.icon(icon: const Icon(Icons.backup_outlined), label: const Text('تهیه فایل پشتیبان'), onPressed: _doBackup),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.restore_outlined),
            label: const Text('بازیابی از فایل پشتیبان'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _doRestore,
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          const Text('داده‌های آزمایشی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('حذف داده‌های آزمایشی'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              setState(() => _busy = true);
              await _seedService.deleteAllSampleData();
              setState(() => _busy = false);
            },
          ),
          if (_busy) ...[const SizedBox(height: 20), const Center(child: CircularProgressIndicator())],
        ]),
      ),
    );
  }
}
