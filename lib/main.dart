import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
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
    return openDatabase(file, version: 4, onConfigure: (db) async {
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
      await _createV3Tables(db);
      await _createV4Tables(db);
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await _createV2Tables(db);
      if (oldVersion < 3) await _createV3Tables(db);
      if (oldVersion < 4) await _createV4Tables(db);
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

  Future<List<Map<String, Object?>>> products(
      {bool includeInactive = false}) async {
    final db = await database;
    return db.rawQuery('''SELECT p.*,
      CASE WHEN p.track_imei=1 THEN
        (SELECT COUNT(*) FROM serial_units s WHERE s.product_id=p.id AND s.status='in_stock')
      ELSE p.quantity END AS stock,
      (SELECT GROUP_CONCAT(s.imei, ' ') FROM serial_units s
       WHERE s.product_id=p.id) AS imeis
      FROM products p
      ${includeInactive ? 'WHERE p.active>=0' : 'WHERE p.active=1'}
      ORDER BY p.active DESC, p.id DESC''');
  }

  Future<Map<String, Object?>> product(int id) async {
    final db = await database;
    final rows = await db.rawQuery('''SELECT p.*,
      CASE WHEN p.track_imei=1 THEN
        (SELECT COUNT(*) FROM serial_units s
         WHERE s.product_id=p.id AND s.status='in_stock')
      ELSE p.quantity END AS stock,
      (SELECT GROUP_CONCAT(s.imei, ' ') FROM serial_units s
       WHERE s.product_id=p.id) AS imeis
      FROM products p WHERE p.id=?''', [id]);
    if (rows.isEmpty) throw Exception('Không tìm thấy hàng hóa');
    return rows.single;
  }

  Future<int> addProduct(Map<String, Object?> row) async {
    final db = await database;
    return db.insert('products', row);
  }

  Future<void> updateProduct({
    required int id,
    required String code,
    required String name,
    required String brand,
    required String capacity,
    required int salePrice,
    int? averageCost,
  }) async {
    if (code.trim().isEmpty || name.trim().isEmpty) {
      throw Exception('Mã hàng và tên hàng không được để trống');
    }
    if (salePrice < 0 || (averageCost != null && averageCost < 0)) {
      throw Exception('Giá bán và giá nhập không được là số âm');
    }
    final db = await database;
    final values = <String, Object?>{
      'code': code.trim(),
      'name': name.trim(),
      'brand': brand.trim(),
      'capacity': capacity.trim(),
      'sale_price': salePrice,
    };
    if (averageCost != null) values['avg_cost'] = averageCost;
    await db.update('products', values, where: 'id=?', whereArgs: [id]);
  }

  Future<void> setProductActive(int id, bool active) async {
    final db = await database;
    final changed = await db.update(
      'products',
      {'active': active ? 1 : 0},
      where: 'id=?',
      whereArgs: [id],
    );
    if (changed == 0) throw Exception('Không tìm thấy hàng hóa');
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['id'],
        where: 'id=?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw Exception('Không tìm thấy hàng hóa');
      final used = Sqflite.firstIntValue(await txn.rawQuery(
            '''SELECT
              (SELECT COUNT(*) FROM purchase_items WHERE product_id=?) +
              (SELECT COUNT(*) FROM sale_items WHERE product_id=?) +
              (SELECT COUNT(*) FROM serial_units WHERE product_id=?) +
              (SELECT COUNT(*) FROM inventory_movements WHERE product_id=?) +
              (SELECT COUNT(*) FROM stocktakes WHERE product_id=?)''',
            [id, id, id, id, id],
          )) ??
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

  Future<List<Map<String, Object?>>> serials(int productId,
      {String? status}) async {
    final db = await database;
    return db.query('serial_units',
        where: status == null ? 'product_id=?' : 'product_id=? AND status=?',
        whereArgs: status == null ? [productId] : [productId, status],
        orderBy: 'id DESC');
  }

  Future<void> updateSerialUnit({
    required int id,
    required String imei,
    required String color,
    required String conditionText,
    required int cost,
  }) async {
    if (imei.trim().isEmpty) throw Exception('IMEI không được để trống');
    if (cost < 0) throw Exception('Giá nhập không được là số âm');
    final db = await database;
    await db.update('serial_units', {
      'imei': imei.trim(),
      'color': color.trim(),
      'condition_text':
          conditionText.trim().isEmpty ? 'Mới' : conditionText.trim(),
      'cost': cost,
    }, where: 'id=?', whereArgs: [id]);
  }

  Future<int?> _ensureCustomer(DatabaseExecutor db,
      String rawName, String rawPhone) async {
    final name = rawName.trim().isEmpty ? 'Khách lẻ' : rawName.trim();
    final phone = rawPhone.trim();
    if (name.toLowerCase() == 'khách lẻ') return null;
    final rows = await db.query('customer_directory',
        where: phone.isNotEmpty
            ? "phone=? OR (LOWER(name)=LOWER(?) AND phone=?)"
            : "LOWER(name)=LOWER(?) AND phone=''",
        whereArgs: phone.isNotEmpty ? [phone, name, phone] : [name],
        limit: 1);
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

  Future<int?> _ensureSupplier(
      DatabaseExecutor db, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return null;
    final rows = await db.query('supplier_directory',
        where: 'LOWER(name)=LOWER(?)', whereArgs: [name], limit: 1);
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

  Future<int> completeMultiSale({
    required List<SaleLineDraft> items,
    required String customer,
    required String phone,
    required int cash,
    required int transfer,
    required int warrantyMonths,
  }) async {
    if (items.isEmpty) throw Exception('Hãy thêm ít nhất một sản phẩm');
    final db = await database;
    return db.transaction((txn) async {
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
              'Sản phẩm ${item.product['name']} không còn kinh doanh');
        }
        final fresh = productRows.single;
        final tracksImei = fresh['track_imei'] == 1;
        if (item.unitPrice <= 0) {
          throw Exception('Giá bán phải lớn hơn 0');
        }
        if (item.discountPerItem < 0 ||
            item.discountPerItem > item.unitPrice) {
          throw Exception(
              'Giảm giá của ${fresh['name']} không hợp lệ');
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
        'code': 'HD${DateTime.now().millisecondsSinceEpoch}',
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
        await txn.insert('sale_items', {
          'sale_id': saleId,
          ...item,
        });
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
      final saleRows =
          await txn.query('sales', where: 'id=?', whereArgs: [saleId]);
      if (saleRows.isEmpty) throw Exception('Không tìm thấy hóa đơn');
      final sale = saleRows.single;
      if (sale['status'] == 'cancelled') return;
      final items =
          await txn.query('sale_items', where: 'sale_id=?', whereArgs: [saleId]);
      final now = DateTime.now().toIso8601String();
      for (final item in items) {
        final productId = item['product_id'] as int;
        final serialId = item['serial_id'] as int?;
        final qty = item['quantity'] as int;
        if (serialId != null) {
          await txn.update('serial_units', {'status': 'in_stock'},
              where: 'id=?', whereArgs: [serialId]);
        } else {
          await txn.rawUpdate(
              'UPDATE products SET quantity=quantity+? WHERE id=?',
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

  Future<void> deleteSale(int saleId) async {
    final db = await database;
    await db.transaction((txn) async {
      final saleRows =
          await txn.query('sales', where: 'id=?', whereArgs: [saleId]);
      if (saleRows.isEmpty) throw Exception('Không tìm thấy hóa đơn');
      final sale = saleRows.single;
      final items =
          await txn.query('sale_items', where: 'sale_id=?', whereArgs: [saleId]);

      // Hóa đơn chưa hủy vẫn đang trừ tồn, nên phải hoàn tồn trước khi xóa.
      if (sale['status'] != 'cancelled') {
        for (final item in items) {
          final productId = item['product_id'] as int;
          final serialId = item['serial_id'] as int?;
          final qty = item['quantity'] as int;
          if (serialId != null) {
            await txn.update('serial_units', {'status': 'in_stock'},
                where: 'id=?', whereArgs: [serialId]);
          } else {
            await txn.rawUpdate(
                'UPDATE products SET quantity=quantity+? WHERE id=?',
                [qty, productId]);
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

  Future<void> updateWarrantyClaim({
    required int id,
    required String issue,
    required String note,
    required String status,
  }) async {
    if (issue.trim().isEmpty) {
      throw Exception('Hãy nhập tình trạng máy');
    }
    final db = await database;
    final updated = await db.update('warranty_claims', {
      'issue': issue.trim(),
      'note': note.trim(),
      'status': status,
      'resolved_at': status == 'returned'
          ? DateTime.now().toIso8601String()
          : null,
    }, where: 'id=?', whereArgs: [id]);
    if (updated == 0) throw Exception('Không tìm thấy phiếu bảo hành');
  }

  Future<void> deleteWarrantyClaim(int id) async {
    final db = await database;
    final deleted =
        await db.delete('warranty_claims', where: 'id=?', whereArgs: [id]);
    if (deleted == 0) throw Exception('Không tìm thấy phiếu bảo hành');
  }

  Future<List<Map<String, Object?>>> customerDirectory() async {
    final db = await database;
    return db.query('customer_directory', orderBy: 'name COLLATE NOCASE');
  }

  Future<List<Map<String, Object?>>> supplierDirectory() async {
    final db = await database;
    return db.query('supplier_directory', orderBy: 'name COLLATE NOCASE');
  }

  Future<Map<String, Object?>> addCustomerDirectory({
    required String name,
    required String phone,
    required String note,
  }) async {
    if (name.trim().isEmpty) throw Exception('Hãy nhập tên khách hàng');
    final db = await database;
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final existing = await db.query('customer_directory',
        where: cleanPhone.isNotEmpty
            ? "phone=? OR (LOWER(name)=LOWER(?) AND phone=?)"
            : "LOWER(name)=LOWER(?) AND phone=''",
        whereArgs: cleanPhone.isNotEmpty
            ? [cleanPhone, cleanName, cleanPhone] : [cleanName],
        limit: 1);
    if (existing.isNotEmpty) return existing.single;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('customer_directory', {
      'name': cleanName,
      'phone': cleanPhone,
      'note': note.trim(),
      'created_at': now,
      'updated_at': now,
    });
    return (await db.query('customer_directory',
        where: 'id=?', whereArgs: [id])).single;
  }

  Future<Map<String, Object?>> updateCustomerDirectory({
    required int id,
    required String name,
    required String phone,
    required String note,
  }) async {
    if (name.trim().isEmpty) throw Exception('Hãy nhập tên khách hàng');
    final db = await database;
    return db.transaction((txn) async {
      final old = (await txn.query('customer_directory',
          where: 'id=?', whereArgs: [id])).single;
      final cleanName = name.trim();
      final cleanPhone = phone.trim();
      await txn.update('customer_directory', {
        'name': cleanName,
        'phone': cleanPhone,
        'note': note.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }, where: 'id=?', whereArgs: [id]);
      for (final table in ['sales', 'repairs']) {
        await txn.update(table, {'customer': cleanName, 'phone': cleanPhone},
            where: 'LOWER(TRIM(customer))=LOWER(?) AND TRIM(phone)=?',
            whereArgs: ['${old['name']}'.trim(), '${old['phone']}'.trim()]);
      }
      return (await txn.query('customer_directory',
          where: 'id=?', whereArgs: [id])).single;
    });
  }

  Future<Map<String, Object?>> addSupplierDirectory({
    required String name,
    required String phone,
    required String address,
    required String note,
  }) async {
    if (name.trim().isEmpty) throw Exception('Hãy nhập tên nhà cung cấp');
    final db = await database;
    final cleanName = name.trim();
    final existing = await db.query('supplier_directory',
        where: 'LOWER(name)=LOWER(?)', whereArgs: [cleanName], limit: 1);
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
    return (await db.query('supplier_directory',
        where: 'id=?', whereArgs: [id])).single;
  }

  Future<Map<String, Object?>> updateSupplierDirectory({
    required int id,
    required String name,
    required String phone,
    required String address,
    required String note,
  }) async {
    if (name.trim().isEmpty) throw Exception('Hãy nhập tên nhà cung cấp');
    final db = await database;
    return db.transaction((txn) async {
      final old = (await txn.query('supplier_directory',
          where: 'id=?', whereArgs: [id])).single;
      final cleanName = name.trim();
      await txn.update('supplier_directory', {
        'name': cleanName,
        'phone': phone.trim(),
        'address': address.trim(),
        'note': note.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }, where: 'id=?', whereArgs: [id]);
      await txn.update('purchases', {'supplier': cleanName},
          where: 'LOWER(TRIM(supplier))=LOWER(?)',
          whereArgs: ['${old['name']}'.trim()]);
      return (await txn.query('supplier_directory',
          where: 'id=?', whereArgs: [id])).single;
    });
  }

  Future<List<Map<String, Object?>>> customers() async {
    final db = await database;
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

  Future<List<Map<String, Object?>>> customerSales(
      String name, String phone) async {
    final db = await database;
    return db.rawQuery('''SELECT s.*,
      COALESCE(SUM(si.quantity),0) item_quantity,
      GROUP_CONCAT(p.name || CASE WHEN su.imei IS NULL OR su.imei=''
        THEN '' ELSE ' • IMEI ' || su.imei END, ' | ') product_names
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id=s.id
      LEFT JOIN products p ON p.id=si.product_id
      LEFT JOIN serial_units su ON su.id=si.serial_id
      WHERE LOWER(TRIM(s.customer))=LOWER(?) AND TRIM(s.phone)=?
      GROUP BY s.id ORDER BY s.created_at DESC''', [name.trim(), phone.trim()]);
  }

  Future<List<Map<String, Object?>>> customerRepairs(
      String name, String phone) async {
    final db = await database;
    return db.query('repairs',
        where: "LOWER(TRIM(customer))=LOWER(?) AND TRIM(phone)=? AND status!='cancelled'",
        whereArgs: [name.trim(), phone.trim()], orderBy: 'received_at DESC');
  }

  Future<List<Map<String, Object?>>> suppliers() async {
    final db = await database;
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

  Future<List<Map<String, Object?>>> supplierPurchases(String name) async {
    final db = await database;
    return db.rawQuery('''SELECT p.*,
      COALESCE(SUM(pi.quantity),0) total_quantity,
      GROUP_CONCAT(pr.name || ' x' || pi.quantity, ' | ') product_names
      FROM purchases p
      LEFT JOIN purchase_items pi ON pi.purchase_id=p.id
      LEFT JOIN products pr ON pr.id=pi.product_id
      WHERE LOWER(TRIM(p.supplier))=LOWER(?)
      GROUP BY p.id ORDER BY p.created_at DESC''', [name.trim()]);
  }

  Future<List<Map<String, Object?>>> debtAdjustments(
      String partyType, int partyId) async {
    final db = await database;
    return db.query('debt_adjustments',
        where: 'party_type=? AND party_id=?',
        whereArgs: [partyType, partyId], orderBy: 'created_at DESC, id DESC');
  }

  Future<void> addDebtAdjustment({
    required String partyType,
    required int partyId,
    required int amount,
    required bool increase,
    required int currentDebt,
    required String note,
  }) async {
    if (partyType != 'customer' && partyType != 'supplier') {
      throw Exception('Loại công nợ không hợp lệ');
    }
    if (amount <= 0) throw Exception('Số tiền phải lớn hơn 0');
    if (!increase && amount > currentDebt) {
      throw Exception('Số tiền giảm không được lớn hơn công nợ hiện tại');
    }
    final db = await database;
    await db.insert('debt_adjustments', {
      'party_type': partyType,
      'party_id': partyId,
      'amount_delta': increase ? amount : -amount,
      'note': note.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
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
    await db.transaction((txn) async {
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
        'status': 'received',
        'note': note.trim(),
        'received_at': now.toIso8601String(),
      });
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

  Future<Map<String, Object?>> repair(int id) async {
    final db = await database;
    final rows = await db.query('repairs', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) throw Exception('Không tìm thấy phiếu sửa chữa');
    return rows.first;
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
    if (device.trim().isEmpty || issue.trim().isEmpty) {
      throw Exception('Hãy nhập tên máy và tình trạng lỗi');
    }
    if (amount < 0 || partsCost < 0 || paid < 0 || paid > amount) {
      throw Exception('Số tiền phiếu sửa chữa không hợp lệ');
    }
    final db = await database;
    await db.transaction((txn) async {
      await _ensureCustomer(txn, customer, phone);
      final updated = await txn.update('repairs', {
        'customer': customer.trim().isEmpty ? 'Khách lẻ' : customer.trim(),
        'phone': phone.trim(),
        'device': device.trim(),
        'imei': imei.trim(),
        'issue': issue.trim(),
        'amount': amount,
        'parts_cost': partsCost,
        'paid': paid,
        'note': note.trim(),
      }, where: 'id=?', whereArgs: [id]);
      if (updated == 0) throw Exception('Không tìm thấy phiếu sửa chữa');
    });
  }

  Future<void> deleteRepair(int id) async {
    final db = await database;
    final deleted = await db.delete('repairs', where: 'id=?', whereArgs: [id]);
    if (deleted == 0) throw Exception('Không tìm thấy phiếu sửa chữa');
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
      'cash_entries', 'stocktakes', 'customer_directory',
      'supplier_directory', 'debt_adjustments', 'app_settings'
    ];
    final data = <String, Object?>{
      'app': 'MinhCanhMobileV3',
      'backup_version': 4,
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
      'warranty_claims', 'stocktakes', 'cash_entries', 'debt_adjustments', 'repairs',
      'inventory_movements', 'sale_items', 'sales', 'purchase_items',
      'serial_units', 'purchases', 'products', 'customer_directory',
      'supplier_directory', 'app_settings'
    ];
    const insertOrder = [
      'products', 'purchases', 'serial_units', 'purchase_items', 'sales',
      'sale_items', 'inventory_movements', 'repairs', 'warranty_claims',
      'cash_entries', 'stocktakes', 'customer_directory',
      'supplier_directory', 'debt_adjustments', 'app_settings'
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
        await _backfillDirectories(txn);
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

  Future<List<Map<String, Object?>>> salesTrend(String mode) async {
    final db = await database;
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
      next = (value, amount) =>
          DateTime(value.year, value.month + amount);
      label = (value) => DateFormat('MM/yyyy').format(value);
    } else {
      first = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
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
      final result = await db.rawQuery('''
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
      ''', [
        startText, endText,
        startText, endText,
        startText, endText,
      ]);
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
    final debtAdjustmentRows = await db.rawQuery('''SELECT
      COALESCE(SUM(amount_delta),0) amount
      FROM debt_adjustments WHERE party_type='customer' ''');
    final stockRows = await db.rawQuery('''SELECT
      COALESCE((SELECT SUM(quantity*avg_cost) FROM products
        WHERE track_imei=0 AND active>=0),0) +
      COALESCE((SELECT SUM(su.cost) FROM serial_units su
        JOIN products p ON p.id=su.product_id
        WHERE su.status='in_stock' AND p.active>=0),0) stock_value''');
    int n(Map<String, Object?> row, String key) => (row[key] as num? ?? 0).toInt();
    final sale = salesRows.single;
    final repair = repairRows.single;
    final cash = cashRows.single;
    return {
      'revenue': n(sale, 'revenue') + n(repair, 'revenue'),
      'profit': n(sale, 'profit') + n(repair, 'profit'),
      'debt': n(sale, 'debt') + n(repair, 'debt')
          + n(debtAdjustmentRows.single, 'amount'),
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

class SaleLineDraft {
  SaleLineDraft({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.discountPerItem,
    this.serialId,
    this.imei = '',
    this.color = '',
  });

  final Map<String, Object?> product;
  int quantity;
  final int unitPrice;
  final int discountPerItem;
  final int? serialId;
  final String imei;
  final String color;

  bool get tracksImei => product['track_imei'] == 1;
  int get soldQuantity => tracksImei ? 1 : quantity;
  int get netUnitPrice => unitPrice - discountPerItem;
  int get total => soldQuantity * netUnitPrice;
  int get discountTotal => soldQuantity * discountPerItem;
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
  bool showInactive = false;

  @override
  Widget build(BuildContext context) => Column(children: [
        PageHeader('Hàng hóa', action: IconButton(
          tooltip: 'Thêm hàng hóa',
          icon: const Icon(Icons.add_circle, size: 34),
          onPressed: _add,
        )),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tên, mã hàng hoặc IMEI',
            ),
            onChanged: (v) => setState(() => search = v.toLowerCase()),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.storefront),
                  label: Text('Đang bán'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.pause_circle_outline),
                  label: Text('Ngừng KD'),
                ),
              ],
              selected: {showInactive},
              onSelectionChanged: (values) =>
                  setState(() => showInactive = values.first),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
          future: StoreDb.instance.products(includeInactive: true),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data!.where((p) {
              final inactive = p['active'] != 1;
              final matchesStatus = showInactive == inactive;
              final matchesSearch =
                  '${p['name']} ${p['code']} ${p['imeis'] ?? ''}'
                      .toLowerCase()
                      .contains(search);
              return matchesStatus && matchesSearch;
            }).toList();
            if (rows.isEmpty) {
              return Center(child: Text(
                showInactive
                    ? 'Không có hàng hóa ngừng kinh doanh'
                    : 'Chưa có hàng hóa\nBấm dấu + để tạo mẫu hàng',
                textAlign: TextAlign.center,
              ));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = rows[i];
                final active = p['active'] == 1;
                return Card(child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: active
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.grey.shade200,
                    child: Icon(
                      active ? Icons.phone_android : Icons.block,
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                  ),
                  title: Text(
                    '${p['name']}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: active ? null : Colors.grey.shade700,
                    ),
                  ),
                  subtitle: Text(
                    '${p['code']} • Tồn: ${p['stock']}\n'
                    '${active ? 'Đang kinh doanh' : 'Ngừng kinh doanh'}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    vnd(p['sale_price'] as int),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: active ? null : Colors.grey,
                    ),
                  ),
                  onTap: () => _detail(p),
                ));
              },
            );
          },
        )),
      ]);

  Future<void> _add() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProductForm()),
    );
    if (changed == true) {
      setState(() {});
      widget.onChanged();
    }
  }

  Future<void> _detail(Map<String, Object?> p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetail(
          product: p,
          onChanged: () {
            setState(() {});
            widget.onChanged();
          },
        ),
      ),
    );
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
  late Map<String, Object?> product;

  @override
  void initState() {
    super.initState();
    product = widget.product;
  }

  @override
  Widget build(BuildContext context) {
    final p = product;
    final tracks = p['track_imei'] == 1;
    final active = p['active'] == 1;
    return Scaffold(
      appBar: AppBar(title: Text('${p['name']}'), actions: [
        IconButton(
          tooltip: 'Sửa thông tin',
          icon: const Icon(Icons.edit_outlined),
          onPressed: edit,
        ),
      ]),
      floatingActionButton: active
          ? FloatingActionButton.extended(
              onPressed: purchase,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nhập thêm hàng'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(
                    '${p['name']}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  )),
                  Chip(
                    avatar: Icon(
                      active ? Icons.check_circle : Icons.pause_circle,
                      size: 18,
                      color: active ? Colors.green : Colors.orange,
                    ),
                    label: Text(
                      active ? 'Đang kinh doanh' : 'Ngừng kinh doanh',
                    ),
                  ),
                ]),
                Text('Mã: ${p['code']}'),
                Text('Giá bán: ${vnd(p['sale_price'] as int)}'),
                if (!tracks)
                  Text('Giá nhập bình quân: ${vnd(p['avg_cost'] as int)}'),
                Text(tracks
                    ? 'Quản lý theo Serial/IMEI'
                    : 'Quản lý theo số lượng'),
              ],
            ),
          )),
          if (!active) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(child: Text(
                    'Hàng hóa đang ngừng kinh doanh nên không xuất hiện khi '
                    'bán hoặc nhập hàng mới. Tồn kho và lịch sử vẫn được giữ.',
                  )),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            tracks ? 'Danh sách IMEI' : 'Tồn kho',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (tracks)
            FutureBuilder<List<Map<String, Object?>>>(
              future: StoreDb.instance.serials(p['id'] as int),
              builder: (context, snap) {
                final rows = snap.data ?? [];
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return const Card(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Chưa nhập IMEI'),
                  ));
                }
                return Column(children: rows.map((s) => Card(child: ListTile(
                  title: Text('${s['imei']}'),
                  subtitle: Text(
                    '${s['color']} • ${s['condition_text']} • '
                    'Giá nhập ${vnd(s['cost'] as int)}\n'
                    '${statusName('${s['status']}')}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => editSerial(s),
                ))).toList());
              },
            )
          else
            Card(child: ListTile(
              title: const Text('Số lượng hiện tại'),
              trailing: Text(
                '${p['stock']}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )),
          const SizedBox(height: 18),
          if (active)
            OutlinedButton.icon(
              onPressed: toggleActive,
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('Ngừng kinh doanh'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
            )
          else
            FilledButton.icon(
              onPressed: toggleActive,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Kinh doanh trở lại'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xóa hàng hóa'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> reload() async {
    final fresh = await StoreDb.instance.product(product['id'] as int);
    if (mounted) setState(() => product = fresh);
  }

  Future<void> edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProductEditForm(product: product)),
    );
    if (changed == true) {
      await reload();
      widget.onChanged();
    }
  }

  Future<void> editSerial(Map<String, Object?> serial) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SerialEditForm(serial: serial)),
    );
    if (changed == true) {
      setState(() {});
      widget.onChanged();
    }
  }

  Future<void> purchase() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PurchaseForm(
        initialProduct: product,
      )),
    );
    if (ok == true) {
      await reload();
      widget.onChanged();
    }
  }

  Future<void> toggleActive() async {
    final active = product['active'] == 1;
    final accepted = await confirm(
      context,
      active ? 'Ngừng kinh doanh' : 'Kinh doanh trở lại',
      active
          ? 'Hàng hóa sẽ không còn xuất hiện khi bán hoặc nhập hàng mới. '
              'Tồn kho và toàn bộ lịch sử vẫn được giữ nguyên.'
          : 'Hàng hóa sẽ xuất hiện trở lại khi bán và nhập hàng.',
    );
    if (!accepted) return;
    try {
      await StoreDb.instance.setProductActive(
        product['id'] as int,
        !active,
      );
      await reload();
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(active
              ? 'Đã ngừng kinh doanh hàng hóa'
              : 'Đã kinh doanh trở lại'),
        ));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> delete() async {
    final accepted = await confirm(
      context,
      'Xóa hẳn hàng hóa',
      'Hàng hóa sẽ biến mất khỏi danh sách và không còn tính vào tồn kho. '
          'Hóa đơn, công nợ và bảo hành cũ vẫn được giữ nguyên để số liệu '
          'không bị sai. Tiếp tục?',
    );
    if (!accepted) return;
    try {
      await StoreDb.instance.deleteProduct(product['id'] as int);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

}

class ProductEditForm extends StatefulWidget {
  const ProductEditForm({super.key, required this.product});
  final Map<String, Object?> product;
  @override
  State<ProductEditForm> createState() => _ProductEditFormState();
}

class _ProductEditFormState extends State<ProductEditForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController code;
  late final TextEditingController name;
  late final TextEditingController brand;
  late final TextEditingController capacity;
  late final TextEditingController salePrice;
  late final TextEditingController averageCost;
  bool saving = false;

  bool get tracksImei => widget.product['track_imei'] == 1;

  @override
  void initState() {
    super.initState();
    code = TextEditingController(text: '${widget.product['code']}');
    name = TextEditingController(text: '${widget.product['name']}');
    brand = TextEditingController(text: '${widget.product['brand']}');
    capacity = TextEditingController(text: '${widget.product['capacity']}');
    salePrice = TextEditingController(text: '${widget.product['sale_price']}');
    averageCost = TextEditingController(text: '${widget.product['avg_cost']}');
  }

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    brand.dispose();
    capacity.dispose();
    salePrice.dispose();
    averageCost.dispose();
    super.dispose();
  }

  String? requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'Không được để trống' : null;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sửa thông tin hàng hóa')),
    body: Form(
      key: form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextFormField(controller: code,
            decoration: const InputDecoration(labelText: 'Mã hàng *'),
            validator: requiredText),
        const SizedBox(height: 12),
        TextFormField(controller: name,
            decoration: const InputDecoration(labelText: 'Tên hàng *'),
            validator: requiredText),
        const SizedBox(height: 12),
        TextFormField(controller: brand,
            decoration: const InputDecoration(labelText: 'Thương hiệu')),
        const SizedBox(height: 12),
        TextFormField(controller: capacity,
            decoration: const InputDecoration(labelText: 'Dung lượng')),
        const SizedBox(height: 12),
        TextFormField(controller: salePrice,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Giá bán *')),
        const SizedBox(height: 12),
        if (!tracksImei)
          TextFormField(controller: averageCost,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Giá nhập bình quân hiện tại *')),
        if (tracksImei)
          const Card(child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
                'Giá nhập của điện thoại được lưu riêng theo từng IMEI. '
                'Quay lại danh sách IMEI và bấm vào chiếc máy cần sửa giá.'),
          )),
        const SizedBox(height: 20),
        FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save),
            label: const Text('Lưu thay đổi')),
      ]),
    ),
  );

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await StoreDb.instance.updateProduct(
        id: widget.product['id'] as int,
        code: code.text,
        name: name.text,
        brand: brand.text,
        capacity: capacity.text,
        salePrice: int.tryParse(salePrice.text) ?? 0,
        averageCost: tracksImei
            ? null : (int.tryParse(averageCost.text) ?? 0),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => saving = false);
      }
    }
  }
}

