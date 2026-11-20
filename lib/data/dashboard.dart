import 'finances.dart';
import 'sales_repository.dart';

class SaleOverview {
  SaleOverview(this.sale, this.orders, this.expenses);
  final RecordData sale;
  final List<RecordData> orders, expenses;
  SaleTotals get quantities => SaleTotals(orders);
  FinancialTotals get finances => FinancialTotals(orders, expenses);
  bool get hasPending =>
      orders.any((o) => o['delivered'] != true || balanceFor(o) > 0);
}

class DashboardData {
  DashboardData(Map<String, List<RecordData>> data, this.date) {
    final sales = data['sales'] ?? [];
    final payments = <Object?, List<RecordData>>{};
    for (final p in data['payments'] ?? <RecordData>[]) {
      (payments[p['order_id']] ??= []).add(p);
    }
    final orders = <Object?, List<RecordData>>{};
    for (final o in data['orders'] ?? <RecordData>[]) {
      final row = <String, dynamic>{
        ...o,
        'total_cents':
            (o['pork_quantity'] as int) * (o['pork_price_cents'] as int) +
            (o['chicken_quantity'] as int) * (o['chicken_price_cents'] as int),
        'payments': payments[o['id']] ?? <RecordData>[],
      };
      (orders[o['sale_id']] ??= []).add(row);
    }
    final expenses = <Object?, List<RecordData>>{};
    for (final e in data['expenses'] ?? <RecordData>[]) {
      (expenses[e['sale_id']] ??= []).add(e);
    }
    final overviews =
        sales
            .map(
              (s) => SaleOverview(
                s,
                orders[s['id']] ?? [],
                expenses[s['id']] ?? [],
              ),
            )
            .toList()
          ..sort((a, b) {
            final d = (a.sale['sale_date'] as String).compareTo(
              b.sale['sale_date'] as String,
            );
            return d != 0
                ? d
                : (a.sale['id'] as String).compareTo(b.sale['id'] as String);
          });
    selected = overviews.where((s) => s.sale['sale_date'] == date).toList();
    upcoming = overviews
        .where((s) => (s.sale['sale_date'] as String).compareTo(date) > 0)
        .toList();
    previousPending = overviews
        .where(
          (s) =>
              (s.sale['sale_date'] as String).compareTo(date) < 0 &&
              s.hasPending,
        )
        .toList()
        .reversed
        .toList();
    final allOrders = selected.expand((s) => s.orders).toList();
    quantities = SaleTotals(allOrders);
    clientCount = allOrders.map((o) => o['client_id']).toSet().length;
    highPriority = allOrders
        .where((o) => o['delivered'] != true && o['high_priority'] == true)
        .length;
    final currencies =
        (selected.isEmpty ? overviews : selected)
            .map((s) => s.sale['currency'] as String)
            .toSet()
            .toList()
          ..sort();
    if (currencies.isEmpty) currencies.add('USD');
    for (final currency in currencies) {
      final group = selected.where((s) => s.sale['currency'] == currency);
      finances[currency] = FinancialTotals(
        group.expand((s) => s.orders),
        group.expand((s) => s.expenses),
      );
    }
  }
  final String date;
  late final List<SaleOverview> selected, upcoming, previousPending;
  late final SaleTotals quantities;
  late final int clientCount, highPriority;
  final finances = <String, FinancialTotals>{};
}
