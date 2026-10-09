import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'lan/remote_bridge.dart';
import 'lan/lan_host_stub.dart' if (dart.library.io) 'lan/lan_host.dart';
import 'platform/browser_print_stub.dart' if (dart.library.html) 'platform/browser_print.dart';
import 'platform/socket_stub.dart' if (dart.library.io) 'platform/socket_native.dart';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' hide Barcode;
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

import 'scanner_page.dart';
import 'vietqr.dart';
import 'features/device_unlock.dart';

part 'features/upgrade_ui.dart';
part 'features/purchase_ui.dart';
part 'features/customer_picker.dart';
part 'features/finance_ui.dart';
part 'data/store.dart';
part 'data/purchase_drafts.dart';
part 'data/finance_store.dart';
part 'data/inventory_report.dart';
part 'lan/store_codec.dart';
part 'features/connection_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if(!kIsWeb) await StoreDb.instance.database;
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
    home: kIsWeb ? const PairGate() : const PinGate(),
  );
}

class SerialDraft {
  SerialDraft({
    this.imei = '',
    this.color = '',
    this.conditionText = 'Mới',
    this.cost = 0,
  });
  String imei;
  String color;
  String conditionText;
  int cost;
}

class PurchaseLineDraft {
  PurchaseLineDraft({required this.product, int initialQuantity = 1})
    : quantity = initialQuantity {
    syncSerials();
  }

  final Map<String, Object?> product;
  int quantity;
  final cost = TextEditingController();
  final discount = TextEditingController(text: '0');
  final serials = <SerialDraft>[];

  bool get tracksImei => product['track_imei'] == 1;
  int get unitPrice => int.tryParse(cost.text) ?? 0;
  int get discountPerItem => int.tryParse(discount.text) ?? 0;
  int get netUnitCost =>
      unitPrice >= discountPerItem ? unitPrice - discountPerItem : 0;
  int get lineQuantity => tracksImei ? serials.length : quantity;
  int get total => tracksImei
      ? serials.fold<int>(0, (sum, serial) => sum + (serial.cost > 0 ? serial.cost : netUnitCost))
      : lineQuantity * netUnitCost;

  void syncSerials() {
    if (!tracksImei) {
      serials.clear();
      return;
    }
    if (quantity < 1) quantity = 1;
    while (serials.length < quantity) {
      serials.add(SerialDraft());
    }
    while (serials.length > quantity) {
      serials.removeLast();
    }
  }

  void dispose() {
    cost.dispose();
    discount.dispose();
  }
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
  int unitPrice;
  int discountPerItem;
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

class _PinGateState extends State<PinGate> with WidgetsBindingObserver {
  late final deviceUnlock = DeviceUnlock(read:StoreDb.instance.getSetting,write:StoreDb.instance.setSetting);
  bool biometrics=false, authenticating=false;

