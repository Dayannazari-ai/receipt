import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import 'service_repository.dart';

/// وضعیت کدهای یک سری از خدمات (مثلاً M-).
class ServiceCodeInfo {
  final String prefix;
  final List<String> freeCodes; // صعودی
  final String suggested;
  const ServiceCodeInfo({required this.prefix, required this.freeCodes, required this.suggested});
}

class _SvcRow {
  final int id;
  final String code;
  final bool deleted;
  final String key;
  const _SvcRow(this.id, this.code, this.deleted, this.key);
}

class _SvcHistory {
  final Set<int> ids; // خدماتی که در اقلام فاکتور آمده‌اند
  final Set<String> keys; // کدهای ثبت‌شده روی اقلام فاکتور
  final bool known; // آیا سوابق فاکتور قابل تشخیص بود؟
  const _SvcHistory(this.ids, this.keys, this.known);
}

/// همان معماری ProductRepository (loadCodeInfo / _ensureCodeFree) برای خدمات.
class ServiceCodeManager {
  final _db = DatabaseHelper.instance;

  /// کلید مقایسه: بدون فاصله، حروف بزرگ، ارقام فارسی/عربی → انگلیسی.
  static String codeKey(String code) {
    final b = StringBuffer();
    for (final r in code.runes) {
      if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(r - 0x06F0 + 0x30);
      } else if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(r - 0x0660 + 0x30);
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  static final RegExp _simpleCode = RegExp(r'^[A-Za-z0-9\-]+$');

  static _SvcRow _rowFrom(Map<String, Object?> r) {
    final code = (r['code'] as String?) ?? '';
    return _SvcRow((r['id'] as num).toInt(), code, ((r['is_deleted'] as num?)?.toInt() ?? 0) == 1, codeKey(code));
  }

  static Future<List<_SvcRow>> _loadRows(DatabaseExecutor ex) async {
    final rows = await ex.query('services', columns: ['id', 'code', 'is_deleted']);
    return rows.map(_rowFrom).toList();
  }

  /// ردیف‌هایی که کدشان با [code] هم‌ارز است. برای کدهای ساده‌ی لاتین فقط
  /// همان ردیف‌ها خوانده می‌شود (ورود نرخ‌نامه با هزاران ثبت کند نشود).
  static Future<List<_SvcRow>> _conflicts(DatabaseExecutor ex, String code, {int? excludeId}) async {
    final key = codeKey(code);
    final trimmed = code.trim();
    final List<Map<String, Object?>> rows;
    if (_simpleCode.hasMatch(trimmed)) {
      rows = await ex.query('services',
          columns: ['id', 'code', 'is_deleted'], where: 'code = ? COLLATE NOCASE', whereArgs: [trimmed]);
    } else {
      rows = await ex.query('services', columns: ['id', 'code', 'is_deleted']);
    }
    return rows.map(_rowFrom).where((r) => r.id != excludeId && r.key == key).toList();
  }

  /// سوابق فاکتور. ستون‌های موجود invoice_items بررسی می‌شود؛ اگر هیچ‌کدام از
  /// service_id و item_code نباشد، چیزی «آزاد» حساب نمی‌شود (امن‌ترین حالت).
  static Future<_SvcHistory> _loadHistory(DatabaseExecutor ex) async {
    final info = await ex.rawQuery('PRAGMA table_info(invoice_items)');
    final cols = info.map((r) => (r['name'] as String?) ?? '').toSet();
    final ids = <int>{};
    final keys = <String>{};
    final hasId = cols.contains('service_id');
    final hasCode = cols.contains('item_code');
    if (hasId) {
      for (final r in await ex.rawQuery('SELECT DISTINCT service_id FROM invoice_items WHERE service_id IS NOT NULL')) {
        ids.add((r['service_id'] as num).toInt());
      }
    }
    if (hasCode) {
      for (final r in await ex.rawQuery(
          "SELECT DISTINCT item_code FROM invoice_items WHERE item_code IS NOT NULL AND item_code != ''")) {
        keys.add(codeKey((r['item_code'] as String?) ?? ''));
      }
    }
    return _SvcHistory(ids, keys, hasId || hasCode);
  }

  /// خدمت حذف‌شده فقط وقتی کدش آزاد می‌شود که نه خودش و نه کدش در فاکتور آمده باشد.
  static bool _reclaimable(_SvcRow r, _SvcHistory h) =>
      h.known && r.deleted && !h.ids.contains(r.id) && !h.keys.contains(r.key);

  /// آیا این کد برای خدمت دیگری (غیر از [excludeId]) «گرفته‌شده» است؟
  /// کد خدمت حذف‌شده‌ی بدون سابقه‌ی فاکتور گرفته‌شده حساب نمی‌شود.
  static Future<bool> isTaken(DatabaseExecutor ex, String code, {int? excludeId}) async {
    if (codeKey(code).isEmpty) return false;
    final conflicts = await _conflicts(ex, code, excludeId: excludeId);
    if (conflicts.isEmpty) return false;
    final h = await _loadHistory(ex);
    return conflicts.any((c) => !_reclaimable(c, h));
  }

  /// داخل تراکنش، قبل از درج/ویرایش صدا زده می‌شود. اگر کد آزاد باشد (یا فقط
  /// مال خدمت حذف‌شده‌ی بدون سابقه باشد) برمی‌گردد؛ وگرنه
  /// [DuplicateServiceCodeException]. کد خدمت حذف‌شده با پسوند «~حذف-شناسه» رها می‌شود.
  static Future<void> ensureFree(DatabaseExecutor txn, String code, {int? excludeId}) async {
    if (codeKey(code).isEmpty) throw StateError('کد خدمت خالی است');
    final conflicts = await _conflicts(txn, code, excludeId: excludeId);
    if (conflicts.isEmpty) return;
    final h = await _loadHistory(txn);
    for (final c in conflicts) {
      if (!_reclaimable(c, h)) throw DuplicateServiceCodeException(code);
    }
    for (final c in conflicts) {
      await txn.update('services', {'code': '${c.code}~حذف-${c.id}'}, where: 'id = ?', whereArgs: [c.id]);
    }
  }

  /// کدهای آزاد و کد پیشنهادی برای سری دسته‌ی داده‌شده. فقط می‌خواند.
  /// پیشنهاد = کوچک‌ترین کد آزاد؛ اگر نبود، شماره‌ی بعد از آخرین.
  /// اگر دسته پیشوند نداشته باشد، [ServiceCategoryException] پرتاب می‌شود.
  Future<ServiceCodeInfo> loadCodeInfo({int? categoryId}) async {
    final prefix = await ServiceRepository().autoCodePrefixForCategory(categoryId);
    final pKey = codeKey(prefix);
    final db = await _db.database;
    final rows = await _loadRows(db);
    final h = await _loadHistory(db);

    final byNumber = <int, List<_SvcRow>>{};
    var last = 0;
    for (final r in rows) {
      if (!r.key.startsWith(pKey)) continue;
      final rest = r.key.substring(pKey.length);
      if (rest.isEmpty || rest.length > 5 || !RegExp(r'^\d+$').hasMatch(rest)) continue;
      final n = int.parse(rest);
      byNumber.putIfAbsent(n, () => []).add(r);
      if (n > last) last = n;
    }

    final free = <String>[];
    for (var n = 1; n <= last; n++) {
      final code = ServiceRepository.formatAutoCode(prefix, n);
      final holders = byNumber[n];
      if (holders != null && holders.isNotEmpty) {
        if (holders.any((r) => !r.deleted)) continue; // خدمت فعال
        if (holders.every((r) => _reclaimable(r, h))) free.add(code);
      } else if (h.known && !h.keys.contains(codeKey(code))) {
        free.add(code);
      }
    }

    String suggested;
    if (free.isNotEmpty) {
      suggested = free.first;
    } else {
      final allKeys = rows.map((r) => r.key).toSet();
      var n = last + 1;
      while (allKeys.contains(codeKey(ServiceRepository.formatAutoCode(prefix, n))) ||
          h.keys.contains(codeKey(ServiceRepository.formatAutoCode(prefix, n)))) {
        n++;
      }
      suggested = ServiceRepository.formatAutoCode(prefix, n);
    }
    return ServiceCodeInfo(prefix: prefix, freeCodes: free, suggested: suggested);
  }
}
