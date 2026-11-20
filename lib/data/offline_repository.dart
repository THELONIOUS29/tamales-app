import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'finances.dart';
import 'local_store.dart';
import 'sales_repository.dart';
import 'sync_gateway.dart';

final activeOfflineRepository = ValueNotifier<OfflineRepository?>(null);

class OfflineRepository extends ChangeNotifier implements SalesRepository {
  OfflineRepository({
    required this.ownerId,
    required this.store,
    required this.gateway,
  });
  final String ownerId;
  final LocalStore store;
  final SyncGateway gateway;
  @override
  Future<Map<String, List<RecordData>>> dashboardSnapshot() => store.snapshot();
  StreamSubscription<List<ConnectivityResult>>? _connection;
  Timer? _retry;
  Completer<void>? _idle;
  Future<void> get idle async {
    while (syncing) {
      await _idle?.future;
    }
  }

  bool syncing = false, online = false, revoked = false, initialized = false;
  bool _transport = true, _foreground = true, _again = false, _disposed = false;
  int _failures = 0;
  List<LocalMutation> operations = [];
  String? lastError;
  int get pendingCount => operations.length;
  List<LocalMutation> get conflicts =>
      operations.where((op) => op.error != null).toList();

  static Future<OfflineRepository> open(String ownerId) async {
    final repository = OfflineRepository(
      ownerId: ownerId,
      store: await LocalStore.open(ownerId),
      gateway: SupabaseSyncGateway(ownerId),
    );
    await repository.initialize(watchConnectivity: true);
    return repository;
  }

