import 'package:supabase_flutter/supabase_flutter.dart';

import 'sales_repository.dart';

List<RecordData> paymentsOf(RecordData order) =>
    ((order['payments'] as List?) ?? [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();

int paidFor(RecordData order) => paymentsOf(order)
    .where((payment) => payment['_sync_error'] == null)
    .fold(0, (total, payment) => total + (payment['amount_cents'] as int));
int balanceFor(RecordData order) =>
    (order['total_cents'] as int) - paidFor(order);
String paymentStatus(RecordData order) =>
    paymentsOf(order).any((p) => p['_sync_error'] != null)
    ? 'Cobro por revisar'
    : paymentsOf(order).any((p) => p['_sync_pending'] == true)
    ? 'Cobro pendiente de sincronizar'
    : balanceFor(order) <= 0
    ? 'Pagado'
    : paidFor(order) == 0
    ? 'Pendiente'
    : 'Abono';

class FinancialTotals {
  FinancialTotals(Iterable<RecordData> orders, Iterable<RecordData> expenses) {
    for (final order in orders) {
      sold += order['total_cents'] as int;
      paid += paidFor(order);
      pending += balanceFor(order);
    }
    for (final expense in expenses) {
      spent += expense['amount_cents'] as int;
    }
  }
  int sold = 0, paid = 0, pending = 0, spent = 0;
  int get result => sold - spent;
  int get cashBalance => paid - spent;
}

String financeError(Object error, String fallback) {
  if (error is DataValidationException) return error.message;
  if (error is PostgrestException) {
    if (error.message.contains('payment_exceeds_balance')) {
      return 'El importe supera el saldo actual. Actualiza el pedido: puede haber un cobro desde otro teléfono.';
    }
    if (error.message.contains('order_total_below_paid')) {
      return 'El total del pedido no puede ser menor que lo ya cobrado. Revisa sus pagos antes de reducirlo.';
    }
    if (error.message.contains('payment_no_balance')) {
      return 'Este pedido ya está pagado. Vuelve al historial y actualiza.';
    }
    if (error.code == 'PGRST202') {
      return 'Falta actualizar las funciones de la base de datos en Supabase.';
    }
  }
  return fallback;
}
