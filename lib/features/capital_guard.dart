part of '../main.dart';

// Bảo vệ vốn: tính số dư dự kiến trên cơ sở số dư chốt đầu kỳ,
// giao dịch từ phiếu gốc và giao dịch thu/chi đã phân loại.
// Không trộn lợi nhuận với dòng tiền hoặc coi tồn kho là tiền có thể tiêu.
Future<Map<String, Object?>> loadCapitalGuard() async {
  final db = StoreDb.instance;
  final keys = [
    'capital_guard_started_at',
    'capital_guard_open_cash',
    'capital_guard_open_bank',
    'capital_guard_min_working',
    'capital_guard_family_budget',
    'capital_guard_extra_reserve',
  ];
  final values = await Future.wait(keys.map(db.getSetting));
  final stock = (await db.dashboard())['stock_value'] ?? 0;
  if (values[0] == null || values[1] == null || values[2] == null) {
    return {'ready': false, 'stock': stock};
  }
  int setting(int index) => int.tryParse(values[index] ?? '') ?? 0;
  final cashOpen = setting(1), bankOpen = setting(2);
  final minimum = setting(3), budget = setting(4), extraReserve = setting(5);
  final start = vietnamWallDate(values[0]!);
  final now = vietnamWallDate(financeNow());
  final end = now.add(const Duration(minutes: 1));
  final ledger = await db.financeLedger(start, end);
  var cash = cashOpen, bank = bankOpen, unknown = 0, familySpent = 0;
  final monthStart = DateTime.utc(now.year, now.month);
  for (final entry in ledger) {
    final amount = (entry['amount'] as num).toInt();
    final income = entry['entry_type'] == 'income';
    final direction = income ? 1 : -1;
    final method = entry['payment_method'];
    if (method == 'cash') {
      cash += direction * amount;
    } else if (method == 'transfer') {
      bank += direction * amount;
    } else {
      unknown += amount;
    }
    if (entry['source_type'] == 'manual' &&
        entry['scope'] == 'personal' &&
        !vietnamWallDate('${entry['occurred_at']}').isBefore(monthStart)) {
      familySpent += direction * -amount;
    }
  }
  final scheduled = await db.recurringExpenses(now.year, now.month);
  var pendingBills = 0;
  for (final bill in scheduled) {
    if (bill['paid'] != true) {
      pendingBills += (bill['amount'] as num).toInt();
    }
  }
  final profit = await db.financeSummary(monthStart, end);
  final total = cash + bank;
  final available = total - minimum - pendingBills - extraReserve;
  final remainFamily = budget - familySpent;
  final candidate = available < remainFamily ? available : remainFamily;
  final canSpend = candidate > 0 ? candidate : 0;
  return {
    'ready': true,
    'started_at': values[0]!,
    'cash': cash,
    'bank': bank,
    'total': total,
    'stock': stock,
    'minimum': minimum,
    'budget': budget,
    'family_spent': familySpent,
    'family_remaining': remainFamily > 0 ? remainFamily : 0,
    'pending_bills': pendingBills,
    'extra_reserve': extraReserve,
    'available_before_budget': available,
    'safe_to_draw': canSpend,
    'unknown_payment_total': unknown,
    'month_profit': profit['business_profit'] ?? 0,
    'unclassified': profit['unclassified'] ?? 0,
    'pending_count': scheduled.where((r) => r['paid'] != true).length,
  };
}

class CapitalGuardPage extends StatefulWidget {
  const CapitalGuardPage({super.key});

  @override
  State<CapitalGuardPage> createState() => _CapitalGuardPageState();
}

class _CapitalGuardPageState extends State<CapitalGuardPage> {
  late Future<Map<String, Object?>> _future = loadCapitalGuard();

  void _refresh() => setState(() => _future = loadCapitalGuard());

