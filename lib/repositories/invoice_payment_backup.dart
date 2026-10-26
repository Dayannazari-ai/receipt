import 'package:sqflite/sqflite.dart';
import '../models/backup_models.dart';
import 'finance_repository.dart';

/// پشتیبان‌گیری/بازیابی «پرداخت‌ها و چک‌های فاکتور» (جدول invoice_payments).
/// جدا از backup_service.dart نوشته شده تا آن فایل کم‌ترین تغییر را بگیرد.

String _newUid() => FinanceRepository.generateUid().replaceFirst('fin-', 'ipay-');

/// حالت افزودن (merge): ردیفی که backup_uid آن از قبل هست یا همان چکِ همان
/// فاکتور (مبلغ و سررسید یکسان) دوباره اضافه نمی‌شود؛ هیچ ردیف فعلی تغییر
/// نمی‌کند. [invoiceIdMap]: شناسه‌ی قدیمی فاکتور در فایل ← شناسه‌ی مقصد.
Future<void> mergeInvoicePayments(
  Transaction txn,
  List<dynamic> raw,
  Map<int, int> invoiceIdMap,
  RestoreReport report,
) async {
  if (raw.isEmpty) return;
  var added = 0;
  var matched = 0;
  for (final r in raw) {
    final m = Map<String, dynamic>.from(r as Map);
    final oldInvoice = (m['invoice_id'] as num?)?.toInt();
    final newInvoice = oldInvoice == null ? null : invoiceIdMap[oldInvoice];
    if (newInvoice == null) {
      report.notes.add('یک پرداخت/چک به دلیل نبود فاکتور متناظر نادیده گرفته شد.');
      continue;
    }
    final uid = (m['backup_uid'] as String?)?.trim() ?? '';
    if (uid.isNotEmpty) {
      final rows = await txn.query('invoice_payments', where: 'backup_uid = ?', whereArgs: [uid], limit: 1);
      if (rows.isNotEmpty) {
        matched++;
        continue;
      }
    } else {
      m['backup_uid'] = _newUid();
    }
    final dup = await txn.query(
      'invoice_payments',
      where: "invoice_id = ? AND method = ? AND amount = ? AND COALESCE(due_date, '') = ?",
      whereArgs: [newInvoice, m['method'], m['amount'], (m['due_date'] as String?) ?? ''],
      limit: 1,
    );
    if (dup.isNotEmpty) {
      matched++;
      continue;
    }
    m.remove('id');
    m['invoice_id'] = newInvoice;
    await txn.insert('invoice_payments', m);
    added++;
  }
  report.notes.add('پرداخت‌ها و چک‌های فاکتور: $added جدید، $matched قبلاً موجود');
}

/// حالت جایگزینی: فقط برای Backup «فاکتورها» و «کامل». چون فاکتورها با
/// شناسه‌ی اصلی‌شان جایگزین می‌شوند، ردیف‌های این جدول هم با همان شناسه‌ها
/// بازیابی می‌شوند. باید بعد از `defer_foreign_keys` و داخل همان تراکنش
/// صدا زده شود (بررسی کلید خارجی تا پایان تراکنش به تعویق افتاده است).
/// اگر Backup قدیمی باشد (بدون این بخش)، ردیف‌های فعلی پاک می‌شوند و چک‌های
/// آن فاکتورها پیگیری نمی‌شوند (مطابق قاعده‌ی فاکتورهای قبل از این قابلیت).
Future<void> replaceInvoicePayments(
  Transaction txn,
  BackupType type,
  Map<String, dynamic> data,
  RestoreReport report,
) async {
  if (type != BackupType.invoices && type != BackupType.full) return;
  await txn.delete('invoice_payments');
  final raw = data['invoice_payments'];
  if (raw is! List) return;
  for (final r in raw) {
    await txn.insert('invoice_payments', Map<String, dynamic>.from(r as Map));
  }
  report.notes.add('پرداخت‌ها و چک‌های فاکتور: ${raw.length} مورد بازیابی شد');
}
