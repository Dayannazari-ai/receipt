import '../models/invoice.dart';
import '../repositories/invoice_payment_repository.dart';
import '../repositories/invoice_repository.dart';

class InvoiceCartLine {
  final InvoiceItemType itemType;
  final int? serviceId;
  final int? productId;
  final String description;
  String? itemCode; // کد کالا/خدمت؛ قابل ویرایش دستی توسط کاربر
  int quantity;
  double unitPrice;

  InvoiceCartLine({
    required this.itemType,
    this.serviceId,
    this.productId,
    required this.description,
    this.itemCode,
    this.quantity = 1,
    required this.unitPrice,
  });

  double get total => unitPrice * quantity;
}

class SideCostLine {
  String title;
  double amount;
  SideCostLine({required this.title, required this.amount});
}

class InvoiceService {
  final _invoiceRepo = InvoiceRepository();

  Future<String> nextInvoiceNumber(InvoiceType type) => _invoiceRepo.getNextInvoiceNumber(type);

  /// شماره‌های آزادشده‌ی (باطل‌شده) این نوع فاکتور که قابل انتخاب دستی‌اند.
  Future<List<String>> freedNumbers(InvoiceType type) => _invoiceRepo.getFreedNumbers(type);

  /// صدور فاکتور اصلی. [vehicleId] اختیاری است؛ فاکتور بدون خودرو هم مجاز است.
  /// [financePay]: تیک «پرداخت از حساب فروش کالا» (فقط برای فاکتور خرید کالا).
  /// [mileageKm]: کیلومتر مراجعه‌ی خودرو (اختیاری).
  /// [manualInvoiceNumber]: شماره‌ی انتخاب‌شده‌ی دستی (فقط شماره‌ی بعدیِ
  /// خودکار یا یکی از شماره‌های آزادشده‌ی همین نوع مجاز است). اگر خالی باشد،
  /// شماره‌ی بعدی خودکار گرفته می‌شود. تکراری نبودن شماره داخل تراکنش
  /// createInvoice هم دوباره بررسی می‌شود.
  /// [paymentLines]: ردیف‌های «پرداخت ترکیبی» (فقط وقتی paymentType = combined).
  Future<int> issueInvoice({
    required InvoiceType type,
    int? customerId,
    int? vehicleId,
    required List<InvoiceCartLine> lines,
    required List<SideCostLine> sideCosts,
    required PaymentType paymentType,
    String? paymentAccountInfo,
    String? notes,
    DateTime? issueDateTime,
    String? checkDueDate,
    bool financePay = false,
    int? mileageKm,
    String? manualInvoiceNumber,
    List<PaymentLine> paymentLines = const [],
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('حداقل یک ردیف باید اضافه شود');
    }
    final String invoiceNumber;
    final manual = manualInvoiceNumber?.trim() ?? '';
    if (manual.isNotEmpty) {
      final next = await nextInvoiceNumber(type);
      if (manual != next) {
        final freed = await _invoiceRepo.getFreedNumbers(type);
        if (!freed.contains(manual)) {
          throw StateError('این شماره‌ی فاکتور دیگر در دسترس نیست؛ شماره را دوباره انتخاب کنید');
        }
      }
      invoiceNumber = manual;
    } else {
      invoiceNumber = await nextInvoiceNumber(type);
    }
    final itemsTotal = lines.fold(0.0, (s, l) => s + l.total);
    final sideCostsTotal = sideCosts.fold(0.0, (s, c) => s + c.amount);
    final finalAmount = itemsTotal + sideCostsTotal;

    if (paymentType == PaymentType.combined) {
      final err = PaymentLine.validate(paymentLines, finalAmount);
      if (err != null) throw StateError(err);
    }

    final invoice = Invoice(
      invoiceNumber: invoiceNumber,
      type: type,
      customerId: customerId,
      vehicleId: vehicleId,
      issueDate: (issueDateTime ?? DateTime.now()).toIso8601String(),
      itemsTotal: itemsTotal,
      sideCosts: sideCostsTotal,
      finalAmount: finalAmount,
      paymentType: paymentType,
      paymentAccountInfo: paymentAccountInfo,
      checkDueDate: checkDueDate,
      notes: notes,
      isDraft: 0,
      mileageKm: mileageKm,
    );

    final items = lines
        .map((l) => InvoiceItem(
              invoiceId: 0,
              itemType: l.itemType,
              serviceId: l.serviceId,
              productId: l.productId,
              description: l.description,
              itemCode: l.itemCode,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
              total: l.total,
            ))
        .toList();

    final sideCostModels =
        sideCosts.map((c) => SideCost(invoiceId: 0, title: c.title, amount: c.amount)).toList();

    return _invoiceRepo.createInvoice(
      invoice: invoice,
      items: items,
      sideCosts: sideCostModels,
      financePay: financePay,
      paymentLines: paymentType == PaymentType.combined ? paymentLines : const [],
    );
  }

