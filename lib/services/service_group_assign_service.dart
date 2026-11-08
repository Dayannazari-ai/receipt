import 'dart:io';
import 'package:excel/excel.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../repositories/service_group_repository.dart';
import '../repositories/service_repository.dart';
import '../repositories/vehicle_reference_repository.dart';
import 'price_list_import_service.dart' show ImportStructureException;

/// یک مجموعه‌ی دیده‌شده در فایل. status: exists | inactive | new
class AssignGroupLine {
  final String name;
  final String status;
  final int rows; // تعداد ردیف‌های فایل برای این مجموعه
  final int toAssign; // تعداد خدماتی که به آن وصل می‌شوند
  const AssignGroupLine(this.name, this.status, this.rows, this.toAssign);
}

class AssignPreview {
  final int totalRows;
  final int toAssignExisting; // خدمات بدون مجموعه که به مجموعه‌ی موجود (فعال) وصل می‌شوند
  final int toAssignNew; // خدماتی که فقط با ساخت مجموعه‌ی جدید وصل می‌شوند
  final int alreadySame; // از قبل در همان مجموعه‌اند
  final int otherGroup; // از قبل مجموعه‌ی دیگری دارند (بازنویسی نمی‌شود)
  final int unmatched; // در دیتابیس پیدا نشد
  final int ambiguous; // چند خدمت با یک کلید تطبیق دارند (رد می‌شود)
  final int inactiveGroupRows; // مجموعه‌ی فایل غیرفعال است (رد می‌شود)
  final List<AssignGroupLine> groups;
  final List<String> unmatchedSample;
  final List<String> ambiguousSample;
  final List<String> otherGroupSample;
  const AssignPreview({
    required this.totalRows,
    required this.toAssignExisting,
    required this.toAssignNew,
    required this.alreadySame,
    required this.otherGroup,
    required this.unmatched,
    required this.ambiguous,
    required this.inactiveGroupRows,
    required this.groups,
    required this.unmatchedSample,
    required this.ambiguousSample,
    required this.otherGroupSample,
  });

  int get newGroupCount => groups.where((g) => g.status == 'new').length;
}

class AssignResult {
  final int assigned;
  final int created;
  const AssignResult(this.assigned, this.created);
}

class _FileRow {
  final int rowNo;
  final String name;
  final String brand;
  final String model;
  final String group;
  const _FileRow(this.rowNo, this.name, this.brand, this.model, this.group);
}

class _GroupAgg {
  final String key;
  final String name;
  int rows = 0;
  int toAssign = 0;
  _GroupAgg(this.key, this.name);
}

class _Plan {
  int totalRows = 0;
  int toAssignExisting = 0;
  int toAssignNew = 0;
  int alreadySame = 0;
  int otherGroup = 0;
  int unmatched = 0;
  int ambiguous = 0;
  int inactiveGroupRows = 0;
  final Map<String, _GroupAgg> groups = {}; // به ترتیب اولین ظهور در فایل
  final Map<String, String> status = {};
  final Map<String, List<int>> assignments = {}; // کلید مجموعه ← شناسه‌ی خدمات
  final List<String> unmatchedSample = [];
  final List<String> ambiguousSample = [];
  final List<String> otherGroupSample = [];
}

/// انتساب مجموعه به خدمات «موجود» از روی ستون «مجموعه»ی فایل نرخ‌نامه.
/// فقط service_group_id همان خدمت نوشته می‌شود؛ قیمت، کد، برند/مدل، برچسب صوتی،
/// فاکتورها و مجموعه‌ی قبلیِ خدمت هرگز تغییر نمی‌کنند. کل انتساب یک تراکنش است.
class ServiceGroupAssignService {
  final _vehicleRepo = VehicleReferenceRepository();

  static const Set<String> _serviceHeaders = {'نام خدمت', 'عنوان خدمت'};
  static const Set<String> _brandHeaders = {'برند خودرو', 'برند'};
  static const Set<String> _modelHeaders = {'مدل خودرو', 'مدل'};
  static const Set<String> _groupHeaders = {'مجموعه', 'مجموعه خدمات'};

  String _k(String s) => ServiceGroupRepository.nameKey(s);

  String _hdrKey(String s) => _k(s.replaceAll(RegExp(r'\(\s*اختیاری\s*\)'), ''));

