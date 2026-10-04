import '../../models/rate_import_models.dart';
import '../../utils/rate_text_utils.dart';

/// نقش هر ستون در جدول ورودی.
enum ColumnRole {
  ignore,
  title,
  code,
  category,
  brand,
  model,
  vehicle,
  type,
  year,
  minApproved,
  negotiated,
  special,
  general,
  notes,
  unit,
  brandPrice,
}

extension ColumnRoleX on ColumnRole {
  String get label {
    switch (this) {
      case ColumnRole.ignore:
        return 'نادیده';
      case ColumnRole.title:
        return 'عنوان خدمت';
      case ColumnRole.code:
        return 'کد خدمت';
      case ColumnRole.category:
        return 'دسته‌بندی';
      case ColumnRole.brand:
        return 'برند';
      case ColumnRole.model:
        return 'مدل';
      case ColumnRole.vehicle:
        return 'خودرو (برند و مدل)';
      case ColumnRole.type:
        return 'تیپ';
      case ColumnRole.year:
        return 'سال';
      case ColumnRole.minApproved:
        return 'حداقل مصوب';
      case ColumnRole.negotiated:
        return 'نرخ توافقی';
      case ColumnRole.special:
        return 'نرخ ویژه';
      case ColumnRole.general:
        return 'قیمت';
      case ColumnRole.notes:
        return 'توضیحات';
      case ColumnRole.unit:
        return 'واحد پول';
      case ColumnRole.brandPrice:
        return 'قیمت برند (سرستون = نام برند)';
    }
  }
}

class ColumnConfig {
  ColumnConfig(this.index, this.header, this.role);
  final int index;
  final String header;
  ColumnRole role;
}

class SheetMapping {
  SheetMapping({required this.headerRow, required this.columns, this.fillDown = false});

  /// شماره‌ی سطر سرستون (از صفر)
  int headerRow;
  List<ColumnConfig> columns;

  /// پر کردن سلول‌های خالی برند/مدل/دسته/تیپ/سال از ردیف بالا (سلول‌های ادغام‌شده)
  bool fillDown;

  bool get hasTitle => columns.any((c) => c.role == ColumnRole.title);

  bool get hasPrice => columns.any((c) =>
      c.role == ColumnRole.general ||
      c.role == ColumnRole.minApproved ||
      c.role == ColumnRole.negotiated ||
      c.role == ColumnRole.special ||
      c.role == ColumnRole.brandPrice);
}

class ExtractResult {
  const ExtractResult(this.rows, this.skippedNoTitle, this.skippedNoPrice);
  final List<ExtractedRateRow> rows;
  final int skippedNoTitle;
  final int skippedNoPrice;
}

ColumnRole _roleOfField(PriceField f) {
  switch (f) {
    case PriceField.general:
      return ColumnRole.general;
    case PriceField.minApproved:
      return ColumnRole.minApproved;
    case PriceField.negotiated:
      return ColumnRole.negotiated;
    case PriceField.special:
      return ColumnRole.special;
  }
}

/// تبدیل جدول خام به ردیف‌های استاندارد نرخ خدمات.
/// این کلاس مستقل از منبع است (Excel / PDF / OCR) و به دیتابیس دسترسی ندارد.
class RateTableMapper {
  RateTableMapper({Set<String>? knownBrandNorms}) : knownBrandNorms = knownBrandNorms ?? <String>{};

  /// نام‌های نرمال‌شده‌ی برندهای موجود؛ برای تشخیص ستون‌های «قیمت به‌تفکیک برند».
  final Set<String> knownBrandNorms;

