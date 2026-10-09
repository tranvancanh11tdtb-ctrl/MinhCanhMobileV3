part of '../main.dart';

class StoreDb {
  StoreDb._();
  static final instance = StoreDb._();
  Database? _db;
  final remoteChanges=ValueNotifier<int>(0);
  bool _nativeStale=false;
  void acknowledgeRemoteChanges(){_nativeStale=false;}

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final file = p.join(await getDatabasesPath(), 'minh_canh_mobile_v3.db');
    return openDatabase(
      file,
      version: 9,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        brand TEXT NOT NULL DEFAULT '',
        capacity TEXT NOT NULL DEFAULT '',
        sale_price INTEGER NOT NULL DEFAULT 0,
        track_imei INTEGER NOT NULL DEFAULT 0,
        quantity INTEGER NOT NULL DEFAULT 0,
        avg_cost INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )''');
        await db.execute('''CREATE TABLE serial_units(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        imei TEXT NOT NULL UNIQUE,
        color TEXT NOT NULL DEFAULT '',
        condition_text TEXT NOT NULL DEFAULT 'Mới',
        cost INTEGER NOT NULL,
        purchase_id INTEGER,
        status TEXT NOT NULL DEFAULT 'in_stock',
        created_at TEXT NOT NULL,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )''');
        await db.execute('''CREATE TABLE purchases(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        supplier TEXT NOT NULL DEFAULT '',
        total INTEGER NOT NULL,
        paid INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        created_at TEXT NOT NULL
      )''');
        await db.execute('''CREATE TABLE purchase_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL,
        FOREIGN KEY(purchase_id) REFERENCES purchases(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )''');
        await db.execute('''CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        customer TEXT NOT NULL DEFAULT 'Khách lẻ',
        phone TEXT NOT NULL DEFAULT '',
        total INTEGER NOT NULL,
        cost_total INTEGER NOT NULL,
        paid_cash INTEGER NOT NULL DEFAULT 0,
        paid_transfer INTEGER NOT NULL DEFAULT 0,
        debt INTEGER NOT NULL DEFAULT 0,
        warranty_months INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'completed',
        created_at TEXT NOT NULL
      )''');
        await db.execute('''CREATE TABLE sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        serial_id INTEGER,
        quantity INTEGER NOT NULL,
        unit_price INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL,
        FOREIGN KEY(sale_id) REFERENCES sales(id),
        FOREIGN KEY(product_id) REFERENCES products(id),
        FOREIGN KEY(serial_id) REFERENCES serial_units(id)
      )''');
        await db.execute('''CREATE TABLE inventory_movements(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        serial_id INTEGER,
        kind TEXT NOT NULL,
        quantity_delta INTEGER NOT NULL,
        reference_type TEXT NOT NULL,
        reference_id INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )''');
        await _createV2Tables(db);
        await _createV3Tables(db);
        await _createV4Tables(db);
        await _createV5Tables(db);
        await _createV6Tables(db);
        await _createV7Tables(db);
        await _createV8Tables(db);
        await _createV9Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2Tables(db);
        if (oldVersion < 3) await _createV3Tables(db);
        if (oldVersion < 4) await _createV4Tables(db);
        if (oldVersion < 5) await _createV5Tables(db);
        if (oldVersion < 6) await _createV6Tables(db);
        if (oldVersion < 7) await _createV7Tables(db);
        if(oldVersion<8) await _createV8Tables(db);
        if(oldVersion<9) await _createV9Tables(db);
      },
    );
  }

  Future<void> _createV2Tables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS app_settings(
      setting_key TEXT PRIMARY KEY,
      setting_value TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS repairs(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      customer TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '',
      device TEXT NOT NULL,
      imei TEXT NOT NULL DEFAULT '',
      issue TEXT NOT NULL,
      amount INTEGER NOT NULL DEFAULT 0,
      parts_cost INTEGER NOT NULL DEFAULT 0,
      paid INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'received',
      note TEXT NOT NULL DEFAULT '',
      received_at TEXT NOT NULL,
      completed_at TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS warranty_claims(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_item_id INTEGER NOT NULL,
      issue TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'received',
      received_at TEXT NOT NULL,
      resolved_at TEXT,
      FOREIGN KEY(sale_item_id) REFERENCES sale_items(id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS cash_entries(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_type TEXT NOT NULL,
      category TEXT NOT NULL,
      amount INTEGER NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS stocktakes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      system_quantity INTEGER NOT NULL,
      actual_quantity INTEGER NOT NULL,
      difference INTEGER NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      FOREIGN KEY(product_id) REFERENCES products(id)
    )''');
  }

  Future<void> _createV3Tables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS customer_directory(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
      idx_customer_directory_identity
      ON customer_directory(name COLLATE NOCASE, phone)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS supplier_directory(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      address TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
      idx_supplier_directory_name
      ON supplier_directory(name COLLATE NOCASE)''');
    await _backfillDirectories(db);
  }

  Future<void> _createV4Tables(DatabaseExecutor db) async {
    final saleColumns = await db.rawQuery('PRAGMA table_info(sales)');
    if (!saleColumns.any((column) => column['name'] == 'discount_total')) {
      await db.execute('''ALTER TABLE sales ADD COLUMN
        discount_total INTEGER NOT NULL DEFAULT 0''');
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS debt_adjustments(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      party_type TEXT NOT NULL,
      party_id INTEGER NOT NULL,
      amount_delta INTEGER NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_debt_adjustments_party
      ON debt_adjustments(party_type, party_id, created_at)''');
  }

  Future<void> _createV5Tables(DatabaseExecutor db) async {
    final repairColumns = await db.rawQuery('PRAGMA table_info(repairs)');
    if (!repairColumns.any((column) => column['name'] == 'hidden')) {
      await db.execute('''ALTER TABLE repairs ADD COLUMN
        hidden INTEGER NOT NULL DEFAULT 0''');
    }
  }

  Future<void> _createV6Tables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS product_categories(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE COLLATE NOCASE,
      created_at TEXT NOT NULL
    )''');
    final now = DateTime.now().toIso8601String();
    for (final name in const [
      'Điện thoại',
      'iPhone',
      'Samsung',
      'Củ sạc',
      'Cáp sạc',
      'Phụ kiện',
    ]) {
      await db.insert('product_categories', {
        'name': name,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.rawInsert(
      '''INSERT OR IGNORE INTO product_categories(name, created_at)
      SELECT DISTINCT TRIM(category), ? FROM products
      WHERE LENGTH(TRIM(category))>0''',
      [now],
    );
  }

  Future<void> _createV7Tables(DatabaseExecutor db) async {
    final categoryColumns = await db.rawQuery(
      'PRAGMA table_info(product_categories)',
    );
    if (!categoryColumns.any((column) => column['name'] == 'parent_id')) {
      await db.execute(
        'ALTER TABLE product_categories ADD COLUMN parent_id INTEGER',
      );
    }
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_product_category_parent
      ON product_categories(parent_id, name)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS product_brands(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE COLLATE NOCASE,
      created_at TEXT NOT NULL
    )''');
    final now = DateTime.now().toIso8601String();
    for (final name in const [
      'Apple',
      'Samsung',
      'Xiaomi',
      'OPPO',
      'realme',
      'Vivo',
    ]) {
      await db.insert('product_brands', {
        'name': name,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.rawInsert(
      '''INSERT OR IGNORE INTO product_brands(name, created_at)
      SELECT DISTINCT TRIM(brand), ? FROM products
      WHERE LENGTH(TRIM(brand))>0''',
      [now],
    );
  }

  Future<void> _backfillDirectories(DatabaseExecutor db) async {
    await db.rawInsert('''INSERT OR IGNORE INTO customer_directory
      (name, phone, note, created_at, updated_at)
      SELECT TRIM(customer), TRIM(phone), '', MIN(activity_at), MAX(activity_at)
      FROM (
        SELECT customer, phone, created_at activity_at FROM sales
        UNION ALL
        SELECT customer, phone, received_at activity_at FROM repairs
      ) activity
      WHERE TRIM(customer)<>'' AND LOWER(TRIM(customer))<>'khách lẻ'
      GROUP BY LOWER(TRIM(customer)), TRIM(phone)''');
    await db.rawInsert('''INSERT OR IGNORE INTO supplier_directory
      (name, phone, address, note, created_at, updated_at)
      SELECT TRIM(supplier), '', '', '', MIN(created_at), MAX(created_at)
      FROM purchases
      WHERE TRIM(supplier)<>''
      GROUP BY LOWER(TRIM(supplier))''');
  }

  Future<List<Map<String, Object?>>> _localProductCategories() async {
    final db = await _executor;
    return db.rawQuery('''SELECT c.*, parent.name parent_name,
      CASE WHEN parent.id IS NULL THEN c.name
           ELSE parent.name || ' → ' || c.name END display_name,
      (SELECT COUNT(*) FROM products p
       WHERE LOWER(TRIM(p.category))=LOWER(TRIM(c.name)) AND p.active>=0)
       product_count
      FROM product_categories c
      LEFT JOIN product_categories parent ON parent.id=c.parent_id
      ORDER BY COALESCE(parent.name, c.name) COLLATE NOCASE,
               CASE WHEN parent.id IS NULL THEN 0 ELSE 1 END,
               c.name COLLATE NOCASE''');
  }

  Future<String> _localAddProductCategory(String rawName, {int? parentId}) async {
    final name = rawName.trim();
    if (name.isEmpty) throw Exception('Tên phân loại không được để trống');
    final db = await _executor;
    if (parentId != null) {
      final parent = await db.query(
        'product_categories',
        columns: ['id', 'parent_id'],
        where: 'id=?',
        whereArgs: [parentId],
      );
      if (parent.isEmpty) throw Exception('Không tìm thấy nhóm cha');
      if (parent.single['parent_id'] != null) {
        throw Exception('Chỉ hỗ trợ phân loại tối đa 2 cấp');
      }
    }
    await db.insert('product_categories', {
      'name': name,
      'parent_id': parentId,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await db.query(
      'product_categories',
      columns: ['name'],
      where: 'LOWER(name)=LOWER(?)',
      whereArgs: [name],
    );
    return '${rows.single['name']}';
  }

  Future<void> _localRenameProductCategory(int id, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw Exception('Tên phân loại không được để trống');
    await _nestedTransaction((txn) async {
      final rows = await txn.query(
        'product_categories',
        columns: ['name'],
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw Exception('Không tìm thấy phân loại');
      final oldName = '${rows.single['name']}';
      await txn.update(
        'product_categories',
        {'name': name},
        where: 'id=?',
        whereArgs: [id],
      );
      await txn.update(
        'products',
        {'category': name},
        where: 'LOWER(TRIM(category))=LOWER(TRIM(?))',
        whereArgs: [oldName],
      );
    });
  }

  Future<void> _localDeleteProductCategory(int id) async {
    await _nestedTransaction((txn) async {
      final rows = await txn.query(
        'product_categories',
        columns: ['name'],
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw Exception('Không tìm thấy phân loại');
      final name = '${rows.single['name']}';
      final children =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM product_categories WHERE parent_id=?',
              [id],
            ),
          ) ??
          0;
      if (children > 0) {
        throw Exception(
          'Nhóm đang có $children phân loại con nên chưa thể xóa',
        );
      }
      final used =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(*) FROM products
               WHERE active>=0 AND LOWER(TRIM(category))=LOWER(TRIM(?))''',
              [name],
            ),
          ) ??
          0;
      if (used > 0) {
        throw Exception('Phân loại đang có $used hàng hóa nên chưa thể xóa');
      }
      await txn.delete('product_categories', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> _localProductBrands() async {
    final db = await _executor;
    return db.rawQuery('''SELECT b.*,
      (SELECT COUNT(*) FROM products p
       WHERE LOWER(TRIM(p.brand))=LOWER(TRIM(b.name)) AND p.active>=0)
       product_count
      FROM product_brands b
      ORDER BY b.name COLLATE NOCASE''');
  }

  Future<String> _localAddProductBrand(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw Exception('Tên hãng không được để trống');
    final db = await _executor;
    await db.insert('product_brands', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await db.query(
      'product_brands',
      columns: ['name'],
      where: 'LOWER(name)=LOWER(?)',
      whereArgs: [name],
    );
    return '${rows.single['name']}';
  }

  Future<void> _localRenameProductBrand(int id, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw Exception('Tên hãng không được để trống');
    await _nestedTransaction((txn) async {
      final rows = await txn.query(
        'product_brands',
        columns: ['name'],
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw Exception('Không tìm thấy hãng');
      final oldName = '${rows.single['name']}';
      await txn.update(
        'product_brands',
        {'name': name},
        where: 'id=?',
        whereArgs: [id],
      );
      await txn.update(
        'products',
        {'brand': name},
        where: 'LOWER(TRIM(brand))=LOWER(TRIM(?))',
        whereArgs: [oldName],
      );
    });
  }

  Future<void> _localDeleteProductBrand(int id) async {
    await _nestedTransaction((txn) async {
      final rows = await txn.query(
        'product_brands',
        columns: ['name'],
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw Exception('Không tìm thấy hãng');
      final name = '${rows.single['name']}';
      final used =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(*) FROM products
               WHERE active>=0 AND LOWER(TRIM(brand))=LOWER(TRIM(?))''',
              [name],
            ),
          ) ??
          0;
      if (used > 0) {
        throw Exception('Hãng đang có $used hàng hóa nên chưa thể xóa');
      }
      await txn.delete('product_brands', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<String> _localNextProductCode() async {
    final db = await _executor;
    final value =
        Sqflite.firstIntValue(
          await db.rawQuery('''SELECT
      COALESCE(MAX(CAST(SUBSTR(code, 3) AS INTEGER)), 0)
      FROM products WHERE code GLOB 'SP[0-9]*' '''),
        ) ??
        0;
    return 'SP${(value + 1).toString().padLeft(6, '0')}';
  }

  Future<List<Map<String, Object?>>> _localProducts({
    bool includeInactive = false,
  }) async {
    final db = await _executor;
    return db.rawQuery('''SELECT p.*,
      CASE WHEN p.track_imei=1 THEN
        (SELECT COUNT(*) FROM serial_units s WHERE s.product_id=p.id AND s.status='in_stock')
      ELSE p.quantity END AS stock,
      (SELECT GROUP_CONCAT(s.imei, ' ') FROM serial_units s
       WHERE s.product_id=p.id) AS imeis
      ,(SELECT GROUP_CONCAT(s.imei, ' ') FROM serial_units s
       WHERE s.product_id=p.id AND s.status='in_stock') AS stock_imeis
      FROM products p
      ${includeInactive ? 'WHERE p.active>=0' : 'WHERE p.active=1'}
      ORDER BY p.active DESC, p.id DESC''');
  }

  Future<Map<String, Object?>> _localProduct(int id) async {
    final db = await _executor;
    final rows = await db.rawQuery(
      '''SELECT p.*,
      CASE WHEN p.track_imei=1 THEN
        (SELECT COUNT(*) FROM serial_units s
         WHERE s.product_id=p.id AND s.status='in_stock')
      ELSE p.quantity END AS stock,
      (SELECT GROUP_CONCAT(s.imei, ' ') FROM serial_units s
       WHERE s.product_id=p.id) AS imeis
      ,(SELECT GROUP_CONCAT(s.imei, ' ') FROM serial_units s
       WHERE s.product_id=p.id AND s.status='in_stock') AS stock_imeis
      FROM products p WHERE p.id=?''',
      [id],
    );
    if (rows.isEmpty) throw Exception('Không tìm thấy hàng hóa');
    return rows.single;
  }

  Future<int> _localAddProduct(Map<String, Object?> row) async {
    final db = await _executor;
    return db.insert('products', row);
  }

  Future<void> _localUpdateProduct({
    required int id,
    required String code,
    required String name,
    required String category,
    required String brand,
    required String capacity,
    required int salePrice,
    int? averageCost,
  }) async {
    if (code.trim().isEmpty || name.trim().isEmpty || category.trim().isEmpty) {
      throw Exception('Mã hàng, tên hàng và phân loại không được để trống');
    }
    if (salePrice < 0 || (averageCost != null && averageCost < 0)) {
      throw Exception('Giá bán và giá nhập không được là số âm');
    }
    final db = await _executor;
    final values = <String, Object?>{
      'code': code.trim(),
      'name': name.trim(),
      'category': category.trim(),
      'brand': brand.trim(),
      'capacity': capacity.trim(),
      'sale_price': salePrice,
    };
    if (averageCost != null) values['avg_cost'] = averageCost;
    await db.update('products', values, where: 'id=?', whereArgs: [id]);
  }

  Future<void> _localSetProductActive(int id, bool active) async {
    final db = await _executor;
    final changed = await db.update(
      'products',
      {'active': active ? 1 : 0},
      where: 'id=?',
      whereArgs: [id],
    );
    if (changed == 0) throw Exception('Không tìm thấy hàng hóa');
  }

  Future<void> _localDeleteProduct(int id) async {
    await _nestedTransaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['id'],
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw Exception('Không tìm thấy hàng hóa');
      final used =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT
              (SELECT COUNT(*) FROM purchase_items WHERE product_id=?) +
              (SELECT COUNT(*) FROM sale_items WHERE product_id=?) +
              (SELECT COUNT(*) FROM serial_units WHERE product_id=?) +
              (SELECT COUNT(*) FROM inventory_movements WHERE product_id=?) +
              (SELECT COUNT(*) FROM stocktakes WHERE product_id=?)''',
              [id, id, id, id, id],
            ),
          ) ??
          0;
      if (used == 0) {
        await txn.delete('products', where: 'id=?', whereArgs: [id]);
      } else {
        // Giữ một bản ghi ẩn để hóa đơn, công nợ và bảo hành cũ không bị sai.
        await txn.update(
          'products',
          {'active': -1},
          where: 'id=?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> _localSerials(
    int productId, {
    String? status,
  }) async {
    final db = await _executor;
    return db.query(
      'serial_units',
      where: status == null ? 'product_id=?' : 'product_id=? AND status=?',
      whereArgs: status == null ? [productId] : [productId, status],
      orderBy: 'id DESC',
    );
  }

  Future<bool> _localSerialExists(String imei) async {
    final db = await _executor;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM serial_units WHERE imei=?', [
            imei.trim(),
          ]),
        ) ??
        0;
    return count > 0;
  }

  Future<void> _localUpdateSerialUnit({
    required int id,
    required String imei,
    required String color,
    required String conditionText,
    required int cost,
  }) async {
    if (imei.trim().isEmpty) throw Exception('IMEI không được để trống');
    if (cost < 0) throw Exception('Giá nhập không được là số âm');
    final db = await _executor;
    await db.update(
      'serial_units',
      {
        'imei': imei.trim(),
        'color': color.trim(),
        'condition_text': conditionText.trim().isEmpty
            ? 'Mới'
            : conditionText.trim(),
        'cost': cost,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<int?> _ensureCustomer(
    DatabaseExecutor db,
    String rawName,
    String rawPhone,
  ) async {
    final name = rawName.trim().isEmpty ? 'Khách lẻ' : rawName.trim();
    final phone = rawPhone.trim();
    if (name.toLowerCase() == 'khách lẻ') return null;
    final rows = await db.query(
      'customer_directory',
      where: phone.isNotEmpty
          ? "phone=? OR (LOWER(name)=LOWER(?) AND phone=?)"
          : "LOWER(name)=LOWER(?) AND phone=''",
      whereArgs: phone.isNotEmpty ? [phone, name, phone] : [name],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.single['id'] as int;
    final now = DateTime.now().toIso8601String();
    return db.insert('customer_directory', {
      'name': name,
      'phone': phone,
      'note': '',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int?> _ensureSupplier(DatabaseExecutor db, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return null;
    final rows = await db.query(
      'supplier_directory',
      where: 'LOWER(name)=LOWER(?)',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.single['id'] as int;
    final now = DateTime.now().toIso8601String();
    return db.insert('supplier_directory', {
      'name': name,
      'phone': '',
      'address': '',
      'note': '',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int> _localCompletePurchase({
    required int productId,
    required int quantity,
    required int unitCost,
    required String supplier,
    required int paid,
    required String paymentMethod,
    required List<SerialDraft> serials,
  }) async {
    return _nestedTransaction((txn) async {
      final product = (await txn.query(
        'products',
        where: 'id=?',
        whereArgs: [productId],
      )).single;
      final tracks = product['track_imei'] == 1;
      if (quantity <= 0) throw Exception('Số lượng phải lớn hơn 0');
      if (tracks && serials.length != quantity) {
        throw Exception('Số IMEI phải đúng bằng số lượng nhập');
      }
      if (tracks) {
        final normalized = serials.map((item) => item.imei.trim()).toList();
        if (normalized.any((imei) => !isValidImei(imei))) {
          throw Exception('IMEI phải đủ 15 số và đúng mã kiểm tra');
        }
        if (normalized.toSet().length != normalized.length) {
          throw Exception('Danh sách nhập đang có IMEI trùng nhau');
        }
        final placeholders = List.filled(normalized.length, '?').join(',');
        final existed = await txn.rawQuery(
          'SELECT imei FROM serial_units WHERE imei IN ($placeholders)',
          normalized,
        );
        if (existed.isNotEmpty) {
          throw Exception(
            'IMEI ${existed.first['imei']} đã có trong kho/lịch sử',
          );
        }
      }
      if (unitCost < 0 || serials.any((serial) => serial.cost < 0)) {
        throw Exception('Giá nhập không hợp lệ');
      }
      final now = DateTime.now().toIso8601String();
      final code = 'PN${DateTime.now().millisecondsSinceEpoch}';
      final purchaseTotal = tracks
          ? serials.fold<int>(0, (sum, serial) => sum + serial.cost)
          : quantity * unitCost;
      if (paid < 0 || paid > purchaseTotal) {
        throw Exception('Số tiền đã thanh toán không hợp lệ');
      }
      await _ensureSupplier(txn, supplier);
      final purchaseId = await txn.insert('purchases', {
        'code': code,
        'supplier': supplier,
        'total': purchaseTotal,
        'paid': paid,
        'payment_method': paymentMethod,
        'created_at': now,
      });
      await txn.insert('purchase_items', {
        'purchase_id': purchaseId,
        'product_id': productId,
        'quantity': quantity,
        'unit_cost': tracks && quantity > 0
            ? (purchaseTotal / quantity).round()
            : unitCost,
      });
      if (tracks) {
        for (final serial in serials) {
          final serialId = await txn.insert('serial_units', {
            'product_id': productId,
            'imei': serial.imei.trim(),
            'color': serial.color.trim(),
            'condition_text': serial.conditionText.trim(),
            'cost': serial.cost,
            'purchase_id': purchaseId,
            'created_at': now,
          });
          await txn.insert('inventory_movements', {
            'product_id': productId,
            'serial_id': serialId,
            'kind': 'purchase',
            'quantity_delta': 1,
            'reference_type': 'purchase',
            'reference_id': purchaseId,
            'created_at': now,
          });
        }
      } else {
        final oldQty = product['quantity'] as int;
        final oldCost = product['avg_cost'] as int;
        final newQty = oldQty + quantity;
        final newCost = newQty == 0
            ? 0
            : ((oldQty * oldCost + quantity * unitCost) / newQty).round();
        await txn.update(
          'products',
          {'quantity': newQty, 'avg_cost': newCost},
          where: 'id=?',
          whereArgs: [productId],
        );
        await txn.insert('inventory_movements', {
          'product_id': productId,
          'kind': 'purchase',
          'quantity_delta': quantity,
          'reference_type': 'purchase',
          'reference_id': purchaseId,
          'created_at': now,
        });
      }
      return purchaseId;
    });
  }

  Future<int> _localCompleteMultiPurchase({
    required List<PurchaseLineDraft> items,
    required String supplier,
    required int paid,
    required String paymentMethod,
    int? draftId, String? completionKey,
  }) async {
    if (items.isEmpty) throw Exception('Hãy thêm ít nhất một sản phẩm');
    return _nestedTransaction((txn) async {
      final fingerprint = sha256.convert(utf8.encode(jsonEncode({
        'items': items.map(_encodeDraft).toList(), 'supplier': supplier,
        'paid': paid, 'paymentMethod': paymentMethod, 'draftId': draftId,
      }))).toString();
      if (completionKey != null) {
        if (completionKey.trim().isEmpty) throw ArgumentError('Mã hoàn thành rỗng');
        final prior = await txn.query('purchase_completions', where:'completion_key=?', whereArgs:[completionKey]);
        if (prior.isNotEmpty) {
          if(prior.single['payload_hash'] != fingerprint) throw StateError('Mã hoàn thành đã dùng cho phiếu khác');
          return prior.single['purchase_id'] as int;
        }
      }
      if (draftId != null && (await txn.query('purchase_drafts',where:'id=?',whereArgs:[draftId])).isEmpty) {
        throw StateError('Phiếu tạm không còn tồn tại');
      }
      final prepared = <Map<String, Object?>>[];
      final allImeis = <String>[];
      final productIds = <int>{};
      var purchaseTotal = 0;

      for (final item in items) {
        final productId = item.product['id'] as int;
        if (!productIds.add(productId)) {
          throw Exception('${item.product['name']} đang có hai dòng nhập');
        }
        final rows = await txn.query(
          'products',
          where: 'id=? AND active=1',
          whereArgs: [productId],
        );
        if (rows.isEmpty) {
          throw Exception('${item.product['name']} không còn kinh doanh');
        }
        final product = rows.single;
        final tracks = product['track_imei'] == 1;
        final quantity = tracks ? item.serials.length : item.quantity;
        if (quantity <= 0) {
          throw Exception('Số lượng ${product['name']} phải lớn hơn 0');
        }
        if (item.unitPrice <= 0) {
          throw Exception('Đơn giá ${product['name']} phải lớn hơn 0');
        }
        if (item.discountPerItem < 0 || item.discountPerItem > item.unitPrice) {
          throw Exception('Giảm giá ${product['name']} không hợp lệ');
        }
        if (tracks) {
          final imeis = item.serials
              .map((serial) => serial.imei.trim())
              .toList();
          if (imeis.any((imei) => !isValidImei(imei))) {
            throw Exception(
              'IMEI của ${product['name']} phải đủ 15 số và đúng mã kiểm tra',
            );
          }
          allImeis.addAll(imeis);
        }
        if (item.serials.any((serial) => serial.cost < 0)) throw Exception('Giá vốn từng máy không hợp lệ');
        final lineTotal = item.total;
        purchaseTotal += lineTotal;
        prepared.add({
          'draft': item,
          'product': product,
          'product_id': productId,
          'tracks': tracks,
          'quantity': quantity,
          'unit_cost': (lineTotal / quantity).round(),
        });
      }

      if (allImeis.toSet().length != allImeis.length) {
        throw Exception('Phiếu nhập đang có IMEI trùng nhau');
      }
      if (allImeis.isNotEmpty) {
        final placeholders = List.filled(allImeis.length, '?').join(',');
        final existed = await txn.rawQuery(
          'SELECT imei FROM serial_units WHERE imei IN ($placeholders)',
          allImeis,
        );
        if (existed.isNotEmpty) {
          throw Exception(
            'IMEI ${existed.first['imei']} đã có trong kho/lịch sử',
          );
        }
      }
      if (paid < 0 || paid > purchaseTotal) {
        throw Exception('Số tiền đã thanh toán không hợp lệ');
      }

      final now = DateTime.now().toIso8601String();
      final code = 'PN${DateTime.now().millisecondsSinceEpoch}';
      await _ensureSupplier(txn, supplier);
      final purchaseId = await txn.insert('purchases', {
        'code': code,
        'supplier': supplier.trim(),
        'total': purchaseTotal,
        'paid': paid,
        'payment_method': paymentMethod,
        'created_at': now,
      });

      for (final row in prepared) {
        final item = row['draft'] as PurchaseLineDraft;
        final product = row['product'] as Map<String, Object?>;
        final productId = row['product_id'] as int;
        final tracks = row['tracks'] as bool;
        final quantity = row['quantity'] as int;
        final unitCost = row['unit_cost'] as int;

        await txn.insert('purchase_items', {
          'purchase_id': purchaseId,
          'product_id': productId,
          'quantity': quantity,
          'unit_cost': unitCost,
        });
        if (tracks) {
          for (final serial in item.serials) {
            final serialId = await txn.insert('serial_units', {
              'product_id': productId,
              'imei': serial.imei.trim(),
              'color': serial.color.trim(),
              'condition_text': serial.conditionText.trim().isEmpty
                  ? 'Mới'
                  : serial.conditionText.trim(),
              'cost': serial.cost > 0 ? serial.cost : item.netUnitCost,
              'purchase_id': purchaseId,
              'created_at': now,
            });
            await txn.insert('inventory_movements', {
              'product_id': productId,
              'serial_id': serialId,
              'kind': 'purchase',
              'quantity_delta': 1,
              'reference_type': 'purchase',
              'reference_id': purchaseId,
              'created_at': now,
            });
          }
        } else {
          final oldQty = product['quantity'] as int;
          final oldCost = product['avg_cost'] as int;
          final newQty = oldQty + quantity;
          final newCost = ((oldQty * oldCost + quantity * unitCost) / newQty)
              .round();
          await txn.update(
            'products',
            {'quantity': newQty, 'avg_cost': newCost},
            where: 'id=?',
            whereArgs: [productId],
          );
          await txn.insert('inventory_movements', {
            'product_id': productId,
            'kind': 'purchase',
            'quantity_delta': quantity,
            'reference_type': 'purchase',
            'reference_id': purchaseId,
            'created_at': now,
          });
        }
      }
      if (draftId != null) await txn.delete('purchase_drafts',where:'id=?',whereArgs:[draftId]);
      if (completionKey != null) await txn.insert('purchase_completions',{
        'completion_key':completionKey,'purchase_id':purchaseId,'payload_hash':fingerprint,
      });
      return purchaseId;
    });
  }

  Future<int> _localCompleteMultiSale({
    required String invoiceCode,
    required List<SaleLineDraft> items,
    required String customer,
    required String phone,
    required int cash,
    required int transfer,
    required int warrantyMonths,
  }) async {
    if (items.isEmpty) throw Exception('Hãy thêm ít nhất một sản phẩm');
    return _nestedTransaction((txn) async {
      final prepared = <Map<String, Object?>>[];
      final requiredQuantities = <int, int>{};
      final productStocks = <int, int>{};
      final selectedSerials = <int>{};
      var total = 0;
      var discountTotal = 0;
      var costTotal = 0;

      for (final item in items) {
        final productId = item.product['id'] as int;
        final productRows = await txn.query(
          'products',
          where: 'id=? AND active=1',
          whereArgs: [productId],
        );
        if (productRows.isEmpty) {
          throw Exception(
            'Sản phẩm ${item.product['name']} không còn kinh doanh',
          );
        }
        final fresh = productRows.single;
        final tracksImei = fresh['track_imei'] == 1;
        if (item.unitPrice <= 0) {
          throw Exception('Giá bán phải lớn hơn 0');
        }
        if (item.discountPerItem < 0 || item.discountPerItem > item.unitPrice) {
          throw Exception('Giảm giá của ${fresh['name']} không hợp lệ');
        }

        final soldQuantity = tracksImei ? 1 : item.quantity;
        if (soldQuantity <= 0) {
          throw Exception('Số lượng bán phải lớn hơn 0');
        }
        int? serialId;
        var unitCost = (fresh['avg_cost'] as num).toInt();

        if (tracksImei) {
          serialId = item.serialId;
          if (serialId == null) {
            throw Exception('Phải chọn IMEI cho ${fresh['name']}');
          }
          if (!selectedSerials.add(serialId)) {
            throw Exception('Một IMEI đang được chọn hai lần');
          }
          final serialRows = await txn.query(
            'serial_units',
            where: "id=? AND product_id=? AND status='in_stock'",
            whereArgs: [serialId, productId],
          );
          if (serialRows.isEmpty) {
            throw Exception('IMEI ${item.imei} không còn trong kho');
          }
          unitCost = (serialRows.single['cost'] as num).toInt();
        } else {
          requiredQuantities[productId] =
              (requiredQuantities[productId] ?? 0) + soldQuantity;
          productStocks[productId] = (fresh['quantity'] as num).toInt();
        }

        final netUnitPrice = item.unitPrice - item.discountPerItem;
        total += netUnitPrice * soldQuantity;
        discountTotal += item.discountPerItem * soldQuantity;
        costTotal += unitCost * soldQuantity;
        prepared.add({
          'product_id': productId,
          'serial_id': serialId,
          'quantity': soldQuantity,
          'unit_price': netUnitPrice,
          'unit_cost': unitCost,
        });
      }

      for (final entry in requiredQuantities.entries) {
        if (entry.value > (productStocks[entry.key] ?? 0)) {
          throw Exception('Số lượng bán vượt tồn kho');
        }
      }
      if (cash < 0 || transfer < 0 || cash + transfer > total) {
        throw Exception('Số tiền thanh toán không hợp lệ');
      }
      if (warrantyMonths < 0) {
        throw Exception('Số tháng bảo hành không hợp lệ');
      }

      final now = DateTime.now().toIso8601String();
      await _ensureCustomer(txn, customer, phone);
      final saleId = await txn.insert('sales', {
        'code': invoiceCode,
        'customer': customer.trim().isEmpty ? 'Khách lẻ' : customer.trim(),
        'phone': phone.trim(),
        'total': total,
        'discount_total': discountTotal,
        'cost_total': costTotal,
        'paid_cash': cash,
        'paid_transfer': transfer,
        'debt': total - cash - transfer,
        'warranty_months': warrantyMonths,
        'created_at': now,
      });

      for (final item in prepared) {
        final productId = item['product_id'] as int;
        final serialId = item['serial_id'] as int?;
        final soldQuantity = item['quantity'] as int;
        await txn.insert('sale_items', {'sale_id': saleId, ...item});
        if (serialId != null) {
          final changed = await txn.update(
            'serial_units',
            {'status': 'sold'},
            where: "id=? AND status='in_stock'",
            whereArgs: [serialId],
          );
          if (changed == 0) throw Exception('IMEI không còn trong kho');
        } else {
          final changed = await txn.rawUpdate(
            '''UPDATE products SET quantity=quantity-?
               WHERE id=? AND quantity>=?''',
            [soldQuantity, productId, soldQuantity],
          );
          if (changed == 0) {
            throw Exception('Số lượng bán vượt tồn kho');
          }
        }
        await txn.insert('inventory_movements', {
          'product_id': productId,
          'serial_id': serialId,
          'kind': 'sale',
          'quantity_delta': -soldQuantity,
          'reference_type': 'sale',
          'reference_id': saleId,
          'created_at': now,
        });
      }
      return saleId;
    });
  }

  Future<List<Map<String, Object?>>> _localSales() async {
    final db = await _executor;
    return db.rawQuery('''SELECT s.*,
      GROUP_CONCAT(p.name, ' • ') product_names,
      GROUP_CONCAT(COALESCE(su.imei, ''), ' ') imeis
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id=s.id
      LEFT JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      GROUP BY s.id ORDER BY s.id DESC''');
  }

  Future<void> _localCancelSale(int saleId) async {
    await _nestedTransaction((txn) async {
      final saleRows = await txn.query(
        'sales',
        where: 'id=?',
        whereArgs: [saleId],
      );
      if (saleRows.isEmpty) throw Exception('Không tìm thấy hóa đơn');
      final sale = saleRows.single;
      if (sale['status'] == 'cancelled') return;
      final items = await txn.query(
        'sale_items',
        where: 'sale_id=?',
        whereArgs: [saleId],
      );
      final now = DateTime.now().toIso8601String();
      for (final item in items) {
        final productId = item['product_id'] as int;
        final serialId = item['serial_id'] as int?;
        final qty = item['quantity'] as int;
        if (serialId != null) {
          await txn.update(
            'serial_units',
            {'status': 'in_stock'},
            where: 'id=?',
            whereArgs: [serialId],
          );
        } else {
          await txn.rawUpdate(
            'UPDATE products SET quantity=quantity+? WHERE id=?',
            [qty, productId],
          );
        }
        await txn.insert('inventory_movements', {
          'product_id': productId,
          'serial_id': serialId,
          'kind': 'cancel_sale',
          'quantity_delta': qty,
          'reference_type': 'sale',
          'reference_id': saleId,
          'created_at': now,
        });
      }
      await txn.update(
        'sales',
        {'status': 'cancelled'},
        where: 'id=?',
        whereArgs: [saleId],
      );
    });
  }

  Future<void> _localDeleteSale(int saleId) async {
    await _nestedTransaction((txn) async {
      final saleRows = await txn.query(
        'sales',
        where: 'id=?',
        whereArgs: [saleId],
      );
      if (saleRows.isEmpty) throw Exception('Không tìm thấy hóa đơn');
      final sale = saleRows.single;
      final items = await txn.query(
        'sale_items',
        where: 'sale_id=?',
        whereArgs: [saleId],
      );

      // Hóa đơn chưa hủy vẫn đang trừ tồn, nên phải hoàn tồn trước khi xóa.
      if (sale['status'] != 'cancelled') {
        for (final item in items) {
          final productId = item['product_id'] as int;
          final serialId = item['serial_id'] as int?;
          final qty = item['quantity'] as int;
          if (serialId != null) {
            await txn.update(
              'serial_units',
              {'status': 'in_stock'},
              where: 'id=?',
              whereArgs: [serialId],
            );
          } else {
            await txn.rawUpdate(
              'UPDATE products SET quantity=quantity+? WHERE id=?',
              [qty, productId],
            );
          }
        }
      }

      // Xóa các dữ liệu con trước để giữ toàn vẹn khóa ngoại.
      await txn.rawDelete(
        '''DELETE FROM warranty_claims
           WHERE sale_item_id IN
             (SELECT id FROM sale_items WHERE sale_id=?)''',
        [saleId],
      );
      await txn.delete(
        'inventory_movements',
        where: "reference_type='sale' AND reference_id=?",
        whereArgs: [saleId],
      );
      await txn.delete('sale_items', where: 'sale_id=?', whereArgs: [saleId]);
      await txn.delete('sales', where: 'id=?', whereArgs: [saleId]);
    });
  }

  Future<String?> _localGetSetting(String key) async {
    final db = await _executor;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key=?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single['setting_value'] as String;
  }

  Future<void> _localSetSetting(String key, String value) async {
    final db = await _executor;
    await db.insert('app_settings', {
      'setting_key': key,
      'setting_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>> _localSaleDetail(int saleId) async {
    final db = await _executor;
    final sale = (await db.query(
      'sales',
      where: 'id=?',
      whereArgs: [saleId],
    )).single;
    final items = await db.rawQuery(
      '''SELECT si.*, p.name product_name,
      p.code product_code, su.imei, su.color
      FROM sale_items si
      JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      WHERE si.sale_id=? ORDER BY si.id''',
      [saleId],
    );
    return {'sale': sale, 'items': items};
  }

  Future<List<Map<String, Object?>>> _localWarranties() async {
    final db = await _executor;
    return db.rawQuery('''SELECT si.id sale_item_id, s.id sale_id, s.code,
      s.customer, s.phone, s.created_at, s.warranty_months,
      p.name product_name, su.imei,
      (SELECT COUNT(*) FROM warranty_claims wc
       WHERE wc.sale_item_id=si.id) claim_count,
      (SELECT wc.status FROM warranty_claims wc
       WHERE wc.sale_item_id=si.id ORDER BY wc.id DESC LIMIT 1) latest_status
      FROM sales s
      JOIN sale_items si ON si.sale_id=s.id
      JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      WHERE s.status='completed' AND p.track_imei=1 AND si.serial_id IS NOT NULL
      ORDER BY s.created_at DESC''');
  }

  Future<List<Map<String, Object?>>> _localWarrantyClaims(int saleItemId) async {
    final db = await _executor;
    return db.query(
      'warranty_claims',
      where: 'sale_item_id=?',
      whereArgs: [saleItemId],
      orderBy: 'id DESC',
    );
  }

  Future<void> _localAddWarrantyClaim({
    required int saleItemId,
    required String issue,
    required String note,
  }) async {
    if (issue.trim().isEmpty) throw Exception('Hãy nhập tình trạng bảo hành');
    final db = await _executor;
    await db.insert('warranty_claims', {
      'sale_item_id': saleItemId,
      'issue': issue.trim(),
      'note': note.trim(),
      'status': 'received',
      'received_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _localUpdateWarrantyClaimStatus(int id, String status) async {
    final db = await _executor;
    await db.update(
      'warranty_claims',
      {
        'status': status,
        'resolved_at': status == 'returned'
            ? DateTime.now().toIso8601String()
            : null,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> _localUpdateWarrantyClaim({
    required int id,
    required String issue,
    required String note,
    required String status,
  }) async {
    if (issue.trim().isEmpty) {
      throw Exception('Hãy nhập tình trạng máy');
    }
    final db = await _executor;
    final updated = await db.update(
      'warranty_claims',
      {
        'issue': issue.trim(),
        'note': note.trim(),
        'status': status,
        'resolved_at': status == 'returned'
            ? DateTime.now().toIso8601String()
            : null,
      },
      where: 'id=?',
      whereArgs: [id],
    );
    if (updated == 0) throw Exception('Không tìm thấy phiếu bảo hành');
  }

  Future<void> _localDeleteWarrantyClaim(int id) async {
    final db = await _executor;
    final deleted = await db.delete(
      'warranty_claims',
      where: 'id=?',
      whereArgs: [id],
    );
    if (deleted == 0) throw Exception('Không tìm thấy phiếu bảo hành');
  }

  Future<List<Map<String, Object?>>> _localCustomerDirectory() async {
    final db = await _executor;
    return db.query('customer_directory', orderBy: 'name COLLATE NOCASE');
  }

  Future<List<Map<String, Object?>>> _localSupplierDirectory() async {
    final db = await _executor;
    return db.query('supplier_directory', orderBy: 'name COLLATE NOCASE');
  }

  Future<Map<String, Object?>> _localAddCustomerDirectory({
    required String name,
    required String phone,
    required String note,
  }) async {
    if (name.trim().isEmpty) throw Exception('Hãy nhập tên khách hàng');
    final db = await _executor;
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final existing = await db.query(
      'customer_directory',
      where: cleanPhone.isNotEmpty
          ? "phone=? OR (LOWER(name)=LOWER(?) AND phone=?)"
          : "LOWER(name)=LOWER(?) AND phone=''",
      whereArgs: cleanPhone.isNotEmpty
          ? [cleanPhone, cleanName, cleanPhone]
          : [cleanName],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.single;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('customer_directory', {
      'name': cleanName,
      'phone': cleanPhone,
      'note': note.trim(),
      'created_at': now,
      'updated_at': now,
    });
    return (await db.query(
      'customer_directory',
      where: 'id=?',
      whereArgs: [id],
    )).single;
  }

  Future<Map<String, Object?>> _localUpdateCustomerDirectory({
    required int id,
    required String name,
    required String phone,
    required String note,
  }) async {
    if (name.trim().isEmpty) throw Exception('Hãy nhập tên khách hàng');
    return _nestedTransaction((txn) async {
      final old = (await txn.query(
        'customer_directory',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      final cleanName = name.trim();
      final cleanPhone = phone.trim();
      await txn.update(
        'customer_directory',
        {
          'name': cleanName,
          'phone': cleanPhone,
          'note': note.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [id],
      );
      for (final table in ['sales', 'repairs']) {
        await txn.update(
          table,
          {'customer': cleanName, 'phone': cleanPhone},
          where: 'LOWER(TRIM(customer))=LOWER(?) AND TRIM(phone)=?',
          whereArgs: ['${old['name']}'.trim(), '${old['phone']}'.trim()],
        );
      }
      return (await txn.query(
        'customer_directory',
        where: 'id=?',
        whereArgs: [id],
      )).single;
    });
  }

  Future<Map<String, Object?>> _localAddSupplierDirectory({
    required String name,
    required String phone,
    required String address,
    required String note,
  }) async {
    if (name.trim().isEmpty) throw Exception('Hãy nhập tên nhà cung cấp');
    final db = await _executor;
    final cleanName = name.trim();
    final existing = await db.query(
      'supplier_directory',
      where: 'LOWER(name)=LOWER(?)',
      whereArgs: [cleanName],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.single;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('supplier_directory', {
      'name': cleanName,
      'phone': phone.trim(),
      'address': address.trim(),
      'note': note.trim(),
      'created_at': now,
      'updated_at': now,
    });
    return (await db.query(
      'supplier_directory',
      where: 'id=?',
      whereArgs: [id],
    )).single;
  }

  Future<Map<String, Object?>> _localUpdateSupplierDirectory({
    required int id,
    required String name,
    required String phone,
    required String address,
    required String note,
  }) async {
    if (name.trim().isEmpty) throw Exception('Hãy nhập tên nhà cung cấp');
    return _nestedTransaction((txn) async {
      final old = (await txn.query(
        'supplier_directory',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      final cleanName = name.trim();
      await txn.update(
        'supplier_directory',
        {
          'name': cleanName,
          'phone': phone.trim(),
          'address': address.trim(),
          'note': note.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [id],
      );
      await txn.update(
        'purchases',
        {'supplier': cleanName},
        where: 'LOWER(TRIM(supplier))=LOWER(?)',
        whereArgs: ['${old['name']}'.trim()],
      );
      return (await txn.query(
        'supplier_directory',
        where: 'id=?',
        whereArgs: [id],
      )).single;
    });
  }

  Future<List<Map<String, Object?>>> _localCustomers() async {
    final db = await _executor;
    return db.rawQuery('''WITH sale_stats AS (
        SELECT LOWER(TRIM(customer)) name_key, TRIM(phone) phone_key,
          COUNT(*) invoice_count, COALESCE(SUM(total),0) sale_value,
          COALESCE(SUM(debt),0) sale_debt, MAX(created_at) last_sale
        FROM sales WHERE status='completed'
        GROUP BY LOWER(TRIM(customer)), TRIM(phone)
      ), quantity_stats AS (
        SELECT LOWER(TRIM(s.customer)) name_key, TRIM(s.phone) phone_key,
          COALESCE(SUM(si.quantity),0) item_quantity
        FROM sales s JOIN sale_items si ON si.sale_id=s.id
        WHERE s.status='completed'
        GROUP BY LOWER(TRIM(s.customer)), TRIM(s.phone)
      ), repair_stats AS (
        SELECT LOWER(TRIM(customer)) name_key, TRIM(phone) phone_key,
          COUNT(*) service_count, COALESCE(SUM(amount),0) service_value,
          COALESCE(SUM(amount-paid),0) service_debt,
          MAX(received_at) last_service
        FROM repairs WHERE status!='cancelled'
        GROUP BY LOWER(TRIM(customer)), TRIM(phone)
      ), debt_stats AS (
        SELECT party_id, COALESCE(SUM(amount_delta),0) debt_adjustment
        FROM debt_adjustments WHERE party_type='customer'
        GROUP BY party_id
      )
      SELECT c.id, c.name customer, c.phone, c.note,
        COALESCE(ss.invoice_count,0) invoice_count,
        COALESCE(rs.service_count,0) service_count,
        COALESCE(ss.invoice_count,0)+COALESCE(rs.service_count,0)
          transaction_count,
        COALESCE(qs.item_quantity,0) item_quantity,
        COALESCE(ss.sale_value,0) sale_value,
        COALESCE(rs.service_value,0) service_value,
        COALESCE(ss.sale_value,0)+COALESCE(rs.service_value,0) total_spent,
        MAX(0, COALESCE(ss.sale_debt,0)+COALESCE(rs.service_debt,0)
          +COALESCE(ds.debt_adjustment,0)) debt,
        CASE WHEN COALESCE(ss.last_sale,'')>=COALESCE(rs.last_service,'')
          THEN ss.last_sale ELSE rs.last_service END last_purchase
      FROM customer_directory c
      LEFT JOIN sale_stats ss ON ss.name_key=LOWER(TRIM(c.name))
        AND ss.phone_key=TRIM(c.phone)
      LEFT JOIN quantity_stats qs ON qs.name_key=LOWER(TRIM(c.name))
        AND qs.phone_key=TRIM(c.phone)
      LEFT JOIN repair_stats rs ON rs.name_key=LOWER(TRIM(c.name))
        AND rs.phone_key=TRIM(c.phone)
      LEFT JOIN debt_stats ds ON ds.party_id=c.id
      ORDER BY CASE WHEN last_purchase IS NULL THEN 1 ELSE 0 END,
        last_purchase DESC, c.name COLLATE NOCASE''');
  }

  Future<List<Map<String, Object?>>> _localCustomerSales(
    String name,
    String phone,
  ) async {
    final db = await _executor;
    return db.rawQuery(
      '''SELECT s.*,
      COALESCE(SUM(si.quantity),0) item_quantity,
      GROUP_CONCAT(p.name || CASE WHEN su.imei IS NULL OR su.imei=''
        THEN '' ELSE ' • IMEI ' || su.imei END, ' | ') product_names
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id=s.id
      LEFT JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      WHERE LOWER(TRIM(s.customer))=LOWER(?) AND TRIM(s.phone)=?
      GROUP BY s.id ORDER BY s.created_at DESC''',
      [name.trim(), phone.trim()],
    );
  }

  Future<List<Map<String, Object?>>> _localCustomerRepairs(
    String name,
    String phone,
  ) async {
    final db = await _executor;
    return db.query(
      'repairs',
      where:
          "LOWER(TRIM(customer))=LOWER(?) AND TRIM(phone)=? "
          "AND status!='cancelled' AND hidden=0",
      whereArgs: [name.trim(), phone.trim()],
      orderBy: 'received_at DESC',
    );
  }

  Future<List<Map<String, Object?>>> _localSuppliers() async {
    final db = await _executor;
    return db.rawQuery('''WITH purchase_stats AS (
        SELECT LOWER(TRIM(p.supplier)) name_key,
          COUNT(DISTINCT p.id) purchase_count,
          COALESCE(SUM(p.total),0) total_purchase,
          COALESCE(SUM(p.total-p.paid),0) debt,
          MAX(p.created_at) last_purchase
        FROM purchases p WHERE p.status='completed'
        GROUP BY LOWER(TRIM(p.supplier))
      ), quantity_stats AS (
        SELECT LOWER(TRIM(p.supplier)) name_key,
          COALESCE(SUM(pi.quantity),0) total_quantity
        FROM purchases p JOIN purchase_items pi ON pi.purchase_id=p.id
        WHERE p.status='completed' GROUP BY LOWER(TRIM(p.supplier))
      ), debt_stats AS (
        SELECT party_id, COALESCE(SUM(amount_delta),0) debt_adjustment
        FROM debt_adjustments WHERE party_type='supplier'
        GROUP BY party_id
      )
      SELECT d.id, d.name supplier_name, d.phone, d.address, d.note,
        COALESCE(ps.purchase_count,0) purchase_count,
        COALESCE(qs.total_quantity,0) total_quantity,
        COALESCE(ps.total_purchase,0) total_purchase,
        MAX(0, COALESCE(ps.debt,0)+COALESCE(ds.debt_adjustment,0)) debt,
        ps.last_purchase
      FROM supplier_directory d
      LEFT JOIN purchase_stats ps ON ps.name_key=LOWER(TRIM(d.name))
      LEFT JOIN quantity_stats qs ON qs.name_key=LOWER(TRIM(d.name))
      LEFT JOIN debt_stats ds ON ds.party_id=d.id
      ORDER BY CASE WHEN ps.last_purchase IS NULL THEN 1 ELSE 0 END,
        ps.last_purchase DESC, d.name COLLATE NOCASE''');
  }

  Future<List<Map<String, Object?>>> _localSupplierPurchases(String name) async {
    final db = await _executor;
    return db.rawQuery(
      '''SELECT p.*,
      COALESCE(SUM(pi.quantity),0) total_quantity,
      GROUP_CONCAT(pr.name || ' x' || pi.quantity, ' | ') product_names
      FROM purchases p
      LEFT JOIN purchase_items pi ON pi.purchase_id=p.id
      LEFT JOIN products pr ON pr.id=pi.product_id
      WHERE LOWER(TRIM(p.supplier))=LOWER(?)
      GROUP BY p.id ORDER BY p.created_at DESC''',
      [name.trim()],
    );
  }

  Future<List<Map<String, Object?>>> _localDebtAdjustments(
    String partyType,
    int partyId,
  ) async {
    final db = await _executor;
    return db.query(
      'debt_adjustments',
      where: 'party_type=? AND party_id=?',
      whereArgs: [partyType, partyId],
      orderBy: 'created_at DESC, id DESC',
    );
  }

  Future<void> _localAddDebtAdjustment({
    required String partyType,
    required int partyId,
    required int amount,
    required bool increase,
    required int currentDebt,
    required String note,
    bool isPayment=false, String paymentMethod='cash', String? occurredAt,
  }) async {
    if (partyType != 'customer' && partyType != 'supplier') {
      throw Exception('Loại công nợ không hợp lệ');
    }
    if (amount <= 0) throw Exception('Số tiền phải lớn hơn 0');
    final parties = partyType == 'customer'
        ? await _localCustomers()
        : await _localSuppliers();
    final matches = parties.where((row) => row['id'] == partyId);
    if (matches.isEmpty) throw Exception('Không tìm thấy đối tượng công nợ');
    final actualDebt = matches.single['debt'] as int;
    if (!increase && amount > actualDebt) {
      throw Exception('Số tiền giảm không được lớn hơn công nợ hiện tại');
    }
    if(isPayment&&increase)throw ArgumentError('Thanh toán phải giảm công nợ');
    if(!['cash','transfer'].contains(paymentMethod))throw ArgumentError('Phương thức không hợp lệ');
    final when=vietnamWallDate(occurredAt??financeNow()).toIso8601String().replaceAll('Z','');
    final db = await _executor;
    final adjustmentId=await db.insert('debt_adjustments', {
      'party_type': partyType,
      'party_id': partyId,
      'amount_delta': increase ? amount : -amount,
      'note': note.trim(),
      'created_at': when,
    });
    if(isPayment)await db.insert('payment_events',{'source_type':partyType,'source_id':adjustmentId,'entry_type':partyType=='customer'?'income':'expense','amount':amount,'payment_method':paymentMethod,'occurred_at':when,'note':note.trim().isEmpty?(partyType=='customer'?'Thu nợ khách hàng':'Trả nợ nhà cung cấp'):note.trim()});
  }

  Future<List<Map<String, Object?>>> _localRepairs() async {
    final db = await _executor;
    return db.query('repairs', where: 'hidden=0', orderBy: 'id DESC');
  }

  Future<void> _localAddRepair({
    required String customer,
    required String phone,
    required String device,
    required String imei,
    required String issue,
    required int amount,
    required int partsCost,
    required int paid,
    required String note,
  }) async {
    if (device.trim().isEmpty || issue.trim().isEmpty) {
      throw Exception('Hãy nhập tên máy và tình trạng lỗi');
    }
    if (amount < 0 || partsCost < 0 || paid < 0 || paid > amount) {
      throw Exception('Số tiền phiếu sửa chữa không hợp lệ');
    }
    final now = DateTime.now();
    await _nestedTransaction((txn) async {
      await _ensureCustomer(txn, customer, phone);
      await txn.insert('repairs', {
        'code': 'SC${now.millisecondsSinceEpoch}',
        'customer': customer.trim().isEmpty ? 'Khách lẻ' : customer.trim(),
        'phone': phone.trim(),
        'device': device.trim(),
        'imei': imei.trim(),
        'issue': issue.trim(),
        'amount': amount,
        'parts_cost': partsCost,
        'paid': paid,
        'initial_paid':paid,
        'status': 'received',
        'note': note.trim(),
        'received_at': now.toIso8601String(),
      });
    });
  }

  Future<void> _localUpdateRepairStatus(int id, String status) async {
    final db = await _executor;
    await db.update(
      'repairs',
      {
        'status': status,
        'completed_at': status == 'completed' || status == 'returned'
            ? DateTime.now().toIso8601String()
            : null,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<Map<String, Object?>> _localRepair(int id) async {
    final db = await _executor;
    final rows = await db.query('repairs', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) throw Exception('Không tìm thấy phiếu sửa chữa');
    return rows.first;
  }

  Future<void> _localUpdateRepair({
    required int id,
    required String customer,
    required String phone,
    required String device,
    required String imei,
    required String issue,
    required int amount,
    required int partsCost,
    required int paid,
    required String note,
  }) async {
    if (device.trim().isEmpty || issue.trim().isEmpty) {
      throw Exception('Hãy nhập tên máy và tình trạng lỗi');
    }
    if (amount < 0 || partsCost < 0 || paid < 0 || paid > amount) {
      throw Exception('Số tiền phiếu sửa chữa không hợp lệ');
    }
    await _nestedTransaction((txn) async {
      await _ensureCustomer(txn, customer, phone);
      final old=(await txn.query('repairs',where:'id=?',whereArgs:[id])).single;
      final delta=paid-(old['paid'] as int);
      if(delta!=0) await txn.insert('payment_events',{'source_type':'repair','source_id':id,'entry_type':delta>0?'income':'expense','amount':delta.abs(),'payment_method':'unknown','occurred_at':financeNow(),'note':'Thanh toán sửa chữa ${old['code']}'});
      final updated = await txn.update(
        'repairs',
        {
          'customer': customer.trim().isEmpty ? 'Khách lẻ' : customer.trim(),
          'phone': phone.trim(),
          'device': device.trim(),
          'imei': imei.trim(),
          'issue': issue.trim(),
          'amount': amount,
          'parts_cost': partsCost,
          'paid': paid,
          'note': note.trim(),
        },
        where: 'id=?',
        whereArgs: [id],
      );
      if (updated == 0) throw Exception('Không tìm thấy phiếu sửa chữa');
    });
  }

  Future<void> _localDeleteRepair(int id) async {
    final db = await _executor;
    final hidden = await db.update(
      'repairs',
      {'hidden': 1},
      where: 'id=?',
      whereArgs: [id],
    );
    if (hidden == 0) throw Exception('Không tìm thấy phiếu sửa chữa');
  }

  Future<List<Map<String, Object?>>> _localCashEntries() async {
    final db = await _executor;
    return db.query('cash_entries', orderBy: 'id DESC');
  }

  Future<void> _localAddCashEntry({
    required String type,
    required String category,
    required int amount,
    required String note,
  }) async {
    if (amount <= 0) throw Exception('Số tiền phải lớn hơn 0');
    final db = await _executor;
    await db.insert('cash_entries', {
      'entry_type': type,
      'category': category.trim().isEmpty
          ? (type == 'income' ? 'Thu khác' : 'Chi khác')
          : category.trim(),
      'amount': amount,
      'note': note.trim(),
      'created_at': financeNow(),
      'occurred_at':financeNow(),
    });
  }

  Future<void> _localDeleteCashEntry(int id) async {
    final db = await _executor;
    if((await db.query('recurring_payments',where:'cash_entry_id=?',whereArgs:[id])).isNotEmpty)throw StateError('Khoản định kỳ đã thanh toán không xóa tại sổ quỹ');
    await db.delete('cash_entries', where: 'id=?', whereArgs: [id]);
  }

  Future<void> _localRecordStocktake({
    required Map<String, Object?> product,
    required int actualQuantity,
    required String note,
  }) async {
    if (actualQuantity < 0) throw Exception('Số lượng thực tế không hợp lệ');
    await _nestedTransaction((txn) async {
      final systemQuantity = product['stock'] as int;
      final difference = actualQuantity - systemQuantity;
      final now = DateTime.now().toIso8601String();
      final stocktakeId = await txn.insert('stocktakes', {
        'product_id': product['id'],
        'system_quantity': systemQuantity,
        'actual_quantity': actualQuantity,
        'difference': difference,
        'note': note.trim(),
        'created_at': now,
      });
      if (product['track_imei'] != 1 && difference != 0) {
        await txn.update(
          'products',
          {'quantity': actualQuantity},
          where: 'id=?',
          whereArgs: [product['id']],
        );
        await txn.insert('inventory_movements', {
          'product_id': product['id'],
          'kind': 'stocktake',
          'quantity_delta': difference,
          'reference_type': 'stocktake',
          'reference_id': stocktakeId,
          'created_at': now,
        });
      }
    });
  }

  Future<List<Map<String, Object?>>> _localStocktakeHistory({int limit = 20}) async {
    final db = await _executor;
    return db.rawQuery(
      '''SELECT st.*, p.name product_name, p.track_imei
      FROM stocktakes st JOIN products p ON p.id=st.product_id
      ORDER BY st.id DESC LIMIT ?''',
      [limit],
    );
  }

  Future<void> _localInventoryAction({
    required Map<String, Object?> product,
    required String kind,
    required int quantity,
    required int? serialId,
  }) async {
    await _nestedTransaction((txn) async {
      final now = DateTime.now();
      final referenceId = now.millisecondsSinceEpoch;
      final tracks = product['track_imei'] == 1;
      if (tracks) {
        if (serialId == null) throw Exception('Hãy chọn IMEI');
        final targetStatus = kind == 'supplier_return'
            ? 'returned_supplier'
            : 'discarded';
        final changed = await txn.update(
          'serial_units',
          {'status': targetStatus},
          where: "id=? AND status='in_stock'",
          whereArgs: [serialId],
        );
        if (changed != 1) throw Exception('IMEI không còn trong kho');
      } else {
        final fresh = (await txn.query(
          'products',
          where: 'id=?',
          whereArgs: [product['id']],
        )).single;
        final stock = fresh['quantity'] as int;
        if (quantity <= 0 || quantity > stock) {
          throw Exception('Số lượng vượt quá tồn kho');
        }
        await txn.rawUpdate(
          'UPDATE products SET quantity=quantity-? WHERE id=?',
          [quantity, product['id']],
        );
      }
      await txn.insert('inventory_movements', {
        'product_id': product['id'],
        'serial_id': serialId,
        'kind': kind,
        'quantity_delta': tracks ? -1 : -quantity,
        'reference_type': kind,
        'reference_id': referenceId,
        'created_at': now.toIso8601String(),
      });
    });
  }

  Future<String> _localExportBackup() async {
    final db = await _executor;
    const tables = [
      'products',
      'purchases',
      'serial_units',
      'purchase_items',
      'sales',
      'sale_items',
      'inventory_movements',
      'repairs',
      'warranty_claims',
      'cash_entries',
      'stocktakes',
      'customer_directory',
      'supplier_directory',
      'debt_adjustments',
      'product_categories',
      'product_brands',
      'app_settings',
      'purchase_drafts',
      'purchase_completions',
      'recurring_expenses',
      'payment_events',
      'recurring_payments',
    ];
    final data = <String, Object?>{
      'app': 'MinhCanhMobileV3',
      'backup_version': 7,
      'created_at': DateTime.now().toIso8601String(),
    };
    for (final table in tables) {
      data[table] = await db.query(table);
    }
    return jsonEncode(data);
  }

  Future<void> _localRestoreBackup(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map || decoded['app'] != 'MinhCanhMobileV3') {
      throw Exception('Nội dung sao lưu không đúng của Minh Cảnh Mobile V3');
    }
    const deleteOrder = [
      'recurring_payments',
      'recurring_expenses',
      'payment_events',
      'purchase_completions',
      'purchase_drafts',
      'warranty_claims',
      'stocktakes',
      'cash_entries',
      'debt_adjustments',
      'repairs',
      'inventory_movements',
      'sale_items',
      'sales',
      'purchase_items',
      'serial_units',
      'purchases',
      'products',
      'customer_directory',
      'supplier_directory',
      'product_categories',
      'product_brands',
      'app_settings',
    ];
    const insertOrder = [
      'products',
      'purchases',
      'serial_units',
      'purchase_items',
      'sales',
      'sale_items',
      'inventory_movements',
      'repairs',
      'warranty_claims',
      'cash_entries',
      'stocktakes',
      'customer_directory',
      'supplier_directory',
      'debt_adjustments',
      'product_categories',
      'product_brands',
      'app_settings',
      'purchase_drafts',
      'purchase_completions',
      'recurring_expenses',
      'payment_events',
      'recurring_payments',
    ];
    if(decoded['backup_version']==6) { decoded['purchase_drafts']=[]; decoded['purchase_completions']=[]; decoded['recurring_expenses']=[]; decoded['recurring_payments']=[]; decoded['payment_events']=[];
      for(final row in decoded['repairs'] as List? ?? []) { if(row is Map) row['initial_paid']=row['paid']??0; } }
    if(decoded['backup_version']!=6 && decoded['backup_version']!=7)throw Exception('Phiên bản sao lưu chưa được hỗ trợ');
    for(final table in insertOrder){
      final rows=decoded[table];
      if(rows is! List || rows.any((row)=>row is! Map))throw Exception('Bản sao lưu thiếu hoặc hỏng bảng $table');
    }
    await _nestedTransaction((txn) async {
        await txn.execute('CREATE TABLE IF NOT EXISTS restore_safety(id INTEGER PRIMARY KEY, source TEXT NOT NULL)');
        await txn.insert('restore_safety',{'id':1,'source':await _localExportBackup()},conflictAlgorithm:ConflictAlgorithm.replace);
        await txn.execute('PRAGMA defer_foreign_keys = ON');
        for (final table in deleteOrder) {
          await txn.delete(table);
        }
        for (final table in insertOrder) {
          final rows = decoded[table];
          if (rows is! List) continue;
          for (final raw in rows) {
            if (raw is Map) {
              await txn.insert(
                table,
                Map<String, Object?>.from(raw),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
        await _backfillDirectories(txn);
        await _createV6Tables(txn);
        await _createV7Tables(txn);
        await _createFinanceTables(txn);
        if((await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty)throw Exception('Bản sao lưu có dữ liệu liên kết không hợp lệ');
        // Restoring replaces business state: old success receipts no longer
        // prove that their effects exist. The monotonic revision rejects retries.
        await txn.delete('lan_requests');
      });
  }

  Future<Map<String, int>> _localReportSummary(DateTime start, DateTime end) async {
    final db = await _executor;
    final from = start.toIso8601String();
    final to = end.toIso8601String();
    final sale = (await db.rawQuery(
      '''SELECT
      COALESCE(SUM(total),0) revenue,
      COALESCE(SUM(total-cost_total),0) gross_profit,
      COALESCE(SUM(debt),0) debt,
      COALESCE(SUM(paid_cash+paid_transfer),0) collected,
      COUNT(*) invoices
      FROM sales
      WHERE status='completed' AND created_at>=? AND created_at<?''',
      [from, to],
    )).single;
    final sold = (await db.rawQuery(
      '''SELECT
      COALESCE(SUM(si.quantity),0) products_sold
      FROM sale_items si
      JOIN sales s ON s.id=si.sale_id
      WHERE s.status='completed' AND s.created_at>=? AND s.created_at<?''',
      [from, to],
    )).single;
    final repair = (await db.rawQuery(
      '''SELECT
      COALESCE(SUM(amount),0) revenue,
      COALESCE(SUM(amount-parts_cost),0) gross_profit,
      COUNT(*) repairs
      FROM repairs
      WHERE status IN ('completed','returned')
        AND COALESCE(completed_at,received_at)>=?
        AND COALESCE(completed_at,received_at)<?''',
      [from, to],
    )).single;
    final finance=await financeSummary(start,end);
    int n(Map<String, Object?> row, String key) =>
        (row[key] as num? ?? 0).toInt();
    final salesRevenue = n(sale, 'revenue');
    final repairRevenue = n(repair, 'revenue');
    final grossProfit = finance['gross_profit']!;
    final otherIncome = finance['business_income']!;
    final expenses = finance['business_expenses']!;
    return {
      'revenue': finance['revenue']!,
      'sales_revenue': salesRevenue,
      'repair_revenue': repairRevenue,
      'gross_profit': grossProfit,
      'other_income': otherIncome,
      'expenses': expenses,
      'net_profit': grossProfit + otherIncome - expenses,
      'debt': n(sale, 'debt'),
      'collected': n(sale, 'collected'),
      'invoices': n(sale, 'invoices'),
      'products_sold': n(sold, 'products_sold'),
      'repairs': n(repair, 'repairs'),
    };
  }

  Future<List<Map<String, Object?>>> _localProductReport(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _executor;
    final rows=await db.rawQuery(
      '''SELECT p.id, p.code, p.name, p.category, p.brand, p.track_imei, p.active,
      CASE WHEN p.track_imei=1 THEN
        (SELECT COUNT(*) FROM serial_units su
         WHERE su.product_id=p.id AND su.status='in_stock')
      ELSE p.quantity END stock,
      CASE WHEN p.track_imei=1 THEN
        COALESCE((SELECT SUM(su.cost) FROM serial_units su
         WHERE su.product_id=p.id AND su.status='in_stock'),0)
      ELSE p.quantity*p.avg_cost END stock_value,
      COALESCE(r.sold_quantity,0) sold_quantity,
      COALESCE(r.revenue,0) revenue,
      COALESCE(r.profit,0) profit
      FROM products p
      LEFT JOIN (
        SELECT si.product_id,
          SUM(si.quantity) sold_quantity,
          SUM(si.quantity*si.unit_price) revenue,
          SUM(si.quantity*(si.unit_price-si.unit_cost)) profit
        FROM sale_items si
        JOIN sales s ON s.id=si.sale_id
        WHERE s.status='completed' AND s.created_at>=? AND s.created_at<?
        GROUP BY si.product_id
      ) r ON r.product_id=p.id
      WHERE p.active>=0
      ORDER BY revenue DESC, p.name''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return _inventoryPeriodRows(rows,start,end);
  }

  Future<List<Map<String, Object?>>> _localInvoiceReport(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _executor;
    return db.rawQuery(
      '''SELECT s.*, s.total-s.cost_total profit,
      GROUP_CONCAT(p.name, ' • ') product_names,
      GROUP_CONCAT(COALESCE(su.imei, ''), ' ') imeis
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id=s.id
      LEFT JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      WHERE s.status='completed' AND s.created_at>=? AND s.created_at<?
      GROUP BY s.id ORDER BY s.created_at DESC''',
      [start.toIso8601String(), end.toIso8601String()],
    );
  }

  Future<List<Map<String, Object?>>> _localSalesTrend(String mode) async {
    final db = await _executor;
    final now = DateTime.now();
    late DateTime first;
    late int count;
    DateTime Function(DateTime, int) next;
    String Function(DateTime) label;

    if (mode == 'year') {
      first = DateTime(now.year - 4);
      count = 5;
      next = (value, amount) => DateTime(value.year + amount);
      label = (value) => '${value.year}';
    } else if (mode == 'month') {
      first = DateTime(now.year, now.month - 11);
      count = 12;
      next = (value, amount) => DateTime(value.year, value.month + amount);
      label = (value) => DateFormat('MM/yyyy').format(value);
    } else {
      first = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6));
      count = 7;
      next = (value, amount) => value.add(Duration(days: amount));
      label = (value) => DateFormat('dd/MM').format(value);
    }

    final rows = <Map<String, Object?>>[];
    for (var index = 0; index < count; index++) {
      final start = next(first, index);
      final end = next(first, index + 1);
      final startText = start.toIso8601String();
      final endText = end.toIso8601String();
      final result = await db.rawQuery(
        '''
        SELECT
          COALESCE((SELECT SUM(total) FROM sales
            WHERE status='completed' AND created_at>=? AND created_at<?),0)
            AS revenue,
          COALESCE((SELECT COUNT(*) FROM sales
            WHERE status='completed' AND created_at>=? AND created_at<?),0)
            AS invoices,
          COALESCE((SELECT SUM(si.quantity)
            FROM sale_items si
            JOIN sales s ON s.id=si.sale_id
            WHERE s.status='completed'
              AND s.created_at>=? AND s.created_at<?),0)
            AS products
      ''',
        [startText, endText, startText, endText, startText, endText],
      );
      final row = result.first;
      rows.add({
        'label': label(start),
        'revenue': (row['revenue'] as num? ?? 0).toInt(),
        'invoices': (row['invoices'] as num? ?? 0).toInt(),
        'products': (row['products'] as num? ?? 0).toInt(),
      });
    }
    return rows;
  }

  Future<Map<String, int>> _localDashboard() async {
    final db = await _executor;
    final salesRows = await db.rawQuery('''SELECT
      COALESCE(SUM(CASE WHEN status='completed' THEN total ELSE 0 END),0) revenue,
      COALESCE(SUM(CASE WHEN status='completed' THEN total-cost_total ELSE 0 END),0) profit,
      COALESCE(SUM(CASE WHEN status='completed' THEN debt ELSE 0 END),0) debt,
      COALESCE(SUM(CASE WHEN status='completed' THEN paid_cash+paid_transfer ELSE 0 END),0) fund,
      COALESCE(SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END),0) invoices
      FROM sales''');
    final repairRows = await db.rawQuery('''SELECT
      COALESCE(SUM(CASE WHEN status IN ('completed','returned') THEN amount ELSE 0 END),0) revenue,
      COALESCE(SUM(CASE WHEN status IN ('completed','returned') THEN amount-parts_cost ELSE 0 END),0) profit,
      COALESCE(SUM(CASE WHEN status!='cancelled' THEN amount-paid ELSE 0 END),0) debt,
      COALESCE(SUM(CASE WHEN status!='cancelled' THEN paid ELSE 0 END),0) fund,
      COALESCE(SUM(CASE WHEN status NOT IN ('completed','returned','cancelled') THEN 1 ELSE 0 END),0) pending
      FROM repairs''');
    final finance=await financeSummary(DateTime(2000),DateTime(2100));
    final debtAdjustmentRows = await db.rawQuery('''SELECT
      COALESCE(SUM(amount_delta),0) amount
      FROM debt_adjustments WHERE party_type='customer' ''');
    final stockRows = await db.rawQuery('''SELECT
      COALESCE((SELECT SUM(quantity*avg_cost) FROM products
        WHERE track_imei=0 AND active>=0),0) +
      COALESCE((SELECT SUM(su.cost) FROM serial_units su
        JOIN products p ON p.id=su.product_id
        WHERE su.status='in_stock' AND p.active>=0),0) stock_value''');
    int n(Map<String, Object?> row, String key) =>
        (row[key] as num? ?? 0).toInt();
    final sale = salesRows.single;
    final repair = repairRows.single;

    return {
      'revenue': n(sale, 'revenue') + n(repair, 'revenue'),
      'profit': finance['business_profit']!,
      'debt':
          n(sale, 'debt') +
          n(repair, 'debt') +
          n(debtAdjustmentRows.single, 'amount'),
      'fund': finance['cash_flow']!,
      'invoices': n(sale, 'invoices'),
      'pending_repairs': n(repair, 'pending'),
      'stock_value': n(stockRows.single, 'stock_value'),
      'warranties':
          Sqflite.firstIntValue(
            await db.rawQuery(
              "SELECT COUNT(*) FROM sale_items si JOIN sales s ON s.id=si.sale_id JOIN products p ON p.id=si.product_id WHERE s.status='completed' AND p.track_imei=1 AND si.serial_id IS NOT NULL",
            ),
          ) ??
          0,
    };
  }

  Future<List<Map<String, Object?>>> productCategories() async {
    if(kIsWeb) { final value=await remoteBridge.call('productCategories',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localProductCategories(), write:false);
  }
  Future<String> addProductCategory(String rawName, {int? parentId}) async {
    if(kIsWeb) { final value=await remoteBridge.call('addProductCategory',{'rawName':rawName,'parentId':parentId},write:true); return value as String; }
    return _callLocal<String>(()=>_localAddProductCategory(rawName, parentId: parentId), write:true);
  }
  Future<void> renameProductCategory(int id, String rawName) async {
    if(kIsWeb) { await remoteBridge.call('renameProductCategory',{'id':id,'rawName':rawName},write:true); return; }
    return _callLocal<void>(()=>_localRenameProductCategory(id, rawName), write:true);
  }
  Future<void> deleteProductCategory(int id) async {
    if(kIsWeb) { await remoteBridge.call('deleteProductCategory',{'id':id},write:true); return; }
    return _callLocal<void>(()=>_localDeleteProductCategory(id), write:true);
  }
  Future<List<Map<String, Object?>>> productBrands() async {
    if(kIsWeb) { final value=await remoteBridge.call('productBrands',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localProductBrands(), write:false);
  }
  Future<String> addProductBrand(String rawName) async {
    if(kIsWeb) { final value=await remoteBridge.call('addProductBrand',{'rawName':rawName},write:true); return value as String; }
    return _callLocal<String>(()=>_localAddProductBrand(rawName), write:true);
  }
  Future<void> renameProductBrand(int id, String rawName) async {
    if(kIsWeb) { await remoteBridge.call('renameProductBrand',{'id':id,'rawName':rawName},write:true); return; }
    return _callLocal<void>(()=>_localRenameProductBrand(id, rawName), write:true);
  }
  Future<void> deleteProductBrand(int id) async {
    if(kIsWeb) { await remoteBridge.call('deleteProductBrand',{'id':id},write:true); return; }
    return _callLocal<void>(()=>_localDeleteProductBrand(id), write:true);
  }
  Future<String> nextProductCode() async {
    if(kIsWeb) { final value=await remoteBridge.call('nextProductCode',{},write:false); return value as String; }
    return _callLocal<String>(()=>_localNextProductCode(), write:false);
  }
  Future<List<Map<String, Object?>>> products({
    bool includeInactive = false,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('products',{'includeInactive':includeInactive},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localProducts(includeInactive: includeInactive), write:false);
  }
  Future<Map<String, Object?>> product(int id) async {
    if(kIsWeb) { final value=await remoteBridge.call('product',{'id':id},write:false); final result=Map<String,Object?>.from(value as Map); if(result['items'] is List) result['items']=(result['items'] as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); return result; }
    return _callLocal<Map<String, Object?>>(()=>_localProduct(id), write:false);
  }
  Future<int> addProduct(Map<String, Object?> row) async {
    if(kIsWeb) { final value=await remoteBridge.call('addProduct',{'row':row},write:true); return value as int; }
    return _callLocal<int>(()=>_localAddProduct(row), write:true);
  }
  Future<void> updateProduct({
    required int id,
    required String code,
    required String name,
    required String category,
    required String brand,
    required String capacity,
    required int salePrice,
    int? averageCost,
  }) async {
    if(kIsWeb) { await remoteBridge.call('updateProduct',{'id':id,'code':code,'name':name,'category':category,'brand':brand,'capacity':capacity,'salePrice':salePrice,'averageCost':averageCost},write:true); return; }
    return _callLocal<void>(()=>_localUpdateProduct(id: id, code: code, name: name, category: category, brand: brand, capacity: capacity, salePrice: salePrice, averageCost: averageCost), write:true);
  }
  Future<void> setProductActive(int id, bool active) async {
    if(kIsWeb) { await remoteBridge.call('setProductActive',{'id':id,'active':active},write:true); return; }
    return _callLocal<void>(()=>_localSetProductActive(id, active), write:true);
  }
  Future<void> deleteProduct(int id) async {
    if(kIsWeb) { await remoteBridge.call('deleteProduct',{'id':id},write:true); return; }
    return _callLocal<void>(()=>_localDeleteProduct(id), write:true);
  }
  Future<List<Map<String, Object?>>> serials(
    int productId, {
    String? status,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('serials',{'productId':productId,'status':status},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localSerials(productId, status: status), write:false);
  }
  Future<bool> serialExists(String imei) async {
    if(kIsWeb) { final value=await remoteBridge.call('serialExists',{'imei':imei},write:false); return value as bool; }
    return _callLocal<bool>(()=>_localSerialExists(imei), write:false);
  }
  Future<void> updateSerialUnit({
    required int id,
    required String imei,
    required String color,
    required String conditionText,
    required int cost,
  }) async {
    if(kIsWeb) { await remoteBridge.call('updateSerialUnit',{'id':id,'imei':imei,'color':color,'conditionText':conditionText,'cost':cost},write:true); return; }
    return _callLocal<void>(()=>_localUpdateSerialUnit(id: id, imei: imei, color: color, conditionText: conditionText, cost: cost), write:true);
  }
  Future<int> completePurchase({
    required int productId,
    required int quantity,
    required int unitCost,
    required String supplier,
    required int paid,
    required String paymentMethod,
    required List<SerialDraft> serials,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('completePurchase',{'productId':productId,'quantity':quantity,'unitCost':unitCost,'supplier':supplier,'paid':paid,'paymentMethod':paymentMethod,'serials':serials.map(_encodeDraft).toList()},write:true); return value as int; }
    return _callLocal<int>(()=>_localCompletePurchase(productId: productId, quantity: quantity, unitCost: unitCost, supplier: supplier, paid: paid, paymentMethod: paymentMethod, serials: serials), write:true);
  }
  Future<int> completeMultiPurchase({
    required List<PurchaseLineDraft> items,
    required String supplier,
    required int paid,
    required String paymentMethod,
    int? draftId, String? completionKey,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('completeMultiPurchase',{'items':items.map(_encodeDraft).toList(),'supplier':supplier,'paid':paid,'paymentMethod':paymentMethod,'draftId':draftId,'completionKey':completionKey},write:true); return value as int; }
    return _callLocal<int>(()=>_localCompleteMultiPurchase(items: items, supplier: supplier, paid: paid, paymentMethod: paymentMethod, draftId:draftId, completionKey:completionKey), write:true);
  }
  Future<int> completeMultiSale({
    required String invoiceCode,
    required List<SaleLineDraft> items,
    required String customer,
    required String phone,
    required int cash,
    required int transfer,
    required int warrantyMonths,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('completeMultiSale',{'invoiceCode':invoiceCode,'items':items.map(_encodeDraft).toList(),'customer':customer,'phone':phone,'cash':cash,'transfer':transfer,'warrantyMonths':warrantyMonths},write:true); return value as int; }
    return _callLocal<int>(()=>_localCompleteMultiSale(invoiceCode: invoiceCode, items: items, customer: customer, phone: phone, cash: cash, transfer: transfer, warrantyMonths: warrantyMonths), write:true);
  }
  Future<List<Map<String, Object?>>> sales() async {
    if(kIsWeb) { final value=await remoteBridge.call('sales',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localSales(), write:false);
  }
  Future<void> cancelSale(int saleId) async {
    if(kIsWeb) { await remoteBridge.call('cancelSale',{'saleId':saleId},write:true); return; }
    return _callLocal<void>(()=>_localCancelSale(saleId), write:true);
  }
  Future<void> deleteSale(int saleId) async {
    if(kIsWeb) { await remoteBridge.call('deleteSale',{'saleId':saleId},write:true); return; }
    return _callLocal<void>(()=>_localDeleteSale(saleId), write:true);
  }
  Future<String?> getSetting(String key) async {
    if(kIsWeb) { final value=await remoteBridge.call('getSetting',{'key':key},write:false); return value as String?; }
    return _callLocal<String?>(()=>_localGetSetting(key), write:false);
  }
  Future<void> setSetting(String key, String value) async {
    if(kIsWeb) { await remoteBridge.call('setSetting',{'key':key,'value':value},write:true); return; }
    return _callLocal<void>(()=>_localSetSetting(key, value), write:true);
  }
  Future<Map<String, Object?>> saleDetail(int saleId) async {
    if(kIsWeb) { final value=await remoteBridge.call('saleDetail',{'saleId':saleId},write:false); final result=Map<String,Object?>.from(value as Map); if(result['items'] is List) result['items']=(result['items'] as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); return result; }
    return _callLocal<Map<String, Object?>>(()=>_localSaleDetail(saleId), write:false);
  }
  Future<List<Map<String, Object?>>> warranties() async {
    if(kIsWeb) { final value=await remoteBridge.call('warranties',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localWarranties(), write:false);
  }
  Future<List<Map<String, Object?>>> warrantyClaims(int saleItemId) async {
    if(kIsWeb) { final value=await remoteBridge.call('warrantyClaims',{'saleItemId':saleItemId},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localWarrantyClaims(saleItemId), write:false);
  }
  Future<void> addWarrantyClaim({
    required int saleItemId,
    required String issue,
    required String note,
  }) async {
    if(kIsWeb) { await remoteBridge.call('addWarrantyClaim',{'saleItemId':saleItemId,'issue':issue,'note':note},write:true); return; }
    return _callLocal<void>(()=>_localAddWarrantyClaim(saleItemId: saleItemId, issue: issue, note: note), write:true);
  }
  Future<void> updateWarrantyClaimStatus(int id, String status) async {
    if(kIsWeb) { await remoteBridge.call('updateWarrantyClaimStatus',{'id':id,'status':status},write:true); return; }
    return _callLocal<void>(()=>_localUpdateWarrantyClaimStatus(id, status), write:true);
  }
  Future<void> updateWarrantyClaim({
    required int id,
    required String issue,
    required String note,
    required String status,
  }) async {
    if(kIsWeb) { await remoteBridge.call('updateWarrantyClaim',{'id':id,'issue':issue,'note':note,'status':status},write:true); return; }
    return _callLocal<void>(()=>_localUpdateWarrantyClaim(id: id, issue: issue, note: note, status: status), write:true);
  }
  Future<void> deleteWarrantyClaim(int id) async {
    if(kIsWeb) { await remoteBridge.call('deleteWarrantyClaim',{'id':id},write:true); return; }
    return _callLocal<void>(()=>_localDeleteWarrantyClaim(id), write:true);
  }
  Future<List<Map<String, Object?>>> customerDirectory() async {
    if(kIsWeb) { final value=await remoteBridge.call('customerDirectory',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localCustomerDirectory(), write:false);
  }
  Future<List<Map<String, Object?>>> supplierDirectory() async {
    if(kIsWeb) { final value=await remoteBridge.call('supplierDirectory',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localSupplierDirectory(), write:false);
  }
  Future<Map<String, Object?>> addCustomerDirectory({
    required String name,
    required String phone,
    required String note,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('addCustomerDirectory',{'name':name,'phone':phone,'note':note},write:true); final result=Map<String,Object?>.from(value as Map); if(result['items'] is List) result['items']=(result['items'] as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); return result; }
    return _callLocal<Map<String, Object?>>(()=>_localAddCustomerDirectory(name: name, phone: phone, note: note), write:true);
  }
  Future<Map<String, Object?>> updateCustomerDirectory({
    required int id,
    required String name,
    required String phone,
    required String note,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('updateCustomerDirectory',{'id':id,'name':name,'phone':phone,'note':note},write:true); final result=Map<String,Object?>.from(value as Map); if(result['items'] is List) result['items']=(result['items'] as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); return result; }
    return _callLocal<Map<String, Object?>>(()=>_localUpdateCustomerDirectory(id: id, name: name, phone: phone, note: note), write:true);
  }
  Future<Map<String, Object?>> addSupplierDirectory({
    required String name,
    required String phone,
    required String address,
    required String note,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('addSupplierDirectory',{'name':name,'phone':phone,'address':address,'note':note},write:true); final result=Map<String,Object?>.from(value as Map); if(result['items'] is List) result['items']=(result['items'] as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); return result; }
    return _callLocal<Map<String, Object?>>(()=>_localAddSupplierDirectory(name: name, phone: phone, address: address, note: note), write:true);
  }
  Future<Map<String, Object?>> updateSupplierDirectory({
    required int id,
    required String name,
    required String phone,
    required String address,
    required String note,
  }) async {
    if(kIsWeb) { final value=await remoteBridge.call('updateSupplierDirectory',{'id':id,'name':name,'phone':phone,'address':address,'note':note},write:true); final result=Map<String,Object?>.from(value as Map); if(result['items'] is List) result['items']=(result['items'] as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); return result; }
    return _callLocal<Map<String, Object?>>(()=>_localUpdateSupplierDirectory(id: id, name: name, phone: phone, address: address, note: note), write:true);
  }
  Future<List<Map<String, Object?>>> customers() async {
    if(kIsWeb) { final value=await remoteBridge.call('customers',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localCustomers(), write:false);
  }
  Future<List<Map<String, Object?>>> customerSales(
    String name,
    String phone,
  ) async {
    if(kIsWeb) { final value=await remoteBridge.call('customerSales',{'name':name,'phone':phone},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localCustomerSales(name, phone), write:false);
  }
  Future<List<Map<String, Object?>>> customerRepairs(
    String name,
    String phone,
  ) async {
    if(kIsWeb) { final value=await remoteBridge.call('customerRepairs',{'name':name,'phone':phone},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localCustomerRepairs(name, phone), write:false);
  }
  Future<List<Map<String, Object?>>> suppliers() async {
    if(kIsWeb) { final value=await remoteBridge.call('suppliers',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localSuppliers(), write:false);
  }
  Future<List<Map<String, Object?>>> supplierPurchases(String name) async {
    if(kIsWeb) { final value=await remoteBridge.call('supplierPurchases',{'name':name},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localSupplierPurchases(name), write:false);
  }
  Future<List<Map<String, Object?>>> debtAdjustments(
    String partyType,
    int partyId,
  ) async {
    if(kIsWeb) { final value=await remoteBridge.call('debtAdjustments',{'partyType':partyType,'partyId':partyId},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localDebtAdjustments(partyType, partyId), write:false);
  }
  Future<void> addDebtAdjustment({
    required String partyType,
    required int partyId,
    required int amount,
    required bool increase,
    required int currentDebt,
    required String note,
    bool isPayment=false, String paymentMethod='cash', String? occurredAt,
  }) async {
    if(kIsWeb) { await remoteBridge.call('addDebtAdjustment',{'partyType':partyType,'partyId':partyId,'amount':amount,'increase':increase,'currentDebt':currentDebt,'note':note,'isPayment':isPayment,'paymentMethod':paymentMethod,'occurredAt':occurredAt},write:true); return; }
    return _callLocal<void>(()=>_localAddDebtAdjustment(partyType: partyType, partyId: partyId, amount: amount, increase: increase, currentDebt: currentDebt, note: note,isPayment:isPayment,paymentMethod:paymentMethod,occurredAt:occurredAt), write:true);
  }
  Future<List<Map<String, Object?>>> repairs() async {
    if(kIsWeb) { final value=await remoteBridge.call('repairs',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localRepairs(), write:false);
  }
  Future<void> addRepair({
    required String customer,
    required String phone,
    required String device,
    required String imei,
    required String issue,
    required int amount,
    required int partsCost,
    required int paid,
    required String note,
  }) async {
    if(kIsWeb) { await remoteBridge.call('addRepair',{'customer':customer,'phone':phone,'device':device,'imei':imei,'issue':issue,'amount':amount,'partsCost':partsCost,'paid':paid,'note':note},write:true); return; }
    return _callLocal<void>(()=>_localAddRepair(customer: customer, phone: phone, device: device, imei: imei, issue: issue, amount: amount, partsCost: partsCost, paid: paid, note: note), write:true);
  }
  Future<void> updateRepairStatus(int id, String status) async {
    if(kIsWeb) { await remoteBridge.call('updateRepairStatus',{'id':id,'status':status},write:true); return; }
    return _callLocal<void>(()=>_localUpdateRepairStatus(id, status), write:true);
  }
  Future<Map<String, Object?>> repair(int id) async {
    if(kIsWeb) { final value=await remoteBridge.call('repair',{'id':id},write:false); final result=Map<String,Object?>.from(value as Map); if(result['items'] is List) result['items']=(result['items'] as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); return result; }
    return _callLocal<Map<String, Object?>>(()=>_localRepair(id), write:false);
  }
  Future<void> updateRepair({
    required int id,
    required String customer,
    required String phone,
    required String device,
    required String imei,
    required String issue,
    required int amount,
    required int partsCost,
    required int paid,
    required String note,
  }) async {
    if(kIsWeb) { await remoteBridge.call('updateRepair',{'id':id,'customer':customer,'phone':phone,'device':device,'imei':imei,'issue':issue,'amount':amount,'partsCost':partsCost,'paid':paid,'note':note},write:true); return; }
    return _callLocal<void>(()=>_localUpdateRepair(id: id, customer: customer, phone: phone, device: device, imei: imei, issue: issue, amount: amount, partsCost: partsCost, paid: paid, note: note), write:true);
  }
  Future<void> deleteRepair(int id) async {
    if(kIsWeb) { await remoteBridge.call('deleteRepair',{'id':id},write:true); return; }
    return _callLocal<void>(()=>_localDeleteRepair(id), write:true);
  }
  Future<List<Map<String, Object?>>> cashEntries() async {
    if(kIsWeb) { final value=await remoteBridge.call('cashEntries',{},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localCashEntries(), write:false);
  }
  Future<void> addCashEntry({
    required String type,
    required String category,
    required int amount,
    required String note,
  }) async {
    if(kIsWeb) { await remoteBridge.call('addCashEntry',{'type':type,'category':category,'amount':amount,'note':note},write:true); return; }
    return _callLocal<void>(()=>_localAddCashEntry(type: type, category: category, amount: amount, note: note), write:true);
  }
  Future<void> deleteCashEntry(int id) async {
    if(kIsWeb) { await remoteBridge.call('deleteCashEntry',{'id':id},write:true); return; }
    return _callLocal<void>(()=>_localDeleteCashEntry(id), write:true);
  }
  Future<void> recordStocktake({
    required Map<String, Object?> product,
    required int actualQuantity,
    required String note,
  }) async {
    if(kIsWeb) { await remoteBridge.call('recordStocktake',{'product':product,'actualQuantity':actualQuantity,'note':note},write:true); return; }
    return _callLocal<void>(()=>_localRecordStocktake(product: product, actualQuantity: actualQuantity, note: note), write:true);
  }
  Future<List<Map<String, Object?>>> stocktakeHistory({int limit = 20}) async {
    if(kIsWeb) { final value=await remoteBridge.call('stocktakeHistory',{'limit':limit},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localStocktakeHistory(limit: limit), write:false);
  }
  Future<void> inventoryAction({
    required Map<String, Object?> product,
    required String kind,
    required int quantity,
    required int? serialId,
  }) async {
    if(kIsWeb) { await remoteBridge.call('inventoryAction',{'product':product,'kind':kind,'quantity':quantity,'serialId':serialId},write:true); return; }
    return _callLocal<void>(()=>_localInventoryAction(product: product, kind: kind, quantity: quantity, serialId: serialId), write:true);
  }
  Future<String> exportBackup() async {
    if(kIsWeb) { final value=await remoteBridge.call('exportBackup',{},write:false); return value as String; }
    return _nestedTransaction((_)=>_localExportBackup());
  }
  Future<void> restoreBackup(String source) async {
    if(kIsWeb) { await remoteBridge.call('restoreBackup',{'source':source},write:true); return; }
    return _callLocal<void>(()=>_localRestoreBackup(source), write:true);
  }
  Future<Map<String, int>> reportSummary(DateTime start, DateTime end) async {
    if(kIsWeb) { final value=await remoteBridge.call('reportSummary',{'start':start.toIso8601String(),'end':end.toIso8601String()},write:false); return (value as Map).map((k,v)=>MapEntry(k as String,(v as num).toInt())); }
    return _callLocal<Map<String, int>>(()=>_localReportSummary(start, end), write:false);
  }
  Future<List<Map<String, Object?>>> productReport(
    DateTime start,
    DateTime end,
  ) async {
    if(kIsWeb) { final value=await remoteBridge.call('productReport',{'start':start.toIso8601String(),'end':end.toIso8601String()},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localProductReport(start, end), write:false);
  }
  Future<List<Map<String, Object?>>> invoiceReport(
    DateTime start,
    DateTime end,
  ) async {
    if(kIsWeb) { final value=await remoteBridge.call('invoiceReport',{'start':start.toIso8601String(),'end':end.toIso8601String()},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localInvoiceReport(start, end), write:false);
  }
  Future<List<Map<String, Object?>>> salesTrend(String mode) async {
    if(kIsWeb) { final value=await remoteBridge.call('salesTrend',{'mode':mode},write:false); return (value as List).map((r)=>Map<String,Object?>.from(r as Map)).toList(); }
    return _callLocal<List<Map<String, Object?>>>(()=>_localSalesTrend(mode), write:false);
  }
  Future<Map<String, int>> dashboard() async {
    if(kIsWeb) { final value=await remoteBridge.call('dashboard',{},write:false); return (value as Map).map((k,v)=>MapEntry(k as String,(v as num).toInt())); }
    return _callLocal<Map<String, int>>(()=>_localDashboard(), write:false);
  }
  static final Object _transactionKey=Object();
  static const writeOperations=<String>{'saveCashEntry','saveRecurringExpense','payRecurringExpense','deleteRecurringExpense','savePurchaseDraft','deletePurchaseDraft','addProductCategory','renameProductCategory','deleteProductCategory','addProductBrand','renameProductBrand','deleteProductBrand','addProduct','updateProduct','setProductActive','deleteProduct','updateSerialUnit','completePurchase','completeMultiPurchase','completeMultiSale','cancelSale','deleteSale','setSetting','addWarrantyClaim','updateWarrantyClaimStatus','updateWarrantyClaim','deleteWarrantyClaim','addCustomerDirectory','updateCustomerDirectory','addSupplierDirectory','updateSupplierDirectory','addDebtAdjustment','addRepair','updateRepairStatus','updateRepair','deleteRepair','addCashEntry','deleteCashEntry','recordStocktake','inventoryAction','restoreBackup'};
  Future<DatabaseExecutor> get _executor async => Zone.current[_transactionKey] as DatabaseExecutor? ?? await database;
  Future<T> _nestedTransaction<T>(Future<T> Function(DatabaseExecutor) body) async {
    final current=Zone.current[_transactionKey] as DatabaseExecutor?;
    if(current!=null)return body(current);
    return (await database).transaction((txn)=>runZoned(()=>body(txn),zoneValues:{_transactionKey:txn}));
  }
  Future<void> _createV8Tables(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS lan_revision(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)');
    await db.execute('INSERT OR IGNORE INTO lan_revision(id,value) VALUES(1,0)');
    await db.execute('CREATE TABLE IF NOT EXISTS lan_requests(request_id TEXT PRIMARY KEY, payload_hash TEXT NOT NULL, result TEXT NOT NULL, revision INTEGER NOT NULL)');
  }
  Future<T> _callLocal<T>(Future<T> Function() body,{required bool write}) async {
    if(!write || Zone.current[_transactionKey]!=null)return body();
    return _nestedTransaction((txn) async {
      if(_nativeStale)throw StateError('Dữ liệu đã đổi trên máy tính. Quay về màn hình chính và bấm Tải lại dữ liệu trước khi lưu.');
      final value=await body();
      await txn.execute('UPDATE lan_revision SET value=value+1 WHERE id=1');
      return value;
    });
  }
  Future<Map<String,Object?>> executeRemote(Map<String,Object?> request) async {
    if(request['protocol']!=null&&request['protocol']!=2)throw StateError('Phiên bản máy tính không tương thích. Tải lại trang từ điện thoại đã nâng cấp.');
    final operation=request['operation'] as String? ?? '';
    final args=Map<String,Object?>.from(request['arguments'] as Map? ?? {});
    if(['getSetting','setSetting'].contains(operation)) {
      const allowed={'payment_bank_bin','payment_bank_name','payment_account_number','payment_account_name','label_show_price','printer_transport','printer_copies','printer_bluetooth_mac','printer_bluetooth_name','printer_lan_ip','printer_lan_port','label_printer_bluetooth_mac','label_printer_bluetooth_name'};
      if(!allowed.contains(args['key']))throw StateError('Cài đặt này chỉ thay đổi trên điện thoại');
    }
    final write=writeOperations.contains(operation);
    final requestId=request['requestId'] as String? ?? '';
    if(write && !RegExp(r'^[a-zA-Z0-9_-]{16,100}$').hasMatch(requestId))throw ArgumentError('Mã giao dịch không hợp lệ');
    final hash=sha256.convert(utf8.encode(jsonEncode([operation,args]))).toString();
    var changed=false;
    final response=await _nestedTransaction((txn) async {
      final revision=(await txn.query('lan_revision',where:'id=1')).single['value'] as int;
      if(write) {
        final old=await txn.query('lan_requests',where:'request_id=?',whereArgs:[requestId]);
        if(old.isNotEmpty){
          if(old.single['payload_hash']!=hash)throw StateError('Mã giao dịch đã dùng cho nội dung khác');
          return {'value':jsonDecode(old.single['result'] as String),'revision':revision};
        }
        if(request['revision']!=revision)throw StateError('Dữ liệu đã thay đổi. Hãy tải lại trước khi lưu.');
      }
      Object? value;
      if(operation=='exportBackup') {
        final backup=jsonDecode(await _localExportBackup()) as Map<String,dynamic>;
        backup['app_settings']=(backup['app_settings'] as List).where((r)=>!['pin','biometric_enabled'].contains(r['setting_key'])).toList();
        value=jsonEncode(backup);
      } else if(operation=='restoreBackup') {
        final backup=jsonDecode(args['source'] as String) as Map<String,dynamic>;
        final secure=await txn.query('app_settings',where:'setting_key IN (?, ?)',whereArgs:['pin','biometric_enabled']);
        backup['app_settings']=[...(backup['app_settings'] as List? ?? []).where((r)=>!['pin','biometric_enabled'].contains(r['setting_key'])),...secure];
        await _localRestoreBackup(jsonEncode(backup));
        value=null;
      } else {
        value=await _dispatch(operation,args);
      }
      if(write){
        await txn.execute('UPDATE lan_revision SET value=value+1 WHERE id=1');
        await txn.insert('lan_requests',{'request_id':requestId,'payload_hash':hash,'result':jsonEncode(value),'revision':revision+1});
        changed=true;
        _nativeStale=true;
      }
      return {'value':value,'revision':revision+(write?1:0)};
    });
    if(changed)remoteChanges.value++;
    return response;
  }
  Future<Object?> _dispatch(String operation,Map<String,Object?> args) async {
    switch(operation){
      case 'productCategories': return productCategories();
case 'addProductCategory': return addProductCategory((args['rawName'] as String), parentId: (args['parentId'] as int?));
case 'renameProductCategory': await renameProductCategory((args['id'] as int), (args['rawName'] as String)); return null;
case 'deleteProductCategory': await deleteProductCategory((args['id'] as int)); return null;
case 'productBrands': return productBrands();
case 'addProductBrand': return addProductBrand((args['rawName'] as String));
case 'renameProductBrand': await renameProductBrand((args['id'] as int), (args['rawName'] as String)); return null;
case 'deleteProductBrand': await deleteProductBrand((args['id'] as int)); return null;
case 'nextProductCode': return nextProductCode();
case 'products': return products(includeInactive: (args['includeInactive'] as bool?) ?? false);
case 'product': return product((args['id'] as int));
case 'addProduct': return addProduct(Map<String,Object?>.from(args['row'] as Map));
case 'updateProduct': await updateProduct(id: (args['id'] as int), code: (args['code'] as String), name: (args['name'] as String), category: (args['category'] as String), brand: (args['brand'] as String), capacity: (args['capacity'] as String), salePrice: (args['salePrice'] as int), averageCost: (args['averageCost'] as int?)); return null;
case 'setProductActive': await setProductActive((args['id'] as int), (args['active'] as bool)); return null;
case 'deleteProduct': await deleteProduct((args['id'] as int)); return null;
case 'serials': return serials((args['productId'] as int), status: (args['status'] as String?));
case 'serialExists': return serialExists((args['imei'] as String));
case 'updateSerialUnit': await updateSerialUnit(id: (args['id'] as int), imei: (args['imei'] as String), color: (args['color'] as String), conditionText: (args['conditionText'] as String), cost: (args['cost'] as int)); return null;
case 'completePurchase': return completePurchase(productId: (args['productId'] as int), quantity: (args['quantity'] as int), unitCost: (args['unitCost'] as int), supplier: (args['supplier'] as String), paid: (args['paid'] as int), paymentMethod: (args['paymentMethod'] as String), serials: (args['serials'] as List).map((v)=>_decodeSerialDraft(Map<String,Object?>.from(v as Map))).toList());
case 'savePurchaseDraft': return savePurchaseDraft(id:args['id'] as int?,payload:Map<String,Object?>.from(args['payload'] as Map));
case 'purchaseDrafts': return purchaseDrafts();
case 'purchaseDraft': return purchaseDraft(args['id'] as int);
case 'deletePurchaseDraft': await deletePurchaseDraft(args['id'] as int); return null;
case 'completeMultiPurchase': return completeMultiPurchase(items: (args['items'] as List).map((v)=>_decodePurchaseLineDraft(Map<String,Object?>.from(v as Map))).toList(), supplier: (args['supplier'] as String), paid: (args['paid'] as int), paymentMethod: (args['paymentMethod'] as String), draftId:args['draftId'] as int?, completionKey:args['completionKey'] as String?);
case 'completeMultiSale': return completeMultiSale(invoiceCode: (args['invoiceCode'] as String), items: (args['items'] as List).map((v)=>_decodeSaleLineDraft(Map<String,Object?>.from(v as Map))).toList(), customer: (args['customer'] as String), phone: (args['phone'] as String), cash: (args['cash'] as int), transfer: (args['transfer'] as int), warrantyMonths: (args['warrantyMonths'] as int));
case 'sales': return sales();
case 'cancelSale': await cancelSale((args['saleId'] as int)); return null;
case 'deleteSale': await deleteSale((args['saleId'] as int)); return null;
case 'getSetting': return getSetting((args['key'] as String));
case 'setSetting': await setSetting((args['key'] as String), (args['value'] as String)); return null;
case 'saleDetail': return saleDetail((args['saleId'] as int));
case 'warranties': return warranties();
case 'warrantyClaims': return warrantyClaims((args['saleItemId'] as int));
case 'addWarrantyClaim': await addWarrantyClaim(saleItemId: (args['saleItemId'] as int), issue: (args['issue'] as String), note: (args['note'] as String)); return null;
case 'updateWarrantyClaimStatus': await updateWarrantyClaimStatus((args['id'] as int), (args['status'] as String)); return null;
case 'updateWarrantyClaim': await updateWarrantyClaim(id: (args['id'] as int), issue: (args['issue'] as String), note: (args['note'] as String), status: (args['status'] as String)); return null;
case 'deleteWarrantyClaim': await deleteWarrantyClaim((args['id'] as int)); return null;
case 'customerDirectory': return customerDirectory();
case 'supplierDirectory': return supplierDirectory();
case 'addCustomerDirectory': return addCustomerDirectory(name: (args['name'] as String), phone: (args['phone'] as String), note: (args['note'] as String));
case 'updateCustomerDirectory': return updateCustomerDirectory(id: (args['id'] as int), name: (args['name'] as String), phone: (args['phone'] as String), note: (args['note'] as String));
case 'addSupplierDirectory': return addSupplierDirectory(name: (args['name'] as String), phone: (args['phone'] as String), address: (args['address'] as String), note: (args['note'] as String));
case 'updateSupplierDirectory': return updateSupplierDirectory(id: (args['id'] as int), name: (args['name'] as String), phone: (args['phone'] as String), address: (args['address'] as String), note: (args['note'] as String));
case 'customers': return customers();
case 'customerSales': return customerSales((args['name'] as String), (args['phone'] as String));
case 'customerRepairs': return customerRepairs((args['name'] as String), (args['phone'] as String));
case 'suppliers': return suppliers();
case 'supplierPurchases': return supplierPurchases((args['name'] as String));
case 'debtAdjustments': return debtAdjustments((args['partyType'] as String), (args['partyId'] as int));
case 'addDebtAdjustment': await addDebtAdjustment(partyType: (args['partyType'] as String), partyId: (args['partyId'] as int), amount: (args['amount'] as int), increase: (args['increase'] as bool), currentDebt: (args['currentDebt'] as int), note: (args['note'] as String),isPayment:args['isPayment'] as bool? ?? false,paymentMethod:args['paymentMethod'] as String? ?? 'cash',occurredAt:args['occurredAt'] as String?); return null;
case 'repairs': return repairs();
case 'addRepair': await addRepair(customer: (args['customer'] as String), phone: (args['phone'] as String), device: (args['device'] as String), imei: (args['imei'] as String), issue: (args['issue'] as String), amount: (args['amount'] as int), partsCost: (args['partsCost'] as int), paid: (args['paid'] as int), note: (args['note'] as String)); return null;
case 'updateRepairStatus': await updateRepairStatus((args['id'] as int), (args['status'] as String)); return null;
case 'repair': return repair((args['id'] as int));
case 'updateRepair': await updateRepair(id: (args['id'] as int), customer: (args['customer'] as String), phone: (args['phone'] as String), device: (args['device'] as String), imei: (args['imei'] as String), issue: (args['issue'] as String), amount: (args['amount'] as int), partsCost: (args['partsCost'] as int), paid: (args['paid'] as int), note: (args['note'] as String)); return null;
case 'deleteRepair': await deleteRepair((args['id'] as int)); return null;
case 'saveCashEntry': return saveCashEntry(id:args['id'] as int?,type:args['type'] as String,scope:args['scope'] as String,category:args['category'] as String,amount:args['amount'] as int,note:args['note'] as String,paymentMethod:args['paymentMethod'] as String,occurredAt:args['occurredAt'] as String);
case 'financeLedger': return financeLedger(DateTime.parse(args['from'] as String),DateTime.parse(args['to'] as String));
case 'financeSummary': return financeSummary(DateTime.parse(args['from'] as String),DateTime.parse(args['to'] as String));
case 'saveRecurringExpense': return saveRecurringExpense(id:args['id'] as int?,payload:Map<String,Object?>.from(args['payload'] as Map));
case 'recurringExpenses': return recurringExpenses(args['year'] as int,args['month'] as int);
case 'payRecurringExpense': return payRecurringExpense(args['id'] as int,args['year'] as int,args['month'] as int,args['paymentMethod'] as String,args['occurredAt'] as String);
case 'deleteRecurringExpense': await deleteRecurringExpense(args['id'] as int);return null;
case 'cashEntries': return cashEntries();
case 'addCashEntry': await addCashEntry(type: (args['type'] as String), category: (args['category'] as String), amount: (args['amount'] as int), note: (args['note'] as String)); return null;
case 'deleteCashEntry': await deleteCashEntry((args['id'] as int)); return null;
case 'recordStocktake': await recordStocktake(product: Map<String,Object?>.from(args['product'] as Map), actualQuantity: (args['actualQuantity'] as int), note: (args['note'] as String)); return null;
case 'stocktakeHistory': return stocktakeHistory(limit: (args['limit'] as int?) ?? 20);
case 'inventoryAction': await inventoryAction(product: Map<String,Object?>.from(args['product'] as Map), kind: (args['kind'] as String), quantity: (args['quantity'] as int), serialId: (args['serialId'] as int?)); return null;
case 'exportBackup': return exportBackup();
case 'restoreBackup': await restoreBackup((args['source'] as String)); return null;
case 'reportSummary': return reportSummary(DateTime.parse(args['start'] as String), DateTime.parse(args['end'] as String));
case 'productReport': return productReport(DateTime.parse(args['start'] as String), DateTime.parse(args['end'] as String));
case 'invoiceReport': return invoiceReport(DateTime.parse(args['start'] as String), DateTime.parse(args['end'] as String));
case 'salesTrend': return salesTrend((args['mode'] as String));
case 'dashboard': return dashboard();
      default: throw ArgumentError('Chức năng không hợp lệ');
    }
  }
}
