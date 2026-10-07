import 'package:sqflite/sqflite.dart';
import '../models/backup_models.dart';
import '../repositories/finance_repository.dart';

/// بازیابی «هزینه‌های خدماتی» از Backup کامل. این توابع جدا از
/// backup_service.dart نوشته شده‌اند تا آن فایل کم‌ترین تغییر را بگیرد.

String _newUid() => FinanceRepository.generateUid().replaceFirst('fin-', 'sexp-');

/// حالت افزودن: هزینه‌ای که backup_uid آن از قبل هست دوباره اضافه نمی‌شود و
/// هیچ هزینه‌ی فعلی تغییر یا حذف نمی‌شود.
Future<void> mergeServiceExpenses(Transaction txn, List<dynamic> raw, RestoreReport report) async {
  if (raw.isEmpty) return;
  var added = 0;
  var matched = 0;
  for (final r in raw) {
    final m = Map<String, dynamic>.from(r as Map);
    final uid = (m['backup_uid'] as String?)?.trim() ?? '';
    if (uid.isNotEmpty) {
      final rows = await txn.query('service_expenses', where: 'backup_uid = ?', whereArgs: [uid], limit: 1);
      if (rows.isNotEmpty) {
        matched++;
        continue;
      }
    } else {
      m['backup_uid'] = _newUid();
    }
    m.remove('id');
    await txn.insert('service_expenses', m);
    added++;
  }
  report.notes.add('هزینه‌های خدماتی: $added جدید، $matched قبلاً موجود');
}

/// حالت جایگزینی: فقط وقتی خود Backup این بخش را دارد جایگزین می‌شود
/// (Backupهای قدیمی‌تر هزینه‌های فعلی را دست‌نخورده می‌گذارند).
Future<void> replaceServiceExpenses(Transaction txn, Map<String, dynamic> data, RestoreReport report) async {
  final raw = data['service_expenses'];
  if (raw is! List) return;
  await txn.delete('service_expenses');
  for (final r in raw) {
    final m = Map<String, dynamic>.from(r as Map);
    await txn.insert('service_expenses', m);
  }
  report.notes.add('هزینه‌های خدماتی: ${raw.length} مورد بازیابی شد');
}