class SerialEditForm extends StatefulWidget {
  const SerialEditForm({super.key, required this.serial});
  final Map<String, Object?> serial;
  @override
  State<SerialEditForm> createState() => _SerialEditFormState();
}

class _SerialEditFormState extends State<SerialEditForm> {
  late final TextEditingController imei;
  late final TextEditingController color;
  late final TextEditingController conditionText;
  late final TextEditingController cost;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    imei = TextEditingController(text: '${widget.serial['imei']}');
    color = TextEditingController(text: '${widget.serial['color']}');
    conditionText =
        TextEditingController(text: '${widget.serial['condition_text']}');
    cost = TextEditingController(text: '${widget.serial['cost']}');
  }

  @override
  void dispose() {
    imei.dispose();
    color.dispose();
    conditionText.dispose();
    cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sửa IMEI và giá nhập')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: imei,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'IMEI *')),
      const SizedBox(height: 12),
      TextField(controller: color,
          decoration: const InputDecoration(labelText: 'Màu sắc')),
      const SizedBox(height: 12),
      TextField(controller: conditionText,
          decoration: const InputDecoration(labelText: 'Tình trạng')),
      const SizedBox(height: 12),
      TextField(controller: cost,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Giá nhập *')),
      const SizedBox(height: 20),
      FilledButton.icon(
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save),
          label: const Text('Lưu thay đổi')),
    ]),
  );

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await StoreDb.instance.updateSerialUnit(
        id: widget.serial['id'] as int,
        imei: imei.text,
        color: color.text,
        conditionText: conditionText.text,
        cost: int.tryParse(cost.text) ?? 0,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => saving = false);
      }
    }
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
  final discount = TextEditingController(text: '0');
  final supplier = TextEditingController();
  final paid = TextEditingController();
  String payment = 'Tiền mặt';
  final serials = <SerialDraft>[];
  List<Map<String, Object?>> suppliers = [];
  int selectedSupplierId = 0;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    product = widget.initialProduct;
    _syncSerials();
    _loadSuppliers();
  }

  @override
  void dispose() {
    cost.dispose();
    discount.dispose();
    supplier.dispose();
    paid.dispose();
    super.dispose();
  }

  int get unitPrice => int.tryParse(cost.text) ?? 0;
  int get discountPerItem => int.tryParse(discount.text) ?? 0;
  int get netUnitCost => unitPrice >= discountPerItem
      ? unitPrice - discountPerItem : 0;
  int get purchaseTotal => quantity * netUnitCost;
  int get remainingToPay {
    final value = purchaseTotal - (int.tryParse(paid.text) ?? 0);
    return value < 0 ? 0 : value;
  }

  Widget _summaryRow(String label, String value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(label,
              style: TextStyle(fontWeight:
                  strong ? FontWeight.bold : FontWeight.w500))),
          Container(
            constraints: const BoxConstraints(minWidth: 135),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: strong ? const Color(0xFFE8ECF2) : Colors.white,
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(value, textAlign: TextAlign.right,
                style: TextStyle(fontSize: 16,
                    fontWeight: strong ? FontWeight.bold : FontWeight.w500)),
          ),
        ]),
      );

  Future<void> _loadSuppliers({int? selectId}) async {
    final rows = await StoreDb.instance.supplierDirectory();
    if (!mounted) return;
    setState(() {
      suppliers = rows;
      if (selectId != null) {
        selectedSupplierId = selectId;
        final selected = rows.where((row) => row['id'] == selectId);
        supplier.text = selected.isEmpty ? '' : '${selected.first['name']}';
      }
    });
  }

  Future<void> _pickSupplier(int? id) async {
    if (id == null) return;
    if (id == -1) {
      final created = await Navigator.push<Map<String, Object?>>(context,
          MaterialPageRoute(builder: (_) => const SupplierFormPage()));
      if (created != null) {
        await _loadSuppliers(selectId: created['id'] as int);
      }
      return;
    }
    setState(() {
      selectedSupplierId = id;
      final selected = suppliers.where((row) => row['id'] == id);
      supplier.text = id == 0 || selected.isEmpty
          ? '' : '${selected.first['name']}';
    });
  }
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

  Future<void> _pickProduct(
      List<Map<String, Object?>> products) async {
    if (products.isEmpty) {
      showError(context, 'Chưa có hàng hóa đang kinh doanh');
      return;
    }
    final selected = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductSearchSheet(
        products: products,
        selectedId: product?['id'] as int?,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      product = selected;
      quantity = 1;
      serials.clear();
      _syncSerials();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phiếu nhập hàng')),
    body: FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.products(), builder: (context, snap) {
      final products = snap.data ?? [];
      return ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          leading: const CircleAvatar(child: Icon(Icons.search)),
          title: Text(
            product == null ? 'Chọn sản phẩm *' : '${product!['name']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            product == null
                ? 'Bấm để tìm theo tên, mã hàng, hãng hoặc dung lượng'
                : [
                    '${product!['code']}',
                    if ('${product!['brand']}'.trim().isNotEmpty)
                      '${product!['brand']}',
                    if ('${product!['capacity']}'.trim().isNotEmpty)
                      '${product!['capacity']}',
                  ].join(' • '),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickProduct(products),
        )),
        const SizedBox(height: 12),
        if (product?['track_imei'] == 1)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Danh sách IMEI',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('Mỗi IMEI tương ứng với một máy nhập.'),
            const SizedBox(height: 8),
            ...List.generate(serials.length, (i) => SerialEditor(
                index: i, draft: serials[i], onRemove: () => _removeSerial(i),
                canRemove: serials.length > 1)),
            OutlinedButton.icon(
              onPressed: _addSerial,
              icon: const Icon(Icons.add),
              label: const Text('Thêm Serial / IMEI'),
            ),
          ])
        else
          TextFormField(initialValue: '$quantity', keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Số lượng *'),
              onChanged: (v) => setState(() => quantity = int.tryParse(v) ?? 0)),
        const SizedBox(height: 12),
        TextField(controller: cost, keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Đơn giá nhập *'),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: discount, keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Giảm giá trên mỗi sản phẩm'),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        Card(color: const Color(0xFFF5F7FA), child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _summaryRow('Số lượng nhập', '$quantity', strong: true),
            _summaryRow('Đơn giá', vnd(unitPrice)),
            _summaryRow('Giảm giá', vnd(discountPerItem)),
            _summaryRow('Giá nhập', vnd(netUnitCost), strong: true),
            _summaryRow('Thành tiền', vnd(purchaseTotal), strong: true),
          ]),
        )),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: ValueKey('supplier-$selectedSupplierId-${suppliers.length}'),
          initialValue: selectedSupplierId,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Nhà cung cấp', prefixIcon: Icon(Icons.local_shipping)),
          items: [
            const DropdownMenuItem(value: 0,
                child: Text('Không ghi nhà cung cấp')),
            ...suppliers.map((row) => DropdownMenuItem(
                value: row['id'] as int,
                child: Text('${row['name']}${'${row['phone']}'.trim().isEmpty ? '' : ' • ${row['phone']}'}'))),
            const DropdownMenuItem(value: -1,
                child: Text('+ Thêm nhà cung cấp mới')),
          ],
          onChanged: _pickSupplier,
        ),
        const SizedBox(height: 12),
        TextField(controller: paid, keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Đã thanh toán',
                helperText: 'Còn phải trả: ${vnd(remainingToPay)}'),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: payment, decoration: const InputDecoration(labelText: 'Phương thức'), items: ['Tiền mặt','Chuyển khoản','Ghi nợ nhà cung cấp'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => payment = v!)),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.check), label: const Text('Hoàn thành phiếu nhập')),
      ]);
    }),
  );

  Future<void> save() async {
    if (product == null) return showError(context, 'Hãy chọn mẫu hàng');
    if (product!['track_imei'] == 1) quantity = serials.length;
    if (quantity <= 0) return showError(context, 'Số lượng phải lớn hơn 0');
    if (unitPrice <= 0) return showError(context, 'Đơn giá nhập phải lớn hơn 0');
    if (discountPerItem < 0 || discountPerItem > unitPrice) {
      return showError(context, 'Giảm giá không được lớn hơn đơn giá');
    }
    if (product!['track_imei'] == 1 &&
        serials.any((s) => s.imei.trim().isEmpty)) {
      return showError(context, 'Hãy nhập đủ IMEI');
    }
    setState(() => saving = true);
    try {
      for (final s in serials) { s.cost = netUnitCost; }
      await StoreDb.instance.completePurchase(productId: product!['id'] as int,
          quantity: quantity, unitCost: netUnitCost, supplier: supplier.text,
          paid: int.tryParse(paid.text) ?? 0, paymentMethod: payment,
          serials: serials);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { showError(context, e); setState(() => saving = false); }
  }
}

