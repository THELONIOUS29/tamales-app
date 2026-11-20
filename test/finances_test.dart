import 'package:app_tamales/data/finances.dart';
import 'package:app_tamales/data/sales_repository.dart';
import 'package:app_tamales/screens/payments_screen.dart';
import 'package:app_tamales/screens/expenses_screen.dart';
import 'package:app_tamales/screens/pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sales_test.dart' show MemorySales, field, tapVisible;

MemorySales fixture() {
  final repo = MemorySales();
  repo.savedSales.add({
    'id': 'sale',
    'sale_date': '2026-10-20',
    'currency': 'USD',
  });
  repo.savedOrders.add({
    'id': 'order',
    'sale_id': 'sale',
    'client_id': 'ana',
    'clients': {'name': 'Ana'},
    'total_cents': 1000,
    'pork_quantity': 5,
    'chicken_quantity': 0,
    'delivered': true,
    'payments': <RecordData>[],
  });
  return repo;
}

void main() {
  test(
    'Financial result separates sales, collections and expenses, including losses',
    () {
      final order = fixture().savedOrders.single;
      (order['payments'] as List).add({'amount_cents': 400});
      final totals = FinancialTotals(
        [order],
        [
          {'amount_cents': 1200},
        ],
      );
      expect(totals.sold, 1000);
      expect(totals.paid, 400);
      expect(totals.pending, 600);
      expect(totals.result, -200);
      expect(totals.cashBalance, -800);
      expect(money(-50, 'USD'), 'USD -0.50');
      expect(paymentStatus(order), 'Abono');
      order['delivered'] = false;
      expect(balanceFor(order), 600);
    },
  );

  testWidgets(
    'Records partial payment and settles remaining balance without changing delivery',
    (tester) async {
      final repo = fixture();
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
      expect(find.text('Saldo pendiente: USD 6.00'), findsOneWidget);
      expect(find.text('Abono'), findsOneWidget);
      await tapVisible(tester, 'Pagar saldo completo');
      await tapVisible(tester, 'Confirmar cobro');
      expect(find.text('Pagado'), findsOneWidget);
      expect(find.text('Saldo pendiente: USD 0.00'), findsOneWidget);
      expect(repo.savedOrders.single['delivered'], true);
      expect(paymentsOf(repo.savedOrders.single).length, 2);
      expect(paidFor(repo.savedOrders.single), 1000);
    },
  );

  testWidgets('Lost response can be retried without creating another payment', (
    tester,
  ) async {
    final repo = fixture()..loseNextPaymentResponse = true;
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
    expect(
      find.textContaining('No se pudo confirmar el cobro'),
      findsOneWidget,
    );
    await tapVisible(tester, 'Confirmar cobro');
    expect(paymentsOf(repo.savedOrders.single).length, 1);
    expect(find.text('Saldo pendiente: USD 6.00'), findsOneWidget);
  });

  testWidgets('Expense accepts description and rejects zero before saving', (
    tester,
  ) async {
    final repo = fixture();
    await tester.pumpWidget(
      MaterialApp(
        home: ExpensesScreen(repository: repo, sale: repo.savedSales.single),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, 'Nuevo gasto');
    await tester.enterText(field('Importe (USD)'), '0');
    await tapVisible(tester, 'Guardar gasto');
    expect(find.text('Ingresa un importe mayor que cero.'), findsOneWidget);
    expect(repo.savedExpenses, isEmpty);
    await tester.enterText(field('Importe (USD)'), '12,50');
    await tester.enterText(field('Descripción (opcional)'), 'Pollo y hojas');
    await tapVisible(tester, 'Guardar gasto');
    expect(repo.savedExpenses.single['amount_cents'], 1250);
    expect(repo.savedExpenses.single['sale_id'], 'sale');
    expect(find.text('Total de gastos: USD 12.50'), findsOneWidget);
    expect(find.textContaining('Pollo y hojas'), findsOneWidget);
  });

  testWidgets('Collects an old delivered debt from the pending list', (
    tester,
  ) async {
    final repo = fixture();
    await tester.pumpWidget(MaterialApp(home: PendingScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.textContaining('20/10/2026'), findsOneWidget);
    await tapVisible(tester, 'Ana');
    await tapVisible(tester, 'Pagar saldo completo');
    await tapVisible(tester, 'Confirmar cobro');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('No hay pedidos pendientes de cobro.'), findsOneWidget);
    expect(repo.savedOrders.single['sale_id'], 'sale');
    expect(repo.savedOrders.single['delivered'], true);
    expect(
      DateTime.parse(
        paymentsOf(repo.savedOrders.single).single['paid_at'] as String,
      ).year,
      DateTime.now().year,
    );
  });
}
