import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StoreDb.instance.database;
  runApp(const MinhCanhApp());
}

final money = NumberFormat.decimalPattern('vi_VN');
String vnd(num value) => '${money.format(value)} đ';

class MinhCanhApp extends StatelessWidget {
  const MinhCanhApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Minh Cảnh Mobile',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0877d1)),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff3f6fa),
          cardTheme: const CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        home: const PinGate(),
      );
}

class StoreDb {
  StoreDb._();
  static final instance = StoreDb._();
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final file = p.join(await getDatabasesPath(), 'minh_canh_mobile_v3.db');
    return openDatabase(file, version: 2, onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    }, onCreate: (db, version) async {
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
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await _createV2Tables(db);
    });
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

  Future<List<Map<String, Object?>>> products() async {
    final db = await database;
    return db.rawQuery('''SELECT p.*,
      CASE WHEN p.track_imei=1 THEN
        (SELECT COUNT(*) FROM serial_units s WHERE s.product_id=p.id AND s.status='in_stock')
      ELSE p.quantity END AS stock,
      (SELECT GROUP_CONCAT(s.imei, ' ') FROM serial_units s
       WHERE s.product_id=p.id) AS imeis
      FROM products p WHERE p.active=1 ORDER BY p.id DESC''');
  }

  Future<int> addProduct(Map<String, Object?> row) async {
    final db = await database;
    return db.insert('products', row);
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    final used = Sqflite.firstIntValue(await db.rawQuery(
          '''SELECT (SELECT COUNT(*) FROM purchase_items WHERE product_id=?) +
          (SELECT COUNT(*) FROM sale_items WHERE product_id=?)''',
          [id, id],
        )) ??
        0;
    if (used > 0) throw Exception('Hàng đã có giao dịch, chỉ có thể ngừng kinh doanh');
    await db.delete('products', where: 'id=?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> serials(int productId,
      {String? status}) async {
    final db = await database;
    return db.query('serial_units',
        where: status == null ? 'product_id=?' : 'product_id=? AND status=?',
        whereArgs: status == null ? [productId] : [productId, status],
        orderBy: 'id DESC');
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
    final db = await database;
    return db.transaction((txn) async {
      final product = (await txn.query('products', where: 'id=?', whereArgs: [productId])).single;
      final tracks = product['track_imei'] == 1;
      if (quantity <= 0) throw Exception('Số lượng phải lớn hơn 0');
      if (tracks && serials.length != quantity) {
        throw Exception('Số IMEI phải đúng bằng số lượng nhập');
      }
      final now = DateTime.now().toIso8601String();
      final code = 'PN${DateTime.now().millisecondsSinceEpoch}';
      final purchaseTotal = tracks
          ? serials.fold<int>(0, (sum, serial) => sum + serial.cost)
          : quantity * unitCost;
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
        'unit_cost': tracks && quantity > 0 ? (purchaseTotal / quantity).round() : unitCost,
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
        await txn.update('products', {'quantity': newQty, 'avg_cost': newCost},
            where: 'id=?', whereArgs: [productId]);
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

  Future<int> completeSale({
    required Map<String, Object?> product,
    required int quantity,
    required int? serialId,
    required int unitPrice,
    required String customer,
    required String phone,
    required int cash,
    required int transfer,
    required int warrantyMonths,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final productId = product['id'] as int;
      final tracks = product['track_imei'] == 1;
      var cost = 0;
      if (tracks) {
        if (serialId == null) throw Exception('Phải chọn IMEI');
        final serialRows = await txn.query('serial_units',
            where: "id=? AND product_id=? AND status='in_stock'",
            whereArgs: [serialId, productId]);
        if (serialRows.isEmpty) throw Exception('IMEI không còn trong kho');
        cost = serialRows.single['cost'] as int;
      } else {
        final fresh = (await txn.query('products', where: 'id=?', whereArgs: [productId])).single;
        final stock = fresh['quantity'] as int;
        if (quantity <= 0 || quantity > stock) throw Exception('Số lượng bán vượt tồn kho');
        cost = (fresh['avg_cost'] as int) * quantity;
      }
      final total = unitPrice * (tracks ? 1 : quantity);
      if (unitPrice <= 0) throw Exception('Giá bán phải lớn hơn 0');
      if (cash < 0 || transfer < 0 || cash + transfer > total) {
        throw Exception('Số tiền thanh toán không hợp lệ');
      }
      final now = DateTime.now().toIso8601String();
      final saleId = await txn.insert('sales', {
        'code': 'HD${DateTime.now().millisecondsSinceEpoch}',
        'customer': customer.trim().isEmpty ? 'Khách lẻ' : customer.trim(),
        'phone': phone.trim(),
        'total': total,
        'cost_total': cost,
        'paid_cash': cash,
        'paid_transfer': transfer,
        'debt': total - cash - transfer,
        'warranty_months': warrantyMonths,
        'created_at': now,
      });
      await txn.insert('sale_items', {
        'sale_id': saleId,
        'product_id': productId,
        'serial_id': serialId,
        'quantity': tracks ? 1 : quantity,
        'unit_price': unitPrice,
        'unit_cost': tracks ? cost : (product['avg_cost'] as int),
      });
      if (tracks) {
        await txn.update('serial_units', {'status': 'sold'},
            where: 'id=?', whereArgs: [serialId]);
      } else {
        await txn.rawUpdate('UPDATE products SET quantity=quantity-? WHERE id=?',
            [quantity, productId]);
      }
      await txn.insert('inventory_movements', {
        'product_id': productId,
        'serial_id': serialId,
        'kind': 'sale',
        'quantity_delta': tracks ? -1 : -quantity,
        'reference_type': 'sale',
        'reference_id': saleId,
        'created_at': now,
      });
      return saleId;
    });
  }

  Future<List<Map<String, Object?>>> sales() async {
    final db = await database;
    return db.rawQuery('''SELECT s.*,
      GROUP_CONCAT(p.name, ' • ') product_names,
      GROUP_CONCAT(COALESCE(su.imei, ''), ' ') imeis
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id=s.id
      LEFT JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      GROUP BY s.id ORDER BY s.id DESC''');
  }

  Future<void> cancelSale(int saleId) async {
    final db = await database;
    await db.transaction((txn) async {
      final sale = (await txn.query('sales', where: 'id=?', whereArgs: [saleId])).single;
      if (sale['status'] == 'cancelled') return;
      final items = await txn.query('sale_items', where: 'sale_id=?', whereArgs: [saleId]);
      final now = DateTime.now().toIso8601String();
      for (final item in items) {
        final productId = item['product_id'] as int;
        final serialId = item['serial_id'] as int?;
        final qty = item['quantity'] as int;
        if (serialId != null) {
          await txn.update('serial_units', {'status': 'in_stock'},
              where: 'id=?', whereArgs: [serialId]);
        } else {
          await txn.rawUpdate('UPDATE products SET quantity=quantity+? WHERE id=?',
              [qty, productId]);
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
      await txn.update('sales', {'status': 'cancelled'},
          where: 'id=?', whereArgs: [saleId]);
    });
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('app_settings',
        columns: ['setting_value'], where: 'setting_key=?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.single['setting_value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings',
        {'setting_key': key, 'setting_value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>> saleDetail(int saleId) async {
    final db = await database;
    final sale = (await db.query('sales', where: 'id=?', whereArgs: [saleId])).single;
    final items = await db.rawQuery('''SELECT si.*, p.name product_name,
      p.code product_code, su.imei, su.color
      FROM sale_items si
      JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      WHERE si.sale_id=? ORDER BY si.id''', [saleId]);
    return {'sale': sale, 'items': items};
  }

  Future<List<Map<String, Object?>>> warranties() async {
    final db = await database;
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
      WHERE s.status='completed'
      ORDER BY s.created_at DESC''');
  }

  Future<List<Map<String, Object?>>> warrantyClaims(int saleItemId) async {
    final db = await database;
    return db.query('warranty_claims', where: 'sale_item_id=?',
        whereArgs: [saleItemId], orderBy: 'id DESC');
  }

  Future<void> addWarrantyClaim({
    required int saleItemId,
    required String issue,
    required String note,
  }) async {
    if (issue.trim().isEmpty) throw Exception('Hãy nhập tình trạng bảo hành');
    final db = await database;
    await db.insert('warranty_claims', {
      'sale_item_id': saleItemId,
      'issue': issue.trim(),
      'note': note.trim(),
      'status': 'received',
      'received_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateWarrantyClaimStatus(int id, String status) async {
    final db = await database;
    await db.update('warranty_claims', {
      'status': status,
      'resolved_at': status == 'returned' ? DateTime.now().toIso8601String() : null,
    }, where: 'id=?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> customers() async {
    final db = await database;
    return db.rawQuery('''SELECT customer, phone,
      SUM(sale_count) invoice_count, COUNT(*) transaction_count,
      SUM(total_value) total_spent, SUM(debt_value) debt,
      MAX(activity_at) last_purchase
      FROM (
        SELECT customer, phone, 1 sale_count, total total_value,
          debt debt_value, created_at activity_at
        FROM sales WHERE status='completed'
        UNION ALL
        SELECT customer, phone, 0 sale_count, amount total_value,
          amount-paid debt_value, received_at activity_at
        FROM repairs WHERE status!='cancelled'
      ) activity
      GROUP BY customer, phone ORDER BY last_purchase DESC''');
  }

  Future<List<Map<String, Object?>>> suppliers() async {
    final db = await database;
    return db.rawQuery('''SELECT CASE WHEN TRIM(supplier)='' THEN 'Không ghi tên'
      ELSE supplier END supplier_name, COUNT(*) purchase_count,
      SUM(total) total_purchase, SUM(total-paid) debt,
      MAX(created_at) last_purchase
      FROM purchases WHERE status='completed'
      GROUP BY supplier ORDER BY last_purchase DESC''');
  }

  Future<List<Map<String, Object?>>> repairs() async {
    final db = await database;
    return db.query('repairs', orderBy: 'id DESC');
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
    if (device.trim().isEmpty || issue.trim().isEmpty) {
      throw Exception('Hãy nhập tên máy và tình trạng lỗi');
    }
    if (amount < 0 || partsCost < 0 || paid < 0 || paid > amount) {
      throw Exception('Số tiền phiếu sửa chữa không hợp lệ');
    }
    final db = await database;
    final now = DateTime.now();
    await db.insert('repairs', {
      'code': 'SC${now.millisecondsSinceEpoch}',
      'customer': customer.trim().isEmpty ? 'Khách lẻ' : customer.trim(),
      'phone': phone.trim(),
      'device': device.trim(),
      'imei': imei.trim(),
      'issue': issue.trim(),
      'amount': amount,
      'parts_cost': partsCost,
      'paid': paid,
      'status': 'received',
      'note': note.trim(),
      'received_at': now.toIso8601String(),
    });
  }

  Future<void> updateRepairStatus(int id, String status) async {
    final db = await database;
    await db.update('repairs', {
      'status': status,
      'completed_at': status == 'completed' || status == 'returned'
          ? DateTime.now().toIso8601String() : null,
    }, where: 'id=?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> cashEntries() async {
    final db = await database;
    return db.query('cash_entries', orderBy: 'id DESC');
  }

  Future<void> addCashEntry({
    required String type,
    required String category,
    required int amount,
    required String note,
  }) async {
    if (amount <= 0) throw Exception('Số tiền phải lớn hơn 0');
    final db = await database;
    await db.insert('cash_entries', {
      'entry_type': type,
      'category': category.trim().isEmpty ? (type == 'income' ? 'Thu khác' : 'Chi khác') : category.trim(),
      'amount': amount,
      'note': note.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteCashEntry(int id) async {
    final db = await database;
    await db.delete('cash_entries', where: 'id=?', whereArgs: [id]);
  }

  Future<void> recordStocktake({
    required Map<String, Object?> product,
    required int actualQuantity,
    required String note,
  }) async {
    if (actualQuantity < 0) throw Exception('Số lượng thực tế không hợp lệ');
    final db = await database;
    await db.transaction((txn) async {
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
        await txn.update('products', {'quantity': actualQuantity},
            where: 'id=?', whereArgs: [product['id']]);
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

  Future<List<Map<String, Object?>>> stocktakeHistory({int limit = 20}) async {
    final db = await database;
    return db.rawQuery('''SELECT st.*, p.name product_name, p.track_imei
      FROM stocktakes st JOIN products p ON p.id=st.product_id
      ORDER BY st.id DESC LIMIT ?''', [limit]);
  }

  Future<void> inventoryAction({
    required Map<String, Object?> product,
    required String kind,
    required int quantity,
    required int? serialId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now();
      final referenceId = now.millisecondsSinceEpoch;
      final tracks = product['track_imei'] == 1;
      if (tracks) {
        if (serialId == null) throw Exception('Hãy chọn IMEI');
        final targetStatus = kind == 'supplier_return' ? 'returned_supplier' : 'discarded';
        final changed = await txn.update('serial_units', {'status': targetStatus},
            where: "id=? AND status='in_stock'", whereArgs: [serialId]);
        if (changed != 1) throw Exception('IMEI không còn trong kho');
      } else {
        final fresh = (await txn.query('products', where: 'id=?',
            whereArgs: [product['id']])).single;
        final stock = fresh['quantity'] as int;
        if (quantity <= 0 || quantity > stock) {
          throw Exception('Số lượng vượt quá tồn kho');
        }
        await txn.rawUpdate('UPDATE products SET quantity=quantity-? WHERE id=?',
            [quantity, product['id']]);
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

  Future<String> exportBackup() async {
    final db = await database;
    const tables = [
      'products', 'purchases', 'serial_units', 'purchase_items', 'sales',
      'sale_items', 'inventory_movements', 'repairs', 'warranty_claims',
      'cash_entries', 'stocktakes', 'app_settings'
    ];
    final data = <String, Object?>{
      'app': 'MinhCanhMobileV3',
      'backup_version': 2,
      'created_at': DateTime.now().toIso8601String(),
    };
    for (final table in tables) {
      data[table] = await db.query(table);
    }
    return jsonEncode(data);
  }

  Future<void> restoreBackup(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map || decoded['app'] != 'MinhCanhMobileV3') {
      throw Exception('Nội dung sao lưu không đúng của Minh Cảnh Mobile V3');
    }
    const deleteOrder = [
      'warranty_claims', 'stocktakes', 'cash_entries', 'repairs',
      'inventory_movements', 'sale_items', 'sales', 'purchase_items',
      'serial_units', 'purchases', 'products', 'app_settings'
    ];
    const insertOrder = [
      'products', 'purchases', 'serial_units', 'purchase_items', 'sales',
      'sale_items', 'inventory_movements', 'repairs', 'warranty_claims',
      'cash_entries', 'stocktakes', 'app_settings'
    ];
    final db = await database;
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        for (final table in deleteOrder) {
          await txn.delete(table);
        }
        for (final table in insertOrder) {
          final rows = decoded[table];
          if (rows is! List) continue;
          for (final raw in rows) {
            if (raw is Map) {
              await txn.insert(table, Map<String, Object?>.from(raw),
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<Map<String, int>> reportSummary(DateTime start, DateTime end) async {
    final db = await database;
    final from = start.toIso8601String();
    final to = end.toIso8601String();
    final sale = (await db.rawQuery('''SELECT
      COALESCE(SUM(total),0) revenue,
      COALESCE(SUM(total-cost_total),0) gross_profit,
      COALESCE(SUM(debt),0) debt,
      COALESCE(SUM(paid_cash+paid_transfer),0) collected,
      COUNT(*) invoices
      FROM sales
      WHERE status='completed' AND created_at>=? AND created_at<?''',
      [from, to])).single;
    final sold = (await db.rawQuery('''SELECT
      COALESCE(SUM(si.quantity),0) products_sold
      FROM sale_items si
      JOIN sales s ON s.id=si.sale_id
      WHERE s.status='completed' AND s.created_at>=? AND s.created_at<?''',
      [from, to])).single;
    final repair = (await db.rawQuery('''SELECT
      COALESCE(SUM(amount),0) revenue,
      COALESCE(SUM(amount-parts_cost),0) gross_profit,
      COUNT(*) repairs
      FROM repairs
      WHERE status IN ('completed','returned')
        AND COALESCE(completed_at,received_at)>=?
        AND COALESCE(completed_at,received_at)<?''', [from, to])).single;
    final cash = (await db.rawQuery('''SELECT
      COALESCE(SUM(CASE WHEN entry_type='income' THEN amount ELSE 0 END),0) other_income,
      COALESCE(SUM(CASE WHEN entry_type='expense' THEN amount ELSE 0 END),0) expenses
      FROM cash_entries
      WHERE created_at>=? AND created_at<?''', [from, to])).single;
    int n(Map<String, Object?> row, String key) =>
        (row[key] as num? ?? 0).toInt();
    final salesRevenue = n(sale, 'revenue');
    final repairRevenue = n(repair, 'revenue');
    final grossProfit =
        n(sale, 'gross_profit') + n(repair, 'gross_profit');
    final otherIncome = n(cash, 'other_income');
    final expenses = n(cash, 'expenses');
    return {
      'revenue': salesRevenue + repairRevenue,
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

  Future<List<Map<String, Object?>>> productReport(
      DateTime start, DateTime end) async {
    final db = await database;
    return db.rawQuery('''SELECT p.id, p.code, p.name, p.category,
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
      WHERE p.active=1
      ORDER BY revenue DESC, p.name''',
      [start.toIso8601String(), end.toIso8601String()]);
  }

  Future<List<Map<String, Object?>>> invoiceReport(
      DateTime start, DateTime end) async {
    final db = await database;
    return db.rawQuery('''SELECT s.*, s.total-s.cost_total profit,
      GROUP_CONCAT(p.name, ' • ') product_names,
      GROUP_CONCAT(COALESCE(su.imei, ''), ' ') imeis
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id=s.id
      LEFT JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      WHERE s.status='completed' AND s.created_at>=? AND s.created_at<?
      GROUP BY s.id ORDER BY s.created_at DESC''',
      [start.toIso8601String(), end.toIso8601String()]);
  }

  Future<Map<String, int>> dashboard() async {
    final db = await database;
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
    final cashRows = await db.rawQuery('''SELECT
      COALESCE(SUM(CASE WHEN entry_type='income' THEN amount ELSE 0 END),0) income,
      COALESCE(SUM(CASE WHEN entry_type='expense' THEN amount ELSE 0 END),0) expense
      FROM cash_entries''');
    final stockRows = await db.rawQuery('''SELECT
      COALESCE((SELECT SUM(quantity*avg_cost) FROM products WHERE track_imei=0),0) +
      COALESCE((SELECT SUM(cost) FROM serial_units WHERE status='in_stock'),0) stock_value''');
    int n(Map<String, Object?> row, String key) => (row[key] as num? ?? 0).toInt();
    final sale = salesRows.single;
    final repair = repairRows.single;
    final cash = cashRows.single;
    return {
      'revenue': n(sale, 'revenue') + n(repair, 'revenue'),
      'profit': n(sale, 'profit') + n(repair, 'profit'),
      'debt': n(sale, 'debt') + n(repair, 'debt'),
      'fund': n(sale, 'fund') + n(repair, 'fund') + n(cash, 'income') - n(cash, 'expense'),
      'invoices': n(sale, 'invoices'),
      'pending_repairs': n(repair, 'pending'),
      'stock_value': n(stockRows.single, 'stock_value'),
    };
  }
}

class SerialDraft {
  SerialDraft({this.imei = '', this.color = '', this.conditionText = 'Mới', this.cost = 0});
  String imei;
  String color;
  String conditionText;
  int cost;
}

class PinGate extends StatefulWidget {
  const PinGate({super.key});
  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  String? savedPin;
  bool loading = true;
  bool unlocked = false;
  bool hiding = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    savedPin = await StoreDb.instance.getSetting('pin');
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (unlocked) return const HomeShell();
    final creating = savedPin == null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.phone_android, size: 68, color: Color(0xff0877d1)),
                const SizedBox(height: 14),
                const Text('Minh Cảnh Mobile', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                        color: Color(0xff0877d1))),
                const Text('Uy tín dẫn đầu – Chất lượng bền lâu',
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                Text(creating ? 'Tạo mã PIN lần đầu' : 'Nhập mã PIN',
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(creating
                    ? 'Mã PIN gồm 4–6 số, dùng để bảo vệ dữ liệu cửa hàng trên máy này.'
                    : 'Nhập mã PIN để mở ứng dụng.'),
                const SizedBox(height: 18),
                TextField(
                  controller: pin,
                  obscureText: hiding,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Mã PIN',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(hiding ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => hiding = !hiding),
                    ),
                  ),
                  onSubmitted: (_) { if (!creating) _unlock(); },
                ),
                if (creating) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPin,
                    obscureText: hiding,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: 'Nhập lại mã PIN', prefixIcon: Icon(Icons.lock_reset)),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: creating ? _createPin : _unlock,
                  icon: Icon(creating ? Icons.check_circle_outline : Icons.login),
                  label: Text(creating ? 'Lưu mã PIN' : 'Mở ứng dụng'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createPin() async {
    if (pin.text.length < 4 || pin.text.length > 6) {
      return showError(context, 'Mã PIN phải có từ 4 đến 6 số');
    }
    if (pin.text != confirmPin.text) {
      return showError(context, 'Hai lần nhập mã PIN chưa giống nhau');
    }
    await StoreDb.instance.setSetting('pin', pin.text);
    if (mounted) setState(() { savedPin = pin.text; unlocked = true; });
  }

  void _unlock() {
    if (pin.text != savedPin) return showError(context, 'Mã PIN không đúng');
    setState(() => unlocked = true);
  }
}

class ChangePinPage extends StatefulWidget {
  const ChangePinPage({super.key});
  @override
  State<ChangePinPage> createState() => _ChangePinPageState();
}

class _ChangePinPageState extends State<ChangePinPage> {
  final oldPin = TextEditingController();
  final newPin = TextEditingController();
  final confirmPin = TextEditingController();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đổi mã PIN')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      pinField(oldPin, 'Mã PIN hiện tại'),
      const SizedBox(height: 12),
      pinField(newPin, 'Mã PIN mới'),
      const SizedBox(height: 12),
      pinField(confirmPin, 'Nhập lại mã PIN mới'),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: save, icon: const Icon(Icons.save),
          label: const Text('Lưu mã PIN mới')),
    ]),
  );

  Widget pinField(TextEditingController controller, String label) => TextField(
    controller: controller,
    obscureText: true,
    maxLength: 6,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.lock_outline)),
  );

  Future<void> save() async {
    final current = await StoreDb.instance.getSetting('pin');
    if (!mounted) return;
    if (oldPin.text != current) return showError(context, 'Mã PIN hiện tại không đúng');
    if (newPin.text.length < 4 || newPin.text.length > 6) {
      return showError(context, 'Mã PIN mới phải có từ 4 đến 6 số');
    }
    if (newPin.text != confirmPin.text) {
      return showError(context, 'Hai lần nhập mã PIN mới chưa giống nhau');
    }
    await StoreDb.instance.setSetting('pin', newPin.text);
    if (mounted) Navigator.pop(context);
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  int refreshKey = 0;
  void refresh() => setState(() => refreshKey++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(key: ValueKey('d$refreshKey')),
      ProductsPage(key: ValueKey('p$refreshKey'), onChanged: refresh),
      SalePage(key: ValueKey('s$refreshKey'), onChanged: refresh),
      InvoicesPage(key: ValueKey('i$refreshKey'), onChanged: refresh),
      MorePage(onChanged: refresh, onSelectTab: (value) => setState(() => index = value)),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Tổng quan'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Hàng hóa'),
          NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), selectedIcon: Icon(Icons.shopping_bag), label: 'Bán hàng'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Hóa đơn'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'Nhiều hơn'),
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
          if (action != null) action!,
        ]),
      );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, int>>(
        future: StoreDb.instance.dashboard(),
        builder: (context, snap) {
          final d = snap.data ?? {
            'revenue': 0, 'profit': 0, 'debt': 0, 'fund': 0,
            'invoices': 0, 'pending_repairs': 0, 'stock_value': 0,
          };
          return ListView(padding: const EdgeInsets.all(16), children: [
            const SizedBox(height: 8),
            const Text('Minh Cảnh Mobile', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Color(0xff0877d1))),
            const Text('Uy tín dẫn đầu – Chất lượng bền lâu'),
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(child: Text('Tổng quan',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ReportsPage())),
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('Xem báo cáo'),
              ),
            ]),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.35,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: [
                MetricCard('Doanh thu', vnd(d['revenue']!), Icons.trending_up, Colors.blue),
                MetricCard('Lợi nhuận', vnd(d['profit']!), Icons.account_balance_wallet, Colors.green),
                MetricCard('Hóa đơn', '${d['invoices']}', Icons.receipt_long, Colors.cyan),
                MetricCard('Công nợ KH', vnd(d['debt']!), Icons.people, Colors.orange),
                MetricCard('Số dư đã thu', vnd(d['fund']!), Icons.savings, Colors.teal),
                MetricCard('Đang sửa chữa', '${d['pending_repairs']} phiếu', Icons.build_circle, Colors.deepPurple),
                MetricCard('Giá trị tồn', vnd(d['stock_value']!), Icons.inventory, Colors.indigo),
              ],
            ),
          ]);
        },
      );
}

class MetricCard extends StatelessWidget {
  const MetricCard(this.label, this.value, this.icon, this.color, {super.key});
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: color)),
            Text(label),
          ]),
        ),
      );
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String search = '';
  @override
  Widget build(BuildContext context) => Column(children: [
        PageHeader('Hàng hóa', action: IconButton(icon: const Icon(Icons.add_circle, size: 34), onPressed: _add)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tên, mã hàng hoặc IMEI'), onChanged: (v) => setState(() => search = v.toLowerCase())),
        ),
        const SizedBox(height: 10),
        Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
          future: StoreDb.instance.products(),
          builder: (context, snap) {
            final rows = (snap.data ?? []).where((p) =>
                '${p['name']} ${p['code']} ${p['imeis'] ?? ''}'.toLowerCase().contains(search)).toList();
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (rows.isEmpty) return const Center(child: Text('Chưa có hàng hóa\nBấm dấu + để tạo mẫu hàng', textAlign: TextAlign.center));
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = rows[i];
                return Card(child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.phone_android)),
                  title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${p['code']} • Tồn: ${p['stock']}'),
                  trailing: Text(vnd(p['sale_price'] as int), style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => _detail(p),
                ));
              },
            );
          },
        )),
      ]);

  Future<void> _add() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ProductForm()));
    if (changed == true) { setState(() {}); widget.onChanged(); }
  }

  Future<void> _detail(Map<String, Object?> p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(product: p, onChanged: () { setState(() {}); widget.onChanged(); })));
    setState(() {});
  }
}

class ProductForm extends StatefulWidget {
  const ProductForm({super.key});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final form = GlobalKey<FormState>();
  final code = TextEditingController();
  final name = TextEditingController();
  final brand = TextEditingController();
  final capacity = TextEditingController();
  final price = TextEditingController();
  bool imei = true;
  bool saving = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Hàng hóa mới')),
        body: Form(key: form, child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: code, decoration: const InputDecoration(labelText: 'Mã hàng *'), validator: requiredText),
          const SizedBox(height: 12),
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Tên hàng *'), validator: requiredText),
          const SizedBox(height: 12),
          TextFormField(controller: brand, decoration: const InputDecoration(labelText: 'Thương hiệu')),
          const SizedBox(height: 12),
          TextFormField(controller: capacity, decoration: const InputDecoration(labelText: 'Dung lượng')),
          const SizedBox(height: 12),
          TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá bán')),
          const SizedBox(height: 12),
          Card(child: SwitchListTile(title: const Text('Quản lý theo Serial/IMEI'), subtitle: Text(imei ? 'Điện thoại: mỗi máy một IMEI' : 'Phụ kiện: quản lý theo số lượng'), value: imei, onChanged: (v) => setState(() => imei = v))),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save), label: const Text('Lưu mẫu hàng')),
        ])),
      );

  String? requiredText(String? v) => v == null || v.trim().isEmpty ? 'Không được để trống' : null;
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await StoreDb.instance.addProduct({
        'code': code.text.trim(), 'name': name.text.trim(), 'category': imei ? 'Điện thoại' : 'Phụ kiện',
        'brand': brand.text.trim(), 'capacity': capacity.text.trim(), 'sale_price': int.tryParse(price.text) ?? 0,
        'track_imei': imei ? 1 : 0, 'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) { showError(context, e); setState(() => saving = false); }
  }
}

class ProductDetail extends StatefulWidget {
  const ProductDetail({super.key, required this.product, required this.onChanged});
  final Map<String, Object?> product;
  final VoidCallback onChanged;
  @override
  State<ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<ProductDetail> {
  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final tracks = p['track_imei'] == 1;
    return Scaffold(
      appBar: AppBar(title: Text('${p['name']}'), actions: [IconButton(icon: const Icon(Icons.delete_outline), onPressed: delete)]),
      floatingActionButton: FloatingActionButton.extended(onPressed: purchase, icon: const Icon(Icons.add_shopping_cart), label: const Text('Nhập thêm hàng')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text('Mã: ${p['code']}'), Text('Giá bán: ${vnd(p['sale_price'] as int)}'),
          Text(tracks ? 'Quản lý theo Serial/IMEI' : 'Quản lý theo số lượng'),
        ]))),
        const SizedBox(height: 14),
        Text(tracks ? 'Danh sách IMEI' : 'Tồn kho', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (tracks) FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.serials(p['id'] as int), builder: (context, snap) {
          final rows = snap.data ?? [];
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (rows.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('Chưa nhập IMEI')));
          return Column(children: rows.map((s) => Card(child: ListTile(title: Text('${s['imei']}'), subtitle: Text('${s['color']} • ${s['condition_text']} • Giá vốn ${vnd(s['cost'] as int)}'), trailing: Text(statusName('${s['status']}'))))).toList());
        }) else Card(child: ListTile(title: const Text('Số lượng hiện tại'), trailing: Text('${p['stock']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))),
        const SizedBox(height: 80),
      ]),
    );
  }

  Future<void> purchase() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => PurchaseForm(initialProduct: widget.product)));
    if (ok == true) { setState(() {}); widget.onChanged(); }
  }
  Future<void> delete() async {
    if (!await confirm(context, 'Xóa hàng hóa', 'Bạn có chắc chắn muốn xóa hàng hóa này không?')) return;
    try { await StoreDb.instance.deleteProduct(widget.product['id'] as int); widget.onChanged(); if (mounted) Navigator.pop(context); }
    catch (e) { showError(context, e); }
  }
}

class PurchaseForm extends StatefulWidget {
  const PurchaseForm({super.key, this.initialProduct});
  final Map<String, Object?>? initialProduct;
  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  Map<String, Object?>? product;
  int quantity = 1;
  final cost = TextEditingController();
  final supplier = TextEditingController();
  final paid = TextEditingController();
  String payment = 'Tiền mặt';
  final serials = <SerialDraft>[];
  bool saving = false;

  @override
  void initState() { super.initState(); product = widget.initialProduct; _syncSerials(); }
  void _syncSerials() {
    if (product?['track_imei'] == 1) {
      if (quantity < 1) {
        quantity = 1;
      }
      while (serials.length < quantity) {
        serials.add(SerialDraft());
      }
      while (serials.length > quantity) {
        serials.removeLast();
      }
    } else {
      serials.clear();
    }
  }

  void _addSerial() => setState(() {
    serials.add(SerialDraft());
    quantity = serials.length;
  });

  void _removeSerial(int index) => setState(() {
    if (serials.length <= 1) return;
    serials.removeAt(index);
    quantity = serials.length;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phiếu nhập hàng')),
    body: FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.products(), builder: (context, snap) {
      final products = snap.data ?? [];
      return ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<int>(
          initialValue: product?['id'] as int?, decoration: const InputDecoration(labelText: 'Chọn mẫu hàng *'),
          items: products.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']}'))).toList(),
          onChanged: (id) => setState(() {
            product = products.firstWhere((p) => p['id'] == id);
            quantity = 1;
            serials.clear();
            _syncSerials();
          }),
        ),
        const SizedBox(height: 12),
        if (product?['track_imei'] == 1)
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Số lượng máy nhập', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Mỗi máy tương ứng với một IMEI', style: TextStyle(fontSize: 12)),
              ])),
              Text('${serials.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ]),
          ))
        else
          TextFormField(initialValue: '$quantity', keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số lượng *'),
              onChanged: (v) => setState(() => quantity = int.tryParse(v) ?? 0)),
        const SizedBox(height: 12),
        TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Đơn giá nhập chung')),
        const SizedBox(height: 12),
        TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Nhà cung cấp')),
        const SizedBox(height: 12),
        TextField(controller: paid, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Đã thanh toán')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: payment, decoration: const InputDecoration(labelText: 'Phương thức'), items: ['Tiền mặt','Chuyển khoản','Ghi nợ nhà cung cấp'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => payment = v!)),
        if (product?['track_imei'] == 1) ...[
          const SizedBox(height: 20),
          const Text('Danh sách IMEI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Bấm “Thêm IMEI” để nhập nhiều máy cùng một mẫu hàng.'),
          const SizedBox(height: 8),
          ...List.generate(serials.length, (i) => SerialEditor(
              index: i, draft: serials[i], onRemove: () => _removeSerial(i),
              canRemove: serials.length > 1)),
          OutlinedButton.icon(
            onPressed: _addSerial,
            icon: const Icon(Icons.add),
            label: const Text('Thêm IMEI / thêm máy'),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.check), label: const Text('Hoàn thành phiếu nhập')),
      ]);
    }),
  );

  Future<void> save() async {
    if (product == null) return showError(context, 'Hãy chọn mẫu hàng');
    if (product!['track_imei'] == 1) quantity = serials.length;
    if (quantity <= 0) return showError(context, 'Số lượng phải lớn hơn 0');
    if (product!['track_imei'] == 1 && serials.any((s) => s.imei.trim().isEmpty || s.cost < 0)) return showError(context, 'Nhập đủ IMEI và giá vốn');
    setState(() => saving = true);
    try {
      final commonCost = int.tryParse(cost.text) ?? 0;
      for (final s in serials) { if (s.cost == 0) s.cost = commonCost; }
      await StoreDb.instance.completePurchase(productId: product!['id'] as int, quantity: quantity, unitCost: commonCost, supplier: supplier.text, paid: int.tryParse(paid.text) ?? 0, paymentMethod: payment, serials: serials);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { showError(context, e); setState(() => saving = false); }
  }
}

class SerialEditor extends StatelessWidget {
  const SerialEditor({super.key, required this.index, required this.draft,
      required this.onRemove, required this.canRemove});
  final int index;
  final SerialDraft draft;
  final VoidCallback onRemove;
  final bool canRemove;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Máy ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
        if (canRemove) IconButton(
          tooltip: 'Bỏ máy này',
          onPressed: onRemove,
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
        ),
      ]),
      const SizedBox(height: 8),
      TextFormField(initialValue: draft.imei, decoration: const InputDecoration(labelText: 'IMEI *'), onChanged: (v) => draft.imei = v),
      const SizedBox(height: 8),
      TextFormField(initialValue: draft.color, decoration: const InputDecoration(labelText: 'Màu sắc'), onChanged: (v) => draft.color = v),
      const SizedBox(height: 8),
      TextFormField(initialValue: draft.cost == 0 ? '' : '${draft.cost}', keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá vốn riêng'), onChanged: (v) => draft.cost = int.tryParse(v) ?? 0),
    ])),
  );
}

class SalePage extends StatefulWidget {
  const SalePage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<SalePage> createState() => _SalePageState();
}

class _SalePageState extends State<SalePage> {
  Map<String, Object?>? product;
  int? serialId;
  int quantity = 1;
  final price = TextEditingController();
  final customer = TextEditingController();
  final phone = TextEditingController();
  final cash = TextEditingController();
  final transfer = TextEditingController();
  final customWarranty = TextEditingController();
  int warranty = 0;
  bool saving = false;

  @override
  Widget build(BuildContext context) => Column(children: [
    const PageHeader('Bán hàng'),
    Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.products(), builder: (context, snap) {
      final products = (snap.data ?? []).where((p) => (p['stock'] as int) > 0).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<int>(decoration: const InputDecoration(labelText: 'Chọn hàng còn tồn'), initialValue: product?['id'] as int?, items: products.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']} • tồn ${p['stock']}'))).toList(), onChanged: (id) => setState(() { product = products.firstWhere((p) => p['id'] == id); serialId = null; price.text = '${product!['sale_price']}'; })),
        if (product?['track_imei'] == 1) FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.serials(product!['id'] as int, status: 'in_stock'), builder: (context, ss) => Padding(padding: const EdgeInsets.only(top: 12), child: DropdownButtonFormField<int>(decoration: const InputDecoration(labelText: 'Chọn IMEI *'), initialValue: serialId, items: (ss.data ?? []).map((s) => DropdownMenuItem(value: s['id'] as int, child: Text('${s['imei']} • ${s['color']}'))).toList(), onChanged: (v) => setState(() => serialId = v))))
        else if (product != null) Padding(padding: const EdgeInsets.only(top: 12), child: TextFormField(initialValue: '1', keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số lượng'), onChanged: (v) => quantity = int.tryParse(v) ?? 0)),
        const SizedBox(height: 12),
        TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá bán *')),
        const SizedBox(height: 12),
        TextField(controller: customer, decoration: const InputDecoration(labelText: 'Khách hàng')),
        const SizedBox(height: 12),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại')),
        const SizedBox(height: 12),
        TextField(controller: cash, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tiền mặt')),
        const SizedBox(height: 12),
        TextField(controller: transfer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Chuyển khoản')),
        const SizedBox(height: 12),
        const Text('Phần tiền còn lại sau tiền mặt và chuyển khoản sẽ tự ghi là khách nợ.',
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: warranty,
          decoration: const InputDecoration(labelText: 'Thời hạn bảo hành'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Không bảo hành')),
            DropdownMenuItem(value: 3, child: Text('3 tháng')),
            DropdownMenuItem(value: 6, child: Text('6 tháng')),
            DropdownMenuItem(value: 9, child: Text('9 tháng')),
            DropdownMenuItem(value: 12, child: Text('12 tháng / 1 năm')),
            DropdownMenuItem(value: 24, child: Text('2 năm')),
            DropdownMenuItem(value: -1, child: Text('Tự nhập số tháng')),
          ],
          onChanged: (v) => setState(() => warranty = v ?? 0),
        ),
        if (warranty == -1) ...[
          const SizedBox(height: 12),
          TextField(controller: customWarranty, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số tháng bảo hành *')),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: saving ? null : complete, icon: const Icon(Icons.shopping_cart_checkout), label: const Text('Hoàn tất bán hàng')),
      ]);
    })),
  ]);

  Future<void> complete() async {
    if (product == null) return showError(context, 'Hãy chọn sản phẩm');
    final warrantyMonths = warranty == -1 ? (int.tryParse(customWarranty.text) ?? -1) : warranty;
    if (warrantyMonths < 0) return showError(context, 'Số tháng bảo hành không hợp lệ');
    setState(() => saving = true);
    try {
      await StoreDb.instance.completeSale(product: product!, quantity: quantity, serialId: serialId, unitPrice: int.tryParse(price.text) ?? 0, customer: customer.text, phone: phone.text, cash: int.tryParse(cash.text) ?? 0, transfer: int.tryParse(transfer.text) ?? 0, warrantyMonths: warrantyMonths);
      customer.clear(); phone.clear(); cash.clear(); transfer.clear(); price.clear(); customWarranty.clear();
      setState(() { product = null; serialId = null; quantity = 1; warranty = 0; saving = false; });
      widget.onChanged();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tạo hóa đơn')));
    } catch (e) { showError(context, e); setState(() => saving = false); }
  }
}

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  String search = '';
  @override
  Widget build(BuildContext context) => Column(children: [
    const PageHeader('Hóa đơn'),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Tìm tên khách, tên máy, mã hóa đơn hoặc IMEI',
        ),
        onChanged: (value) => setState(() => search = value.trim().toLowerCase()),
      ),
    ),
    const SizedBox(height: 8),
    Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.sales(), builder: (context, snap) {
      final rows = (snap.data ?? []).where((sale) {
        final haystack = '${sale['customer']} ${sale['phone']} ${sale['code']} '
            '${sale['product_names'] ?? ''} ${sale['imeis'] ?? ''} '
            '${formatDateTime(sale['created_at'])}';
        return haystack.toLowerCase().contains(search);
      }).toList();
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (rows.isEmpty) {
        return Center(child: Text(search.isEmpty
            ? 'Chưa có hóa đơn' : 'Không tìm thấy hóa đơn phù hợp'));
      }
      return ListView.separated(padding: const EdgeInsets.all(16), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) {
        final s = rows[i]; final cancelled = s['status'] == 'cancelled';
        return Card(child: ListTile(
          title: Row(children: [Expanded(child: Text('${s['customer']}', style: const TextStyle(fontWeight: FontWeight.bold))), Text(vnd(s['total'] as int))]),
          subtitle: Text('${s['product_names'] ?? 'Hàng hóa'}\n'
              '${s['code']} • Ngày bán: ${formatDateTime(s['created_at'])}\n'
              '${cancelled ? 'ĐÃ HỦY' : 'Bảo hành: ${warrantyLabel(s['warranty_months'] as int)} • Nợ: ${vnd(s['debt'] as int)}'}'),
          isThreeLine: true,
          trailing: cancelled ? null : IconButton(icon: const Icon(Icons.cancel_outlined, color: Colors.red), onPressed: () => cancel(s['id'] as int)),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => InvoiceDetailPage(saleId: s['id'] as int)));
            if (mounted) setState(() {});
          },
        ));
      });
    })),
  ]);
  Future<void> cancel(int id) async {
    if (!await confirm(context, 'Hủy hóa đơn', 'Hủy hóa đơn sẽ hoàn lại tồn kho và loại số liệu khỏi doanh thu. Tiếp tục?')) return;
    await StoreDb.instance.cancelSale(id); setState(() {}); widget.onChanged();
  }
}

class InvoiceDetailPage extends StatelessWidget {
  const InvoiceDetailPage({super.key, required this.saleId});
  final int saleId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết hóa đơn')),
    body: FutureBuilder<Map<String, Object?>>(
      future: StoreDb.instance.saleDetail(saleId),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final sale = snap.data!['sale'] as Map<String, Object?>;
        final items = snap.data!['items'] as List<Map<String, Object?>>;
        final months = sale['warranty_months'] as int;
        final soldAt = parseDate(sale['created_at']);
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${sale['code']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              infoLine('Ngày bán', formatDateTime(sale['created_at'])),
              infoLine('Khách hàng', '${sale['customer']}'),
              infoLine('Số điện thoại', '${sale['phone']}'.trim().isEmpty ? 'Không ghi' : '${sale['phone']}'),
              infoLine('Trạng thái', sale['status'] == 'cancelled' ? 'Đã hủy' : 'Hoàn thành'),
            ]),
          )),
          const SizedBox(height: 12),
          const Text('Hàng đã bán', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...items.map((item) => Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.phone_android)),
            title: Text('${item['product_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text([
              if ('${item['imei']}'.trim().isNotEmpty && item['imei'] != null) 'IMEI: ${item['imei']}',
              'Số lượng: ${item['quantity']}',
              'Đơn giá: ${vnd(item['unit_price'] as int)}',
            ].join('\n')),
            isThreeLine: true,
          ))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Thanh toán', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              infoLine('Tổng tiền', vnd(sale['total'] as int)),
              infoLine('Tiền mặt', vnd(sale['paid_cash'] as int)),
              infoLine('Chuyển khoản', vnd(sale['paid_transfer'] as int)),
              infoLine('Khách còn nợ', vnd(sale['debt'] as int)),
            ]),
          )),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Bảo hành', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              infoLine('Thời hạn', warrantyLabel(months)),
              infoLine('Ngày bắt đầu', soldAt == null ? 'Không rõ' : DateFormat('dd/MM/yyyy').format(soldAt)),
              infoLine('Ngày hết hạn', months <= 0 || soldAt == null
                  ? 'Không có' : DateFormat('dd/MM/yyyy').format(addMonths(soldAt, months))),
            ]),
          )),
        ]);
      },
    ),
  );
}

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onChanged, required this.onSelectTab});
  final VoidCallback onChanged;
  final ValueChanged<int> onSelectTab;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const PageHeader('Nhiều hơn'),
    MenuGroup('Hàng hóa', [
      MenuAction(Icons.inventory_2, 'Hàng hóa', () => onSelectTab(1)),
      MenuAction(Icons.download, 'Nhập hàng', () async { final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PurchaseForm())); if (ok == true) onChanged(); }),
      MenuAction(Icons.fact_check, 'Kiểm kho', () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const StocktakePage())); onChanged(); }),
      MenuAction(Icons.assignment_return, 'Trả hàng nhập', () async { final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const InventoryActionPage(kind: 'supplier_return'))); if (ok == true) onChanged(); }),
      MenuAction(Icons.delete_sweep, 'Xuất hủy', () async { final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const InventoryActionPage(kind: 'discard'))); if (ok == true) onChanged(); }),
    ]),
    const SizedBox(height: 12),
    MenuGroup('Báo cáo', [
      MenuAction(Icons.assessment, 'Báo cáo tổng hợp', () =>
          Navigator.push(context, MaterialPageRoute(
              builder: (_) => const ReportsPage()))),
    ]),
    const SizedBox(height: 12),
    MenuGroup('Quản lý', [
      MenuAction(Icons.people, 'Khách hàng', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersPage()))),
      MenuAction(Icons.local_shipping, 'Nhà cung cấp', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuppliersPage()))),
      MenuAction(Icons.build, 'Phiếu sửa chữa', () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const RepairsPage())); onChanged(); }),
      MenuAction(Icons.verified_user, 'Phiếu bảo hành', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WarrantiesPage()))),
      MenuAction(Icons.savings, 'Sổ quỹ', () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const CashBookPage())); onChanged(); }),
    ]),
    const SizedBox(height: 12),
    MenuGroup('Dữ liệu', [
      MenuAction(Icons.backup, 'Sao lưu & khôi phục', () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage())); onChanged(); }),
      MenuAction(Icons.password, 'Đổi mã PIN', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePinPage()))),
    ]),
  ]);
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String period = 'month';
  DateTime anchor = DateTime.now();
  DateTimeRange? customRange;

  DateTimeRange get range {
    if (period == 'custom' && customRange != null) return customRange!;
    if (period == 'day') {
      final start = DateTime(anchor.year, anchor.month, anchor.day);
      return DateTimeRange(start: start, end: start.add(const Duration(days: 1)));
    }
    if (period == 'quarter') {
      final firstMonth = ((anchor.month - 1) ~/ 3) * 3 + 1;
      final start = DateTime(anchor.year, firstMonth);
      return DateTimeRange(start: start, end: DateTime(anchor.year, firstMonth + 3));
    }
    if (period == 'year') {
      final start = DateTime(anchor.year);
      return DateTimeRange(start: start, end: DateTime(anchor.year + 1));
    }
    final start = DateTime(anchor.year, anchor.month);
    return DateTimeRange(start: start, end: DateTime(anchor.year, anchor.month + 1));
  }

  String get rangeLabel {
    final current = range;
    if (period == 'day') return DateFormat('dd/MM/yyyy').format(current.start);
    if (period == 'month') return 'Tháng ${DateFormat('MM/yyyy').format(current.start)}';
    if (period == 'quarter') {
      final quarter = ((current.start.month - 1) ~/ 3) + 1;
      return 'Quý $quarter/${current.start.year}';
    }
    if (period == 'year') return 'Năm ${current.start.year}';
    final inclusiveEnd = current.end.subtract(const Duration(days: 1));
    return '${DateFormat('dd/MM/yyyy').format(current.start)} – '
        '${DateFormat('dd/MM/yyyy').format(inclusiveEnd)}';
  }

  void shiftPeriod(int amount) {
    setState(() {
      if (period == 'day') {
        anchor = anchor.add(Duration(days: amount));
      } else if (period == 'month') {
        anchor = DateTime(anchor.year, anchor.month + amount, 1);
      } else if (period == 'quarter') {
        anchor = DateTime(anchor.year, anchor.month + amount * 3, 1);
      } else if (period == 'year') {
        anchor = DateTime(anchor.year + amount, anchor.month, 1);
      }
    });
  }

  Future<void> pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: customRange == null
          ? DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: DateTime(now.year, now.month, now.day))
          : DateTimeRange(
              start: customRange!.start,
              end: customRange!.end.subtract(const Duration(days: 1))),
      helpText: 'Chọn khoảng thời gian báo cáo',
      cancelText: 'Hủy',
      confirmText: 'Xem báo cáo',
      saveText: 'Xong',
    );
    if (picked == null || !mounted) return;
    setState(() {
      period = 'custom';
      customRange = DateTimeRange(
          start: DateTime(picked.start.year, picked.start.month, picked.start.day),
          end: DateTime(picked.end.year, picked.end.month, picked.end.day)
              .add(const Duration(days: 1)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedRange = range;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Báo cáo'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Doanh thu'),
              Tab(text: 'Hàng hóa'),
              Tab(text: 'Hóa đơn'),
            ],
          ),
        ),
        body: Column(children: [
          _filterPanel(),
          Expanded(
            child: FutureBuilder<List<Object?>>(
              future: Future.wait<Object?>([
                StoreDb.instance.reportSummary(
                    selectedRange.start, selectedRange.end),
                StoreDb.instance.productReport(
                    selectedRange.start, selectedRange.end),
                StoreDb.instance.invoiceReport(
                    selectedRange.start, selectedRange.end),
              ]),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Không thể tải báo cáo: ${snapshot.error}',
                        textAlign: TextAlign.center),
                  ));
                }
                final summary = snapshot.data![0] as Map<String, int>;
                final products =
                    snapshot.data![1] as List<Map<String, Object?>>;
                final invoices =
                    snapshot.data![2] as List<Map<String, Object?>>;
                return TabBarView(children: [
                  _summaryTab(summary),
                  _productTab(products),
                  _invoiceTab(invoices),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _filterPanel() => Material(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(children: [
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: period,
            isDense: true,
            decoration: const InputDecoration(
                labelText: 'Xem báo cáo theo',
                prefixIcon: Icon(Icons.calendar_month)),
            items: const [
              DropdownMenuItem(value: 'day', child: Text('Ngày')),
              DropdownMenuItem(value: 'month', child: Text('Tháng')),
              DropdownMenuItem(value: 'quarter', child: Text('Quý')),
              DropdownMenuItem(value: 'year', child: Text('Năm')),
              DropdownMenuItem(value: 'custom', child: Text('Tùy chọn')),
            ],
            onChanged: (value) {
              if (value == null) return;
              if (value == 'custom') {
                pickCustomRange();
              } else {
                setState(() {
                  period = value;
                  customRange = null;
                });
              }
            },
          )),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Chọn ngày',
            onPressed: pickCustomRange,
            icon: const Icon(Icons.date_range),
          ),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            tooltip: 'Kỳ trước',
            onPressed: period == 'custom' ? null : () => shiftPeriod(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(child: Text(rangeLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          IconButton(
            tooltip: 'Kỳ sau',
            onPressed: period == 'custom' ? null : () => shiftPeriod(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
      ]),
    ),
  );

  Widget _summaryTab(Map<String, int> data) {
    final net = data['net_profit'] ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Kết quả $rangeLabel',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.35,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            MetricCard('Tổng doanh thu', vnd(data['revenue'] ?? 0),
                Icons.trending_up, Colors.blue),
            MetricCard('Lợi nhuận gộp', vnd(data['gross_profit'] ?? 0),
                Icons.account_balance_wallet, Colors.green),
            MetricCard('Chi phí sổ quỹ', vnd(data['expenses'] ?? 0),
                Icons.payments_outlined, Colors.orange),
            MetricCard('Lợi nhuận sau chi phí', vnd(net),
                Icons.savings, net < 0 ? Colors.red : Colors.teal),
            MetricCard('Hóa đơn bán', '${data['invoices'] ?? 0}',
                Icons.receipt_long, Colors.cyan),
            MetricCard('Sản phẩm đã bán', '${data['products_sold'] ?? 0}',
                Icons.shopping_bag, Colors.indigo),
          ],
        ),
        const SizedBox(height: 14),
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            infoLine('Bán hàng', vnd(data['sales_revenue'] ?? 0)),
            infoLine('Dịch vụ sửa chữa', vnd(data['repair_revenue'] ?? 0)),
            infoLine('Thu khác', vnd(data['other_income'] ?? 0)),
            infoLine('Khách còn nợ', vnd(data['debt'] ?? 0)),
            infoLine('Đã thu từ hóa đơn', vnd(data['collected'] ?? 0)),
            infoLine('Phiếu sửa hoàn tất', '${data['repairs'] ?? 0}'),
          ]),
        )),
        const SizedBox(height: 12),
        const Card(child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Lợi nhuận sau chi phí = lợi nhuận bán hàng và sửa chữa '
            '+ thu khác − các khoản chi trong Sổ quỹ.',
            style: TextStyle(color: Colors.black54),
          ),
        )),
      ],
    );
  }

  Widget _productTab(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return const EmptyState(Icons.inventory_2_outlined, 'Chưa có hàng hóa',
          'Hãy nhập hàng để xem báo cáo.');
    }
    final totalStock = rows.fold<int>(
        0, (sum, row) => sum + (row['stock'] as num? ?? 0).toInt());
    final stockValue = rows.fold<int>(
        0, (sum, row) => sum + (row['stock_value'] as num? ?? 0).toInt());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Báo cáo hàng hóa • $rangeLabel',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tổng tồn hiện tại'),
                Text('$totalStock sản phẩm',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold)),
              ],
            )),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Giá trị tồn'),
                Text(vnd(stockValue),
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold,
                        color: Colors.indigo)),
              ],
            )),
          ]),
        )),
        const SizedBox(height: 10),
        ...rows.map((row) {
          final sold = (row['sold_quantity'] as num? ?? 0).toInt();
          final revenue = (row['revenue'] as num? ?? 0).toInt();
          final profit = (row['profit'] as num? ?? 0).toInt();
          final stock = (row['stock'] as num? ?? 0).toInt();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(child: ListTile(
              leading: CircleAvatar(
                backgroundColor: sold > 0
                    ? Colors.blue.shade50 : Colors.grey.shade100,
                child: Icon(Icons.inventory_2,
                    color: sold > 0 ? Colors.blue : Colors.grey),
              ),
              title: Text('${row['name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  '${row['code']} • Tồn: $stock • Đã bán: $sold\n'
                  'Doanh thu: ${vnd(revenue)} • Lãi: ${vnd(profit)}'),
              isThreeLine: true,
            )),
          );
        }),
      ],
    );
  }

  Widget _invoiceTab(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return EmptyState(Icons.receipt_long_outlined, 'Không có hóa đơn',
          'Không có hóa đơn bán hàng trong $rangeLabel.');
    }
    final total = rows.fold<int>(
        0, (sum, row) => sum + (row['total'] as num? ?? 0).toInt());
    final profit = rows.fold<int>(
        0, (sum, row) => sum + (row['profit'] as num? ?? 0).toInt());
    final widgets = <Widget>[
      Text('Báo cáo hóa đơn • $rangeLabel',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Số hóa đơn'),
              Text('${rows.length}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          )),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(vnd(total),
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold,
                      color: Colors.blue)),
              Text('Lãi ${vnd(profit)}',
                  style: const TextStyle(color: Colors.green)),
            ],
          )),
        ]),
      )),
      const SizedBox(height: 12),
    ];
    String? lastDay;
    for (final row in rows) {
      final date = parseDate(row['created_at']) ?? DateTime.now();
      final day = DateFormat('dd/MM/yyyy').format(date);
      if (day != lastDay) {
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(day,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ));
        lastDay = day;
      }
      widgets.add(Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
        title: Text('${row['code']} • ${row['customer']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${DateFormat('HH:mm').format(date)} • ${row['product_names'] ?? ''}'
            '${'${row['imeis'] ?? ''}'.trim().isEmpty ? '' : ' • IMEI ${row['imeis']}'}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(vnd((row['total'] as num).toInt()),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Lãi ${vnd((row['profit'] as num).toInt())}',
                style: const TextStyle(fontSize: 12, color: Colors.green)),
          ],
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => InvoiceDetailPage(saleId: row['id'] as int))),
      )));
    }
    return ListView(padding: const EdgeInsets.all(16), children: widgets);
  }
}

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Khách hàng')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.customers(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState(Icons.people_outline, 'Chưa có khách hàng', 'Khách sẽ tự xuất hiện sau khi bán hàng.');
        return ListView.separated(
          padding: const EdgeInsets.all(16), itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text('${r['customer']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${('${r['phone']}').trim().isEmpty ? 'Không ghi SĐT' : r['phone']}\n'
                  '${r['transaction_count']} giao dịch • Tổng ${vnd(r['total_spent'] as num)}'),
              isThreeLine: true,
              trailing: (r['debt'] as num).toInt() > 0
                  ? Text('Nợ\n${vnd(r['debt'] as num)}', textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
                  : const Icon(Icons.check_circle, color: Colors.green),
            ));
          },
        );
      },
    ),
  );
}

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nhà cung cấp')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.suppliers(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState(Icons.local_shipping_outlined, 'Chưa có nhà cung cấp', 'Nhà cung cấp sẽ tự xuất hiện từ phiếu nhập hàng.');
        return ListView.separated(
          padding: const EdgeInsets.all(16), itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
              title: Text('${r['supplier_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${r['purchase_count']} phiếu nhập • Tổng ${vnd(r['total_purchase'] as num)}\n'
                  'Lần gần nhất: ${formatDateTime(r['last_purchase'])}'),
              isThreeLine: true,
              trailing: (r['debt'] as num).toInt() > 0
                  ? Text('Còn nợ\n${vnd(r['debt'] as num)}', textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))
                  : const Icon(Icons.check_circle, color: Colors.green),
            ));
          },
        );
      },
    ),
  );
}

class StocktakePage extends StatefulWidget {
  const StocktakePage({super.key});
  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kiểm kho')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.products(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState(Icons.fact_check_outlined, 'Chưa có hàng hóa', 'Hãy tạo và nhập hàng trước khi kiểm kho.');
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Tồn kho hiện tại', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...rows.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(child: ListTile(
              leading: Icon(p['track_imei'] == 1 ? Icons.phone_android : Icons.inventory_2),
              title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(p['track_imei'] == 1
                  ? 'Kiểm theo số lượng và danh sách IMEI'
                  : 'Kiểm và cân bằng lại số lượng'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Tồn ${p['stock']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (p['track_imei'] == 1) IconButton(
                  tooltip: 'Xem danh sách IMEI',
                  icon: const Icon(Icons.list_alt),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ProductDetail(product: p, onChanged: () => setState(() {})))),
                ),
              ]),
              onTap: () => count(p),
            )),
          )),
          const SizedBox(height: 14),
          const Text('Lịch sử kiểm gần đây', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, Object?>>>(
            future: StoreDb.instance.stocktakeHistory(),
            builder: (context, historySnap) {
              if (!historySnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final history = historySnap.data!;
              if (history.isEmpty) {
                return const Card(child: Padding(
                    padding: EdgeInsets.all(18), child: Text('Chưa có phiếu kiểm kho.')));
              }
              return Column(children: history.map((h) {
                final difference = h['difference'] as int;
                return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
                  leading: CircleAvatar(child: Text(difference == 0 ? '=' : difference > 0 ? '+' : '−')),
                  title: Text('${h['product_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${formatDateTime(h['created_at'])}\nHệ thống: ${h['system_quantity']} • Thực tế: ${h['actual_quantity']}'),
                  isThreeLine: true,
                  trailing: Text(difference == 0 ? 'Khớp' : '${difference > 0 ? '+' : ''}$difference',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          color: difference == 0 ? Colors.green : Colors.orange)),
                )));
              }).toList());
            },
          ),
        ]);
      },
    ),
  );

  Future<void> count(Map<String, Object?> product) async {
    final actual = TextEditingController(text: '${product['stock']}');
    final note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('Kiểm ${product['name']}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Tồn trên ứng dụng: ${product['stock']}'),
        const SizedBox(height: 12),
        TextField(controller: actual, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Số lượng đếm thực tế')),
        const SizedBox(height: 12),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Ghi chú')),
        if (product['track_imei'] == 1) ...[
          const SizedBox(height: 10),
          const Text('Với điện thoại, phiếu kiểm chỉ ghi nhận chênh lệch. Muốn giảm kho phải chọn đúng IMEI tại Trả hàng nhập hoặc Xuất hủy.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Bỏ qua')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Lưu kiểm kho')),
      ],
    ));
    if (ok != true) return;
    try {
      await StoreDb.instance.recordStocktake(
          product: product, actualQuantity: int.tryParse(actual.text) ?? -1, note: note.text);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu kết quả kiểm kho')));
      }
    } catch (e) { if (mounted) showError(context, e); }
  }
}

class InventoryActionPage extends StatefulWidget {
  const InventoryActionPage({super.key, required this.kind});
  final String kind;
  @override
  State<InventoryActionPage> createState() => _InventoryActionPageState();
}

class _InventoryActionPageState extends State<InventoryActionPage> {
  Map<String, Object?>? product;
  int? serialId;
  final quantity = TextEditingController(text: '1');
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final returning = widget.kind == 'supplier_return';
    return Scaffold(
      appBar: AppBar(title: Text(returning ? 'Trả hàng nhập' : 'Xuất hủy')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: StoreDb.instance.products(),
        builder: (context, snap) {
          final products = (snap.data ?? []).where((p) => (p['stock'] as int) > 0).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(returning
                ? 'Chọn hàng còn trong kho để trả lại nhà cung cấp.'
                : 'Chọn hàng hỏng, mất hoặc không còn giá trị để xuất khỏi kho.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: product?['id'] as int?,
              decoration: const InputDecoration(labelText: 'Hàng hóa *'),
              items: products.map((p) => DropdownMenuItem<int>(
                  value: p['id'] as int, child: Text('${p['name']} • tồn ${p['stock']}'))).toList(),
              onChanged: (id) => setState(() {
                product = products.firstWhere((p) => p['id'] == id);
                serialId = null;
              }),
            ),
            if (product?['track_imei'] == 1)
              FutureBuilder<List<Map<String, Object?>>>(
                future: StoreDb.instance.serials(product!['id'] as int, status: 'in_stock'),
                builder: (context, serialSnap) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<int>(
                    initialValue: serialId,
                    decoration: const InputDecoration(labelText: 'Chọn IMEI *'),
                    items: (serialSnap.data ?? []).map((s) => DropdownMenuItem<int>(
                        value: s['id'] as int, child: Text('${s['imei']} • ${s['color']}'))).toList(),
                    onChanged: (value) => setState(() => serialId = value),
                  ),
                ),
              )
            else if (product != null) ...[
              const SizedBox(height: 12),
              TextField(controller: quantity, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Số lượng *')),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: Icon(returning ? Icons.assignment_return : Icons.delete_sweep),
              label: Text(returning ? 'Xác nhận trả hàng' : 'Xác nhận xuất hủy'),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> save() async {
    if (product == null) return showError(context, 'Hãy chọn hàng hóa');
    setState(() => saving = true);
    try {
      await StoreDb.instance.inventoryAction(
        product: product!, kind: widget.kind,
        quantity: int.tryParse(quantity.text) ?? 0, serialId: serialId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { showError(context, e); setState(() => saving = false); }
    }
  }
}

class RepairsPage extends StatefulWidget {
  const RepairsPage({super.key});
  @override
  State<RepairsPage> createState() => _RepairsPageState();
}

class _RepairsPageState extends State<RepairsPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phiếu sửa chữa')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add, icon: const Icon(Icons.add), label: const Text('Nhận máy')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.repairs(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const EmptyState(Icons.build_outlined, 'Chưa có phiếu sửa chữa', 'Bấm “Nhận máy” để tạo phiếu đầu tiên.');
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            return Card(child: ListTile(
              leading: CircleAvatar(child: Icon(repairIcon('${r['status']}'))),
              title: Text('${r['device']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${r['code']} • ${r['customer']}\n${repairStatus('${r['status']}')} • ${formatDateTime(r['received_at'])}'),
              isThreeLine: true,
              trailing: Text(vnd(r['amount'] as int), style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () async {
                final changed = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => RepairDetailPage(repair: r)));
                if (changed == true && mounted) setState(() {});
              },
            ));
          },
        );
      },
    ),
  );

  Future<void> add() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const RepairForm()));
    if (changed == true && mounted) setState(() {});
  }
}

class RepairForm extends StatefulWidget {
  const RepairForm({super.key});
  @override
  State<RepairForm> createState() => _RepairFormState();
}

class _RepairFormState extends State<RepairForm> {
  final customer = TextEditingController();
  final phone = TextEditingController();
  final device = TextEditingController();
  final imei = TextEditingController();
  final issue = TextEditingController();
  final amount = TextEditingController();
  final partsCost = TextEditingController();
  final paid = TextEditingController();
  final note = TextEditingController();
  bool saving = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nhận máy sửa chữa')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: customer, decoration: const InputDecoration(labelText: 'Khách hàng')),
      const SizedBox(height: 12),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại')),
      const SizedBox(height: 12),
      TextField(controller: device, decoration: const InputDecoration(labelText: 'Tên máy *')),
      const SizedBox(height: 12),
      TextField(controller: imei, decoration: const InputDecoration(labelText: 'IMEI')),
      const SizedBox(height: 12),
      TextField(controller: issue, maxLines: 2, decoration: const InputDecoration(labelText: 'Tình trạng lỗi *')),
      const SizedBox(height: 12),
      TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá sửa dự kiến')),
      const SizedBox(height: 12),
      TextField(controller: partsCost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tiền linh kiện / giá vốn')),
      const SizedBox(height: 12),
      TextField(controller: paid, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Khách đã thanh toán')),
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Ghi chú')),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: saving ? null : save,
          icon: const Icon(Icons.save), label: const Text('Lưu phiếu nhận máy')),
    ]),
  );

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await StoreDb.instance.addRepair(
        customer: customer.text, phone: phone.text, device: device.text,
        imei: imei.text, issue: issue.text,
        amount: int.tryParse(amount.text) ?? 0,
        partsCost: int.tryParse(partsCost.text) ?? 0,
        paid: int.tryParse(paid.text) ?? 0, note: note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { showError(context, e); setState(() => saving = false); }
    }
  }
}

class RepairDetailPage extends StatefulWidget {
  const RepairDetailPage({super.key, required this.repair});
  final Map<String, Object?> repair;
  @override
  State<RepairDetailPage> createState() => _RepairDetailPageState();
}

class _RepairDetailPageState extends State<RepairDetailPage> {
  late String status = '${widget.repair['status']}';
  bool changed = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.repair;
    return Scaffold(
      appBar: AppBar(title: Text('${r['code']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['device']}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            infoLine('Khách hàng', '${r['customer']}'),
            infoLine('Số điện thoại', '${r['phone']}'.trim().isEmpty ? 'Không ghi' : '${r['phone']}'),
            infoLine('IMEI', '${r['imei']}'.trim().isEmpty ? 'Không ghi' : '${r['imei']}'),
            infoLine('Ngày nhận', formatDateTime(r['received_at'])),
            infoLine('Tình trạng', '${r['issue']}'),
            infoLine('Ghi chú', '${r['note']}'.trim().isEmpty ? 'Không có' : '${r['note']}'),
          ],
        ))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chi phí', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            infoLine('Tiền sửa', vnd(r['amount'] as int)),
            infoLine('Giá vốn', vnd(r['parts_cost'] as int)),
            infoLine('Lợi nhuận dự kiến', vnd((r['amount'] as int) - (r['parts_cost'] as int))),
            infoLine('Đã thu', vnd(r['paid'] as int)),
            infoLine('Khách còn nợ', vnd((r['amount'] as int) - (r['paid'] as int))),
          ],
        ))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Trạng thái phiếu'),
          items: const ['received', 'repairing', 'completed', 'returned', 'cancelled']
              .map((s) => DropdownMenuItem(value: s, child: Text(repairStatus(s)))).toList(),
          onChanged: (value) async {
            if (value == null) return;
            await StoreDb.instance.updateRepairStatus(r['id'] as int, value);
            if (mounted) setState(() { status = value; changed = true; });
          },
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.pop(context, changed), child: const Text('Xong')),
      ]),
    );
  }
}

class WarrantiesPage extends StatefulWidget {
  const WarrantiesPage({super.key});
  @override
  State<WarrantiesPage> createState() => _WarrantiesPageState();
}

class _WarrantiesPageState extends State<WarrantiesPage> {
  String search = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tra cứu bảo hành')),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Nhập IMEI, tên máy, tên khách hoặc SĐT',
          ),
          onChanged: (value) => setState(() => search = value.trim().toLowerCase()),
        ),
      ),
      Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
        future: StoreDb.instance.warranties(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final allRows = snap.data!;
          final rows = allRows.where((r) {
            final haystack = '${r['product_name']} ${r['customer']} ${r['phone']} '
                '${r['imei'] ?? ''} ${r['code']} ${formatDateTime(r['created_at'])}';
            return haystack.toLowerCase().contains(search);
          }).toList();
          if (rows.isEmpty) {
            return EmptyState(Icons.verified_user_outlined,
                allRows.isEmpty ? 'Chưa có máy đã bán' : 'Không tìm thấy thông tin',
                allRows.isEmpty
                    ? 'Máy sẽ xuất hiện ở đây sau khi tạo hóa đơn bán hàng.'
                    : 'Hãy kiểm tra lại IMEI, tên máy hoặc tên khách.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16), itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = rows[i];
              final months = r['warranty_months'] as int;
              final sold = parseDate(r['created_at']);
              final end = sold == null || months <= 0 ? null : addMonths(sold, months);
              final active = months > 0 && end != null && !DateTime.now().isAfter(end);
              final noWarranty = months <= 0;
              final statusText = noWarranty
                  ? 'Hóa đơn không có bảo hành'
                  : active
                      ? 'Còn bảo hành đến ${DateFormat('dd/MM/yyyy').format(end)}'
                      : 'Đã hết bảo hành ${end == null ? '' : 'từ ${DateFormat('dd/MM/yyyy').format(end)}'}';
              final statusColor = noWarranty ? Colors.grey : (active ? Colors.green : Colors.red);
              return Card(child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: 0.1),
                    child: Icon(noWarranty ? Icons.gpp_maybe : active ? Icons.verified_user : Icons.gpp_bad,
                        color: statusColor)),
                title: Text('${r['product_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${r['customer']} • ${r['imei'] == null || '${r['imei']}'.trim().isEmpty ? 'Không IMEI' : r['imei']}\n'
                    '$statusText${(r['claim_count'] as num).toInt() > 0 ? ' • ${r['claim_count']} lần tiếp nhận' : ''}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => WarrantyDetailPage(warranty: r)));
                  if (mounted) setState(() {});
                },
              ));
            },
          );
        },
      )),
    ]),
  );
}

class WarrantyDetailPage extends StatefulWidget {
  const WarrantyDetailPage({super.key, required this.warranty});
  final Map<String, Object?> warranty;
  @override
  State<WarrantyDetailPage> createState() => _WarrantyDetailPageState();
}

class _WarrantyDetailPageState extends State<WarrantyDetailPage> {
  @override
  Widget build(BuildContext context) {
    final w = widget.warranty;
    final months = w['warranty_months'] as int;
    final sold = parseDate(w['created_at']);
    final end = sold == null || months <= 0 ? null : addMonths(sold, months);
    final active = months > 0 && end != null && !DateTime.now().isAfter(end);
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý bảo hành')),
      floatingActionButton: active ? FloatingActionButton.extended(
          onPressed: addClaim, icon: const Icon(Icons.add), label: const Text('Tiếp nhận bảo hành')) : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        if (!active) Card(color: Colors.orange.shade50, child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(child: Text(months <= 0
                ? 'Hóa đơn này không có thời hạn bảo hành.'
                : 'Sản phẩm đã hết thời hạn bảo hành.')),
          ]),
        )),
        if (!active) const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${w['product_name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            infoLine('Khách hàng', '${w['customer']}'),
            infoLine('Số điện thoại', '${w['phone']}'.trim().isEmpty ? 'Không ghi' : '${w['phone']}'),
            infoLine('IMEI', '${w['imei']}'.trim().isEmpty || w['imei'] == null ? 'Không ghi' : '${w['imei']}'),
            infoLine('Hóa đơn', '${w['code']}'),
            infoLine('Ngày bán', formatDateTime(w['created_at'])),
            infoLine('Thời hạn', warrantyLabel(months)),
            infoLine('Hết hạn', months <= 0 ? 'Không có' : end == null ? 'Không rõ' : DateFormat('dd/MM/yyyy').format(end)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => InvoiceDetailPage(saleId: w['sale_id'] as int))),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Xem hóa đơn gốc'),
            ),
          ],
        ))),
        const SizedBox(height: 16),
        const Text('Lịch sử tiếp nhận', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, Object?>>>(
          future: StoreDb.instance.warrantyClaims(w['sale_item_id'] as int),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Chưa có lần tiếp nhận bảo hành nào.')));
            return Column(children: rows.map((r) => Card(child: Padding(
              padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['issue']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Ngày nhận: ${formatDateTime(r['received_at'])}'),
                if ('${r['note']}'.trim().isNotEmpty) Text('Ghi chú: ${r['note']}'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: '${r['status']}',
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: const ['received', 'processing', 'waiting_parts', 'completed', 'returned']
                      .map((s) => DropdownMenuItem(value: s, child: Text(warrantyStatus(s)))).toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    await StoreDb.instance.updateWarrantyClaimStatus(r['id'] as int, value);
                    if (mounted) setState(() {});
                  },
                ),
              ]),
            ))).toList());
          },
        ),
      ]),
    );
  }

  Future<void> addClaim() async {
    final issue = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Tiếp nhận bảo hành'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: issue, maxLines: 2, decoration: const InputDecoration(labelText: 'Tình trạng máy *')),
        const SizedBox(height: 12),
        TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Ghi chú')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Tiếp nhận')),
      ],
    ));
    if (ok != true) return;
    try {
      await StoreDb.instance.addWarrantyClaim(
          saleItemId: widget.warranty['sale_item_id'] as int, issue: issue.text, note: note.text);
      if (mounted) setState(() {});
    } catch (e) { if (mounted) showError(context, e); }
  }
}

class CashBookPage extends StatefulWidget {
  const CashBookPage({super.key});
  @override
  State<CashBookPage> createState() => _CashBookPageState();
}

class _CashBookPageState extends State<CashBookPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sổ quỹ')),
    floatingActionButton: FloatingActionButton.extended(
        onPressed: add, icon: const Icon(Icons.add), label: const Text('Thêm thu/chi')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.cashEntries(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        final income = rows.where((r) => r['entry_type'] == 'income')
            .fold<int>(0, (sum, r) => sum + (r['amount'] as int));
        final expense = rows.where((r) => r['entry_type'] == 'expense')
            .fold<int>(0, (sum, r) => sum + (r['amount'] as int));
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tổng thu khác'), Text(vnd(income), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
            ])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Tổng chi'), Text(vnd(expense), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
            ])),
          ]))),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Chưa có khoản thu/chi riêng.')),
          ...rows.map((r) {
            final isIncome = r['entry_type'] == 'income';
            return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
              leading: CircleAvatar(backgroundColor: isIncome ? Colors.green.shade50 : Colors.red.shade50,
                  child: Icon(isIncome ? Icons.south_west : Icons.north_east,
                      color: isIncome ? Colors.green : Colors.red)),
              title: Text('${r['category']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${formatDateTime(r['created_at'])}${'${r['note']}'.trim().isEmpty ? '' : '\n${r['note']}'}'),
              isThreeLine: '${r['note']}'.trim().isNotEmpty,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${isIncome ? '+' : '-'}${vnd(r['amount'] as int)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: isIncome ? Colors.green : Colors.red)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => remove(r['id'] as int)),
              ]),
            )));
          }),
        ]);
      },
    ),
  );

  Future<void> add() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CashEntryForm()));
    if (changed == true && mounted) setState(() {});
  }

  Future<void> remove(int id) async {
    if (!await confirm(context, 'Xóa khoản thu/chi', 'Bạn có chắc muốn xóa mục này khỏi sổ quỹ?')) return;
    await StoreDb.instance.deleteCashEntry(id);
    if (mounted) setState(() {});
  }
}

class CashEntryForm extends StatefulWidget {
  const CashEntryForm({super.key});
  @override
  State<CashEntryForm> createState() => _CashEntryFormState();
}

class _CashEntryFormState extends State<CashEntryForm> {
  String type = 'expense';
  final category = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thêm khoản thu/chi')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'income', label: Text('Thu'), icon: Icon(Icons.south_west)),
          ButtonSegment(value: 'expense', label: Text('Chi'), icon: Icon(Icons.north_east)),
        ],
        selected: {type}, onSelectionChanged: (value) => setState(() => type = value.first),
      ),
      const SizedBox(height: 16),
      TextField(controller: category, decoration: const InputDecoration(labelText: 'Nhóm thu/chi')),
      const SizedBox(height: 12),
      TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số tiền *')),
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Ghi chú')),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Lưu vào sổ quỹ')),
    ]),
  );

  Future<void> save() async {
    try {
      await StoreDb.instance.addCashEntry(type: type, category: category.text,
          amount: int.tryParse(amount.text) ?? 0, note: note.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) showError(context, e); }
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final restoreText = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sao lưu & khôi phục')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sao lưu dữ liệu', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Ứng dụng sẽ sao chép toàn bộ kho, hóa đơn, bảo hành, sửa chữa và sổ quỹ vào bộ nhớ tạm. Hãy dán nội dung đó vào Ghi chú hoặc một tệp riêng để cất giữ.'),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: busy ? null : backup,
              icon: const Icon(Icons.copy_all), label: const Text('Sao chép bản sao lưu')),
        ],
      ))),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Khôi phục dữ liệu', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Dán nguyên nội dung bản sao lưu đã lưu trước đó vào ô bên dưới.'),
          const SizedBox(height: 12),
          TextField(controller: restoreText, minLines: 5, maxLines: 10,
              decoration: const InputDecoration(labelText: 'Dán dữ liệu sao lưu tại đây')),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(onPressed: busy ? null : restore,
              icon: const Icon(Icons.restore), label: const Text('Khôi phục từ bản sao')),
        ],
      ))),
    ]),
  );

  Future<void> backup() async {
    setState(() => busy = true);
    try {
      final data = await StoreDb.instance.exportBackup();
      await Clipboard.setData(ClipboardData(text: data));
      if (mounted) {
        await showDialog(context: context, builder: (dialogContext) => AlertDialog(
          title: const Text('Đã sao chép'),
          content: const Text('Toàn bộ dữ liệu đã được sao chép. Anh hãy mở Ghi chú, dán vào và lưu lại. Không chỉnh sửa nội dung bản sao.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Đã hiểu'))],
        ));
      }
    } catch (e) { if (mounted) showError(context, e); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> restore() async {
    if (restoreText.text.trim().isEmpty) return showError(context, 'Chưa có nội dung sao lưu');
    if (!await confirm(context, 'Khôi phục dữ liệu', 'Dữ liệu hiện tại trong ứng dụng sẽ được thay bằng bản sao này. Tiếp tục?')) return;
    setState(() => busy = true);
    try {
      await StoreDb.instance.restoreBackup(restoreText.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Khôi phục dữ liệu thành công')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) { showError(context, e); setState(() => busy = false); }
    }
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.title, this.subtitle, {super.key});
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 64, color: Colors.black26),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
    ]),
  ));
}

class MenuAction {
  MenuAction(this.icon, this.title, this.onTap);
  final IconData icon; final String title; final VoidCallback onTap;
}
class MenuGroup extends StatelessWidget {
  const MenuGroup(this.title, this.items, {super.key});
  final String title; final List<MenuAction> items;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.all(10), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
    ...items.map((e) => ListTile(leading: Icon(e.icon, color: Theme.of(context).colorScheme.primary), title: Text(e.title), trailing: const Icon(Icons.chevron_right), onTap: e.onTap)),
  ])));
}

String statusName(String status) => switch (status) {
  'in_stock' => 'Còn hàng', 'sold' => 'Đã bán', 'reserved' => 'Đang giữ',
  'returned_supplier' => 'Đã trả NCC', 'discarded' => 'Đã xuất hủy', _ => status,
};

DateTime? parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value');
}

String formatDateTime(Object? value) {
  final date = parseDate(value);
  return date == null ? 'Không rõ' : DateFormat('dd/MM/yyyy HH:mm').format(date);
}

DateTime addMonths(DateTime date, int months) {
  final firstOfTarget = DateTime(date.year, date.month + months, 1,
      date.hour, date.minute, date.second);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(firstOfTarget.year, firstOfTarget.month, day,
      date.hour, date.minute, date.second);
}

String warrantyLabel(int months) {
  if (months <= 0) return 'Không bảo hành';
  if (months == 12) return '12 tháng / 1 năm';
  if (months == 24) return '24 tháng / 2 năm';
  return '$months tháng';
}

Widget infoLine(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 125, child: Text(label, style: const TextStyle(color: Colors.black54))),
    Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
  ]),
);

String repairStatus(String status) => switch (status) {
  'received' => 'Đã nhận máy',
  'repairing' => 'Đang sửa chữa',
  'completed' => 'Đã sửa xong',
  'returned' => 'Đã trả khách',
  'cancelled' => 'Đã hủy',
  _ => status,
};

IconData repairIcon(String status) => switch (status) {
  'received' => Icons.move_to_inbox,
  'repairing' => Icons.build,
  'completed' => Icons.task_alt,
  'returned' => Icons.check_circle,
  'cancelled' => Icons.cancel,
  _ => Icons.build,
};

String warrantyStatus(String status) => switch (status) {
  'received' => 'Đã tiếp nhận',
  'processing' => 'Đang kiểm tra / xử lý',
  'waiting_parts' => 'Chờ linh kiện',
  'completed' => 'Đã xử lý xong',
  'returned' => 'Đã trả khách',
  _ => status,
};

void showError(BuildContext context, Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').replaceFirst('DatabaseException(', '').split(') sql').first;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: Colors.red));
}
Future<bool> confirm(BuildContext context, String title, String body) async => await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(title), content: Text(body), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận'))])) ?? false;