class ProductSearchSheet extends StatefulWidget {
  const ProductSearchSheet({
    super.key,
    required this.products,
    this.selectedId,
  });

  final List<Map<String, Object?>> products;
  final int? selectedId;

  @override
  State<ProductSearchSheet> createState() => _ProductSearchSheetState();
}

class _ProductSearchSheetState extends State<ProductSearchSheet> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final rows = widget.products.where((product) {
      final text = [
        product['name'],
        product['code'],
        product['brand'],
        product['capacity'],
        product['category'],
      ].map((value) => '${value ?? ''}').join(' ').toLowerCase();
      return normalized.isEmpty || text.contains(normalized);
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(children: [
            const Expanded(child: Text(
              'Tìm sản phẩm',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            )),
            IconButton(
              tooltip: 'Đóng',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Nhập tên, mã hàng, hãng hoặc dung lượng',
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xóa từ khóa',
                      onPressed: () {
                        search.clear();
                        setState(() => query = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(
                  Icons.search_off,
                  'Không tìm thấy sản phẩm',
                  'Hãy thử tên hoặc mã hàng khác.',
                )
              : ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (context, index) {
                    final product = rows[index];
                    final selected = product['id'] == widget.selectedId;
                    final details = [
                      '${product['code']}',
                      if ('${product['brand']}'.trim().isNotEmpty)
                        '${product['brand']}',
                      if ('${product['capacity']}'.trim().isNotEmpty)
                        '${product['capacity']}',
                    ].join(' • ');
                    return Card(child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(product['track_imei'] == 1
                            ? Icons.phone_android
                            : Icons.inventory_2_outlined),
                      ),
                      title: Text(
                        '${product['name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(details),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, product),
                    ));
                  },
                ),
        ),
      ]),
    );
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
  final saleDiscount = TextEditingController(text: '0');
  final customer = TextEditingController();
  final phone = TextEditingController();
  final cash = TextEditingController();
  final transfer = TextEditingController();
  final customWarranty = TextEditingController();
  final cart = <SaleLineDraft>[];
  List<Map<String, Object?>> customers = [];
  int selectedCustomerId = 0;
  int warranty = 0;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    price.dispose();
    saleDiscount.dispose();
    customer.dispose();
    phone.dispose();
    cash.dispose();
    transfer.dispose();
    customWarranty.dispose();
    super.dispose();
  }

  int get draftQuantity => product?['track_imei'] == 1 ? 1 : quantity;
  int get listedUnitPrice => int.tryParse(price.text) ?? 0;
  int get discountPerItem => int.tryParse(saleDiscount.text) ?? 0;
  int get netSalePrice => listedUnitPrice >= discountPerItem
      ? listedUnitPrice - discountPerItem
      : 0;
  int get draftTotal => draftQuantity * netSalePrice;
  int get cartQuantity =>
      cart.fold(0, (sum, item) => sum + item.soldQuantity);
  int get cartTotal => cart.fold(0, (sum, item) => sum + item.total);
  int get cartDiscount =>
      cart.fold(0, (sum, item) => sum + item.discountTotal);
  int get customerDebt {
    final value = cartTotal - (int.tryParse(cash.text) ?? 0) -
        (int.tryParse(transfer.text) ?? 0);
    return value < 0 ? 0 : value;
  }

  Widget _saleSummaryRow(String label, String value,
          {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(
            label,
            style: TextStyle(
                fontWeight: strong ? FontWeight.bold : FontWeight.w500),
          )),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: strong ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ]),
      );

  Future<void> _loadCustomers({int? selectId}) async {
    final rows = await StoreDb.instance.customerDirectory();
    if (!mounted) return;
    setState(() {
      customers = rows;
      if (selectId != null) {
        selectedCustomerId = selectId;
        final selected = rows.where((row) => row['id'] == selectId);
        if (selected.isNotEmpty) {
          customer.text = '${selected.first['name']}';
          phone.text = '${selected.first['phone']}';
        }
      }
    });
  }

  Future<void> _pickCustomer(int? id) async {
    if (id == null) return;
    if (id == -1) {
      final created = await Navigator.push<Map<String, Object?>>(
        context,
        MaterialPageRoute(builder: (_) => const CustomerFormPage()),
      );
      if (created != null) {
        await _loadCustomers(selectId: created['id'] as int);
      }
      return;
    }
    setState(() {
      selectedCustomerId = id;
      final selected = customers.where((row) => row['id'] == id);
      customer.text =
          id == 0 || selected.isEmpty ? '' : '${selected.first['name']}';
      phone.text =
          id == 0 || selected.isEmpty ? '' : '${selected.first['phone']}';
    });
  }

  Future<void> _pickProduct(
      List<Map<String, Object?>> products) async {
    if (products.isEmpty) {
      showError(context, 'Không có sản phẩm còn tồn kho');
      return;
    }
    final selected = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductSearchSheet(
        products: products,
        selectedId: product?['id'] as int?,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      product = selected;
      serialId = null;
      quantity = 1;
      price.text = '${selected['sale_price']}';
      saleDiscount.text = '0';
    });
  }

  Future<void> addItem() async {
    final selectedProduct = product;
    if (selectedProduct == null) {
      showError(context, 'Hãy chọn sản phẩm cần thêm');
      return;
    }
    if (listedUnitPrice <= 0) {
      showError(context, 'Giá bán phải lớn hơn 0');
      return;
    }
    if (discountPerItem < 0 || discountPerItem > listedUnitPrice) {
      showError(context, 'Giảm giá không được lớn hơn giá bán');
      return;
    }

    final productId = selectedProduct['id'] as int;
    final tracksImei = selectedProduct['track_imei'] == 1;
    var imei = '';
    var color = '';

    if (tracksImei) {
      if (serialId == null) {
        showError(context, 'Hãy chọn IMEI');
        return;
      }
      if (cart.any((item) => item.serialId == serialId)) {
        showError(context, 'IMEI này đã có trong hóa đơn');
        return;
      }
      final serialRows = await StoreDb.instance.serials(
        productId,
        status: 'in_stock',
      );
      final selected =
          serialRows.where((row) => row['id'] == serialId).toList();
      if (selected.isEmpty) {
        if (mounted) showError(context, 'IMEI không còn trong kho');
        return;
      }
      imei = '${selected.single['imei']}';
      color = '${selected.single['color']}';
    } else {
      if (quantity <= 0) {
        showError(context, 'Số lượng phải lớn hơn 0');
        return;
      }
      final alreadyAdded = cart
          .where((item) =>
              item.serialId == null &&
              item.product['id'] == productId)
          .fold<int>(0, (sum, item) => sum + item.quantity);
      final stock = (selectedProduct['stock'] as num).toInt();
      if (alreadyAdded + quantity > stock) {
        showError(context, 'Tổng số lượng trong hóa đơn vượt tồn kho');
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      if (!tracksImei) {
        final sameLine = cart.where((item) =>
            item.serialId == null &&
            item.product['id'] == productId &&
            item.unitPrice == listedUnitPrice &&
            item.discountPerItem == discountPerItem);
        if (sameLine.isNotEmpty) {
          sameLine.first.quantity += quantity;
        } else {
          cart.add(SaleLineDraft(
            product: selectedProduct,
            quantity: quantity,
            unitPrice: listedUnitPrice,
            discountPerItem: discountPerItem,
          ));
        }
      } else {
        cart.add(SaleLineDraft(
          product: selectedProduct,
          quantity: 1,
          serialId: serialId,
          imei: imei,
          color: color,
          unitPrice: listedUnitPrice,
          discountPerItem: discountPerItem,
        ));
      }
      product = null;
      serialId = null;
      quantity = 1;
      price.clear();
      saleDiscount.text = '0';
    });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    const PageHeader('Bán hàng'),
    Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.products(),
      builder: (context, snap) {
        final products = (snap.data ?? [])
            .where((p) => (p['stock'] as num).toInt() > 0)
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Thêm sản phẩm vào hóa đơn',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.search)),
                    title: Text(
                      product == null
                          ? 'Chọn sản phẩm'
                          : '${product!['name']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(product == null
                        ? 'Tìm theo tên, mã, hãng hoặc dung lượng'
                        : '${product!['code']} • Tồn: ${product!['stock']}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickProduct(products),
                  ),
                  if (product?['track_imei'] == 1)
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: StoreDb.instance.serials(
                        product!['id'] as int,
                        status: 'in_stock',
                      ),
                      builder: (context, serialSnapshot) {
                        final rows = (serialSnapshot.data ?? []).where((row) =>
                            !cart.any((item) =>
                                item.serialId == row['id'])).toList();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(
                                'imei-${product!['id']}-${cart.length}'),
                            initialValue: serialId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Chọn IMEI *',
                            ),
                            items: rows.map((serial) => DropdownMenuItem(
                              value: serial['id'] as int,
                              child: Text(
                                '${serial['imei']} • ${serial['color']}',
                              ),
                            )).toList(),
                            onChanged: (value) =>
                                setState(() => serialId = value),
                          ),
                        );
                      },
                    )
                  else if (product != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextFormField(
                        key: ValueKey('sale-quantity-${product!['id']}'),
                        initialValue: '1',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Số lượng'),
                        onChanged: (value) => setState(
                            () => quantity = int.tryParse(value) ?? 0),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration:
                        const InputDecoration(labelText: 'Giá bán *'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: saleDiscount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Giảm giá trên mỗi sản phẩm',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (product != null) ...[
                    const SizedBox(height: 10),
                    _saleSummaryRow(
                        'Giá sau giảm', vnd(netSalePrice)),
                    _saleSummaryRow(
                        'Thành tiền', vnd(draftTotal), strong: true),
                  ],
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: product == null ? null : addItem,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Thêm vào hóa đơn'),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            Text(
              'Sản phẩm trong hóa đơn (${cart.length})',
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (cart.isEmpty)
              const Card(child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Chưa có sản phẩm. Hãy chọn hàng và bấm '
                  '“Thêm vào hóa đơn”.',
                  textAlign: TextAlign.center,
                ),
              ))
            else
              ...cart.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final details = item.tracksImei
                    ? 'IMEI: ${item.imei}'
                        '${item.color.trim().isEmpty ? '' : ' • ${item.color}'}'
                    : 'Số lượng: ${item.quantity}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(
                      '${item.product['name']}',
                      style:
                          const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '$details\n'
                      'Giá: ${vnd(item.unitPrice)}'
                      '${item.discountPerItem > 0 ? ' • Giảm: ${vnd(item.discountPerItem)}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          vnd(item.total),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                        InkWell(
                          onTap: () => setState(() => cart.removeAt(index)),
                          child: const Padding(
                            padding: EdgeInsets.only(top: 5),
                            child: Icon(Icons.delete_outline,
                                color: Colors.red, size: 21),
                          ),
                        ),
                      ],
                    ),
                  )),
                );
              }),
            const SizedBox(height: 10),
            Card(
              color: const Color(0xFFF5F7FA),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  _saleSummaryRow(
                      'Tổng số lượng', '$cartQuantity sản phẩm'),
                  if (cartDiscount > 0)
                    _saleSummaryRow(
                        'Tổng giảm giá', '-${vnd(cartDiscount)}'),
                  _saleSummaryRow(
                      'Khách phải trả', vnd(cartTotal), strong: true),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              key:
                  ValueKey('customer-$selectedCustomerId-${customers.length}'),
              initialValue: selectedCustomerId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Khách hàng',
                prefixIcon: Icon(Icons.person),
              ),
              items: [
                const DropdownMenuItem(
                    value: 0, child: Text('Khách lẻ')),
                ...customers.map((row) => DropdownMenuItem(
                  value: row['id'] as int,
                  child: Text(
                    '${row['name']}'
                    '${'${row['phone']}'.trim().isEmpty ? '' : ' • ${row['phone']}'}',
                  ),
                )),
                const DropdownMenuItem(
                  value: -1,
                  child: Text('+ Thêm khách hàng mới'),
                ),
              ],
              onChanged: _pickCustomer,
            ),
            if (selectedCustomerId > 0) ...[
              const SizedBox(height: 8),
              Text(
                'SĐT: ${phone.text.trim().isEmpty ? 'Không ghi' : phone.text}',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: cash,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration:
                  const InputDecoration(labelText: 'Tiền mặt'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: transfer,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: 'Chuyển khoản',
                helperText: 'Khách còn nợ: ${vnd(customerDebt)}',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text(
              'Phần tiền còn lại sau tiền mặt và chuyển khoản '
              'sẽ tự ghi là khách nợ.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: warranty,
              decoration:
                  const InputDecoration(labelText: 'Thời hạn bảo hành'),
              items: const [
                DropdownMenuItem(
                    value: 0, child: Text('Không bảo hành')),
                DropdownMenuItem(value: 3, child: Text('3 tháng')),
                DropdownMenuItem(value: 6, child: Text('6 tháng')),
                DropdownMenuItem(value: 9, child: Text('9 tháng')),
                DropdownMenuItem(
                    value: 12, child: Text('12 tháng / 1 năm')),
                DropdownMenuItem(value: 24, child: Text('2 năm')),
                DropdownMenuItem(
                    value: -1, child: Text('Tự nhập số tháng')),
              ],
              onChanged: (value) =>
                  setState(() => warranty = value ?? 0),
            ),
            if (warranty == -1) ...[
              const SizedBox(height: 12),
              TextField(
                controller: customWarranty,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                    labelText: 'Số tháng bảo hành *'),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: saving || cart.isEmpty ? null : complete,
              icon: const Icon(Icons.shopping_cart_checkout),
              label: Text(cart.isEmpty
                  ? 'Hãy thêm sản phẩm'
                  : 'Hoàn tất hóa đơn ${vnd(cartTotal)}'),
            ),
          ],
        );
      },
    )),
  ]);

  Future<void> complete() async {
    if (cart.isEmpty) {
      showError(context, 'Hãy thêm ít nhất một sản phẩm');
      return;
    }
    final warrantyMonths = warranty == -1
        ? (int.tryParse(customWarranty.text) ?? -1)
        : warranty;
    if (warrantyMonths < 0) {
      showError(context, 'Số tháng bảo hành không hợp lệ');
      return;
    }
    final cashValue = int.tryParse(cash.text) ?? 0;
    final transferValue = int.tryParse(transfer.text) ?? 0;
    if (cashValue + transferValue > cartTotal) {
      showError(context, 'Số tiền thanh toán vượt tổng hóa đơn');
      return;
    }

    setState(() => saving = true);
    try {
      await StoreDb.instance.completeMultiSale(
        items: List<SaleLineDraft>.from(cart),
        customer: customer.text,
        phone: phone.text,
        cash: cashValue,
        transfer: transferValue,
        warrantyMonths: warrantyMonths,
      );
      customer.clear();
      phone.clear();
      cash.clear();
      transfer.clear();
      price.clear();
      saleDiscount.text = '0';
      customWarranty.clear();
      setState(() {
        cart.clear();
        product = null;
        serialId = null;
        quantity = 1;
        warranty = 0;
        selectedCustomerId = 0;
        saving = false;
      });
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tạo hóa đơn nhiều sản phẩm')),
        );
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => saving = false);
      }
    }
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
        onChanged: (value) =>
            setState(() => search = value.trim().toLowerCase()),
      ),
    ),
    const SizedBox(height: 8),
    Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.sales(),
      builder: (context, snap) {
        final rows = (snap.data ?? []).where((sale) {
          final haystack =
              '${sale['customer']} ${sale['phone']} ${sale['code']} '
              '${sale['product_names'] ?? ''} ${sale['imeis'] ?? ''} '
              '${formatDateTime(sale['created_at'])}';
          return haystack.toLowerCase().contains(search);
        }).toList();
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows.isEmpty) {
          return Center(child: Text(search.isEmpty
              ? 'Chưa có hóa đơn'
              : 'Không tìm thấy hóa đơn phù hợp'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final sale = rows[i];
            final cancelled = sale['status'] == 'cancelled';
            return Card(child: ListTile(
              title: Row(children: [
                Expanded(child: Text(
                  '${sale['customer']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
                Text(vnd(sale['total'] as int)),
              ]),
              subtitle: Text(
                '${sale['product_names'] ?? 'Hàng hóa'}\n'
                '${sale['code']} • Ngày bán: '
                '${formatDateTime(sale['created_at'])}\n'
                '${cancelled ? 'ĐÃ HỦY' : 'Bảo hành: ${warrantyLabel(sale['warranty_months'] as int)} • Nợ: ${vnd(sale['debt'] as int)}'}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                tooltip: 'Thao tác hóa đơn',
                onSelected: (action) {
                  if (action == 'cancel') {
                    cancel(sale['id'] as int);
                  } else if (action == 'delete') {
                    delete(sale['id'] as int);
                  }
                },
                itemBuilder: (_) => [
                  if (!cancelled)
                    const PopupMenuItem(
                      value: 'cancel',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.cancel_outlined,
                            color: Colors.orange),
                        title: Text('Hủy hóa đơn'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_forever, color: Colors.red),
                      title: Text('Xóa hóa đơn'),
                    ),
                  ),
                ],
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        InvoiceDetailPage(saleId: sale['id'] as int),
                  ),
                );
                if (mounted) setState(() {});
              },
            ));
          },
        );
      },
    )),
  ]);

  Future<void> cancel(int id) async {
    final accepted = await confirm(
      context,
      'Hủy hóa đơn',
      'Hủy hóa đơn sẽ hoàn lại tồn kho và loại số liệu khỏi doanh thu. '
          'Tiếp tục?',
    );
    if (!accepted) return;
    try {
      await StoreDb.instance.cancelSale(id);
      if (mounted) setState(() {});
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> delete(int id) async {
    final accepted = await confirm(
      context,
      'Xóa vĩnh viễn hóa đơn',
      'Hóa đơn sẽ bị xóa khỏi lịch sử. Tồn kho/IMEI được hoàn lại, '
          'công nợ, doanh thu, lợi nhuận và dữ liệu bảo hành liên quan '
          'cũng được loại bỏ. Thao tác này không thể hoàn tác.',
    );
    if (!accepted) return;
    try {
      await StoreDb.instance.deleteSale(id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa hóa đơn và hoàn lại tồn kho')),
        );
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final sale = snap.data!['sale'] as Map<String, Object?>;
        final items = snap.data!['items'] as List<Map<String, Object?>>;
        final discountTotal = (sale['discount_total'] as num? ?? 0).toInt();
        final months = sale['warranty_months'] as int;
        final soldAt = parseDate(sale['created_at']);
        final receipt = ReceiptDocument.invoice(sale, items);
        return ListView(padding: const EdgeInsets.all(16), children: [
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReceiptPreviewPage(receipt: receipt),
              ),
            ),
            icon: const Icon(Icons.print),
            label: const Text('In / chia sẻ hóa đơn'),
          ),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sale['code']}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                infoLine('Ngày bán', formatDateTime(sale['created_at'])),
                infoLine('Khách hàng', '${sale['customer']}'),
                infoLine(
                  'Số điện thoại',
                  '${sale['phone']}'.trim().isEmpty
                      ? 'Không ghi'
                      : '${sale['phone']}',
                ),
                infoLine(
                  'Trạng thái',
                  sale['status'] == 'cancelled' ? 'Đã hủy' : 'Hoàn thành',
                ),
              ],
            ),
          )),
          const SizedBox(height: 12),
          const Text(
            'Hàng đã bán',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.phone_android)),
            title: Text(
              '${item['product_name']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text([
              if ('${item['imei']}'.trim().isNotEmpty &&
                  item['imei'] != null)
                'IMEI: ${item['imei']}',
              'Số lượng: ${item['quantity']}',
              'Đơn giá: ${vnd(item['unit_price'] as int)}',
            ].join('\n')),
            isThreeLine: true,
          ))),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thanh toán',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (discountTotal > 0) ...[
                  infoLine(
                    'Tạm tính',
                    vnd((sale['total'] as int) + discountTotal),
                  ),
                  infoLine('Giảm giá', '-${vnd(discountTotal)}'),
                ],
                infoLine('Tổng tiền', vnd(sale['total'] as int)),
                infoLine('Tiền mặt', vnd(sale['paid_cash'] as int)),
                infoLine(
                    'Chuyển khoản', vnd(sale['paid_transfer'] as int)),
                infoLine('Khách còn nợ', vnd(sale['debt'] as int)),
              ],
            ),
          )),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bảo hành',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                infoLine('Thời hạn', warrantyLabel(months)),
                infoLine(
                  'Ngày bắt đầu',
                  soldAt == null
                      ? 'Không rõ'
                      : DateFormat('dd/MM/yyyy').format(soldAt),
                ),
                infoLine(
                  'Ngày hết hạn',
                  months <= 0 || soldAt == null
                      ? 'Không có'
                      : DateFormat('dd/MM/yyyy')
                          .format(addMonths(soldAt, months)),
                ),
              ],
            ),
          )),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => delete(context),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Xóa hóa đơn'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          const SizedBox(height: 16),
        ]);
      },
    ),
  );

  Future<void> delete(BuildContext context) async {
    final accepted = await confirm(
      context,
      'Xóa vĩnh viễn hóa đơn',
      'Hóa đơn sẽ bị xóa khỏi lịch sử. Tồn kho/IMEI được hoàn lại, '
          'công nợ, doanh thu, lợi nhuận và dữ liệu bảo hành liên quan '
          'cũng được loại bỏ. Thao tác này không thể hoàn tác.',
    );
    if (!accepted) return;
    try {
      await StoreDb.instance.deleteSale(saleId);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Đã xóa hóa đơn và hoàn lại tồn kho')),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
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
      MenuAction(Icons.print, 'Cài đặt máy in K80', () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const PrinterSettingsPage()))),
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
  String trendPeriod = 'day';
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
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Báo cáo'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Doanh thu'),
              Tab(text: 'Hàng hóa'),
              Tab(text: 'Hóa đơn'),
              Tab(text: 'Biểu đồ'),
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
                StoreDb.instance.salesTrend(trendPeriod),
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
                final trend =
                    snapshot.data![3] as List<Map<String, Object?>>;
                return TabBarView(children: [
                  _summaryTab(summary),
                  _productTab(products),
                  _invoiceTab(invoices),
                  _trendTab(trend),
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

  Widget _trendTab(List<Map<String, Object?>> rows) {
    final maxRevenue = rows.fold<int>(
        0,
        (current, row) =>
            (row['revenue'] as num? ?? 0).toInt() > current
                ? (row['revenue'] as num? ?? 0).toInt()
                : current);
    final totalRevenue = rows.fold<int>(
        0, (sum, row) => sum + (row['revenue'] as num? ?? 0).toInt());
    final totalProducts = rows.fold<int>(
        0, (sum, row) => sum + (row['products'] as num? ?? 0).toInt());
    final totalInvoices = rows.fold<int>(
        0, (sum, row) => sum + (row['invoices'] as num? ?? 0).toInt());
    final title = trendPeriod == 'year'
        ? 'So sánh 5 năm gần nhất'
        : trendPeriod == 'month'
            ? 'So sánh 12 tháng gần nhất'
            : 'So sánh 7 ngày gần nhất';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'day',
                label: Text('Ngày'),
                icon: Icon(Icons.today)),
            ButtonSegment(
                value: 'month',
                label: Text('Tháng'),
                icon: Icon(Icons.calendar_month)),
            ButtonSegment(
                value: 'year',
                label: Text('Năm'),
                icon: Icon(Icons.event_note)),
          ],
          selected: {trendPeriod},
          onSelectionChanged: (values) =>
              setState(() => trendPeriod = values.first),
        ),
        const SizedBox(height: 16),
        Text(title,
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            infoLine('Tổng doanh thu bán hàng', vnd(totalRevenue)),
            infoLine('Sản phẩm đã bán', '$totalProducts'),
            infoLine('Số hóa đơn', '$totalInvoices'),
          ]),
        )),
        const SizedBox(height: 14),
        ...rows.map((row) {
          final revenue = (row['revenue'] as num? ?? 0).toInt();
          final products = (row['products'] as num? ?? 0).toInt();
          final invoices = (row['invoices'] as num? ?? 0).toInt();
          final ratio =
              maxRevenue == 0 ? 0.0 : revenue / maxRevenue;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
                child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                SizedBox(
                  width: 68,
                  child: Text('${row['label']}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(vnd(revenue),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 15,
                          color: Colors.blue,
                          backgroundColor: Colors.blue.shade50,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('$products sản phẩm • $invoices hóa đơn',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ])),
              ]),
            )),
          );
        }),
        const Card(
            child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
              'Biểu đồ chỉ so sánh hoạt động bán hàng. Phiếu bảo hành không được tính vào doanh thu hoặc lợi nhuận.'),
        )),
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

