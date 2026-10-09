part of '../main.dart';

class PeriodFilter {
  const PeriodFilter(this.mode, this.anchor);
  factory PeriodFilter.month(DateTime date) => PeriodFilter('month', date);
  final String mode;
  final DateTime anchor;
  DateTime? get start => switch (mode) {
    'day' => DateTime(anchor.year, anchor.month, anchor.day),
    'week' => DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).subtract(Duration(days: anchor.weekday - 1)),
    'month' => DateTime(anchor.year, anchor.month),
    'quarter' => DateTime(anchor.year, ((anchor.month - 1) ~/ 3) * 3 + 1),
    'year' => DateTime(anchor.year),
    _ => null,
  };
  DateTime? get end => switch (mode) {
    'day' => DateTime(anchor.year, anchor.month, anchor.day + 1),
    'week' => start!.add(const Duration(days: 7)),
    'month' => DateTime(anchor.year, anchor.month + 1),
    'quarter' => DateTime(anchor.year, ((anchor.month - 1) ~/ 3) * 3 + 4),
    'year' => DateTime(anchor.year + 1),
    _ => null,
  };
  bool includes(DateTime? date) =>
      mode == 'all' ||
      (date != null && !date.isBefore(start!) && date.isBefore(end!));
  String get label => switch (mode) {
    'all' => 'Toàn bộ thời gian',
    'day' => DateFormat('dd/MM/yyyy').format(anchor),
    'month' => 'Tháng ${DateFormat('MM/yyyy').format(anchor)}',
    'year' => 'Năm ${anchor.year}',
    'quarter' => 'Quý ${(anchor.month - 1) ~/ 3 + 1}/${anchor.year}',
    _ => 'Tuần ${DateFormat('dd/MM/yyyy').format(start!)}',
  };
}

class PeriodPicker extends StatelessWidget {
  const PeriodPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.extended = false,
  });
  final PeriodFilter value;
  final ValueChanged<PeriodFilter> onChanged;
  final bool extended;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final entry in <String, String>{
              'all': 'Tất cả',
              'day': 'Ngày',
              if (extended) 'week': 'Tuần',
              'month': 'Tháng',
              if (extended) 'quarter': 'Quý',
              'year': 'Năm',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: value.mode == entry.key,
                onSelected: (_) =>
                    onChanged(PeriodFilter(entry.key, value.anchor)),
              ),
          ],
        ),
        if (value.mode != 'all')
          TextButton.icon(
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(value.label),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: value.anchor,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null) onChanged(PeriodFilter(value.mode, date));
            },
          ),
      ],
    ),
  );
}

class SupplierSearchDialog extends StatefulWidget {
  const SupplierSearchDialog({super.key, required this.rows});
  final List<Map<String, Object?>> rows;
  @override
  State<SupplierSearchDialog> createState() => _SupplierSearchDialogState();
}

