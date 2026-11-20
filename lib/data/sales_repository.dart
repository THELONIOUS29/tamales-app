import 'package:supabase_flutter/supabase_flutter.dart';

typedef RecordData = Map<String, dynamic>;

class DataValidationException implements Exception {
  DataValidationException(this.message);
  final String message;
}

/// Importes enteros: nunca se calcula dinero con double.
int? parseCents(String input) {
  final value = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

String decimalPrice(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
String money(int cents, String currency) => '$currency ${decimalPrice(cents)}';
String dateLabel(String iso) {
  final parts = iso.split('-');
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

String dateValue(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

int? parseQuantity(String value) {
  if (value.trim().isEmpty) return 0;
  if (!RegExp(r'^\d{1,6}$').hasMatch(value.trim())) return null;
  return int.tryParse(value.trim());
}

class SaleTotals {
  SaleTotals(Iterable<RecordData> orders) {
    for (final order in orders) {
      pork += order['pork_quantity'] as int;
      chicken += order['chicken_quantity'] as int;
      sold += order['total_cents'] as int;
      if (order['delivered'] == true) {
        delivered++;
      } else {
        remainingPork += order['pork_quantity'] as int;
        remainingChicken += order['chicken_quantity'] as int;
      }
      count++;
    }
  }
  int pork = 0, chicken = 0, sold = 0, delivered = 0, count = 0;
  int remainingPork = 0, remainingChicken = 0;
}

abstract class SalesRepository {
  Future<Map<String, List<RecordData>>> dashboardSnapshot() =>
      throw UnimplementedError();
  Future<List<RecordData>> sales({int offset = 0});
  Future<RecordData> sale(String id) async =>
      (await sales()).firstWhere((row) => row['id'] == id);
  Future<RecordData> saveSale(RecordData data, {required bool creating});
  Future<List<RecordData>> orders(String saleId);
  Future<List<RecordData>> clients();
  Future<RecordData> saveOrder(RecordData data, {required bool creating});
  Future<void> deliver(String id, bool value);
  Future<RecordData> order(String id);
  Future<List<RecordData>> expenses(String saleId);
  Future<RecordData> saveExpense(RecordData data, {required bool creating});
  Future<void> deleteExpense(String id);
  Future<void> recordPayment(RecordData data, {required bool settle});
  Future<void> deletePayment(String id);
  Future<List<RecordData>> pending({int offset = 0});
  Future<RecordData> prepareDeletion(String table, String id) async => {};
  Future<void> deleteRecord(String table, String id, {RecordData? preview}) =>
      throw UnimplementedError();
  Future<RecordData> saveClient(RecordData data, {required bool creating}) =>
      throw UnimplementedError();
}

class SupabaseSalesRepository implements SalesRepository {
  SupabaseSalesRepository(this.ownerId);
  final String ownerId;
  final _db = Supabase.instance.client;
  @override
  Future<Map<String, List<RecordData>>> dashboardSnapshot() async {
    const names = ['clients', 'sales', 'orders', 'payments', 'expenses'];
    final rows = await Future.wait(
      names.map(
        (table) => _all(
          (from, to) => _db.from(table).select().order('id').range(from, to),
        ),
      ),
    );
    return {for (var i = 0; i < names.length; i++) names[i]: rows[i]};
  }

  @override
  Future<RecordData> prepareDeletion(String table, String id) async =>
      table == 'clients'
      ? {}
      : Map<String, dynamic>.from(
          await _db.rpc(
                'deletion_preview',
                params: {'p_table': table, 'p_id': id},
              )
              as Map,
        );
  @override
  Future<void> deleteRecord(
    String table,
    String id, {
    RecordData? preview,
  }) async {
    if (!['clients', 'orders', 'sales'].contains(table)) {
      throw ArgumentError(table);
    }
    if (table != 'clients') {
      await _db.rpc(
        'delete_business_record',
        params: {
          'p_table': table,
          'p_id': id,
          'p_expected': preview?['fingerprint'],
        },
      );
    } else {
      await _db.from(table).delete().eq('id', id);
    }
  }

  @override
  Future<RecordData> sale(String id) =>
      _db.from('sales').select().eq('id', id).single();
  @override
  Future<RecordData> saveClient(RecordData data, {required bool creating}) =>
      _save('clients', data, creating);

  @override
  Future<List<RecordData>> sales({int offset = 0}) => _db
      .from('sales')
      .select()
      .order('sale_date', ascending: false)
      .order('id')
      .range(offset, offset + 19);

  // Recorre todas las páginas para no presentar un resumen incompleto por el
  // límite de filas de la API. Solo se ejecuta al abrir o actualizar esa venta.
  Future<List<RecordData>> _all(
    Future<List<RecordData>> Function(int, int) page,
  ) async {
    final rows = <RecordData>[];
    var offset = 0;
    while (true) {
      final batch = await page(offset, offset + 499);
      rows.addAll(batch);
      if (batch.length < 500) return rows;
      offset += batch.length;
    }
  }

  @override
  Future<List<RecordData>> clients() => _all(
    (from, to) => _db
        .from('clients')
        .select('id,name,phone,address,reference,latitude,longitude')
        .order('name')
        .order('id')
        .range(from, to),
  );

  @override
  Future<List<RecordData>> orders(String saleId) => _all(
    (from, to) => _db
        .from('orders')
        .select(
          '*, clients(name,phone), payments(id,amount_cents,paid_at,method,notes)',
        )
        .eq('sale_id', saleId)
        .order('created_at')
        .order('id')
        .range(from, to),
  );

  Future<RecordData> _save(String table, RecordData data, bool creating) async {
    final payload = {...data, 'owner_id': ownerId};
    if (creating) {
      try {
        return await _db.from(table).insert(payload).select().single();
      } on PostgrestException catch (error) {
        // Un reintento usa el mismo ID: no crea una segunda venta/pedido.
        if (error.code != '23505') rethrow;
      }
    }
    final changes = {...payload}..remove('id');
    return _db
        .from(table)
        .update(changes)
        .eq('id', data['id'] as String)
        .select()
        .single();
  }

  @override
  Future<RecordData> saveSale(RecordData data, {required bool creating}) =>
      _save('sales', data, creating);
  @override
  Future<RecordData> saveOrder(RecordData data, {required bool creating}) =>
      _save('orders', data, creating);
  @override
  Future<void> deliver(String id, bool value) async {
    await _db
        .from('orders')
        .update({'delivered': value})
        .eq('id', id)
        .select('id')
        .single();
  }

  @override
  Future<RecordData> order(String id) => _db
      .from('orders')
      .select(
        '*,clients(name,phone),payments(id,amount_cents,paid_at,method,notes)',
      )
      .eq('id', id)
      .single();

  @override
  Future<List<RecordData>> expenses(String saleId) => _all(
    (from, to) => _db
        .from('expenses')
        .select()
        .eq('sale_id', saleId)
        .order('spent_on', ascending: false)
        .order('id')
        .range(from, to),
  );

  @override
  Future<RecordData> saveExpense(RecordData data, {required bool creating}) =>
      _save('expenses', data, creating);

  @override
  Future<void> deleteExpense(String id) async {
    await _db.from('expenses').delete().eq('id', id).select('id').single();
  }

  @override
  Future<void> recordPayment(RecordData data, {required bool settle}) async {
    await _db.rpc(
      'record_payment',
      params: {
        'p_id': data['id'],
        'p_order_id': data['order_id'],
        'p_amount_cents': data['amount_cents'],
        'p_paid_at': data['paid_at'],
        'p_method': data['method'],
        'p_notes': data['notes'],
        'p_settle': settle,
      },
    );
  }

  @override
  Future<void> deletePayment(String id) async {
    await _db.from('payments').delete().eq('id', id).select('id').single();
  }

  @override
  Future<List<RecordData>> pending({int offset = 0}) async {
    final rows = await _db.rpc(
      'pending_balances',
      params: {'p_offset': offset, 'p_limit': 50},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
