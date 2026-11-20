import 'package:app_tamales/data/sales_repository.dart';
import 'package:app_tamales/data/finances.dart';
import 'package:app_tamales/screens/sales_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySales extends SalesRepository {
  final savedSales = <RecordData>[];
  final savedOrders = <RecordData>[];
  final attemptedIds = <String>[];
  bool failNextSale = false;
  bool loseNextPaymentResponse = false;
  final savedExpenses = <RecordData>[];

  @override
  Future<List<RecordData>> sales({int offset = 0}) async =>
      savedSales.skip(offset).take(20).toList();
  @override
  Future<RecordData> saveSale(RecordData data, {required bool creating}) async {
    attemptedIds.add(data['id'] as String);
    if (failNextSale) {
      failNextSale = false;
      throw Exception('Network timeout');
    }
    savedSales.removeWhere((sale) => sale['id'] == data['id']);
    savedSales.add({...data});
    return data;
  }

  @override
  Future<List<RecordData>> orders(String saleId) async =>
      savedOrders.where((o) => o['sale_id'] == saleId).toList();
  @override
  Future<List<RecordData>> clients() async => [
    {
      'id': 'ana',
      'name': 'Ana',
      'phone': 'TELEFONO_DE_EJEMPLO',
      'address': 'Calle Uno',
      'reference': 'Puerta verde',
      'latitude': null,
      'longitude': null,
    },
  ];
  @override
  Future<RecordData> saveOrder(
    RecordData data, {
    required bool creating,
  }) async {
    final row = {
      ...data,
      'clients': {'name': 'Ana', 'phone': 'TELEFONO_DE_EJEMPLO'},
      'delivered': false,
      'total_cents':
          (data['pork_quantity'] as int) * (data['pork_price_cents'] as int) +
          (data['chicken_quantity'] as int) *
              (data['chicken_price_cents'] as int),
    };
    savedOrders.add(row);
    return row;
  }

  @override
  Future<void> deliver(String id, bool value) async {
    savedOrders.firstWhere((o) => o['id'] == id)['delivered'] = value;
  }

  @override
  Future<RecordData> order(String id) async =>
      savedOrders.firstWhere((o) => o['id'] == id);
  @override
  Future<List<RecordData>> expenses(String saleId) async =>
      savedExpenses.where((e) => e['sale_id'] == saleId).toList();
  @override
  Future<RecordData> saveExpense(
    RecordData data, {
    required bool creating,
  }) async {
    savedExpenses.removeWhere((e) => e['id'] == data['id']);
    savedExpenses.add({...data});
    return data;
  }

  @override
  Future<void> deleteExpense(String id) async {
    savedExpenses.removeWhere((e) => e['id'] == id);
  }

  @override
  Future<void> recordPayment(RecordData data, {required bool settle}) async {
    final target = savedOrders.firstWhere((o) => o['id'] == data['order_id']);
    final payments =
        target.putIfAbsent('payments', () => <RecordData>[]) as List;
    if (payments.any((p) => p['id'] == data['id'])) return;
    final amount = settle ? balanceFor(target) : data['amount_cents'] as int;
    if (amount <= 0 || amount > balanceFor(target)) {
      throw StateError('Invalid amount');
    }
    payments.add({...data, 'amount_cents': amount});
    if (loseNextPaymentResponse) {
      loseNextPaymentResponse = false;
      throw Exception('Response lost after commit');
    }
  }

  @override
  Future<void> deletePayment(String id) async {
    for (final order in savedOrders) {
      (order['payments'] as List?)?.removeWhere((p) => p['id'] == id);
    }
  }

  @override
  Future<List<RecordData>> pending({int offset = 0}) async => savedOrders
      .where((o) => balanceFor(o) > 0)
      .skip(offset)
      .take(50)
      .map((o) {
        final sale = savedSales.firstWhere((s) => s['id'] == o['sale_id']);
        return <String, dynamic>{
          'order_id': o['id'],
          'sale_id': o['sale_id'],
          'client_name': (o['clients'] as Map)['name'],
          'sale_date': sale['sale_date'],
          'currency': sale['currency'],
          'total_cents': o['total_cents'],
          'paid_cents': paidFor(o),
          'balance_cents': balanceFor(o),
          'delivered': o['delivered'],
        };
      })
      .toList();
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> tapVisible(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  for (
    var attempt = 0;
    attempt < 20 && find.text(text).hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    final target = find.text(text);
    final above =
        target.evaluate().isNotEmpty && tester.getCenter(target).dy < 100;
    await tester.drag(
      find.byType(Scrollable).last,
      Offset(0, above ? 180 : -180),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(text).hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  test('Money accepts decimal comma without floating point rounding', () {
    expect(parseCents('1,25'), 125);
    expect(parseCents('0.10'), 10);
    expect(parseCents(' 2.5 '), 250);
    for (final value in ['-1', '1.999', '', 'NaN', '1,2.3', '1e3']) {
      expect(parseCents(value), isNull, reason: value);
    }
    expect(decimalPrice(5), '0.05');
  });

  test('Sale totals separate preparation from pending delivery', () {
    final totals = SaleTotals([
      {
        'pork_quantity': 3,
        'chicken_quantity': 2,
        'total_cents': 650,
        'delivered': true,
      },
      {
        'pork_quantity': 1,
        'chicken_quantity': 4,
        'total_cents': 700,
        'delivered': false,
      },
    ]);
    expect(totals.pork, 4);
    expect(totals.chicken, 6);
    expect(totals.remainingPork, 1);
    expect(totals.remainingChicken, 4);
    expect(totals.sold, 1350);
    expect(totals.delivered, 1);
    expect(totals.count, 2);
    expect(parseQuantity('2.5'), isNull);
    expect(parseQuantity('-1'), isNull);
  });

  testWidgets('Creates a dated sale and an order from a saved client', (
    tester,
  ) async {
    final repo = MemorySales();
    await tester.pumpWidget(MaterialApp(home: SalesScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Nueva venta');
    await tester.enterText(field('Nombre de la venta (opcional)'), 'Sábado');
    await tester.enterText(field('Chancho'), '1,25');
    await tester.enterText(field('Pollo'), '1.50');
    await tapVisible(tester, 'Guardar venta');
    expect(repo.savedSales.single['pork_price_cents'], 125);
    expect(repo.savedSales.single['currency'], 'USD');
    expect(find.text('Resumen de la venta'), findsOneWidget);
    await tapVisible(tester, 'Agregar pedido');
    await tapVisible(tester, 'Seleccionar cliente');
    await tapVisible(tester, 'Ana');
    await tester.enterText(field('Cantidad').at(0), '2');
    await tester.enterText(field('Cantidad').at(1), '3');
    await tester.pumpAndSettle();
    expect(find.text('Total: USD 7.00'), findsOneWidget);
    await tapVisible(tester, 'Guardar pedido');
    expect(repo.savedOrders.single['client_id'], 'ana');
    expect(repo.savedOrders.single['delivery_address'], 'Calle Uno');
    expect(repo.savedOrders.single['sale_id'], repo.savedSales.single['id']);
    expect(find.text('Total vendido: USD 7.00'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar venta'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Chancho'), '2');
    await tester.enterText(field('Pollo'), '2');
    await tapVisible(tester, 'Guardar venta');
    expect(find.text('Total vendido: USD 7.00'), findsOneWidget);
    expect(repo.savedOrders.single['pork_price_cents'], 125);
    expect(repo.savedOrders.single['chicken_price_cents'], 150);
    await tapVisible(tester, 'Entregado');
    expect(repo.savedOrders.single['delivered'], true);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1400));
    await tester.pumpAndSettle();
    expect(
      find.text('Por entregar: 0 de chancho · 0 de pollo'),
      findsOneWidget,
    );
    expect(find.text('Total vendido: USD 7.00'), findsOneWidget);
  });

  testWidgets('Retry keeps the sale identifier after a connection failure', (
    tester,
  ) async {
    final repo = MemorySales()..failNextSale = true;
    await tester.pumpWidget(MaterialApp(home: SalesScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Nueva venta');
    await tester.enterText(field('Chancho'), '1');
    await tester.enterText(field('Pollo'), '1');
    await tapVisible(tester, 'Guardar venta');
    expect(
      find.textContaining('No se pudo confirmar el guardado'),
      findsOneWidget,
    );
    await tapVisible(tester, 'Guardar venta');
    expect(repo.attemptedIds.length, 2);
    expect(repo.attemptedIds.toSet().length, 1);
    expect(repo.savedSales.length, 1);
  });
}