class _SupplierSearchDialogState extends State<SupplierSearchDialog> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.rows
        .where(
          (r) => '${r['name']} ${r['phone']}'.toLowerCase().contains(query),
        )
        .toList();
    return AlertDialog(
      title: const Text('Tìm nhà cung cấp'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Tên hoặc số điện thoại',
              ),
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Không tìm thấy nhà cung cấp'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (c, i) => ListTile(
                        title: Text('${rows[i]['name']}'),
                        subtitle: Text('${rows[i]['phone'] ?? ''}'),
                        onTap: () => Navigator.pop(context, rows[i]['id']),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class ProductReportPage extends StatefulWidget {
  const ProductReportPage({super.key});
  @override
  State<ProductReportPage> createState() => _ProductReportPageState();
}

class _ProductReportPageState extends State<ProductReportPage> {
  PeriodFilter period = PeriodFilter.month(DateTime.now());
  String search = '',
      metric = 'stock_value',
      brand = '',
      category = '',
      kind = 'all';
  bool details = false, descending = true;
  int visible = 50;
  late Future<List<Map<String, Object?>>> future = _load();
  Future<List<Map<String, Object?>>> _load() => StoreDb.instance.productReport(
    period.start ?? DateTime(2000),
    period.end ?? DateTime(2100),
  );
  final metrics = const {
    'stock_value': 'Giá trị kho',
    'stock': 'Số lượng tồn',
    'revenue': 'Doanh thu',
    'sold_quantity': 'Số lượng bán',
    'profit': 'Lợi nhuận',
  };
  num number(Map<String, Object?> r, String key) => r[key] as num? ?? 0;
  String amount(num n, String key) =>
      ['stock', 'sold_quantity'].contains(key) ? money.format(n) : vnd(n);
  void changePeriod(PeriodFilter p) => setState(() {
    period = p;
    future = _load();
    visible = 50;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Báo cáo hàng hóa'),
      actions: [
        IconButton(
          tooltip: details ? 'Xem tổng hợp' : 'Xem danh sách',
          onPressed: () => setState(() => details = !details),
          icon: Icon(details ? Icons.bar_chart : Icons.list_alt),
        ),
        IconButton(
          tooltip: 'Đổi thứ tự sắp xếp',
          onPressed: () => setState(() => descending = !descending),
          icon: const Icon(Icons.swap_vert),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Không tải được báo cáo: ${snapshot.error}'),
                TextButton(
                  onPressed: () => setState(() => future = _load()),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final all = snapshot.data!;
        final rows = all
            .where(
              (r) =>
                  '${r['name']} ${r['code']}'.toLowerCase().contains(search) &&
                  (brand.isEmpty || r['brand'] == brand) &&
                  (category.isEmpty || r['category'] == category) &&
                  (kind == 'all' || (r['track_imei'] == 1) == (kind == 'imei')),
            )
            .toList();
        rows.sort(
          (a, b) =>
              (descending ? -1 : 1) *
              number(a, metric).compareTo(number(b, metric)),
        );
        final total = rows.fold<num>(
          0,
          (sum, r) => sum + number(r, 'stock_value'),
        );
        final units = rows.fold<num>(0, (sum, r) => sum + number(r, 'stock'));
        final brands =
            all
                .map((r) => '${r['brand'] ?? ''}')
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        final categories =
            all
                .map((r) => '${r['category'] ?? ''}')
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            PeriodPicker(
              value: period,
              onChanged: changePeriod,
              extended: true,
            ),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Tìm mã hoặc tên hàng hóa',
              ),
              onChanged: (v) => setState(() {
                search = v.trim().toLowerCase();
                visible = 50;
              }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: metric,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Chỉ tiêu'),
                    items: metrics.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => metric = v!),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: brand,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Hãng'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Tất cả hãng'),
                      ),
                      ...brands.map(
                        (b) => DropdownMenuItem(value: b, child: Text(b)),
                      ),
                    ],
                    onChanged: (v) => setState(() => brand = v!),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Phân loại'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Tất cả phân loại'),
                      ),
                      ...categories.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c)),
                      ),
                    ],
                    onChanged: (v) => setState(() => category = v!),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Loại hàng'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                      DropdownMenuItem(value: 'imei', child: Text('Máy IMEI')),
                      DropdownMenuItem(
                        value: 'accessory',
                        child: Text('Phụ kiện'),
                      ),
                    ],
                    onChanged: (v) => setState(() => kind = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff0877d1), Color(0xff20a5bf)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TỒN KHO HIỆN TẠI',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    child: Text(
                      vnd(total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${money.format(units)} sản phẩm tồn • ${rows.length} mẫu hàng',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nhập–xuất–tồn theo kỳ đã chọn. Giá trị kho là giá trị hiện tại.',
                style: TextStyle(color: Colors.blueGrey, fontSize: 12),
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 1000) ...[
              _inventoryTable(rows.take(visible).toList()),
              if (rows.length > visible)
                TextButton(
                  onPressed: () => setState(() => visible += 50),
                  child: const Text('Xem thêm 50 hàng hóa'),
                ),
            ] else if (details) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${rows.length} mẫu hàng'),
                subtitle: Text(
                  'Tổng ${metrics[metric]!.toLowerCase()}: ${amount(rows.fold<num>(0, (s, r) => s + number(r, metric)), metric)}',
                ),
              ),
              Card(
                child: Column(
                  children: [
                    for (final r in rows.take(visible)) _row(r, metric, null),
                  ],
                ),
              ),
              if (rows.length > visible)
                TextButton(
                  onPressed: () => setState(() => visible += 50),
                  child: const Text('Xem thêm 50 hàng hóa'),
                ),
            ] else ...[
              _ranking(rows, 'revenue', 'Top hàng theo doanh thu'),
              const SizedBox(height: 16),
              _ranking(rows, 'stock_value', 'Top hàng theo giá trị kho'),
            ],
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Không có hàng hóa phù hợp bộ lọc')),
              ),
          ],
        );
      },
    ),
  );
  Widget _inventoryTable(List<Map<String, Object?>> rows) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 50,
          columns: const [
            DataColumn(label: Text('Hàng hóa')),
            DataColumn(label: Text('Tồn đầu'), numeric: true),
            DataColumn(label: Text('Nhập'), numeric: true),
            DataColumn(label: Text('Xuất'), numeric: true),
            DataColumn(label: Text('Tồn cuối'), numeric: true),
            DataColumn(label: Text('Giá trị hiện tại'), numeric: true),
            DataColumn(label: Text('Doanh thu'), numeric: true),
            DataColumn(label: Text('Lợi nhuận'), numeric: true),
          ],
          rows: rows
              .map(
                (r) => DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 230,
                        child: Text(
                          '${r['name']}\n${r['code']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onTap: () async {
                        try {
                          final product = await StoreDb.instance.product(
                            r['id'] as int,
                          );
                          if (!mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetail(
                                product: product,
                                onChanged: () {},
                              ),
                            ),
                          );
                          if (mounted) setState(() => future = _load());
                        } catch (e) {
                          if (mounted) showError(context, e);
                        }
                      },
                    ),
                    ...[
                      'opening_stock',
                      'incoming',
                      'outgoing',
                      'closing_stock',
                    ].map((k) => DataCell(Text('${r[k] ?? 0}'))),
                    ...[
                      'stock_value',
                      'revenue',
                      'profit',
                    ].map((k) => DataCell(Text(vnd((r[k] as num?) ?? 0)))),
                  ],
                ),
              )
              .toList(),
        ),
      );
  Widget _ranking(List<Map<String, Object?>> rows, String key, String title) {
    final sorted = [...rows]
      ..sort((a, b) => number(b, key).compareTo(number(a, key)));
    final max = sorted.isEmpty ? 0 : number(sorted.first, key);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() {
                metric = key;
                details = true;
                descending = true;
              }),
            ),
            for (final r in sorted.take(10)) _row(r, key, max),
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, Object?> r, String key, num? max) => InkWell(
    onTap: () async {
      Map<String, Object?> product;
      try {
        // Report rows contain aggregates, not the complete editable product.
        product = await StoreDb.instance.product(r['id'] as int);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Không tải được hàng hóa. Hãy tải lại báo cáo và thử lại.',
              ),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetail(product: product, onChanged: () {}),
        ),
      );
      if (mounted) setState(() => future = _load());
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          if (key == metric && details)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Tồn đầu ${r['opening_stock'] ?? 0} • Nhập ${r['incoming'] ?? 0} • Xuất ${r['outgoing'] ?? 0} • Tồn cuối ${r['closing_stock'] ?? 0}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r['name']}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  amount(number(r, key), key),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Color(0xff0877d1),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (max != null) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: max > 0
                  ? (number(r, key) / max).clamp(0, 1).toDouble()
                  : 0,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: const Color(0xffedf2f7),
              color: const Color(0xff44bda5),
            ),
          ] else
            const Divider(),
        ],
      ),
    ),
  );
}

