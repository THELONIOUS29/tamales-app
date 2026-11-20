import 'package:flutter/material.dart';
import '../data/sales_repository.dart';
import '../data/finances.dart';

Future<bool> deleteRecord(
  BuildContext context,
  SalesRepository repository,
  String table,
  String id,
  String name,
) async {
  final preparing = repository.prepareDeletion(table, id);
  final preview = await showDialog<RecordData>(
    context: context,
    builder: (c) => FutureBuilder<RecordData>(
      future: preparing,
      builder: (c, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AlertDialog(
            title: Text('Comprobando datos…'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Actualizando los importes antes de eliminar.'),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return AlertDialog(
            title: const Text('No se pudo preparar la eliminación'),
            content: Text(
              financeError(
                snapshot.error!,
                'No se pudieron comprobar los datos. Revisa internet y vuelve a intentarlo.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cerrar'),
              ),
            ],
          );
        }
        final data = snapshot.data ?? <String, dynamic>{};
        final summary = data['summary'] as Map?;
        final currency = summary?['currency'] as String? ?? 'USD';
        return AlertDialog(
          title: Text('¿Eliminar $name?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary != null) ...[
                  Text('${summary['name'] ?? ''}'),
                  const SizedBox(height: 12),
                  Text(
                    'Pedidos: ${summary['orders']} · ${money(summary['sold_cents'] as int, currency)}',
                  ),
                  Text(
                    'Cobros: ${summary['payments']} · ${money(summary['paid_cents'] as int, currency)}',
                  ),
                  if (table == 'sales')
                    Text(
                      'Gastos: ${summary['expenses']} · ${money(summary['spent_cents'] as int, currency)}',
                    ),
                  const SizedBox(height: 12),
                ],
                Text(
                  table == 'sales'
                      ? 'Se eliminará esta venta con todos sus pedidos, cobros y gastos. Los clientes guardados se conservarán.'
                      : table == 'orders'
                      ? 'Se eliminará este pedido junto con todos sus cobros. El cliente guardado se conservará.'
                      : 'Se eliminará este cliente si no tiene pedidos registrados.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Se sincronizará con los demás teléfonos y los importes dejarán de aparecer en los resúmenes. Esta acción no se puede deshacer.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, data),
              child: Text(
                table == 'sales'
                    ? 'Eliminar venta completa'
                    : table == 'orders'
                    ? 'Eliminar pedido y cobros'
                    : 'Eliminar',
              ),
            ),
          ],
        );
      },
    ),
  );
  if (preview == null) return false;
  try {
    await repository.deleteRecord(table, id, preview: preview);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            financeError(
              e,
              'No se pudo guardar la eliminación. Actualiza antes de volver a intentarlo.',
            ),
          ),
        ),
      );
    }
    return false;
  }
}