class CustomerFormPage extends StatefulWidget {
  const CustomerFormPage({super.key, this.customer});
  final Map<String, Object?>? customer;
  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController note;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${widget.customer?['customer'] ?? widget.customer?['name'] ?? ''}');
    phone = TextEditingController(text: '${widget.customer?['phone'] ?? ''}');
    note = TextEditingController(text: '${widget.customer?['note'] ?? ''}');
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.customer == null
        ? 'Thêm khách hàng' : 'Sửa khách hàng')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: name,
          decoration: const InputDecoration(labelText: 'Tên khách hàng *')),
      const SizedBox(height: 12),
      TextField(controller: phone, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Số điện thoại')),
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Ghi chú / quà đã tri ân')),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: saving ? null : save,
          icon: const Icon(Icons.save), label: const Text('Lưu khách hàng')),
    ]),
  );

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final result = widget.customer == null
          ? await StoreDb.instance.addCustomerDirectory(
              name: name.text, phone: phone.text, note: note.text)
          : await StoreDb.instance.updateCustomerDirectory(
              id: widget.customer!['id'] as int, name: name.text,
              phone: phone.text, note: note.text);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) { showError(context, e); setState(() => saving = false); }
    }
  }
}

class SupplierFormPage extends StatefulWidget {
  const SupplierFormPage({super.key, this.supplier});
  final Map<String, Object?>? supplier;
  @override
  State<SupplierFormPage> createState() => _SupplierFormPageState();
}

