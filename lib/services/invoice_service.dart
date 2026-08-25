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

  Future<int> issueInvoice({
    required InvoiceType type,
    int? customerId,
    required List<InvoiceCartLine> lines,
    required List<SideCostLine> sideCosts,
    required PaymentType paymentType,
    String? paymentAccountInfo,
    String? notes,
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
      issueDate: DateTime.now().toIso8601String(),
      itemsTotal: itemsTotal,
      sideCosts: sideCostsTotal,
      finalAmount: finalAmount,
      paymentType: paymentType,
      paymentAccountInfo: paymentAccountInfo,
      notes: notes,
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
}
