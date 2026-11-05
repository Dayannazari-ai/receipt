import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// نتیجه‌ی فرم ساخت دسته.
class CategoryInput {
  final String name;
  final String prefix; // لاتین، بزرگ‌حرف، بدون خط تیره
  const CategoryInput(this.name, this.prefix);
}

final RegExp _prefixRe = RegExp(r'^[A-Za-z][A-Za-z0-9]{0,4}$');
const String _prefixRule = 'پیشوند باید ۱ تا ۵ نویسه‌ی لاتین (حرف یا رقم) باشد و با حرف شروع شود؛ مثل PDR';

Widget _prefixField(TextEditingController c, String? error, {bool autofocus = false}) => TextField(
      controller: c,
      autofocus: autofocus,
      maxLength: 5,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
      decoration: InputDecoration(
        labelText: 'پیشوند کد (لاتین، مثل PDR)',
        helperText: 'با کیبورد انگلیسی بنویس. کد خدمات این دسته مثل PDR-0001 ساخته می‌شود.',
        helperMaxLines: 2,
        counterText: '',
        errorText: error,
      ),
    );

/// فرم ساخت دسته: نام + پیشوند کد (کاربر خودش تعیین می‌کند).
Future<CategoryInput?> askCategoryNameAndPrefix(BuildContext context) {
  final nameCtrl = TextEditingController();
  final prefixCtrl = TextEditingController();
  String? nameError;
  String? prefixError;
  return showDialog<CategoryInput>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('دسته‌بندی جدید'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: 'نام دسته‌بندی', errorText: nameError),
            ),
            const SizedBox(height: 12),
            _prefixField(prefixCtrl, prefixError),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final p = prefixCtrl.text.trim().toUpperCase();
              final nErr = name.isEmpty ? 'نام دسته‌بندی را وارد کنید' : null;
              final pErr = _prefixRe.hasMatch(p) ? null : _prefixRule;
              if (nErr != null || pErr != null) {
                setState(() {
                  nameError = nErr;
                  prefixError = pErr;
                });
                return;
              }
              Navigator.pop(ctx, CategoryInput(name, p));
            },
            child: const Text('افزودن'),
          ),
        ],
      ),
    ),
  );
}

/// فرم تعیین/تغییر پیشوند یک دسته. خروجی: پیشوند بزرگ‌حرف، یا null در صورت انصراف.
Future<String?> askCategoryPrefix(BuildContext context, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('پیشوند کد خدمات'),
        content: SingleChildScrollView(child: _prefixField(ctrl, error, autofocus: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          TextButton(
            onPressed: () {
              final p = ctrl.text.trim().toUpperCase();
              if (!_prefixRe.hasMatch(p)) {
                setState(() => error = _prefixRule);
                return;
              }
              Navigator.pop(ctx, p);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    ),
  );
}

/// پیام خطا وسط صفحه.
Future<void> showCategoryError(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('انجام نشد'),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه'))],
    ),
  );
}
