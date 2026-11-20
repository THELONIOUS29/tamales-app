import 'package:app_tamales/data/sales_repository.dart';
import 'package:app_tamales/screens/delete_record.dart';
import 'package:app_tamales/screens/sale_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sales_test.dart' show MemorySales, tapVisible;

class DeletionRepository extends MemorySales {
  int deletions = 0;
  @override
  Future<RecordData> prepareDeletion(String table, String id) async => {
    'fingerprint': {
      'root': {'id': id, 'updated_at': 'v1'},
      'orders': [],
      'payments': [],
      'expenses': [],
    },
    'summary': {
      'name': 'Pantera',
      'currency': 'USD',
      'orders': 1,
      'payments': 1,
      'expenses': 1,
      'sold_cents': 500,
      'paid_cents': 500,
      'spent_cents': 200,
    },
  };
  @override
  Future<void> deleteRecord(
    String table,
    String id, {
    RecordData? preview,
  }) async {
    expect(preview?['fingerprint'], isNotNull);
    deletions++;
  }
}

void main() {
  testWidgets(
    'Deleting a paid order requires explicit confirmation including its collections',
    (tester) async {
      final repo = DeletionRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    deleteRecord(c, repo, 'orders', 'order', 'pedido'),
                child: const Text('Borrar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(find.text('Cobros: 1 · USD 5.00'), findsOneWidget);
      expect(
        find.textContaining('El cliente guardado se conservará'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.deletions, 0);
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Eliminar pedido y cobros');
      expect(repo.deletions, 1);
    },
  );
  testWidgets(
    'Full sale deletion is available even when it contains paid orders and expenses',
    (tester) async {
      final repo = DeletionRepository();
      final sale = <String, dynamic>{
        'id': 'sale',
        'title': 'Venta',
        'sale_date': '2026-10-23',
        'currency': 'USD',
        'pork_price_cents': 100,
        'chicken_price_cents': 100,
      };
      repo.savedSales.add(sale);
      repo.savedOrders.add({
        'id': 'order',
        'sale_id': 'sale',
        'client_id': 'client',
        'clients': {'name': 'Pantera'},
        'pork_quantity': 5,
        'chicken_quantity': 0,
        'pork_price_cents': 100,
        'chicken_price_cents': 100,
        'total_cents': 500,
        'delivered': true,
        'payments': [
          {'id': 'payment', 'amount_cents': 500},
        ],
      });
      repo.savedExpenses.add({
        'id': 'expense',
        'sale_id': 'sale',
        'amount_cents': 200,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SaleDetailScreen(repository: repo, sale: sale),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eliminar venta completa'));
      await tester.pumpAndSettle();
      expect(find.text('Gastos: 1 · USD 2.00'), findsOneWidget);
      expect(
        find.textContaining('Los clientes guardados se conservarán'),
        findsOneWidget,
      );
      expect(find.text('Eliminar venta completa'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.deletions, 0);
    },
  );
}
