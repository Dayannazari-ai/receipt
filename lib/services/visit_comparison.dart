import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/invoice.dart';
import '../repositories/invoice_visit_repository.dart';
import '../utils/persian_date.dart';

/// گزارش کوچک «کارکرد و فاصله از آخرین مراجعه» بالای امضای مشتری.
/// همه‌ی مقادیر از سوابق واقعی همان خودرو محاسبه می‌شوند؛ چیزی ذخیره
/// یا در فاکتور قبلی تغییر نمی‌کند. اگر خودرو یا مراجعه‌ی قبلی نباشد، null
/// برمی‌گردد و جدول اصلاً چاپ نمی‌شود.
class VisitComparison {
  static const double _fontSize = 6.5;
  static const double _borderWidth = 0.4;
  static const double _verticalPadding = 1.5;
  static const double _kmColumnFlex = 1.4;
  static const double _daysColumnFlex = 1.0;

  final String kmText;
  final String daysText;
  const VisitComparison._(this.kmText, this.daysText);

  static Future<VisitComparison?> load(Invoice invoice) async {
    final vehicleId = invoice.vehicleId;
    if (vehicleId == null) return null;
    try {
      final prev = await InvoiceVisitRepository().getPreviousVisit(
        vehicleId: vehicleId,
        issueDate: invoice.issueDate,
        excludeInvoiceId: invoice.id,
      );
      if (prev == null) return null;

      final cur = DateTime.tryParse(invoice.issueDate);
      final old = DateTime.tryParse(prev.issueDate);
      if (cur == null || old == null) return null;
      final days = DateTime.utc(cur.year, cur.month, cur.day)
          .difference(DateTime.utc(old.year, old.month, old.day))
          .inDays;
      if (days < 0) return null;

      final curKm = invoice.mileageKm;
      final prevKm = prev.mileageKm;
      final String kmValue;
      if (curKm == null || curKm <= 0) {
        kmValue = 'کیلومتر فعلی ثبت نشده';
      } else if (prevKm == null || prevKm <= 0) {
        kmValue = 'کیلومتر مراجعه قبلی ثبت نشده';
      } else if (curKm < prevKm) {
        kmValue = 'کیلومتر فعلی کمتر از قبلی است (بررسی شود)';
      } else {
        kmValue = '${PersianDateUtil.toPersianDigits('${curKm - prevKm}')} کیلومتر';
      }

      return VisitComparison._(
        'میزان کارکرد خودرو نسبت به آخرین مراجعه: $kmValue',
        'مدت‌زمان از آخرین مراجعه: ${PersianDateUtil.toPersianDigits('$days')} روز',
      );
    } catch (_) {
      return null;
    }
  }

  /// جدول یک‌ردیفه و دوستونه. ترتیب لیست فیزیکی (چپ به راست) است:
  /// ستون اول (راست) = کیلومتر، ستون دوم (چپ) = مدت‌زمان.
  pw.Widget build({
    required PdfColor borderColor,
    required PdfColor textColor,
    required double horizontalPadding,
  }) {
    pw.Widget cell(String text) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: pw.EdgeInsets.symmetric(horizontal: horizontalPadding + 1, vertical: _verticalPadding),
          child: pw.Text(text,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: _fontSize, color: textColor)),
        );
    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: _borderWidth),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(_daysColumnFlex),
        1: pw.FlexColumnWidth(_kmColumnFlex),
      },
      children: [
        pw.TableRow(children: [cell(daysText), cell(kmText)]),
      ],
    );
  }
}