class _SupplierFormPageState extends State<SupplierFormPage> {
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController address;
  late final TextEditingController note;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${widget.supplier?['supplier_name'] ?? widget.supplier?['name'] ?? ''}');
    phone = TextEditingController(text: '${widget.supplier?['phone'] ?? ''}');
    address = TextEditingController(text: '${widget.supplier?['address'] ?? ''}');
    note = TextEditingController(text: '${widget.supplier?['note'] ?? ''}');
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.supplier == null
        ? 'Thêm nhà cung cấp' : 'Sửa nhà cung cấp')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: name,
          decoration: const InputDecoration(labelText: 'Tên nhà cung cấp *')),
      const SizedBox(height: 12),
      TextField(controller: phone, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Số điện thoại')),
      const SizedBox(height: 12),
      TextField(controller: address,
          decoration: const InputDecoration(labelText: 'Địa chỉ')),
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 3,
          decoration: const InputDecoration(labelText: 'Ghi chú')),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: saving ? null : save,
          icon: const Icon(Icons.save), label: const Text('Lưu nhà cung cấp')),
    ]),
  );

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final result = widget.supplier == null
          ? await StoreDb.instance.addSupplierDirectory(
              name: name.text, phone: phone.text,
              address: address.text, note: note.text)
          : await StoreDb.instance.updateSupplierDirectory(
              id: widget.supplier!['id'] as int, name: name.text,
              phone: phone.text, address: address.text, note: note.text);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) { showError(context, e); setState(() => saving = false); }
    }
  }
}

class DebtAdjustmentPage extends StatefulWidget {
  const DebtAdjustmentPage({super.key, required this.partyType,
      required this.partyId, required this.partyName,
      required this.currentDebt});
  final String partyType;
  final int partyId;
  final String partyName;
  final int currentDebt;

  @override
  State<DebtAdjustmentPage> createState() => _DebtAdjustmentPageState();
}

class _DebtAdjustmentPageState extends State<DebtAdjustmentPage> {
  final amount = TextEditingController();
  final note = TextEditingController();
  bool increase = false;
  bool saving = false;

  int get amountValue => int.tryParse(amount.text) ?? 0;
  int get newDebt {
    final value = widget.currentDebt + (increase ? amountValue : -amountValue);
    return value < 0 ? 0 : value;
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Điều chỉnh công nợ')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.partyName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            infoLine('Công nợ hiện tại', vnd(widget.currentDebt)),
          ],
        ))),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, icon: const Icon(Icons.payments),
                label: const Text('Giảm nợ / đã trả')),
            const ButtonSegment(value: true, icon: Icon(Icons.add_card),
                label: Text('Tăng công nợ')),
          ],
          selected: {increase},
          onSelectionChanged: (value) => setState(() => increase = value.first),
        ),
        const SizedBox(height: 16),
        TextField(controller: amount, keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Số tiền *'),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: note, maxLines: 3,
            decoration: InputDecoration(labelText: increase
                ? 'Lý do tăng nợ' : 'Ghi chú thanh toán / giảm nợ')),
        const SizedBox(height: 16),
        Card(color: const Color(0xFFF5F7FA), child: Padding(
          padding: const EdgeInsets.all(16),
          child: infoLine('Công nợ sau điều chỉnh', vnd(newDebt)),
        )),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: saving ? null : save,
            icon: const Icon(Icons.save), label: const Text('Lưu điều chỉnh')),
      ]),
    );
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await StoreDb.instance.addDebtAdjustment(
        partyType: widget.partyType, partyId: widget.partyId,
        amount: amountValue, increase: increase,
        currentDebt: widget.currentDebt, note: note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { showError(context, e); setState(() => saving = false); }
    }
  }
}

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String search = '';
  String sort = 'recent';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Khách hàng')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add, icon: const Icon(Icons.person_add),
      label: const Text('Thêm khách')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.customers(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final allRows = snap.data!;
        final rows = allRows.where((row) =>
            '${row['customer']} ${row['phone']}'.toLowerCase()
                .contains(search)).toList();
        int number(Map<String, Object?> row, String key) =>
            (row[key] as num? ?? 0).toInt();
        if (sort == 'spent') {
          rows.sort((a, b) => number(b, 'total_spent')
              .compareTo(number(a, 'total_spent')));
        } else if (sort == 'count') {
          rows.sort((a, b) => number(b, 'invoice_count')
              .compareTo(number(a, 'invoice_count')));
        } else if (sort == 'quantity') {
          rows.sort((a, b) => number(b, 'item_quantity')
              .compareTo(number(a, 'item_quantity')));
        }
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                  hintText: 'Tìm tên hoặc số điện thoại'),
              onChanged: (value) => setState(() => search = value.trim().toLowerCase()),
            )),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: sort,
              decoration: const InputDecoration(labelText: 'Sắp xếp để tri ân'),
              items: const [
                DropdownMenuItem(value: 'recent', child: Text('Giao dịch gần đây')),
                DropdownMenuItem(value: 'count', child: Text('Mua nhiều lần nhất')),
                DropdownMenuItem(value: 'quantity', child: Text('Mua nhiều sản phẩm nhất')),
                DropdownMenuItem(value: 'spent', child: Text('Chi tiêu cao nhất')),
              ],
              onChanged: (value) => setState(() => sort = value ?? 'recent'),
            )),
          const SizedBox(height: 8),
          Expanded(child: allRows.isEmpty
              ? const EmptyState(Icons.people_outline, 'Chưa có khách hàng',
                  'Thêm khách tại đây hoặc khi bán hàng/nhận sửa chữa.')
              : rows.isEmpty
                  ? const Center(child: Text('Không tìm thấy khách hàng'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final invoices = number(r, 'invoice_count');
                        final quantity = number(r, 'item_quantity');
                        return Card(child: ListTile(
                          leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text('${r['customer']}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${'${r['phone']}'.trim().isEmpty ? 'Không ghi SĐT' : r['phone']}\n'
                              '$invoices lần mua • $quantity sản phẩm • ${number(r, 'service_count')} lần sửa\n'
                              'Tổng giao dịch: ${vnd(number(r, 'total_spent'))}'),
                          isThreeLine: true,
                          trailing: number(r, 'debt') > 0
                              ? Text('Nợ\n${vnd(number(r, 'debt'))}', textAlign: TextAlign.right,
                                  style: const TextStyle(color: Colors.orange,
                                      fontWeight: FontWeight.bold))
                              : const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => CustomerDetailPage(customer: r)));
                            if (mounted) setState(() {});
                          },
                        ));
                      },
                    )),
        ]);
      },
    ),
  );

  Future<void> add() async {
    final created = await Navigator.push<Map<String, Object?>>(context,
        MaterialPageRoute(builder: (_) => const CustomerFormPage()));
    if (created != null && mounted) setState(() {});
  }
}

