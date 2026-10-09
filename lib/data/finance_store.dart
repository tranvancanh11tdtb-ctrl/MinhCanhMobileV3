part of '../main.dart';

const financeScopes = <String, String>{
  'business': 'Cửa hàng',
  'personal': 'Cá nhân / gia đình',
  'loan_principal': 'Trả gốc vay',
  'business_interest': 'Lãi vay cửa hàng',
  'loan_received': 'Nhận tiền vay',
  'unclassified': 'Chưa phân loại',
};
DateTime vietnamWallDate(String source) {
  final date = DateTime.parse(source);
  final shifted =
      RegExp(r'(Z|[+-]\d{2}:\d{2})$', caseSensitive: false).hasMatch(source)
      ? date.toUtc().add(const Duration(hours: 7))
      : date;
  return DateTime.utc(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
    shifted.microsecond,
  );
}

String financeNow() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 7))
    .toIso8601String()
    .replaceAll('Z', '');

extension FinanceStore on StoreDb {
  Future<void> _createFinanceTables(DatabaseExecutor db) async {
    final columns = (await db.rawQuery('PRAGMA table_info(cash_entries)'))
        .map((r) => r['name'])
        .toSet();
    for (final column in {
      'scope': "TEXT NOT NULL DEFAULT 'unclassified'",
      'payment_method': "TEXT NOT NULL DEFAULT 'unknown'",
      'occurred_at': "TEXT NOT NULL DEFAULT ''",
    }.entries) {
      if (!columns.contains(column.key))
        await db.execute(
          'ALTER TABLE cash_entries ADD COLUMN ${column.key} ${column.value}',
        );
    }
    await db.execute(
      "UPDATE cash_entries SET occurred_at=created_at WHERE occurred_at=''",
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS recurring_expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS recurring_payments(template_id INTEGER NOT NULL REFERENCES recurring_expenses(id), month TEXT NOT NULL, cash_entry_id INTEGER NOT NULL REFERENCES cash_entries(id), PRIMARY KEY(template_id,month))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS payment_events(id INTEGER PRIMARY KEY AUTOINCREMENT, source_type TEXT NOT NULL, source_id INTEGER NOT NULL, entry_type TEXT NOT NULL, amount INTEGER NOT NULL, payment_method TEXT NOT NULL, occurred_at TEXT NOT NULL, note TEXT NOT NULL DEFAULT \'\')',
    );
    final repairColumns = (await db.rawQuery('PRAGMA table_info(repairs)'))
        .map((r) => r['name'])
        .toSet();
    if (!repairColumns.contains('initial_paid')) {
      await db.execute(
        'ALTER TABLE repairs ADD COLUMN initial_paid INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('UPDATE repairs SET initial_paid=paid');
    }
  }

  Future<int> saveCashEntry({
    int? id,
    required String type,
    required String scope,
    required String category,
    required int amount,
    required String note,
    required String paymentMethod,
    required String occurredAt,
  }) async {
    final args = <String, Object?>{
      'id': id,
      'type': type,
      'scope': scope,
      'category': category,
      'amount': amount,
      'note': note,
      'paymentMethod': paymentMethod,
      'occurredAt': occurredAt,
    };
    if (kIsWeb)
      return await remoteBridge.call('saveCashEntry', args, write: true) as int;
    return _callLocal(() async {
      if (!['income', 'expense'].contains(type) ||
          !financeScopes.containsKey(scope) ||
          amount <= 0)
        throw ArgumentError('Loại, nhóm hoặc số tiền không hợp lệ');
      if (!['cash', 'transfer', 'unknown'].contains(paymentMethod))
        throw ArgumentError('Phương thức không hợp lệ');
      if ((scope == 'loan_received' && type != 'income') ||
          (['loan_principal', 'business_interest'].contains(scope) &&
              type != 'expense'))
        throw ArgumentError('Nhóm vay không phù hợp với thu/chi');
      final when = vietnamWallDate(occurredAt)
          .toIso8601String()
          .replaceAll('Z', '');
      final db = await _executor;
      final values = <String, Object?>{
        'entry_type': type,
        'scope': scope,
        'category': category.trim().isEmpty
            ? financeScopes[scope]
            : category.trim(),
        'amount': amount,
        'note': note.trim(),
        'payment_method': paymentMethod,
        'occurred_at': when,
      };
      if (id == null) {
        values['created_at'] = financeNow();
        return db.insert('cash_entries', values);
      }
      if ((await db.query(
        'recurring_payments',
        where: 'cash_entry_id=?',
        whereArgs: [id],
      )).isNotEmpty)
        throw StateError('Khoản định kỳ đã thanh toán không sửa tại sổ quỹ');
      if (await db.update(
            'cash_entries',
            values,
            where: 'id=?',
            whereArgs: [id],
          ) !=
          1)
        throw StateError('Khoản thu/chi không còn tồn tại');
      return id;
    }, write: true);
  }

  Future<List<Map<String, Object?>>> financeLedger(
    DateTime from,
    DateTime to,
  ) async {
    if (kIsWeb)
      return (await remoteBridge.call(
        'financeLedger',
        {'from': from.toIso8601String(), 'to': to.toIso8601String()},
        write: false,
      ) as List).map((r) => Map<String, Object?>.from(r as Map)).toList();
    return _callLocal(() async {
      final db = await _executor;
      final result = <Map<String, Object?>>[];
      void add(
        String source,
        int id,
        String type,
        int amount,
        String date,
        String label,
        String method, {
        String scope = 'business',
        String note = '',
      }) {
        if (amount == 0) return;
        final wall = vietnamWallDate(date);
        final start = DateTime.utc(
          from.year,
          from.month,
          from.day,
          from.hour,
          from.minute,
        );
        final end = DateTime.utc(to.year, to.month, to.day, to.hour, to.minute);
        if (wall.isBefore(start) || !wall.isBefore(end)) return;
        result.add({
          'source_type': source,
          'source_id': id,
          'entry_type': amount < 0
              ? (type == 'income' ? 'expense' : 'income')
              : type,
          'amount': amount.abs(),
          'occurred_at': wall.toIso8601String().replaceAll('Z', ''),
          'category': label,
          'payment_method': method,
          'scope': scope,
          'note': note,
        });
      }

      for (final r in await db.query('cash_entries')) {
        add(
          'manual',
          r['id'] as int,
          r['entry_type'] as String,
          r['amount'] as int,
          '${r['occurred_at']}',
          '${r['category']}',
          '${r['payment_method']}',
          scope: '${r['scope']}',
          note: '${r['note']}',
        );
      }
      for (final r in await db.query('sales', where: "status='completed'")) {
        add(
          'sale',
          r['id'] as int,
          'income',
          r['paid_cash'] as int,
          '${r['created_at']}',
          'Bán hàng ${r['code']}',
          'cash',
        );
        add(
          'sale',
          r['id'] as int,
          'income',
          r['paid_transfer'] as int,
          '${r['created_at']}',
          'Bán hàng ${r['code']}',
          'transfer',
        );
      }
      for (final r in await db.query(
        'purchases',
        where: "status='completed'",
      )) {
        add(
          'purchase',
          r['id'] as int,
          'expense',
          r['paid'] as int,
          '${r['created_at']}',
          'Nhập hàng ${r['code']}',
          _financeMethod('${r['payment_method']}'),
          scope: 'inventory',
        );
      }
      for (final r in await db.query('repairs', where: "status!='cancelled'")) {
        add(
          'repair',
          r['id'] as int,
          'income',
          r['initial_paid'] as int,
          '${r['received_at']}',
          'Sửa chữa ${r['code']}',
          'unknown',
        );
      }
      for (final r in await db.query('payment_events')) {
        if (r['source_type'] == 'repair') {
          final repairs = await db.query(
            'repairs',
            where: 'id=?',
            whereArgs: [r['source_id']],
          );
          if (repairs.isEmpty || repairs.single['status'] == 'cancelled')
            continue;
        }
        add(
          '${r['source_type']}_payment',
          r['id'] as int,
          '${r['entry_type']}',
          r['amount'] as int,
          '${r['occurred_at']}',
          '${r['note']}',
          '${r['payment_method']}',
          scope: r['source_type'] == 'supplier' ? 'inventory' : 'business',
        );
      }
      result.sort(
        (a, b) => '${b['occurred_at']}'.compareTo('${a['occurred_at']}'),
      );
      return result;
    }, write: false);
  }

  String _financeMethod(String raw) => ['cash', 'Tiền mặt'].contains(raw)
      ? 'cash'
      : ['transfer', 'Chuyển khoản'].contains(raw)
      ? 'transfer'
      : 'unknown';

  Future<Map<String, int>> financeSummary(DateTime from, DateTime to) async {
    if (kIsWeb)
      return (await remoteBridge.call(
        'financeSummary',
        {'from': from.toIso8601String(), 'to': to.toIso8601String()},
        write: false,
      ) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()));
    return _callLocal(() async {
      final ledger = await financeLedger(from, to);
      final db = await _executor;
      final out = <String, int>{
        'income': 0,
        'expense': 0,
        'business_income': 0,
        'business_expenses': 0,
        'personal_expenses': 0,
        'principal_paid': 0,
        'unclassified': 0,
        'gross_profit': 0,
        'revenue': 0,
        'cash_flow': 0,
        'business_profit': 0,
        'remaining_profit': 0,
      };
      for (final row in ledger) {
        final amount = row['amount'] as int;
        final income = row['entry_type'] == 'income';
        out[income ? 'income' : 'expense'] =
            out[income ? 'income' : 'expense']! + amount;
        if (row['source_type'] == 'manual') {
          switch (row['scope']) {
            case 'business':
            case 'business_interest':
              out[income ? 'business_income' : 'business_expenses'] =
                  out[income ? 'business_income' : 'business_expenses']! +
                  amount;
            case 'personal':
              out['personal_expenses'] =
                  out['personal_expenses']! + (income ? -amount : amount);
            case 'loan_principal':
              out['principal_paid'] =
                  out['principal_paid']! + (income ? -amount : amount);
            case 'unclassified':
              out['unclassified'] = out['unclassified']! + amount;
          }
        }
      }
      bool includes(String date) {
        final wall = vietnamWallDate(date);
        return !wall.isBefore(
              DateTime.utc(
                from.year,
                from.month,
                from.day,
                from.hour,
                from.minute,
              ),
            ) &&
            wall.isBefore(
              DateTime.utc(to.year, to.month, to.day, to.hour, to.minute),
            );
      }

      for (final r in await db.query('sales', where: "status='completed'")) {
        if (includes('${r['created_at']}')) {
          out['gross_profit'] =
              out['gross_profit']! +
              (r['total'] as int) -
              (r['cost_total'] as int);
          out['revenue'] = out['revenue']! + (r['total'] as int);
        }
      }
      for (final r in await db.query(
        'repairs',
        where: "status IN ('completed','returned')",
      )) {
        if (includes('${r['completed_at'] ?? r['received_at']}')) {
          out['gross_profit'] =
              out['gross_profit']! +
              (r['amount'] as int) -
              (r['parts_cost'] as int);
          out['revenue'] = out['revenue']! + (r['amount'] as int);
        }
      }
      out['cash_flow'] = out['income']! - out['expense']!;
      out['business_profit'] =
          out['gross_profit']! +
          out['business_income']! -
          out['business_expenses']!;
      out['remaining_profit'] =
          out['business_profit']! -
          out['personal_expenses']! -
          out['principal_paid']!;
      return out;
    }, write: false);
  }

  Future<int> saveRecurringExpense({
    int? id,
    required Map<String, Object?> payload,
  }) async {
    if (kIsWeb)
      return await remoteBridge.call('saveRecurringExpense', {
        'id': id,
        'payload': payload,
      }, write: true) as int;
    return _callLocal(() async {
      if ((payload['amount'] as int? ?? 0) <= 0 ||
          (payload['day'] as int? ?? 0) < 1 ||
          (payload['day'] as int? ?? 0) > 31 ||
          '${payload['title'] ?? ''}'.trim().isEmpty)
        throw ArgumentError('Tên, số tiền hoặc ngày đến hạn không hợp lệ');
      final start = '${payload['start_month'] ?? ''}';
      if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(start))
        throw ArgumentError('Tháng bắt đầu không hợp lệ');
      if (![
        'business',
        'personal',
        'loan_principal',
        'business_interest',
      ].contains(payload['scope']))
        throw ArgumentError('Nhóm chi không hợp lệ');
      final db = await _executor;
      final values = {'payload': jsonEncode(payload)};
      if (id == null) return db.insert('recurring_expenses', values);
      if (await db.update(
            'recurring_expenses',
            values,
            where: 'id=?',
            whereArgs: [id],
          ) !=
          1)
        throw StateError('Khoản định kỳ không còn tồn tại');
      return id;
    }, write: true);
  }

