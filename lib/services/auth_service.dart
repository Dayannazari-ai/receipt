import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

/// مدیریت رمز عبور اختیاری برنامه. رمز به‌صورت ساده در جدول settings
/// (که از قبل کلید/مقدار دلخواه را پشتیبانی می‌کند) ذخیره می‌شود.
class AuthService {
  static const _key = 'app_password';

  Future<String?> getPassword() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [_key]);
    if (rows.isEmpty) return null;
    final v = rows.first['value'] as String?;
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<bool> hasPassword() async => (await getPassword()) != null;

  Future<void> setPassword(String password) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('settings', {'key': _key, 'value': password},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removePassword() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('settings', where: 'key = ?', whereArgs: [_key]);
  }

  Future<bool> verify(String input) async {
    final pass = await getPassword();
    return pass != null && pass == input;
  }
}