class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({super.key, required this.customer});
  final Map<String, Object?> customer;
  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late Map<String, Object?> customer = widget.customer;

  int n(String key) => (customer[key] as num? ?? 0).toInt();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${customer['customer']}'), actions: [
      IconButton(onPressed: edit, icon: const Icon(Icons.edit_outlined),
          tooltip: 'Sửa khách hàng'),
    ]),
    body: FutureBuilder<List<Object?>>(
      future: Future.wait<Object?>([
        StoreDb.instance.customerSales('${customer['customer']}', '${customer['phone']}'),
        StoreDb.instance.customerRepairs('${customer['customer']}', '${customer['phone']}'),
        StoreDb.instance.debtAdjustments('customer', customer['id'] as int),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final sales = snap.data![0] as List<Map<String, Object?>>;
        final repairs = snap.data![1] as List<Map<String, Object?>>;
        final adjustments = snap.data![2] as List<Map<String, Object?>>;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${customer['customer']}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              infoLine('Số điện thoại', textOrDash(customer['phone'])),
              infoLine('Số lần mua', '${n('invoice_count')}'),
              infoLine('Số hàng đã mua', '${n('item_quantity')} sản phẩm'),
              infoLine('Tiền mua hàng', vnd(n('sale_value'))),
              infoLine('Số lần sửa chữa', '${n('service_count')}'),
              infoLine('Tổng giao dịch', vnd(n('total_spent'))),
              infoLine('Còn nợ', vnd(n('debt'))),
              infoLine('Lần gần nhất', formatDateTime(customer['last_purchase'])),
              if ('${customer['note']}'.trim().isNotEmpty)
                infoLine('Ghi chú tri ân', '${customer['note']}'),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: adjustDebt, icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Điều chỉnh công nợ'),
              )),
            ],
          ))),
          const SizedBox(height: 16),
          Text('Lịch sử công nợ (${adjustments.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (adjustments.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16),
                child: Text('Chưa có lần điều chỉnh công nợ.'))),
          ...adjustments.map((entry) {
            final delta = (entry['amount_delta'] as num).toInt();
            return Padding(padding: const EdgeInsets.only(bottom: 8),
              child: Card(child: ListTile(
                leading: CircleAvatar(child: Icon(delta > 0
                    ? Icons.add_card : Icons.payments)),
                title: Text(delta > 0
                    ? 'Tăng nợ ${vnd(delta)}'
                    : 'Giảm nợ ${vnd(-delta)}',
                    style: TextStyle(fontWeight: FontWeight.bold,
                        color: delta > 0 ? Colors.orange : Colors.green)),
                subtitle: Text('${formatDateTime(entry['created_at'])}'
                    '${'${entry['note']}'.trim().isEmpty ? '' : '\n${entry['note']}'}'),
                isThreeLine: '${entry['note']}'.trim().isNotEmpty,
              )));
          }),
          const SizedBox(height: 10),
          Text('Lịch sử mua hàng (${sales.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (sales.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16),
                child: Text('Khách chưa có hóa đơn mua hàng.'))),
          ...sales.map((sale) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
              title: Text('${sale['code']} • ${vnd(sale['total'] as num)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${formatDateTime(sale['created_at'])}\n'
                  '${sale['product_names'] ?? 'Hàng hóa'} • ${sale['item_quantity']} sản phẩm'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => InvoiceDetailPage(saleId: sale['id'] as int))),
            )),
          )),
          const SizedBox(height: 10),
          Text('Lịch sử sửa chữa (${repairs.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (repairs.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16),
                child: Text('Khách chưa có phiếu sửa chữa.'))),
          ...repairs.map((repair) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.build)),
              title: Text('${repair['device']} • ${vnd(repair['amount'] as num)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${repair['code']} • ${formatDateTime(repair['received_at'])}\n'
                  '${repairStatus('${repair['status']}')}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => RepairDetailPage(repair: repair))),
            )),
          )),
        ]);
      },
    ),
  );

  Future<void> edit() async {
    final changed = await Navigator.push<Map<String, Object?>>(context,
        MaterialPageRoute(builder: (_) => CustomerFormPage(customer: customer)));
    if (changed == null) return;
    final rows = await StoreDb.instance.customers();
    final fresh = rows.where((row) => row['id'] == changed['id']);
    if (fresh.isNotEmpty && mounted) setState(() => customer = fresh.first);
  }

  Future<void> adjustDebt() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => DebtAdjustmentPage(
        partyType: 'customer', partyId: customer['id'] as int,
        partyName: '${customer['customer']}', currentDebt: n('debt'),
      ),
    ));
    if (changed != true) return;
    final rows = await StoreDb.instance.customers();
    final fresh = rows.where((row) => row['id'] == customer['id']);
    if (fresh.isNotEmpty && mounted) setState(() => customer = fresh.first);
  }
}

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});
  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String search = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nhà cung cấp')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add, icon: const Icon(Icons.add_business),
      label: const Text('Thêm nhà cung cấp')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
              hintText: 'Tìm tên hoặc số điện thoại'),
          onChanged: (value) => setState(() => search = value.trim().toLowerCase()),
        )),
      Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
        future: StoreDb.instance.suppliers(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final allRows = snap.data!;
          final rows = allRows.where((row) =>
              '${row['supplier_name']} ${row['phone']}'.toLowerCase()
                  .contains(search)).toList();
          if (allRows.isEmpty) return const EmptyState(
              Icons.local_shipping_outlined, 'Chưa có nhà cung cấp',
              'Thêm tại đây hoặc ngay khi lập phiếu nhập hàng.');
          if (rows.isEmpty) return const Center(child: Text('Không tìm thấy nhà cung cấp'));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = rows[i];
              final debt = (r['debt'] as num? ?? 0).toInt();
              return Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
                title: Text('${r['supplier_name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${r['purchase_count']} lần nhập • ${r['total_quantity']} sản phẩm\n'
                    'Tổng đã nhập: ${vnd(r['total_purchase'] as num)}\n'
                    'Gần nhất: ${formatDateTime(r['last_purchase'])}'),
                isThreeLine: true,
                trailing: debt > 0
                    ? Text('Còn nợ\n${vnd(debt)}', textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.orange,
                            fontWeight: FontWeight.bold))
                    : const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SupplierDetailPage(supplier: r)));
                  if (mounted) setState(() {});
                },
              ));
            },
          );
        },
      )),
    ]),
  );

  Future<void> add() async {
    final created = await Navigator.push<Map<String, Object?>>(context,
        MaterialPageRoute(builder: (_) => const SupplierFormPage()));
    if (created != null && mounted) setState(() {});
  }
}

class SupplierDetailPage extends StatefulWidget {
  const SupplierDetailPage({super.key, required this.supplier});
  final Map<String, Object?> supplier;
  @override
  State<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  late Map<String, Object?> supplier = widget.supplier;
  int n(String key) => (supplier[key] as num? ?? 0).toInt();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${supplier['supplier_name']}'), actions: [
      IconButton(onPressed: edit, icon: const Icon(Icons.edit_outlined),
          tooltip: 'Sửa nhà cung cấp'),
    ]),
    body: FutureBuilder<List<Object?>>(
      future: Future.wait<Object?>([
        StoreDb.instance.supplierPurchases('${supplier['supplier_name']}'),
        StoreDb.instance.debtAdjustments('supplier', supplier['id'] as int),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data![0] as List<Map<String, Object?>>;
        final adjustments = snap.data![1] as List<Map<String, Object?>>;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${supplier['supplier_name']}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              infoLine('Số điện thoại', textOrDash(supplier['phone'])),
              infoLine('Địa chỉ', textOrDash(supplier['address'])),
              infoLine('Số lần nhập', '${n('purchase_count')}'),
              infoLine('Số hàng đã nhập', '${n('total_quantity')} sản phẩm'),
              infoLine('Tổng tiền nhập', vnd(n('total_purchase'))),
              infoLine('Còn nợ NCC', vnd(n('debt'))),
              infoLine('Lần gần nhất', formatDateTime(supplier['last_purchase'])),
              if ('${supplier['note']}'.trim().isNotEmpty)
                infoLine('Ghi chú', '${supplier['note']}'),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: adjustDebt, icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Điều chỉnh công nợ'),
              )),
            ],
          ))),
          const SizedBox(height: 16),
          Text('Lịch sử công nợ (${adjustments.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (adjustments.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16),
                child: Text('Chưa có lần điều chỉnh công nợ.'))),
          ...adjustments.map((entry) {
            final delta = (entry['amount_delta'] as num).toInt();
            return Padding(padding: const EdgeInsets.only(bottom: 8),
              child: Card(child: ListTile(
                leading: CircleAvatar(child: Icon(delta > 0
                    ? Icons.add_card : Icons.payments)),
                title: Text(delta > 0
                    ? 'Tăng nợ ${vnd(delta)}'
                    : 'Đã trả / giảm nợ ${vnd(-delta)}',
                    style: TextStyle(fontWeight: FontWeight.bold,
                        color: delta > 0 ? Colors.orange : Colors.green)),
                subtitle: Text('${formatDateTime(entry['created_at'])}'
                    '${'${entry['note']}'.trim().isEmpty ? '' : '\n${entry['note']}'}'),
                isThreeLine: '${entry['note']}'.trim().isNotEmpty,
              )));
          }),
          const SizedBox(height: 10),
          Text('Lịch sử nhập hàng (${rows.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16),
                child: Text('Chưa có phiếu nhập từ nhà cung cấp này.'))),
          ...rows.map((purchase) {
            final total = (purchase['total'] as num? ?? 0).toInt();
            final paid = (purchase['paid'] as num? ?? 0).toInt();
            return Padding(padding: const EdgeInsets.only(bottom: 8),
              child: Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.inventory)),
                title: Text('${purchase['code']} • ${vnd(total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${formatDateTime(purchase['created_at'])}\n'
                    '${purchase['product_names'] ?? 'Hàng hóa'}\n'
                    '${purchase['total_quantity']} sản phẩm • Đã trả ${vnd(paid)}'),
                isThreeLine: true,
                trailing: total > paid
                    ? Text('Nợ ${vnd(total - paid)}',
                        style: const TextStyle(color: Colors.orange,
                            fontWeight: FontWeight.bold))
                    : const Icon(Icons.check_circle, color: Colors.green),
              )));
          }),
        ]);
      },
    ),
  );

  Future<void> edit() async {
    final changed = await Navigator.push<Map<String, Object?>>(context,
        MaterialPageRoute(builder: (_) => SupplierFormPage(supplier: supplier)));
    if (changed == null) return;
    final rows = await StoreDb.instance.suppliers();
    final fresh = rows.where((row) => row['id'] == changed['id']);
    if (fresh.isNotEmpty && mounted) setState(() => supplier = fresh.first);
  }

  Future<void> adjustDebt() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => DebtAdjustmentPage(
        partyType: 'supplier', partyId: supplier['id'] as int,
        partyName: '${supplier['supplier_name']}', currentDebt: n('debt'),
      ),
    ));
    if (changed != true) return;
    final rows = await StoreDb.instance.suppliers();
    final fresh = rows.where((row) => row['id'] == supplier['id']);
    if (fresh.isNotEmpty && mounted) setState(() => supplier = fresh.first);
  }
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
  const RepairForm({super.key, this.repair});
  final Map<String, Object?>? repair;

  @override
  State<RepairForm> createState() => _RepairFormState();
}

class _RepairFormState extends State<RepairForm> {
  late final TextEditingController customer;
  late final TextEditingController phone;
  late final TextEditingController device;
  late final TextEditingController imei;
  late final TextEditingController issue;
  late final TextEditingController amount;
  late final TextEditingController partsCost;
  late final TextEditingController paid;
  late final TextEditingController note;
  List<Map<String, Object?>> customers = [];
  int selectedCustomerId = 0;
  bool saving = false;

  bool get editing => widget.repair != null;

  @override
  void initState() {
    super.initState();
    final r = widget.repair;
    customer = TextEditingController(text: '${r?['customer'] ?? ''}');
    phone = TextEditingController(text: '${r?['phone'] ?? ''}');
    device = TextEditingController(text: '${r?['device'] ?? ''}');
    imei = TextEditingController(text: '${r?['imei'] ?? ''}');
    issue = TextEditingController(text: '${r?['issue'] ?? ''}');
    amount = TextEditingController(text: r == null ? '' : '${r['amount']}');
    partsCost =
        TextEditingController(text: r == null ? '' : '${r['parts_cost']}');
    paid = TextEditingController(text: r == null ? '' : '${r['paid']}');
    note = TextEditingController(text: '${r?['note'] ?? ''}');
    _loadCustomers();
  }

