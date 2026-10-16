import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../repositories/customer_repository.dart';

/// نتیجه‌ی دیالوگ افزودن سریع مشتری.
/// [alreadyExisted] یعنی مشتری با همین شماره از قبل در دیتابیس بود و
/// مشتری تکراری ساخته نشد؛ همان مشتری قبلی برگردانده شده است.
class QuickAddCustomerResult {
  final Customer customer;
  final bool alreadyExisted;
  const QuickAddCustomerResult(this.customer, this.alreadyExisted);
}

/// دیالوگ افزودن مشتری جدید (نام + موبایل) بدون خروج از صفحه‌ی فاکتور.
/// فقط وقتی کاربر «ثبت» را بزند چیزی در دیتابیس نوشته می‌شود. اگر موبایل
/// واردشده قبلاً برای مشتری دیگری ثبت شده باشد، مشتری جدید ساخته نمی‌شود و
/// همان مشتری قبلی برگردانده می‌شود. خروجی null یعنی انصراف.
Future<QuickAddCustomerResult?> showQuickAddCustomerDialog(
  BuildContext context, {
  String initialName = '',
  String initialMobile = '',
}) {
  return showDialog<QuickAddCustomerResult>(
    context: context,
    builder: (_) => _QuickAddCustomerDialog(initialName: initialName, initialMobile: initialMobile),
  );
}

class _QuickAddCustomerDialog extends StatefulWidget {
  final String initialName;
  final String initialMobile;
  const _QuickAddCustomerDialog({required this.initialName, required this.initialMobile});

  @override
  State<_QuickAddCustomerDialog> createState() => _QuickAddCustomerDialogState();
}

class _QuickAddCustomerDialogState extends State<_QuickAddCustomerDialog> {
  final _repo = CustomerRepository();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mobileCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _mobileCtrl = TextEditingController(text: widget.initialMobile);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final mobile = _mobileCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'نام مشتری را وارد کنید');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (mobile.isNotEmpty) {
        final existing = await _repo.search(mobile);
        final match = existing.where((c) => c.mobile == mobile);
        if (match.isNotEmpty) {
          if (mounted) Navigator.pop(context, QuickAddCustomerResult(match.first, true));
          return;
        }
      }
      final id = await _repo.insert(Customer(name: name, mobile: mobile));
      final saved = await _repo.getById(id) ?? Customer(id: id, name: name, mobile: mobile);
      if (mounted) Navigator.pop(context, QuickAddCustomerResult(saved, false));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'خطا در ثبت مشتری: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('افزودن مشتری جدید'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'نام مشتری'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mobileCtrl,
          decoration: const InputDecoration(labelText: 'شماره تماس'),
          keyboardType: TextInputType.phone,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ]),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('انصراف')),
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ثبت مشتری'),
        ),
      ],
    );
  }
}
