import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../models/app_settings.dart';
import '../../models/finance_account.dart';
import '../../repositories/finance_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/persian_date.dart';
import '../../utils/thousands_input_formatter.dart';

/// تعریف یا ویرایش «حساب مالی فروش کالا». خودش وضعیت را از دیتابیس
/// می‌خواند: اگر حساب نباشد، حالت تعریف؛ اگر باشد، حالت ویرایش.
///
/// در حالت ویرایش فقط نام، شماره کارت و توضیحات قابل تغییرند. تاریخ شروع و
/// موجودی اولیه قابل ویرایش مستقیم نیستند (موجودی اولیه فقط با اصلاحیه در
/// صفحه‌ی گردش مالی تغییر می‌کند).
class FinanceAccountSetupScreen extends StatefulWidget {
  const FinanceAccountSetupScreen({super.key});
  @override
  State<FinanceAccountSetupScreen> createState() => _FinanceAccountSetupScreenState();
}

class _FinanceAccountSetupScreenState extends State<FinanceAccountSetupScreen> {
  final _repo = FinanceRepository();
  final _settingsRepo = SettingsRepository();

  final _nameCtrl = TextEditingController(text: 'حساب فروش کالا');
  final _cardCtrl = TextEditingController();
  final _openingCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  FinanceAccount? _account;
  Currency _currency = Currency.toman;
  DateTime _startDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  bool get _isEdit => _account != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cardCtrl.dispose();
    _openingCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _settingsRepo.getSettings();
    final account = await _repo.getGoodsSalesAccount();
    if (!mounted) return;
    setState(() {
      _currency = settings.currency;
      _account = account;
      if (account != null) {
        _nameCtrl.text = account.name;
        _cardCtrl.text = account.cardNumber ?? '';
        _notesCtrl.text = account.notes ?? '';
        _startDate = account.startDateTime;
      }
      _loading = false;
    });
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickStartDate() async {
    final jalali = await showPersianDatePicker(
      context: context,
      initialDate: Jalali.fromDateTime(_startDate),
      firstDate: Jalali(1394, 1, 1),
      lastDate: Jalali(1450, 12, 29),
    );
    if (jalali == null) return;
    setState(() => _startDate = jalali.toDateTime());
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _msg('نام حساب را وارد کنید');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _repo.updateAccountInfo(
          id: _account!.id!,
          name: name,
          cardNumber: _cardCtrl.text,
          notes: _notesCtrl.text,
        );
      } else {
        final raw = _openingCtrl.text.trim();
        final opening = raw.isEmpty ? 0.0 : double.tryParse(ThousandsInputFormatter.unformat(raw));
        if (opening == null || opening < 0) {
          _msg('موجودی اولیه معتبر نیست');
          return;
        }
        await _repo.createGoodsSalesAccount(
          name: name,
          cardNumber: _cardCtrl.text,
          startDate: _startDate,
          notes: _notesCtrl.text,
          openingBalance: opening,
        );
      }
      if (mounted) {
        _msg(_isEdit ? 'اطلاعات حساب ذخیره شد' : 'حساب مالی فروش کالا تعریف شد');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _msg('خطا: ${financeErrorText(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'ویرایش حساب فروش کالا' : 'تعریف حساب فروش کالا')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'نام حساب')),
        const SizedBox(height: 12),
        TextField(
          controller: _cardCtrl,
          decoration: const InputDecoration(labelText: 'شماره کارت / حساب (اختیاری)'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        if (!_isEdit) ...[
          TextField(
            controller: _openingCtrl,
            decoration: InputDecoration(labelText: 'موجودی اولیه', suffixText: _currency.label),
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsInputFormatter()],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickStartDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'تاریخ شروع'),
              child: Text(PersianDateUtil.formatDate(_startDate.toIso8601String())),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'موجودی اولیه به‌صورت اولین تراکنش دفتر ثبت می‌شود و از آن لحظه به بعد تمام گردش‌های مالی فروشگاه کالا از روی آن محاسبه می‌شود.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ] else ...[
          InputDecorator(
            decoration: const InputDecoration(labelText: 'تاریخ شروع'),
            child: Text(PersianDateUtil.formatDate(_startDate.toIso8601String())),
          ),
          const SizedBox(height: 8),
          const Text(
            'تاریخ شروع و موجودی اولیه مستقیم قابل ویرایش نیستند. برای تغییر موجودی اولیه، در صفحه‌ی گردش مالی آن را با «اصلاحیه» معکوس کنید و موجودی درست را دوباره ثبت کنید.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _notesCtrl,
          decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
          maxLines: 2,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_isEdit ? 'ذخیره تغییرات' : 'تعریف حساب'),
        ),
      ]),
    );
  }
}