  Future<void> initialize({bool watchConnectivity = false}) async {
    initialized = await store.meta('initialized') == 'true';
    revoked = await store.meta('revoked') == 'true';
    await _refreshQueue();
    if (watchConnectivity) {
      final connectivity = Connectivity();
      _connection = connectivity.onConnectivityChanged.listen((results) {
        setConnectivity(results.any((r) => r != ConnectivityResult.none));
      });
      setConnectivity(
        (await connectivity.checkConnectivity()).any(
          (r) => r != ConnectivityResult.none,
        ),
      );
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _refreshQueue() async {
    operations = await store.queue();
  }

  void setConnectivity(bool available) {
    _transport = available;
    if (!available) {
      online = false;
      _retry?.cancel();
      _emit();
    } else {
      unawaited(synchronize());
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value) {
      unawaited(synchronize());
    } else {
      _retry?.cancel();
    }
  }

  Future<void> _pull() async {
    if (!initialized) {
      final snapshot = await gateway.bootstrap().timeout(
        const Duration(seconds: 12),
      );
      await store.bootstrap(snapshot);
      initialized = true;
    }
    var cursor = int.parse(await store.meta('cursor') ?? '0');
    while (_foreground && _transport) {
      final events = await gateway
          .changes(cursor)
          .timeout(const Duration(seconds: 12));
      if (events.isEmpty) return;
      await store.applyChanges(events);
      cursor = events.last['sequence'] as int;
      if (events.length < 500) return;
    }
  }

  /// Solo corre con la app activa: al recuperar red, guardar, actualizar o volver.
  Future<void> synchronize() async {
    if (_disposed || !_foreground || !_transport) return;
    if (syncing) {
      _again = true;
      await _idle?.future;
      return;
    }
    syncing = true;
    _idle = Completer<void>();
    _retry?.cancel();
    lastError = null;
    _emit();
    try {
      final authorized = await gateway.authorizedOwner().timeout(
        const Duration(seconds: 10),
      );
      online = true;
      revoked = authorized != ownerId;
      await store.setMeta('revoked', revoked.toString());
      if (revoked) {
        lastError =
            'Este teléfono ya no está autorizado. Sus cambios siguen guardados aquí.';
        return;
      }
      await _pull();
      while (_foreground && _transport) {
        final pending = await store.queue();
        if (pending.isEmpty) {
          _again = false;
          break;
        }
        final operation = pending.first;
        if (operation.error != null) break;
        try {
          final record = await gateway
              .push(operation)
              .timeout(const Duration(seconds: 12));
          await store.acknowledge(operation, record);
        } on SyncConflict catch (error) {
          await store.fail(operation.sequence, error.message);
          break;
        }
      }
      await _pull();
      _failures = 0;
    } catch (error) {
      online = false;
      lastError = error is PostgrestException
          ? 'No se pudo sincronizar. Revisa la configuración de Supabase o vuelve a intentar.'
          : 'Sin conexión con Supabase. Los cambios permanecen en este teléfono.';
      _failures++;
      if (_foreground && _transport && !_disposed) {
        final delay = [5, 15, 45, 120][_failures.clamp(1, 4) - 1];
        _retry = Timer(
          Duration(seconds: delay),
          () => unawaited(synchronize()),
        );
      }
    } finally {
      await _refreshQueue();
      syncing = false;
      _emit();
      _idle?.complete();
      if (_again && !_disposed && _foreground && _transport) {
        _again = false;
        unawaited(synchronize());
      }
    }
  }

  Future<void> retry(LocalMutation operation) async {
    await store.retry(operation.sequence);
    await _refreshQueue();
    _emit();
    await synchronize();
  }

  Future<void> discard(LocalMutation operation) async {
    await store.discard(operation.sequence);
    await _refreshQueue();
    _emit();
    unawaited(synchronize());
  }

  void _checkAccess() {
    if (revoked) {
      throw DataValidationException(
        'Este teléfono necesita autorización antes de registrar más cambios.',
      );
    }
  }

  Future<void> _enqueue(
    String table,
    String id,
    String kind,
    RecordData payload, {
    String? mutationId,
  }) async {
    _checkAccess();
    await store.enqueue(
      mutationId: mutationId ?? const Uuid().v4(),
      table: table,
      id: id,
      kind: kind,
      payload: payload,
    );
    await _refreshQueue();
    _emit();
    unawaited(synchronize());
  }

  Future<RecordData> _save(String table, RecordData data, bool creating) async {
    final id = data['id'] as String;
    final values = {
      ...data,
      if (creating) 'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _enqueue(table, id, creating ? 'create' : 'update', values);
    return (await store.rows(table)).firstWhere((row) => row['id'] == id);
  }

  @override
  Future<RecordData> prepareDeletion(String table, String id) async {
    if (table == 'clients') return {};
    if (!['orders', 'sales'].contains(table)) throw ArgumentError(table);
    await synchronize();
    _checkAccess();
    if (!online || pendingCount > 0) {
      throw DataValidationException(
        'Para eliminar una venta o un pedido, conecta internet y sincroniza primero los cambios pendientes.',
      );
    }
    return gateway
        .deletionPreview(table, id)
        .timeout(const Duration(seconds: 12));
  }

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
      final expected = preview?['fingerprint'];
      if (expected is! Map) {
        throw DataValidationException(
          'Actualiza y vuelve a confirmar la eliminación.',
        );
      }
      await _enqueue(table, id, 'delete_tree', {
        '_expected': expected,
        'description': preview?['summary']?['name'] ?? '',
      });
      return;
    }
    if ((await store.rows('orders')).any((o) => o['client_id'] == id)) {
      throw DataValidationException(
        'El cliente tiene pedidos registrados. Conserva sus datos para el historial.',
      );
    }
    await _enqueue(table, id, 'delete', {});
  }

  @override
  Future<List<RecordData>> clients() async {
    final rows = await store.rows('clients');
    for (final row in rows) {
      row.putIfAbsent('phone', () => '');
      row.putIfAbsent('address', () => '');
      row.putIfAbsent('reference', () => '');
      row.putIfAbsent('notes', () => '');
    }
    rows.sort(
      (a, b) => (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      ),
    );
    return rows;
  }

  @override
  Future<RecordData> saveClient(RecordData data, {required bool creating}) =>
      _save('clients', data, creating);
  @override
  Future<List<RecordData>> sales({int offset = 0}) async {
    final rows = await store.rows('sales');
    rows.sort((a, b) {
      final order = (b['sale_date'] as String).compareTo(
        a['sale_date'] as String,
      );
      return order == 0
          ? (a['id'] as String).compareTo(b['id'] as String)
          : order;
    });
    return rows.skip(offset).take(20).toList();
  }

  @override
  Future<RecordData> saveSale(RecordData data, {required bool creating}) =>
      _save('sales', data, creating);
  @override
  Future<RecordData> sale(String id) async =>
      (await store.rows('sales')).firstWhere((row) => row['id'] == id);

  Future<List<RecordData>> _orders() async {
    final data = await Future.wait([
      store.rows('orders'),
      clients(),
      store.rows('payments'),
      store.rows('sales'),
    ]);
    final clientMap = {for (final client in data[1]) client['id']: client};
    final saleIds = data[3].map((s) => s['id']).toSet();
    final rows = data[0]
        .where((o) => saleIds.contains(o['sale_id']))
        .map(
          (row) => <String, dynamic>{
            'delivered': false,
            'high_priority': false,
            'notes': '',
            ...row,
            'total_cents':
                (row['pork_quantity'] as int) *
                    (row['pork_price_cents'] as int) +
                (row['chicken_quantity'] as int) *
                    (row['chicken_price_cents'] as int),
            'clients': clientMap[row['client_id']] ?? {'name': 'Cliente'},
            'payments': data[2]
                .where((p) => p['order_id'] == row['id'])
                .toList(),
          },
        )
        .toList();
    rows.sort(
      (a, b) => (a['created_at'] as String? ?? '').compareTo(
        b['created_at'] as String? ?? '',
      ),
    );
    return rows;
  }

  @override
  Future<List<RecordData>> orders(String saleId) async =>
      (await _orders()).where((row) => row['sale_id'] == saleId).toList();
  @override
  Future<RecordData> order(String id) async =>
      (await _orders()).firstWhere((row) => row['id'] == id);
  @override
  Future<RecordData> saveOrder(
    RecordData data, {
    required bool creating,
  }) async {
    if (!creating) {
      final current = await order(data['id'] as String);
      final total =
          (data['pork_quantity'] as int) * (data['pork_price_cents'] as int) +
          (data['chicken_quantity'] as int) *
              (data['chicken_price_cents'] as int);
      if (total < paidFor(current)) {
        throw DataValidationException(
          'El total no puede ser menor que lo ya cobrado en este teléfono.',
        );
      }
    }
    await _save('orders', data, creating);
    return order(data['id'] as String);
  }

  @override
  Future<void> deliver(String id, bool value) =>
      _enqueue('orders', id, 'delivery', {'delivered': value});
  @override
  Future<List<RecordData>> expenses(String saleId) async {
    final rows = (await store.rows(
      'expenses',
    )).where((row) => row['sale_id'] == saleId).toList();
    rows.sort(
      (a, b) => (b['spent_on'] as String).compareTo(a['spent_on'] as String),
    );
    return rows;
  }

  @override
  Future<RecordData> saveExpense(RecordData data, {required bool creating}) =>
      _save('expenses', data, creating);
  @override
  Future<void> deleteExpense(String id) =>
      _enqueue('expenses', id, 'delete', {});
  @override
  Future<void> deletePayment(String id) =>
      _enqueue('payments', id, 'delete', {});
  @override
  Future<void> recordPayment(RecordData data, {required bool settle}) async {
    if ((await store.rows('payments')).any((p) => p['id'] == data['id'])) {
      return;
    }
    final target = await order(data['order_id'] as String);
    final balance = balanceFor(target);
    final amount = settle ? balance : data['amount_cents'] as int;
    if (amount <= 0 || amount > balance) {
      throw DataValidationException(
        'El importe debe ser mayor que cero y no superar el saldo guardado en este teléfono.',
      );
    }
    await _enqueue('payments', data['id'] as String, 'payment', {
      ...data,
      'amount_cents': amount,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, mutationId: data['id'] as String);
  }

  @override
  Future<List<RecordData>> pending({int offset = 0}) async {
    final sales = {for (final row in await store.rows('sales')) row['id']: row};
    return (await _orders())
        .where((o) => balanceFor(o) > 0)
        .skip(offset)
        .take(50)
        .map(
          (o) => <String, dynamic>{
            'order_id': o['id'],
            'sale_id': o['sale_id'],
            'client_name': (o['clients'] as Map)['name'],
            'sale_date': sales[o['sale_id']]!['sale_date'],
            'currency': sales[o['sale_id']]!['currency'],
            'balance_cents': balanceFor(o),
            'delivered': o['delivered'],
          },
        )
        .toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    unawaited(_connection?.cancel());
    super.dispose();
  }
}
