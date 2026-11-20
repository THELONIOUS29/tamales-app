import 'package:flutter/material.dart';

import '../data/finances.dart';
import '../data/sales_repository.dart';
import 'payments_screen.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key, required this.repository});
  final SalesRepository repository;
  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  final _rows = <RecordData>[];
  bool _loading = false, _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.pending(
        offset: reset ? 0 : _rows.length,
      );
      if (mounted) {
        setState(() {
          if (reset) _rows.clear();
          _rows.addAll(rows);
          _more = rows.length == 50;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = financeError(
            error,
            'No se pudieron cargar los pendientes. Revisa la conexión.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(RecordData row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsScreen(
          repository: widget.repository,
          orderId: row['order_id'] as String,
          currency: row['currency'] as String,
          clientName: row['client_name'] as String,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pendientes de cobro'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Actualizar pendientes',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Deudas de todas las ventas, aunque el pedido ya esté entregado.',
          ),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!),
          if (!_loading && _error == null && _rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No hay pedidos pendientes de cobro.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final row in _rows)
            Card(
              child: ListTile(
                title: Text(row['client_name'] as String),
                subtitle: Text(
                  'Venta: ${dateLabel(row['sale_date'] as String)}\nFalta: ${money(row['balance_cents'] as int, row['currency'] as String)}\n${row['delivered'] == true ? 'Entregado' : 'No entregado'}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(row),
              ),
            ),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          if (!_loading && _more && _rows.isNotEmpty)
            TextButton(
              onPressed: () => _load(reset: false),
              child: const Text('Ver más pendientes'),
            ),
          if (_error != null)
            TextButton(onPressed: _load, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