class DashboardDetailPage extends StatelessWidget {
  const DashboardDetailPage({super.key, required this.metric});
  final String metric;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        metric == 'fund'
            ? 'Chi tiết dòng tiền ròng'
            : metric == 'profit'
            ? 'Chi tiết lợi nhuận'
            : 'Chi tiết doanh thu',
      ),
    ),
    body: FutureBuilder<List<Object>>(
      future: Future.wait<Object>([
        StoreDb.instance.sales(),
        StoreDb.instance.repairs(),
        StoreDb.instance.financeLedger(DateTime(2000), DateTime(2100)),
        StoreDb.instance.dashboard(),
      ]),
      builder: (context, snap) {
        if (snap.hasError)
          return Center(child: Text('Không tải được: ${snap.error}'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final sales = snap.data![0] as List<Map<String, Object?>>;
        final repairs = snap.data![1] as List<Map<String, Object?>>;
        final cash = snap.data![2] as List<Map<String, Object?>>;
        final d = snap.data![3] as Map<String, int>;
        num n(Map<String, Object?> r, String k) => r[k] as num? ?? 0;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  vnd(d[metric] ?? 0),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff0877d1),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hóa đơn bán hàng',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (metric != 'fund')
              for (final s in sales.where((s) => s['status'] == 'completed'))
                ListTile(
                  title: Text('${s['code']} • ${s['customer']}'),
                  subtitle: Text(formatDateTime(s['created_at'])),
                  trailing: Text(
                    vnd(
                      metric == 'fund'
                          ? n(s, 'paid_cash') + n(s, 'paid_transfer')
                          : metric == 'profit'
                          ? n(s, 'total') - n(s, 'cost_total')
                          : n(s, 'total'),
                    ),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvoiceDetailPage(saleId: s['id'] as int),
                    ),
                  ),
                ),
            const Divider(),
            const Text(
              'Sửa chữa',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (metric != 'fund')
              for (final r in repairs.where(
                (r) => metric == 'fund'
                    ? r['status'] != 'cancelled'
                    : ['completed', 'returned'].contains(r['status']),
              ))
                ListTile(
                  title: Text('${r['code']} • ${r['customer']}'),
                  subtitle: Text('${r['device']}'),
                  trailing: Text(
                    vnd(
                      metric == 'fund'
                          ? n(r, 'paid')
                          : metric == 'profit'
                          ? n(r, 'amount') - n(r, 'parts_cost')
                          : n(r, 'amount'),
                    ),
                  ),
                ),
            if (metric == 'fund' || metric == 'profit') ...[
              const Divider(),
              const Text(
                'Thu / chi khác',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              for (final r in cash.where(
                (r) =>
                    metric == 'fund' ||
                    (r['source_type'] == 'manual' &&
                        ['business', 'business_interest'].contains(r['scope'])),
              ))
                ListTile(
                  title: Text('${r['note'] ?? r['category'] ?? ''}'),
                  subtitle: Text(
                    formatDateTime(r['occurred_at'] ?? r['created_at']),
                  ),
                  trailing: Text(
                    vnd(
                      n(r, 'amount') * (r['entry_type'] == 'expense' ? -1 : 1),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}
