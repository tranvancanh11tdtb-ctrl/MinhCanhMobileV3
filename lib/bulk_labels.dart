part of 'main.dart';

/// Batch printer: choose multiple accessory products and specific IMEIs.
class BulkLabelSelectionPage extends StatefulWidget {
  const BulkLabelSelectionPage({super.key});
  @override
  State<BulkLabelSelectionPage> createState() => _BulkLabelSelectionPageState();
}

class _BulkLabelSelectionPageState extends State<BulkLabelSelectionPage> {
  late final Future<List<Map<String, Object?>>> products;
  final Map<int, int> quantities = {};
  final Map<int, List<Map<String, Object?>>> units = {};
  final Set<int> chosenImeis = {};
  final Set<int> loading = {};
  String search = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    products = StoreDb.instance.products(includeInactive: false);
  }

  int get total => chosenImeis.length +
      quantities.values.fold<int>(0, (n, count) => n + count);

  Future<void> loadImeis(int id) async {
    if (units.containsKey(id) || loading.contains(id)) return;
    setState(() => loading.add(id));
    try {
      final data = await StoreDb.instance.serials(id, status: 'in_stock');
      if (mounted) setState(() => units[id] = data);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => loading.remove(id));
    }
  }

  void changeQty(int id, int delta) {
    setState(() {
      final q = (quantities[id] ?? 0) + delta;
      if (q <= 0) {
        quantities.remove(id);
      } else {
        quantities[id] = q.clamp(1, 99);
      }
    });
  }

  Widget accessory(Map<String, Object?> p) {
    final id = (p['id'] as num).toInt();
    final qty = quantities[id] ?? 0;
    return Card(child: Column(children: [
      CheckboxListTile(
        value: qty > 0,
        onChanged: (v) => setState(() {
          if (v == true) { quantities[id] = 1; }
          else { quantities.remove(id); }
        }),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${p['code']} • Tồn: ${p['stock']} • ${vnd((p['sale_price'] as num).toInt())}'),
      ),
      if (qty > 0)
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          const Text('Số tem'),
          IconButton(onPressed: () => changeQty(id,-1),
              icon: const Icon(Icons.remove_circle_outline)),
          Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(onPressed: () => changeQty(id,1),
              icon: const Icon(Icons.add_circle_outline)),
          const SizedBox(width: 12),
        ]),
    ]));
  }

  Widget tracked(Map<String, Object?> p) {
    final id = (p['id'] as num).toInt();
    final rows = units[id] ?? [];
    final selected = rows.where((u) => chosenImeis.contains((u['id'] as num).toInt())).length;
    return Card(child: ExpansionTile(
      title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('Máy theo IMEI • Đã chọn $selected'),
      onExpansionChanged: (expanded) { if (expanded) loadImeis(id); },
      children: [
        if (loading.contains(id)) const Padding(
          padding: EdgeInsets.all(12), child: CircularProgressIndicator())
        else if (units.containsKey(id)) ...[
          if (rows.isEmpty) const ListTile(title: Text('Không có IMEI còn trong kho')),
          if (rows.isNotEmpty) TextButton.icon(
            onPressed: () => setState(() {
              for (final u in rows) { chosenImeis.add((u['id'] as num).toInt()); }
            }),
            icon: const Icon(Icons.done_all),
            label: const Text('Chọn tất cả IMEI còn trong kho')),
          for (final u in rows)
            CheckboxListTile(
              dense: true,
              value: chosenImeis.contains((u['id'] as num).toInt()),
              title: Text('${u['imei']}'),
              subtitle: Text('${u['color'] ?? ''} • ${p['capacity'] ?? ''}'),
              onChanged: (yes) => setState(() {
                final uid = (u['id'] as num).toInt();
                if (yes == true) {chosenImeis.add(uid);}
                else {chosenImeis.remove(uid);}
              }),
            ),
        ],
      ],
    ));
  }

  Future<void> preview() async {
    if (busy || total == 0) return;
    setState(() => busy = true);
    try {
      final rows = await products;
      final labels = <ProductLabelData>[];
      for (final p in rows) {
        final id = (p['id'] as num).toInt();
        if (p['track_imei'] == 1) {
          for (final unit in units[id] ?? <Map<String,Object?>>[]) {
            if (chosenImeis.contains((unit['id'] as num).toInt())) {
              labels.add(labelForSerial(p, unit));
            }
          }
        } else {
          for (var i=0; i<(quantities[id] ?? 0); i++) {
            labels.add(ProductLabelData(
              productName: '${p['name']}',
              detail: [p['brand'], p['capacity']].map((v)=>'${v ?? ''}'.trim())
                  .where((v)=>v.isNotEmpty).join(' • '),
              code: '${p['code']}',
              productCode: '${p['code']}',
              price: (p['sale_price'] as num).toInt(),
              isImei: false,
            ));
          }
        }
      }
      if (!mounted) return;
      if (labels.isEmpty) throw StateError('Chưa có tem được chọn');
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => LabelPreviewPage(labels: labels)));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('In tem nhiều sản phẩm')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search), labelText: 'Tìm tên / mã / phân loại'),
        onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
      )),
      Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
        future: products,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(
              child: Text('Không tải được sản phẩm: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(
              child: CircularProgressIndicator());
          final visible = snapshot.data!.where((p) =>
              p['active'] == 1 &&
              '${p['name']} ${p['code']} ${p['category']} ${p['brand']}'
                  .toLowerCase().contains(search)).toList();
          if (visible.isEmpty) return const Center(
              child: Text('Không có sản phẩm phù hợp'));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: visible.length,
            itemBuilder: (context, i) => visible[i]['track_imei'] == 1
                ? tracked(visible[i]) : accessory(visible[i]),
          );
        },
      )),
    ]),
    bottomNavigationBar: SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16,8,16,12),
      child: FilledButton.icon(
        onPressed: busy || total == 0 ? null : preview,
        icon: const Icon(Icons.print),
        label: Text(busy ? 'Đang chuẩn bị tem' : 'Xem trước và in $total tem'),
      ),
    )),
  );
}
