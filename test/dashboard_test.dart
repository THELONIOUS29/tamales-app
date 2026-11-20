import 'package:app_tamales/data/dashboard.dart';
import 'package:app_tamales/data/sales_repository.dart';
import 'package:app_tamales/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sales_test.dart' show MemorySales, tapVisible;

RecordData sale(String id, String date, {String currency = 'USD'}) => {
  'id': id,
  'sale_date': date,
  'currency': currency,
  'title': 'Venta $id',
  'pork_price_cents': 100,
  'chicken_price_cents': 150,
};
RecordData order(
  String id,
  String saleId, {
  int pork = 0,
  int chicken = 0,
  int porkPrice = 100,
  bool delivered = false,
  bool priority = false,
  String client = 'client',
}) => {
  'id': id,
  'sale_id': saleId,
  'client_id': client,
  'pork_quantity': pork,
  'chicken_quantity': chicken,
  'pork_price_cents': porkPrice,
  'chicken_price_cents': 150,
  'delivered': delivered,
  'high_priority': priority,
  'total_cents': 999999,
};
Map<String, List<RecordData>> fixtures() => {
  'sales': [
    sale('a', '2026-10-22'),
    sale('b', '2026-10-22'),
    sale('eur', '2026-10-22', currency: 'EUR'),
    sale('old', '2026-10-21'),
    sale('next', '2026-10-23'),
  ],
  'clients': [],
  'orders': [
    order('a1', 'a', pork: 5, delivered: true),
    order('b1', 'b', chicken: 3, priority: true),
    order('eur1', 'eur', pork: 2, porkPrice: 200, client: 'euro-client'),
    order('old1', 'old', pork: 3, delivered: true),
    order('next1', 'next', pork: 1),
    order('orphan', 'deleted-sale', pork: 100),
  ],
  'payments': [
    {
      'id': 'cash',
      'order_id': 'a1',
      'amount_cents': 200,
      'paid_at': '2026-10-24T10:00:00Z',
    },
    {
      'id': 'rejected',
      'order_id': 'a1',
      'amount_cents': 50,
      '_sync_error': 'rechazado',
    },
    {'id': 'next-cash', 'order_id': 'next1', 'amount_cents': 100},
  ],
  'expenses': [
    {'id': 'e1', 'sale_id': 'a', 'amount_cents': 100, 'spent_on': '2026-10-20'},
    {'id': 'e2', 'sale_id': 'b', 'amount_cents': 250, 'spent_on': '2026-10-22'},
    {'id': 'orphan', 'sale_id': 'deleted-sale', 'amount_cents': 999999},
    {'id': 'future', 'sale_id': 'next', 'amount_cents': 50},
  ],
};

class DashboardRepository extends MemorySales with ChangeNotifier {
  DashboardRepository(this.data);
  final Map<String, List<RecordData>> data;
  int reads = 0;
  @override
  Future<Map<String, List<RecordData>>> dashboardSnapshot() async {
    reads++;
    return data;
  }

  void changed() => notifyListeners();
}

void main() {
  test(
    'Summary combines every sale on the date and keeps currencies separate',
    () {
      final d = DashboardData(fixtures(), '2026-10-22');
      expect(d.selected, hasLength(3));
      expect(d.clientCount, 2);
      expect(d.quantities.pork, 7);
      expect(d.quantities.chicken, 3);
      expect(d.quantities.remainingPork, 2);
      expect(d.quantities.remainingChicken, 3);
      expect(d.quantities.delivered, 1);
      expect(d.highPriority, 1);
      final usd = d.finances['USD']!;
      expect(usd.sold, 950);
      expect(usd.paid, 200);
      expect(usd.pending, 750);
      expect(usd.spent, 350);
      expect(usd.result, 600);
      expect(usd.cashBalance, -150);
      expect(d.finances['EUR']!.sold, 400);
      expect(d.previousPending.single.sale['id'], 'old');
      expect(d.upcoming.single.sale['id'], 'next');
    },
  );
  test(
    'A delivered but unpaid previous sale remains accessible; orphan rows are ignored',
    () {
      final d = DashboardData(fixtures(), '2026-10-23');
      expect(d.quantities.pork, 1);
      expect(d.finances['USD']!.sold, 100);
      expect(d.finances['USD']!.paid, 100);
      expect(d.finances['USD']!.spent, 50);
      expect(d.previousPending.map((s) => s.sale['id']), contains('old'));
      expect(
        d.previousPending.map((s) => s.sale['id']),
        isNot(contains('deleted-sale')),
      );
    },
  );
  test(
    'All 25 sales on a date are included, independent of the sales list page size',
    () {
      final d = DashboardData({
        'sales': [for (var i = 0; i < 25; i++) sale('$i', '2026-10-22')],
        'orders': [for (var i = 0; i < 25; i++) order('o$i', '$i', pork: 1)],
      }, '2026-10-22');
      expect(d.selected, hasLength(25));
      expect(d.finances['USD']!.sold, 2500);
      expect(d.quantities.pork, 25);
    },
  );
  testWidgets(
    'Inicio shows next scheduled date when today has no sales and allows returning to today',
    (tester) async {
      final repo = DashboardRepository({
        'sales': [sale('tomorrow', '2026-10-23')],
        'orders': [order('a', 'tomorrow', pork: 5)],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            repository: repo,
            now: () => DateTime(2026, 10, 22),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inicio'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sin ventas en esta fecha'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Sin ventas en esta fecha'), findsOneWidget);
      await tapVisible(tester, 'Próxima: 23/10/2026');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quantity-Chancho')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('quantity-Chancho')))
            .data,
        '5',
      );
      await tester.scrollUntilVisible(
        find.text('Hoy'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Hoy'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Sin ventas en esta fecha'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Sin ventas en esta fecha'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets(
    'Summary updates when a payment changes without opening a global collections screen',
    (tester) async {
      final data = {
        'sales': [sale('a', '2026-10-22')],
        'orders': [order('a1', 'a', pork: 5)],
        'payments': <RecordData>[],
      };
      final repo = DashboardRepository(data);
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            repository: repo,
            now: () => DateTime(2026, 10, 22),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('money-Cobrado-USD')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('money-Cobrado-USD')), findsOneWidget);
      data['payments']!.add({
        'id': 'payment',
        'order_id': 'a1',
        'amount_cents': 200,
      });
      repo.changed();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('money-Cobrado-USD')))
            .data,
        'USD 2.00',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('money-Por cobrar-USD')))
            .data,
        'USD 3.00',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets('Inicio follows the new local day after returning to the app', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 22, 23, 59);
    final repo = DashboardRepository({
      'sales': [sale('a', '2026-10-22'), sale('b', '2026-10-23')],
      'orders': [order('a1', 'a', pork: 5), order('b1', 'b', pork: 1)],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(repository: repo, now: () => now),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hoy · 22/10/2026'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 10, 23, 0, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Hoy · 23/10/2026'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('quantity-Chancho')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quantity-Chancho'))).data,
      '1',
    );
    expect(find.byKey(const ValueKey('quantity-Chancho')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });
}
