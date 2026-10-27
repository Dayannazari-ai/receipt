import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/app_settings.dart';
import '../repositories/invoice_payment_repository.dart';
import '../repositories/settings_repository.dart';
import '../screens/invoices/invoice_detail_screen.dart';
import '../utils/currency_formatter.dart';
import '../utils/persian_date.dart';

class _Planned {
  final int id;
  final String title;
  final String body;
  final DateTime at;
  final bool repeatDaily;
  final int invoiceId;
  const _Planned(this.id, this.title, this.body, this.at, this.repeatDaily, this.invoiceId);
}

/// اعلان واقعی اندروید برای چک‌های پرداخت‌نشده.
///
/// برای هر چک (ساعت [notifyHour] به وقت گوشی):
///  - ۲ روز قبل از سررسید، ۱ روز قبل، و خودِ روز سررسید (هرکدام یک‌بار)
///  - از روز بعد از سررسید، هر روز (تکرار روزانه) تا پرداخت ثبت شود
///
/// همه‌ی اعلان‌ها از روی اطلاعات واقعی دیتابیس ساخته می‌شوند و شناسه‌ی هر
/// اعلان فقط از شناسه‌ی پرداخت می‌آید (paymentId * 4 + شماره‌ی نوبت). هر بار
/// که فهرست چک‌های پرداخت‌نشده تغییر کند (چک جدید، پرداخت، ابطال، بازیابی
/// بکاپ)، همه‌ی اعلان‌های قبلی لغو و از نو زمان‌بندی می‌شوند؛ پس اعلان تکراری
/// یا اعلانِ چک پرداخت‌شده نمی‌ماند و به شناسه‌ی قدیمی گوشی وابسته نیستیم.
/// یادآوری داخل برنامه (کادر بالای رسید) کاملاً مستقل از این اعلان‌هاست.
class ChequeNotificationService {
  ChequeNotificationService._();

  static const int notifyHour = 9;
  static const int _maxScheduled = 400; // سقف امن تعداد آلارم‌های اندروید
  static const String _channelId = 'cheque_reminders';

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// فقط وقتی true است که برنامه قفل نیست؛ باز کردن فاکتور از اعلان نباید
  /// قفل رمز را دور بزند.
  static bool appUnlocked = false;

  /// null = هنوز بررسی نشده، false = مجوز اعلان داده نشده/خاموش است.
  static final ValueNotifier<bool?> notificationsAllowed = ValueNotifier<bool?>(null);

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static bool _initFailed = false;
  static bool _askedThisSession = false;
  static bool _syncing = false;
  static String _lastSignature = '';
  static int? _pendingInvoiceId;

