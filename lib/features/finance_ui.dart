part of '../main.dart';

class CashBookPage extends StatefulWidget {
  const CashBookPage({super.key});
  @override
  State<CashBookPage> createState() => _CashBookPageState();
}

class _CashBookPageState extends State<CashBookPage> {
  PeriodFilter period = PeriodFilter.month(DateTime.now());
  late Future<Map<String, Object?>> future = load();
  Future<Map<String, Object?>> load() async {
    final from = period.start ?? DateTime(2000),
        to = period.end ?? DateTime(2100);
    final summary = await StoreDb.instance.financeSummary(from, to);
    final ledger = await StoreDb.instance.financeLedger(from, to);
    final recurring = await StoreDb.instance.recurringExpenses(
      period.anchor.year,
      period.anchor.month,
    );
    return {'summary': summary, 'ledger': ledger, 'recurring': recurring};
  }

  void reload() {
    if (mounted) setState(() => future = load());
  }

  Future<void> edit([Map<String, Object?>? row]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CashEntryForm(entry: row)),
    );
    if (result == true) reload();
  }

  Widget metric(String label, int value) => SizedBox(
    width: 280,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            Text(
              vnd(value),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: value < 0 ? Colors.red : const Color(0xff12588a),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Thu–Chi & chi tiêu'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Tổng quan'),
            Tab(text: 'Lịch sử'),
            Tab(text: 'Chi phí cố định'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Thêm thu/chi'),
      ),
      body: Column(
        children: [
          PeriodPicker(
            value: period,
            onChanged: (p) {
              setState(() {
                period = p;
                future = load();
              });
            },
          ),
          Expanded(
            child: FutureBuilder<Map<String, Object?>>(
              future: future,
              builder: (ctx, snap) {
                if (snap.hasError)
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${snap.error}'),
                        TextButton(
                          onPressed: reload,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  );
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final data = snap.data!;
                final totals = data['summary'] as Map<String, int>;
                final rows = data['ledger'] as List<Map<String, Object?>>;
                final recurring =
                    data['recurring'] as List<Map<String, Object?>>;
                final fixed = recurring.fold<int>(
                  0,
                  (n, r) => n + (r['amount'] as int),
                );
                final businessFixed = recurring
                    .where(
                      (r) => [
                        'business',
                        'business_interest',
                      ].contains(r['scope']),
                    )
                    .fold<int>(0, (n, r) => n + (r['amount'] as int));
                final days = DateTime(
                  period.anchor.year,
                  period.anchor.month + 1,
                  0,
                ).day;
                return TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      children: [
                        if ((totals['unknown_repair_payments'] ?? 0) > 0)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Đã thu sửa chữa cũ: ${vnd(totals['unknown_repair_payments']!)} — không rõ ngày thu; chưa cộng vào thực thu theo kỳ.',
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            metric(
                              'Lợi nhuận kinh doanh',
                              totals['business_profit']!,
                            ),
                            metric(
                              'Sau chi gia đình & trả gốc',
                              totals['remaining_profit']!,
                            ),
                            metric('Thực thu', totals['income']!),
                            metric('Thực chi', totals['expense']!),
                            metric('Dòng tiền ròng', totals['cash_flow']!),
                            metric(
                              'Chi gia đình',
                              totals['personal_expenses']!,
                            ),
                            metric('Trả gốc vay', totals['principal_paid']!),
                          ],
                        ),
                        if (totals['unclassified']! > 0)
                          Card(
                            color: Colors.amber.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Có ${vnd(totals['unclassified']!)} chưa phân loại. Mở Lịch sử để phân loại khoản cũ; lợi nhuận chưa tính những khoản này.',
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Chi phí cố định tháng ${period.anchor.month}/${period.anchor.year}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        infoLine(
                          'Cửa hàng cần lợi nhuận/ngày',
                          vnd((businessFixed / days).ceil()),
                        ),
                        infoLine(
                          'Tổng nhu cầu chi/ngày',
                          vnd((fixed / days).ceil()),
                        ),
                        const Text(
                          'Tính theo các khoản cố định đã khai và số ngày của tháng. Dòng tiền ròng là tiền thu trừ tiền chi, không phải số dư tài khoản.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Tiền nhập hàng ghi vào dòng tiền; giá vốn tính khi bán. Chi gia đình và gốc vay được tách khỏi lợi nhuận kinh doanh.',
                        ),
                      ],
                    ),
                    rows.isEmpty
                        ? const Center(
                            child: Text('Chưa có giao dịch trong kỳ'),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i],
                                  income = r['entry_type'] == 'income';
                              final manual = r['source_type'] == 'manual';
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  leading: Icon(
                                    income
                                        ? Icons.south_west
                                        : Icons.north_east,
                                    color: income ? Colors.green : Colors.red,
                                  ),
                                  title: Text('${r['category']}'),
                                  subtitle: Text(
                                    '${DateFormat('dd/MM/yyyy HH:mm').format(vietnamWallDate('${r['occurred_at']}'))} • ${financeScopes[r['scope']] ?? (r['scope'] == 'inventory' ? 'Tiền nhập hàng' : 'Cửa hàng')}\n${paymentLabel('${r['payment_method']}')}${manual ? '' : ' • Tự động từ phiếu gốc'}${'${r['note']}'.isEmpty ? '' : ' • ${r['note']}'}',
                                  ),
                                  isThreeLine: true,
                                  trailing: Text(
                                    '${income ? '+' : '−'}${vnd(r['amount'] as int)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: income ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  onTap: () => manual
                                      ? edit(r)
                                      : showDialog<void>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                              'Giao dịch từ phiếu gốc',
                                            ),
                                            content: Text(
                                              '${r['category']}\n${vnd(r['amount'] as int)}\nSửa thông tin tại hóa đơn, phiếu nhập hoặc công nợ tương ứng để giữ số liệu đồng nhất.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child: const Text('Đóng'),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              );
                            },
                          ),
                    ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => recurringForm(),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm khoản chi cố định'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Lịch thanh toán tháng ${period.anchor.month}/${period.anchor.year}',
                        ),
                        ...recurring.map(
                          (r) => Card(
                            child: ListTile(
                              title: Text(
                                '${r['title']} • ${vnd(r['amount'] as int)}',
                              ),
                              subtitle: Text(
                                'Hạn ${r['due_date']} • ${r['paid'] == true ? 'Đã thanh toán' : 'Chưa thanh toán'}',
                              ),
                              onTap: () => recurringForm(r),
                              trailing: r['paid'] == true
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    )
                                  : TextButton(
                                      onPressed: () => pay(r),
                                      child: const Text('Thanh toán'),
                                    ),
                            ),
                          ),
                        ),
                        if (recurring.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Chưa có khoản cố định. Thêm tiền nhà, điện nước hoặc trả ngân hàng.',
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  String paymentLabel(String method) => method == 'cash'
      ? 'Tiền mặt'
      : method == 'transfer'
      ? 'Chuyển khoản'
      : 'Chưa rõ phương thức';
  Future<void> pay(Map<String, Object?> row) async {
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Thanh toán ${row['title']}'),
        content: Text(
          'Ghi chi ${vnd(row['amount'] as int)} cho tháng ${period.anchor.month}/${period.anchor.year} ngay hôm nay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cash'),
            child: const Text('Tiền mặt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'transfer'),
            child: const Text('Chuyển khoản'),
          ),
        ],
      ),
    );
    if (method == null) return;
    try {
      await StoreDb.instance.payRecurringExpense(
        row['id'] as int,
        period.anchor.year,
        period.anchor.month,
        method,
        financeNow(),
      );
      reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> recurringForm([Map<String, Object?>? row]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecurringExpenseForm(entry: row, anchor: period.anchor),
      ),
    );
    if (changed == true) reload();
  }
}