  @override void dispose(){WidgetsBinding.instance.removeObserver(this);pin.dispose();confirmPin.dispose();super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused || state==AppLifecycleState.hidden){deviceUnlock.background(DateTime.now());}
    if(state==AppLifecycleState.resumed && deviceUnlock.resume(DateTime.now()) && unlocked){
      Navigator.of(context).popUntil((route)=>route.isFirst);
      setState((){unlocked=false;pin.clear();});
      _load();
    }
  }
  Future<void> biometricUnlock() async {
    if(authenticating)return;
    setState(()=>authenticating=true);
    final ok=await deviceUnlock.biometricUnlock();
    if(!mounted)return;
    setState((){authenticating=false;if(ok){unlocked=true;pin.clear();}});
    if(!ok)showError(context,'Chưa xác thực được. Anh có thể thử lại hoặc nhập mã PIN.');
  }
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  String? savedPin;
  bool loading = true;
  bool unlocked = false;
  bool hiding = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    biometrics=await StoreDb.instance.getSetting('biometric_enabled')=='1';
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.phone_android,
                    size: 68,
                    color: Color(0xff0877d1),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Minh Cảnh Mobile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff0877d1),
                    ),
                  ),
                  const Text(
                    'Uy tín dẫn đầu – Chất lượng bền lâu',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    creating ? 'Tạo mã PIN lần đầu' : 'Nhập mã PIN',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    creating
                        ? 'Mã PIN gồm 4–6 số, dùng để bảo vệ dữ liệu cửa hàng trên máy này.'
                        : 'Nhập mã PIN để mở ứng dụng.',
                  ),
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
                        icon: Icon(
                          hiding
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => hiding = !hiding),
                      ),
                    ),
                    onSubmitted: (_) {
                      if (!creating) _unlock();
                    },
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
                        labelText: 'Nhập lại mã PIN',
                        prefixIcon: Icon(Icons.lock_reset),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if(!creating && biometrics) OutlinedButton.icon(
                    onPressed:authenticating?null:biometricUnlock,
                    icon:const Icon(Icons.fingerprint),label:const Text('Mở khóa bằng sinh trắc học')),
                  FilledButton.icon(
                    onPressed: authenticating ? null : creating ? _createPin : _unlock,
                    icon: Icon(
                      creating ? Icons.check_circle_outline : Icons.login,
                    ),
                    label: Text(creating ? 'Lưu mã PIN' : 'Mở ứng dụng'),
                  ),
                ],
              ),
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
    if (mounted)
      setState(() {
        savedPin = pin.text;
        unlocked = true;
      });
  }

  Future<void> _unlock() async {
    final valid=await deviceUnlock.checkPin(pin.text);
    if(!mounted)return;
    if(!valid)return showError(context,'Mã PIN không đúng');
    setState((){unlocked=true;pin.clear();});
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
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        pinField(oldPin, 'Mã PIN hiện tại'),
        const SizedBox(height: 12),
        pinField(newPin, 'Mã PIN mới'),
        const SizedBox(height: 12),
        pinField(confirmPin, 'Nhập lại mã PIN mới'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: save,
          icon: const Icon(Icons.save),
          label: const Text('Lưu mã PIN mới'),
        ),
      ],
    ),
  );

  Widget pinField(TextEditingController controller, String label) => TextField(
    controller: controller,
    obscureText: true,
    maxLength: 6,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
    ),
  );

  Future<void> save() async {
    final current = await StoreDb.instance.getSetting('pin');
    if (!mounted) return;
    if (oldPin.text != current)
      return showError(context, 'Mã PIN hiện tại không đúng');
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
  int index=0, refreshKey=0;
  void refresh(){if(kIsWeb)remoteBridge.acceptLatest();setState(()=>refreshKey++);}
  @override Widget build(BuildContext context){
    final wide=MediaQuery.sizeOf(context).width>=840;
    final pages=[DashboardPage(key:ValueKey('d$refreshKey')),ProductsPage(key:ValueKey('p$refreshKey'),onChanged:refresh),SalePage(key:ValueKey('s$refreshKey'),onChanged:refresh),InvoicesPage(key:ValueKey('i$refreshKey'),onChanged:refresh),MorePage(onChanged:refresh,onSelectTab:(v)=>setState(()=>index=v))];
    const labels=['Tổng quan','Hàng hóa','Bán hàng','Hóa đơn','Nhiều hơn'];
    const icons=[Icons.insights_outlined,Icons.inventory_2_outlined,Icons.shopping_bag_outlined,Icons.receipt_long_outlined,Icons.menu];
    return Scaffold(body:SafeArea(child:Column(children:[
      if(!kIsWeb) ValueListenableBuilder<int>(valueListenable:StoreDb.instance.remoteChanges,builder:(context,_,child)=>StoreDb.instance._nativeStale?Material(color:const Color(0xffffefce),child:Padding(padding:const EdgeInsets.all(12),child:Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[
        const Text('Dữ liệu đã thay đổi trên máy tính.'),
        TextButton(onPressed:()async {
          if(!await confirm(context,'Tải lại dữ liệu','Dữ liệu mới sẽ được tải từ kho. Nội dung đang nhập chưa lưu sẽ được bỏ. Tiếp tục?'))return;
          if(!mounted)return;
          StoreDb.instance.acknowledgeRemoteChanges();refresh();
        },child:const Text('Tải lại dữ liệu')),
      ]))):const SizedBox.shrink()),
      if(kIsWeb) AnimatedBuilder(animation:remoteBridge,builder:(context,_)=>Material(color:remoteBridge.connected?const Color(0xffe8f3fc):const Color(0xffffe4e4),child:Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:12,children:[
        Icon(remoteBridge.connected?Icons.wifi:Icons.wifi_off,size:18),
        Text(remoteBridge.message??(remoteBridge.connected?'Đang dùng dữ liệu trên điện thoại':'Mất kết nối điện thoại')),
        if(!remoteBridge.connected) TextButton(onPressed:(){remoteBridge.disconnect();Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>const PairGate()),(_)=>false);},child:const Text('Ghép nối lại')),
        if(remoteBridge.pending!=null) TextButton(onPressed:remoteBridge.busy?null:()async{try{await remoteBridge.resolvePending();}catch(e){if(context.mounted)showError(context,e.toString());}},child:const Text('Kiểm tra giao dịch')),
        TextButton.icon(onPressed:remoteBridge.pending!=null?null:()async{await remoteBridge.poll();if(remoteBridge.connected)refresh();},icon:const Icon(Icons.refresh),label:const Text('Tải lại dữ liệu')),
      ])))),
      Expanded(child:Row(children:[
        if(wide) NavigationRail(extended:true,minExtendedWidth:190,leading:const Padding(padding:EdgeInsets.all(16),child:Text('MINH CẢNH\nMOBILE',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:Color(0xff0877d1)))),selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:[for(var i=0;i<labels.length;i++)NavigationRailDestination(icon:Icon(icons[i]),label:Text(labels[i]))]),
        if(wide)const VerticalDivider(width:1),
        Expanded(child:IndexedStack(index:index,children:pages)),
      ])),
    ])),bottomNavigationBar:wide?null:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:[for(var i=0;i<labels.length;i++)NavigationDestination(icon:Icon(icons[i]),label:labels[i])]));
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, int>>(
    future: StoreDb.instance.dashboard(),
    builder: (context, snap) {
      final d =
          snap.data ??
          {
            'revenue': 0,
            'profit': 0,
            'debt': 0,
            'fund': 0,
            'invoices': 0,
            'pending_repairs': 0,
            'stock_value': 0,
          };
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          const Text(
            'Minh Cảnh Mobile',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: Color(0xff0877d1),
            ),
          ),
          const Text('Uy tín dẫn đầu – Chất lượng bền lâu'),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tổng quan',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsPage()),
                ),
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('Xem báo cáo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.sizeOf(context).width >= 1000 ? 4 : 2,
            childAspectRatio: 1.35,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              MetricCard(
                'Doanh thu',
                vnd(d['revenue']!),
                Icons.trending_up,
                Colors.blue,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const DashboardDetailPage(metric: 'revenue'),
                  ),
                ),
              ),
              MetricCard(
                'Lợi nhuận',
                vnd(d['profit']!),
                Icons.account_balance_wallet,
                Colors.green,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DashboardDetailPage(metric: 'profit'),
                  ),
                ),
              ),
              MetricCard(
                'Hóa đơn',
                '${d['invoices']}',
                Icons.receipt_long,
                Colors.cyan,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Hóa đơn')),
                      body: InvoicesPage(onChanged: () {}),
                    ),
                  ),
                ),
              ),
              MetricCard(
                'Công nợ KH',
                vnd(d['debt']!),
                Icons.people,
                Colors.orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CustomersPage(debtOnly: true),
                  ),
                ),
              ),
              MetricCard(
                'Dòng tiền ròng',
                vnd(d['fund']!),
                Icons.savings,
                Colors.teal,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DashboardDetailPage(metric: 'fund'),
                  ),
                ),
              ),
              MetricCard(
                'Đang sửa chữa',
                '${d['pending_repairs']} phiếu',
                Icons.build_circle,
                Colors.deepPurple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RepairsPage()),
                ),
              ),
              MetricCard(
                'Giá trị tồn',
                vnd(d['stock_value']!),
                Icons.inventory,
                Colors.indigo,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductReportPage()),
                ),
              ),
              MetricCard(
                'Phiếu bảo hành',
                '${d['warranties'] ?? 0} máy',
                Icons.verified_user,
                Colors.blueGrey,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WarrantiesPage()),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard(
    this.label,
    this.value,
    this.icon,
    this.color, {
    super.key,
    this.onTap,
  });
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(child: Text(label)),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ],
        ),
      ),
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
  final searchController = TextEditingController();
  String search = '';
  String selectedCategory = '';
  List<String> categories = [];
  bool showInactive = false;

  @override
  void initState() {
    super.initState();
    loadCategories();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadCategories() async {
    final rows = await StoreDb.instance.productCategories();
    if (mounted) {
      setState(() => categories = rows.map((row) => '${row['name']}').toList());
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PageHeader(
        'Hàng hóa',
        action: IconButton(
          tooltip: 'Thêm hàng hóa',
          icon: const Icon(Icons.add_circle, size: 34),
          onPressed: _add,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Tên, mã hàng, mã vạch hoặc IMEI',
            suffixIcon: IconButton(
              tooltip: 'Quét bằng camera',
              onPressed: scanProduct,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ),
          onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
        ),
      ),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<String>(
          initialValue: selectedCategory,
          decoration: const InputDecoration(
            labelText: 'Lọc theo phân loại',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Tất cả phân loại')),
            ...categories.map(
              (value) => DropdownMenuItem(value: value, child: Text(value)),
            ),
          ],
          onChanged: (value) => setState(() => selectedCategory = value ?? ''),
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
      Expanded(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: StoreDb.instance.products(includeInactive: true),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.data!.where((p) {
              final inactive = p['active'] != 1;
              final matchesStatus = showInactive == inactive;
              final matchesSearch =
                  '${p['name']} ${p['code']} ${p['category']} ${p['imeis'] ?? ''}'
                      .toLowerCase()
                      .contains(search);
              final matchesCategory =
                  selectedCategory.isEmpty ||
                  '${p['category']}'.toLowerCase() ==
                      selectedCategory.toLowerCase();
              return matchesStatus && matchesSearch && matchesCategory;
            }).toList();
            if (rows.isEmpty) {
              return Center(
                child: Text(
                  showInactive
                      ? 'Không có hàng hóa ngừng kinh doanh'
                      : 'Chưa có hàng hóa\nBấm dấu + để tạo mẫu hàng',
                  textAlign: TextAlign.center,
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = rows[i];
                final active = p['active'] == 1;
                return Card(
                  child: ListTile(
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
                      '${p['code']} • ${p['category']} • Tồn: ${p['stock']}\n'
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
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );

  Future<void> _add() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProductForm()),
    );
    if (changed == true) {
      await loadCategories();
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

  Future<void> scanProduct() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodePage(title: 'Quét hàng hóa / IMEI'),
      ),
    );
    if (scanned == null || !mounted) return;
    final value = extractImei(scanned) ?? scanned.trim();
    final rows = await StoreDb.instance.products(includeInactive: true);
    final matches = rows.where((row) {
      final code = '${row['code']}'.trim().toLowerCase();
      final imeis = '${row['imeis'] ?? ''}'.split(' ');
      return code == value.toLowerCase() || imeis.contains(value);
    }).toList();
    if (!mounted) return;
    if (matches.length == 1) {
      await _detail(matches.single);
      return;
    }
    searchController.text = value;
    setState(() => search = value.toLowerCase());
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
  List<String> categories = [];
  Map<String, String> categoryLabels = {};
  List<String> brands = [];
  String category = 'Điện thoại';
  bool imei = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    loadInitial();
  }

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    brand.dispose();
    capacity.dispose();
    price.dispose();
    super.dispose();
  }

  Future<void> loadInitial() async {
    final values = await Future.wait([
      StoreDb.instance.nextProductCode(),
      StoreDb.instance.productCategories(),
      StoreDb.instance.productBrands(),
    ]);
    if (!mounted) return;
    final rows = values[1] as List<Map<String, Object?>>;
    setState(() {
      if (code.text.trim().isEmpty) code.text = values[0] as String;
      categories = rows.map((row) => '${row['name']}').toList();
      categoryLabels = {
        for (final row in rows)
          '${row['name']}': '${row['display_name'] ?? row['name']}',
      };
      brands = (values[2] as List<Map<String, Object?>>)
          .map((row) => '${row['name']}')
          .toList();
      if (!categories.contains(category) && categories.isNotEmpty) {
        category = categories.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hàng hóa mới')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: code,
            decoration: InputDecoration(
              labelText: 'Mã hàng / mã vạch *',
              suffixIcon: IconButton(
                tooltip: 'Quét mã hàng',
                onPressed: scanProductCode,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
            validator: requiredText,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Tên hàng *'),
            validator: requiredText,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('category-$category-${categories.length}'),
            initialValue: categories.contains(category) ? category : null,
            decoration: const InputDecoration(
              labelText: 'Phân loại hàng hóa *',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              ...categories.map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(categoryLabels[value] ?? value),
                ),
              ),
              const DropdownMenuItem(
                value: '__new__',
                child: Text('+ Tạo phân loại mới'),
              ),
            ],
            onChanged: pickCategory,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('brand-${brand.text}-${brands.length}'),
            initialValue: brands.contains(brand.text) ? brand.text : '',
            decoration: const InputDecoration(labelText: 'Hãng'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Không chọn hãng')),
              ...brands.map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              ),
              const DropdownMenuItem(
                value: '__new__',
                child: Text('+ Tạo hãng mới'),
              ),
            ],
            onChanged: pickBrand,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: capacity,
            decoration: const InputDecoration(labelText: 'Dung lượng'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Giá bán'),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Quản lý theo Serial/IMEI'),
              subtitle: Text(
                imei
                    ? 'Điện thoại: mỗi máy một IMEI'
                    : 'Phụ kiện: quản lý theo số lượng',
              ),
              value: imei,
              onChanged: (value) => setState(() {
                final oldDefault = imei ? 'Điện thoại' : 'Phụ kiện';
                imei = value;
                if (category == oldDefault) {
                  final nextDefault = imei ? 'Điện thoại' : 'Phụ kiện';
                  if (categories.contains(nextDefault)) category = nextDefault;
                }
              }),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save),
            label: const Text('Lưu mẫu hàng'),
          ),
        ],
      ),
    ),
  );

  String? requiredText(String? v) =>
      v == null || v.trim().isEmpty ? 'Không được để trống' : null;

  Future<void> scanProductCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodePage(
          title: 'Quét mã hàng',
          hint: 'Đưa mã vạch có sẵn của sản phẩm vào khung',
        ),
      ),
    );
    if (result != null && mounted) code.text = result.trim();
  }

  Future<void> pickCategory(String? value) async {
    if (value == null) return;
    if (value != '__new__') {
      setState(() => category = value);
      return;
    }
    final created = await promptNewCategory(context);
    if (created == null || !mounted) return;
    final saved = await StoreDb.instance.addProductCategory(created);
    final rows = await StoreDb.instance.productCategories();
    if (!mounted) return;
    setState(() {
      categories = rows.map((row) => '${row['name']}').toList();
      categoryLabels = {
        for (final row in rows)
          '${row['name']}': '${row['display_name'] ?? row['name']}',
      };
      category = saved;
    });
  }

  Future<void> pickBrand(String? value) async {
    if (value == null) return;
    if (value != '__new__') {
      setState(() => brand.text = value);
      return;
    }
    final created = await promptNewBrand(context);
    if (created == null || !mounted) return;
    final saved = await StoreDb.instance.addProductBrand(created);
    final rows = await StoreDb.instance.productBrands();
    if (!mounted) return;
    setState(() {
      brands = rows.map((row) => '${row['name']}').toList();
      brand.text = saved;
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (category.trim().isEmpty) {
      showError(context, 'Hãy chọn phân loại hàng hóa');
      return;
    }
    setState(() => saving = true);
    try {
      await StoreDb.instance.addProduct({
        'code': code.text.trim(),
        'name': name.text.trim(),
        'category': category,
        'brand': brand.text.trim(),
        'capacity': capacity.text.trim(),
        'sale_price': int.tryParse(price.text) ?? 0,
        'track_imei': imei ? 1 : 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      showError(context, e);
      setState(() => saving = false);
    }
  }
}

class ProductDetail extends StatefulWidget {
  const ProductDetail({
    super.key,
    required this.product,
    required this.onChanged,
  });
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
      appBar: AppBar(
        title: Text('${p['name']}'),
        actions: [
          IconButton(
            tooltip: 'Sửa thông tin',
            icon: const Icon(Icons.edit_outlined),
            onPressed: edit,
          ),
        ],
      ),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${p['name']}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
                    ],
                  ),
                  Text('Mã: ${p['code']}'),
                  Text('Phân loại: ${p['category']}'),
                  Text('Giá bán: ${vnd(p['sale_price'] as int)}'),
                  if (!tracks)
                    Text('Giá nhập bình quân: ${vnd(p['avg_cost'] as int)}'),
                  Text(
                    tracks
                        ? 'Quản lý theo Serial/IMEI'
                        : 'Quản lý theo số lượng',
                  ),
                ],
              ),
            ),
          ),
          if (!active) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Hàng hóa đang ngừng kinh doanh nên không xuất hiện khi '
                        'bán hoặc nhập hàng mới. Tồn kho và lịch sử vẫn được giữ.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: tracks ? printAllImeiLabels : printProductLabel,
            icon: const Icon(Icons.label_outline),
            label: Text(
              tracks
                  ? 'In tem 40×30 cho IMEI còn hàng'
                  : 'In tem mã hàng 40×30',
            ),
          ),
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
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Chưa nhập IMEI'),
                    ),
                  );
                }
                return Column(
                  children: rows
                      .map(
                        (s) => Card(
                          child: ListTile(
                            title: Text('${s['imei']}'),
                            subtitle: Text(
                              '${s['color']} • ${s['condition_text']} • '
                              'Giá nhập ${vnd(s['cost'] as int)}\n'
                              '${statusName('${s['status']}')}',
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'In tem IMEI',
                                  onPressed: () => printSerialLabel(s),
                                  icon: const Icon(Icons.label_outline),
                                ),
                                const Icon(Icons.edit_outlined),
                              ],
                            ),
                            onTap: () => editSerial(s),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            )
          else
            Card(
              child: ListTile(
                title: const Text('Số lượng hiện tại'),
                trailing: Text(
                  '${p['stock']}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
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
      MaterialPageRoute(builder: (_) => PurchaseForm(initialProduct: product)),
    );
    if (ok == true) {
      await reload();
      widget.onChanged();
    }
  }

  Future<void> printProductLabel() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LabelPreviewPage(
          labels: [
            ProductLabelData(
              productName: '${product['name']}',
              detail: [product['brand'], product['capacity']]
                  .map((value) => '${value ?? ''}'.trim())
                  .where((value) => value.isNotEmpty)
                  .join(' • '),
              code: '${product['code']}',
              price: (product['sale_price'] as num).toInt(),
              isImei: false,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> printSerialLabel(Map<String, Object?> serial) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LabelPreviewPage(labels: [labelForSerial(product, serial)]),
      ),
    );
  }

  Future<void> printAllImeiLabels() async {
    final rows = await StoreDb.instance.serials(
      product['id'] as int,
      status: 'in_stock',
    );
    if (!mounted) return;
    if (rows.isEmpty) {
      showError(context, 'Sản phẩm không có IMEI còn trong kho để in tem');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LabelPreviewPage(
          labels: rows
              .map((serial) => labelForSerial(product, serial))
              .toList(),
        ),
      ),
    );
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
      await StoreDb.instance.setProductActive(product['id'] as int, !active);
      await reload();
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              active ? 'Đã ngừng kinh doanh hàng hóa' : 'Đã kinh doanh trở lại',
            ),
          ),
        );
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
  late String category;
  List<String> categories = [];
  Map<String, String> categoryLabels = {};
  List<String> brands = [];
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
    category = '${widget.product['category']}';
    brand = TextEditingController(text: '${widget.product['brand']}');
    capacity = TextEditingController(text: '${widget.product['capacity']}');
    salePrice = TextEditingController(text: '${widget.product['sale_price']}');
    averageCost = TextEditingController(text: '${widget.product['avg_cost']}');
    loadCategories();
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

  Future<void> loadCategories() async {
    final values = await Future.wait([
      StoreDb.instance.productCategories(),
      StoreDb.instance.productBrands(),
    ]);
    final rows = values[0];
    if (!mounted) return;
    setState(() {
      categories = rows.map((row) => '${row['name']}').toList();
      categoryLabels = {
        for (final row in rows)
          '${row['name']}': '${row['display_name'] ?? row['name']}',
      };
      if (!categories.contains(category)) categories.add(category);
      categories.sort();
      brands = values[1].map((row) => '${row['name']}').toList();
      if (brand.text.trim().isNotEmpty && !brands.contains(brand.text)) {
        brands.add(brand.text);
      }
    });
  }

  Future<void> pickCategory(String? value) async {
    if (value == null) return;
    if (value != '__new__') {
      setState(() => category = value);
      return;
    }
    final created = await promptNewCategory(context);
    if (created == null || !mounted) return;
    final saved = await StoreDb.instance.addProductCategory(created);
    await loadCategories();
    if (mounted) setState(() => category = saved);
  }

  Future<void> pickBrand(String? value) async {
    if (value == null) return;
    if (value != '__new__') {
      setState(() => brand.text = value);
      return;
    }
    final created = await promptNewBrand(context);
    if (created == null || !mounted) return;
    final saved = await StoreDb.instance.addProductBrand(created);
    await loadCategories();
    if (mounted) setState(() => brand.text = saved);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sửa thông tin hàng hóa')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: code,
            decoration: const InputDecoration(labelText: 'Mã hàng *'),
            validator: requiredText,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Tên hàng *'),
            validator: requiredText,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('edit-category-$category-${categories.length}'),
            initialValue: categories.contains(category) ? category : null,
            decoration: const InputDecoration(
              labelText: 'Phân loại hàng hóa *',
            ),
            items: [
              ...categories.map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(categoryLabels[value] ?? value),
                ),
              ),
              const DropdownMenuItem(
                value: '__new__',
                child: Text('+ Tạo phân loại mới'),
              ),
            ],
            onChanged: pickCategory,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('edit-brand-${brand.text}-${brands.length}'),
            initialValue: brands.contains(brand.text) ? brand.text : '',
            decoration: const InputDecoration(labelText: 'Hãng'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Không chọn hãng')),
              ...brands.map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              ),
              const DropdownMenuItem(
                value: '__new__',
                child: Text('+ Tạo hãng mới'),
              ),
            ],
            onChanged: pickBrand,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: capacity,
            decoration: const InputDecoration(labelText: 'Dung lượng'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: salePrice,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Giá bán *'),
          ),
          const SizedBox(height: 12),
          if (!tracksImei)
            TextFormField(
              controller: averageCost,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Giá nhập bình quân hiện tại *',
              ),
            ),
          if (tracksImei)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Giá nhập của điện thoại được lưu riêng theo từng IMEI. '
                  'Quay lại danh sách IMEI và bấm vào chiếc máy cần sửa giá.',
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save),
            label: const Text('Lưu thay đổi'),
          ),
        ],
      ),
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
        category: category,
        brand: brand.text,
        capacity: capacity.text,
        salePrice: int.tryParse(salePrice.text) ?? 0,
        averageCost: tracksImei ? null : (int.tryParse(averageCost.text) ?? 0),
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
    conditionText = TextEditingController(
      text: '${widget.serial['condition_text']}',
    );
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
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: imei,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'IMEI *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: color,
          decoration: const InputDecoration(labelText: 'Màu sắc'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: conditionText,
          decoration: const InputDecoration(labelText: 'Tình trạng'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: cost,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Giá nhập *'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save),
          label: const Text('Lưu thay đổi'),
        ),
      ],
    ),
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
  String category = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final categories =
        widget.products
            .map((product) => '${product['category']}')
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final rows = widget.products.where((product) {
      final text = [
        product['name'],
        product['code'],
        product['brand'],
        product['capacity'],
        product['category'],
        product['imeis'],
      ].map((value) => '${value ?? ''}').join(' ').toLowerCase();
      final matchesQuery = normalized.isEmpty || text.contains(normalized);
      final matchesCategory =
          category.isEmpty ||
          '${product['category']}'.toLowerCase() == category.toLowerCase();
      return matchesQuery && matchesCategory;
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tìm sản phẩm',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Tên, mã hàng, mã vạch, IMEI…',
                suffixIcon: IconButton(
                  tooltip: 'Quét bằng camera',
                  onPressed: scan,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(
                labelText: 'Phân loại',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Tất cả phân loại'),
                ),
                ...categories.map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                ),
              ],
              onChanged: (value) => setState(() => category = value ?? ''),
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
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              product['track_imei'] == 1
                                  ? Icons.phone_android
                                  : Icons.inventory_2_outlined,
                            ),
                          ),
                          title: Text(
                            '${product['name']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(details),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, product),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> scan() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodePage(title: 'Quét mã hàng / IMEI'),
      ),
    );
    if (scanned == null || !mounted) return;
    final normalized = extractImei(scanned) ?? scanned.trim();
    final matches = widget.products.where((product) {
      final productCode = '${product['code']}'.trim().toLowerCase();
      final imeis = '${product['imeis'] ?? ''}'.split(' ');
      return productCode == normalized.toLowerCase() ||
          imeis.contains(normalized);
    }).toList();
    if (matches.length == 1) {
      Navigator.pop(context, {...matches.single, '_scan_code': normalized});
      return;
    }
    search.text = normalized;
    setState(() => query = normalized);
  }
}

class SerialEditor extends StatefulWidget {
  const SerialEditor({
    super.key,
    required this.index,
    required this.draft,
    required this.onRemove,
    required this.canRemove,
  });
  final int index;
  final SerialDraft draft;
  final VoidCallback onRemove;
  final bool canRemove;

  @override
  State<SerialEditor> createState() => _SerialEditorState();
}

class _SerialEditorState extends State<SerialEditor> {
  late final TextEditingController imei;
  late final TextEditingController color;

  @override
  void initState() {
    super.initState();
    imei = TextEditingController(text: widget.draft.imei);
    color = TextEditingController(text: widget.draft.color);
  }

  @override
  void didUpdateWidget(covariant SerialEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (imei.text != widget.draft.imei) imei.text = widget.draft.imei;
    if (color.text != widget.draft.color) color.text = widget.draft.color;
  }

  @override
  void dispose() {
    imei.dispose();
    color.dispose();
    super.dispose();
  }

