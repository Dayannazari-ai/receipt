import '../models/invoice.dart';
import '../repositories/invoice_repository.dart';

class InvoiceCartLine {
  final InvoiceItemType itemType;
  final int? serviceId;
  final int? productId;
  final String description;
  int quantity;
  double unitPrice;

  InvoiceCartLine({
    required this.itemType,
    this.serviceId,
    this.productId,
    required this.description,
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

  /// صدور فاکتور اصلی: رفتار کاملاً مثل قبل، بدون هیچ تغییری.
  Future<int> issueInvoice({
    required InvoiceType type,
    int? customerId,
    required List<InvoiceCartLine> lines,
    required List<SideCostLine> sideCosts,
    required PaymentType paymentType,
    String? paymentAccountInfo,
    String? notes,
    DateTime? issueDateTime,
    String? checkDueDate,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('حداقل یک ردیف باید اضافه شود');
    }
    final invoiceNumber = await nextInvoiceNumber(type);
    final itemsTotal = lines.fold(0.0, (s, l) => s + l.total);
    final sideCostsTotal = sideCosts.fold(0.0, (s, c) => s + c.amount);
    final finalAmount = itemsTotal + sideCostsTotal;

    final invoice = Invoice(
      invoiceNumber: invoiceNumber,
      type: type,
      customerId: customerId,
      issueDate: (issueDateTime ?? DateTime.now()).toIso8601String(),
      itemsTotal: itemsTotal,
      sideCosts: sideCostsTotal,
      finalAmount: finalAmount,
      paymentType: paymentType,
      paymentAccountInfo: paymentAccountInfo,
      checkDueDate: checkDueDate,
      notes: notes,
      isDraft: 0,
    );

    final items = lines
        .map((l) => InvoiceItem(
              invoiceId: 0,
              itemType: l.itemType,
              serviceId: l.serviceId,
              productId: l.productId,
              description: l.description,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
              total: l.total,
            ))
        .toList();

    final sideCostModels =
        sideCosts.map((c) => SideCost(invoiceId: 0, title: c.title, amount: c.amount)).toList();

    return _invoiceRepo.createInvoice(invoice: invoice, items: items, sideCosts: sideCostModels);
  }

  /// ذخیره به‌عنوان پیش‌فاکتور. شماره از سری جداگانه‌ی DRAFT گرفته می‌شود و
  /// هیچ اثری روی موجودی کالا یا stock_movements ندارد.
  Future<int> saveDraftInvoice({
    required InvoiceType type,
    int? customerId,
    required List<InvoiceCartLine> lines,
    required List<SideCostLine> sideCosts,
    required PaymentType paymentType,
    String? paymentAccountInfo,
    String? notes,
    DateTime? issueDateTime,
    String? checkDueDate,
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
      issueDate: (issueDateTime ?? DateTime.now()).toIso8601String(),
      itemsTotal: itemsTotal,
      sideCosts: sideCostsTotal,
      finalAmount: finalAmount,
      paymentType: paymentType,
      paymentAccountInfo: paymentAccountInfo,
      checkDueDate: checkDueDate,
      notes: notes,
      isDraft: 1,
    );

    final items = lines
        .map((l) => InvoiceItem(
              invoiceId: 0,
              itemType: l.itemType,
              serviceId: l.serviceId,
              productId: l.productId,
              description: l.description,
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
    );
  }

  /// ویرایش کامل یک پیش‌فاکتور موجود. فقط روی رکوردی با is_draft = 1 کار
  /// می‌کند؛ در غیر این صورت استثنا پرتاب می‌شود. شماره‌ی پیش‌فاکتور با
  /// ویرایش تغییر نمی‌کند.
  Future<void> updateDraftInvoice({
    required int invoiceId,
    required InvoiceType type,
    int? customerId,
    required List<InvoiceCartLine> lines,
    required List<SideCostLine> sideCosts,
    required PaymentType paymentType,
    String? paymentAccountInfo,
    String? notes,
    required DateTime issueDateTime,
    String? checkDueDate,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('حداقل یک ردیف باید اضافه شود');
    }
    final itemsTotal = lines.fold(0.0, (s, l) => s + l.total);
    final sideCostsTotal = sideCosts.fold(0.0, (s, c) => s + c.amount);
    final finalAmount = itemsTotal + sideCostsTotal;

    // invoiceNumber اینجا با پیش‌فاکتور فعلی جایگزین می‌شود (در Repository)،
    // پس مقدار موقت زیر صرفاً برای ساخت آبجکت Invoice لازم است و در
    // updateDraftInvoice نادیده گرفته می‌شود.
    final invoice = Invoice(
      invoiceNumber: '',
      type: type,
      customerId: customerId,
      issueDate: issueDateTime.toIso8601String(),
      itemsTotal: itemsTotal,
      sideCosts: sideCostsTotal,
      finalAmount: finalAmount,
      paymentType: paymentType,
      paymentAccountInfo: paymentAccountInfo,
      checkDueDate: checkDueDate,
      notes: notes,
      isDraft: 1,
    );

    final items = lines
        .map((l) => InvoiceItem(
              invoiceId: invoiceId,
              itemType: l.itemType,
              serviceId: l.serviceId,
              productId: l.productId,
              description: l.description,
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
    );
  }

  /// تبدیل اتمیک پیش‌فاکتور به فاکتور اصلی. شماره‌ی نهایی فاکتور را برمی‌گرداند.
  Future<String> convertDraftToInvoice(int invoiceId) => _invoiceRepo.convertDraftToInvoice(invoiceId);
}
