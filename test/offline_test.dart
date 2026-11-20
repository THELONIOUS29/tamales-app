import 'dart:convert';
import 'dart:io';

import 'package:app_tamales/data/finances.dart';
import 'package:app_tamales/data/local_store.dart';
import 'package:app_tamales/data/offline_repository.dart';
import 'package:app_tamales/data/sales_repository.dart';
import 'package:app_tamales/data/sync_gateway.dart';
import 'package:app_tamales/screens/clients_screen.dart';
import 'package:app_tamales/screens/payments_screen.dart';
import 'package:app_tamales/screens/sync_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'sales_test.dart' show field, tapVisible;

RecordData copy(RecordData data) => jsonDecode(jsonEncode(data)) as RecordData;

class FakeGateway extends SyncGateway {
  bool available = true,
      losePaymentResponse = false,
      loseDeleteResponse = false;
  String? owner = 'business';
  final tables = <String, Map<String, RecordData>>{
    for (final name in syncTables) name: <String, RecordData>{},
  };
  final events = <RecordData>[];
  final sent = <String>[];
  void check() {
    if (!available) throw const SocketException('offline');
  }

  RecordData write(String table, RecordData row) {
    final stored = {...row, 'updated_at': 'version-${events.length + 1}'};
    tables[table]![row['id'] as String] = stored;
    events.add({
      'sequence': events.length + 1,
      'table_name': table,
      'record_id': row['id'],
      'record_data': copy(stored),
    });
    return copy(stored);
  }

  void remove(String table, String id) {
    tables[table]!.remove(id);
    events.add({
      'sequence': events.length + 1,
      'table_name': table,
      'record_id': id,
      'record_data': null,
    });
  }

  @override
  Future<String?> authorizedOwner() async {
    check();
    return owner;
  }

  @override
  Future<RecordData> bootstrap() async {
    check();
    return copy({
      'cursor': events.length,
      'tables': {
        for (final table in syncTables) table: tables[table]!.values.toList(),
      },
    });
  }

  @override
  Future<List<RecordData>> changes(int after) async {
    check();
    return events
        .where((e) => (e['sequence'] as int) > after)
        .map(copy)
        .toList();
  }

  @override
  Future<RecordData> deletionPreview(String table, String id) async {
    check();
    final root = tables[table]![id]!;
    final orders = tables['orders']!.values
        .where((o) => table == 'sales' ? o['sale_id'] == id : o['id'] == id)
        .toList();
    final ids = orders.map((o) => o['id']).toSet();
    final payments = tables['payments']!.values
        .where((p) => ids.contains(p['order_id']))
        .toList();
    final expenses = tables['expenses']!.values
        .where((e) => table == 'sales' && e['sale_id'] == id)
        .toList();
    List<RecordData> versions(List<RecordData> rows) =>
        rows
            .map(
              (r) => <String, dynamic>{
                'id': r['id'],
                'updated_at': r['updated_at'],
              },
            )
            .toList()
          ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return {
      'fingerprint': {
        'root': {'id': id, 'updated_at': root['updated_at']},
        'orders': versions(orders),
        'payments': versions(payments),
        'expenses': versions(expenses),
      },
      'summary': {
        'name': 'Prueba',
        'currency': 'USD',
        'orders': orders.length,
        'payments': payments.length,
        'expenses': expenses.length,
        'sold_cents': orders.fold<int>(
          0,
          (s, o) => s + (o['total_cents'] as int),
        ),
        'paid_cents': payments.fold<int>(
          0,
          (s, p) => s + (p['amount_cents'] as int),
        ),
        'spent_cents': expenses.fold<int>(
          0,
          (s, e) => s + (e['amount_cents'] as int),
        ),
      },
    };
  }

