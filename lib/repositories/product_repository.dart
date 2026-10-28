import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/product.dart';

/// کد کالا قبلاً به کالای دیگری اختصاص داده شده است.
class DuplicateCodeException implements Exception {
  final String code;
  const DuplicateCodeException(this.code);
  String get message => 'این کد کالا تکراری است؛ لطفاً کد دیگری وارد کنید';
  @override
  String toString() => message;
}

/// کدی که به هیچ کالای جدیدی داده نمی‌شود، و دلیلش.
class UnusableCode {
  final String code;
  final String reason;
  const UnusableCode(this.code, this.reason);
}

/// وضعیت کدهای کالا، محاسبه‌شده از روی اطلاعات واقعی (نه از روی تعداد کالاها).
class ProductCodeInfo {
  final String prefix; // پیشوند غالب کدهای فعلی (پیش‌فرض PRD)
  final int width; // تعداد ارقام با صفر پُرکننده (۰ = بدون صفر)
  final String? lastCode; // بالاترین شماره‌ی ثبت‌شده (کالای فعال یا آرشیوشده)
  final int productsWithCode; // تعداد کالاهای فعال دارای کد
  final List<String> freeCodes; // آزاد و قابل استفاده مجدد، صعودی
  final List<UnusableCode> unusableCodes; // آزاد نمی‌شوند (به‌خاطر سوابق)
  final List<String> duplicateCodes; // کدهای تکراری از قبل موجود (در صورت وجود)
  final String suggested; // کد پیشنهادی برای کالای جدید

  const ProductCodeInfo({
    required this.prefix,
    required this.width,
    required this.lastCode,
    required this.productsWithCode,
    required this.freeCodes,
    required this.unusableCodes,
    required this.duplicateCodes,
    required this.suggested,
  });
}

class _CodeRow {
  final int id;
  final String code;
  final bool deleted;
  final String key; // برای مقایسه: بدون فاصله، حروف بزرگ، ارقام انگلیسی
  final String prefix;
  final String prefixKey;
  final int? number;
  final int digitsLen;
  final bool zeroPadded;

  _CodeRow._(this.id, this.code, this.deleted, this.key, this.prefix, this.prefixKey, this.number,
      this.digitsLen, this.zeroPadded);

  factory _CodeRow.from(int id, String code, bool deleted) {
    final compact = ProductRepository._digits(code).replaceAll(RegExp(r'\s+'), '');
    final m = RegExp(r'^(.*?)(\d+)$').firstMatch(compact);
    int? number;
    var prefix = '';
    var len = 0;
    var padded = false;
    // فقط شماره‌های حداکثر ۵ رقمی «شماره‌ی ترتیبی» حساب می‌شوند (کدهای طولانی
    // مثل بارکد یا شماره‌تلفن وارد محاسبه‌ی شماره‌های آزاد نمی‌شوند).
    if (m != null && m.group(2)!.length <= 5) {
      final d = m.group(2)!;
      number = int.parse(d);
      prefix = m.group(1)!;
      len = d.length;
      padded = d.length > 1 && d.startsWith('0');
    }
    return _CodeRow._(id, code, deleted, compact.toUpperCase(), prefix, prefix.toUpperCase(), number, len, padded);
  }
}

class _History {
  final Set<int> productIds; // کالاهایی که در اقلام فاکتور یا گردش انبار آمده‌اند
  final Set<String> codeKeys; // کدهایی که روی اقلام فاکتور ثبت (فریز) شده‌اند
  const _History(this.productIds, this.codeKeys);
}

class ProductRepository {
  final _db = DatabaseHelper.instance;

  // ==================== نرمال‌سازی کد ====================

  static String _digits(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(r - 0x06F0 + 0x30);
      } else if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(r - 0x0660 + 0x30);
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// کلید مقایسه‌ی کد: فاصله‌ها حذف، حروف بزرگ، ارقام فارسی/عربی → انگلیسی.
  static String codeKey(String code) => _digits(code).replaceAll(RegExp(r'\s+'), '').toUpperCase();

