import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// این کلاس فقط مسئول باز کردن اتصال دیتابیس و ساخت جداول است.
/// منطق CRUD در لایه repositories است.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String dbName = 'receipt_app.db';
  static const int dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final dpath = join(dbPath, dbName);
    return openDatabase(
      dpath,
      version: dbVersion,
      onCreate: _onCreate,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        mobile TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('CREATE INDEX idx_customers_mobile ON customers(mobile)');
    batch.execute('CREATE INDEX idx_customers_name ON customers(name)');

    batch.execute('''
      CREATE TABLE vehicle_brands (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE vehicle_models (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        brand_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        FOREIGN KEY (brand_id) REFERENCES vehicle_brands(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_vehicle_models_brand ON vehicle_models(brand_id)');

    batch.execute('''
      CREATE TABLE service_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        brand_id INTEGER,
        model_id INTEGER,
        price REAL NOT NULL,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (category_id) REFERENCES service_categories(id),
        FOREIGN KEY (brand_id) REFERENCES vehicle_brands(id),
        FOREIGN KEY (model_id) REFERENCES vehicle_models(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_services_category ON services(category_id)');
    batch.execute('CREATE INDEX idx_services_brand ON services(brand_id)');
    batch.execute('CREATE INDEX idx_services_code ON services(code)');

    batch.execute('''
      CREATE TABLE service_price_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service_id INTEGER NOT NULL,
        old_price REAL NOT NULL,
        new_price REAL NOT NULL,
        changed_at TEXT NOT NULL,
        FOREIGN KEY (service_id) REFERENCES services(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_sph_service ON service_price_history(service_id)');

    batch.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        purchase_price REAL NOT NULL,
        sell_price REAL NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_products_code ON products(code)');
    batch.execute('CREATE INDEX idx_products_name ON products(name)');

    batch.execute('''
      CREATE TABLE payment_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        number TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        customer_id INTEGER,
        issue_date TEXT NOT NULL,
        items_total REAL NOT NULL DEFAULT 0,
        side_costs REAL NOT NULL DEFAULT 0,
        final_amount REAL NOT NULL DEFAULT 0,
        payment_type TEXT NOT NULL,
        payment_account_info TEXT,
        check_due_date TEXT,
        notes TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_invoices_number ON invoices(invoice_number)');
    batch.execute('CREATE INDEX idx_invoices_customer ON invoices(customer_id)');
    batch.execute('CREATE INDEX idx_invoices_date ON invoices(issue_date)');
    batch.execute('CREATE INDEX idx_invoices_type ON invoices(type)');

    batch.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        service_id INTEGER,
        product_id INTEGER,
        description TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total REAL NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_invoice_items_invoice ON invoice_items(invoice_id)');

    batch.execute('''
      CREATE TABLE side_costs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_side_costs_invoice ON side_costs(invoice_id)');

    batch.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        reason TEXT NOT NULL,
        invoice_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_stock_moves_product ON stock_movements(product_id)');

    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  Future<String> getDbFilePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, dbName);
  }
}