  Future<void> _settings() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CapitalGuardSettingsPage()),
    );
    if (changed == true && mounted) _refresh();
  }

  Widget _metric(String title, String value, {String? details}) => SizedBox(
    width: 250,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 7),
            Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            if (details != null) Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(details, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _line(String label, int amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(vnd(amount), style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _notice(String message, {bool warning = false}) => Card(
    color: warning ? Colors.amber.shade50 : Colors.blue.shade50,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warning ? Icons.warning_amber : Icons.info_outline,
              color: warning ? Colors.orange.shade800 : Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bảo vệ vốn & ngân sách'),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Tải lại'),
        IconButton(onPressed: _settings, icon: const Icon(Icons.tune), tooltip: 'Thiết lập'),
      ],
    ),
    body: FutureBuilder<Map<String, Object?>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Không đọc được dữ liệu tài chính: ${snap.error}'),
              TextButton(onPressed: _refresh, child: const Text('Thử lại')),
            ],
          ));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final info = snap.data!;
        if (info['ready'] != true) {
          return ListView(padding: const EdgeInsets.all(20), children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 54, color: Color(0xff0877d1)),
            const SizedBox(height: 16),
            const Text('Chốt số dư đầu kỳ', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Anh đang dùng chung tiền cửa hàng và sinh hoạt. Hãy nhập số tiền mặt và tiền trong ngân hàng hiện có để app bắt đầu theo dõi từ thời điểm chốt.'),
            const SizedBox(height: 10),
            const Text('Số vốn hàng tồn kho được lấy từ dữ liệu hàng hóa trên app; không nhập 250 triệu hàng tồn thành một khoản thu.'),
            const SizedBox(height: 16),
            _metric('Vốn hàng theo app', vnd((info['stock'] as num).toInt()),
              details: 'Nếu chưa nhập đủ hàng thì con số này chưa đầy đủ.'),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _settings,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Thiết lập số dư & mục tiêu')),
          ]);
        }
        int n(String key) => (info[key] as num).toInt();
        final unknown = n('unknown_payment_total');
        final unclassified = n('unclassified');
        final safe = n('safe_to_draw');
        final capitalShort = n('available_before_budget') < 0;
        final thresholdMissing = n('minimum') == 0;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            Text('Dữ liệu tính từ ${DateFormat('dd/MM/yyyy HH:mm').format(vietnamWallDate(info['started_at'] as String))}',
              style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _metric('Tiền mặt dự kiến', vnd(n('cash'))),
              _metric('Ngân hàng dự kiến', vnd(n('bank'))),
              _metric('Tổng tiền dự kiến', vnd(n('total'))),
              _metric('Vốn hàng trong kho', vnd(n('stock'))),
              _metric('Lợi nhuận kinh doanh tháng', vnd(n('month_profit')),
                details: 'Không phải số tiền được phép tiêu'),
              _metric('Chi tiêu gia đình tháng', vnd(n('family_spent'))),
            ]),
            const SizedBox(height: 12),
            _notice('Tiền mặt và ngân hàng là số dư TÍNH TỪ GIAO DỊCH, không tự kết nối ngân hàng. Hãy đối chiếu với tiền thực tế mỗi ngày. Giao dịch chưa ghi hoặc sai phương thức thanh toán sẽ làm số dư lệch.'),
            if (unknown > 0) _notice(
              'Có ${vnd(unknown)} giao dịch chưa rõ tiền mặt hay ngân hàng trong thời gian theo dõi. Chưa thể xác nhận số tiền được rút an toàn. Hãy đối soát và phân loại.',
              warning: true,
            ),
            if (unclassified > 0) _notice(
              'Tháng này có ${vnd(unclassified)} thu/chi chưa phân loại. Lợi nhuận kinh doanh có thể chưa chính xác.',
              warning: true,
            ),
            if (thresholdMissing) _notice(
              'Anh chưa thiết lập mức vốn xoay vòng tối thiểu. Đừng dựa vào mức tiền có thể rút trước khi đặt vốn sàn.',
              warning: true,
            ),
            if (capitalShort) _notice(
              'Tiền hiện có không đủ cho mức vốn sàn và những khoản dự phòng đã khai. Ưu tiên giữ tiền, bán hàng tồn và rà soát chi phí.',
              warning: true,
            ),
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Giới hạn rút tiền cho gia đình',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _line('Tổng tiền đang theo dõi', n('total')),
                _line('Giữ lại để xoay vòng vốn', n('minimum')),
                _line('Khoản định kỳ tháng chưa thanh toán', n('pending_bills')),
                _line('Dự phòng bổ sung', n('extra_reserve')),
                const Divider(),
                _line('Ngân sách gia đình còn lại', n('family_remaining')),
                const SizedBox(height: 8),
                Text(
                  unknown > 0 || thresholdMissing
                      ? 'CẦN ĐỐI SOÁT TRƯỚC KHI XÁC ĐỊNH'
                      : vnd(safe),
                  style: TextStyle(
                    fontSize: unknown > 0 || thresholdMissing ? 17 : 28,
                    fontWeight: FontWeight.bold,
                    color: capitalShort ? Colors.red : Colors.teal.shade800,
                  ),
                ),
                const Text('Mức tính tham khảo, chưa tính khoản vay/chi phát sinh chưa khai, nhu cầu nhập hàng bất thường và giao dịch ngoài app. Không tự cho phép chi tiền.'),
              ]),
            )),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _settings, icon: const Icon(Icons.tune),
                label: const Text('Chỉnh mục tiêu vốn')),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CashBookPage()));
                  if (mounted) _refresh();
                },
                icon: const Icon(Icons.receipt_long),
                label: const Text('Xem Thu – Chi')),
            ]),
            const SizedBox(height: 12),
            const Text(
              'Nguyên tắc kế toán: Nhập hàng làm giảm tiền và tăng hàng tồn, chỉ tính giá vốn khi bán. Rút tiền sinh hoạt và trả gốc vay làm giảm tiền nhưng không làm giảm lợi nhuận. Tiền mặt + tồn kho chưa phải vốn chủ sở hữu vì còn các khoản vay/công nợ.',
            ),
          ],
        );
      },
    ),
  );
}