  Future<void> scanImei() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodePage(
          title: 'Quét IMEI',
          hint: 'Đưa mã vạch IMEI 15 số vào giữa khung hình',
        ),
      ),
    );
    if (raw == null || !mounted) return;
    final value = extractImei(raw);
    if (value == null || !isValidImei(value)) {
      showError(context, 'Mã quét không phải IMEI hợp lệ');
      return;
    }
    imei.text = value;
    widget.draft.imei = value;
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Máy ${widget.index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (widget.canRemove)
                IconButton(
                  tooltip: 'Bỏ máy này',
                  onPressed: widget.onRemove,
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: imei,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 15,
            decoration: InputDecoration(
              labelText: 'IMEI *',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'Quét IMEI',
                onPressed: scanImei,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
            onChanged: (value) => widget.draft.imei = value,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: color,
            decoration: const InputDecoration(labelText: 'Màu sắc'),
            onChanged: (value) => widget.draft.color = value,
          ),
        ],
      ),
    ),
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
  VietQrAccount? paymentAccount;
  late String invoiceCode;
  int selectedCustomerId = 0;
  int warranty = 0;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    invoiceCode = newInvoiceCode();
    _loadCustomers();
    loadPaymentAccount();
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
  int get cartQuantity => cart.fold(0, (sum, item) => sum + item.soldQuantity);
  int get cartTotal => cart.fold(0, (sum, item) => sum + item.total);
  int get cartDiscount => cart.fold(0, (sum, item) => sum + item.discountTotal);
  int get customerDebt {
    final value =
        cartTotal -
        (int.tryParse(cash.text) ?? 0) -
        (int.tryParse(transfer.text) ?? 0);
    return value < 0 ? 0 : value;
  }

  int get transferAmount => int.tryParse(transfer.text) ?? 0;

  Future<void> loadPaymentAccount() async {
    final bin = await StoreDb.instance.getSetting('payment_bank_bin') ?? '';
    final bank = await StoreDb.instance.getSetting('payment_bank_name') ?? '';
    final number =
        await StoreDb.instance.getSetting('payment_account_number') ?? '';
    final name =
        await StoreDb.instance.getSetting('payment_account_name') ?? '';
    if (!mounted) return;
    final account = VietQrAccount(
      bankBin: bin,
      bankName: bank,
      accountNumber: number,
      accountName: name,
    );
    setState(() => paymentAccount = account.isValid ? account : null);
  }

  Widget _saleSummaryRow(String label, String value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: strong ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Future<void> _loadCustomers({int? selectId}) async {
    final raw = await StoreDb.instance.customers();
    final rows=raw.map((r)=>{...r,'name':r['customer']??r['name']}).toList();
    if (!mounted) return;
    setState(() {
      customers=rows;
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
      customer.text = id == 0 || selected.isEmpty
          ? ''
          : '${selected.first['name']}';
      phone.text = id == 0 || selected.isEmpty
          ? ''
          : '${selected.first['phone']}';
    });
  }

  Future<void> _pickProduct(List<Map<String, Object?>> products) async {
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
    final scannedCode = '${selected['_scan_code'] ?? ''}'.trim();
    final cleanProduct = Map<String, Object?>.from(selected)
      ..remove('_scan_code');
    setState(() {
      product = cleanProduct;
      serialId = null;
      quantity = 1;
      price.text = '${cleanProduct['sale_price']}';
      saleDiscount.text = '0';
    });
    if (scannedCode.isEmpty) return;
    if (cleanProduct['track_imei'] == 1) {
      final rows = await StoreDb.instance.serials(
        cleanProduct['id'] as int,
        status: 'in_stock',
      );
      final match = rows.where((row) => '${row['imei']}' == scannedCode);
      if (match.isEmpty) {
        if (mounted) {
          showError(
            context,
            'Hãy quét đúng IMEI của máy còn trong kho hoặc chọn IMEI',
          );
        }
        return;
      }
      if (mounted) setState(() => serialId = match.first['id'] as int);
    }
    await addItem();
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
      final selected = serialRows
          .where((row) => row['id'] == serialId)
          .toList();
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
          .where(
            (item) => item.serialId == null && item.product['id'] == productId,
          )
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
        final sameLine = cart.where(
          (item) =>
              item.serialId == null &&
              item.product['id'] == productId &&
              item.unitPrice == listedUnitPrice &&
              item.discountPerItem == discountPerItem,
        );
        if (sameLine.isNotEmpty) {
          sameLine.first.quantity += quantity;
        } else {
          cart.add(
            SaleLineDraft(
              product: selectedProduct,
              quantity: quantity,
              unitPrice: listedUnitPrice,
              discountPerItem: discountPerItem,
            ),
          );
        }
      } else {
        cart.add(
          SaleLineDraft(
            product: selectedProduct,
            quantity: 1,
            serialId: serialId,
            imei: imei,
            color: color,
            unitPrice: listedUnitPrice,
            discountPerItem: discountPerItem,
          ),
        );
      }
      product = null;
      serialId = null;
      quantity = 1;
      price.clear();
      saleDiscount.text = '0';
    });
  }

  Future<void> editCartItem(int index) async {
    final item = cart[index];
    final priceController = TextEditingController(text: '${item.unitPrice}');
    final discountController = TextEditingController(
      text: '${item.discountPerItem}',
    );
    final quantityController = TextEditingController(text: '${item.quantity}');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sửa ${item.product['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Giá bán'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: discountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Giảm giá mỗi sản phẩm',
                ),
              ),
              if (!item.tracksImei) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Số lượng'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bỏ qua'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final newPrice = int.tryParse(priceController.text) ?? 0;
    final newDiscount = int.tryParse(discountController.text) ?? 0;
    final newQuantity = item.tracksImei
        ? 1
        : (int.tryParse(quantityController.text) ?? 0);
    if (newPrice <= 0 || newDiscount < 0 || newDiscount > newPrice) {
      showError(context, 'Giá bán hoặc giảm giá không hợp lệ');
      return;
    }
    if (newQuantity <= 0) {
      showError(context, 'Số lượng phải lớn hơn 0');
      return;
    }
    if (!item.tracksImei) {
      final otherQuantity = cart
          .asMap()
          .entries
          .where(
            (entry) =>
                entry.key != index &&
                entry.value.serialId == null &&
                entry.value.product['id'] == item.product['id'],
          )
          .fold<int>(0, (sum, entry) => sum + entry.value.quantity);
      if (otherQuantity + newQuantity >
          (item.product['stock'] as num).toInt()) {
        showError(context, 'Tổng số lượng trong hóa đơn vượt tồn kho');
        return;
      }
    }
    setState(() {
      item.unitPrice = newPrice;
      item.discountPerItem = newDiscount;
      item.quantity = newQuantity;
    });
  }

  void usePayment(String kind) {
    setState(() {
      if (kind == 'cash') {
        cash.text = '$cartTotal';
        transfer.text = '0';
      } else if (kind == 'transfer') {
        cash.text = '0';
        transfer.text = '$cartTotal';
      } else if (kind == 'debt') {
        cash.text = '0';
        transfer.text = '0';
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const PageHeader('Bán hàng'),
      Expanded(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: StoreDb.instance.products(),
          builder: (context, snap) {
            final products = (snap.data ?? [])
                .where((p) => (p['stock'] as num).toInt() > 0)
                .toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Thêm sản phẩm vào hóa đơn',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.search),
                          ),
                          title: Text(
                            product == null
                                ? 'Chọn sản phẩm'
                                : '${product!['name']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            product == null
                                ? 'Tìm theo tên, mã, hãng hoặc dung lượng'
                                : '${product!['code']} • Tồn: ${product!['stock']}',
                          ),
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
                              final rows = (serialSnapshot.data ?? [])
                                  .where(
                                    (row) => !cart.any(
                                      (item) => item.serialId == row['id'],
                                    ),
                                  )
                                  .toList();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: DropdownButtonFormField<int>(
                                  key: ValueKey(
                                    'imei-${product!['id']}-${cart.length}',
                                  ),
                                  initialValue: serialId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Chọn IMEI *',
                                  ),
                                  items: rows
                                      .map(
                                        (serial) => DropdownMenuItem(
                                          value: serial['id'] as int,
                                          child: Text(
                                            '${serial['imei']} • ${serial['color']}',
                                          ),
                                        ),
                                      )
                                      .toList(),
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
                              decoration: const InputDecoration(
                                labelText: 'Số lượng',
                              ),
                              onChanged: (value) => setState(
                                () => quantity = int.tryParse(value) ?? 0,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Giá bán *',
                          ),
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
                          _saleSummaryRow('Giá sau giảm', vnd(netSalePrice)),
                          _saleSummaryRow(
                            'Thành tiền',
                            vnd(draftTotal),
                            strong: true,
                          ),
                        ],
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: product == null ? null : addItem,
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Thêm vào hóa đơn'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Sản phẩm trong hóa đơn (${cart.length})',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (cart.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Chưa có sản phẩm. Hãy chọn hàng và bấm '
                        '“Thêm vào hóa đơn”.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
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
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(
                            '${item.product['name']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '$details\n'
                            'Giá: ${vnd(item.unitPrice)}'
                            '${item.discountPerItem > 0 ? ' • Giảm: ${vnd(item.discountPerItem)}' : ''}',
                          ),
                          isThreeLine: true,
                          onTap: () => editCartItem(index),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                vnd(item.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                tooltip: 'Sửa hoặc xóa',
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    editCartItem(index);
                                  } else if (action == 'delete') {
                                    setState(() => cart.removeAt(index));
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Sửa giá/giảm giá'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Xóa khỏi hóa đơn'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 10),
                Card(
                  color: const Color(0xFFF5F7FA),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        _saleSummaryRow(
                          'Tổng số lượng',
                          '$cartQuantity sản phẩm',
                        ),
                        if (cartDiscount > 0)
                          _saleSummaryRow(
                            'Tổng giảm giá',
                            '-${vnd(cartDiscount)}',
                          ),
                        _saleSummaryRow(
                          'Khách phải trả',
                          vnd(cartTotal),
                          strong: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                CustomerSearchPicker(rows:customers,selectedId:selectedCustomerId,onSelected:_pickCustomer),
                if (selectedCustomerId > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'SĐT: ${phone.text.trim().isEmpty ? 'Không ghi' : phone.text}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Tiền mặt đủ'),
                      onPressed: () => usePayment('cash'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.qr_code, size: 18),
                      label: const Text('Chuyển khoản đủ'),
                      onPressed: () => usePayment('transfer'),
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                      ),
                      label: const Text('Khách nợ'),
                      onPressed: () => usePayment('debt'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cash,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Tiền mặt'),
                  onChanged: (_) => setState(() {}),
                ),
                if (transferAmount > 0) ...[
                  const SizedBox(height: 12),
                  PaymentQrCard(
                    account: paymentAccount,
                    amount: transferAmount,
                    invoiceCode: invoiceCode,
                    onSettingsChanged: loadPaymentAccount,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: transfer,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                  decoration: const InputDecoration(
                    labelText: 'Thời hạn bảo hành',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Không bảo hành')),
                    DropdownMenuItem(value: 3, child: Text('3 tháng')),
                    DropdownMenuItem(value: 6, child: Text('6 tháng')),
                    DropdownMenuItem(value: 9, child: Text('9 tháng')),
                    DropdownMenuItem(
                      value: 12,
                      child: Text('12 tháng / 1 năm'),
                    ),
                    DropdownMenuItem(value: 24, child: Text('2 năm')),
                    DropdownMenuItem(
                      value: -1,
                      child: Text('Tự nhập số tháng'),
                    ),
                  ],
                  onChanged: (value) => setState(() => warranty = value ?? 0),
                ),
                if (warranty == -1) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: customWarranty,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Số tháng bảo hành *',
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: saving || cart.isEmpty ? null : complete,
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: Text(
                    cart.isEmpty
                        ? 'Hãy thêm sản phẩm'
                        : 'Hoàn tất hóa đơn ${vnd(cartTotal)}',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );

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
        invoiceCode: invoiceCode,
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
        invoiceCode = newInvoiceCode();
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
  final searchController = TextEditingController();
  String search = '';
  PeriodFilter period = PeriodFilter.month(DateTime.now());

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const PageHeader('Hóa đơn'),
      PeriodPicker(value: period, onChanged: (v) => setState(() => period = v)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Tìm tên khách, tên máy, mã hóa đơn hoặc IMEI',
            suffixIcon: IconButton(
              tooltip: 'Quét hóa đơn / IMEI',
              onPressed: scanInvoice,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ),
          onChanged: (value) =>
              setState(() => search = value.trim().toLowerCase()),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: StoreDb.instance.sales(),
          builder: (context, snap) {
            final rows = (snap.data ?? []).where((sale) {
              final haystack =
                  '${sale['customer']} ${sale['phone']} ${sale['code']} '
                  '${sale['product_names'] ?? ''} ${sale['imeis'] ?? ''} '
                  '${formatDateTime(sale['created_at'])}';
              return haystack.toLowerCase().contains(search) &&
                  period.includes(parseDate(sale['created_at']));
            }).toList();
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (rows.isEmpty) {
              return Center(
                child: Text(
                  search.isEmpty
                      ? 'Chưa có hóa đơn'
                      : 'Không tìm thấy hóa đơn phù hợp',
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final sale = rows[i];
                final cancelled = sale['status'] == 'cancelled';
                return Card(
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${sale['customer']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(vnd(sale['total'] as int)),
                      ],
                    ),
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
                              leading: Icon(
                                Icons.cancel_outlined,
                                color: Colors.orange,
                              ),
                              title: Text('Hủy hóa đơn'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.delete_forever,
                              color: Colors.red,
                            ),
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
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );

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

  Future<void> scanInvoice() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodePage(title: 'Quét hóa đơn / IMEI'),
      ),
    );
    if (scanned == null || !mounted) return;
    final value = extractImei(scanned) ?? scanned.trim();
    final rows = await StoreDb.instance.sales();
    final matches = rows.where((sale) {
      final code = '${sale['code']}'.trim().toLowerCase();
      final imeis = '${sale['imeis'] ?? ''}'.split(' ');
      return code == value.toLowerCase() || imeis.contains(value);
    }).toList();
    if (!mounted) return;
    if (matches.length == 1) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              InvoiceDetailPage(saleId: matches.single['id'] as int),
        ),
      );
      if (mounted) setState(() {});
      return;
    }
    searchController.text = value;
    setState(() => search = value.toLowerCase());
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
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            Card(
              child: Padding(
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
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Hàng đã bán',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.phone_android)),
                  title: Text(
                    '${item['product_name']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    [
                      if ('${item['imei']}'.trim().isNotEmpty &&
                          item['imei'] != null)
                        'IMEI: ${item['imei']}',
                      'Số lượng: ${item['quantity']}',
                      'Đơn giá: ${vnd(item['unit_price'] as int)}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thanh toán',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
                    infoLine('Chuyển khoản', vnd(sale['paid_transfer'] as int)),
                    infoLine('Khách còn nợ', vnd(sale['debt'] as int)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bảo hành',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => delete(context),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Xóa hóa đơn'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
            const SizedBox(height: 16),
          ],
        );
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
  const MorePage({
    super.key,
    required this.onChanged,
    required this.onSelectTab,
  });
  final VoidCallback onChanged;
  final ValueChanged<int> onSelectTab;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const PageHeader('Nhiều hơn'),
      MenuGroup('Hàng hóa', [
        MenuAction(Icons.inventory_2, 'Hàng hóa', () => onSelectTab(1)),
        MenuAction(
          Icons.category_outlined,
          'Phân loại hàng hóa',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CategoryManagerPage()),
          ),
        ),
        MenuAction(
          Icons.business_outlined,
          'Danh mục hãng',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BrandManagerPage()),
          ),
        ),
        MenuAction(Icons.download, 'Nhập hàng', () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const PurchaseForm()),
          );
          if (ok == true) onChanged();
        }),
        MenuAction(Icons.fact_check, 'Kiểm kho', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StocktakePage()),
          );
          onChanged();
        }),
        MenuAction(Icons.assignment_return, 'Trả hàng nhập', () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const InventoryActionPage(kind: 'supplier_return'),
            ),
          );
          if (ok == true) onChanged();
        }),
        MenuAction(Icons.delete_sweep, 'Xuất hủy', () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => const InventoryActionPage(kind: 'discard'),
            ),
          );
          if (ok == true) onChanged();
        }),
      ]),
      const SizedBox(height: 12),
      MenuGroup('Báo cáo', [
        MenuAction(
          Icons.bar_chart_rounded,
          'Báo cáo hàng hóa',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProductReportPage()),
          ),
        ),
        MenuAction(
          Icons.assessment,
          'Báo cáo tổng hợp',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReportsPage()),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      MenuGroup('Quản lý', [
        MenuAction(
          Icons.people,
          'Khách hàng',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CustomersPage()),
          ),
        ),
        MenuAction(
          Icons.local_shipping,
          'Nhà cung cấp',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SuppliersPage()),
          ),
        ),
        MenuAction(Icons.build, 'Phiếu sửa chữa', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RepairsPage()),
          );
          onChanged();
        }),
        MenuAction(
          Icons.verified_user,
          'Phiếu bảo hành',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WarrantiesPage()),
          ),
        ),
        MenuAction(Icons.savings, 'Sổ quỹ', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CashBookPage()),
          );
          onChanged();
        }),
      ]),
      const SizedBox(height: 12),
      MenuGroup('Dữ liệu', [
        if(!kIsWeb) MenuAction(Icons.devices_rounded,'Kết nối máy tính',()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const ConnectionPage()))),
        if(kIsWeb) MenuAction(Icons.print_outlined,'In trên máy tính',()=>showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('In hóa đơn và tem'),content:const Text('Mở hóa đơn hoặc tem, chọn In hoặc Chia sẻ để tải PDF. Mở PDF và in bằng máy in đã cài trên máy tính; chọn đúng khổ giấy và tỷ lệ 100%.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Đã hiểu'))]))),
        MenuAction(
          Icons.account_balance,
          'Tài khoản nhận chuyển khoản',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PaymentSettingsPage()),
          ),
        ),
        if(!kIsWeb) MenuAction(
          Icons.label_outline,
          'Cài đặt máy in tem 40×30',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LabelPrinterSettingsPage()),
          ),
        ),
        if(!kIsWeb) MenuAction(
          Icons.print,
          'Cài đặt máy in K80',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrinterSettingsPage()),
          ),
        ),
        MenuAction(Icons.backup, 'Sao lưu & khôi phục', () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BackupPage()),
          );
          onChanged();
        }),
        if(!kIsWeb) MenuAction(Icons.fingerprint,'Mở khóa sinh trắc học',()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const BiometricSettingsPage()))),
        if(!kIsWeb) MenuAction(
          Icons.password,
          'Đổi mã PIN',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChangePinPage()),
          ),
        ),
      ]),
    ],
  );
}

