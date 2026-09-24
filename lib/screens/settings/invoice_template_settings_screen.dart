import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/app_settings.dart';
import '../../models/customer.dart';
import '../../models/invoice.dart';
import '../../models/invoice_layout_settings.dart';
import '../../repositories/settings_repository.dart';
import '../../services/invoice_layout_storage.dart';
import '../../services/pdf_service.dart';

/// صفحه‌ی «تنظیمات قالب فاکتور» با پیش‌نمایش زنده.
///
/// پیش‌نمایش با همان [PdfService.generateInvoicePdf] ساخته می‌شود که PDF
/// واقعی فاکتور را می‌سازد؛ هیچ Layout جداگانه‌ای برای پیش‌نمایش وجود ندارد.
class InvoiceTemplateSettingsScreen extends StatefulWidget {
  const InvoiceTemplateSettingsScreen({super.key});

  @override
  State<InvoiceTemplateSettingsScreen> createState() => _InvoiceTemplateSettingsScreenState();
}

class _InvoiceTemplateSettingsScreenState extends State<InvoiceTemplateSettingsScreen> {
  static const Duration _debounce = Duration(milliseconds: 350);

  InvoiceLayoutSettings _layout = InvoiceLayoutSettings.defaults;
  AppSettings _appSettings = AppSettings();
  bool _loading = true;

  /// با هر افزایش این عدد، PdfPreview دوباره ساخته می‌شود.
  int _previewVersion = 0;
  Timer? _timer;

  // ---------- فاکتور نمونه (فقط در حافظه، برای پیش‌نمایش) ----------
  late final Invoice _sampleInvoice = Invoice(
    invoiceNumber: 'B/1015',
    type: InvoiceType.electrical,
    issueDate: DateTime.now().toIso8601String(),
    itemsTotal: 2900000,
    sideCosts: 500000,
    finalAmount: 3400000,
    paymentType: PaymentType.cash,
  );

  late final List<InvoiceItem> _sampleItems = [
    InvoiceItem(
      invoiceId: 0,
      itemType: InvoiceItemType.service,
      description: 'اجرت شارژ و گاز R134 و تزریق گاز',
      quantity: 1,
      unitPrice: 200000,
      total: 200000,
    ),
    InvoiceItem(
      invoiceId: 0,
      itemType: InvoiceItemType.service,
      description: 'باز و بست اوپراتور با داشبورد',
      quantity: 1,
      unitPrice: 1200000,
      total: 1200000,
    ),
    InvoiceItem(
      invoiceId: 0,
      itemType: InvoiceItemType.service,
      description: 'باز و بست کندانسور',
      quantity: 1,
      unitPrice: 1500000,
      total: 1500000,
    ),
  ];

  late final List<SideCost> _sampleSideCosts = [
    SideCost(invoiceId: 0, title: 'تست نشت و تعویض کله اورینگ ها', amount: 500000),
  ];