  ColumnRole? _roleByKeyword(String n) {
    bool has(List<String> ks) => ks.any((k) => n.contains(k));
    if (has(['توافق'])) return ColumnRole.negotiated;
    if (has(['ویژه'])) return ColumnRole.special;
    if (has(['حداقل', 'مصوب'])) return ColumnRole.minApproved;
    if (has(['کد'])) return ColumnRole.code;
    if (has(['توضیح'])) return ColumnRole.notes;
    if (has(['سال'])) return ColumnRole.year;
    if (has(['تیپ'])) return ColumnRole.type;
    if (has(['مدل'])) return ColumnRole.model;
    if (has(['برند'])) return ColumnRole.brand;
    if (has(['خودرو'])) return ColumnRole.vehicle;
    if (has(['دسته'])) return ColumnRole.category;
    if (has(['واحد'])) return ColumnRole.unit;
    if (has(['خدمت', 'خدمات']) && !has(['قیمت', 'نرخ', 'مبلغ'])) return ColumnRole.title;
    if (has(['قیمت', 'نرخ', 'مبلغ', 'هزینه', 'اجرت', 'تومان', 'ریال'])) return ColumnRole.general;
    if (has(['خدمت', 'خدمات', 'شرح', 'عنوان', 'تعمیر', 'نام'])) return ColumnRole.title;
    return null;
  }

  ColumnRole guessRole(String header) {
    final n = RateText.normalize(header);
    if (n.isEmpty) return ColumnRole.ignore;
    final kw = _roleByKeyword(n);
    if (kw != null) return kw;
    if (knownBrandNorms.contains(n)) return ColumnRole.brandPrice;
    return ColumnRole.ignore;
  }

