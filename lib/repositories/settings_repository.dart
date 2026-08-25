import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  final _db = DatabaseHelper.instance;

  Future<AppSettings> getSettings() async {
    final db = await _db.database;
    final rows = await db.query('settings');
    final map = <String, String>{};
    for (final row in rows) {
      map[row['key'] as String] = (row['value'] as String?) ?? '';
    }
    return AppSettings.fromKeyValueMap(map);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final db = await _db.database;
    final map = settings.toKeyValueMap();
    await db.transaction((txn) async {
      for (final entry in map.entries) {
        await txn.insert('settings', {'key': entry.key, 'value': entry.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