  /// ذخیره به‌عنوان پیش‌فاکتور. شماره از سری جداگانه‌ی DRAFT گرفته می‌شود و
  /// هیچ اثری روی موجودی کالا یا stock_movements (و حساب مالی) ندارد.
  Future<int> saveDraftInvoice({
    required InvoiceType type,
    int? customerId,
    int? vehicleId,
    required List<InvoiceCartLine> lines,
    required List<SideCostLine> sideCosts,
    required PaymentType paymentType,
    String? paymentAccountInfo,
    String? notes,
    DateTime? issueDateTime,
    String? checkDueDate,
    bool financePay = false,
    int? mileageKm,
    List<PaymentLine> paymentLines = const [],
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('حداقل یک ردیف باید اضافه شود');
    }
    final draftNumber = await _invoiceRepo.getNextDraftNumber();
    final itemsTotal = lines.fold(0.0, (s, l) => s + l.total);
    final sideCostsTotal = sideCosts.fold(0.0, (s, c) => s + c.amount);
    final finalAmount = itemsTotal + sideCostsTotal;

    final invoice = Invoice(
      invoiceNumber: draftNumber,
      type: type,
      customerId: customerId,
      vehicleId: vehicleId,
      issueDate: (issueDateTime ?? DateTime.now()).toIso8601String(),
      itemsTotal: itemsTotal,
      sideCosts: sideCostsTotal,
      finalAmount: finalAmount,
      paymentType: paymentType,
      paymentAccountInfo: paymentAccountInfo,
      checkDueDate: checkDueDate,
      notes: notes,
      isDraft: 1,
      mileageKm: mileageKm,
    );

    final items = lines
        .map((l) => InvoiceItem(
              invoiceId: 0,
              itemType: l.itemType,
              serviceId: l.serviceId,
              productId: l.productId,
              description: l.description,
              itemCode: l.itemCode,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
              total: l.total,
            ))
        .toList();

    final sideCostModels =
        sideCosts.map((c) => SideCost(invoiceId: 0, title: c.title, amount: c.amount)).toList();

    return _invoiceRepo.createInvoice(
      invoice: invoice,
      items: items,
      sideCosts: sideCostModels,
      isDraft: true,
      financePay: financePay,
      paymentLines: paymentType == PaymentType.combined ? paymentLines : const [],
    );
  }

  /// ویرایش کامل یک پیش‌فاکتور موجود. فقط روی رکوردی با is_draft = 1 کار
  /// می‌کند؛ در غیر این صورت استثنا پرتاب می‌شود. شماره‌ی پیش‌فاکتور با
  /// ویرایش تغییر نمی‌کند. اگر [financePay] داده شود، تیک پرداخت از حساب
  /// فروش کالا هم به‌روز می‌شود. [paymentLines] = null یعنی ردیف‌های پرداخت
  /// ترکیبیِ ذخیره‌شده دست‌نخورده بمانند.
  Future<void> updateDraftInvoice({
    required int invoiceId,
    required InvoiceType type,
    int? customerId,
    int? vehicleId,
    required List<InvoiceCartLine> lines,
    required List<SideCostLine> sideCosts,
    required PaymentType paymentType,
    String? paymentAccountInfo,
    String? notes,
    required DateTime issueDateTime,
    String? checkDueDate,
    bool? financePay,
    int? mileageKm,
    List<PaymentLine>? paymentLines,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('حداقل یک ردیف باید اضافه شود');
    }
    final itemsTotal = lines.fold(0.0, (s, l) => s + l.total);
    final sideCostsTotal = sideCosts.fold(0.0, (s, c) => s + c.amount);
    final finalAmount = itemsTotal + sideCostsTotal;

    if (paymentType == PaymentType.combined && paymentLines != null) {
      final err = PaymentLine.validate(paymentLines, finalAmount);
      if (err != null) throw StateError(err);
    }

    // invoiceNumber اینجا با پیش‌فاکتور فعلی جایگزین می‌شود (در Repository)،
    // پس مقدار موقت زیر صرفاً برای ساخت آبجکت Invoice لازم است و در
    // updateDraftInvoice نادیده گرفته می‌شود.
    final invoice = Invoice(
      invoiceNumber: '',
      type: type,
      customerId: customerId,
      vehicleId: vehicleId,
      issueDate: issueDateTime.toIso8601String(),
      itemsTotal: itemsTotal,
      sideCosts: sideCostsTotal,
      finalAmount: finalAmount,
      paymentType: paymentType,
      paymentAccountInfo: paymentAccountInfo,
      checkDueDate: checkDueDate,
      notes: notes,
      isDraft: 1,
      mileageKm: mileageKm,
    );

    final items = lines
        .map((l) => InvoiceItem(
              invoiceId: invoiceId,
              itemType: l.itemType,
              serviceId: l.serviceId,
              productId: l.productId,
              description: l.description,
              itemCode: l.itemCode,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
              total: l.total,
            ))
        .toList();

    final sideCostModels =
        sideCosts.map((c) => SideCost(invoiceId: invoiceId, title: c.title, amount: c.amount)).toList();

    await _invoiceRepo.updateDraftInvoice(
      invoiceId: invoiceId,
      invoice: invoice,
      items: items,
      sideCosts: sideCostModels,
      financePay: financePay,
      paymentLines: paymentType == PaymentType.combined ? paymentLines : const [],
    );
  }

  /// تبدیل اتمیک پیش‌فاکتور به فاکتور اصلی. شماره‌ی نهایی فاکتور را برمی‌گرداند.
  Future<String> convertDraftToInvoice(int invoiceId) => _invoiceRepo.convertDraftToInvoice(invoiceId);
}