class CashEntryForm extends StatefulWidget {
  const CashEntryForm({super.key, this.entry});
  final Map<String, Object?>? entry;
  @override
  State<CashEntryForm> createState() => _CashEntryFormState();
}

class _CashEntryFormState extends State<CashEntryForm> {
  late final category = TextEditingController(
    text: '${widget.entry?['category'] ?? ''}',
  );
  late final amount = TextEditingController(
    text: widget.entry == null ? '' : '${widget.entry!['amount']}',
  );
  late final note = TextEditingController(
    text: '${widget.entry?['note'] ?? ''}',
  );
  late String type = '${widget.entry?['entry_type'] ?? 'expense'}',
      scope = '${widget.entry?['scope'] ?? 'business'}',
      method = '${widget.entry?['payment_method'] ?? 'cash'}';
  late DateTime date = vietnamWallDate(
    '${widget.entry?['occurred_at'] ?? financeNow()}',
  );
  bool saving = false;
  @override
  void dispose() {
    category.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.entry == null ? 'Thêm thu/chi' : 'Sửa thu/chi'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'income', label: Text('Thu')),
            ButtonSegment(value: 'expense', label: Text('Chi')),
          ],
          selected: {type},
          onSelectionChanged: (v) => setState(() {
            type = v.first;
            if (type == 'income' &&
                ['loan_principal', 'business_interest'].contains(scope))
              scope = 'business';
            if (type == 'expense' && scope == 'loan_received')
              scope = 'business';
          }),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key:ValueKey(scope),
          initialValue: scope,
          decoration: const InputDecoration(labelText: 'Phân loại'),
          items: financeScopes.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() {
            scope = v!;
            if (scope == 'loan_received') type = 'income';
            if (['loan_principal', 'business_interest'].contains(scope))
              type = 'expense';
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Số tiền *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: category,
          decoration: const InputDecoration(labelText: 'Danh mục / nội dung'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children:
              (scope == 'personal'
                      ? [
                          'Ăn uống',
                          'Sinh hoạt',
                          'Chi tiêu cho con',
                          'Mua sắm',
                          'Gia đình',
                        ]
                      : [
                          'Tiền thuê mặt bằng',
                          'Điện nước Internet',
                          'Vật tư sửa chữa',
                          'Quảng cáo',
                          'Vận chuyển',
                          'Phát sinh',
                        ])
                  .map(
                    (c) => ActionChip(
                      label: Text(c),
                      onPressed: () => category.text = c,
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: method,
          decoration: const InputDecoration(labelText: 'Thanh toán'),
          items: const [
            DropdownMenuItem(value: 'cash', child: Text('Tiền mặt')),
            DropdownMenuItem(value: 'transfer', child: Text('Chuyển khoản')),
            DropdownMenuItem(value: 'unknown', child: Text('Chưa rõ')),
          ],
          onChanged: (v) => setState(() => method = v!),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month),
          title: Text(DateFormat('dd/MM/yyyy').format(date)),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final selected = await showDatePicker(
              context: context,
              initialDate: DateTime(date.year, date.month, date.day),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (selected != null && mounted)
              setState(
                () => date = DateTime.utc(
                  selected.year,
                  selected.month,
                  selected.day,
                  date.hour,
                  date.minute,
                ),
              );
          },
        ),
        TextField(
          controller: note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Ghi chú'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save),
          label: Text(saving ? 'Đang lưu…' : 'Lưu thu/chi'),
        ),
        if (widget.entry != null)
          TextButton.icon(
            onPressed: saving ? null : remove,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xóa giao dịch'),
          ),
      ],
    ),
  );
  Future<void> save() async {
    if (saving) return;
    if(widget.entry!=null&&!await confirm(context,'Lưu thay đổi','Cập nhật khoản thu/chi này?'))return;
    if(!mounted)return;
    setState(() => saving = true);
    try {
      await StoreDb.instance.saveCashEntry(
        id: widget.entry?['source_id'] as int?,
        type: type,
        scope: scope,
        category: category.text,
        amount: int.tryParse(amount.text) ?? 0,
        note: note.text,
        paymentMethod: method,
        occurredAt: date.toIso8601String().replaceAll('Z', ''),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> remove() async {
    if (!await confirm(context, 'Xóa thu/chi', 'Xóa giao dịch này?')) return;
    setState(() => saving = true);
    try {
      await StoreDb.instance.deleteCashEntry(widget.entry!['source_id'] as int);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class RecurringExpenseForm extends StatefulWidget {
  const RecurringExpenseForm({super.key, this.entry, required this.anchor});
  final Map<String, Object?>? entry;
  final DateTime anchor;
  @override
  State<RecurringExpenseForm> createState() => _RecurringExpenseFormState();
}

class _RecurringExpenseFormState extends State<RecurringExpenseForm> {
  late final title = TextEditingController(
        text: '${widget.entry?['title'] ?? ''}',
      ),
      amount = TextEditingController(text: '${widget.entry?['amount'] ?? ''}'),
      day = TextEditingController(text: '${widget.entry?['day'] ?? 1}');
  late String scope = '${widget.entry?['scope'] ?? 'business'}';
  bool saving = false;
  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    day.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Khoản chi cố định')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Tên khoản chi *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Số tiền mỗi tháng *'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: day,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Ngày đến hạn (1–31)'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key:ValueKey(scope),
          initialValue: scope,
          decoration: const InputDecoration(labelText: 'Phân loại'),
          items: financeScopes.entries
              .where(
                (e) => [
                  'business',
                  'personal',
                  'loan_principal',
                  'business_interest',
                ].contains(e.key),
              )
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => scope = v!),
        ),
        const SizedBox(height: 12),
        const Text(
          'Lặp mỗi tháng. Tháng ngắn dùng ngày cuối tháng. Khoản đến hạn chưa được ghi chi cho đến khi bấm Thanh toán.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Lưu khoản cố định'),
        ),
        if (widget.entry != null)
          TextButton(
            onPressed: saving ? null : stop,
            child: const Text('Ngừng khoản định kỳ'),
          ),
      ],
    ),
  );
  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await StoreDb.instance.saveRecurringExpense(
        id: widget.entry?['id'] as int?,
        payload: {
          'title': title.text,
          'category': title.text,
          'amount': int.tryParse(amount.text) ?? 0,
          'day': int.tryParse(day.text) ?? 0,
          'scope': scope,
          'start_month':
              widget.entry?['start_month'] ??
              '${widget.anchor.year}-${widget.anchor.month.toString().padLeft(2, '0')}',
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> stop() async {
    if (!await confirm(
      context,
      'Ngừng khoản định kỳ',
      'Không tạo kỳ hạn mới cho khoản này. Các giao dịch đã thanh toán vẫn giữ.',
    ))
      return;
    setState(() => saving = true);
    try {
      await StoreDb.instance.deleteRecurringExpense(widget.entry!['id'] as int);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