class CategoryManagerPage extends StatefulWidget {
  const CategoryManagerPage({super.key});

  @override
  State<CategoryManagerPage> createState() => _CategoryManagerPageState();
}

class _CategoryManagerPageState extends State<CategoryManagerPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phân loại hàng hóa')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const Text('Thêm phân loại'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.productCategories(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const EmptyState(
            Icons.category_outlined,
            'Chưa có phân loại',
            'Bấm “Thêm phân loại” để bắt đầu.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            final count = (row['product_count'] as num? ?? 0).toInt();
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    row['parent_id'] == null
                        ? Icons.folder_outlined
                        : Icons.subdirectory_arrow_right,
                  ),
                ),
                title: Text(
                  '${row['display_name'] ?? row['name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  row['parent_id'] == null
                      ? '$count hàng hóa • Nhóm cấp 1'
                      : '$count hàng hóa • Phân loại cấp 2',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'add_child') add(parent: row);
                    if (action == 'rename') rename(row);
                    if (action == 'delete') remove(row);
                  },
                  itemBuilder: (_) => [
                    if (row['parent_id'] == null)
                      const PopupMenuItem(
                        value: 'add_child',
                        child: Text('Thêm phân loại con'),
                      ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Đổi tên'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Xóa')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> add({Map<String, Object?>? parent}) async {
    final value = await promptNewCategory(context);
    if (value == null) return;
    try {
      await StoreDb.instance.addProductCategory(
        value,
        parentId: parent?['id'] as int?,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> rename(Map<String, Object?> row) async {
    final controller = TextEditingController(text: '${row['name']}');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đổi tên phân loại'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên phân loại'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Bỏ qua'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await StoreDb.instance.renameProductCategory(row['id'] as int, value);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> remove(Map<String, Object?> row) async {
    final accepted = await confirm(
      context,
      'Xóa phân loại',
      'Xóa phân loại “${row['name']}”? Phân loại đang có hàng hóa sẽ không thể xóa.',
    );
    if (!accepted) return;
    try {
      await StoreDb.instance.deleteProductCategory(row['id'] as int);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class BrandManagerPage extends StatefulWidget {
  const BrandManagerPage({super.key});

  @override
  State<BrandManagerPage> createState() => _BrandManagerPageState();
}

class _BrandManagerPageState extends State<BrandManagerPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Danh mục hãng')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const Text('Thêm hãng'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.productBrands(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const EmptyState(
            Icons.business_outlined,
            'Chưa có hãng',
            'Bấm “Thêm hãng” để bắt đầu.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            final count = (row['product_count'] as num? ?? 0).toInt();
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.business)),
                title: Text(
                  '${row['name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('$count hàng hóa'),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'rename') rename(row);
                    if (action == 'delete') remove(row);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
                    PopupMenuItem(value: 'delete', child: Text('Xóa')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<String?> prompt(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên hãng'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> add() async {
    final value = await prompt('Thêm hãng');
    if (value == null) return;
    try {
      await StoreDb.instance.addProductBrand(value);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> rename(Map<String, Object?> row) async {
    final value = await prompt('Đổi tên hãng', initial: '${row['name']}');
    if (value == null) return;
    try {
      await StoreDb.instance.renameProductBrand(row['id'] as int, value);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> remove(Map<String, Object?> row) async {
    final accepted = await confirm(
      context,
      'Xóa hãng',
      'Xóa hãng “${row['name']}”? Hãng đang có hàng hóa sẽ không thể xóa.',
    );
    if (!accepted) return;
    try {
      await StoreDb.instance.deleteProductBrand(row['id'] as int);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class BankOption {
  const BankOption(this.bin, this.name);
  final String bin;
  final String name;
}

const vietQrBanks = <BankOption>[
  BankOption('970422', 'MB Bank'),
  BankOption('970436', 'Vietcombank'),
  BankOption('970415', 'VietinBank'),
  BankOption('970418', 'BIDV'),
  BankOption('970405', 'Agribank'),
  BankOption('970407', 'Techcombank'),
  BankOption('970432', 'VPBank'),
  BankOption('970416', 'ACB'),
  BankOption('970423', 'TPBank'),
  BankOption('970403', 'Sacombank'),
  BankOption('970441', 'VIB'),
  BankOption('970426', 'MSB'),
  BankOption('970437', 'HDBank'),
  BankOption('970443', 'SHB'),
  BankOption('970440', 'SeABank'),
  BankOption('970448', 'OCB'),
  BankOption('970431', 'Eximbank'),
  BankOption('970449', 'LPBank'),
  BankOption('970428', 'Nam A Bank'),
  BankOption('970412', 'PVcomBank'),
  BankOption('970433', 'VietBank'),
  BankOption('970425', 'ABBank'),
  BankOption('970419', 'NCB'),
  BankOption('970452', 'KienlongBank'),
];

class PaymentSettingsPage extends StatefulWidget {
  const PaymentSettingsPage({super.key});

  @override
  State<PaymentSettingsPage> createState() => _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends State<PaymentSettingsPage> {
  final accountNumber = TextEditingController();
  final accountName = TextEditingController();
  String bankBin = vietQrBanks.first.bin;
  bool loading = true;
  bool saving = false;

  BankOption get selectedBank => vietQrBanks.firstWhere(
    (bank) => bank.bin == bankBin,
    orElse: () => vietQrBanks.first,
  );

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    accountNumber.dispose();
    accountName.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final savedBin =
        await StoreDb.instance.getSetting('payment_bank_bin') ?? '';
    accountNumber.text =
        await StoreDb.instance.getSetting('payment_account_number') ?? '';
    accountName.text =
        await StoreDb.instance.getSetting('payment_account_name') ?? '';
    if (!mounted) return;
    setState(() {
      if (vietQrBanks.any((bank) => bank.bin == savedBin)) bankBin = savedBin;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tài khoản nhận chuyển khoản')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Chỉ lưu thông tin tài khoản nhận tiền trên điện thoại. '
                    'Ứng dụng không yêu cầu mật khẩu hoặc mã OTP ngân hàng.',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: bankBin,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Ngân hàng nhận tiền',
                  prefixIcon: Icon(Icons.account_balance),
                ),
                items: vietQrBanks
                    .map(
                      (bank) => DropdownMenuItem(
                        value: bank.bin,
                        child: Text('${bank.name} • ${bank.bin}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => bankBin = value ?? bankBin),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountNumber,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(19),
                ],
                decoration: const InputDecoration(
                  labelText: 'Số tài khoản nhận tiền *',
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountName,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Tên chủ tài khoản',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: saving ? null : save,
                icon: const Icon(Icons.save),
                label: Text(saving ? 'Đang lưu' : 'Lưu tài khoản mặc định'),
              ),
            ],
          ),
  );

  Future<void> save() async {
    final number = accountNumber.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{6,19}$').hasMatch(number)) {
      showError(context, 'Số tài khoản phải có từ 6 đến 19 ký tự');
      return;
    }
    setState(() => saving = true);
    await StoreDb.instance.setSetting('payment_bank_bin', bankBin);
    await StoreDb.instance.setSetting('payment_bank_name', selectedBank.name);
    await StoreDb.instance.setSetting('payment_account_number', number);
    await StoreDb.instance.setSetting(
      'payment_account_name',
      accountName.text.trim(),
    );
    if (mounted) {
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu tài khoản nhận tiền')),
      );
    }
  }
}

class PaymentQrCard extends StatelessWidget {
  const PaymentQrCard({
    super.key,
    required this.account,
    required this.amount,
    required this.invoiceCode,
    required this.onSettingsChanged,
  });

  final VietQrAccount? account;
  final int amount;
  final String invoiceCode;
  final Future<void> Function() onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final receiver = account;
    if (receiver == null) {
      return Card(
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chưa cài tài khoản nhận chuyển khoản',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentSettingsPage(),
                    ),
                  );
                  await onSettingsChanged();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Cài tài khoản nhận tiền'),
              ),
            ],
          ),
        ),
      );
    }
    final payload = buildVietQrPayload(
      bankBin: receiver.bankBin,
      accountNumber: receiver.accountNumber,
      amount: amount,
      description: 'MCM $invoiceCode',
    );
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Text(
              'QUÉT MÃ CHUYỂN KHOẢN',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(10),
              child: BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: payload,
                width: 230,
                height: 230,
                drawText: false,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              vnd(amount),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.blue,
              ),
            ),
            Text(
              '${receiver.bankName} • ${receiver.accountNumber}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (receiver.accountName.trim().isNotEmpty)
              Text(receiver.accountName, textAlign: TextAlign.center),
            Text('Nội dung: MCM $invoiceCode'),
            const SizedBox(height: 6),
            const Text(
              'Khách chuyển vào tài khoản trên; loa thanh toán liên kết với '
              'tài khoản sẽ tự thông báo tiền về.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
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
      return DateTimeRange(
        start: start,
        end: start.add(const Duration(days: 1)),
      );
    }
    if (period == 'quarter') {
      final firstMonth = ((anchor.month - 1) ~/ 3) * 3 + 1;
      final start = DateTime(anchor.year, firstMonth);
      return DateTimeRange(
        start: start,
        end: DateTime(anchor.year, firstMonth + 3),
      );
    }
    if (period == 'year') {
      final start = DateTime(anchor.year);
      return DateTimeRange(start: start, end: DateTime(anchor.year + 1));
    }
    final start = DateTime(anchor.year, anchor.month);
    return DateTimeRange(
      start: start,
      end: DateTime(anchor.year, anchor.month + 1),
    );
  }

  String get rangeLabel {
    final current = range;
    if (period == 'day') return DateFormat('dd/MM/yyyy').format(current.start);
    if (period == 'month')
      return 'Tháng ${DateFormat('MM/yyyy').format(current.start)}';
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
              end: DateTime(now.year, now.month, now.day),
            )
          : DateTimeRange(
              start: customRange!.start,
              end: customRange!.end.subtract(const Duration(days: 1)),
            ),
      helpText: 'Chọn khoảng thời gian báo cáo',
      cancelText: 'Hủy',
      confirmText: 'Xem báo cáo',
      saveText: 'Xong',
    );
    if (picked == null || !mounted) return;
    setState(() {
      period = 'custom';
      customRange = DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
        ).add(const Duration(days: 1)),
      );
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
        body: Column(
          children: [
            _filterPanel(),
            Expanded(
              child: FutureBuilder<List<Object?>>(
                future: Future.wait<Object?>([
                  StoreDb.instance.reportSummary(
                    selectedRange.start,
                    selectedRange.end,
                  ),
                  StoreDb.instance.productReport(
                    selectedRange.start,
                    selectedRange.end,
                  ),
                  StoreDb.instance.invoiceReport(
                    selectedRange.start,
                    selectedRange.end,
                  ),
                  StoreDb.instance.salesTrend(trendPeriod),
                ]),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Không thể tải báo cáo: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final summary = snapshot.data![0] as Map<String, int>;
                  final products =
                      snapshot.data![1] as List<Map<String, Object?>>;
                  final invoices =
                      snapshot.data![2] as List<Map<String, Object?>>;
                  final trend = snapshot.data![3] as List<Map<String, Object?>>;
                  return TabBarView(
                    children: [
                      _summaryTab(summary),
                      _productTab(products),
                      _invoiceTab(invoices),
                      _trendTab(trend),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPanel() => Material(
    color: Colors.white,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: period,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Xem báo cáo theo',
                    prefixIcon: Icon(Icons.calendar_month),
                  ),
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
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Chọn ngày',
                onPressed: pickCustomRange,
                icon: const Icon(Icons.date_range),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Kỳ trước',
                onPressed: period == 'custom' ? null : () => shiftPeriod(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  rangeLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Kỳ sau',
                onPressed: period == 'custom' ? null : () => shiftPeriod(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _summaryTab(Map<String, int> data) {
    final net = data['net_profit'] ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Kết quả $rangeLabel',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.35,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            MetricCard(
              'Tổng doanh thu',
              vnd(data['revenue'] ?? 0),
              Icons.trending_up,
              Colors.blue,
            ),
            MetricCard(
              'Lợi nhuận gộp',
              vnd(data['gross_profit'] ?? 0),
              Icons.account_balance_wallet,
              Colors.green,
            ),
            MetricCard(
              'Chi phí sổ quỹ',
              vnd(data['expenses'] ?? 0),
              Icons.payments_outlined,
              Colors.orange,
            ),
            MetricCard(
              'Lợi nhuận sau chi phí',
              vnd(net),
              Icons.savings,
              net < 0 ? Colors.red : Colors.teal,
            ),
            MetricCard(
              'Hóa đơn bán',
              '${data['invoices'] ?? 0}',
              Icons.receipt_long,
              Colors.cyan,
            ),
            MetricCard(
              'Sản phẩm đã bán',
              '${data['products_sold'] ?? 0}',
              Icons.shopping_bag,
              Colors.indigo,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                infoLine('Bán hàng', vnd(data['sales_revenue'] ?? 0)),
                infoLine('Dịch vụ sửa chữa', vnd(data['repair_revenue'] ?? 0)),
                infoLine('Thu khác', vnd(data['other_income'] ?? 0)),
                infoLine('Khách còn nợ', vnd(data['debt'] ?? 0)),
                infoLine('Đã thu từ hóa đơn', vnd(data['collected'] ?? 0)),
                infoLine('Phiếu sửa hoàn tất', '${data['repairs'] ?? 0}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Lợi nhuận sau chi phí = lợi nhuận bán hàng và sửa chữa '
              '+ thu khác − các khoản chi trong Sổ quỹ.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
      ],
    );
  }

  Widget _productTab(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return const EmptyState(
        Icons.inventory_2_outlined,
        'Chưa có hàng hóa',
        'Hãy nhập hàng để xem báo cáo.',
      );
    }
    final totalStock = rows.fold<int>(
      0,
      (sum, row) => sum + (row['stock'] as num? ?? 0).toInt(),
    );
    final stockValue = rows.fold<int>(
      0,
      (sum, row) => sum + (row['stock_value'] as num? ?? 0).toInt(),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Báo cáo hàng hóa • $rangeLabel',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tổng tồn hiện tại'),
                      Text(
                        '$totalStock sản phẩm',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Giá trị tồn'),
                      Text(
                        vnd(stockValue),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...rows.map((row) {
          final sold = (row['sold_quantity'] as num? ?? 0).toInt();
          final revenue = (row['revenue'] as num? ?? 0).toInt();
          final profit = (row['profit'] as num? ?? 0).toInt();
          final stock = (row['stock'] as num? ?? 0).toInt();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: sold > 0
                      ? Colors.blue.shade50
                      : Colors.grey.shade100,
                  child: Icon(
                    Icons.inventory_2,
                    color: sold > 0 ? Colors.blue : Colors.grey,
                  ),
                ),
                title: Text(
                  '${row['name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${row['code']} • Tồn: $stock • Đã bán: $sold\n'
                  'Doanh thu: ${vnd(revenue)} • Lãi: ${vnd(profit)}',
                ),
                isThreeLine: true,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _trendTab(List<Map<String, Object?>> rows) {
    final maxRevenue = rows.fold<int>(
      0,
      (current, row) => (row['revenue'] as num? ?? 0).toInt() > current
          ? (row['revenue'] as num? ?? 0).toInt()
          : current,
    );
    final totalRevenue = rows.fold<int>(
      0,
      (sum, row) => sum + (row['revenue'] as num? ?? 0).toInt(),
    );
    final totalProducts = rows.fold<int>(
      0,
      (sum, row) => sum + (row['products'] as num? ?? 0).toInt(),
    );
    final totalInvoices = rows.fold<int>(
      0,
      (sum, row) => sum + (row['invoices'] as num? ?? 0).toInt(),
    );
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
              icon: Icon(Icons.today),
            ),
            ButtonSegment(
              value: 'month',
              label: Text('Tháng'),
              icon: Icon(Icons.calendar_month),
            ),
            ButtonSegment(
              value: 'year',
              label: Text('Năm'),
              icon: Icon(Icons.event_note),
            ),
          ],
          selected: {trendPeriod},
          onSelectionChanged: (values) =>
              setState(() => trendPeriod = values.first),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                infoLine('Tổng doanh thu bán hàng', vnd(totalRevenue)),
                infoLine('Sản phẩm đã bán', '$totalProducts'),
                infoLine('Số hóa đơn', '$totalInvoices'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        ...rows.map((row) {
          final revenue = (row['revenue'] as num? ?? 0).toInt();
          final products = (row['products'] as num? ?? 0).toInt();
          final invoices = (row['invoices'] as num? ?? 0).toInt();
          final ratio = maxRevenue == 0 ? 0.0 : revenue / maxRevenue;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(
                        '${row['label']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vnd(revenue),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
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
                          Text(
                            '$products sản phẩm • $invoices hóa đơn',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Biểu đồ chỉ so sánh hoạt động bán hàng. Phiếu bảo hành không được tính vào doanh thu hoặc lợi nhuận.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _invoiceTab(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return EmptyState(
        Icons.receipt_long_outlined,
        'Không có hóa đơn',
        'Không có hóa đơn bán hàng trong $rangeLabel.',
      );
    }
    final total = rows.fold<int>(
      0,
      (sum, row) => sum + (row['total'] as num? ?? 0).toInt(),
    );
    final profit = rows.fold<int>(
      0,
      (sum, row) => sum + (row['profit'] as num? ?? 0).toInt(),
    );
    final widgets = <Widget>[
      Text(
        'Báo cáo hóa đơn • $rangeLabel',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Số hóa đơn'),
                    Text(
                      '${rows.length}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      vnd(total),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    Text(
                      'Lãi ${vnd(profit)}',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
    String? lastDay;
    for (final row in rows) {
      final date = parseDate(row['created_at']) ?? DateTime.now();
      final day = DateFormat('dd/MM/yyyy').format(date);
      if (day != lastDay) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              day,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        );
        lastDay = day;
      }
      widgets.add(
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
            title: Text(
              '${row['code']} • ${row['customer']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${DateFormat('HH:mm').format(date)} • ${row['product_names'] ?? ''}'
              '${'${row['imeis'] ?? ''}'.trim().isEmpty ? '' : ' • IMEI ${row['imeis']}'}',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  vnd((row['total'] as num).toInt()),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Lãi ${vnd((row['profit'] as num).toInt())}',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InvoiceDetailPage(saleId: row['id'] as int),
              ),
            ),
          ),
        ),
      );
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
    name = TextEditingController(
      text: '${widget.customer?['customer'] ?? widget.customer?['name'] ?? ''}',
    );
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
    appBar: AppBar(
      title: Text(
        widget.customer == null ? 'Thêm khách hàng' : 'Sửa khách hàng',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Tên khách hàng *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Số điện thoại'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Ghi chú / quà đã tri ân',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save),
          label: const Text('Lưu khách hàng'),
        ),
      ],
    ),
  );

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final result = widget.customer == null
          ? await StoreDb.instance.addCustomerDirectory(
              name: name.text,
              phone: phone.text,
              note: note.text,
            )
          : await StoreDb.instance.updateCustomerDirectory(
              id: widget.customer!['id'] as int,
              name: name.text,
              phone: phone.text,
              note: note.text,
            );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => saving = false);
      }
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
    name = TextEditingController(
      text:
          '${widget.supplier?['supplier_name'] ?? widget.supplier?['name'] ?? ''}',
    );
    phone = TextEditingController(text: '${widget.supplier?['phone'] ?? ''}');
    address = TextEditingController(
      text: '${widget.supplier?['address'] ?? ''}',
    );
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
    appBar: AppBar(
      title: Text(
        widget.supplier == null ? 'Thêm nhà cung cấp' : 'Sửa nhà cung cấp',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Tên nhà cung cấp *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Số điện thoại'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: address,
          decoration: const InputDecoration(labelText: 'Địa chỉ'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Ghi chú'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save),
          label: const Text('Lưu nhà cung cấp'),
        ),
      ],
    ),
  );

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final result = widget.supplier == null
          ? await StoreDb.instance.addSupplierDirectory(
              name: name.text,
              phone: phone.text,
              address: address.text,
              note: note.text,
            )
          : await StoreDb.instance.updateSupplierDirectory(
              id: widget.supplier!['id'] as int,
              name: name.text,
              phone: phone.text,
              address: address.text,
              note: note.text,
            );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => saving = false);
      }
    }
  }
}

class DebtAdjustmentPage extends StatefulWidget {
  const DebtAdjustmentPage({
    super.key,
    required this.partyType,
    required this.partyId,
    required this.partyName,
    required this.currentDebt,
  });
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
  bool isPayment=true;
  String paymentMethod='cash';
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.partyName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  infoLine('Công nợ hiện tại', vnd(widget.currentDebt)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.payments),
                label: const Text('Giảm nợ / đã trả'),
              ),
              const ButtonSegment(
                value: true,
                icon: Icon(Icons.add_card),
                label: Text('Tăng công nợ'),
              ),
            ],
            selected: {increase},
            onSelectionChanged: (value) =>
                setState(() => increase = value.first),
          ),
          if(!increase)...[
            SwitchListTile(title:const Text('Có thu / trả tiền thực tế'),subtitle:const Text('Tắt nếu chỉ điều chỉnh số nợ, không có tiền thu/chi'),value:isPayment,onChanged:(v)=>setState(()=>isPayment=v)),
            if(isPayment)DropdownButtonFormField<String>(initialValue:paymentMethod,decoration:const InputDecoration(labelText:'Phương thức thanh toán'),items:const [DropdownMenuItem(value:'cash',child:Text('Tiền mặt')),DropdownMenuItem(value:'transfer',child:Text('Chuyển khoản'))],onChanged:(v)=>setState(()=>paymentMethod=v!)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Số tiền *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: increase
                  ? 'Lý do tăng nợ'
                  : 'Ghi chú thanh toán / giảm nợ',
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFF5F7FA),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: infoLine('Công nợ sau điều chỉnh', vnd(newDebt)),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save),
            label: const Text('Lưu điều chỉnh'),
          ),
        ],
      ),
    );
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await StoreDb.instance.addDebtAdjustment(
        partyType: widget.partyType,
        partyId: widget.partyId,
        amount: amountValue,
        increase: increase,
        currentDebt: widget.currentDebt,
        note: note.text,
        isPayment:!increase&&isPayment, paymentMethod:paymentMethod,
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

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, this.debtOnly = false});
  final bool debtOnly;
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  late bool debtOnly = widget.debtOnly;
  String search = '';
  String sort = 'recent';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Khách hàng')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.person_add),
      label: const Text('Thêm khách'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.customers(),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final allRows = snap.data!;
        final rows = allRows
            .where(
              (row) =>
                  '${row['customer']} ${row['phone']}'.toLowerCase().contains(
                    search,
                  ) &&
                  (!debtOnly || ((row['debt'] as num? ?? 0) > 0)),
            )
            .toList();
        int number(Map<String, Object?> row, String key) =>
            (row[key] as num? ?? 0).toInt();
        if (sort == 'spent') {
          rows.sort(
            (a, b) =>
                number(b, 'total_spent').compareTo(number(a, 'total_spent')),
          );
        } else if (sort == 'count') {
          rows.sort(
            (a, b) => number(
              b,
              'invoice_count',
            ).compareTo(number(a, 'invoice_count')),
          );
        } else if (sort == 'quantity') {
          rows.sort(
            (a, b) => number(
              b,
              'item_quantity',
            ).compareTo(number(a, 'item_quantity')),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: !debtOnly,
                    onSelected: (_) => setState(() => debtOnly = false),
                  ),
                  ChoiceChip(
                    label: Text(
                      'Công nợ • ${allRows.where((r) => (r['debt'] as num? ?? 0) > 0).length} khách',
                    ),
                    selected: debtOnly,
                    onSelected: (_) => setState(() => debtOnly = true),
                  ),
                ],
              ),
            ),
            if (debtOnly)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Tổng còn nợ: ${vnd(rows.fold<num>(0, (sum, r) => sum + (r['debt'] as num? ?? 0)))}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Tìm tên hoặc số điện thoại',
                ),
                onChanged: (value) =>
                    setState(() => search = value.trim().toLowerCase()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                initialValue: sort,
                decoration: const InputDecoration(
                  labelText: 'Sắp xếp để tri ân',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'recent',
                    child: Text('Giao dịch gần đây'),
                  ),
                  DropdownMenuItem(
                    value: 'count',
                    child: Text('Mua nhiều lần nhất'),
                  ),
                  DropdownMenuItem(
                    value: 'quantity',
                    child: Text('Mua nhiều sản phẩm nhất'),
                  ),
                  DropdownMenuItem(
                    value: 'spent',
                    child: Text('Chi tiêu cao nhất'),
                  ),
                ],
                onChanged: (value) => setState(() => sort = value ?? 'recent'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: allRows.isEmpty
                  ? const EmptyState(
                      Icons.people_outline,
                      'Chưa có khách hàng',
                      'Thêm khách tại đây hoặc khi bán hàng/nhận sửa chữa.',
                    )
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
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${i + 1}')),
                            title: Text(
                              '${r['customer']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${'${r['phone']}'.trim().isEmpty ? 'Không ghi SĐT' : r['phone']}\n'
                              '$invoices lần mua • $quantity sản phẩm • ${number(r, 'service_count')} lần sửa\n'
                              'Tổng giao dịch: ${vnd(number(r, 'total_spent'))}',
                            ),
                            isThreeLine: true,
                            trailing: number(r, 'debt') > 0
                                ? Text(
                                    'Nợ\n${vnd(number(r, 'debt'))}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CustomerDetailPage(customer: r),
                                ),
                              );
                              if (mounted) setState(() {});
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> add() async {
    final created = await Navigator.push<Map<String, Object?>>(
      context,
      MaterialPageRoute(builder: (_) => const CustomerFormPage()),
    );
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
    appBar: AppBar(
      title: Text('${customer['customer']}'),
      actions: [
        IconButton(
          onPressed: edit,
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Sửa khách hàng',
        ),
      ],
    ),
    body: FutureBuilder<List<Object?>>(
      future: Future.wait<Object?>([
        StoreDb.instance.customerSales(
          '${customer['customer']}',
          '${customer['phone']}',
        ),
        StoreDb.instance.customerRepairs(
          '${customer['customer']}',
          '${customer['phone']}',
        ),
        StoreDb.instance.debtAdjustments('customer', customer['id'] as int),
      ]),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final sales = snap.data![0] as List<Map<String, Object?>>;
        final repairs = snap.data![1] as List<Map<String, Object?>>;
        final adjustments = snap.data![2] as List<Map<String, Object?>>;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${customer['customer']}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    infoLine('Số điện thoại', textOrDash(customer['phone'])),
                    infoLine('Số lần mua', '${n('invoice_count')}'),
                    infoLine(
                      'Số hàng đã mua',
                      '${n('item_quantity')} sản phẩm',
                    ),
                    infoLine('Tiền mua hàng', vnd(n('sale_value'))),
                    infoLine('Số lần sửa chữa', '${n('service_count')}'),
                    infoLine('Tổng giao dịch', vnd(n('total_spent'))),
                    infoLine('Còn nợ', vnd(n('debt'))),
                    infoLine(
                      'Lần gần nhất',
                      formatDateTime(customer['last_purchase']),
                    ),
                    if ('${customer['note']}'.trim().isNotEmpty)
                      infoLine('Ghi chú tri ân', '${customer['note']}'),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: adjustDebt,
                        icon: const Icon(Icons.account_balance_wallet),
                        label: const Text('Điều chỉnh công nợ'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Lịch sử công nợ (${adjustments.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (adjustments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa có lần điều chỉnh công nợ.'),
                ),
              ),
            ...adjustments.map((entry) {
              final delta = (entry['amount_delta'] as num).toInt();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(delta > 0 ? Icons.add_card : Icons.payments),
                    ),
                    title: Text(
                      delta > 0
                          ? 'Tăng nợ ${vnd(delta)}'
                          : 'Giảm nợ ${vnd(-delta)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: delta > 0 ? Colors.orange : Colors.green,
                      ),
                    ),
                    subtitle: Text(
                      '${formatDateTime(entry['created_at'])}'
                      '${'${entry['note']}'.trim().isEmpty ? '' : '\n${entry['note']}'}',
                    ),
                    isThreeLine: '${entry['note']}'.trim().isNotEmpty,
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Text(
              'Lịch sử mua hàng (${sales.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (sales.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Khách chưa có hóa đơn mua hàng.'),
                ),
              ),
            ...sales.map(
              (sale) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.receipt_long),
                    ),
                    title: Text(
                      '${sale['code']} • ${vnd(sale['total'] as num)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${formatDateTime(sale['created_at'])}\n'
                      '${sale['product_names'] ?? 'Hàng hóa'} • ${sale['item_quantity']} sản phẩm',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            InvoiceDetailPage(saleId: sale['id'] as int),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Lịch sử sửa chữa (${repairs.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (repairs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Khách chưa có phiếu sửa chữa.'),
                ),
              ),
            ...repairs.map(
              (repair) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.build)),
                    title: Text(
                      '${repair['device']} • ${vnd(repair['amount'] as num)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${repair['code']} • ${formatDateTime(repair['received_at'])}\n'
                      '${repairStatus('${repair['status']}')}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RepairDetailPage(repair: repair),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> edit() async {
    final changed = await Navigator.push<Map<String, Object?>>(
      context,
      MaterialPageRoute(builder: (_) => CustomerFormPage(customer: customer)),
    );
    if (changed == null) return;
    final rows = await StoreDb.instance.customers();
    final fresh = rows.where((row) => row['id'] == changed['id']);
    if (fresh.isNotEmpty && mounted) setState(() => customer = fresh.first);
  }

  Future<void> adjustDebt() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DebtAdjustmentPage(
          partyType: 'customer',
          partyId: customer['id'] as int,
          partyName: '${customer['customer']}',
          currentDebt: n('debt'),
        ),
      ),
    );
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
      onPressed: add,
      icon: const Icon(Icons.add_business),
      label: const Text('Thêm nhà cung cấp'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm tên hoặc số điện thoại',
            ),
            onChanged: (value) =>
                setState(() => search = value.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: StoreDb.instance.suppliers(),
            builder: (context, snap) {
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final allRows = snap.data!;
              final rows = allRows
                  .where(
                    (row) => '${row['supplier_name']} ${row['phone']}'
                        .toLowerCase()
                        .contains(search),
                  )
                  .toList();
              if (allRows.isEmpty)
                return const EmptyState(
                  Icons.local_shipping_outlined,
                  'Chưa có nhà cung cấp',
                  'Thêm tại đây hoặc ngay khi lập phiếu nhập hàng.',
                );
              if (rows.isEmpty)
                return const Center(child: Text('Không tìm thấy nhà cung cấp'));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final debt = (r['debt'] as num? ?? 0).toInt();
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.local_shipping),
                      ),
                      title: Text(
                        '${r['supplier_name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${r['purchase_count']} lần nhập • ${r['total_quantity']} sản phẩm\n'
                        'Tổng đã nhập: ${vnd(r['total_purchase'] as num)}\n'
                        'Gần nhất: ${formatDateTime(r['last_purchase'])}',
                      ),
                      isThreeLine: true,
                      trailing: debt > 0
                          ? Text(
                              'Còn nợ\n${vnd(debt)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SupplierDetailPage(supplier: r),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  Future<void> add() async {
    final created = await Navigator.push<Map<String, Object?>>(
      context,
      MaterialPageRoute(builder: (_) => const SupplierFormPage()),
    );
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
    appBar: AppBar(
      title: Text('${supplier['supplier_name']}'),
      actions: [
        IconButton(
          onPressed: edit,
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Sửa nhà cung cấp',
        ),
      ],
    ),
    body: FutureBuilder<List<Object?>>(
      future: Future.wait<Object?>([
        StoreDb.instance.supplierPurchases('${supplier['supplier_name']}'),
        StoreDb.instance.debtAdjustments('supplier', supplier['id'] as int),
      ]),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final rows = snap.data![0] as List<Map<String, Object?>>;
        final adjustments = snap.data![1] as List<Map<String, Object?>>;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${supplier['supplier_name']}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    infoLine('Số điện thoại', textOrDash(supplier['phone'])),
                    infoLine('Địa chỉ', textOrDash(supplier['address'])),
                    infoLine('Số lần nhập', '${n('purchase_count')}'),
                    infoLine(
                      'Số hàng đã nhập',
                      '${n('total_quantity')} sản phẩm',
                    ),
                    infoLine('Tổng tiền nhập', vnd(n('total_purchase'))),
                    infoLine('Còn nợ NCC', vnd(n('debt'))),
                    infoLine(
                      'Lần gần nhất',
                      formatDateTime(supplier['last_purchase']),
                    ),
                    if ('${supplier['note']}'.trim().isNotEmpty)
                      infoLine('Ghi chú', '${supplier['note']}'),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: adjustDebt,
                        icon: const Icon(Icons.account_balance_wallet),
                        label: const Text('Điều chỉnh công nợ'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Lịch sử công nợ (${adjustments.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (adjustments.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa có lần điều chỉnh công nợ.'),
                ),
              ),
            ...adjustments.map((entry) {
              final delta = (entry['amount_delta'] as num).toInt();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(delta > 0 ? Icons.add_card : Icons.payments),
                    ),
                    title: Text(
                      delta > 0
                          ? 'Tăng nợ ${vnd(delta)}'
                          : 'Đã trả / giảm nợ ${vnd(-delta)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: delta > 0 ? Colors.orange : Colors.green,
                      ),
                    ),
                    subtitle: Text(
                      '${formatDateTime(entry['created_at'])}'
                      '${'${entry['note']}'.trim().isEmpty ? '' : '\n${entry['note']}'}',
                    ),
                    isThreeLine: '${entry['note']}'.trim().isNotEmpty,
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Text(
              'Lịch sử nhập hàng (${rows.length})',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa có phiếu nhập từ nhà cung cấp này.'),
                ),
              ),
            ...rows.map((purchase) {
              final total = (purchase['total'] as num? ?? 0).toInt();
              final paid = (purchase['paid'] as num? ?? 0).toInt();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.inventory)),
                    title: Text(
                      '${purchase['code']} • ${vnd(total)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${formatDateTime(purchase['created_at'])}\n'
                      '${purchase['product_names'] ?? 'Hàng hóa'}\n'
                      '${purchase['total_quantity']} sản phẩm • Đã trả ${vnd(paid)}',
                    ),
                    isThreeLine: true,
                    trailing: total > paid
                        ? Text(
                            'Nợ ${vnd(total - paid)}',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : const Icon(Icons.check_circle, color: Colors.green),
                  ),
                ),
              );
            }),
          ],
        );
      },
    ),
  );

  Future<void> edit() async {
    final changed = await Navigator.push<Map<String, Object?>>(
      context,
      MaterialPageRoute(builder: (_) => SupplierFormPage(supplier: supplier)),
    );
    if (changed == null) return;
    final rows = await StoreDb.instance.suppliers();
    final fresh = rows.where((row) => row['id'] == changed['id']);
    if (fresh.isNotEmpty && mounted) setState(() => supplier = fresh.first);
  }

  Future<void> adjustDebt() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DebtAdjustmentPage(
          partyType: 'supplier',
          partyId: supplier['id'] as int,
          partyName: '${supplier['supplier_name']}',
          currentDebt: n('debt'),
        ),
      ),
    );
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
  final searchController = TextEditingController();
  String search = '';
  String category = '';
  List<String> categories = [];

  @override
  void initState() {
    super.initState();
    loadCategories();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadCategories() async {
    final rows = await StoreDb.instance.productCategories();
    if (mounted) {
      setState(() => categories = rows.map((row) => '${row['name']}').toList());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kiểm kho')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Tên, mã hàng hoặc IMEI',
              suffixIcon: IconButton(
                tooltip: 'Quét mã / IMEI',
                onPressed: scanStock,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
            onChanged: (value) =>
                setState(() => search = value.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(
              labelText: 'Phân loại hàng tồn',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Tất cả phân loại'),
              ),
              ...categories.map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              ),
            ],
            onChanged: (value) => setState(() => category = value ?? ''),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: StoreDb.instance.products(),
            builder: (context, snap) {
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final rows = snap.data!.where((product) {
                final text =
                    ('${product['name']} ${product['code']} '
                            '${product['category']} ${product['imeis'] ?? ''}')
                        .toLowerCase();
                final matchesSearch = search.isEmpty || text.contains(search);
                final matchesCategory =
                    category.isEmpty ||
                    '${product['category']}'.toLowerCase() ==
                        category.toLowerCase();
                return matchesSearch && matchesCategory;
              }).toList();
              if (rows.isEmpty)
                return const EmptyState(
                  Icons.fact_check_outlined,
                  'Chưa có hàng hóa',
                  'Hãy tạo và nhập hàng trước khi kiểm kho.',
                );
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Tồn kho hiện tại',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...rows.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: Icon(
                            p['track_imei'] == 1
                                ? Icons.phone_android
                                : Icons.inventory_2,
                          ),
                          title: Text(
                            '${p['name']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            p['track_imei'] == 1
                                ? 'Kiểm theo số lượng và danh sách IMEI'
                                : 'Kiểm và cân bằng lại số lượng',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tồn ${p['stock']}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (p['track_imei'] == 1)
                                IconButton(
                                  tooltip: 'Xem danh sách IMEI',
                                  icon: const Icon(Icons.list_alt),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ProductDetail(
                                        product: p,
                                        onChanged: () => setState(() {}),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => count(p),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Lịch sử kiểm gần đây',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Map<String, Object?>>>(
                    future: StoreDb.instance.stocktakeHistory(),
                    builder: (context, historySnap) {
                      if (!historySnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final history = historySnap.data!;
                      if (history.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('Chưa có phiếu kiểm kho.'),
                          ),
                        );
                      }
                      return Column(
                        children: history.map((h) {
                          final difference = h['difference'] as int;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    difference == 0
                                        ? '='
                                        : difference > 0
                                        ? '+'
                                        : '−',
                                  ),
                                ),
                                title: Text(
                                  '${h['product_name']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${formatDateTime(h['created_at'])}\nHệ thống: ${h['system_quantity']} • Thực tế: ${h['actual_quantity']}',
                                ),
                                isThreeLine: true,
                                trailing: Text(
                                  difference == 0
                                      ? 'Khớp'
                                      : '${difference > 0 ? '+' : ''}$difference',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: difference == 0
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  Future<void> scanStock() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodePage(title: 'Quét hàng tồn / IMEI'),
      ),
    );
    if (raw == null || !mounted) return;
    final value = extractImei(raw) ?? raw.trim();
    searchController.text = value;
    setState(() => search = value.toLowerCase());
  }

  Future<void> count(Map<String, Object?> product) async {
    final actual = TextEditingController(text: '${product['stock']}');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Kiểm ${product['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tồn trên ứng dụng: ${product['stock']}'),
              const SizedBox(height: 12),
              TextField(
                controller: actual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số lượng đếm thực tế',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
              ),
              if (product['track_imei'] == 1) ...[
                const SizedBox(height: 10),
                const Text(
                  'Với điện thoại, phiếu kiểm chỉ ghi nhận chênh lệch. Muốn giảm kho phải chọn đúng IMEI tại Trả hàng nhập hoặc Xuất hủy.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bỏ qua'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lưu kiểm kho'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StoreDb.instance.recordStocktake(
        product: product,
        actualQuantity: int.tryParse(actual.text) ?? -1,
        note: note.text,
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu kết quả kiểm kho')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
          final products = (snap.data ?? [])
              .where((p) => (p['stock'] as int) > 0)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                returning ? 'Chọn hàng còn trong kho để trả lại nhà cung cấp.' : 'Chọn hàng hỏng, mất hoặc không còn giá trị để xuất khỏi kho.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: product?['id'] as int?,
                decoration: const InputDecoration(labelText: 'Hàng hóa *'),
                items: products
                    .map(
                      (p) => DropdownMenuItem<int>(
                        value: p['id'] as int,
                        child: Text('${p['name']} • tồn ${p['stock']}'),
                      ),
                    )
                    .toList(),
                onChanged: (id) => setState(() {
                  product = products.firstWhere((p) => p['id'] == id);
                  serialId = null;
                }),
              ),
              if (product?['track_imei'] == 1)
                FutureBuilder<List<Map<String, Object?>>>(
                  future: StoreDb.instance.serials(
                    product!['id'] as int,
                    status: 'in_stock',
                  ),
                  builder: (context, serialSnap) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: DropdownButtonFormField<int>(
                      initialValue: serialId,
                      decoration: const InputDecoration(
                        labelText: 'Chọn IMEI *',
                      ),
                      items: (serialSnap.data ?? [])
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: s['id'] as int,
                              child: Text('${s['imei']} • ${s['color']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => serialId = value),
                    ),
                  ),
                )
              else if (product != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Số lượng *'),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: saving ? null : save,
                icon: Icon(
                  returning ? Icons.assignment_return : Icons.delete_sweep,
                ),
                label: Text(
                  returning ? 'Xác nhận trả hàng' : 'Xác nhận xuất hủy',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> save() async {
    if (product == null) return showError(context, 'Hãy chọn hàng hóa');
    setState(() => saving = true);
    try {
      await StoreDb.instance.inventoryAction(
        product: product!,
        kind: widget.kind,
        quantity: int.tryParse(quantity.text) ?? 0,
        serialId: serialId,
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
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const Text('Nhận máy'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: StoreDb.instance.repairs(),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty)
          return const EmptyState(
            Icons.build_outlined,
            'Chưa có phiếu sửa chữa',
            'Bấm “Nhận máy” để tạo phiếu đầu tiên.',
          );
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = rows[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(repairIcon('${r['status']}')),
                ),
                title: Text(
                  '${r['device']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${r['code']} • ${r['customer']}\n${repairStatus('${r['status']}')} • ${formatDateTime(r['received_at'])}',
                ),
                isThreeLine: true,
                trailing: Text(
                  vnd(r['amount'] as int),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RepairDetailPage(repair: r),
                    ),
                  );
                  if (changed == true && mounted) setState(() {});
                },
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> add() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RepairForm()),
    );
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
    partsCost = TextEditingController(
      text: r == null ? '' : '${r['parts_cost']}',
    );
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
        final samePhone =
            phone.text.trim().isNotEmpty &&
            '${row['phone']}'.trim() == phone.text.trim();
        final sameName =
            '${row['name']}'.trim().toLowerCase() ==
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
      customer.text = id == 0 || selected.isEmpty
          ? ''
          : '${selected.first['name']}';
      phone.text = id == 0 || selected.isEmpty
          ? ''
          : '${selected.first['phone']}';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(editing ? 'Sửa phiếu sửa chữa' : 'Nhận máy sửa chữa'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey(
            'repair-customer-$selectedCustomerId-${customers.length}',
          ),
          initialValue: selectedCustomerId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Chọn nhanh khách hàng',
            prefixIcon: Icon(Icons.person_search),
          ),
          items: [
            const DropdownMenuItem(
              value: 0,
              child: Text('Khách lẻ / nhập tay'),
            ),
            ...customers.map(
              (row) => DropdownMenuItem(
                value: row['id'] as int,
                child: Text(
                  '${row['name']}${'${row['phone']}'.trim().isEmpty ? '' : ' • ${row['phone']}'}',
                ),
              ),
            ),
            const DropdownMenuItem(
              value: -1,
              child: Text('+ Thêm khách hàng mới'),
            ),
          ],
          onChanged: _pickCustomer,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: customer,
          decoration: const InputDecoration(labelText: 'Tên khách hàng'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Số điện thoại'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: device,
          decoration: const InputDecoration(labelText: 'Tên máy *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: imei,
          decoration: const InputDecoration(labelText: 'IMEI'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: issue,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Tình trạng lỗi *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Giá sửa dự kiến'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: partsCost,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Tiền linh kiện / giá vốn',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: paid,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Khách đã thanh toán'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Ghi chú'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save),
          label: Text(editing ? 'Lưu thay đổi' : 'Lưu phiếu nhận máy'),
        ),
      ],
    ),
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
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RepairForm(repair: repair)),
    );
    if (saved == true) await reload();
  }

  Future<void> remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa phiếu sửa chữa?'),
        content: const Text(
          'Phiếu sẽ biến mất khỏi danh sách nhưng số lượng hàng, doanh thu và lợi nhuận đã ghi nhận vẫn được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa khỏi danh sách'),
          ),
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
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              tooltip: 'Xóa phiếu',
              onPressed: remove,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceiptPreviewPage(receipt: receipt),
                ),
              ),
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
                    Text(
                      '${r['device']}',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    infoLine('Khách hàng', '${r['customer']}'),
                    infoLine(
                      'Số điện thoại',
                      '${r['phone']}'.trim().isEmpty
                          ? 'Không ghi'
                          : '${r['phone']}',
                    ),
                    infoLine(
                      'IMEI',
                      '${r['imei']}'.trim().isEmpty
                          ? 'Không ghi'
                          : '${r['imei']}',
                    ),
                    infoLine('Ngày nhận', formatDateTime(r['received_at'])),
                    infoLine('Tình trạng', '${r['issue']}'),
                    infoLine(
                      'Ghi chú',
                      '${r['note']}'.trim().isEmpty
                          ? 'Không có'
                          : '${r['note']}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chi phí',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    infoLine('Tiền sửa', vnd(r['amount'] as int)),
                    infoLine('Giá vốn', vnd(r['parts_cost'] as int)),
                    infoLine(
                      'Lợi nhuận dự kiến',
                      vnd((r['amount'] as int) - (r['parts_cost'] as int)),
                    ),
                    infoLine('Đã thu', vnd(r['paid'] as int)),
                    infoLine(
                      'Khách còn nợ',
                      vnd((r['amount'] as int) - (r['paid'] as int)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('repair-status-$status'),
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Trạng thái phiếu'),
              items:
                  const [
                        'received',
                        'repairing',
                        'completed',
                        'returned',
                        'cancelled',
                      ]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(repairStatus(value)),
                        ),
                      )
                      .toList(),
              onChanged: (value) async {
                if (value == null) return;
                await StoreDb.instance.updateRepairStatus(
                  r['id'] as int,
                  value,
                );
                await reload();
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, changed),
              child: const Text('Xong'),
            ),
          ],
        ),
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
  final searchController = TextEditingController();
  String search = '';
  PeriodFilter period = PeriodFilter.month(DateTime.now());

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tra cứu bảo hành')),
    body: Column(
      children: [
        PeriodPicker(
          value: period,
          onChanged: (v) => setState(() => period = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Nhập IMEI, tên máy, tên khách hoặc SĐT',
              suffixIcon: IconButton(
                tooltip: 'Quét IMEI',
                onPressed: scanWarranty,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
            onChanged: (value) =>
                setState(() => search = value.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: StoreDb.instance.warranties(),
            builder: (context, snap) {
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final allRows = snap.data!;
              final rows = allRows.where((r) {
                final haystack =
                    '${r['product_name']} ${r['customer']} ${r['phone']} '
                    '${r['imei'] ?? ''} ${r['code']} ${formatDateTime(r['created_at'])}';
                return haystack.toLowerCase().contains(search) &&
                    period.includes(parseDate(r['created_at']));
              }).toList();
              if (rows.isEmpty) {
                return EmptyState(
                  Icons.verified_user_outlined,
                  allRows.isEmpty
                      ? 'Chưa có máy đã bán'
                      : 'Không tìm thấy thông tin',
                  allRows.isEmpty
                      ? 'Máy sẽ xuất hiện ở đây sau khi tạo hóa đơn bán hàng.'
                      : 'Hãy kiểm tra lại IMEI, tên máy hoặc tên khách.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final months = r['warranty_months'] as int;
                  final sold = parseDate(r['created_at']);
                  final end = sold == null || months <= 0
                      ? null
                      : addMonths(sold, months);
                  final active =
                      months > 0 && end != null && !DateTime.now().isAfter(end);
                  final noWarranty = months <= 0;
                  final statusText = noWarranty
                      ? 'Hóa đơn không có bảo hành'
                      : active
                      ? 'Còn bảo hành đến ${DateFormat('dd/MM/yyyy').format(end)}'
                      : 'Đã hết bảo hành ${end == null ? '' : 'từ ${DateFormat('dd/MM/yyyy').format(end)}'}';
                  final statusColor = noWarranty
                      ? Colors.grey
                      : (active ? Colors.green : Colors.red);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withValues(alpha: 0.1),
                        child: Icon(
                          noWarranty
                              ? Icons.gpp_maybe
                              : active
                              ? Icons.verified_user
                              : Icons.gpp_bad,
                          color: statusColor,
                        ),
                      ),
                      title: Text(
                        '${r['product_name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${r['customer']} • ${r['imei'] == null || '${r['imei']}'.trim().isEmpty ? 'Không IMEI' : r['imei']}\n'
                        '$statusText${(r['claim_count'] as num).toInt() > 0 ? ' • ${r['claim_count']} lần tiếp nhận' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WarrantyDetailPage(warranty: r),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  Future<void> scanWarranty() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanCodePage(title: 'Quét IMEI tra bảo hành'),
      ),
    );
    if (raw == null || !mounted) return;
    final value = extractImei(raw) ?? raw.trim();
    searchController.text = value;
    setState(() => search = value.toLowerCase());
  }
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
    final receipt = ReceiptDocument.warranty(w);
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý bảo hành')),
      floatingActionButton: active
          ? FloatingActionButton.extended(
              onPressed: addClaim,
              icon: const Icon(Icons.add),
              label: const Text('Tiếp nhận bảo hành'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReceiptPreviewPage(receipt: receipt),
              ),
            ),
            icon: const Icon(Icons.print),
            label: const Text('In / chia sẻ phiếu bảo hành'),
          ),
          const SizedBox(height: 12),
          if (!active)
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        months <= 0
                            ? 'Hóa đơn này không có thời hạn bảo hành.'
                            : 'Sản phẩm đã hết thời hạn bảo hành.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!active) const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${w['product_name']}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  infoLine('Khách hàng', '${w['customer']}'),
                  infoLine(
                    'Số điện thoại',
                    '${w['phone']}'.trim().isEmpty
                        ? 'Không ghi'
                        : '${w['phone']}',
                  ),
                  infoLine(
                    'IMEI',
                    '${w['imei']}'.trim().isEmpty || w['imei'] == null
                        ? 'Không ghi'
                        : '${w['imei']}',
                  ),
                  infoLine('Hóa đơn', '${w['code']}'),
                  infoLine('Ngày bán', formatDateTime(w['created_at'])),
                  infoLine('Thời hạn', warrantyLabel(months)),
                  infoLine(
                    'Hết hạn',
                    months <= 0
                        ? 'Không có'
                        : end == null
                        ? 'Không rõ'
                        : DateFormat('dd/MM/yyyy').format(end),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            InvoiceDetailPage(saleId: w['sale_id'] as int),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Xem hóa đơn gốc'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Lịch sử tiếp nhận',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, Object?>>>(
            future: StoreDb.instance.warrantyClaims(w['sale_item_id'] as int),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Chưa có lần tiếp nhận bảo hành nào.'),
                  ),
                );
              }
              return Column(
                children: rows
                    .map(
                      (r) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${r['issue']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Sửa phiếu bảo hành',
                                    onPressed: () => editClaim(r),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Xóa phiếu bảo hành',
                                    onPressed: () => deleteClaim(r),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'Ngày nhận: ${formatDateTime(r['received_at'])}',
                              ),
                              if ('${r['note']}'.trim().isNotEmpty)
                                Text('Ghi chú: ${r['note']}'),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'warranty-status-${r['id']}-${r['status']}',
                                ),
                                initialValue: '${r['status']}',
                                decoration: const InputDecoration(
                                  labelText: 'Trạng thái',
                                ),
                                items:
                                    const [
                                          'received',
                                          'processing',
                                          'waiting_parts',
                                          'completed',
                                          'returned',
                                        ]
                                        .map(
                                          (value) => DropdownMenuItem(
                                            value: value,
                                            child: Text(warrantyStatus(value)),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (value) async {
                                  if (value == null) return;
                                  await StoreDb.instance
                                      .updateWarrantyClaimStatus(
                                        r['id'] as int,
                                        value,
                                      );
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: issue,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Tình trạng máy *',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'issue': issue.text,
              'note': note.text,
            }),
            child: const Text('Tiếp nhận'),
          ),
        ],
      ),
    );
    issue.dispose();
    note.dispose();
    if (result == null) return;
    try {
      await StoreDb.instance.addWarrantyClaim(
        saleItemId: widget.warranty['sale_item_id'] as int,
        issue: result['issue'] ?? '',
        note: result['note'] ?? '',
      );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: issue,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Tình trạng máy *',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'issue': issue.text,
              'note': note.text,
            }),
            child: const Text('Lưu thay đổi'),
          ),
        ],
      ),
    );
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
          'Lần tiếp nhận này sẽ bị xóa khỏi danh sách. Số lượng hàng, doanh thu và lợi nhuận không thay đổi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa hẳn'),
          ),
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
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sao lưu dữ liệu',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  kIsWeb ? 'Tải bản sao lưu JSON về máy tính. Cất giữ tệp này để khôi phục kho, hóa đơn, công nợ và lịch sử khi cần.' : 'Ứng dụng sẽ sao chép toàn bộ kho, hóa đơn, bảo hành, sửa chữa và sổ quỹ vào bộ nhớ tạm. Hãy dán nội dung đó vào Ghi chú hoặc một tệp riêng để cất giữ.',
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: busy ? null : backup,
                  icon: const Icon(Icons.copy_all),
                  label: const Text(kIsWeb ? 'Tải bản sao lưu' : 'Sao chép bản sao lưu'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Khôi phục dữ liệu',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dán nguyên nội dung bản sao lưu đã lưu trước đó vào ô bên dưới.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: restoreText,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Dán dữ liệu sao lưu tại đây',
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : restore,
                  icon: const Icon(Icons.restore),
                  label: const Text('Khôi phục từ bản sao'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> backup() async {
    setState(() => busy = true);
    try {
      final data = await StoreDb.instance.exportBackup();
      if(kIsWeb) {
        if(mounted) await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
          title:const Text('Bản sao lưu đã sẵn sàng'),content:const Text('Bấm tải tệp JSON. Khi cần khôi phục, mở tệp và dán toàn bộ nội dung vào ô khôi phục.'),
          actions:[FilledButton(onPressed:(){browserDownloadBackup(data,'MinhCanh-backup-${DateTime.now().millisecondsSinceEpoch}.json');Navigator.pop(ctx);},child:const Text('Tải tệp JSON'))]));
        return;
      }
      await Clipboard.setData(ClipboardData(text: data));
      if (mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Đã sao chép'),
            content: const Text(
              'Toàn bộ dữ liệu đã được sao chép. Anh hãy mở Ghi chú, dán vào và lưu lại. Không chỉnh sửa nội dung bản sao.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Đã hiểu'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {if(mounted)setState(()=>busy=false);}
  }

  Future<void> restore() async {
    if (restoreText.text.trim().isEmpty)
      return showError(context, 'Chưa có nội dung sao lưu');
    if (!await confirm(
      context,
      'Khôi phục dữ liệu',
      'Dữ liệu hiện tại trong ứng dụng sẽ được thay bằng bản sao này. Tiếp tục?',
    ))
      return;
    setState(() => busy = true);
    try {
      await StoreDb.instance.restoreBackup(restoreText.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Khôi phục dữ liệu thành công')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => busy = false);
      }
    }
  }
}

class ProductLabelData {
  const ProductLabelData({
    required this.productName,
    required this.detail,
    required this.code,
    required this.price,
    required this.isImei,
  });

  final String productName;
  final String detail;
  final String code;
  final int price;
  final bool isImei;
}

ProductLabelData labelForSerial(
  Map<String, Object?> product,
  Map<String, Object?> serial,
) {
  final details = [product['capacity'], serial['color']]
      .map((value) => '${value ?? ''}'.trim())
      .where((value) => value.isNotEmpty)
      .join(' • ');
  return ProductLabelData(
    productName: '${product['name']}',
    detail: details,
    code: '${serial['imei']}',
    price: (product['sale_price'] as num).toInt(),
    isImei: true,
  );
}

class LabelPaper extends StatelessWidget {
  const LabelPaper({
    super.key,
    required this.label,
    required this.showPrice,
    this.width = 320,
  });

  final ProductLabelData label;
  final bool showPrice;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 0.75,
    color: Colors.white,
    padding: EdgeInsets.all(width * 0.035),
    child: DefaultTextStyle(
      style: TextStyle(
        color: Colors.black,
        fontSize: width * 0.037,
        height: 1.05,
      ),
      child: Column(
        children: [
          Text(
            'MINH CẢNH MOBILE',
            maxLines: 1,
            style: TextStyle(
              fontSize: width * 0.048,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: width * 0.012),
          Text(
            label.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: width * 0.052,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (label.detail.isNotEmpty)
            Text(label.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
          SizedBox(height: width * 0.012),
          Expanded(
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: label.code,
              drawText: false,
              color: Colors.black,
              backgroundColor: Colors.white,
            ),
          ),
          SizedBox(height: width * 0.008),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${label.isImei ? 'IMEI' : 'Mã'}: ${label.code}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (showPrice)
                Text(
                  vnd(label.price),
                  style: TextStyle(
                    fontSize: width * 0.048,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ProductLabelPrinter {
  static Future<Uint8List> render(
    BuildContext context,
    ProductLabelData label,
    bool showPrice,
  ) async {
    final controller = ScreenshotController();
    return controller.captureFromWidget(
      InheritedTheme.captureAll(
        context,
        Material(
          color: Colors.white,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: LabelPaper(label: label, showPrice: showPrice),
          ),
        ),
      ),
      delay: const Duration(milliseconds: 60),
      pixelRatio: 1,
    );
  }

  static Future<List<int>> thermalBytes(Uint8List png) async {
    final decoded = img.decodeImage(png);
    if (decoded == null) throw Exception('Không thể tạo ảnh tem');
    final printable = img.copyResize(
      decoded,
      width: 320,
      height: 240,
      interpolation: img.Interpolation.average,
    );
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    return <int>[
      ...generator.reset(),
      ...generator.imageRaster(printable, align: PosAlign.center),
      ...generator.feed(1),
    ];
  }

  static Future<void> print(
    BuildContext context,
    List<ProductLabelData> labels,
    bool showPrice,
  ) async {
    if(kIsWeb){await share(context,labels,showPrice);return;}
    final mac =
        await StoreDb.instance.getSetting('label_printer_bluetooth_mac') ?? '';
    if (mac.isEmpty) {
      throw Exception('Chưa chọn máy in tem Bluetooth 40×30');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw Exception('Bluetooth đang tắt. Hãy bật Bluetooth rồi thử lại');
    }
    var connected = await PrintBluetoothThermal.connectionStatus;
    if (!connected) {
      connected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    }
    if (!connected) throw Exception('Không kết nối được máy in tem');
    for (final label in labels) {
      final png = await render(context, label, showPrice);
      final ok = await PrintBluetoothThermal.writeBytes(
        await thermalBytes(png),
      );
      if (!ok) throw Exception('Máy in không nhận dữ liệu tem');
    }
  }

  static Future<void> share(
    BuildContext context,
    List<ProductLabelData> labels,
    bool showPrice,
  ) async {
    final document = pw.Document();
    for (final label in labels) {
      final png = await render(context, label, showPrice);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            40 * PdfPageFormat.mm,
            30 * PdfPageFormat.mm,
            marginAll: 0,
          ),
          build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
        ),
      );
    }
    final bytes = await document.save();
    if(kIsWeb){await offerBrowserPdf(context,bytes,'Tem_40x30_Minh_Canh_Mobile.pdf');return;}
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
        fileNameOverrides: const ['Tem_40x30_Minh_Canh_Mobile.pdf'],
        subject: 'Tem hàng hóa 40×30 Minh Cảnh Mobile',
      ),
    );
  }
}

class LabelPreviewPage extends StatefulWidget {
  const LabelPreviewPage({super.key, required this.labels});
  final List<ProductLabelData> labels;

  @override
  State<LabelPreviewPage> createState() => _LabelPreviewPageState();
}

class _LabelPreviewPageState extends State<LabelPreviewPage> {
  bool showPrice = true;
  bool busy = false;
  int index = 0;

  @override
  void initState() {
    super.initState();
    loadPreference();
  }

  Future<void> loadPreference() async {
    final saved = await StoreDb.instance.getSetting('label_show_price');
    if (mounted && saved != null) {
      setState(() => showPrice = saved != '0');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Xem trước tem 40×30')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: SwitchListTile(
            title: const Text('Hiện giá bán trên tem'),
            subtitle: Text(
              showPrice
                  ? 'Tem sẽ in giá bán'
                  : 'Tem chỉ in tên hàng và mã vạch/IMEI',
            ),
            value: showPrice,
            onChanged: (value) async {
              setState(() => showPrice = value);
              await StoreDb.instance.setSetting(
                'label_show_price',
                value ? '1' : '0',
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 255,
          child: PageView.builder(
            itemCount: widget.labels.length,
            onPageChanged: (value) => setState(() => index = value),
            itemBuilder: (context, itemIndex) => Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8),
                  ],
                ),
                child: LabelPaper(
                  label: widget.labels[itemIndex],
                  showPrice: showPrice,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tem ${index + 1}/${widget.labels.length} • Khổ 40×30 mm',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: busy ? null : share,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Chia sẻ PDF tem 40×30'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: busy ? null : printLabels,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print),
          label: Text(
            busy ? 'Đang in' : 'In ${widget.labels.length} tem qua Bluetooth',
          ),
        ),
      ],
    ),
  );

  Future<void> printLabels() async {
    setState(() => busy = true);
    try {
      await ProductLabelPrinter.print(context, widget.labels, showPrice);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã gửi tem tới máy in')));
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> share() async {
    setState(() => busy = true);
    try {
      await ProductLabelPrinter.share(context, widget.labels, showPrice);
    } catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) setState(() => busy = false);
  }
}

class LabelPrinterSettingsPage extends StatefulWidget {
  const LabelPrinterSettingsPage({super.key});

  @override
  State<LabelPrinterSettingsPage> createState() =>
      _LabelPrinterSettingsPageState();
}

class _LabelPrinterSettingsPageState extends State<LabelPrinterSettingsPage> {
  String bluetoothMac = '';
  String bluetoothName = '';
  List<BluetoothInfo> devices = [];
  bool loading = true;
  bool searching = false;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    bluetoothMac =
        await StoreDb.instance.getSetting('label_printer_bluetooth_mac') ?? '';
    bluetoothName =
        await StoreDb.instance.getSetting('label_printer_bluetooth_name') ?? '';
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Máy in tem 40×30')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Ghép đôi máy in tem trong Cài đặt Bluetooth của điện '
                    'thoại trước, sau đó chọn máy tại đây.',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                bluetoothName.isEmpty
                    ? 'Chưa chọn máy in tem'
                    : 'Đã chọn: $bluetoothName\n$bluetoothMac',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: searching ? null : searchBluetooth,
                icon: searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(searching ? 'Đang tìm' : 'Tìm máy đã ghép đôi'),
              ),
              ...devices.map(
                (device) => RadioListTile<String>(
                  value: device.macAdress,
                  groupValue: bluetoothMac,
                  title: Text(
                    device.name.isEmpty ? 'Máy in Bluetooth' : device.name,
                  ),
                  subtitle: Text(device.macAdress),
                  onChanged: (value) => setState(() {
                    bluetoothMac = value ?? '';
                    bluetoothName = device.name.isEmpty
                        ? 'Máy in Bluetooth'
                        : device.name;
                  }),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: bluetoothMac.isEmpty ? null : save,
                icon: const Icon(Icons.save),
                label: const Text('Lưu máy in tem'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: testing || bluetoothMac.isEmpty ? null : test,
                icon: testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print),
                label: const Text('In thử tem 40×30'),
              ),
            ],
          ),
  );

  Future<void> searchBluetooth() async {
    setState(() => searching = true);
    try {
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        throw Exception('Bluetooth đang tắt');
      }
      final rows = await PrintBluetoothThermal.pairedBluetooths;
      if (mounted) setState(() => devices = rows);
      if (rows.isEmpty) {
        throw Exception('Không thấy máy Bluetooth đã ghép đôi');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) setState(() => searching = false);
  }

  Future<void> save() async {
    await StoreDb.instance.setSetting(
      'label_printer_bluetooth_mac',
      bluetoothMac,
    );
    await StoreDb.instance.setSetting(
      'label_printer_bluetooth_name',
      bluetoothName,
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã lưu máy in tem')));
    }
  }

  Future<void> test() async {
    setState(() => testing = true);
    try {
      await save();
      if (mounted) {
        await ProductLabelPrinter.print(context, const [
          ProductLabelData(
            productName: 'TEM IN THỬ',
            detail: 'Khổ 40×30 mm',
            code: 'SP000001',
            price: 123000,
            isImei: false,
          ),
        ], true);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
    if (mounted) setState(() => testing = false);
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
    Map<String, Object?> sale,
    List<Map<String, Object?>> rows,
  ) {
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
        MapEntry(
          'Trạng thái',
          sale['status'] == 'cancelled' ? 'ĐÃ HỦY' : 'Hoàn thành',
        ),
      ],
      items: rows
          .map(
            (item) => ReceiptItem(
              name: '${item['product_name']}',
              detail: [
                if (item['imei'] != null && '${item['imei']}'.trim().isNotEmpty)
                  'IMEI: ${item['imei']}',
                if (item['color'] != null &&
                    '${item['color']}'.trim().isNotEmpty)
                  'Màu: ${item['color']}',
              ].join(' • '),
              quantity: (item['quantity'] as num).toInt(),
              unitPrice: (item['unit_price'] as num).toInt(),
            ),
          )
          .toList(),
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
    final expires = soldAt == null || months <= 0
        ? null
        : addMonths(soldAt, months);
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
        MapEntry(
          'Hết hạn',
          expires == null
              ? 'Không có'
              : DateFormat('dd/MM/yyyy').format(expires),
        ),
      ],
      note:
          'Điều kiện bảo hành: máy còn nguyên tem và IMEI, không rơi vỡ, '
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'MINH CẢNH MOBILE',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          const Text(
            '196 Trung Hưng, Vũ Thư, Hưng Yên',
            textAlign: TextAlign.center,
          ),
          const Text('Điện thoại: 0889 486 662', textAlign: TextAlign.center),
          const SizedBox(height: 10),
          _receiptRule(),
          const SizedBox(height: 9),
          Text(
            receipt.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(
            'Mã phiếu: ${receipt.code}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(receipt.date, textAlign: TextAlign.center),
          const SizedBox(height: 7),
          SizedBox(
            height: 42,
            width: 230,
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: receipt.code,
              drawText: false,
              color: Colors.black,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 9),
          _receiptRule(),
          const SizedBox(height: 7),
          ...receipt.details.map((line) => _ReceiptRow(line.key, line.value)),
          if (receipt.items.isNotEmpty) ...[
            const SizedBox(height: 7),
            _receiptRule(),
            const SizedBox(height: 7),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'HÀNG HÓA',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 5),
            ...receipt.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (item.detail.isNotEmpty)
                      Text(item.detail, style: const TextStyle(fontSize: 12)),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.quantity} x ${vnd(item.unitPrice)}',
                          ),
                        ),
                        Text(
                          vnd(item.quantity * item.unitPrice),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (receipt.totals.isNotEmpty) ...[
            _receiptRule(),
            const SizedBox(height: 6),
            ...receipt.totals.map(
              (line) => _ReceiptRow(
                line.key,
                line.value,
                bold: line == receipt.totals.first,
              ),
            ),
          ],
          if (receipt.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            _receiptRule(),
            const SizedBox(height: 7),
            Text(
              receipt.note,
              textAlign: TextAlign.left,
              style: const TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Khách hàng\n(Ký, ghi rõ họ tên)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Text(
                  'Nhân viên\n(Ký, ghi rõ họ tên)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 42),
          const Text(
            'Cảm ơn quý khách!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
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
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class ReceiptPrinter {
  static Future<Uint8List> render(
    BuildContext context,
    ReceiptDocument receipt,
  ) async {
    final controller = ScreenshotController();
    return controller.captureFromLongWidget(
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
      constraints: const BoxConstraints(minWidth: 360, maxWidth: 360),
    );
  }

  static Future<List<int>> thermalBytes(Uint8List png) async {
    final decoded = img.decodeImage(png);
    if (decoded == null) throw Exception('Không thể tạo ảnh phiếu in');
    final printable = img.copyResize(
      decoded,
      width: 576,
      interpolation: img.Interpolation.average,
    );
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    return <int>[
      ...generator.reset(),
      ...generator.imageRaster(printable, align: PosAlign.center),
      ...generator.feed(3),
    ];
  }

  static Future<void> print(
    BuildContext context,
    ReceiptDocument receipt,
  ) async {
    if(kIsWeb){await share(context,receipt);return;}
    final transport =
        await StoreDb.instance.getSetting('printer_transport') ?? 'lan';
    final savedCopies = int.tryParse(
      await StoreDb.instance.getSetting('printer_copies') ?? '1',
    );
    final copies = (savedCopies ?? 1).clamp(1, 3);
    final png = await render(context, receipt);
    final bytes = await thermalBytes(png);

    if (transport == 'bluetooth') {
      final mac =
          await StoreDb.instance.getSetting('printer_bluetooth_mac') ?? '';
      if (mac.isEmpty) {
        throw Exception('Chưa chọn máy in Bluetooth trong Cài đặt máy in K80');
      }
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        throw Exception('Bluetooth đang tắt. Hãy bật Bluetooth rồi thử lại');
      }
      var connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        connected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      }
      if (!connected) throw Exception('Không kết nối được máy in Bluetooth');
      for (var i = 0; i < copies; i++) {
        final ok = await PrintBluetoothThermal.writeBytes(bytes);
        if (!ok) throw Exception('Máy in Bluetooth không nhận dữ liệu');
      }
      return;
    }

    final host = await StoreDb.instance.getSetting('printer_lan_ip') ?? '';
    final port =
        int.tryParse(
          await StoreDb.instance.getSetting('printer_lan_port') ?? '9100',
        ) ??
        9100;
    if (host.trim().isEmpty) {
      throw Exception(
        'Chưa nhập địa chỉ IP máy in LAN trong Cài đặt máy in K80',
      );
    }
    await sendToPrinter(host.trim(), port, bytes, copies);
  }

  static Future<void> share(
    BuildContext context,
    ReceiptDocument receipt,
  ) async {
    final png = await render(context, receipt);
    final decoded = img.decodeImage(png);
    if (decoded == null) throw Exception('Không thể tạo tệp chia sẻ');
    final pageWidth = 80 * PdfPageFormat.mm;
    final printableWidth = pageWidth - 8 * PdfPageFormat.mm;
    final pageHeight =
        printableWidth * decoded.height / decoded.width + 8 * PdfPageFormat.mm;
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidth,
          pageHeight,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Center(
          child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
        ),
      ),
    );
    final pdfBytes = await document.save();
    if(kIsWeb){await offerBrowserPdf(context,pdfBytes,receipt.fileName);return;}
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(pdfBytes, mimeType: 'application/pdf')],
        fileNameOverrides: [receipt.fileName],
        subject: '${receipt.title} ${receipt.code}',
        text: '${receipt.title} ${receipt.code} - Minh Cảnh Mobile',
      ),
    );
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
          child: ReceiptPaper(receipt: widget.receipt, width: width),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : share,
                  icon: const Icon(Icons.share),
                  label: const Text('Chia sẻ PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : printReceipt,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print),
                  label: Text(busy ? 'Đang xử lý' : 'In phiếu'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> printReceipt() async {
    setState(() => busy = true);
    try {
      await ReceiptPrinter.print(context, widget.receipt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi phiếu tới máy in')),
        );
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
    transport = await StoreDb.instance.getSetting('printer_transport') ?? 'lan';
    ip.text = await StoreDb.instance.getSetting('printer_lan_ip') ?? '';
    port.text = await StoreDb.instance.getSetting('printer_lan_port') ?? '9100';
    bluetoothMac =
        await StoreDb.instance.getSetting('printer_bluetooth_mac') ?? '';
    bluetoothName =
        await StoreDb.instance.getSetting('printer_bluetooth_name') ?? '';
    copies =
        int.tryParse(
          await StoreDb.instance.getSetting('printer_copies') ?? '1',
        ) ??
        1;
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cài đặt máy in K80')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Kiểu kết nối',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'lan',
                    icon: Icon(Icons.lan),
                    label: Text('LAN / Wi-Fi'),
                  ),
                  ButtonSegment(
                    value: 'bluetooth',
                    icon: Icon(Icons.bluetooth),
                    label: Text('Bluetooth'),
                  ),
                ],
                selected: {transport},
                onSelectionChanged: (value) =>
                    setState(() => transport = value.first),
              ),
              const SizedBox(height: 16),
              if (transport == 'lan') ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Máy in KiotViet dùng dây LAN',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Điện thoại phải dùng Wi-Fi cùng bộ phát mạng với máy in.',
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: ip,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Địa chỉ IP máy in',
                            hintText: 'Ví dụ: 192.168.1.100',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: port,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Cổng in',
                            hintText: '9100',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Máy in cầm tay Bluetooth',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          bluetoothName.isEmpty
                              ? 'Chưa chọn máy in. Hãy ghép đôi máy trong Cài đặt Bluetooth của điện thoại trước.'
                              : 'Đã chọn: $bluetoothName\n$bluetoothMac',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: searching ? null : searchBluetooth,
                          icon: searching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search),
                          label: Text(
                            searching ? 'Đang tìm' : 'Tìm máy đã ghép đôi',
                          ),
                        ),
                        ...devices.map(
                          (device) => RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            value: device.macAdress,
                            groupValue: bluetoothMac,
                            title: Text(
                              device.name.isEmpty
                                  ? 'Máy in Bluetooth'
                                  : device.name,
                            ),
                            subtitle: Text(device.macAdress),
                            onChanged: (value) => setState(() {
                              bluetoothMac = value ?? '';
                              bluetoothName = device.name.isEmpty
                                  ? 'Máy in Bluetooth'
                                  : device.name;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: copies,
                decoration: const InputDecoration(
                  labelText: 'Số liên mỗi lần in',
                ),
                items: const [1, 2, 3]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value liên'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => copies = value ?? 1),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await save();
                  } catch (e) {
                    if (mounted) showError(context, e);
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Lưu cài đặt'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: testing ? null : testPrint,
                icon: testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print),
                label: Text(testing ? 'Đang in thử' : 'Lưu và in thử'),
              ),
            ],
          ),
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
            'Không thấy máy đã ghép đôi. Hãy ghép đôi máy in trong Cài đặt Bluetooth trước',
          );
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => searching = false);
  }

  Future<void> save({bool notify = true}) async {
    final portValue = int.tryParse(port.text.trim());
    if (transport == 'lan' && (ip.text.trim().isEmpty || portValue == null)) {
      throw Exception('Hãy nhập đúng IP và cổng máy in LAN');
    }
    if (transport == 'bluetooth' && bluetoothMac.isEmpty) {
      throw Exception('Hãy chọn máy in Bluetooth');
    }
    await StoreDb.instance.setSetting('printer_transport', transport);
    await StoreDb.instance.setSetting('printer_lan_ip', ip.text.trim());
    await StoreDb.instance.setSetting('printer_lan_port', port.text.trim());
    await StoreDb.instance.setSetting('printer_bluetooth_mac', bluetoothMac);
    await StoreDb.instance.setSetting('printer_bluetooth_name', bluetoothName);
    await StoreDb.instance.setSetting('printer_copies', '$copies');
    if (notify && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã lưu cài đặt máy in')));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã gửi phiếu in thử')));
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}

