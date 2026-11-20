import 'package:flutter/material.dart';

import '../data/sales_repository.dart';
import '../data/finances.dart';
import 'expenses_screen.dart';
import 'payments_screen.dart';
import 'order_editor.dart';
import 'sales_screen.dart';
import 'repository_observer.dart';
import '../data/offline_repository.dart';
import '../data/delivery.dart';
import 'delivery_screen.dart';
import 'location_editor.dart';
import 'delete_record.dart';

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({
    super.key,
    required this.sale,
    required this.repository,
  });
  final RecordData sale;
  final SalesRepository repository;
  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen>
    with RepositoryObserver<SaleDetailScreen> {
  @override
  SalesRepository get observedRepository => widget.repository;
  @override
  Future<void> reloadRepository() => _load();
  late RecordData _sale = widget.sale;
  List<RecordData> _orders = [];
  List<RecordData> _expenses = [];
  bool _busy = false;
  final _updating = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy || _updating.isNotEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await Future.wait<dynamic>([
        widget.repository.orders(_sale['id'] as String),
        widget.repository.expenses(_sale['id'] as String),
        widget.repository.sale(_sale['id'] as String),
      ]);
      if (mounted) {
        setState(() {
          _orders = data[0] as List<RecordData>;
          _expenses = data[1] as List<RecordData>;
          _sale = data[2] as RecordData;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = financeError(
            error,
            'No se pudo actualizar la venta. Revisa tu conexión.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSale() async {
    final updated = await Navigator.of(context).push<RecordData>(
      MaterialPageRoute(
        builder: (_) => SaleEditor(repository: widget.repository, sale: _sale),
      ),
    );
    if (updated != null && mounted) setState(() => _sale = updated);
  }

  Future<void> _editOrder([RecordData? order]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderEditor(
          repository: widget.repository,
          sale: _sale,
          order: order,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _openPayments(RecordData order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsScreen(
          repository: widget.repository,
          orderId: order['id'] as String,
          currency: _sale['currency'] as String,
          clientName:
              (order['clients'] as Map?)?['name'] as String? ?? 'Cliente',
          saleDate: _sale['sale_date'] as String,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openExpenses() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ExpensesScreen(repository: widget.repository, sale: _sale),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _deliver(RecordData order, bool value) async {
    final id = order['id'] as String;
    if (_updating.contains(id)) return;
    setState(() => _updating.add(id));
    try {
      await widget.repository.deliver(id, value);
      if (mounted) setState(() => order['delivered'] = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo confirmar la entrega. Actualiza para comprobar su estado.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = SaleTotals(_orders);
    final finances = FinancialTotals(_orders, _expenses);
    final currency = _sale['currency'] as String;
    return Scaffold(
      appBar: AppBar(
        title: Text(dateLabel(_sale['sale_date'] as String)),
        actions: [
          if (!_busy)
            IconButton(
              tooltip: 'Eliminar venta completa',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final deleted = await deleteRecord(
                  context,
                  widget.repository,
                  'sales',
                  _sale['id'] as String,
                  'venta completa',
                );
                if (!context.mounted) return;
                if (deleted) {
                  Navigator.pop(context);
                }
              },
            ),
          IconButton(
            onPressed: _busy || _updating.isNotEmpty ? null : refreshRepository,
            tooltip: 'Actualizar pedidos',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _editSale,
            tooltip: 'Editar venta',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshRepository,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if ((_sale['title'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _sale['title'] as String,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_busy && _error == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumen de la venta',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Para preparar: ${totals.pork} de chancho · ${totals.chicken} de pollo',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Por entregar: ${totals.remainingPork} de chancho · ${totals.remainingChicken} de pollo',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pedidos entregados: ${totals.delivered} de ${totals.count}',
                      ),
                      const Divider(height: 28),
                      Text(
                        'Total vendido: ${money(totals.sold, currency)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text('Cobrado: ${money(finances.paid, currency)}'),
                      Text(
                        'Pendiente de cobro: ${money(finances.pending, currency)}',
                      ),
                      Text('Gastos: ${money(finances.spent, currency)}'),
                      const Divider(height: 24),
                      Text(
                        'Resultado: ${money(finances.result, currency)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text('Total vendido menos gastos.'),
                      const SizedBox(height: 8),
                      Text(
                        'Cobrado menos gastos: ${money(finances.cashBalance, currency)}',
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openExpenses,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Ver gastos'),
            ),
            const SizedBox(height: 20),
            if (widget.repository is OfflineRepository)
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeliveryScreen(
                      repository: widget.repository as OfflineRepository,
                      sale: _sale,
                    ),
                  ),
                ),
                icon: const Icon(Icons.route),
                label: const Text('Organizar reparto'),
              ),
            Text('Pedidos', style: Theme.of(context).textTheme.titleLarge),
            if (!_busy && _orders.isEmpty && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Agrega un cliente y las cantidades que te pidió.'),
              ),
            for (final order in _orders)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: Text(
                          (order['clients'] as Map?)?['name'] as String? ??
                              'Cliente',
                        ),
                        subtitle: Text(
                          '${order['pork_quantity']} de chancho · ${order['chicken_quantity']} de pollo\n${money(order['total_cents'] as int, currency)}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          onPressed: _updating.contains(order['id'])
                              ? null
                              : () => _editOrder(order),
                          tooltip: 'Editar pedido',
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                      if (order['high_priority'] == true ||
                          order['available_from'] != null ||
                          order['available_until'] != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if (order['high_priority'] == true)
                                const Chip(
                                  label: Text('Prioridad alta'),
                                  avatar: Icon(Icons.priority_high, size: 16),
                                ),
                              if (order['available_from'] != null)
                                Chip(
                                  label: Text(
                                    'Desde ${order['available_from'].toString().substring(0, 5)}',
                                  ),
                                ),
                              if (order['available_until'] != null)
                                Chip(
                                  label: Text(
                                    'Hasta ${order['available_until'].toString().substring(0, 5)}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ContactButtons(
                          client: order['clients'] as Map? ?? {},
                          location: coordinates(order),
                        ),
                      ),
                      CheckboxListTile(
                        value: order['delivered'] == true,
                        title: const Text('Entregado'),
                        subtitle: const Text('La entrega no modifica el pago.'),
                        onChanged: _updating.contains(order['id']) || _busy
                            ? null
                            : (value) => _deliver(order, value!),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${paymentStatus(order)} · Falta ${money(balanceFor(order), currency)}',
                            ),
                            TextButton.icon(
                              onPressed:
                                  _busy || _updating.contains(order['id'])
                                  ? null
                                  : () => _openPayments(order),
                              icon: const Icon(
                                Icons.account_balance_wallet_outlined,
                              ),
                              label: const Text('Ver cobros'),
                            ),
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final deleted = await deleteRecord(
                                        context,
                                        widget.repository,
                                        'orders',
                                        order['id'] as String,
                                        'pedido',
                                      );
                                      if (deleted && mounted) {
                                        await _load();
                                      }
                                    },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Eliminar pedido'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _editOrder(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar pedido'),
      ),
    );
  }
}