  @override
  void dispose() {
    customer.dispose();
    phone.dispose();
    device.dispose();
    imei.dispose();
    issue.dispose();
    amount.dispose();
    partsCost.dispose();
    paid.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers({int? selectId}) async {
    final rows = await StoreDb.instance.customerDirectory();
    if (!mounted) return;
    var resolvedId = selectId ?? selectedCustomerId;
    if (selectId == null && editing) {
      for (final row in rows) {
        final samePhone = phone.text.trim().isNotEmpty &&
            '${row['phone']}'.trim() == phone.text.trim();
        final sameName = '${row['name']}'.trim().toLowerCase() ==
            customer.text.trim().toLowerCase();
        if (samePhone || sameName) {
          resolvedId = row['id'] as int;
          break;
        }
      }
    }
    setState(() {
      customers = rows;
      selectedCustomerId = resolvedId;
      if (selectId != null) {
        final selected = rows.where((row) => row['id'] == selectId);
        if (selected.isNotEmpty) {
          customer.text = '${selected.first['name']}';
          phone.text = '${selected.first['phone']}';
        }
      }
    });
  }

  Future<void> _pickCustomer(int? id) async {
    if (id == null) return;
    if (id == -1) {
      final created = await Navigator.push<Map<String, Object?>>(context,
          MaterialPageRoute(builder: (_) => const CustomerFormPage()));
      if (created != null) {
        await _loadCustomers(selectId: created['id'] as int);
      }
      return;
    }
    setState(() {
      selectedCustomerId = id;
      final selected = customers.where((row) => row['id'] == id);
      customer.text =
          id == 0 || selected.isEmpty ? '' : '${selected.first['name']}';
      phone.text =
          id == 0 || selected.isEmpty ? '' : '${selected.first['phone']}';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(editing ? 'Sửa phiếu sửa chữa' : 'Nhận máy sửa chữa')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<int>(
            key: ValueKey(
                'repair-customer-$selectedCustomerId-${customers.length}'),
            initialValue: selectedCustomerId,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Chọn nhanh khách hàng',
                prefixIcon: Icon(Icons.person_search)),
            items: [
              const DropdownMenuItem(value: 0, child: Text('Khách lẻ / nhập tay')),
              ...customers.map((row) => DropdownMenuItem(
                  value: row['id'] as int,
                  child: Text(
                      '${row['name']}${'${row['phone']}'.trim().isEmpty ? '' : ' • ${row['phone']}'}'))),
              const DropdownMenuItem(
                  value: -1, child: Text('+ Thêm khách hàng mới')),
            ],
            onChanged: _pickCustomer,
          ),
          const SizedBox(height: 12),
          TextField(
              controller: customer,
              decoration: const InputDecoration(labelText: 'Tên khách hàng')),
          const SizedBox(height: 12),
          TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Số điện thoại')),
          const SizedBox(height: 12),
          TextField(
              controller: device,
              decoration: const InputDecoration(labelText: 'Tên máy *')),
          const SizedBox(height: 12),
          TextField(
              controller: imei,
              decoration: const InputDecoration(labelText: 'IMEI')),
          const SizedBox(height: 12),
          TextField(
              controller: issue,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Tình trạng lỗi *')),
          const SizedBox(height: 12),
          TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Giá sửa dự kiến')),
          const SizedBox(height: 12),
          TextField(
              controller: partsCost,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Tiền linh kiện / giá vốn')),
          const SizedBox(height: 12),
          TextField(
              controller: paid,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Khách đã thanh toán')),
          const SizedBox(height: 12),
          TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Ghi chú')),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.save),
              label: Text(editing
                  ? 'Lưu thay đổi'
                  : 'Lưu phiếu nhận máy')),
        ]),
      );

  Future<void> save() async {
    setState(() => saving = true);
    try {
      if (editing) {
        await StoreDb.instance.updateRepair(
          id: widget.repair!['id'] as int,
          customer: customer.text,
          phone: phone.text,
          device: device.text,
          imei: imei.text,
          issue: issue.text,
          amount: int.tryParse(amount.text) ?? 0,
          partsCost: int.tryParse(partsCost.text) ?? 0,
          paid: int.tryParse(paid.text) ?? 0,
          note: note.text,
        );
      } else {
        await StoreDb.instance.addRepair(
          customer: customer.text,
          phone: phone.text,
          device: device.text,
          imei: imei.text,
          issue: issue.text,
          amount: int.tryParse(amount.text) ?? 0,
          partsCost: int.tryParse(partsCost.text) ?? 0,
          paid: int.tryParse(paid.text) ?? 0,
          note: note.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => saving = false);
      }
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
  late Map<String, Object?> repair = widget.repair;
  late String status = '${widget.repair['status']}';
  bool changed = false;

  Future<void> reload() async {
    final fresh = await StoreDb.instance.repair(repair['id'] as int);
    if (!mounted) return;
    setState(() {
      repair = fresh;
      status = '${fresh['status']}';
      changed = true;
    });
  }

  Future<void> edit() async {
    final saved = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => RepairForm(repair: repair)));
    if (saved == true) await reload();
  }

  Future<void> remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa phiếu sửa chữa?'),
        content: const Text(
            'Phiếu sẽ bị xóa hẳn. Báo cáo doanh thu và lợi nhuận sẽ tự tính lại theo các phiếu còn lại.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xóa hẳn')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await StoreDb.instance.deleteRepair(repair['id'] as int);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = repair;
    final receipt = ReceiptDocument.repair(r, status);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        appBar: AppBar(
          title: Text('${r['code']}'),
          actions: [
            IconButton(
                tooltip: 'Sửa phiếu',
                onPressed: edit,
                icon: const Icon(Icons.edit)),
            IconButton(
                tooltip: 'Xóa phiếu',
                onPressed: remove,
                icon: const Icon(Icons.delete_outline, color: Colors.red)),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          FilledButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        ReceiptPreviewPage(receipt: receipt))),
            icon: const Icon(Icons.print),
            label: const Text('In / chia sẻ phiếu sửa chữa'),
          ),
          const SizedBox(height: 12),
          Card(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['device']}',
                      style: const TextStyle(
                          fontSize: 23, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  infoLine('Khách hàng', '${r['customer']}'),
                  infoLine(
                      'Số điện thoại',
                      '${r['phone']}'.trim().isEmpty
                          ? 'Không ghi'
                          : '${r['phone']}'),
                  infoLine(
                      'IMEI',
                      '${r['imei']}'.trim().isEmpty
                          ? 'Không ghi'
                          : '${r['imei']}'),
                  infoLine('Ngày nhận', formatDateTime(r['received_at'])),
                  infoLine('Tình trạng', '${r['issue']}'),
                  infoLine(
                      'Ghi chú',
                      '${r['note']}'.trim().isEmpty
                          ? 'Không có'
                          : '${r['note']}'),
                ]),
          )),
          const SizedBox(height: 12),
          Card(
              child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Chi phí',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  infoLine('Tiền sửa', vnd(r['amount'] as int)),
                  infoLine('Giá vốn', vnd(r['parts_cost'] as int)),
                  infoLine(
                      'Lợi nhuận dự kiến',
                      vnd((r['amount'] as int) -
                          (r['parts_cost'] as int))),
                  infoLine('Đã thu', vnd(r['paid'] as int)),
                  infoLine(
                      'Khách còn nợ',
                      vnd((r['amount'] as int) -
                          (r['paid'] as int))),
                ]),
          )),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('repair-status-$status'),
            initialValue: status,
            decoration:
                const InputDecoration(labelText: 'Trạng thái phiếu'),
            items: const [
              'received',
              'repairing',
              'completed',
              'returned',
              'cancelled'
            ]
                .map((value) => DropdownMenuItem(
                    value: value, child: Text(repairStatus(value))))
                .toList(),
            onChanged: (value) async {
              if (value == null) return;
              await StoreDb.instance
                  .updateRepairStatus(r['id'] as int, value);
              await reload();
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
              onPressed: () => Navigator.pop(context, changed),
              child: const Text('Xong')),
        ]),
      ),
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
    final active =
        months > 0 && end != null && !DateTime.now().isAfter(end);
    final receipt = ReceiptDocument.warranty(w);
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý bảo hành')),
      floatingActionButton: active
          ? FloatingActionButton.extended(
              onPressed: addClaim,
              icon: const Icon(Icons.add),
              label: const Text('Tiếp nhận bảo hành'))
          : null,
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ReceiptPreviewPage(receipt: receipt))),
              icon: const Icon(Icons.print),
              label: const Text('In / chia sẻ phiếu bảo hành'),
            ),
            const SizedBox(height: 12),
            if (!active)
              Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(months <= 0
                              ? 'Hóa đơn này không có thời hạn bảo hành.'
                              : 'Sản phẩm đã hết thời hạn bảo hành.')),
                    ]),
                  )),
            if (!active) const SizedBox(height: 12),
            Card(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${w['product_name']}',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    infoLine('Khách hàng', '${w['customer']}'),
                    infoLine(
                        'Số điện thoại',
                        '${w['phone']}'.trim().isEmpty
                            ? 'Không ghi'
                            : '${w['phone']}'),
                    infoLine(
                        'IMEI',
                        '${w['imei']}'.trim().isEmpty || w['imei'] == null
                            ? 'Không ghi'
                            : '${w['imei']}'),
                    infoLine('Hóa đơn', '${w['code']}'),
                    infoLine('Ngày bán', formatDateTime(w['created_at'])),
                    infoLine('Thời hạn', warrantyLabel(months)),
                    infoLine(
                        'Hết hạn',
                        months <= 0
                            ? 'Không có'
                            : end == null
                                ? 'Không rõ'
                                : DateFormat('dd/MM/yyyy').format(end)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => InvoiceDetailPage(
                                  saleId: w['sale_id'] as int))),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Xem hóa đơn gốc'),
                    ),
                  ]),
            )),
            const SizedBox(height: 16),
            const Text('Lịch sử tiếp nhận',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, Object?>>>(
              future: StoreDb.instance
                  .warrantyClaims(w['sale_item_id'] as int),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data!;
                if (rows.isEmpty) {
                  return const Card(
                      child: Padding(
                          padding: EdgeInsets.all(20),
                          child:
                              Text('Chưa có lần tiếp nhận bảo hành nào.')));
                }
                return Column(
                    children: rows
                        .map((r) => Card(
                                child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                          child: Text('${r['issue']}',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      IconButton(
                                          tooltip: 'Sửa phiếu bảo hành',
                                          onPressed: () => editClaim(r),
                                          icon: const Icon(Icons.edit_outlined)),
                                      IconButton(
                                          tooltip: 'Xóa phiếu bảo hành',
                                          onPressed: () => deleteClaim(r),
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.red)),
                                    ]),
                                    Text(
                                        'Ngày nhận: ${formatDateTime(r['received_at'])}'),
                                    if ('${r['note']}'.trim().isNotEmpty)
                                      Text('Ghi chú: ${r['note']}'),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                          'warranty-status-${r['id']}-${r['status']}'),
                                      initialValue: '${r['status']}',
                                      decoration: const InputDecoration(
                                          labelText: 'Trạng thái'),
                                      items: const [
                                        'received',
                                        'processing',
                                        'waiting_parts',
                                        'completed',
                                        'returned'
                                      ]
                                          .map((value) => DropdownMenuItem(
                                              value: value,
                                              child: Text(
                                                  warrantyStatus(value))))
                                          .toList(),
                                      onChanged: (value) async {
                                        if (value == null) return;
                                        await StoreDb.instance
                                            .updateWarrantyClaimStatus(
                                                r['id'] as int, value);
                                        if (mounted) setState(() {});
                                      },
                                    ),
                                  ]),
                            )))
                        .toList());
              },
            ),
          ]),
    );
  }

  Future<void> addClaim() async {
    final issue = TextEditingController();
    final note = TextEditingController();
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Tiếp nhận bảo hành'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: issue,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Tình trạng máy *')),
                const SizedBox(height: 12),
                TextField(
                    controller: note,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Ghi chú')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Hủy')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, {
                          'issue': issue.text,
                          'note': note.text,
                        }),
                    child: const Text('Tiếp nhận')),
              ],
            ));
    issue.dispose();
    note.dispose();
    if (result == null) return;
    try {
      await StoreDb.instance.addWarrantyClaim(
          saleItemId: widget.warranty['sale_item_id'] as int,
          issue: result['issue'] ?? '',
          note: result['note'] ?? '');
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> editClaim(Map<String, Object?> claim) async {
    final issue = TextEditingController(text: '${claim['issue']}');
    final note = TextEditingController(text: '${claim['note']}');
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Sửa phiếu bảo hành'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: issue,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Tình trạng máy *')),
                const SizedBox(height: 12),
                TextField(
                    controller: note,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Ghi chú')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Hủy')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, {
                          'issue': issue.text,
                          'note': note.text,
                        }),
                    child: const Text('Lưu thay đổi')),
              ],
            ));
    issue.dispose();
    note.dispose();
    if (result == null) return;
    try {
      await StoreDb.instance.updateWarrantyClaim(
        id: claim['id'] as int,
        issue: result['issue'] ?? '',
        note: result['note'] ?? '',
        status: '${claim['status']}',
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> deleteClaim(Map<String, Object?> claim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa phiếu bảo hành?'),
        content: const Text(
            'Lần tiếp nhận này sẽ bị xóa hẳn. Thao tác không ảnh hưởng doanh thu và lợi nhuận.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xóa hẳn')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await StoreDb.instance.deleteWarrantyClaim(claim['id'] as int);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
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

class ReceiptItem {
  const ReceiptItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.detail = '',
  });

  final String name;
  final String detail;
  final int quantity;
  final int unitPrice;
}

class ReceiptDocument {
  const ReceiptDocument({
    required this.title,
    required this.code,
    required this.date,
    required this.details,
    this.items = const [],
    this.totals = const [],
    this.note = '',
  });

  final String title;
  final String code;
  final String date;
  final List<MapEntry<String, String>> details;
  final List<ReceiptItem> items;
  final List<MapEntry<String, String>> totals;
  final String note;

  String get fileName => 'Phieu_$code.pdf';

  factory ReceiptDocument.invoice(
      Map<String, Object?> sale, List<Map<String, Object?>> rows) {
    final months = sale['warranty_months'] as int;
    final soldAt = parseDate(sale['created_at']);
    final discountTotal = (sale['discount_total'] as num? ?? 0).toInt();
    return ReceiptDocument(
      title: 'HÓA ĐƠN BÁN HÀNG',
      code: '${sale['code']}',
      date: formatDateTime(sale['created_at']),
      details: [
        MapEntry('Khách hàng', '${sale['customer']}'),
        MapEntry('Điện thoại', textOrDash(sale['phone'])),
        MapEntry('Trạng thái',
            sale['status'] == 'cancelled' ? 'ĐÃ HỦY' : 'Hoàn thành'),
      ],
      items: rows.map((item) => ReceiptItem(
        name: '${item['product_name']}',
        detail: [
          if (item['imei'] != null && '${item['imei']}'.trim().isNotEmpty)
            'IMEI: ${item['imei']}',
          if (item['color'] != null && '${item['color']}'.trim().isNotEmpty)
            'Màu: ${item['color']}',
        ].join(' • '),
        quantity: (item['quantity'] as num).toInt(),
        unitPrice: (item['unit_price'] as num).toInt(),
      )).toList(),
      totals: [
        if (discountTotal > 0) ...[
          MapEntry('Tạm tính', vnd((sale['total'] as int) + discountTotal)),
          MapEntry('Giảm giá', '-${vnd(discountTotal)}'),
        ],
        MapEntry('TỔNG TIỀN', vnd(sale['total'] as int)),
        MapEntry('Tiền mặt', vnd(sale['paid_cash'] as int)),
        MapEntry('Chuyển khoản', vnd(sale['paid_transfer'] as int)),
        MapEntry('Còn nợ', vnd(sale['debt'] as int)),
      ],
      note: months <= 0
          ? 'Sản phẩm không có bảo hành.'
          : 'Bảo hành ${warrantyLabel(months)}${soldAt == null ? '' : ', đến ${DateFormat('dd/MM/yyyy').format(addMonths(soldAt, months))}'}.'
              ' Vui lòng giữ phiếu và IMEI còn nguyên vẹn.',
    );
  }

  factory ReceiptDocument.repair(Map<String, Object?> repair, String status) {
    final amount = (repair['amount'] as num).toInt();
    final paid = (repair['paid'] as num).toInt();
    return ReceiptDocument(
      title: 'PHIẾU SỬA CHỮA',
      code: '${repair['code']}',
      date: formatDateTime(repair['received_at']),
      details: [
        MapEntry('Khách hàng', textOrDash(repair['customer'])),
        MapEntry('Điện thoại', textOrDash(repair['phone'])),
        MapEntry('Thiết bị', '${repair['device']}'),
        MapEntry('IMEI', textOrDash(repair['imei'])),
        MapEntry('Tình trạng', '${repair['issue']}'),
        MapEntry('Trạng thái', repairStatus(status)),
      ],
      totals: [
        MapEntry('Tiền sửa dự kiến', vnd(amount)),
        MapEntry('Đã thanh toán', vnd(paid)),
        MapEntry('Còn lại', vnd(amount - paid)),
      ],
      note: '${repair['note']}'.trim().isEmpty
          ? 'Khách hàng vui lòng kiểm tra kỹ thiết bị khi nhận lại máy.'
          : 'Ghi chú: ${repair['note']}\nKhách hàng vui lòng kiểm tra kỹ thiết bị khi nhận lại máy.',
    );
  }

  factory ReceiptDocument.warranty(Map<String, Object?> warranty) {
    final months = (warranty['warranty_months'] as num).toInt();
    final soldAt = parseDate(warranty['created_at']);
    final expires =
        soldAt == null || months <= 0 ? null : addMonths(soldAt, months);
    return ReceiptDocument(
      title: 'PHIẾU BẢO HÀNH',
      code: '${warranty['code']}',
      date: formatDateTime(warranty['created_at']),
      details: [
        MapEntry('Khách hàng', textOrDash(warranty['customer'])),
        MapEntry('Điện thoại', textOrDash(warranty['phone'])),
        MapEntry('Sản phẩm', '${warranty['product_name']}'),
        MapEntry('IMEI', textOrDash(warranty['imei'])),
        MapEntry('Thời hạn', warrantyLabel(months)),
        MapEntry('Hết hạn', expires == null
            ? 'Không có'
            : DateFormat('dd/MM/yyyy').format(expires)),
      ],
      note: 'Điều kiện bảo hành: máy còn nguyên tem và IMEI, không rơi vỡ, '
          'không vào nước, không tự ý tháo sửa. Vui lòng mang theo phiếu khi bảo hành.',
    );
  }

  factory ReceiptDocument.test() => ReceiptDocument(
    title: 'PHIẾU IN THỬ K80',
    code: 'TEST-${DateFormat('HHmmss').format(DateTime.now())}',
    date: formatDateTime(DateTime.now().toIso8601String()),
    details: const [
      MapEntry('Kết nối', 'Thành công'),
      MapEntry('Khổ giấy', 'K80 / 80 mm'),
    ],
    note: 'Nếu chữ và đường kẻ rõ ràng, máy in đã sẵn sàng sử dụng.',
  );
}

String textOrDash(Object? value) {
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty ? 'Không ghi' : text;
}

class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper({super.key, required this.receipt, this.width = 360});
  final ReceiptDocument receipt;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
    child: DefaultTextStyle(
      style: const TextStyle(color: Colors.black, fontSize: 13, height: 1.25),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('MINH CẢNH MOBILE', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        const Text('196 Trung Hưng, Vũ Thư, Hưng Yên',
            textAlign: TextAlign.center),
        const Text('Điện thoại: 0889 486 662', textAlign: TextAlign.center),
        const SizedBox(height: 10),
        _receiptRule(),
        const SizedBox(height: 9),
        Text(receipt.title, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text('Mã phiếu: ${receipt.code}', textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(receipt.date, textAlign: TextAlign.center),
        const SizedBox(height: 9),
        _receiptRule(),
        const SizedBox(height: 7),
        ...receipt.details.map((line) => _ReceiptRow(line.key, line.value)),
        if (receipt.items.isNotEmpty) ...[
          const SizedBox(height: 7),
          _receiptRule(),
          const SizedBox(height: 7),
          const Align(alignment: Alignment.centerLeft,
              child: Text('HÀNG HÓA',
                  style: TextStyle(fontWeight: FontWeight.w900))),
          const SizedBox(height: 5),
          ...receipt.items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text(item.name,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              if (item.detail.isNotEmpty)
                Text(item.detail, style: const TextStyle(fontSize: 12)),
              Row(children: [
                Expanded(child: Text('${item.quantity} x ${vnd(item.unitPrice)}')),
                Text(vnd(item.quantity * item.unitPrice),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ]),
          )),
        ],
        if (receipt.totals.isNotEmpty) ...[
          _receiptRule(),
          const SizedBox(height: 6),
          ...receipt.totals.map((line) => _ReceiptRow(line.key, line.value,
              bold: line == receipt.totals.first)),
        ],
        if (receipt.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          _receiptRule(),
          const SizedBox(height: 7),
          Text(receipt.note, textAlign: TextAlign.left,
              style: const TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 18),
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text('Khách hàng\n(Ký, ghi rõ họ tên)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          Expanded(child: Text('Nhân viên\n(Ký, ghi rõ họ tên)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 42),
        const Text('Cảm ơn quý khách!', textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900)),
      ]),
    ),
  );
}

