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

  // ---------- ساخت رشته‌ی نمایش عدد ----------
  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) {
    final safeValue = value.clamp(min, max).toDouble();
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
          width: 44,
          child: Text(_fmt(value),
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
          height: screenHeight * 0.45,
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ]),
    );
  }
}