  Future<List<Map<String, Object?>>> recurringExpenses(
    int year,
    int month,
  ) async {
    if (kIsWeb)
      return (await remoteBridge.call(
        'recurringExpenses',
        {'year': year, 'month': month},
        write: false,
      ) as List).map((r) => Map<String, Object?>.from(r as Map)).toList();
    return _callLocal(() async {
      if (month < 1 || month > 12 || year < 2000 || year > 2100)
        throw ArgumentError('Tháng không hợp lệ');
      final db = await _executor;
      final key = '$year-${month.toString().padLeft(2, '0')}';
      final rows = <Map<String, Object?>>[];
      for (final row in await db.query('recurring_expenses')) {
        final data = Map<String, Object?>.from(
          jsonDecode(row['payload'] as String) as Map,
        );
        if ('${data['start_month']}'.compareTo(key) > 0 ||
            data['active'] == false)
          continue;
        final last = DateTime(year, month + 1, 0).day;
        final day = (data['day'] as int).clamp(1, last);
        final payment = await db.query(
          'recurring_payments',
          where: 'template_id=? AND month=?',
          whereArgs: [row['id'], key],
        );
        rows.add({
          ...data,
          'id': row['id'],
          'due_date': '$key-${day.toString().padLeft(2, '0')}',
          'paid': payment.isNotEmpty,
          'cash_entry_id': payment.isEmpty
              ? null
              : payment.single['cash_entry_id'],
        });
      }
      return rows;
    }, write: false);
  }