  static Future<void> init() async {
    if (_inited || _initFailed) return;
    try {
      // اعلان‌ها با لحظه‌ی مطلق (UTC) زمان‌بندی می‌شوند؛ به منطقه‌ی زمانی
      // دستگاه یا بسته‌ی دیگری نیاز نیست.
      tz.setLocalLocation(tz.UTC);
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: _onTap,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _pendingInvoiceId = int.tryParse(launch!.notificationResponse?.payload ?? '');
      }
      _inited = true;
    } catch (_) {
      _initFailed = true;
    }
  }

  static void _onTap(NotificationResponse r) {
    _pendingInvoiceId = int.tryParse(r.payload ?? '');
    openPendingIfPossible();
  }

  /// اگر کاربر روی اعلان زده و برنامه قفل نیست، جزئیات همان فاکتور باز می‌شود.
  static void openPendingIfPossible() {
    final id = _pendingInvoiceId;
    if (id == null || !appUnlocked) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _pendingInvoiceId = null;
    nav.push(MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoiceId: id)));
  }

  /// بعد از برگشت به برنامه صدا زده می‌شود تا وضعیت مجوز و زمان‌بندی دوباره
  /// بررسی شود (کاربر ممکن است مجوز را در تنظیمات گوشی عوض کرده باشد).
  static void invalidate() => _lastSignature = '';

  static Future<bool> _permissionOk() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    var ok = await android.areNotificationsEnabled() ?? false;
    if (!ok && !_askedThisSession) {
      _askedThisSession = true;
      ok = await android.requestNotificationsPermission() ?? false;
    }
    notificationsAllowed.value = ok;
    return ok;
  }

  /// همگام‌سازی اعلان‌ها با فهرست فعلی چک‌های پرداخت‌نشده.
  static Future<void> sync(List<ChequeReminder> items) async {
    if (_syncing) return;
    _syncing = true;
    var sig = '';
    try {
      await init();
      if (!_inited) return;
      sig = items
          .map((c) =>
              '${c.paymentId}|${c.dueDate.millisecondsSinceEpoch}|${c.customerName}|${c.amount}|${c.invoiceNumber}')
          .join(';');
      if (sig == _lastSignature) return;

      if (items.isEmpty) {
        await _plugin.cancelAll();
        _lastSignature = sig;
        return;
      }
      if (!await _permissionOk()) {
        _lastSignature = sig;
        return;
      }

      final settings = await SettingsRepository().getSettings();
      await _plugin.cancelAll();
      final now = DateTime.now();
      var budget = _maxScheduled;
      for (final c in items) {
        for (final n in _planFor(c, now, settings.currency)) {
          if (budget <= 0) break;
          await _schedule(n);
          budget--;
        }
      }
      _lastSignature = sig;
    } catch (_) {
      _lastSignature = sig; // خطا نباید هر چند ثانیه تکرار شود
    } finally {
      _syncing = false;
    }
  }

  static List<_Planned> _planFor(ChequeReminder c, DateTime now, Currency currency) {
    final name = c.customerName.isEmpty ? 'مشتری' : c.customerName;
    final date = PersianDateUtil.formatDateNumeric(c.dueDate.toIso8601String());
    final info =
        'فاکتور ${PersianDateUtil.toPersianDigits(c.invoiceNumber)} — ${CurrencyFormatter.format(c.amount, currency)}';
    final promise = c.isPromise;
    final what = promise ? 'پرداخت' : 'چک';
    final dueBody = promise
        ? 'آقای/خانم $name، موعد پرداخت توافقی شما در تاریخ $date می‌باشد. جهت یادآوری و پیگیری پرداخت.\n$info'
        : 'آقای/خانم $name، موعد پرداخت یا سررسید چک شما در تاریخ $date می‌باشد. جهت یادآوری و پیگیری پرداخت.\n$info';
    final overdueBody = promise
        ? 'پرداخت توافقی $name با سررسید $date هنوز دریافت نشده است. برای پیگیری با مشتری تماس بگیرید.\n$info'
        : 'چک $name با سررسید $date هنوز پرداخت نشده است. برای پیگیری پرداخت با مشتری تماس بگیرید.\n$info';

    DateTime at(int dayOffset) =>
        DateTime(c.dueDate.year, c.dueDate.month, c.dueDate.day + dayOffset, notifyHour);

    final base = c.paymentId * 4;
    final margin = now.add(const Duration(minutes: 1));
    final out = <_Planned>[];

    if (at(-2).isAfter(margin)) {
      out.add(_Planned(base, 'یادآوری $what: ۲ روز تا سررسید', dueBody, at(-2), false, c.invoiceId));
    }
    if (at(-1).isAfter(margin)) {
      out.add(_Planned(base + 1, 'یادآوری $what: فردا سررسید', dueBody, at(-1), false, c.invoiceId));
    }
    if (at(0).isAfter(margin)) {
      out.add(_Planned(base + 2, 'سررسید $what امروز است', dueBody, at(0), false, c.invoiceId));
    }

    // از روز بعد از سررسید هر روز تا پرداخت. اگر سررسید گذشته، از نزدیک‌ترین
    // ساعت ۹ بعدی شروع می‌شود.
    var start = at(1);
    final today9 = DateTime(now.year, now.month, now.day, notifyHour);
    final next9 =
        today9.isAfter(margin) ? today9 : DateTime(now.year, now.month, now.day + 1, notifyHour);
    if (start.isBefore(next9)) start = next9;
    out.add(_Planned(base + 3, promise ? 'پرداخت توافقی سررسیدگذشته' : 'چک سررسیدگذشته پرداخت نشده', overdueBody, start, true, c.invoiceId));
    return out;
  }

  static Future<void> _schedule(_Planned n) async {
    final when = tz.TZDateTime.from(n.at, tz.UTC);
    await _plugin.zonedSchedule(
      n.id,
      n.title,
      n.body,
      when,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'یادآوری چک‌ها',
          channelDescription: 'یادآوری سررسید چک‌های پرداخت‌نشده',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(n.body),
        ),
      ),
      // زمان‌بندی «تقریبی»: مجوز ویژه‌ی آلارم دقیق لازم ندارد؛ اندروید ممکن
      // است اعلان را چند دقیقه (در Doze گاهی بیشتر) دیرتر نمایش دهد.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: '${n.invoiceId}',
      matchDateTimeComponents: n.repeatDaily ? DateTimeComponents.time : null,
    );
  }
}
