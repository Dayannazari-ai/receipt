
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// وضعیت پیش‌نیازهای شناسایی تماس ورودی (همه از سمت اندروید خوانده می‌شود).
class CallerIdStatus {
  final int sdk;
  final bool roleAvailable;
  final bool roleHeld;
  final bool overlayGranted;
  final bool contactsGranted;

  const CallerIdStatus({
    required this.sdk,
    required this.roleAvailable,
    required this.roleHeld,
    required this.overlayGranted,
    required this.contactsGranted,
  });

  static const unknown = CallerIdStatus(
      sdk: 0, roleAvailable: false, roleHeld: false, overlayGranted: false, contactsGranted: false);

  /// شناسایی تماس فقط در اندروید ۱۰ به بالا پشتیبانی می‌شود.
  bool get supported => sdk >= 29 && roleAvailable;
  bool get allGranted => roleHeld && overlayGranted && contactsGranted;
}

/// پل بین Flutter و کد بومی شناسایی تماس. هیچ داده‌ی مشتری یا مخاطبی از این
/// پل عبور نمی‌کند؛ فقط وضعیت مجوزها و فرمان‌ها.
class CallerIdService {
  CallerIdService._();
  static const MethodChannel _ch = MethodChannel('receipt_app/caller_id');

  static Future<CallerIdStatus> status() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status');
      if (m == null) return CallerIdStatus.unknown;
      return CallerIdStatus(
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
        roleAvailable: m['roleAvailable'] == true,
        roleHeld: m['roleHeld'] == true,
        overlayGranted: m['overlayGranted'] == true,
        contactsGranted: m['contactsGranted'] == true,
      );
    } catch (_) {
      return CallerIdStatus.unknown;
    }
  }

  /// درخواست نقش «شناساگر تماس» (پنجره‌ی خود سیستم باز می‌شود). true = داده شد.
  static Future<bool> requestRole() async {
    try {
      return (await _ch.invokeMethod<bool>('requestRole')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// صفحه‌ی مجوز «نمایش روی برنامه‌های دیگر» را باز می‌کند.
  static Future<void> requestOverlay() async {
    try {
      await Permission.systemAlertWindow.request();
    } catch (_) {}
  }

  /// فقط برای دریافت تماس شماره‌های ذخیره‌شده؛ مخاطبین هرگز خوانده نمی‌شوند.
  /// اگر کاربر قبلاً «دیگر نپرس» زده باشد، صفحه‌ی تنظیمات برنامه باز می‌شود.
  static Future<void> requestContacts() async {
    try {
      final s = await Permission.contacts.status;
      if (s.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        await Permission.contacts.request();
      }
    } catch (_) {}
  }

  static Future<void> openAppInfo() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }

  /// 'ok' | 'no_overlay_permission' | 'failed'
  static Future<String> showPreview() async {
    try {
      return (await _ch.invokeMethod<String>('showPreview')) ?? 'failed';
    } catch (_) {
      return 'failed';
    }
  }
}