  String? _cellText(CellValue? cv) {
    if (cv == null) return null;
    final s = cv.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// خواندن فایل. هر ایراد ساختاری یا ردیف نامعتبر، خطای روشن می‌دهد و چیزی نوشته نمی‌شود.
  List<_FileRow> _readRows(String path) {
    final bytes = File(path).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final rows = <_FileRow>[];
    final errors = <String>[];
    final firstRowOfKey = <String, int>{};
    var foundSheet = false;

    for (final te in excel.tables.entries) {
      final sheetName = te.key;
      final sheet = te.value;
      if (sheet.maxRows == 0) continue;
      final header = sheet.row(0);
      final keys = [for (final c in header) _hdrKey(_cellText(c?.value) ?? '')];
      List<int> idx(Set<String> names) =>
          [for (var i = 0; i < keys.length; i++) if (names.contains(keys[i])) i];

      final sI = idx(_serviceHeaders);
      final bI = idx(_brandHeaders);
      final mI = idx(_modelHeaders);
      final gI = idx(_groupHeaders);
      if (sI.isEmpty && bI.isEmpty && mI.isEmpty && gI.isEmpty) continue;

      final sheetErrors = <String>[];
      void need(List<int> l, String label) {
        if (l.isEmpty) {
          sheetErrors.add('ستون «$label» پیدا نشد');
        } else if (l.length > 1) {
          sheetErrors.add('ستون «$label» بیش از یک‌بار آمده است');
        }
      }

      need(sI, 'نام خدمت');
      need(bI, 'برند خودرو');
      need(mI, 'مدل خودرو');
      need(gI, 'مجموعه');
      if (sheetErrors.isNotEmpty) {
        for (final m in sheetErrors) {
          errors.add('شیت «$sheetName»: $m');
        }
        continue;
      }
      foundSheet = true;

      var bad = 0;
      final badMsgs = <String>[];
      for (var r = 1; r < sheet.maxRows; r++) {
        final row = sheet.row(r);
        CellValue? at(int i) => i < row.length ? row[i]?.value : null;
        final name = _cellText(at(sI.first));
        final brand = _cellText(at(bI.first));
        final model = _cellText(at(mI.first));
        final group = _cellText(at(gI.first));
        if (name == null && brand == null && model == null && group == null) continue;
        final reasons = <String>[];
        if (name == null) reasons.add('نام خدمت خالی');
        if (brand == null) reasons.add('برند خالی');
        if (model == null) reasons.add('مدل خالی');
        if (group == null) reasons.add('مجموعه خالی');
        if (reasons.isNotEmpty) {
          bad++;
          if (badMsgs.length < 5) badMsgs.add('ردیف ${r + 1}: ${reasons.join('، ')}');
          continue;
        }
        final key = '${_k(name!)}|${_k(brand!)}|${_k(model!)}';
        final prev = firstRowOfKey[key];
        if (prev != null) {
          bad++;
          if (badMsgs.length < 5) badMsgs.add('ردیف ${r + 1}: تکراری ردیف $prev (نام، برند و مدل یکسان)');
          continue;
        }
        firstRowOfKey[key] = r + 1;
        rows.add(_FileRow(r + 1, name, brand, model, group!));
      }
      if (bad > 0) {
        errors.add('شیت «$sheetName»: $bad ردیف نامعتبر است');
        for (final m in badMsgs) {
          errors.add('• $m');
        }
        if (bad > badMsgs.length) errors.add('• و ${bad - badMsgs.length} ردیف نامعتبر دیگر');
      }
    }

    if (!foundSheet && errors.isEmpty) {
      errors.add('هیچ شیتی با سرستون‌های «نام خدمت»، «برند خودرو»، «مدل خودرو» و «مجموعه» پیدا نشد');
    }
    if (errors.isNotEmpty) throw ImportStructureException(errors.join('\n'));
    if (rows.isEmpty) throw const ImportStructureException('هیچ ردیف معتبری در فایل پیدا نشد');
    return rows;
  }

  Future<_Plan> _plan(String path, int categoryId) async {
    final fileRows = _readRows(path);
    if (!await ServiceCategoryRepository().isActive(categoryId)) {
      throw const ServiceCategoryException('دسته‌بندی انتخاب‌شده وجود ندارد یا بایگانی شده است');
    }
    final db = await DatabaseHelper.instance.database;

    final brandKeyById = <int, String>{};
    final modelKeyById = <int, String>{};
    for (final b in await _vehicleRepo.getAllBrands()) {
      brandKeyById[b.id!] = _k(b.name);
      for (final m in await _vehicleRepo.getModelsByBrand(b.id!)) {
        modelKeyById[m.id!] = _k(m.name);
      }
    }

    final groups = await ServiceGroupRepository().getByCategory(categoryId);
    final groupByKey = {for (final g in groups) _k(g.name): g};

    final svcRows = await db.query('services',
        columns: ['id', 'name', 'brand_id', 'model_id', 'service_group_id'],
        where: 'category_id = ? AND is_deleted = 0',
        whereArgs: [categoryId]);
    final index = <String, List<Map<String, Object?>>>{};
    for (final r in svcRows) {
      final bId = (r['brand_id'] as num?)?.toInt();
      final mId = (r['model_id'] as num?)?.toInt();
      final key = '${_k((r['name'] as String?) ?? '')}|'
          '${bId == null ? '' : (brandKeyById[bId] ?? '#$bId')}|'
          '${mId == null ? '' : (modelKeyById[mId] ?? '#$mId')}';
      index.putIfAbsent(key, () => []).add(r);
    }

    final plan = _Plan()..totalRows = fileRows.length;
    String label(_FileRow fr) => '${fr.name} | ${fr.brand} ${fr.model}';

    for (final fr in fileRows) {
      final gKey = _k(fr.group);
      final agg = plan.groups.putIfAbsent(gKey, () => _GroupAgg(gKey, fr.group));
      agg.rows++;
      final existing = groupByKey[gKey];
      final status = existing == null ? 'new' : (existing.active ? 'exists' : 'inactive');
      plan.status[gKey] = status;

      final matches = index['${_k(fr.name)}|${_k(fr.brand)}|${_k(fr.model)}'];
      if (matches == null || matches.isEmpty) {
        plan.unmatched++;
        if (plan.unmatchedSample.length < 5) plan.unmatchedSample.add(label(fr));
        continue;
      }
      if (matches.length > 1) {
        plan.ambiguous++;
        if (plan.ambiguousSample.length < 5) plan.ambiguousSample.add('${label(fr)} (${matches.length} خدمت)');
        continue;
      }
      final svc = matches.first;
      final curGid = (svc['service_group_id'] as num?)?.toInt();
      if (curGid != null) {
        if (existing != null && existing.id == curGid) {
          plan.alreadySame++;
        } else {
          plan.otherGroup++;
          if (plan.otherGroupSample.length < 5) plan.otherGroupSample.add(label(fr));
        }
        continue;
      }
      if (status == 'inactive') {
        plan.inactiveGroupRows++;
        continue;
      }
      if (status == 'new') {
        plan.toAssignNew++;
      } else {
        plan.toAssignExisting++;
      }
      agg.toAssign++;
      plan.assignments.putIfAbsent(gKey, () => []).add((svc['id'] as num).toInt());
    }
    return plan;
  }

  /// تحلیل برای پیش‌نمایش. چیزی نمی‌نویسد.
  Future<AssignPreview> analyze(String path, int categoryId) async {
    final p = await _plan(path, categoryId);
    return AssignPreview(
      totalRows: p.totalRows,
      toAssignExisting: p.toAssignExisting,
      toAssignNew: p.toAssignNew,
      alreadySame: p.alreadySame,
      otherGroup: p.otherGroup,
      unmatched: p.unmatched,
      ambiguous: p.ambiguous,
      inactiveGroupRows: p.inactiveGroupRows,
      groups: [
        for (final g in p.groups.values) AssignGroupLine(g.name, p.status[g.key] ?? 'new', g.rows, g.toAssign)
      ],
      unmatchedSample: p.unmatchedSample,
      ambiguousSample: p.ambiguousSample,
      otherGroupSample: p.otherGroupSample,
    );
  }

  /// اجرای انتساب در یک تراکنش. مجموعه‌ی جدید فقط وقتی ساخته می‌شود که [createMissing] درست باشد؛
  /// وگرنه ردیف‌های آن مجموعه‌ها رد می‌شوند. فقط خدمات «بدون مجموعه» پر می‌شوند.
  Future<AssignResult> apply({
    required String path,
    required int categoryId,
    required bool createMissing,
  }) async {
    final plan = await _plan(path, categoryId);
    final db = await DatabaseHelper.instance.database;
    var assigned = 0;
    var created = 0;

    await db.transaction((txn) async {
      final cat = await txn.query('service_categories',
          columns: ['id'], where: 'id = ? AND is_deleted = 0', whereArgs: [categoryId], limit: 1);
      if (cat.isEmpty) throw const ServiceCategoryException('دسته‌بندی انتخاب‌شده وجود ندارد یا بایگانی شده است');

      final idByKey = <String, int>{};
      final existing = await txn.query('service_groups',
          columns: ['id', 'name'], where: 'category_id = ? AND is_active = 1', whereArgs: [categoryId]);
      for (final r in existing) {
        idByKey[_k((r['name'] as String?) ?? '')] = (r['id'] as num).toInt();
      }

      if (createMissing) {
        final maxRow = await txn.rawQuery(
            'SELECT COALESCE(MAX(sort_order), 0) FROM service_groups WHERE category_id = ?', [categoryId]);
        var next = (Sqflite.firstIntValue(maxRow) ?? 0) + 1;
        for (final g in plan.groups.values) {
          if (plan.status[g.key] != 'new') continue;
          final id = await txn.insert('service_groups', {
            'category_id': categoryId,
            'name': g.name,
            'name_key': g.key,
            'sort_order': next++,
            'is_active': 1,
          });
          idByKey[g.key] = id;
          created++;
        }
      }

      for (final e in plan.assignments.entries) {
        final gid = idByKey[e.key];
        if (gid == null) continue;
        final ids = e.value;
        const chunk = 500;
        for (var i = 0; i < ids.length; i += chunk) {
          final part = ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk);
          final ph = List.filled(part.length, '?').join(',');
          assigned += await txn.rawUpdate(
              'UPDATE services SET service_group_id = ? '
              'WHERE service_group_id IS NULL AND is_deleted = 0 AND category_id = ? AND id IN ($ph)',
              [gid, categoryId, ...part]);
        }
      }
    });
    return AssignResult(assigned, created);
  }
}
