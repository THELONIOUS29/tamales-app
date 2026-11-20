import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../data/delivery.dart';
import '../data/delivery_session.dart';
import '../data/delivery_notifications.dart';
import '../data/offline_repository.dart';
import '../data/sales_repository.dart';
import '../data/finances.dart';
import '../data/road_matrix.dart';
import 'location_editor.dart';
import 'order_editor.dart';
import 'payments_screen.dart';
import 'repository_observer.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({
    super.key,
    required this.repository,
    required this.sale,
  });
  final OfflineRepository repository;
  final RecordData sale;
  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen>
    with RepositoryObserver<DeliveryScreen> {
  @override
  SalesRepository get observedRepository => widget.repository;
  @override
  Future<void> reloadRepository() => _load();
  List<RecordData> _orders = [];
  final _selected = <String>{};
  LatLng? _origin;
  late TimeOfDay _start = TimeOfDay.now();
  int _service = 3;
  bool _busy = true, _initialized = false, _roads = true, _calculating = false;
  bool _planRoads = false;
  String? _error;
  DeliveryPlan? _plan;
  List<String>? _manual;
  String get _key => 'delivery_${widget.sale['id']}';
  bool get _active =>
      activeDeliverySession?.settings?['sale_id'] == widget.sale['id'];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await widget.repository.orders(
        widget.sale['id'] as String,
      );
      if (!_initialized) {
        final raw = await widget.repository.store.meta(_key);
        if (raw != null) {
          final data = jsonDecode(raw) as Map;
          _origin = coordinates(data);
          _service = data['service'] as int? ?? 3;
          _roads = data['roads'] as bool? ?? true;
          final minute = data['start'] as int?;
          if (minute != null) {
            _start = TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
          }
          _selected.addAll((data['selected'] as List? ?? []).cast<String>());
          _manual = (data['manual'] as List?)?.cast<String>();
        } else {
          _selected.addAll(
            orders
                .where((o) => o['delivered'] != true)
                .map((o) => o['id'] as String),
          );
        }
        _initialized = true;
      }
      if (mounted) {
        setState(() {
          _orders = orders;
          _busy = false;
          _error = null;
        });
      }
      if ((_plan != null || _active) && _origin != null) {
        _calculate(manual: _manual, persist: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'No se pudo cargar el reparto: $e';
        });
      }
    }
  }

  Future<void> _persist() => widget.repository.store.setMeta(
    _key,
    jsonEncode({
      'latitude': _origin?.latitude,
      'longitude': _origin?.longitude,
      'service': _service,
      'roads': _roads,
      'start': _start.hour * 60 + _start.minute,
      'selected': _selected.toList(),
      'manual': _manual,
    }),
  );
  Future<void> _calculate({List<String>? manual, bool persist = true}) async {
    if (_origin == null) {
      setState(() => _error = 'Elige el punto de salida.');
      return;
    }
    final chosen = _orders.where((o) => _selected.contains(o['id'])).toList();
    if (chosen.every((o) => o['delivered'] == true)) {
      setState(() {
        if (!persist) {
          _plan = DeliveryPlan([], [], _start.hour * 60 + _start.minute, 0);
          _error = null;
        } else {
          _error = 'Selecciona al menos un pedido pendiente.';
        }
      });
      return;
    }
    if (_calculating) return;
    if (mounted) {
      setState(() {
        _calculating = true;
        _error = null;
      });
    }
    try {
      RoadMatrix? matrix;
      final located = chosen.where((o) => coordinates(o) != null).toList();
      final pending = located.where((o) => o['delivered'] != true).toList();
      if (_roads && pending.isNotEmpty) {
        final full = await RoadMatrix.load(widget.repository.store, [
          _origin!,
          ...located.map((o) => coordinates(o)!),
        ], allowNetwork: persist);
        final indices = [0, ...pending.map((o) => located.indexOf(o) + 1)];
        matrix = RoadMatrix(
          indices
              .map((i) => indices.map((j) => full.durations[i][j]).toList())
              .toList(),
          indices
              .map((i) => indices.map((j) => full.distances[i][j]).toList())
              .toList(),
        );
      }
      final plan = planDelivery(
        chosen,
        _origin!,
        _start.hour * 60 + _start.minute,
        _service,
        manualOrder: manual,
        durations: matrix?.durations,
        distances: matrix?.distances,
      );
      if (mounted) {
        setState(() {
          _plan = plan;
          _manual = manual;
          _planRoads = matrix != null;
        });
      }
      if (persist) {
        await _persist();
        if (_active) {
          await activeDeliverySession?.start({
            'sale_id': widget.sale['id'],
            'currency': widget.sale['currency'],
            'ids': plan.visits.map((v) => v.order['id']).toList(),
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = financeError(e, 'No se pudo calcular el reparto.'),
        );
      }
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<void> _startRoute() async {
    final plan = _plan;
    if (plan == null || plan.visits.isEmpty) return;
    if (_active) {
      await activeDeliverySession?.stop();
      if (mounted) setState(() {});
      return;
    }
    if (activeDeliverySession?.settings != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Cambiar reparto activo'),
          content: const Text(
            'Se pausará el reparto de la otra venta en este teléfono.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Cambiar'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    _manual = plan.visits.map((v) => v.order['id'] as String).toList();
    await _persist();
    await activeDeliverySession?.start({
      'sale_id': widget.sale['id'],
      'currency': widget.sale['currency'],
      'ids': plan.visits.map((v) => v.order['id']).toList(),
    });
    if (mounted) setState(() {});
  }

  Future<void> _delivered(RecordData order) async {
    try {
      await widget.repository.deliver(order['id'] as String, true);
      _origin = coordinates(order) ?? _origin;
      _start = TimeOfDay.now();
      _manual = _plan?.visits
          .where((v) => v.order['id'] != order['id'])
          .map((v) => v.order['id'] as String)
          .toList();
      await _persist();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = financeError(e, 'No se pudo guardar la entrega.'),
        );
      }
    }
  }

  Future<void> _edit(RecordData order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderEditor(
          repository: widget.repository,
          sale: widget.sale,
          order: order,
        ),
      ),
    );
    await _load();
  }

  Future<void> _pay(RecordData order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsScreen(
          repository: widget.repository,
          orderId: order['id'] as String,
          currency: widget.sale['currency'] as String,
          clientName:
              (order['clients'] as Map?)?['name'] as String? ?? 'Cliente',
          saleDate: widget.sale['sale_date'] as String,
        ),
      ),
    );
    await _load();
  }

  Future<void> _move(int index, int delta) async {
    final ids = _plan!.visits.map((v) => v.order['id'] as String).toList();
    final target = index + delta;
    if (target < 0 || target >= ids.length) return;
    final id = ids.removeAt(index);
    ids.insert(target, id);
    await _calculate(manual: ids);
    if (_active) {
      await activeDeliverySession?.start({
        'sale_id': widget.sale['id'],
        'currency': widget.sale['currency'],
        'ids': _plan!.visits.map((v) => v.order['id']).toList(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reparto'),
        actions: [
          IconButton(
            tooltip: 'Actualizar reparto',
            onPressed: refreshRepository,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Venta ${dateLabel(widget.sale['sale_date'] as String)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Un repartidor. La ruta de este teléfono se guarda al cerrar la app. Las entregas y cobros se comparten con los demás dispositivos.',
                ),
                const SizedBox(height: 12),
                LocationField(
                  value: _origin,
                  label: 'Punto de salida',
                  onChanged: (p) => setState(() {
                    _origin = p;
                    _plan = null;
                  }),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hora de salida'),
                  subtitle: Text(timeValue(_start)),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _start,
                    );
                    if (t != null && mounted) {
                      setState(() {
                        _start = t;
                        _plan = null;
                      });
                    }
                  },
                ),
                DropdownButtonFormField<int>(
                  initialValue: _service,
                  decoration: const InputDecoration(
                    labelText: 'Minutos por entrega',
                  ),
                  items: [1, 2, 3, 5, 10, 15]
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text('$m minutos'),
                        ),
                      )
                      .toList(),
                  onChanged: (m) => setState(() {
                    _service = m!;
                    _plan = null;
                  }),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Calcular por calles'),
                  subtitle: const Text(
                    'openrouteservice · requiere internet al calcular. Sin esta opción se estima por cercanía.',
                  ),
                  value: _roads,
                  onChanged: _calculating
                      ? null
                      : (v) => setState(() {
                          _roads = v;
                          _plan = null;
                        }),
                ),
                ExpansionTile(
                  title: Text('Pedidos seleccionados: ${_selected.length}'),
                  initiallyExpanded: plan == null,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _selected.clear();
                        _selected.addAll(
                          _orders
                              .where((o) => o['delivered'] != true)
                              .map((o) => o['id'] as String),
                        );
                        _plan = null;
                      }),
                      child: const Text('Seleccionar pendientes'),
                    ),
                    for (final o in _orders.where(
                      (o) => o['delivered'] != true,
                    ))
                      CheckboxListTile(
                        value: _selected.contains(o['id']),
                        title: Text(
                          (o['clients'] as Map?)?['name'] as String? ??
                              'Cliente',
                        ),
                        subtitle: Text(
                          '${o['pork_quantity']} chancho · ${o['chicken_quantity']} pollo${coordinates(o) == null ? ' · Sin ubicación' : ''}',
                        ),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(o['id'] as String);
                          } else {
                            _selected.remove(o['id']);
                          }
                          _plan = null;
                        }),
                      ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _calculating ? null : () => _calculate(),
                  icon: const Icon(Icons.route),
                  label: Text(
                    _calculating ? 'Calculando…' : 'Calcular orden de entrega',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (plan != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _planRoads
                        ? 'Tiempos y distancias por calles para automóvil, sin tráfico en vivo. Prioridad alta primero cuando el cliente esté disponible. Revisa los horarios antes de salir.'
                        : 'Estimación local por cercanía; no calcula calles ni tráfico. Prioridad alta primero cuando el cliente esté disponible. Revisa los horarios antes de salir.',
                  ),
                  if (_planRoads)
                    const Text(
                      '© openrouteservice.org by HeiGIT | Map data © OpenStreetMap contributors',
                    ),
                  if (plan.visits.isEmpty && plan.missing.isEmpty)
                    const Text(
                      'Las entregas seleccionadas ya están completadas.',
                    ),
                  Text(
                    '${plan.visits.length} paradas · ${plan.distance.toStringAsFixed(1)} km ${_planRoads ? 'por calles' : 'en línea recta'} · Fin aprox. ${clockLabel(plan.finish)}',
                  ),
                  if (_manual != null)
                    const Text(
                      'Orden manual: comprueba prioridad y posibles retrasos.',
                    ),
                  if (plan.missing.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            const Text(
                              'Estos pedidos siguen pendientes y no están incluidos en la ruta. Agrega su ubicación:',
                            ),
                            for (final o in plan.missing)
                              ListTile(
                                title: Text(
                                  (o['clients'] as Map?)?['name'] as String? ??
                                      'Cliente',
                                ),
                                trailing: const Icon(Icons.edit_location_alt),
                                onTap: () => _edit(o),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (plan.visits.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _startRoute,
                      icon: Icon(
                        _active
                            ? Icons.pause
                            : Icons.notifications_active_outlined,
                      ),
                      label: Text(
                        _active
                            ? 'Pausar aviso de reparto'
                            : 'Iniciar reparto y mostrar siguiente entrega',
                      ),
                    ),
                  const Text(
                    'Si Android lo solicita, permite las notificaciones. Marca Entregado para pasar al siguiente; no modifica el pago.',
                  ),
                  TextButton.icon(
                    onPressed: DeliveryNotifications.openSettings,
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Permisos de notificación'),
                  ),
                  for (var i = 0; i < plan.visits.length; i++)
                    _visit(plan.visits[i], i),
                ],
                if (_active && plan == null)
                  OutlinedButton(
                    onPressed: () async {
                      await activeDeliverySession?.stop();
                      if (mounted) setState(() {});
                    },
                    child: const Text('Pausar reparto activo'),
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _visit(DeliveryVisit v, int index) {
    final o = v.order, client = o['clients'] as Map? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ${client['name'] ?? 'Cliente'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${o['pork_quantity']} chancho · ${o['chicken_quantity']} pollo',
            ),
            Text(
              'Llegada aprox. ${clockLabel(v.arrival)}${v.wait > 0 ? ' · Espera ${v.wait} min' : ''}',
            ),
            if (o['high_priority'] == true) const Text('Prioridad alta'),
            if (o['available_from'] != null || o['available_until'] != null)
              Text(
                'Disponible: ${o['available_from']?.toString().substring(0, 5) ?? 'sin inicio'} – ${o['available_until']?.toString().substring(0, 5) ?? 'sin límite'}',
              ),
            if (v.late > 0)
              Text(
                'Atención: ${v.late} min después de la hora límite.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if ((o['delivery_address'] as String? ?? '').isNotEmpty)
              Text(o['delivery_address'] as String),
            if ((o['delivery_reference'] as String? ?? '').isNotEmpty)
              Text(o['delivery_reference'] as String),
            if ((o['notes'] as String? ?? '').isNotEmpty)
              Text(o['notes'] as String),
            Text(
              '${paymentStatus(o)} · Falta ${money(balanceFor(o), widget.sale['currency'] as String)}',
            ),
            ContactButtons(client: client, location: coordinates(o)),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _delivered(o),
                  icon: const Icon(Icons.check),
                  label: const Text('Entregado'),
                ),
                TextButton(
                  onPressed: () => _pay(o),
                  child: const Text('Ver cobros'),
                ),
                TextButton(
                  onPressed: () => _edit(o),
                  child: const Text('Editar'),
                ),
                IconButton(
                  tooltip: 'Adelantar',
                  onPressed: index == 0 ? null : () => _move(index, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Dejar para el final',
                  onPressed: index == _plan!.visits.length - 1
                      ? null
                      : () => _move(index, _plan!.visits.length - 1 - index),
                  icon: const Icon(Icons.low_priority),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
