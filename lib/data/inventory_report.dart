part of '../main.dart';

extension InventoryPeriodReport on StoreDb {
  Future<List<Map<String, Object?>>> _inventoryPeriodRows(
    List<Map<String, Object?>> products,
    DateTime from,
    DateTime to,
  ) async {
    final db = await _executor;
    final movements = await db.query('inventory_movements');
    final byProduct = <int, List<Map<String, Object?>>>{};
    for (final row in movements) {
      (byProduct[row['product_id'] as int] ??= []).add(row);
    }
    final sales = await db.rawQuery(
      "SELECT si.*,s.created_at FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.status='completed'",
    );
    final soldByProduct = <int, List<Map<String, Object?>>>{};
    for (final row in sales) {
      (soldByProduct[row['product_id'] as int] ??= []).add(row);
    }
    final start = DateTime.utc(
          from.year,
          from.month,
          from.day,
          from.hour,
          from.minute,
        ),
        end = DateTime.utc(to.year, to.month, to.day, to.hour, to.minute);
    return products.map((row) {
      var incoming = 0,
          outgoing = 0,
          after = 0,
          revenue = 0,
          cost = 0,
          sold = 0;
      for (final movement in byProduct[row['id']] ?? <Map<String, Object?>>[]) {
        final date = vietnamWallDate('${movement['created_at']}');
        final delta = movement['quantity_delta'] as int;
        if (!date.isBefore(end)) {
          after += delta;
        } else if (!date.isBefore(start)) {
          if (delta > 0) {
            incoming += delta;
          } else {
            outgoing -= delta;
          }
        }
      }
      for (final sale in soldByProduct[row['id']] ?? <Map<String, Object?>>[]) {
        final date = vietnamWallDate('${sale['created_at']}');
        if (date.isBefore(start) || !date.isBefore(end)) continue;
        revenue += sale['line_total'] as int;
        cost += sale['line_cost'] as int;
        sold += sale['quantity'] as int;
      }
      final closing = (row['stock'] as num).toInt() - after;
      return {
        ...row,
        'opening_stock': closing - incoming + outgoing,
        'incoming': incoming,
        'outgoing': outgoing,
        'closing_stock': closing,
        'revenue': revenue,
        'profit': revenue - cost,
        'sold_quantity': sold,
      };
    }).toList();
  }
}