  @override
  Future<RecordData?> push(LocalMutation mutation) async {
    check();
    sent.add('${mutation.table}:${mutation.kind}');
    final table = tables[mutation.table]!;
    final current = table[mutation.recordId];
    if (mutation.kind == 'delete_tree') {
      if (current == null) return null;
      final preview = await deletionPreview(mutation.table, mutation.recordId);
      if (jsonEncode(preview['fingerprint']) !=
          jsonEncode(mutation.payload['_expected'])) {
        throw SyncConflict('El registro cambió después de confirmar.');
      }
      final graph = mutation.payload['_expected'] as Map;
      for (final target in ['payments', 'expenses', 'orders']) {
        for (final row in graph[target] as List) {
          remove(target, (row as Map)['id'] as String);
        }
      }
      if (mutation.table == 'sales') remove('sales', mutation.recordId);
      if (loseDeleteResponse) {
        loseDeleteResponse = false;
        throw const SocketException('Delete response lost');
      }
      return null;
    }
    if (mutation.kind == 'payment') {
      if (current != null) return copy(current);
      final order = tables['orders']![mutation.payload['order_id']]!;
      final paid = tables['payments']!.values
          .where((p) => p['order_id'] == order['id'])
          .fold<int>(0, (sum, p) => sum + (p['amount_cents'] as int));
      if ((mutation.payload['amount_cents'] as int) + paid >
          (order['total_cents'] as int)) {
        throw SyncConflict('El importe supera el saldo actual.');
      }
      final row = write('payments', {
        'id': mutation.recordId,
        ...mutation.payload,
      });
      if (losePaymentResponse) {
        losePaymentResponse = false;
        throw const SocketException('Response lost after commit');
      }
      return row;
    }
    if (mutation.kind == 'create') {
      if (current != null) return copy(current);
    } else if (current?['updated_at'] != mutation.baseVersion) {
      throw SyncConflict('Otro teléfono modificó el registro.');
    }
    if (mutation.kind == 'delete') {
      remove(mutation.table, mutation.recordId);
      return null;
    }
    final row = {...?current, ...mutation.payload, 'id': mutation.recordId};
    if (mutation.table == 'orders') {
      row['total_cents'] =
          (row['pork_quantity'] as int) * (row['pork_price_cents'] as int) +
          (row['chicken_quantity'] as int) *
              (row['chicken_price_cents'] as int);
    }
    return write(mutation.table, row);
  }
}