class CapitalGuardSettingsPage extends StatefulWidget {
  const CapitalGuardSettingsPage({super.key});

  @override
  State<CapitalGuardSettingsPage> createState() => _CapitalGuardSettingsPageState();
}

class _CapitalGuardSettingsPageState extends State<CapitalGuardSettingsPage> {
  final _cash = TextEditingController();
  final _bank = TextEditingController();
  final _minimum = TextEditingController();
  final _budget = TextEditingController();
  final _reserve = TextEditingController();
  late Future<void> _loading = _load();
  bool _busy = false;
  String? _start;

  Future<void> _load() async {
    final db = StoreDb.instance;
    final keys = [
      'capital_guard_started_at',
      'capital_guard_open_cash',
      'capital_guard_open_bank',
      'capital_guard_min_working',
      'capital_guard_family_budget',
      'capital_guard_extra_reserve',
    ];
    final values = await Future.wait(keys.map(db.getSetting));
    _start = values[0];
    _cash.text = values[1] ?? '';
    _bank.text = values[2] ?? '';
    _minimum.text = values[3] ?? '';
    _budget.text = values[4] ?? '';
    _reserve.text = values[5] ?? '';
  }

  @override
  void dispose() {
    for (final field in [_cash, _bank, _minimum, _budget, _reserve]) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _field(String title, TextEditingController controller, String hint) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: title, helperText: hint),
    ),
  );

  Future<void> _save() async {
    final fields = [_cash, _bank, _minimum, _budget, _reserve];
    if (fields.any((f) => f.text.trim().isEmpty)) {
      showError(context, 'Hãy nhập đủ cả 5 mục; khoản không có thì ghi 0.');
      return;
    }
    final amounts = fields.map((f) => int.tryParse(f.text.trim())).toList();
    if (amounts.any((n) => n == null || n < 0)) {
      showError(context, 'Số tiền không hợp lệ.');
      return;
    }
    setState(() => _busy = true);
    try {
      final db = StoreDb.instance;
      final settings = {
        'capital_guard_open_cash': _cash.text.trim(),
        'capital_guard_open_bank': _bank.text.trim(),
        'capital_guard_min_working': _minimum.text.trim(),
        'capital_guard_family_budget': _budget.text.trim(),
        'capital_guard_extra_reserve': _reserve.text.trim(),
      };
      for (final setting in settings.entries) {
        await db.setSetting(setting.key, setting.value);
      }
      // Chỉ chốt thời điểm lần đầu, không tự đặt lại khi anh chỉnh ngân sách.
      if (_start == null) {
        await db.setSetting('capital_guard_started_at', financeNow());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mục tiêu & số dư đầu kỳ')),
    body: FutureBuilder<void>(
      future: _loading,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Không tải được thiết lập: ${snap.error}'));
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(_start == null
              ? 'Đếm tiền mặt, kiểm tra số dư ngân hàng rồi chốt tại đây. Anh có thể dùng chung tài khoản, app sẽ theo dõi bằng các giao dịch được ghi lại.'
              : 'Anh đang chỉnh số dư ĐẦU KỲ. Việc sửa số dư này sẽ tính lại mọi số dư dự kiến kể từ ngày chốt ban đầu.',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 16),
          _field('Tiền mặt ban đầu (đ)', _cash, 'Tiền trong két và ví'),
          _field('Ngân hàng ban đầu (đ)', _bank, 'Tổng tài khoản đang dùng chung'),
          const Divider(),
          _field('Vốn xoay vòng tối thiểu (đ)', _minimum, 'Mức tiền cần giữ để nhập máy, phụ kiện'),
          _field('Ngân sách gia đình mỗi tháng (đ)', _budget, 'Giới hạn rút cho ăn uống, con cái, sinh hoạt'),
          _field('Dự phòng bổ sung (đ)', _reserve, 'Không bao gồm các khoản cố định đã khai'),
          const Text('Các khoản cố định chưa thanh toán sẽ tự được giữ lại từ lịch chi phí trên Sổ quỹ. Không nhập lặp chúng vào dự phòng bổ sung.'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_busy ? 'Đang lưu...' : 'Lưu & bắt đầu theo dõi'),
          ),
        ]);
      },
    ),
  );
}
