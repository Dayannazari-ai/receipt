import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/backup_models.dart';
import 'backup_service.dart';

/// خطای قابل‌نمایش به کاربر در پشتیبان‌گیری خودکار.
/// [pathProblem] یعنی مشکل از مسیر ذخیره است (تعیین نشده، در دسترس نیست،
/// یا امکان نوشتن ندارد) و تغییر مسیر می‌تواند کمک کند.
class AutoBackupException implements Exception {
  final String message;
  final bool pathProblem;
  AutoBackupException(this.message, {this.pathProblem = false});
  @override
  String toString() => message;
}

/// پشتیبان‌گیری خودکار هنگام خروج از برنامه.
///
/// - از همان «پشتیبان کامل» BackupService استفاده می‌کند (سیستم جداگانه نیست).
/// - مسیر پوشه در shared_preferences ذخیره می‌شود، نه در جدول settings؛
///   چون مخصوص همین دستگاه است و نباید وارد بکاپ/بازیابی تنظیمات شود.
/// - ابتدا فایل موقت (.tmp) ساخته و اعتبارسنجی می‌شود، بعد به نام نهایی
///   منتقل می‌شود. بکاپ‌های قبلی هرگز حذف یا بازنویسی نمی‌شوند.
class AutoBackupService {
  static const _dirKey = 'auto_backup_dir';
  static bool _running = false; // قفل ضد اجرای هم‌زمان

  final _backupService = BackupService();

  Future<String?> getBackupDir() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_dirKey)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> clearBackupDir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dirKey);
  }

  /// انتخاب پوشه توسط کاربر. فقط اگر واقعاً قابل نوشتن بود ذخیره می‌شود.
  /// خروجی: مسیر ذخیره‌شده، یا null اگر کاربر انصراف داد.
  /// اگر پوشه قابل استفاده نبود، AutoBackupException پرتاب می‌شود.
  Future<String?> chooseAndSaveDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return null;
    final err = await _checkWritable(dir);
    if (err != null) throw AutoBackupException(err, pathProblem: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dirKey, dir);
    return dir;
  }

  /// آزمایش واقعی نوشتن (ساخت، خواندن و حذف یک فایل کوچک). null = سالم.
  Future<String?> _checkWritable(String dir) async {
    try {
      if (!await Directory(dir).exists()) return 'این مسیر در دسترس نیست.';
      final probe = File(p.join(dir, '.write_test_${DateTime.now().millisecondsSinceEpoch}'));
      await probe.writeAsString('ok', flush: true);
      final back = await probe.readAsString();
      await probe.delete();
      if (back != 'ok') return 'نوشتن در این پوشه درست انجام نشد.';
      return null;
    } catch (_) {
      return 'امکان نوشتن در این پوشه نیست (دسترسی ندارد). پوشه‌ی دیگری انتخاب کنید.';
    }
  }

  String _nextName(String dir) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final base = 'AutoBackup_${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}'
        '_${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
    final ext = BackupType.full.fileExtension;
    var name = '$base.$ext';
    var i = 2;
    while ((File(p.join(dir, name)).existsSync() || File(p.join(dir, '$name.tmp')).existsSync()) && i < 100) {
      name = '${base}_$i.$ext';
      i++;
    }
    return name;
  }

  /// اجرای پشتیبان‌گیری. در صورت موفقیت فایل نهایی را برمی‌گرداند؛
  /// در صورت هر مشکل AutoBackupException پرتاب می‌شود.
  Future<File> runAutoBackup() async {
    if (_running) throw AutoBackupException('پشتیبان‌گیری در حال انجام است.');
    _running = true;
    File? source; // فایل موقتِ پشتیبان کامل در پوشه‌ی Documents برنامه
    File? tmp; // فایل .tmp داخل پوشه‌ی مقصد
    try {
      final dir = await getBackupDir();
      if (dir == null) {
        throw AutoBackupException('مسیر ذخیره‌ی پشتیبان تعیین نشده است.', pathProblem: true);
      }
      final err = await _checkWritable(dir);
      if (err != null) throw AutoBackupException(err, pathProblem: true);

      source = await _backupService.exportFull();
      final sourceEnv = await _backupService.readBackupFile(source.path);
      final sourceCheck = _backupService.validateEnvelope(sourceEnv);
      if (!sourceCheck.isValid) {
        throw AutoBackupException('پشتیبان تهیه‌شده معتبر نبود: ${sourceCheck.errors.join(' | ')}');
      }
      final sourceSize = await source.length();

      final name = _nextName(dir);
      tmp = File(p.join(dir, '$name.tmp'));
      await source.copy(tmp.path);
      if (await tmp.length() != sourceSize) {
        throw AutoBackupException('کپی فایل پشتیبان کامل انجام نشد.', pathProblem: true);
      }
      final copyEnv = await _backupService.readBackupFile(tmp.path);
      final copyCheck = _backupService.validateEnvelope(copyEnv);
      if (!copyCheck.isValid) {
        throw AutoBackupException('فایل پشتیبان ذخیره‌شده معتبر نبود: ${copyCheck.errors.join(' | ')}');
      }

      final finalFile = File(p.join(dir, name));
      await tmp.rename(finalFile.path);
      tmp = null; // منتقل شد؛ دیگر چیزی برای پاک‌کردن نیست
      return finalFile;
    } on AutoBackupException {
      rethrow;
    } catch (e) {
      throw AutoBackupException('$e', pathProblem: e is FileSystemException);
    } finally {
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      try {
        if (source != null && await source.exists()) await source.delete();
      } catch (_) {}
      _running = false;
    }
  }
}