  Future<int> payRecurringExpense(
    int id,
    int year,
    int month,
    String paymentMethod,
    String occurredAt,
  ) async {
    if (kIsWeb)
      return await remoteBridge.call('payRecurringExpense', {
        'id': id,
        'year': year,
        'month': month,
        'paymentMethod': paymentMethod,
        'occurredAt': occurredAt,
      }, write: true) as int;
    return _callLocal(() async {
      final db = await _executor;
      final key = '$year-${month.toString().padLeft(2, '0')}';
      final prior = await db.query(
        'recurring_payments',
        where: 'template_id=? AND month=?',
        whereArgs: [id, key],
      );
      if (prior.isNotEmpty) return prior.single['cash_entry_id'] as int;
      final rows = await recurringExpenses(year, month);
      final row = rows.firstWhere(
        (r) => r['id'] == id,
        orElse: () => throw StateError('Không tìm thấy khoản định kỳ'),
      );
      final entry = await saveCashEntry(
        type: 'expense',
        scope: '${row['scope']}',
        category: '${row['category'] ?? row['title']}',
        amount: row['amount'] as int,
        note: '${row['title']} • $key',
        paymentMethod: paymentMethod,
        occurredAt: occurredAt,
      );
      await db.insert('recurring_payments', {
        'template_id': id,
        'month': key,
        'cash_entry_id': entry,
      });
      return entry;
    }, write: true);
  }

  Future<void> deleteRecurringExpense(int id) async {
    if (kIsWeb) {
      await remoteBridge.call('deleteRecurringExpense', {
        'id': id,
      }, write: true);
      return;
    }
    return _callLocal(() async {
      final db = await _executor;
      final row = (await db.query(
        'recurring_expenses',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      final data = Map<String, Object?>.from(
        jsonDecode(row['payload'] as String) as Map,
      )..['active'] = false;
      await db.update(
        'recurring_expenses',
        {'payload': jsonEncode(data)},
        where: 'id=?',
        whereArgs: [id],
      );
    }, write: true);
  }
}