  final Customer _sampleCustomer = Customer(name: 'آقای نمونه', mobile: '09120000000');

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final layout = await InvoiceLayoutStorage.load();
    AppSettings settings;
    try {
      settings = await SettingsRepository().getSettings();
    } catch (_) {
      settings = AppSettings();
    }
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _appSettings = settings;
      _loading = false;
    });
  }

  /// اعمال تغییر: فوراً روی صفحه دیده می‌شود، ولی ذخیره و ساخت مجدد
  /// پیش‌نمایش با تأخیر انجام می‌شود تا هنگام کشیدن Slider فشار نیاید.
  void _update(InvoiceLayoutSettings next) {
    setState(() => _layout = next);
    _timer?.cancel();
    _timer = Timer(_debounce, () async {
      await InvoiceLayoutStorage.save(_layout);
      if (mounted) setState(() => _previewVersion++);
    });
  }

  /// اعمال فوری بدون تأخیر (برای انتخاب رنگ که رویداد پیوسته نیست).
  void _updateImmediate(InvoiceLayoutSettings next) {
    _timer?.cancel();
    setState(() {
      _layout = next;
      _previewVersion++;
    });
    InvoiceLayoutStorage.save(_layout);
  }

  // ---------- ساخت رشته‌ی نمایش عدد ----------
  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  /// نمایش سه‌رقم اعشار برای عرض ستون‌ها (مثلاً ۰.۰۸۰ و ۰.۵۲۰).
  String _fmtWidth(double v) => v.toStringAsFixed(3);

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
    String Function(double)? format,
  }) {
    final safeValue = value.clamp(min, max).toDouble();
    final display = format ?? _fmt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: safeValue,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(display(value),
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _groupHeader(String title, VoidCallback onReset) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        TextButton.icon(
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('بازنشانی گروه'),
          onPressed: onReset,
        ),
      ]),
    );
  }

  // ---------- گروه لوگو ----------
  void _resetLogoGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _update(_layout.copyWith(
      logoImageHeight: d.logoImageHeight,
      logoOffsetX: d.logoOffsetX,
      logoOffsetY: d.logoOffsetY,
    ));
  }

  List<Widget> _logoGroup() => [
        _groupHeader('لوگو', _resetLogoGroup),
        _sliderRow(
          label: 'اندازه لوگو',
          value: _layout.logoImageHeight,
          min: 10,
          max: 100,
          onChanged: (v) => _update(_layout.copyWith(logoImageHeight: v)),
        ),
        _sliderRow(
          label: 'موقعیت افقی',
          value: _layout.logoOffsetX,
          min: -60,
          max: 60,
          onChanged: (v) => _update(_layout.copyWith(logoOffsetX: v)),
        ),
        _sliderRow(
          label: 'موقعیت عمودی',
          value: _layout.logoOffsetY,
          min: -60,
          max: 60,
          onChanged: (v) => _update(_layout.copyWith(logoOffsetY: v)),
        ),
      ];

  // ---------- گروه سربرگ ----------
  void _resetHeaderGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _update(_layout.copyWith(
      headerPaddingTop: d.headerPaddingTop,
      headerPaddingBottom: d.headerPaddingBottom,
      headerLogoToContactSpacing: d.headerLogoToContactSpacing,
      headerIconToTextSpacing: d.headerIconToTextSpacing,
      headerCompanyNameFontSize: d.headerCompanyNameFontSize,
      headerContactFontSize: d.headerContactFontSize,
      headerSubTitleFontSize: d.headerSubTitleFontSize,
    ));
  }

  List<Widget> _headerGroup() => [
        _groupHeader('سربرگ', _resetHeaderGroup),
        _sliderRow(
          label: 'فاصله بالای سربرگ',
          value: _layout.headerPaddingTop,
          min: 0,
          max: 30,
          onChanged: (v) => _update(_layout.copyWith(headerPaddingTop: v)),
        ),
        _sliderRow(
          label: 'فاصله پایین سربرگ',
          value: _layout.headerPaddingBottom,
          min: 0,
          max: 30,
          onChanged: (v) => _update(_layout.copyWith(headerPaddingBottom: v)),
        ),
        _sliderRow(
          label: 'فاصله لوگو تا تماس',
          value: _layout.headerLogoToContactSpacing,
          min: 0,
          max: 20,
          onChanged: (v) => _update(_layout.copyWith(headerLogoToContactSpacing: v)),
        ),
        _sliderRow(
          label: 'فاصله آیکون از متن',
          value: _layout.headerIconToTextSpacing,
          min: 0,
          max: 15,
          onChanged: (v) => _update(_layout.copyWith(headerIconToTextSpacing: v)),
        ),
        _sliderRow(
          label: 'اندازه عنوان',
          value: _layout.headerCompanyNameFontSize,
          min: 6,
          max: 24,
          onChanged: (v) => _update(_layout.copyWith(headerCompanyNameFontSize: v)),
        ),
        _sliderRow(
          label: 'اندازه شماره تماس',
          value: _layout.headerContactFontSize,
          min: 4,
          max: 16,
          onChanged: (v) => _update(_layout.copyWith(headerContactFontSize: v)),
        ),
        _sliderRow(
          label: 'اندازه آدرس',
          value: _layout.headerSubTitleFontSize,
          min: 4,
          max: 16,
          onChanged: (v) => _update(_layout.copyWith(headerSubTitleFontSize: v)),
        ),
      ];

  // ---------- گروه جدول ----------
  void _resetTableGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _update(_layout.copyWith(
      tableRowVerticalPadding: d.tableRowVerticalPadding,
      tableCellFontSize: d.tableCellFontSize,
      tableHeaderFontSize: d.tableHeaderFontSize,
      colWidthRow: d.colWidthRow,
      colWidthDescription: d.colWidthDescription,
      colWidthUnitPrice: d.colWidthUnitPrice,
      colWidthTotalPrice: d.colWidthTotalPrice,
      tableCellHorizontalPadding: d.tableCellHorizontalPadding,
    ));
  }

  /// مجموع عرض ستون‌ها (فقط برای نمایش؛ در PDF فقط نسبت‌ها مهم‌اند).
  double get _colWidthSum =>
      _layout.colWidthRow + _layout.colWidthDescription + _layout.colWidthUnitPrice + _layout.colWidthTotalPrice;

  String _percentOfSum(double v) {
    final sum = _colWidthSum;
    if (sum <= 0) return '۰٪';
    return '${(v / sum * 100).toStringAsFixed(0)}٪';
  }

  Widget _columnWidthRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(children: [
      _sliderRow(
        label: label,
        value: value,
        min: 0.02,
        max: 0.4,
        onChanged: onChanged,
        format: _fmtWidth,
      ),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 12),
          child: Text('سهم از عرض جدول: ${_percentOfSum(value)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
      ),
    ]);
  }

  List<Widget> _tableGroup() => [
        _groupHeader('جدول', _resetTableGroup),
        _sliderRow(
          label: 'ارتفاع ردیف',
          value: _layout.tableRowVerticalPadding,
          min: 0,
          max: 10,
          onChanged: (v) => _update(_layout.copyWith(tableRowVerticalPadding: v)),
        ),
        _sliderRow(
          label: 'اندازه فونت جدول',
          value: _layout.tableCellFontSize,
          min: 4,
          max: 16,
          onChanged: (v) => _update(_layout.copyWith(tableCellFontSize: v, tableHeaderFontSize: v)),
        ),
        _sliderRow(
          label: 'فاصله داخلی سلول',
          value: _layout.tableCellHorizontalPadding,
          min: 0,
          max: 10,
          onChanged: (v) => _update(_layout.copyWith(tableCellHorizontalPadding: v)),
        ),
        const SizedBox(height: 6),
        const Text('عرض ستون‌ها (نسبت‌ها مهم‌اند، نه اعداد مطلق)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        _columnWidthRow(
          label: 'ستون ردیف',
          value: _layout.colWidthRow,
          onChanged: (v) => _update(_layout.copyWith(colWidthRow: v)),
        ),
        _columnWidthRow(
          label: 'ستون شرح',
          value: _layout.colWidthDescription,
          onChanged: (v) => _update(_layout.copyWith(colWidthDescription: v)),
        ),
        _columnWidthRow(
          label: 'ستون قیمت واحد',
          value: _layout.colWidthUnitPrice,
          onChanged: (v) => _update(_layout.copyWith(colWidthUnitPrice: v)),
        ),
        _columnWidthRow(
          label: 'ستون قیمت کل',
          value: _layout.colWidthTotalPrice,
          onChanged: (v) => _update(_layout.copyWith(colWidthTotalPrice: v)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('مجموع عرض ستون‌ها: ${_fmtWidth(_colWidthSum)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ];

  // ---------- گروه مشتری ----------
  void _resetCustomerGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _update(_layout.copyWith(
      customerBoxFontSize: d.customerBoxFontSize,
      spacingAfterCustomerBox: d.spacingAfterCustomerBox,
      customerBoxHeight: d.customerBoxHeight,
    ));
  }

  List<Widget> _customerGroup() => [
        _groupHeader('مشتری', _resetCustomerGroup),
        _sliderRow(
          label: 'اندازه فونت',
          value: _layout.customerBoxFontSize,
          min: 4,
          max: 16,
          onChanged: (v) => _update(_layout.copyWith(customerBoxFontSize: v)),
        ),
        _sliderRow(
          label: 'فاصله تا جدول',
          value: _layout.spacingAfterCustomerBox,
          min: 0,
          max: 24,
          onChanged: (v) => _update(_layout.copyWith(spacingAfterCustomerBox: v)),
        ),
        _sliderRow(
          label: 'ارتفاع بخش (۰=خودکار)',
          value: _layout.customerBoxHeight,
          min: 0,
          max: 60,
          onChanged: (v) => _update(_layout.copyWith(customerBoxHeight: v)),
        ),
      ];

  // ---------- گروه جمع کل ----------
  void _resetTotalsGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _update(_layout.copyWith(
      totalsBoldFontSize: d.totalsBoldFontSize,
      totalsBoxVerticalPadding: d.totalsBoxVerticalPadding,
      totalsBoxHorizontalPadding: d.totalsBoxHorizontalPadding,
      spacingAfterTotals: d.spacingAfterTotals,
    ));
  }

  List<Widget> _totalsGroup() => [
        _groupHeader('جمع کل', _resetTotalsGroup),
        _sliderRow(
          label: 'اندازه فونت',
          value: _layout.totalsBoldFontSize,
          min: 6,
          max: 20,
          onChanged: (v) => _update(_layout.copyWith(totalsBoldFontSize: v)),
        ),
        _sliderRow(
          label: 'ارتفاع کادر (عمودی)',
          value: _layout.totalsBoxVerticalPadding,
          min: 0,
          max: 16,
          onChanged: (v) => _update(_layout.copyWith(totalsBoxVerticalPadding: v)),
        ),
        _sliderRow(
          label: 'عرض کادر (افقی)',
          value: _layout.totalsBoxHorizontalPadding,
          min: 0,
          max: 20,
          onChanged: (v) => _update(_layout.copyWith(totalsBoxHorizontalPadding: v)),
        ),
        _sliderRow(
          label: 'فاصله بعد از جمع کل',
          value: _layout.spacingAfterTotals,
          min: 0,
          max: 24,
          onChanged: (v) => _update(_layout.copyWith(spacingAfterTotals: v)),
        ),
      ];

  // ---------- گروه نکات مهم ----------
  void _resetTermsGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _update(_layout.copyWith(
      termsFontSize: d.termsFontSize,
      termsColumnDividerMargin: d.termsColumnDividerMargin,
      termsLineSpacing: d.termsLineSpacing,
      termsBoxPadding: d.termsBoxPadding,
    ));
  }

  List<Widget> _termsGroup() => [
        _groupHeader('نکات مهم', _resetTermsGroup),
        _sliderRow(
          label: 'اندازه فونت',
          value: _layout.termsFontSize,
          min: 4,
          max: 14,
          onChanged: (v) => _update(_layout.copyWith(termsFontSize: v)),
        ),
        _sliderRow(
          label: 'فاصله بین دو ستون',
          value: _layout.termsColumnDividerMargin,
          min: 0,
          max: 20,
          onChanged: (v) => _update(_layout.copyWith(termsColumnDividerMargin: v)),
        ),
        _sliderRow(
          label: 'فاصله بین خطوط',
          value: _layout.termsLineSpacing,
          min: 0,
          max: 10,
          onChanged: (v) => _update(_layout.copyWith(termsLineSpacing: v)),
        ),
        _sliderRow(
          label: 'ارتفاع بخش (پدینگ)',
          value: _layout.termsBoxPadding,
          min: 0,
          max: 16,
          onChanged: (v) => _update(_layout.copyWith(termsBoxPadding: v)),
        ),
      ];

  // ---------- گروه امضا و مهر ----------
  void _resetSignatureGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _update(_layout.copyWith(
      stampImageSize: d.stampImageSize,
      signatureOffsetX: d.signatureOffsetX,
      signatureOffsetY: d.signatureOffsetY,
    ));
  }

  List<Widget> _signatureGroup() => [
        _groupHeader('امضا و مهر', _resetSignatureGroup),
        _sliderRow(
          label: 'اندازه مهر',
          value: _layout.stampImageSize,
          min: 20,
          max: 100,
          onChanged: (v) => _update(_layout.copyWith(stampImageSize: v)),
        ),
        _sliderRow(
          label: 'موقعیت افقی',
          value: _layout.signatureOffsetX,
          min: -60,
          max: 60,
          onChanged: (v) => _update(_layout.copyWith(signatureOffsetX: v)),
        ),
        _sliderRow(
          label: 'موقعیت عمودی',
          value: _layout.signatureOffsetY,
          min: -60,
          max: 60,
          onChanged: (v) => _update(_layout.copyWith(signatureOffsetY: v)),
        ),
      ];

  // ---------- گروه حاشیه صفحه ----------
  void _resetMarginGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _update(_layout.copyWith(
      pageMarginTop: d.pageMarginTop,
      pageMarginBottom: d.pageMarginBottom,
      pageMarginLeft: d.pageMarginLeft,
      pageMarginRight: d.pageMarginRight,
    ));
  }

  List<Widget> _marginGroup() => [
        _groupHeader('حاشیه صفحه', _resetMarginGroup),
        _sliderRow(
          label: 'حاشیه بالا',
          value: _layout.pageMarginTop,
          min: 0,
          max: 40,
          onChanged: (v) => _update(_layout.copyWith(pageMarginTop: v)),
        ),
        _sliderRow(
          label: 'حاشیه پایین',
          value: _layout.pageMarginBottom,
          min: 0,
          max: 40,
          onChanged: (v) => _update(_layout.copyWith(pageMarginBottom: v)),
        ),
        _sliderRow(
          label: 'حاشیه چپ',
          value: _layout.pageMarginLeft,
          min: 0,
          max: 40,
          onChanged: (v) => _update(_layout.copyWith(pageMarginLeft: v)),
        ),
        _sliderRow(
          label: 'حاشیه راست',
          value: _layout.pageMarginRight,
          min: 0,
          max: 40,
          onChanged: (v) => _update(_layout.copyWith(pageMarginRight: v)),
        ),
      ];

  // ---------- گروه رنگ‌ها ----------
  static const List<int> _colorPalette = [
    0xFFE87722, // نارنجی پیش‌فرض
    0xFFD64545,
    0xFF2E8B57,
    0xFF1E5F74,
    0xFF6B4EFF,
    0xFF00838F,
    0xFF2B2B2B, // خاکستری تیره پیش‌فرض
    0xFF616161,
    0xFF9E9E9E,
    0xFFBDBDBD, // خاکستری روشن (حاشیه پیش‌فرض)
    0xFF000000, // مشکی (متن پیش‌فرض)
    0xFFFFFFFF,
  ];

  void _resetColorsGroup() {
    const d = InvoiceLayoutSettings.defaults;
    _updateImmediate(_layout.copyWith(
      colorOrange: d.colorOrange,
      colorDarkGray: d.colorDarkGray,
      colorText: d.colorText,
      colorBorder: d.colorBorder,
    ));
  }

  Widget _colorPickerRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Color(value),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _colorPalette.map((hex) {
            final selected = hex == value;
            return GestureDetector(
              onTap: () => onChanged(hex),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color(hex),
                  shape: BoxShape.circle,
                  border: selected ? Border.all(color: Colors.black, width: 2.5) : null,
                ),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  List<Widget> _colorsGroup() => [
        _groupHeader('رنگ‌ها', _resetColorsGroup),
        _colorPickerRow(
          label: 'رنگ نارنجی اصلی',
          value: _layout.colorOrange,
          onChanged: (v) => _updateImmediate(_layout.copyWith(colorOrange: v)),
        ),
        _colorPickerRow(
          label: 'رنگ خاکستری تیره',
          value: _layout.colorDarkGray,
          onChanged: (v) => _updateImmediate(_layout.copyWith(colorDarkGray: v)),
        ),
        _colorPickerRow(
          label: 'رنگ متن',
          value: _layout.colorText,
          onChanged: (v) => _updateImmediate(_layout.copyWith(colorText: v)),
        ),
        _colorPickerRow(
          label: 'رنگ خطوط',
          value: _layout.colorBorder,
          onChanged: (v) => _updateImmediate(_layout.copyWith(colorBorder: v)),
        ),
      ];

  // ---------- بازنشانی همه ----------
  Future<void> _confirmResetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بازنشانی همه تنظیمات'),
        content: const Text('تمام تنظیمات قالب فاکتور به مقادیر پیش‌فرض بازمی‌گردند. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('بازنشانی همه', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _timer?.cancel();
    await InvoiceLayoutStorage.resetAll();
    if (!mounted) return;
    setState(() {
      _layout = InvoiceLayoutSettings.defaults;
      _previewVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات قالب فاکتور')),
      body: Column(children: [
        // ---------- پیش‌نمایش زنده ----------
        SizedBox(
          height: screenHeight * 0.4,
          child: PdfPreview(
            key: ValueKey(_previewVersion),
            build: (format) async {
              final file = await PdfService.generateInvoicePdf(
                invoice: _sampleInvoice,
                items: _sampleItems,
                sideCosts: _sampleSideCosts,
                customer: _sampleCustomer,
                settings: _appSettings,
                layout: _layout,
              );
              return file.readAsBytes();
            },
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
          ),
        ),
        const Divider(height: 1),
        // ---------- تنظیمات ----------
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              ..._logoGroup(),
              const Divider(),
              ..._headerGroup(),
              const Divider(),
              ..._tableGroup(),
              const Divider(),
              ..._customerGroup(),
              const Divider(),
              ..._totalsGroup(),
              const Divider(),
              ..._termsGroup(),
              const Divider(),
              ..._signatureGroup(),
              const Divider(),
              ..._marginGroup(),
              const Divider(),
              ..._colorsGroup(),
              const SizedBox(height: 20),
              const Divider(thickness: 1.2),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.settings_backup_restore, color: Colors.red),
                  label: const Text('بازنشانی همه تنظیمات', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                  onPressed: _confirmResetAll,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ]),
    );
  }
}
