import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../repositories/customer_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/service_repository.dart';
import '../repositories/vehicle_reference_repository.dart';

class SeedService {
  static const sampleTag = '[SAMPLE]';

  Future<void> seedIfEmpty() async {
    final vehicleRepo = VehicleReferenceRepository();
    await vehicleRepo.ensureDefaults();

    final categoryRepo = ServiceCategoryRepository();
    await categoryRepo.ensureDefaults();

    final customerRepo = CustomerRepository();
    final existing = await customerRepo.getAll();
    if (existing.isNotEmpty) return;

    await customerRepo.insert(Customer(name: 'علی رضایی', mobile: '09121234567', notes: sampleTag));
    await customerRepo.insert(Customer(name: 'زهرا محمدی', mobile: '09351234567', notes: sampleTag));

    final productRepo = ProductRepository();
    await productRepo.insert(Product(
        name: 'فیلتر روغن', code: 'PRD-001', purchasePrice: 80000, sellPrice: 120000, stock: 25, minStock: 5, notes: sampleTag));
    await productRepo.insert(Product(
        name: 'روغن موتور 4 لیتری', code: 'PRD-002', purchasePrice: 400000, sellPrice: 550000, stock: 10, minStock: 3, notes: sampleTag));
  }

  Future<void> deleteAllSampleData() async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.delete('products', where: 'notes LIKE ?', whereArgs: ['%$sampleTag%']);
      await txn.delete('customers', where: 'notes LIKE ?', whereArgs: ['%$sampleTag%']);
    });
  }
}