  /// شکل ذخیره‌شده‌ی کد: فاصله‌های ابتدا/انتها و فاصله‌های تکراری حذف می‌شود.
  static String cleanCode(String code) => code.trim().replaceAll(RegExp(r'\s+'), ' ');

  // ==================== کنترل یکتایی (داخل تراکنش) ====================

  Future<List<_CodeRow>> _loadRows(DatabaseExecutor db) async {
    final rows = await db.query('products', columns: ['id', 'code', 'is_deleted']);
    return rows
        .map((r) => _CodeRow.from((r['id'] as num).toInt(), (r['code'] as String?) ?? '', (r['is_deleted'] as int? ?? 0) == 1))
        .toList();
  }

  Future<_History> _loadHistory(DatabaseExecutor db) async {
    final ids = <int>{};
    final keys = <String>{};
    for (final r in await db.rawQuery('SELECT DISTINCT product_id FROM invoice_items WHERE product_id IS NOT NULL')) {
      ids.add((r['product_id'] as num).toInt());
    }
    for (final r in await db.rawQuery('SELECT DISTINCT product_id FROM stock_movements WHERE product_id IS NOT NULL')) {
      ids.add((r['product_id'] as num).toInt());
    }
    for (final r in await db.rawQuery(
        "SELECT DISTINCT item_code FROM invoice_items WHERE item_code IS NOT NULL AND item_code != ''")) {
      keys.add(codeKey((r['item_code'] as String?) ?? ''));
    }
    return _History(ids, keys);
  }

  /// کالای آرشیوشده فقط وقتی کدش آزاد می‌شود که در هیچ فاکتور یا گردش انبار
  /// استفاده نشده باشد.
  bool _reclaimable(_CodeRow r, _History h) =>
      r.deleted && !h.productIds.contains(r.id) && !h.codeKeys.contains(r.key);

  /// اگر کد آزاد باشد (یا فقط به کالای آرشیوشده‌ی بدون سابقه تعلق داشته باشد)
  /// برمی‌گردد؛ در غیر این صورت [DuplicateCodeException]. کدِ آرشیوشده‌ی
  /// بدون سابقه با اضافه کردن «~حذف-شناسه» به انتهایش رها می‌شود.
  Future<void> _ensureCodeFree(DatabaseExecutor txn, String code, {int? excludeId}) async {
    final key = codeKey(code);
    if (key.isEmpty) throw StateError('کد کالا را وارد کنید');
    final rows = await _loadRows(txn);
    final conflicts = rows.where((r) => r.id != excludeId && r.key == key).toList();
    if (conflicts.isEmpty) return;
    final history = await _loadHistory(txn);
    for (final c in conflicts) {
      if (!_reclaimable(c, history)) throw DuplicateCodeException(code);
    }
    for (final c in conflicts) {
      await txn.update('products', {'code': '${c.code}~حذف-${c.id}'}, where: 'id = ?', whereArgs: [c.id]);
    }
  }

  /// آیا این کد برای کالای دیگری (غیر از [excludeId]) گرفته شده است؟ کدِ کالای
  /// فعال یا آرشیوشده‌ی دارای سابقه «گرفته‌شده» است. حروف بزرگ/کوچک و فاصله
  /// اثری ندارند.
  Future<bool> codeExists(String code, {int? excludeId}) async {
    final key = codeKey(code);
    if (key.isEmpty) return false;
    final db = await _db.database;
    final rows = await _loadRows(db);
    final conflicts = rows.where((r) => r.id != excludeId && r.key == key).toList();
    if (conflicts.isEmpty) return false;
    final history = await _loadHistory(db);
    return conflicts.any((c) => !_reclaimable(c, history));
  }

  // ==================== ثبت و ویرایش ====================