  int guessHeaderRow(RawTable t) {
    var best = 0;
    var bestScore = -1;
    final limit = t.rows.length < 10 ? t.rows.length : 10;
    for (var r = 0; r < limit; r++) {
      var score = 0;
      for (final cell in t.rows[r]) {
        if (_roleByKeyword(RateText.normalize(cell)) != null) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return best;
  }

  SheetMapping guessMapping(RawTable t, {int? headerRow}) {
    final hr = headerRow ?? guessHeaderRow(t);
    var colCount = 0;
    for (final row in t.rows) {
      if (row.length > colCount) colCount = row.length;
    }
    final header = hr < t.rows.length ? t.rows[hr] : const <String>[];
    final cols = <ColumnConfig>[];
    var titleTaken = false;
    for (var i = 0; i < colCount; i++) {
      final h = i < header.length ? header[i].trim() : '';
      var role = guessRole(h);
      // فقط اولین ستون عنوان به‌صورت خودکار انتخاب می‌شود
      if (role == ColumnRole.title) {
        if (titleTaken) {
          role = ColumnRole.ignore;
        } else {
          titleTaken = true;
        }
      }
      cols.add(ColumnConfig(i, h, role));
    }
    return SheetMapping(headerRow: hr, columns: cols);
  }

  String? _unitFromHeader(String header) {
    final n = RateText.normalize(header);
    if (n.contains('ریال')) return 'rial';
    if (n.contains('تومان')) return 'toman';
    return null;
  }

  String _cleanNum(String s) {
    final t = s.trim();
    if (RegExp(r'^\d+\.0+$').hasMatch(RateText.toLatinDigits(t))) {
      return RateText.toLatinDigits(t).split('.').first;
    }
    return t;
  }

  String? _nz(String s) => s.isEmpty ? null : s;

  ExtractResult extract(RawTable t, SheetMapping m, {required int Function() nextId}) {
    final out = <ExtractedRateRow>[];
    var skippedNoTitle = 0;
    var skippedNoPrice = 0;

    ColumnConfig? first(ColumnRole role) {
      for (final c in m.columns) {
        if (c.role == role) return c;
      }
      return null;
    }

    final titleCol = first(ColumnRole.title);
    if (titleCol == null) return const ExtractResult([], 0, 0);
    final codeCol = first(ColumnRole.code);
    final categoryCol = first(ColumnRole.category);
    final brandCol = first(ColumnRole.brand);
    final modelCol = first(ColumnRole.model);
    final vehicleCol = first(ColumnRole.vehicle);
    final typeCol = first(ColumnRole.type);
    final yearCol = first(ColumnRole.year);
    final notesCol = first(ColumnRole.notes);
    final unitCol = first(ColumnRole.unit);
    final priceCols = <PriceField, ColumnConfig>{};
    for (final f in PriceField.values) {
      final c = first(_roleOfField(f));
      if (c != null) priceCols[f] = c;
    }
    final brandPriceCols = m.columns.where((c) => c.role == ColumnRole.brandPrice).toList();

    const fillRoles = {
      ColumnRole.category,
      ColumnRole.brand,
      ColumnRole.model,
      ColumnRole.vehicle,
      ColumnRole.type,
      ColumnRole.year,
    };
    final carry = <ColumnRole, String>{};

    for (var r = m.headerRow + 1; r < t.rows.length; r++) {
      final cells = t.rows[r];
      if (cells.every((e) => e.trim().isEmpty)) continue;

      String cell(ColumnConfig? c) => (c == null || c.index >= cells.length) ? '' : cells[c.index].trim();

      String ctx(ColumnRole role, ColumnConfig? c) {
        final v = cell(c);
        if (!m.fillDown || !fillRoles.contains(role)) return v;
        if (v.isNotEmpty) {
          carry[role] = v;
          if (role == ColumnRole.brand) carry.remove(ColumnRole.model);
          return v;
        }
        return carry[role] ?? '';
      }

      final category = ctx(ColumnRole.category, categoryCol);
      final brand = ctx(ColumnRole.brand, brandCol);
      final model = ctx(ColumnRole.model, modelCol);
      final vehicle = ctx(ColumnRole.vehicle, vehicleCol);
      final type = ctx(ColumnRole.type, typeCol);
      final year = _cleanNum(ctx(ColumnRole.year, yearCol));
      final title = cell(titleCol);
      final code = _cleanNum(cell(codeCol));
      final notes = cell(notesCol);
      final unitCellNorm = RateText.normalize(cell(unitCol));
      final String? unitFromCell =
          unitCellNorm.contains('ریال') ? 'rial' : (unitCellNorm.contains('تومان') ? 'toman' : null);

      // قیمت‌های ستون‌های معمولی
      final flags = <String>[];
      String? unit = unitFromCell;
      final base = <PriceField, double?>{};
      var anyPriceCell = false;
      for (final e in priceCols.entries) {
        final raw = cell(e.value);
        if (raw.isEmpty) continue;
        anyPriceCell = true;
        final pa = RateText.parseAmount(raw);
        if (pa.problem != null) flags.add('قیمت «${e.key.label}»: ${pa.problem}');
        base[e.key] = pa.value;
        unit ??= pa.unit ?? _unitFromHeader(e.value.header);
      }

      // قیمت‌های ستون‌های «برند»
      final brandPrices = <(ColumnConfig, ParsedAmount)>[];
      for (final c in brandPriceCols) {
        final raw = cell(c);
        if (raw.isEmpty) continue;
        anyPriceCell = true;
        brandPrices.add((c, RateText.parseAmount(raw)));
      }

      if (!anyPriceCell) {
        if (title.isNotEmpty) skippedNoPrice++;
        continue;
      }
      if (title.isEmpty) {
        skippedNoTitle++;
        continue;
      }

      ExtractedRateRow make() {
        final row = ExtractedRateRow(
          localId: nextId(),
          title: title,
          sourceLabel: '${t.name} · ردیف ${r + 1}',
        );
        row.code = _nz(code);
        row.categoryText = _nz(category);
        row.brandText = _nz(brand);
        row.modelText = _nz(model);
        row.vehicleText = _nz(vehicle);
        row.type = _nz(type);
        row.year = _nz(year);
        row.notes = _nz(notes);
        return row;
      }

      if (base.isNotEmpty) {
        final row = make();
        for (final e in base.entries) {
          row.setPrice(e.key, e.value);
        }
        row.unit = unit;
        row.extractionFlags.addAll(flags);
        out.add(row);
      }

      for (final bp in brandPrices) {
        final row = make();
        row.brandText = bp.$1.header.trim();
        row.vehicleText = null;
        row.general = bp.$2.value;
        row.unit = bp.$2.unit ?? unitFromCell ?? _unitFromHeader(bp.$1.header);
        if (bp.$2.problem != null) {
          row.extractionFlags.add('قیمت «${row.brandText}»: ${bp.$2.problem}');
        }
        out.add(row);
      }
    }
    return ExtractResult(out, skippedNoTitle, skippedNoPrice);
  }
}
