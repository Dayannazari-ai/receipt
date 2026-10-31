
import 'package:flutter/material.dart';
import '../../services/caller_id_service.dart';

/// صفحه‌ی فعال‌سازی و وضعیت «شناسایی تماس ورودی».
/// این صفحه هیچ داده‌ی مشتری یا مخاطبی را نمی‌خواند یا تغییر نمی‌دهد.
class CallerIdSettingsScreen extends StatefulWidget {
  const CallerIdSettingsScreen({super.key});
  @override
  State<CallerIdSettingsScreen> createState() => _CallerIdSettingsScreenState();
}

class _CallerIdSettingsScreenState extends State<CallerIdSettingsScreen> with WidgetsBindingObserver {
  CallerIdStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await CallerIdService.status();
    if (!mounted) return;
    setState(() => _status = s);
  }

  void _msg(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _enableRole() => _run(() async {
        final ok = await CallerIdService.requestRole();
        if (!ok && mounted) _msg('فعال‌سازی انجام نشد. در پنجره‌ی سیستم باید این برنامه را انتخاب و تأیید کنید.');
      });

  Future<void> _enableOverlay() => _run(() => CallerIdService.requestOverlay());

  Future<void> _enableContacts() => _run(() => CallerIdService.requestContacts());

  Future<void> _preview() async {
    final r = await CallerIdService.showPreview();
    if (!mounted) return;
    if (r == 'ok') {
      _msg('پیش‌نمایش نمایش داده شد (۲۵ ثانیه یا با دکمه‌ی بستن بسته می‌شود).');
    } else if (r == 'no_overlay_permission') {
      _msg('ابتدا مجوز «نمایش روی برنامه‌های دیگر» را فعال کنید.');
    } else {
      _msg('پیش‌نمایش نمایش داده نشد.');
    }
  }

  Widget _step({
    required String title,
    required String hint,
    required bool done,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? Colors.green : Colors.grey),
        title: Text(title),
        subtitle: Text(hint, style: const TextStyle(fontSize: 12)),
        trailing: done ? null : TextButton(onPressed: _busy ? null : onAction, child: Text(actionLabel)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('شناسایی تماس ورودی')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                'هنگام تماس ورودی، اگر شماره متعلق به یکی از مشتریان ثبت‌شده در همین برنامه باشد، '
                'نام مشتری و مشخصات خودروی او روی صفحه نمایش داده می‌شود. '
                'اطلاعات فقط از بانک مشتریان همین برنامه خوانده می‌شود و تغییر نمی‌کند.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'مخاطبین شخصی گوشی هرگز وارد برنامه نمی‌شوند، خوانده یا ذخیره نمی‌شوند و تغییری در آن‌ها ایجاد نمی‌شود.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (s.sdk == 0)
                _infoBox('وضعیت گوشی خوانده نشد. این قابلیت فقط روی اندروید در دسترس است.', Colors.orange)
              else if (!s.supported)
                _infoBox('این قابلیت فقط روی اندروید ۱۰ به بالا کار می‌کند.', Colors.orange)
              else ...[
                _step(
                  title: '۱. شناساگر تماس',
                  hint: 'سیستم یک‌بار تأیید می‌گیرد. برنامه‌ی تماس گوشی شما عوض نمی‌شود.',
                  done: s.roleHeld,
                  actionLabel: 'فعال‌سازی',
                  onAction: _enableRole,
                ),
                _step(
                  title: '۲. نمایش روی برنامه‌های دیگر',
                  hint: 'برای نمایش پنجره‌ی اطلاعات روی صفحه‌ی تماس.',
                  done: s.overlayGranted,
                  actionLabel: 'فعال‌سازی',
                  onAction: _enableOverlay,
                ),
                _step(
                  title: '۳. دسترسی مخاطبین (فقط برای شناسایی)',
                  hint: 'بدون این دسترسی، سیستم تماس شماره‌های ذخیره‌شده در مخاطبین را به برنامه اطلاع نمی‌دهد. '
                      'مخاطبین خوانده یا ذخیره نمی‌شوند.',
                  done: s.contactsGranted,
                  actionLabel: 'فعال‌سازی',
                  onAction: _enableContacts,
                ),
                const SizedBox(height: 8),
                if (s.allGranted)
                  _infoBox(
                      'تنظیمات کامل است. عملکرد واقعی را باید با یک تماس آزمایشی از شماره‌ی یکی از مشتریان بررسی کنید.',
                      Colors.green),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('پیش‌نمایش ظاهر پنجره (نمونه‌ی آزمایشی)'),
                  onPressed: _preview,
                ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              const Text('اگر پنجره نمایش داده نشد', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'بعضی گوشی‌ها (مثل شیائومی) محدودیت اضافه دارند. در تنظیمات برنامه این موارد را بررسی کنید: '
                '«نمایش پنجره‌ی پاپ‌آپ در پس‌زمینه» روشن، «شروع خودکار» روشن، و صرفه‌جویی باتری روی «بدون محدودیت».',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.settings_outlined),
                label: const Text('باز کردن تنظیمات برنامه'),
                onPressed: CallerIdService.openAppInfo,
              ),
            ]),
    );
  }

  Widget _infoBox(String text, MaterialColor color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.shade200),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );
}
