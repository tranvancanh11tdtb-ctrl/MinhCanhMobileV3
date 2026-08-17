import 'package:flutter/material.dart';
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
        home: const HomeShell(),
      );
}

class StoreDb {
  StoreDb._();
  static final instance = StoreDb._();
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final file = p.join(await getDatabasesPath(), 'minh_canh_mobile_v3.db');
    return openDatabase(file, version: 1, onConfigure: (db) async {
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
    });
  }

  Future<List<Map<String, Object?>>> products() async {
    final db = await database;
    return db.rawQuery('''SELECT p.*,
      CASE WHEN p.track_imei=1 THEN
        (SELECT COUNT(*) FROM serial_units s WHERE s.product_id=p.id AND s.status='in_stock')
      ELSE p.quantity END AS stock
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
    return db.query('sales', orderBy: 'id DESC');
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

  Future<Map<String, int>> dashboard() async {
    final db = await database;
    final rows = await db.rawQuery('''SELECT
      COALESCE(SUM(CASE WHEN status='completed' THEN total ELSE 0 END),0) revenue,
      COALESCE(SUM(CASE WHEN status='completed' THEN total-cost_total ELSE 0 END),0) profit,
      COALESCE(SUM(CASE WHEN status='completed' THEN debt ELSE 0 END),0) debt,
      COALESCE(SUM(CASE WHEN status='completed' THEN paid_cash+paid_transfer ELSE 0 END),0) fund,
      SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) invoices
      FROM sales''');
    final row = rows.single;
    return {for (final e in row.entries) e.key: (e.value as num).toInt()};
  }
}

class SerialDraft {
  SerialDraft({this.imei = '', this.color = '', this.conditionText = 'Mới', this.cost = 0});
  String imei;
  String color;
  String conditionText;
  int cost;
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
      MorePage(onChanged: refresh),
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
          final d = snap.data ?? {'revenue': 0, 'profit': 0, 'debt': 0, 'fund': 0, 'invoices': 0};
          return ListView(padding: const EdgeInsets.all(16), children: [
            const SizedBox(height: 8),
            const Text('Minh Cảnh Mobile', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Color(0xff0877d1))),
            const Text('Uy tín dẫn đầu – Chất lượng bền lâu'),
            const SizedBox(height: 20),
            const Text('Tổng quan', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
            final rows = (snap.data ?? []).where((p) => '${p['name']} ${p['code']}'.toLowerCase().contains(search)).toList();
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
      while (serials.length < quantity) serials.add(SerialDraft());
      while (serials.length > quantity) serials.removeLast();
    } else { serials.clear(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phiếu nhập hàng')),
    body: FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.products(), builder: (context, snap) {
      final products = snap.data ?? [];
      return ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<int>(
          initialValue: product?['id'] as int?, decoration: const InputDecoration(labelText: 'Chọn mẫu hàng *'),
          items: products.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']}'))).toList(),
          onChanged: (id) => setState(() { product = products.firstWhere((p) => p['id'] == id); _syncSerials(); }),
        ),
        const SizedBox(height: 12),
        TextFormField(initialValue: '$quantity', keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số lượng *'), onChanged: (v) => setState(() { quantity = int.tryParse(v) ?? 0; _syncSerials(); })),
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
          const Text('Số dòng IMEI phải đúng bằng số lượng nhập.'),
          const SizedBox(height: 8),
          ...List.generate(serials.length, (i) => SerialEditor(index: i, draft: serials[i])),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.check), label: const Text('Hoàn thành phiếu nhập')),
      ]);
    }),
  );

  Future<void> save() async {
    if (product == null) return showError(context, 'Hãy chọn mẫu hàng');
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
  const SerialEditor({super.key, required this.index, required this.draft});
  final int index;
  final SerialDraft draft;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Máy ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
        DropdownButtonFormField<int>(initialValue: warranty, decoration: const InputDecoration(labelText: 'Bảo hành'), items: const [DropdownMenuItem(value: 0, child: Text('Không bảo hành')), DropdownMenuItem(value: 3, child: Text('3 tháng')), DropdownMenuItem(value: 6, child: Text('6 tháng')), DropdownMenuItem(value: 9, child: Text('9 tháng')), DropdownMenuItem(value: 12, child: Text('12 tháng')), DropdownMenuItem(value: 24, child: Text('2 năm'))], onChanged: (v) => warranty = v!),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: saving ? null : complete, icon: const Icon(Icons.shopping_cart_checkout), label: const Text('Hoàn tất bán hàng')),
      ]);
    })),
  ]);

  Future<void> complete() async {
    if (product == null) return showError(context, 'Hãy chọn sản phẩm');
    setState(() => saving = true);
    try {
      await StoreDb.instance.completeSale(product: product!, quantity: quantity, serialId: serialId, unitPrice: int.tryParse(price.text) ?? 0, customer: customer.text, phone: phone.text, cash: int.tryParse(cash.text) ?? 0, transfer: int.tryParse(transfer.text) ?? 0, warrantyMonths: warranty);
      customer.clear(); phone.clear(); cash.clear(); transfer.clear(); price.clear();
      setState(() { product = null; serialId = null; quantity = 1; saving = false; });
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
  @override
  Widget build(BuildContext context) => Column(children: [
    const PageHeader('Hóa đơn'),
    Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: StoreDb.instance.sales(), builder: (context, snap) {
      final rows = snap.data ?? [];
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (rows.isEmpty) return const Center(child: Text('Chưa có hóa đơn'));
      return ListView.separated(padding: const EdgeInsets.all(16), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, i) {
        final s = rows[i]; final cancelled = s['status'] == 'cancelled';
        return Card(child: ListTile(
          title: Row(children: [Expanded(child: Text('${s['customer']}', style: const TextStyle(fontWeight: FontWeight.bold))), Text(vnd(s['total'] as int))]),
          subtitle: Text('${s['code']}\n${cancelled ? 'ĐÃ HỦY' : 'Lợi nhuận: ${vnd((s['total'] as int) - (s['cost_total'] as int))} • Nợ: ${vnd(s['debt'] as int)}'}'),
          isThreeLine: true,
          trailing: cancelled ? null : IconButton(icon: const Icon(Icons.cancel_outlined, color: Colors.red), onPressed: () => cancel(s['id'] as int)),
        ));
      });
    })),
  ]);
  Future<void> cancel(int id) async {
    if (!await confirm(context, 'Hủy hóa đơn', 'Hủy hóa đơn sẽ hoàn lại tồn kho và loại số liệu khỏi doanh thu. Tiếp tục?')) return;
    await StoreDb.instance.cancelSale(id); setState(() {}); widget.onChanged();
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const PageHeader('Nhiều hơn'),
    MenuGroup('Hàng hóa', [
      MenuAction(Icons.inventory_2, 'Hàng hóa', () {}),
      MenuAction(Icons.download, 'Nhập hàng', () async { final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PurchaseForm())); if (ok == true) onChanged(); }),
      MenuAction(Icons.fact_check, 'Kiểm kho', () => coming(context)),
      MenuAction(Icons.assignment_return, 'Trả hàng nhập', () => coming(context)),
      MenuAction(Icons.delete_sweep, 'Xuất hủy', () => coming(context)),
    ]),
    const SizedBox(height: 12),
    MenuGroup('Quản lý', [
      MenuAction(Icons.people, 'Khách hàng', () => coming(context)),
      MenuAction(Icons.local_shipping, 'Nhà cung cấp', () => coming(context)),
      MenuAction(Icons.build, 'Phiếu sửa chữa', () => coming(context)),
      MenuAction(Icons.verified_user, 'Phiếu bảo hành', () => coming(context)),
      MenuAction(Icons.savings, 'Sổ quỹ', () => coming(context)),
    ]),
    const SizedBox(height: 12),
    MenuGroup('Dữ liệu', [
      MenuAction(Icons.backup, 'Sao lưu', () => coming(context)),
      MenuAction(Icons.restore, 'Khôi phục', () => coming(context)),
    ]),
  ]);
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

void coming(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chức năng sẽ được hoàn thiện ở phiên bản tiếp theo')));
void showError(BuildContext context, Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').replaceFirst('DatabaseException(', '').split(') sql').first;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: Colors.red));
}
Future<bool> confirm(BuildContext context, String title, String body) async => await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(title), content: Text(body), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận'))])) ?? false;
