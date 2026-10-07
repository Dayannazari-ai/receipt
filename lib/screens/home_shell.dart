import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auto_backup_service.dart';
import 'receipt/receipt_screen.dart';
import 'customers/customers_screen.dart';
import 'products/products_screen.dart';
import 'services/services_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/settings_screen.dart';

enum _FailAction { cancel, retry, changePath }

/// انتخاب کاربر در هشدار «برنامه خالی است».
enum _EmptyAction { stay, exitOnly, backupAndExit }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 5; // شروع از صفحه‌ی «رسید»

  final _autoBackup = AutoBackupService();
  bool _busy = false; // قفل ضد کلیک چندباره / بکاپ هم‌زمان

  final _pages = const [
    SettingsScreen(),
    CustomersScreen(),
    ProductsScreen(),
    ServicesScreen(),
    ReportsScreen(),
    ReceiptScreen(),
  ];

  final _titles = const ['تنظیمات', 'مشتریان', 'محصولات', 'خدمات', 'گزارش', 'رسید'];

  final _icons = const [
    Icons.settings_outlined,
    Icons.person_outline,
    Icons.shopping_cart_outlined,
    Icons.build_outlined,
    Icons.bar_chart_outlined,
    Icons.add_shopping_cart,
  ];

  // ==================== رهگیری خروج ====================

  /// دکمه‌ی بازگشت روی صفحه‌ی ریشه: هیچ‌وقت مستقیم خارج نمی‌شود؛
  /// پنجره‌ی تأیید نشان داده می‌شود.
  Future<bool> _onWillPop() async {
    if (!_busy) _confirmExit();
    return false;
  }

  /// هشدار وقتی برنامه کاملاً خالی است (مثلاً بعد از نصب تازه و قبل از
  /// بازیابی): پشتیبان خالی ممکن است پشتیبان‌های سالم قبلی را جایگزین کند.
  Future<_EmptyAction?> _showEmptyDataWarning() {
    return showDialog<_EmptyAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('هشدار: برنامه خالی است'),
        content: const Text(
            'در برنامه هنوز هیچ مشتری، کالا یا فاکتوری ثبت نشده است.\n\n'
            'اگر الان پشتیبان‌گیری کنید، از اطلاعات خالی پشتیبان گرفته می‌شود و ممکن است '
            'پشتیبان‌های سالم قبلی شما جایگزین شوند.\n\n'
            'اگر قبلاً پشتیبان دارید، اول آن را از «تنظیمات ← پشتیبان‌گیری و بازیابی» '
            'بازیابی کنید و بعد خارج شوید.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, _EmptyAction.stay), child: const Text('ماندن در برنامه')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, _EmptyAction.exitOnly),
              child: const Text('خروج بدون پشتیبان‌گیری')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, _EmptyAction.backupAndExit),
              child: const Text('پشتیبان‌گیری و خروج', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (await _autoBackup.isAppDataEmpty()) {
      if (!mounted) return;
      final choice = await _showEmptyDataWarning();
      if (!mounted) return;
      if (choice == null || choice == _EmptyAction.stay) return;
      if (choice == _EmptyAction.exitOnly) {
        await SystemNavigator.pop(); // بدون ساخت پشتیبان خالی
        return;
      }
      await _backupAndExit(); // کاربر آگاهانه پشتیبان خالی را خواسته
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خروج از برنامه'),
        content: const Text('آیا می‌خواهید از برنامه خارج شوید؟\nقبل از خروج یک پشتیبان کامل گرفته می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('پشتیبان‌گیری و خروج')),
        ],
      ),
    );
    if (go == true && mounted) await _backupAndExit();
  }

  /// اگر مسیر تعیین نشده باشد به کاربر اطلاع می‌دهد و امکان تعیین مسیر می‌دهد.
  /// true = الان مسیر معتبر داریم.
  Future<bool> _askAndChooseDir({String? reason}) async {
    final choose = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسیر پشتیبان'),
        content: Text(reason ??
            'مسیر ذخیره‌ی پشتیبان هنوز تعیین نشده است. برای خروج با پشتیبان‌گیری، یک پوشه انتخاب کنید.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تعیین مسیر')),
        ],
      ),
    );
    if (choose != true || !mounted) return false;
    try {
      final dir = await _autoBackup.chooseAndSaveDir();
      return dir != null;
    } on AutoBackupException catch (e) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('این مسیر قابل استفاده نیست'),
          content: Text('${e.message}\nخروج از برنامه لغو شد.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه'))],
        ),
      );
      return false;
    }
  }

  Future<_FailAction> _showFailure(AutoBackupException e) async {
    final r = await showDialog<_FailAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('پشتیبان‌گیری انجام نشد'),
        content: Text('پشتیبان‌گیری انجام نشد. خروج از برنامه لغو شد.\n\n${e.message}\n\n'
            'پشتیبان‌های قبلی شما دست‌نخورده ماندند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, _FailAction.cancel), child: const Text('بستن')),
          if (e.pathProblem)
            TextButton(onPressed: () => Navigator.pop(ctx, _FailAction.changePath), child: const Text('تغییر مسیر')),
          TextButton(onPressed: () => Navigator.pop(ctx, _FailAction.retry), child: const Text('تلاش مجدد')),
        ],
      ),
    );
    return r ?? _FailAction.cancel;
  }

  Future<void> _backupAndExit() async {
    if (_busy) return;
    setState(() => _busy = true);
    var exiting = false;
    try {
      while (true) {
        if (await _autoBackup.getBackupDir() == null) {
          if (!await _askAndChooseDir()) return; // خروج لغو شد
          if (!mounted) return;
        }

        final done = ValueNotifier<bool>(false);
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              content: ValueListenableBuilder<bool>(
                valueListenable: done,
                builder: (_, ok, __) => Row(children: [
                  ok
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(width: 16),
                  Expanded(child: Text(ok ? 'پشتیبان با موفقیت ذخیره شد' : 'در حال تهیه پشتیبان کامل…')),
                ]),
              ),
            ),
          ),
        );

        AutoBackupException? failure;
        try {
          await _autoBackup.runAutoBackup();
          done.value = true;
          await Future.delayed(const Duration(milliseconds: 900));
        } on AutoBackupException catch (e) {
          failure = e;
        } catch (e) {
          failure = AutoBackupException('$e');
        }

        if (mounted) Navigator.of(context, rootNavigator: true).pop(); // بستن پنجره‌ی پیشرفت
        if (!mounted) return;

        if (failure == null) {
          exiting = true;
          await SystemNavigator.pop(); // فقط بعد از موفقیت کامل
          return;
        }

        final action = await _showFailure(failure);
        if (!mounted) return;
        if (action == _FailAction.cancel) return;
        if (action == _FailAction.changePath) {
          if (!await _askAndChooseDir(reason: 'یک پوشه‌ی دیگر برای ذخیره‌ی پشتیبان انتخاب کنید.')) return;
          if (!mounted) return;
        }
        // retry یا بعد از تغییر مسیر: دوباره از ابتدای حلقه
      }
    } finally {
      if (mounted && !exiting) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: List.generate(
            _titles.length,
            (i) => NavigationDestination(icon: Icon(_icons[i]), label: _titles[i]),
          ),
        ),
      ),
    );
  }
}
