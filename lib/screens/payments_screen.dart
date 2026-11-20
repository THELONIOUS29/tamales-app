import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/finances.dart';
import '../data/sales_repository.dart';
import 'repository_observer.dart';

String paymentDate(String value) {
  final date = DateTime.parse(value).toLocal();
  return '${dateLabel(dateValue(date))} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String methodLabel(String? method) => switch (method) {
  'cash' => 'Efectivo',
  'transfer' => 'Transferencia',
  'other' => 'Otro',
  _ => 'Sin método',
};

Future<bool> confirmRemoval(BuildContext context, String description) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    ) ??
    false;

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    super.key,
    required this.repository,
    required this.orderId,
    required this.currency,
    required this.clientName,
    this.saleDate,
  });
  final SalesRepository repository;
  final String orderId, currency, clientName;
  final String? saleDate;
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with RepositoryObserver<PaymentsScreen> {
  @override
  SalesRepository get observedRepository => widget.repository;
  @override
  Future<void> reloadRepository() => _load();
  RecordData? _order;
  bool _loading = false, _deleting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await widget.repository.order(widget.orderId);
      if (mounted) setState(() => _order = order);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = financeError(
            error,
            'No se pudo cargar el historial. Revisa la conexión.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add({bool settle = false}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentEditor(
          repository: widget.repository,
          order: _order!,
          currency: widget.currency,
          settle: settle,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _remove(RecordData payment) async {
    if (!await confirmRemoval(
      context,
      'Se eliminará este cobro y se recalculará el saldo pendiente del pedido.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.deletePayment(payment['id'] as String);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo confirmar la eliminación. Actualiza el historial.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final payments = order == null ? <RecordData>[] : paymentsOf(order)
      ..sort(
        (a, b) => (b['paid_at'] as String).compareTo(a['paid_at'] as String),
      );
    final busy = _loading || _deleting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobros del pedido'),
        actions: [
          IconButton(
            onPressed: busy ? null : refreshRepository,
            tooltip: 'Actualizar cobros',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshRepository,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.clientName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (widget.saleDate != null)
              Text('Venta del ${dateLabel(widget.saleDate!)}'),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!),
              TextButton(
                onPressed: refreshRepository,
                child: const Text('Reintentar'),
              ),
            ],
            if (order != null && _error == null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        paymentStatus(order),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Total del pedido: ${money(order['total_cents'] as int, widget.currency)}',
                      ),
                      Text(
                        'Cobrado: ${money(paidFor(order), widget.currency)}',
                      ),
                      Text(
                        'Saldo pendiente: ${money(balanceFor(order), widget.currency)}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        order['delivered'] == true
                            ? 'Entregado'
                            : 'No entregado',
                      ),
                    ],
                  ),
                ),
              ),
              if (balanceFor(order) > 0) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : () => _add(),
                  child: const Text('Registrar abono'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => _add(settle: true),
                  child: const Text('Pagar saldo completo'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Historial de cobros',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (payments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No hay cobros registrados.'),
                ),
              for (final payment in payments)
                Card(
                  child: ListTile(
                    title: Text(
                      money(payment['amount_cents'] as int, widget.currency),
                    ),
                    subtitle: Text(
                      '${paymentDate(payment['paid_at'] as String)}\n${methodLabel(payment['method'] as String?)}${(payment['notes'] as String? ?? '').isEmpty ? '' : '\n${payment['notes']}'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Eliminar cobro',
                      onPressed: busy ? null : () => _remove(payment),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class PaymentEditor extends StatefulWidget {
  const PaymentEditor({
    super.key,
    required this.repository,
    required this.order,
    required this.currency,
    this.settle = false,
  });
  final SalesRepository repository;
  final RecordData order;
  final String currency;
  final bool settle;
  @override
  State<PaymentEditor> createState() => _PaymentEditorState();
}

class _PaymentEditorState extends State<PaymentEditor> {
  final _form = GlobalKey<FormState>();
  final _id = const Uuid().v4();
  late final _amount = TextEditingController(
    text: decimalPrice(balanceFor(widget.order)),
  );
  final _notes = TextEditingController();
  DateTime _paidAt = DateTime.now();
  String _method = 'cash';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.recordPayment({
        'id': _id,
        'order_id': widget.order['id'],
        'amount_cents': widget.settle ? null : parseCents(_amount.text),
        'paid_at': _paidAt.toUtc().toIso8601String(),
        'method': _method,
        'notes': _notes.text.trim(),
      }, settle: widget.settle);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = financeError(
            error,
            'No se pudo confirmar el cobro. Reintenta en este formulario para no duplicar el registro.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.settle ? 'Pagar saldo completo' : 'Registrar abono'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Saldo consultado: ${money(balanceFor(widget.order), widget.currency)}',
            ),
            const SizedBox(height: 20),
            if (widget.settle)
              const Text(
                'Se guardará el saldo que muestra este teléfono. Si cambió en otro dispositivo, se pedirá revisar el cobro al sincronizar.',
              )
            else
              TextFormField(
                controller: _amount,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Importe recibido (${widget.currency})',
                ),
                validator: (value) {
                  final cents = parseCents(value ?? '');
                  if (cents == null || cents <= 0) {
                    return 'Ingresa un importe mayor que cero.';
                  }
                  if (cents > balanceFor(widget.order)) {
                    return 'El importe supera el saldo pendiente.';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha del cobro'),
              subtitle: Text(dateLabel(dateValue(_paidAt))),
              trailing: const Icon(Icons.calendar_month),
              onTap: _busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _paidAt,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null && mounted) {
                        setState(
                          () => _paidAt = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            _paidAt.hour,
                            _paidAt.minute,
                          ),
                        );
                      }
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Forma de pago'),
              items: ['cash', 'transfer', 'other']
                  .map(
                    (m) =>
                        DropdownMenuItem(value: m, child: Text(methodLabel(m))),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _method = value!),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _notes,
              enabled: !_busy,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Guardando…' : 'Confirmar cobro'),
            ),
          ],
        ),
      ),
    ),
  );
}