void main() {
  late Directory temp;
  late LocalStore store;
  late OfflineRepository repo;
  late FakeGateway server;
  late String file;

  Future<void> connect() async {
    repo.setConnectivity(true);
    await repo.idle;
  }

  Future<void> seedLocalOrder() async {
    await repo.saveClient({
      'id': 'client',
      'name': 'Ana',
      'phone': '',
      'address': '',
      'reference': '',
      'notes': '',
    }, creating: true);
    await repo.saveSale({
      'id': 'sale',
      'title': 'Sábado',
      'sale_date': '2026-10-24',
      'currency': 'USD',
      'pork_price_cents': 100,
      'chicken_price_cents': 100,
    }, creating: true);
    await repo.saveOrder({
      'id': 'order',
      'sale_id': 'sale',
      'client_id': 'client',
      'pork_quantity': 10,
      'chicken_quantity': 0,
      'pork_price_cents': 100,
      'chicken_price_cents': 100,
      'notes': '',
    }, creating: true);
  }

  Future<void> reopen() async {
    repo.dispose();
    await store.close();
    store = LocalStore(
      await databaseFactoryFfiNoIsolate.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: LocalStore.createSchema,
        ),
      ),
    );
    repo = OfflineRepository(
      ownerId: 'business',
      store: store,
      gateway: server,
    );
    repo.setConnectivity(false);
    await repo.initialize();
  }

  setUpAll(() {
    sqfliteFfiInit();
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tamales-offline-');
    file = '${temp.path}/local.sqlite';
    store = LocalStore(
      await databaseFactoryFfiNoIsolate.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: LocalStore.createSchema,
        ),
      ),
    );
    server = FakeGateway();
    repo = OfflineRepository(
      ownerId: 'business',
      store: store,
      gateway: server,
    );
    repo.setConnectivity(false);
    await repo.initialize();
  });
  tearDown(() async {
    await repo.idle;
    repo.dispose();
    await store.close();
    await temp.delete(recursive: true);
  });

  test(
    'Offline clients, sale, order and expense survive reopening and synchronize in dependency order',
    () async {
      await seedLocalOrder();
      await repo.saveExpense({
        'id': 'expense',
        'sale_id': 'sale',
        'amount_cents': 300,
        'description': 'Hojas',
        'spent_on': '2026-10-22',
      }, creating: true);
      await reopen();
      expect((await repo.clients()).single['name'], 'Ana');
      expect((await repo.sales()).single['title'], 'Sábado');
      expect((await repo.order('order'))['total_cents'], 1000);
      expect((await repo.expenses('sale')).single['amount_cents'], 300);
      expect(repo.pendingCount, 4);
      await connect();
      expect(repo.pendingCount, 0);
      expect(server.sent, [
        'clients:create',
        'sales:create',
        'orders:create',
        'expenses:create',
      ]);
      expect(server.tables['orders']!.length, 1);
    },
  );

  test(
    'A cash payment with a lost response is retried after restart exactly once',
    () async {
      await seedLocalOrder();
      await connect();
      repo.setConnectivity(false);
      await repo.recordPayment({
        'id': 'payment',
        'order_id': 'order',
        'amount_cents': 400,
        'paid_at': '2026-10-22T15:00:00Z',
        'method': 'cash',
        'notes': '',
      }, settle: false);
      expect(balanceFor(await repo.order('order')), 600);
      server.losePaymentResponse = true;
      await connect();
      expect(repo.pendingCount, 1);
      expect(server.tables['payments']!.length, 1);
      await reopen();
      await connect();
      expect(repo.pendingCount, 0);
      expect(server.tables['payments']!.length, 1);
      expect(balanceFor(await repo.order('order')), 600);
    },
  );

  test(
    'A stale offline payment is kept for review without replacing a server payment',
    () async {
      await seedLocalOrder();
      await connect();
      repo.setConnectivity(false);
      await repo.recordPayment({
        'id': 'local-pay',
        'order_id': 'order',
        'amount_cents': 700,
        'paid_at': '2026-10-22T15:00:00Z',
        'method': 'cash',
        'notes': '',
      }, settle: false);
      server.write('payments', {
        'id': 'other-pay',
        'order_id': 'order',
        'amount_cents': 400,
        'paid_at': '2026-10-22T14:00:00Z',
        'method': 'cash',
        'notes': '',
      });
      await connect();
      expect(repo.conflicts.length, 1);
      expect(server.tables['payments']!.containsKey('local-pay'), false);
      expect(paymentStatus(await repo.order('order')), 'Cobro por revisar');
      expect(balanceFor(await repo.order('order')), 600);
      await reopen();
      expect(repo.conflicts.length, 1);
      await repo.discard(repo.conflicts.single);
      await repo.idle;
      expect(balanceFor(await repo.order('order')), 600);
      expect(server.tables['payments']!.length, 1);
    },
  );

  test(
    'Remote deletion propagates incrementally, local deletion survives restart, and updated versions chain',
    () async {
      await seedLocalOrder();
      await connect();
      repo.setConnectivity(false);
      await repo.saveExpense({
        'id': 'expense',
        'sale_id': 'sale',
        'amount_cents': 300,
        'description': 'Hojas',
        'spent_on': '2026-10-22',
      }, creating: true);
      await connect();
      repo.setConnectivity(false);
      await repo.saveClient({
        'id': 'client',
        'name': 'Ana Uno',
        'phone': '',
        'address': '',
        'reference': '',
        'notes': '',
      }, creating: false);
      await repo.saveClient({
        'id': 'client',
        'name': 'Ana Dos',
        'phone': '',
        'address': '',
        'reference': '',
        'notes': '',
      }, creating: false);
      await repo.deleteExpense('expense');
      await reopen();
      await connect();
      expect(repo.conflicts, isEmpty);
      expect(server.tables['clients']!['client']!['name'], 'Ana Dos');
      expect(server.tables['expenses'], isEmpty);
      server.write('expenses', {
        'id': 'remote',
        'sale_id': 'sale',
        'amount_cents': 100,
        'description': 'Pollo',
        'spent_on': '2026-10-22',
      });
      await connect();
      expect((await repo.expenses('sale')).length, 1);
      server.remove('expenses', 'remote');
      await connect();
      expect(await repo.expenses('sale'), isEmpty);
    },
  );

  test(
    'A conflicting edit does not overwrite another phone and a revoked device cannot write',
    () async {
      await seedLocalOrder();
      await connect();
      repo.setConnectivity(false);
      await repo.saveClient({
        'id': 'client',
        'name': 'Local',
        'phone': '',
        'address': '',
        'reference': '',
        'notes': '',
      }, creating: false);
      server.write('clients', {
        ...server.tables['clients']!['client']!,
        'name': 'Remoto',
      });
      await connect();
      expect(repo.conflicts.length, 1);
      expect(server.tables['clients']!['client']!['name'], 'Remoto');
      server.owner = null;
      await connect();
      expect(repo.revoked, true);
      await reopen();
      expect(repo.revoked, true);
      expect(
        () => repo.saveSale({'id': 'blocked'}, creating: true),
        throwsA(isA<DataValidationException>()),
      );
    },
  );
  testWidgets('Client screen saves into SQLite without an internet request', (
    tester,
  ) async {
    server.available = false;
    await tester.pumpWidget(MaterialApp(home: ClientsScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Nuevo cliente');
    await tester.enterText(field('Nombre'), 'Cliente sin internet');
    await tapVisible(tester, 'Guardar cliente');
    expect(find.text('Cliente sin internet'), findsOneWidget);
    expect(repo.pendingCount, 1);
    expect(server.sent, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Offline cash entry is visible but explicitly pending synchronization',
    (tester) async {
      await seedLocalOrder();
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentsScreen(
            repository: repo,
            orderId: 'order',
            currency: 'USD',
            clientName: 'Ana',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Registrar abono');
      await tester.enterText(field('Importe recibido (USD)'), '4');
      await tapVisible(tester, 'Confirmar cobro');
      expect(find.text('Cobro pendiente de sincronizar'), findsOneWidget);
      expect(find.text('Saldo pendiente: USD 6.00'), findsOneWidget);
      expect(repo.pendingCount, 4);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Connection banner retains the open form and hides it on revocation',
    (tester) async {
      activeOfflineRepository.value = repo;
      addTearDown(() {
        activeOfflineRepository.value = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: appNavigatorKey,
          builder: (context, child) => SyncFrame(child: child!),
          home: ClientsScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Nuevo cliente');
      await tester.enterText(field('Nombre'), 'Borrador conservado');
      repo.revoked = true;
      repo.setConnectivity(false);
      await tester.pumpAndSettle();
      expect(find.text('Borrador conservado'), findsNothing);
      expect(
        find.textContaining('necesita autorización de nuevo'),
        findsOneWidget,
      );
      repo.revoked = false;
      repo.setConnectivity(false);
      await tester.pumpAndSettle();
      expect(find.text('Borrador conservado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'Paid order deletion is atomic in the queue and keeps client, sale and expenses',
    () async {
      await seedLocalOrder();
      await connect();
      await repo.recordPayment({
        'id': 'cash',
        'order_id': 'order',
        'amount_cents': 1000,
        'paid_at': '2026-10-22T12:00:00Z',
        'method': 'cash',
        'notes': '',
      }, settle: false);
      await repo.saveExpense({
        'id': 'expense',
        'sale_id': 'sale',
        'amount_cents': 200,
        'description': 'Preparación',
        'spent_on': '2026-10-22',
      }, creating: true);
      await repo.idle;
      final preview = await repo.prepareDeletion('orders', 'order');
      expect(preview['summary']['paid_cents'], 1000);
      repo.setConnectivity(false);
      await repo.deleteRecord('orders', 'order', preview: preview);
      expect(await repo.orders('sale'), isEmpty);
      expect(await store.rows('payments'), isEmpty);
      expect(await repo.expenses('sale'), hasLength(1));
      expect(await repo.clients(), hasLength(1));
      await reopen();
      expect(await repo.orders('sale'), isEmpty);
      await connect();
      expect(server.tables['orders'], isEmpty);
      expect(server.tables['payments'], isEmpty);
      expect(server.tables['sales'], hasLength(1));
      expect(server.tables['expenses'], hasLength(1));
      expect(await store.rows('payments'), isEmpty);
    },
  );

  test(
    'Complete sale deletion retries safely after lost response and retains clients',
    () async {
      await seedLocalOrder();
      await connect();
      await repo.recordPayment({
        'id': 'cash',
        'order_id': 'order',
        'amount_cents': 1000,
        'paid_at': '2026-10-22T12:00:00Z',
        'method': 'cash',
        'notes': '',
      }, settle: false);
      await repo.saveExpense({
        'id': 'expense',
        'sale_id': 'sale',
        'amount_cents': 200,
        'description': 'Compra',
        'spent_on': '2026-10-22',
      }, creating: true);
      await repo.idle;
      final preview = await repo.prepareDeletion('sales', 'sale');
      server.loseDeleteResponse = true;
      await repo.deleteRecord('sales', 'sale', preview: preview);
      await repo.idle;
      expect(repo.pendingCount, 1);
      for (final table in ['sales', 'orders', 'payments', 'expenses']) {
        expect(await store.rows(table), isEmpty);
      }
      expect(await repo.clients(), hasLength(1));
      final events = server.events.length;
      repo.setConnectivity(false);
      await reopen();
      await connect();
      expect(repo.pendingCount, 0);
      expect(server.events.length, events);
      expect(await repo.clients(), hasLength(1));
    },
  );

  test(
    'A collection received after deletion confirmation cancels the entire deletion',
    () async {
      await seedLocalOrder();
      await connect();
      final preview = await repo.prepareDeletion('sales', 'sale');
      server.write('payments', {
        'id': 'new-cash',
        'order_id': 'order',
        'amount_cents': 200,
        'paid_at': '2026-10-22T12:00:00Z',
        'method': 'cash',
        'notes': '',
      });
      await repo.deleteRecord('sales', 'sale', preview: preview);
      await repo.idle;
      expect(repo.conflicts, hasLength(1));
      expect(server.tables['sales'], hasLength(1));
      expect(server.tables['orders'], hasLength(1));
      expect(server.tables['payments'], hasLength(1));
      await repo.discard(repo.conflicts.single);
      await repo.idle;
      expect((await repo.orders('sale')).single['payments'], hasLength(1));
      expect(await repo.sales(), hasLength(1));
    },
  );

  test(
    'Destructive preview requires connectivity and an empty pending queue',
    () async {
      await seedLocalOrder();
      expect(
        repo.prepareDeletion('sales', 'sale'),
        throwsA(isA<DataValidationException>()),
      );
    },
  );
  test(
    'Dashboard snapshot includes pending writes and hides complete deletions consistently',
    () async {
      await seedLocalOrder();
      final offline = await repo.dashboardSnapshot();
      expect(offline['sales'], hasLength(1));
      expect(offline['orders'], hasLength(1));
      expect(offline['clients']!.single['_sync_pending'], true);
      await connect();
      final preview = await repo.prepareDeletion('sales', 'sale');
      repo.setConnectivity(false);
      await repo.deleteRecord('sales', 'sale', preview: preview);
      final snapshot = await repo.dashboardSnapshot();
      for (final table in ['sales', 'orders', 'payments', 'expenses']) {
        expect(snapshot[table], isEmpty);
      }
      expect(snapshot['clients'], hasLength(1));
      for (final table in syncTables) {
        expect(snapshot[table], await store.rows(table));
      }
    },
  );
}