class MenuAction {
  MenuAction(this.icon, this.title, this.onTap);
  final IconData icon;
  final String title;
  final VoidCallback onTap;
}

class MenuGroup extends StatelessWidget {
  const MenuGroup(this.title, this.items, {super.key});
  final String title;
  final List<MenuAction> items;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          ...items.map(
            (e) => ListTile(
              leading: Icon(
                e.icon,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(e.title),
              trailing: const Icon(Icons.chevron_right),
              onTap: e.onTap,
            ),
          ),
        ],
      ),
    ),
  );
}

String newInvoiceCode() {
  final now = DateTime.now();
  return 'HD${DateFormat('yyyyMMddHHmmssSSS').format(now)}';
}

Future<String?> promptNewCategory(BuildContext context) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Tạo phân loại mới'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Tên phân loại',
          hintText: 'Ví dụ: iPhone, Samsung, Cáp sạc…',
        ),
        onSubmitted: (text) {
          if (text.trim().isNotEmpty) Navigator.pop(dialogContext, text.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) Navigator.pop(dialogContext, text);
          },
          child: const Text('Tạo'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

Future<String?> promptNewBrand(BuildContext context) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Tạo hãng mới'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Tên hãng',
          hintText: 'Ví dụ: Apple, Samsung, Xiaomi…',
        ),
        onSubmitted: (text) {
          if (text.trim().isNotEmpty) {
            Navigator.pop(dialogContext, text.trim());
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) Navigator.pop(dialogContext, text);
          },
          child: const Text('Tạo'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

String statusName(String status) => switch (status) {
  'in_stock' => 'Còn hàng',
  'sold' => 'Đã bán',
  'reserved' => 'Đang giữ',
  'returned_supplier' => 'Đã trả NCC',
  'discarded' => 'Đã xuất hủy',
  _ => status,
};

DateTime? parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value');
}

String formatDateTime(Object? value) {
  final date = parseDate(value);
  return date == null
      ? 'Không rõ'
      : DateFormat('dd/MM/yyyy HH:mm').format(date);
}

DateTime addMonths(DateTime date, int months) {
  final firstOfTarget = DateTime(
    date.year,
    date.month + months,
    1,
    date.hour,
    date.minute,
    date.second,
  );
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(
    firstOfTarget.year,
    firstOfTarget.month,
    day,
    date.hour,
    date.minute,
    date.second,
  );
}

String warrantyLabel(int months) {
  if (months <= 0) return 'Không bảo hành';
  if (months == 12) return '12 tháng / 1 năm';
  if (months == 24) return '24 tháng / 2 năm';
  return '$months tháng';
}

Widget infoLine(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 125,
        child: Text(label, style: const TextStyle(color: Colors.black54)),
      ),
      Expanded(
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ],
  ),
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
  final text = error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('DatabaseException(', '')
      .split(') sql')
      .first;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), backgroundColor: Colors.red));
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ) ??
    false;
