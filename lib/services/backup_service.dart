import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';

class BackupService {
  Future<File> createBackup() async {
    final dbHelper = DatabaseHelper.instance;
    await dbHelper.database;
    final dbPath = await dbHelper.getDbFilePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) throw StateError('فایل دیتابیس یافت نشد');

    final backupDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '${backupDir.path}/receipt_backup_$timestamp.db';
    return dbFile.copy(backupPath);
  }

  Future<void> shareBackup(File backupFile) async {
    await Share.shareXFiles([XFile(backupFile.path)], text: 'فایل پشتیبان اطلاعات');
  }

  /// کاربر فایل .db را با فایل‌منیجر گوشی به پوشه Documents برنامه منتقل می‌کند
  /// و مسیر کامل آن را وارد می‌کند.
  Future<void> restoreFromPath(String pickedPath) async {
    final dbHelper = DatabaseHelper.instance;
    final dbPath = await dbHelper.getDbFilePath();
    await dbHelper.close();
    final pickedFile = File(pickedPath);
    if (!await pickedFile.exists()) throw StateError('فایل یافت نشد');
    await pickedFile.copy(dbPath);
    await dbHelper.database;
  }
}