Widget _receiptRule() => Container(height: 1, color: Colors.black);

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 118, child: Text(label,
          style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w500))),
      Expanded(child: Text(value, textAlign: TextAlign.right,
          style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700))),
    ]),
  );
}

class ReceiptPrinter {
  static Future<Uint8List> render(
      BuildContext context, ReceiptDocument receipt) async {
    final controller = ScreenshotController();
    return controller.captureFromWidget(
      InheritedTheme.captureAll(
        context,
        Material(
          color: Colors.white,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: ReceiptPaper(receipt: receipt),
          ),
        ),
      ),
      delay: const Duration(milliseconds: 80),
      pixelRatio: 2,
    );
  }

  static Future<List<int>> thermalBytes(Uint8List png) async {
    final decoded = img.decodeImage(png);
    if (decoded == null) throw Exception('Không thể tạo ảnh phiếu in');
    final printable = img.copyResize(decoded, width: 576,
        interpolation: img.Interpolation.average);
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    return <int>[
      ...generator.reset(),
      ...generator.imageRaster(printable, align: PosAlign.center),
      ...generator.feed(3),
    ];
  }

  static Future<void> print(
      BuildContext context, ReceiptDocument receipt) async {
    final transport =
        await StoreDb.instance.getSetting('printer_transport') ?? 'lan';
    final savedCopies = int.tryParse(
        await StoreDb.instance.getSetting('printer_copies') ?? '1');
    final copies = (savedCopies ?? 1).clamp(1, 3);
    final png = await render(context, receipt);
    final bytes = await thermalBytes(png);

    if (transport == 'bluetooth') {
      final mac =
          await StoreDb.instance.getSetting('printer_bluetooth_mac') ?? '';
      if (mac.isEmpty) {
        throw Exception(
            'Chưa chọn máy in Bluetooth trong Cài đặt máy in K80');
      }
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        throw Exception('Bluetooth đang tắt. Hãy bật Bluetooth rồi thử lại');
      }
      var connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        connected =
            await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      }
      if (!connected) throw Exception('Không kết nối được máy in Bluetooth');
      for (var i = 0; i < copies; i++) {
        final ok = await PrintBluetoothThermal.writeBytes(bytes);
        if (!ok) throw Exception('Máy in Bluetooth không nhận dữ liệu');
      }
      return;
    }

    final host = await StoreDb.instance.getSetting('printer_lan_ip') ?? '';
    final port = int.tryParse(
        await StoreDb.instance.getSetting('printer_lan_port') ?? '9100') ?? 9100;
    if (host.trim().isEmpty) {
      throw Exception(
          'Chưa nhập địa chỉ IP máy in LAN trong Cài đặt máy in K80');
    }
    final socket = await Socket.connect(host.trim(), port,
        timeout: const Duration(seconds: 7));
    try {
      for (var i = 0; i < copies; i++) {
        socket.add(bytes);
        await socket.flush();
      }
    } finally {
      await socket.close();
    }
  }

  static Future<void> share(
      BuildContext context, ReceiptDocument receipt) async {
    final png = await render(context, receipt);
    final decoded = img.decodeImage(png);
    if (decoded == null) throw Exception('Không thể tạo tệp chia sẻ');
    final pageWidth = 80 * PdfPageFormat.mm;
    final printableWidth = pageWidth - 8 * PdfPageFormat.mm;
    final pageHeight = printableWidth * decoded.height / decoded.width +
        8 * PdfPageFormat.mm;
    final document = pw.Document();
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat(pageWidth, pageHeight,
          marginAll: 4 * PdfPageFormat.mm),
      build: (_) => pw.Center(
          child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)),
    ));
    final pdfBytes = await document.save();
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(pdfBytes, mimeType: 'application/pdf')],
      fileNameOverrides: [receipt.fileName],
      subject: '${receipt.title} ${receipt.code}',
      text: '${receipt.title} ${receipt.code} - Minh Cảnh Mobile',
    ));
  }
}

class ReceiptPreviewPage extends StatefulWidget {
  const ReceiptPreviewPage({super.key, required this.receipt});
  final ReceiptDocument receipt;
  @override
  State<ReceiptPreviewPage> createState() => _ReceiptPreviewPageState();
}

class _ReceiptPreviewPageState extends State<ReceiptPreviewPage> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - 32;
    final width = available < 360 ? available : 360.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Xem trước phiếu K80')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
            child: ReceiptPaper(receipt: widget.receipt, width: width)),
      ),
      bottomNavigationBar: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: busy ? null : share,
            icon: const Icon(Icons.share),
            label: const Text('Chia sẻ PDF'),
          )),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(
            onPressed: busy ? null : printReceipt,
            icon: busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print),
            label: Text(busy ? 'Đang xử lý' : 'In phiếu'),
          )),
        ]),
      )),
    );
  }

  Future<void> printReceipt() async {
    setState(() => busy = true);
    try {
      await ReceiptPrinter.print(context, widget.receipt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã gửi phiếu tới máy in')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> share() async {
    setState(() => busy = true);
    try {
      await ReceiptPrinter.share(context, widget.receipt);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }
}

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});
  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  String transport = 'lan';
  String bluetoothMac = '';
  String bluetoothName = '';
  int copies = 1;
  final ip = TextEditingController();
  final port = TextEditingController(text: '9100');
  List<BluetoothInfo> devices = [];
  bool loading = true;
  bool searching = false;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    ip.dispose();
    port.dispose();
    super.dispose();
  }

  Future<void> load() async {
    transport =
        await StoreDb.instance.getSetting('printer_transport') ?? 'lan';
    ip.text = await StoreDb.instance.getSetting('printer_lan_ip') ?? '';
    port.text =
        await StoreDb.instance.getSetting('printer_lan_port') ?? '9100';
    bluetoothMac =
        await StoreDb.instance.getSetting('printer_bluetooth_mac') ?? '';
    bluetoothName =
        await StoreDb.instance.getSetting('printer_bluetooth_name') ?? '';
    copies = int.tryParse(
        await StoreDb.instance.getSetting('printer_copies') ?? '1') ?? 1;
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cài đặt máy in K80')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Kiểu kết nối',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'lan', icon: Icon(Icons.lan),
                    label: Text('LAN / Wi-Fi')),
                ButtonSegment(value: 'bluetooth', icon: Icon(Icons.bluetooth),
                    label: Text('Bluetooth')),
              ],
              selected: {transport},
              onSelectionChanged: (value) =>
                  setState(() => transport = value.first),
            ),
            const SizedBox(height: 16),
            if (transport == 'lan') ...[
              Card(child: Padding(padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Máy in KiotViet dùng dây LAN',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                        'Điện thoại phải dùng Wi-Fi cùng bộ phát mạng với máy in.'),
                    const SizedBox(height: 14),
                    TextField(controller: ip,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'Địa chỉ IP máy in',
                            hintText: 'Ví dụ: 192.168.1.100')),
                    const SizedBox(height: 12),
                    TextField(controller: port,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Cổng in', hintText: '9100')),
                  ]))),
            ] else ...[
              Card(child: Padding(padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    const Text('Máy in cầm tay Bluetooth',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(bluetoothName.isEmpty
                        ? 'Chưa chọn máy in. Hãy ghép đôi máy trong Cài đặt Bluetooth của điện thoại trước.'
                        : 'Đã chọn: $bluetoothName\n$bluetoothMac'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: searching ? null : searchBluetooth,
                      icon: searching
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search),
                      label: Text(searching ? 'Đang tìm' : 'Tìm máy đã ghép đôi'),
                    ),
                    ...devices.map((device) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: device.macAdress,
                      groupValue: bluetoothMac,
                      title: Text(device.name.isEmpty
                          ? 'Máy in Bluetooth' : device.name),
                      subtitle: Text(device.macAdress),
                      onChanged: (value) => setState(() {
                        bluetoothMac = value ?? '';
                        bluetoothName = device.name.isEmpty
                            ? 'Máy in Bluetooth' : device.name;
                      }),
                    )),
                  ]))),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: copies,
              decoration: const InputDecoration(
                  labelText: 'Số liên mỗi lần in'),
              items: const [1, 2, 3].map((value) => DropdownMenuItem(
                  value: value, child: Text('$value liên'))).toList(),
              onChanged: (value) => setState(() => copies = value ?? 1),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: () async {
                try {
                  await save();
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
                icon: const Icon(Icons.save),
                label: const Text('Lưu cài đặt')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: testing ? null : testPrint,
              icon: testing
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print),
              label: Text(testing ? 'Đang in thử' : 'Lưu và in thử'),
            ),
          ]),
  );

  Future<void> searchBluetooth() async {
    setState(() => searching = true);
    try {
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        throw Exception('Bluetooth đang tắt. Hãy bật Bluetooth rồi thử lại');
      }
      final results = await PrintBluetoothThermal.pairedBluetooths;
      if (mounted) {
        setState(() => devices = results);
        if (results.isEmpty) {
          throw Exception(
              'Không thấy máy đã ghép đôi. Hãy ghép đôi máy in trong Cài đặt Bluetooth trước');
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => searching = false);
  }

  Future<void> save({bool notify = true}) async {
    final portValue = int.tryParse(port.text.trim());
    if (transport == 'lan' &&
        (ip.text.trim().isEmpty || portValue == null)) {
      throw Exception('Hãy nhập đúng IP và cổng máy in LAN');
    }
    if (transport == 'bluetooth' && bluetoothMac.isEmpty) {
      throw Exception('Hãy chọn máy in Bluetooth');
    }
    await StoreDb.instance.setSetting('printer_transport', transport);
    await StoreDb.instance.setSetting('printer_lan_ip', ip.text.trim());
    await StoreDb.instance.setSetting('printer_lan_port', port.text.trim());
    await StoreDb.instance
        .setSetting('printer_bluetooth_mac', bluetoothMac);
    await StoreDb.instance
        .setSetting('printer_bluetooth_name', bluetoothName);
    await StoreDb.instance.setSetting('printer_copies', '$copies');
    if (notify && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu cài đặt máy in')));
    }
  }

  Future<void> testPrint() async {
    setState(() => testing = true);
    try {
      await save(notify: false);
      if (mounted) {
        await ReceiptPrinter.print(context, ReceiptDocument.test());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã gửi phiếu in thử')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => testing = false);
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
