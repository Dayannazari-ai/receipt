import '../database/database_helper.dart';
import '../models/invoice.dart';

/// فقط‌خواندنی: سوابق مراجعه‌ی یک خودرو از روی خودِ فاکتورها
/// (جدول جدید یا ستون جدید ندارد). پیش‌فاکتور و فاکتور باطل‌شده حساب نمی‌شوند.
class InvoiceVisitRepository {
  final _db = DatabaseHelper.instance;

  /// آخرین کیلومتر ثبت‌شده‌ی یک خودرو؛ بر اساس تاریخ مراجعه و بعد ترتیب ثبت
  /// (نه بزرگ‌ترین عدد). اگر سابقه‌ای نباشد null.
  Future<int?> getLastMileage(int vehicleId) async {
    final db = await _db.database;
    final rows = await db.query(
      'invoices',
      columns: ['mileage_km'],
      where: 'vehicle_id = ? AND is_deleted = 0 AND is_draft = 0 AND mileage_km IS NOT NULL AND mileage_km > 0',
      whereArgs: [vehicleId],
      orderBy: 'issue_date DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['mileage_km'] as num?)?.toInt();
  }

  /// آخرین مراجعه‌ی قبلی همان خودرو نسبت به فاکتوری با تاریخ [issueDate].
  /// برای فاکتور ذخیره‌شده، [excludeInvoiceId] خودِ آن فاکتور است. برای
  /// پیش‌نمایش (هنوز ذخیره نشده) null بدهید.
  Future<Invoice?> getPreviousVisit({
    required int vehicleId,
    required String issueDate,
    int? excludeInvoiceId,
  }) async {
    final db = await _db.database;
    final String where;
    final List<Object?> args;
    if (excludeInvoiceId == null) {
      where = 'vehicle_id = ? AND is_deleted = 0 AND is_draft = 0 AND issue_date <= ?';
      args = [vehicleId, issueDate];
    } else {
      where = 'vehicle_id = ? AND is_deleted = 0 AND is_draft = 0 AND id != ? '
          'AND (issue_date < ? OR (issue_date = ? AND id < ?))';
      args = [vehicleId, excludeInvoiceId, issueDate, issueDate, excludeInvoiceId];
    }
    final rows = await db.query(
      'invoices',
      where: where,
      whereArgs: args,
      orderBy: 'issue_date DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Invoice.fromMap(rows.first);
  }
}
