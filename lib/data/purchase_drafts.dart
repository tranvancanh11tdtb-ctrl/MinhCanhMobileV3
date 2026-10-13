part of '../main.dart';

extension PurchaseDraftStore on StoreDb {
  Future<void> _createV9Tables(DatabaseExecutor db) async {
    await _createFinanceTables(db);
    await db.execute(
      'CREATE TABLE IF NOT EXISTS purchase_drafts(id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, updated_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS purchase_completions(completion_key TEXT PRIMARY KEY, purchase_id INTEGER NOT NULL REFERENCES purchases(id), payload_hash TEXT NOT NULL)',
    );
  }

  Future<int> savePurchaseDraft({
    int? id,
    required Map<String, Object?> payload,
  }) async {
    if (kIsWeb)
      return await remoteBridge.call('savePurchaseDraft', {
        'id': id,
        'payload': payload,
      }, write: true) as int;
    return _callLocal(() async {
      final db = await _executor;
      final values = {
        'payload': jsonEncode(payload),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (id == null) return db.insert('purchase_drafts', values);
      if (await db.update(
            'purchase_drafts',
            values,
            where: 'id=?',
            whereArgs: [id],
          ) !=
          1)
        throw StateError('Phiếu tạm không còn tồn tại');
      return id;
    }, write: true);
  }

  Future<List<Map<String, Object?>>> purchaseDrafts() async {
    if (kIsWeb)
      return (await remoteBridge.call(
        'purchaseDrafts',
        {},
        write: false,
      ) as List).map((v) => Map<String, Object?>.from(v as Map)).toList();
    return _callLocal(
      () async =>
          (await (await _executor).query(
                'purchase_drafts',
                orderBy: 'updated_at DESC',
              ))
              .map((r) => {...r, 'payload': jsonDecode(r['payload'] as String)})
              .toList(),
      write: false,
    );
  }

  Future<Map<String, Object?>> purchaseDraft(int id) async {
    final rows = await purchaseDrafts();
    return rows.firstWhere(
      (r) => r['id'] == id,
      orElse: () => throw StateError('Không tìm thấy phiếu tạm'),
    );
  }

  Future<void> deletePurchaseDraft(int id) async {
    if (kIsWeb) {
      await remoteBridge.call('deletePurchaseDraft', {'id': id}, write: true);
      return;
    }
    return _callLocal(() async {
      await (await _executor).delete(
        'purchase_drafts',
        where: 'id=?',
        whereArgs: [id],
      );
    }, write: true);
  }
}
