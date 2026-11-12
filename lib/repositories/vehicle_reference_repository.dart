import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/vehicle_reference.dart';

class VehicleReferenceRepository {
  final _db = DatabaseHelper.instance;

  /// [includeDeleted] فقط برای نمایش نام برند در خودروها/فاکتورهای قدیمی است
  /// که برندشان بعداً حذف منطقی شده؛ در لیست‌های انتخاب هرگز true نشود.
  Future<List<VehicleBrand>> getAllBrands({bool includeDeleted = false}) async {
    final db = await _db.database;
    final rows = includeDeleted
        ? await db.query('vehicle_brands', orderBy: 'name')
        : await db.query('vehicle_brands', where: 'is_deleted = 0', orderBy: 'name');
    return rows.map((r) => VehicleBrand.fromMap(r)).toList();
  }

  Future<void> updateBrand(int id, String name) async {
    final db = await _db.database;
    await db.update('vehicle_brands', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// آیا نام برند (بدون حساسیت به فاصله‌ی اضافی/حروف) قبلاً وجود دارد؟
  Future<bool> brandNameExists(String name, {int? excludeId}) async {
    final target = name.trim().toLowerCase();
    final brands = await getAllBrands();
    return brands.any((b) => b.id != excludeId && b.name.trim().toLowerCase() == target);
  }

  /// بررسی می‌کند آیا این برند در جایی (مدل‌ها، خدمات یا خودروها) استفاده شده است.
  Future<bool> isBrandInUse(int brandId) async {
    final db = await _db.database;
    Future<int> count(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, [brandId])) ?? 0;
    final models = await count('SELECT COUNT(*) FROM vehicle_models WHERE brand_id = ?');
    final services = await count('SELECT COUNT(*) FROM services WHERE brand_id = ?');
    final vehicles = await count('SELECT COUNT(*) FROM vehicles WHERE brand_id = ?');
    return models > 0 || services > 0 || vehicles > 0;
  }

  /// اگر برند جایی استفاده نشده، کاملاً حذف می‌شود؛ در غیر این صورت فقط
  /// حذف منطقی (Soft Delete) می‌شود تا سوابق قبلی خراب نشوند.
  Future<void> deleteBrand(int id) async {
    final db = await _db.database;
    final inUse = await isBrandInUse(id);
    if (inUse) {
      await db.update('vehicle_brands', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);
    } else {
      await db.delete('vehicle_brands', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<int> insertBrand(String name) async {
    final db = await _db.database;
    return db.insert('vehicle_brands', {'name': name});
  }

  Future<List<VehicleModel>> getModelsByBrand(int brandId) async {
    final db = await _db.database;
    final rows =
        await db.query('vehicle_models', where: 'brand_id = ?', whereArgs: [brandId], orderBy: 'name');
    return rows.map((r) => VehicleModel.fromMap(r)).toList();
  }

  Future<int> insertModel(int brandId, String name) async {
    final db = await _db.database;
    return db.insert('vehicle_models', {'brand_id': brandId, 'name': name});
  }

  Future<void> updateModel(int id, String name) async {
    final db = await _db.database;
    await db.update('vehicle_models', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// آیا نام مدل، داخل همان برند، قبلاً وجود دارد؟
  Future<bool> modelNameExists(int brandId, String name, {int? excludeId}) async {
    final target = name.trim().toLowerCase();
    final models = await getModelsByBrand(brandId);
    return models.any((m) => m.id != excludeId && m.name.trim().toLowerCase() == target);
  }

  /// آیا این مدل توسط خدمات یا خودروها استفاده شده است؟
  Future<bool> isModelInUse(int modelId) async {
    final db = await _db.database;
    Future<int> count(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, [modelId])) ?? 0;
    final services = await count('SELECT COUNT(*) FROM services WHERE model_id = ?');
    final vehicles = await count('SELECT COUNT(*) FROM vehicles WHERE model_id = ?');
    return services > 0 || vehicles > 0;
  }

  /// جدول vehicle_models ستون is_deleted ندارد و برای حفظ داده‌ها
  /// ساختار دیتابیس را تغییر نمی‌دهیم. بنابراین فقط مدلی که جایی استفاده
  /// نشده حذف می‌شود. خروجی false یعنی مدل در حال استفاده است و حذف نشد.
  Future<bool> deleteModel(int id) async {
    if (await isModelInUse(id)) return false;
    final db = await _db.database;
    await db.delete('vehicle_models', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  // ==================== پیش‌فرض ثابت برندها و مدل‌ها ====================
  //
  // نصب تازه (جدول برند خالی): فهرست پیش‌فرض زیر یک‌جا ساخته می‌شود.
  // بعد از آن هر گوشی برند/مدل را به سلیقه‌ی خودش اضافه، ویرایش یا حذف می‌کند
  // و برنامه هرگز چیزی به آن اضافه نمی‌کند، چیزی را برنمی‌گرداند و تغییری
  // در داده‌ی موجود نمی‌دهد.
  //
  // نصب قدیمی (برندها از قبل هست): فقط یک بار، اگر برندی با نام فارسی
  // «برلیانس» یا «دانگ‌فنگ» وجود داشته باشد، نامش به Brilliance و Dongfeng
  // تغییر می‌کند (همان رکورد، پس خدمات/خودروها/فاکتورها سالم می‌مانند).
  // اگر برند هم‌نام انگلیسی از قبل وجود داشته باشد، هیچ تغییری داده نمی‌شود.
  //
  // ادغام برندهای فارسی (فقط یک بار، نصب قدیمی): هشت برند فارسی شناخته‌شده
  // (ایران‌خودرو، تویوتا، رنو، سایپا، سیتروئن، مزدا، پژو، کیا) با برند
  // انگلیسی هم‌نامشان یکی می‌شوند: مدل‌ها، خدمات و خودروها به برند انگلیسی
  // منتقل می‌شوند (مدل هم‌نام یکی می‌شود). اگر برند انگلیسی وجود نداشته باشد،
  // خود برند فارسی به نام انگلیسی تغییر نام می‌دهد. هیچ خدمت، قیمت، کد،
  // خودرو یا فاکتوری حذف یا بازنویسی نمی‌شود؛ همه‌چیز در یک تراکنش است.

  static const String _renameDoneKey = 'vehicle_brand_rename_v1_done';
  static const String _mergeDoneKey = 'vehicle_brand_merge_v1_done';

  static const Map<String, String> _legacyRenames = {
    'برلیانس': 'Brilliance',
    'دانگ‌فنگ': 'Dongfeng',
  };

  static const Map<String, String> _persianToEnglish = {
    'ایران‌خودرو': 'IRCO',
    'تویوتا': 'Toyota',
    'رنو': 'Renault',
    'سایپا': 'Saipa',
    'سیتروئن': 'Citroen',
    'مزدا': 'Mazda',
    'پژو': 'Peugeot',
    'کیا': 'Kia',
  };

  static const Map<String, List<String>> _defaultBrands = {
    'IRCO': ['سمند', 'وانت پیکان', 'آریسان', 'سمند EF7', 'دنا EF7', 'سورن', 'سورن پلاس', 'دنا', 'دنا پلاس', 'رانا', 'رانا پلاس', 'تارا'],
    'Peugeot': ['206', '207', '405', 'پارس', 'پارس ELX'],
    'Saipa': ['پراید', 'تیبا', 'ساینا', 'کوییک', 'شاهین', 'شاهین پلاس', 'اطلس', 'سهند', 'آریا', 'پارس نوا (P90)'],
    'Zamyad': ['زامیاد', 'پادرا', 'شوکا'],
    'Renault': ['ال90', 'مگان', 'ساندرو', 'تندر 90', 'ساندرو استپ‌وی', 'پی‌کی'],
    'Citroen': ['زانتیا', 'C3', 'C5'],
    'Kia': ['ریو', 'سراتو', 'پیکانتو', 'ایبروس', 'اپتیما', 'کادنزا', 'سورنتو 3500', 'سورنتو 2400', 'اسپورتیج', 'موهاوی 8 سیلندر', 'موهاوی 6 سیلندر', 'سراتو وارداتی'],
    'Hyundai': ['i10', 'i20', 'i30', 'i40', 'النترا', 'اکسنت', 'توسان 2400', 'توسان 2700', 'ix35', 'آوانته', 'آزرا 3300', 'سانتافه 3500', 'سانتافه 2700', 'سانتافه 2400', 'جنسیس', 'وراکروز ix55', 'سوناتا 6 سیلندر اتوماتیک NF', 'سوناتا 4 سیلندر NF.YF.LF', 'ولستر', 'کوپه 2700'],
    'Chery': ['آریزو', 'A11', 'کوین', 'تیگو 5', 'تیگو 7', 'آریزو 5', 'آریزو 6'],
    'MVM': ['110', '110S', 'X22', 'X33', 'X33S', '315', '315S', '530', '550'],
    'Lifan': ['520', '820', 'X70', '620', 'X60', 'X50'],
    'JAC': ['J3', 'J4', 'J5', 'S3', 'S5'],
    'Brilliance': ['H220', 'H230', 'H320', 'H320 Cross', 'H330', '1500cc', '1600cc'],
    'Bahman': ['دلیکا', 'کاپرا', 'فیدلیتی'],
    'Mazda': ['2000', '323', 'کارا', '3', '3 نیو', '2', 'وانت', '323 اتوماتیک'],
    'Geely': ['ام‌گرند EC7', 'ام‌گرند EC718', 'ام‌گرند X7', 'GC6'],
    'Nissan': ['وانت', 'قشقایی', 'مورانو', 'جوک', 'ایکس تریل', 'تیانا', 'ماکسیما', 'پاترول', 'پیکاپ', 'سرانزا', 'رونیز', 'پت فایندر', 'پیکاپ ریچ'],
    'Dongfeng': ['H30 کراس'],
    'Toyota': ['کمری', 'لندکروز', 'پرادو', 'هایلوکس', 'هایس'],
    'Daewoo': ['ماتیز', 'اسپرو', 'ریسو', 'سیلو'],
    'Suzuki': ['ویتارا'],
  };

  /// نرمال‌سازی نام برای مقایسه: ی/ي، ک/ك، نیم‌فاصله، فاصله، کشیده، ارقام و حروف.
  static String _norm(String s) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    var t = s
        .toLowerCase()
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('\u200c', '')
        .replaceAll('\u200f', '')
        .replaceAll('ـ', '')
        .replaceAll(' ', '');
    for (var i = 0; i < 10; i++) {
      t = t.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    return t;
  }

  Future<void> ensureDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAllBrands(includeDeleted: true);
    if (all.isEmpty) {
      await _seedDefaults();
      await prefs.setBool(_renameDoneKey, true);
      await prefs.setBool(_mergeDoneKey, true);
      return;
    }
    if (prefs.getBool(_renameDoneKey) != true) {
      await _renameLegacyBrands(all);
      await prefs.setBool(_renameDoneKey, true);
    }
    if (prefs.getBool(_mergeDoneKey) != true) {
      try {
        await _mergePersianBrands();
        await prefs.setBool(_mergeDoneKey, true);
      } catch (_) {
        // اگر ادغام انجام نشد، تراکنش کامل برگشت خورده و داده دست‌نخورده است؛
        // پرچم ثبت نمی‌شود تا دفعه‌ی بعد دوباره تلاش شود و برنامه هم باز شود.
      }
    }
  }

  Future<void> _seedDefaults() async {
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final entry in _defaultBrands.entries) {
        final brandId = await txn.insert('vehicle_brands', {'name': entry.key});
        for (final model in entry.value) {
          await txn.insert('vehicle_models', {'brand_id': brandId, 'name': model});
        }
      }
    });
  }

  Future<void> _renameLegacyBrands(List<VehicleBrand> all) async {
    final active = await getAllBrands();
    for (final e in _legacyRenames.entries) {
      final newKey = _norm(e.value);
      if (all.any((b) => _norm(b.name) == newKey)) continue;
      final oldKey = _norm(e.key);
      for (final b in active) {
        if (_norm(b.name) != oldKey) continue;
        final int? id = b.id;
        if (id == null) continue;
        await updateBrand(id, e.value);
        break;
      }
    }
  }

  /// ادغام یک‌باره‌ی برندهای فارسی با برند انگلیسی هم‌نام (همه در یک تراکنش).
  Future<void> _mergePersianBrands() async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final brands = await txn.query('vehicle_brands');
      for (final e in _persianToEnglish.entries) {
        final pKey = _norm(e.key);
        final tKey = _norm(e.value);
        final persian = brands.where((b) => _norm((b['name'] as String?) ?? '') == pKey).toList();
        if (persian.isEmpty) continue;

        // برند انگلیسی مقصد (ترجیحاً فعال).
        int? targetId;
        var targetDeleted = true;
        for (final b in brands) {
          if (_norm((b['name'] as String?) ?? '') != tKey) continue;
          final del = ((b['is_deleted'] as num?)?.toInt() ?? 0) == 1;
          if (targetId == null || (targetDeleted && !del)) {
            targetId = (b['id'] as num).toInt();
            targetDeleted = del;
          }
        }

        for (final p in persian) {
          final pid = (p['id'] as num).toInt();
          final pDeleted = ((p['is_deleted'] as num?)?.toInt() ?? 0) == 1;

          // برند انگلیسی وجود ندارد: همین رکورد فارسی تغییر نام می‌دهد.
          if (targetId == null) {
            await txn.update('vehicle_brands', {'name': e.value}, where: 'id = ?', whereArgs: [pid]);
            targetId = pid;
            targetDeleted = pDeleted;
            continue;
          }
          final tid = targetId;
          if (tid == pid) continue;

          // مدل‌ها: مدل هم‌نام یکی می‌شود، مدل جدید به برند مقصد منتقل می‌شود.
          final pModels = await txn.query('vehicle_models', where: 'brand_id = ?', whereArgs: [pid]);
          final tModels = await txn.query('vehicle_models', where: 'brand_id = ?', whereArgs: [tid]);
          final byName = <String, int>{
            for (final m in tModels) _norm((m['name'] as String?) ?? ''): (m['id'] as num).toInt(),
          };
          for (final m in pModels) {
            final mid = (m['id'] as num).toInt();
            final key = _norm((m['name'] as String?) ?? '');
            final same = byName[key];
            if (same != null) {
              await txn.update('services', {'model_id': same}, where: 'model_id = ?', whereArgs: [mid]);
              await txn.update('vehicles', {'model_id': same}, where: 'model_id = ?', whereArgs: [mid]);
              await txn.delete('vehicle_models', where: 'id = ?', whereArgs: [mid]);
            } else {
              await txn.update('vehicle_models', {'brand_id': tid}, where: 'id = ?', whereArgs: [mid]);
              byName[key] = mid;
            }
          }

          // خدمات و خودروهای برند فارسی به برند انگلیسی می‌روند.
          await txn.update('services', {'brand_id': tid}, where: 'brand_id = ?', whereArgs: [pid]);
          await txn.update('vehicles', {'brand_id': tid}, where: 'brand_id = ?', whereArgs: [pid]);

          // اگر برند مقصد حذف منطقی بود ولی برند فارسی فعال بود، مقصد فعال می‌شود.
          if (targetDeleted && !pDeleted) {
            await txn.update('vehicle_brands', {'is_deleted': 0}, where: 'id = ?', whereArgs: [tid]);
            targetDeleted = false;
          }

          // برند فارسی دیگر هیچ وابستگی ندارد.
          await txn.delete('vehicle_brands', where: 'id = ?', whereArgs: [pid]);
        }
      }
    });
  }
}