  /// ثبت کالای جدید. بررسی یکتایی و درج در یک تراکنش انجام می‌شود (اتمیک).
  Future<int> insert(Product p) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final code = cleanCode(p.code);
      await _ensureCodeFree(txn, code);
      return txn.insert('products', p.copyWith(code: code).toMap()..remove('id'));
    });
  }

  Future<int> update(Product p) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final code = cleanCode(p.code);
      // اگر کد تغییر نکرده، کنترل نمی‌شود تا کالاهای قدیمیِ دارای کد تکراری
      // قابل ویرایش بمانند.
      final cur = await txn.query('products', columns: ['code'], where: 'id = ?', whereArgs: [p.id], limit: 1);
      final unchanged = cur.isNotEmpty && codeKey((cur.first['code'] as String?) ?? '') == codeKey(code);
      if (!unchanged) await _ensureCodeFree(txn, code, excludeId: p.id);
      return txn.update('products', p.copyWith(code: code).toMap(), where: 'id = ?', whereArgs: [p.id]);
    });
  }

  Future<int> softDelete(int id) async {
    final db = await _db.database;
    return db.update('products', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Product?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<List<Product>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('products', where: 'is_deleted = 0', orderBy: 'name');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<List<Product>> search(String q) async {
    final db = await _db.database;
    final like = '%$q%';
    final rows = await db.query('products',
        where: 'is_deleted = 0 AND (name LIKE ? OR code LIKE ?)', whereArgs: [like, like], orderBy: 'name');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  /// جستجوی فازی/نزدیک بر اساس نام یا برچسب جستجوی صوتی. برای جستجوی صوتی
  /// استفاده می‌شود: همه‌ی کلمات پرسش باید جایی در نام یا برچسب پیدا شوند
  /// (نه لزوماً تطابق دقیق و پشت‌سرهم).
  Future<List<Product>> searchFuzzy(String query) async {
    final db = await _db.database;
    final tokens = query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return [];
    final whereParts = <String>[];
    final args = <String>[];
    for (final t in tokens) {
      whereParts.add('(name LIKE ? OR voice_search_label LIKE ?)');
      args.add('%$t%');
      args.add('%$t%');
    }
    final rows = await db.query('products',
        where: 'is_deleted = 0 AND (${whereParts.join(' AND ')})', whereArgs: args, orderBy: 'name');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<List<Product>> getLowStock() async {
    final db = await _db.database;
    final rows =
        await db.query('products', where: 'is_deleted = 0 AND stock <= min_stock', orderBy: 'stock ASC');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  /// جستجوی کالا بر اساس بارکد اسکن‌شده. برای اسکن هنگام صدور فاکتور استفاده می‌شود.
  Future<Product?> getByBarcode(String barcode) async {
    final db = await _db.database;
    final rows = await db.query('products',
        where: 'is_deleted = 0 AND barcode = ?', whereArgs: [barcode]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<bool> barcodeExists(String barcode, {int? excludeId}) async {
    final db = await _db.database;
    final rows = await db.query('products',
        where: excludeId == null ? 'barcode = ?' : 'barcode = ? AND id != ?',
        whereArgs: excludeId == null ? [barcode] : [barcode, excludeId]);
    return rows.isNotEmpty;
  }

  Future<int> count() async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM products WHERE is_deleted = 0');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> adjustStock(int productId, int deltaQuantity,
      {required String reason, int? invoiceId}) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final rows = await txn.query('products', where: 'id = ?', whereArgs: [productId]);
      if (rows.isEmpty) throw StateError('کالا یافت نشد');
      final current = rows.first['stock'] as int;
      final next = current + deltaQuantity;
      if (next < 0) {
        throw StateError('موجودی کافی نیست (موجودی فعلی: $current)');
      }
      await txn.update('products', {'stock': next}, where: 'id = ?', whereArgs: [productId]);
      await txn.insert('stock_movements', {
        'product_id': productId,
        'type': deltaQuantity >= 0 ? 'increase' : 'decrease',
        'quantity': deltaQuantity.abs(),
        'reason': reason,
        'invoice_id': invoiceId,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  // ==================== مدیریت کدها ====================

  /// آخرین شماره، کدهای آزاد، کدهای غیرقابل‌استفاده و کد پیشنهادی. همه از
  /// روی کدهای واقعی (فعال و آرشیوشده) و سوابق فاکتور/انبار محاسبه می‌شود،
  /// نه از روی تعداد کالاها.
  ///
  /// قواعد:
  ///  - پیشوند و تعداد ارقام = الگوی غالبِ کدهای فعلی (پیش‌فرض PRD و ۴ رقم).
  ///  - کدِ کالای فعال هرگز آزاد نیست.
  ///  - کدِ کالای آرشیوشده فقط وقتی آزاد است که در هیچ فاکتور یا گردش انبار
  ///    نیامده باشد؛ وگرنه در فهرست «غیرقابل استفاده» می‌آید.
  ///  - شماره‌ی بدون کالایی که قبلاً روی اقلام فاکتورها ثبت شده، آزاد نیست.
  ///  - پیشنهاد = کوچک‌ترین کد آزاد؛ اگر نبود، شماره‌ی بعد از آخرین.
  Future<ProductCodeInfo> loadCodeInfo() async {
    final db = await _db.database;
    final rows = await _loadRows(db);
    final history = await _loadHistory(db);

    final groups = <String, List<_CodeRow>>{};
    for (final r in rows) {
      if (r.number != null) groups.putIfAbsent(r.prefixKey, () => []).add(r);
    }
    var prefix = 'PRD';
    var group = <_CodeRow>[];
    if (groups.isNotEmpty) {
      final best = groups.entries.reduce((a, b) => b.value.length > a.value.length ? b : a);
      group = best.value;
      prefix = group.first.prefix;
    }
    final padded = group.any((r) => r.zeroPadded);
    final width = group.isEmpty ? 4 : (padded ? group.map((r) => r.digitsLen).reduce(math.max) : 0);
    String fmt(int n) => '$prefix${n.toString().padLeft(width, '0')}';

    final byNumber = <int, List<_CodeRow>>{};
    for (final r in group) {
      byNumber.putIfAbsent(r.number!, () => []).add(r);
    }
    final last = group.isEmpty ? null : group.map((r) => r.number!).reduce(math.max);

    final free = <String>[];
    final unusable = <UnusableCode>[];
    if (last != null) {
      for (var n = 1; n <= last; n++) {
        final code = fmt(n);
        final holders = byNumber[n];
        if (holders != null && holders.isNotEmpty) {
          if (holders.any((r) => !r.deleted)) continue; // کالای فعال
          if (holders.every((r) => _reclaimable(r, history))) {
            free.add(code);
          } else {
            unusable.add(UnusableCode(code, 'کالای آرشیوشده‌ای که در فاکتور یا انبار استفاده شده'));
          }
        } else if (history.codeKeys.contains(codeKey(code))) {
          unusable.add(UnusableCode(code, 'در فاکتورهای قبلی استفاده شده'));
        } else {
          free.add(code);
        }
      }
    }

    final allKeys = rows.map((r) => r.key).toSet();
    String suggested;
    if (free.isNotEmpty) {
      suggested = free.first;
    } else {
      var n = (last ?? 0) + 1;
      while (true) {
        final c = fmt(n);
        final k = codeKey(c);
        if (!allKeys.contains(k) && !history.codeKeys.contains(k)) {
          suggested = c;
          break;
        }
        n++;
      }
    }

    // کدهای تکراریِ از قبل موجود بین کالاهای فعال (فقط برای هشدار).
    final seen = <String, String>{};
    final dups = <String>{};
    for (final r in rows.where((r) => !r.deleted && r.key.isNotEmpty)) {
      if (seen.containsKey(r.key)) {
        dups.add(seen[r.key]!);
      } else {
        seen[r.key] = r.code;
      }
    }

    return ProductCodeInfo(
      prefix: prefix,
      width: width,
      lastCode: last == null ? null : fmt(last),
      productsWithCode: rows.where((r) => !r.deleted && r.key.isNotEmpty).length,
      freeCodes: free,
      unusableCodes: unusable,
      duplicateCodes: dups.toList()..sort(),
      suggested: suggested,
    );
  }
}
