import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// این کلاس فقط مسئول باز کردن اتصال دیتابیس و ساخت جداول است.
/// منطق CRUD در لایه repositories است.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String dbName = 'receipt_app.db';
  // نسخه ۲: افزودن ستون voice_search_label به products و services برای
  // قابلیت جستجوی صوتی. این تغییر با Migration امن (ALTER TABLE) انجام
  // می‌شود و هیچ داده‌ی قبلی کاربران حذف یا بازنویسی نمی‌شود.
  // نسخه ۴: افزودن ستون is_draft به invoices برای قابلیت «پیش‌فاکتور».
  // نسخه ۵: افزودن ستون item_code به invoice_items؛ کد کالا/خدمت در لحظه‌ی
  // صدور یا ذخیره‌ی هر ردیف فریز می‌شود، درست مانند unit_price، و با تغییر
  // بعدی Product.code یا ServiceItem.code تغییر نمی‌کند.
  // نسخه ۶: افزودن جدول vehicles (رابطه‌ی مشتری↔خودرو، هر مشتری چند
  // خودرو) و ستون‌های invoices.vehicle_id (اتصال اختیاری فاکتور به خودرو)
  // و invoices.backup_uid (شناسه‌ی پایدار و یکتا برای تشخیص دقیق فاکتور
  // در عملیات Backup/Restore، مستقل از invoice_number).
  // نسخه ۷: افزودن دو جدول کاملاً جدید finance_accounts و
  // finance_transactions برای «حساب مالی فروش کالا». هیچ جدول یا ستون
  // موجودی تغییر نمی‌کند. مانده‌ی حساب هرگز ذخیره نمی‌شود و همیشه از روی
  // تراکنش‌ها محاسبه می‌شود.
  // نسخه ۸: اتصال فاکتور به حساب مالی. جدول جدید finance_cheques (چک‌های
  // در انتظار وصول) و ستون invoices.finance_pay (تیک «پرداخت از حساب فروش
  // کالا» برای فاکتور خرید؛ پیش‌فرض ۰ پس فاکتورهای قبلی تغییری نمی‌کنند).
  static const int dbVersion = 8;

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
      onUpgrade: _onUpgrade,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  /// نصب تازه (کاربر جدید): جداول از همان ابتدا شامل voice_search_label،
  /// is_draft، item_code، vehicles و ستون‌های vehicle_id/backup_uid هستند.
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
        name TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
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

    // خودروهای متعلق به مشتریان (رابطه‌ی یک‌به‌چند: هر مشتری چند خودرو).
    // برند/مدل به جدول‌های مرجع بالا اشاره می‌کنند تا داده‌ی تکراری نسازیم.
    batch.execute('''
      CREATE TABLE vehicles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        brand_id INTEGER,
        model_id INTEGER,
        plate_number TEXT,
        notes TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id),
        FOREIGN KEY (brand_id) REFERENCES vehicle_brands(id),
        FOREIGN KEY (model_id) REFERENCES vehicle_models(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_vehicles_customer ON vehicles(customer_id)');
    batch.execute('CREATE INDEX idx_vehicles_plate ON vehicles(plate_number)');

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
        voice_search_label TEXT,
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
        barcode TEXT,
        purchase_price REAL NOT NULL,
        sell_price REAL NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        voice_search_label TEXT,
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

    // invoices: افزوده شده vehicle_id (اتصال اختیاری به خودرو) و backup_uid
    // (شناسه‌ی پایدار یکتا، مستقل از invoice_number، برای تشخیص دقیق فاکتور
    // در عملیات Backup/Restore) و finance_pay (تیک پرداخت از حساب فروش کالا).
    batch.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        customer_id INTEGER,
        vehicle_id INTEGER,
        issue_date TEXT NOT NULL,
        items_total REAL NOT NULL DEFAULT 0,
        side_costs REAL NOT NULL DEFAULT 0,
        final_amount REAL NOT NULL DEFAULT 0,
        payment_type TEXT NOT NULL,
        payment_account_info TEXT,
        check_due_date TEXT,
        notes TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_draft INTEGER NOT NULL DEFAULT 0,
        finance_pay INTEGER NOT NULL DEFAULT 0,
        backup_uid TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id),
        FOREIGN KEY (vehicle_id) REFERENCES vehicles(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_invoices_number ON invoices(invoice_number)');
    batch.execute('CREATE INDEX idx_invoices_customer ON invoices(customer_id)');
    batch.execute('CREATE INDEX idx_invoices_vehicle ON invoices(vehicle_id)');
    batch.execute('CREATE INDEX idx_invoices_date ON invoices(issue_date)');
    batch.execute('CREATE INDEX idx_invoices_type ON invoices(type)');
    batch.execute('CREATE INDEX idx_invoices_is_draft ON invoices(is_draft)');
    batch.execute('CREATE UNIQUE INDEX idx_invoices_backup_uid ON invoices(backup_uid)');

    batch.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        service_id INTEGER,
        product_id INTEGER,
        description TEXT NOT NULL,
        item_code TEXT,
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

    for (final sql in _financeSchema) {
      batch.execute(sql);
    }

    await batch.commit(noResult: true);
  }

  /// جدول‌های حساب مالی فروش کالا (نسخه‌ی ۷ و ۸). هم در نصب تازه و هم در
  /// ارتقا استفاده می‌شود. همه‌ی دستورها IF NOT EXISTS هستند تا اجرای
  /// مجدد بی‌خطر باشد.
  static const List<String> _financeSchema = [
    '''
      CREATE TABLE IF NOT EXISTS finance_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        account_type TEXT NOT NULL DEFAULT 'goods_sales',
        card_number TEXT,
        start_date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE IF NOT EXISTS finance_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        occurred_at TEXT NOT NULL,
        tx_type TEXT NOT NULL,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        invoice_id INTEGER,
        invoice_number TEXT,
        counterparty TEXT,
        notes TEXT,
        reverses_id INTEGER,
        correction_reason TEXT,
        backup_uid TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES finance_accounts(id)
      )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_fin_tx_account ON finance_transactions(account_id, occurred_at)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_fin_tx_uid ON finance_transactions(backup_uid)',
    // هر تراکنش حداکثر یک بار قابل اصلاح (معکوس‌شدن) است.
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_fin_tx_reverses ON finance_transactions(reverses_id) WHERE reverses_id IS NOT NULL',
    // نسخه‌ی ۸: چک‌های در انتظار وصول (تا وصول وارد مانده نمی‌شوند).
    '''
      CREATE TABLE IF NOT EXISTS finance_cheques (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        invoice_id INTEGER,
        invoice_number TEXT,
        direction TEXT NOT NULL,
        amount REAL NOT NULL,
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        collected_tx_id INTEGER,
        backup_uid TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES finance_accounts(id)
      )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_fin_chq_status ON finance_cheques(status, due_date)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_fin_chq_uid ON finance_cheques(backup_uid)',
    // هر فاکتور حداکثر یک چک دارد.
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_fin_chq_invoice ON finance_cheques(invoice_id) WHERE invoice_id IS NOT NULL',
  ];

  /// نصب موجود (کاربر قبلی): فقط ستون‌های جدید با ALTER TABLE اضافه می‌شوند.
  /// هیچ جدولی حذف یا بازسازی نمی‌شود و هیچ داده‌ای از بین نمی‌رود.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // ستون ممکن است در نصب‌های خیلی جدید از قبل وجود داشته باشد؛
      // برای اطمینان، خطای "duplicate column" را نادیده می‌گیریم تا
      // ارتقا هرگز باعث Crash نشود.
      try {
        await db.execute('ALTER TABLE products ADD COLUMN voice_search_label TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE services ADD COLUMN voice_search_label TEXT');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE vehicle_brands ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      // افزودن وضعیت «پیش‌فاکتور». مقدار پیش‌فرض ۰ یعنی تمام فاکتورهای
      // قبلی همچنان فاکتور اصلی محسوب می‌شوند؛ هیچ داده‌ای تغییر نمی‌کند.
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN is_draft INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX idx_invoices_is_draft ON invoices(is_draft)');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      // افزودن کد کالا/خدمت فریزشده به هر ردیف فاکتور. رکوردهای قدیمی
      // item_code را NULL می‌گیرند و در PDF/UI با یک خط تیره نمایش
      // داده می‌شوند؛ هیچ داده‌ای بازنویسی یا حذف نمی‌شود.
      try {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN item_code TEXT');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      // جدول خودروها. رابطه‌ی یک‌به‌چند با مشتری؛ هیچ داده‌ی قبلی تحت تأثیر
      // قرار نمی‌گیرد چون این یک جدول کاملاً جدید است.
      try {
        await db.execute('''
          CREATE TABLE vehicles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL,
            brand_id INTEGER,
            model_id INTEGER,
            plate_number TEXT,
            notes TEXT,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY (customer_id) REFERENCES customers(id),
            FOREIGN KEY (brand_id) REFERENCES vehicle_brands(id),
            FOREIGN KEY (model_id) REFERENCES vehicle_models(id)
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX idx_vehicles_customer ON vehicles(customer_id)');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX idx_vehicles_plate ON vehicles(plate_number)');
      } catch (_) {}
      // ستون اتصال اختیاری فاکتور به خودرو؛ رکوردهای قدیمی NULL می‌گیرند
      // و هیچ فاکتور موجودی تحت تأثیر قرار نمی‌گیرد.
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN vehicle_id INTEGER');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX idx_invoices_vehicle ON invoices(vehicle_id)');
      } catch (_) {}
      // شناسه‌ی پایدار برای Backup/Restore؛ رکوردهای قدیمی NULL می‌گیرند.
      // Repository هنگام هر insert جدید یک UUID تازه تولید می‌کند؛ برای
      // فاکتورهای قدیمی که از قبل وجود داشتند، این مقدار تا اولین
      // Backup/Restore که به آن‌ها برسد NULL باقی می‌ماند و تشخیص Merge
      // برای آن‌ها به شماره‌ی فاکتور و محتوا متکی می‌شود، نه backup_uid.
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN backup_uid TEXT');
      } catch (_) {}
      try {
        await db.execute('CREATE UNIQUE INDEX idx_invoices_backup_uid ON invoices(backup_uid)');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      // فقط دو جدول کاملاً جدید برای حساب مالی فروش کالا. هیچ جدول یا
      // ستون موجودی لمس نمی‌شود، پس داده‌ی قبلی تحت تأثیر قرار نمی‌گیرد.
      for (final sql in _financeSchema) {
        try {
          await db.execute(sql);
        } catch (_) {}
      }
    }
    if (oldVersion < 8) {
      // ستون finance_pay با پیش‌فاکتور ۰: فاکتورهای قبلی بدون تغییر می‌مانند.
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN finance_pay INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      // جدول چک‌ها (و بقیه‌ی دستورهای IF NOT EXISTS، که بی‌خطر تکرار می‌شوند).
      for (final sql in _financeSchema) {
        try {
          await db.execute(sql);
        } catch (_) {}
      }
    }
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
