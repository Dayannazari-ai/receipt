import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/app_settings.dart';
import '../../models/payment_account.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/payment_account_repository.dart';
import '../../services/backup_service.dart';
import '../../services/seed_service.dart';
import '../../services/auth_service.dart';
import '../../services/auto_backup_service.dart';
import '../../main.dart';
import 'price_list_import_screen.dart';
import 'invoice_template_settings_screen.dart';
import 'backup_restore_screen.dart';
import '../finance/finance_account_setup_screen.dart';
import '../finance/finance_ledger_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = SettingsRepository();
  final _authService = AuthService();
  final _paymentRepo = PaymentAccountRepository();
  final _backupService = BackupService();
  final _seedService = SeedService();
  final _autoBackup = AutoBackupService();

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
  String? _autoBackupDir;
  List<PaymentAccount> _accounts = [];
  bool _loading = true;
  bool _busy = false;
  bool _hasPassword = false;

  final _colorOptions = ['#FF7A1A', '#1E5F74', '#2E8B57', '#D64545', '#6B4EFF', '#00838F'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _repo.getSettings();
    final accounts = await _paymentRepo.getAll();
    final hasPassword = await _authService.hasPassword();
    final autoBackupDir = await _autoBackup.getBackupDir();
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
      _hasPassword = hasPassword;
      _autoBackupDir = autoBackupDir;
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

  Future<void> _pickStampImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => _stampPathCtrl.text = result.files.single.path!);
    }
  }

  Future<void> _chooseAutoBackupDir() async {
    try {
      final dir = await _autoBackup.chooseAndSaveDir();
      if (dir == null) return; // انصراف
      if (!mounted) return;
      setState(() => _autoBackupDir = dir);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مسیر پشتیبان ذخیره شد')));
    } on AutoBackupException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  Future<void> _clearAutoBackupDir() async {
    await _autoBackup.clearBackupDir();
    if (mounted) setState(() => _autoBackupDir = null);
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

  Future<void> _setOrChangePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? errorText;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text(_hasPassword ? 'تغییر رمز عبور' : 'تعیین رمز عبور'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_hasPassword)
              TextField(
                  controller: oldCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'رمز فعلی')),
            if (_hasPassword) const SizedBox(height: 10),
            TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'رمز جدید')),
            const SizedBox(height: 10),
            TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تکرار رمز جدید')),
            if (errorText != null) ...[
              const SizedBox(height: 10),
              Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            TextButton(
              onPressed: () async {
                if (_hasPassword) {
                  final ok = await _authService.verify(oldCtrl.text);
                  if (!ok) {
                    setDialogState(() => errorText = 'رمز فعلی اشتباه است');
                    return;
                  }
                }
                if (newCtrl.text.trim().isEmpty) {
                  setDialogState(() => errorText = 'رمز جدید نباید خالی باشد');
                  return;
                }
                if (newCtrl.text != confirmCtrl.text) {
                  setDialogState(() => errorText = 'رمز جدید و تکرار آن یکسان نیستند');
                  return;
                }
                await _authService.setPassword(newCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      }),
    );
    if (saved == true) _load();
  }

  Future<void> _removePassword() async {
    final ctrl = TextEditingController();
    String? errorText;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: const Text('حذف رمز عبور'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('برای حذف رمز، رمز فعلی را وارد کنید:'),
            const SizedBox(height: 10),
            TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: 'رمز فعلی')),
            if (errorText != null) ...[
              const SizedBox(height: 10),
              Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            TextButton(
              onPressed: () async {
                final ok = await _authService.verify(ctrl.text);
                if (!ok) {
                  setDialogState(() => errorText = 'رمز فعلی اشتباه است');
                  return;
                }
                await _authService.removePassword();
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('حذف رمز', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      }),
    );
    if (confirmed == true) _load();
  }

  Future<void> _doBackup() async {
    setState(() => _busy = true);
    try {
      final file = await _backupService.createLegacyFullDbBackup();
      await _backupService.shareBackup(file);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRestore() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    final pickedPath = result.files.single.path!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بازیابی از فایل پشتیبان'),
        content: const Text('هشدار: اطلاعات فعلی با این فایل جایگزین می‌شود و قابل بازگشت نیست. ادامه می‌دهید؟',
            style: TextStyle(color: Colors.red)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('بازیابی', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await _backupService.restoreLegacyFullDbFromPath(pickedPath);
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
          const Text('عکس مهر/امضا را با دکمه زیر مستقیم از فایل‌منیجر گوشی انتخاب کنید.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(controller: _stampPathCtrl, decoration: const InputDecoration(labelText: 'مسیر فایل عکس مهر/امضا')),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(icon: const Icon(Icons.folder_open), label: const Text('انتخاب'), onPressed: _pickStampImage),
          ]),
          if (_stampImagePath != null && File(_stampImagePath!).existsSync()) ...[
            const SizedBox(height: 10),
            Image.file(File(_stampImagePath!), height: 80),
          ],
          const SizedBox(height: 20),

          OutlinedButton.icon(
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('تنظیمات قالب فاکتور'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const InvoiceTemplateSettingsScreen())),
          ),
          const SizedBox(height: 20),

          ElevatedButton(onPressed: _save, child: const Text('ذخیره تنظیمات')),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          const Text('رمز عبور برنامه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            _hasPassword
                ? 'رمز عبور فعال است. برای باز کردن برنامه باید رمز وارد شود.'
                : 'رمز عبور تنظیم نشده — برنامه بدون رمز باز می‌شود.',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_outline),
            label: Text(_hasPassword ? 'تغییر رمز عبور' : 'تعیین رمز عبور'),
            onPressed: _setOrChangePassword,
          ),
          if (_hasPassword) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('حذف رمز عبور'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _removePassword,
            ),
          ],

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
          const Text('حساب مالی فروش کالا', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('دفتر مالی مستقل برای فروشگاه کالا، جدا از درآمد خدمات تعمیرگاهی.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('تعریف / ویرایش حساب مالی فروش کالا'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FinanceAccountSetupScreen())),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('گردش مالی فروش کالا'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FinanceLedgerScreen())),
          ),

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
          const Text('پشتیبان‌گیری و بازیابی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('پشتیبان‌گیری و بازیابی مستقل برای هر بخش (مشتریان، محصولات، خدمات، فاکتورها) یا به‌صورت کامل.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.backup_outlined),
            label: const Text('پشتیبان‌گیری و بازیابی'),
            onPressed: () async {
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const BackupRestoreScreen()));
              if (mounted) _load();
            },
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          const Text('پشتیبان خودکار هنگام خروج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text(
              'هنگام خروج از برنامه (دکمه‌ی بازگشت)، یک پشتیبان کامل با نام AutoBackup_تاریخ_ساعت در پوشه‌ی انتخابی ذخیره می‌شود. '
              'این مسیر مخصوص همین دستگاه است و در پشتیبان تنظیمات نمی‌آید.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          Text(
            _autoBackupDir == null ? 'مسیر پشتیبان: تعیین نشده' : 'مسیر پشتیبان: $_autoBackupDir',
            style: TextStyle(
                fontSize: 12,
                color: _autoBackupDir == null ? Colors.orange : null,
                fontWeight: FontWeight.bold),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: Text(_autoBackupDir == null ? 'تعیین مسیر پشتیبان' : 'تغییر مسیر پشتیبان'),
            onPressed: _chooseAutoBackupDir,
          ),
          if (_autoBackupDir != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.clear),
              label: const Text('حذف مسیر پشتیبان'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _clearAutoBackupDir,
            ),
          ],

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
