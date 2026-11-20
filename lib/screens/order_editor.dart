import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/sales_repository.dart';
import '../data/finances.dart';
import '../data/delivery.dart';
import 'location_editor.dart';
import 'package:latlong2/latlong.dart';

String timeValue(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
TimeOfDay? readTime(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

class OrderEditor extends StatefulWidget {
  const OrderEditor({
    super.key,
    required this.repository,
    required this.sale,
    this.order,
  });
  final SalesRepository repository;
  final RecordData sale;
  final RecordData? order;
  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends State<OrderEditor> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.order?['id'] as String? ?? const Uuid().v4();
  late final _pork = TextEditingController(
    text: '${widget.order?['pork_quantity'] ?? 0}',
  );
  late final _chicken = TextEditingController(
    text: '${widget.order?['chicken_quantity'] ?? 0}',
  );
  late final _porkPrice = TextEditingController(
    text: decimalPrice(
      (widget.order ?? widget.sale)['pork_price_cents'] as int,
    ),
  );
  late final _chickenPrice = TextEditingController(
    text: decimalPrice(
      (widget.order ?? widget.sale)['chicken_price_cents'] as int,
    ),
  );
  late final _notes = TextEditingController(
    text: widget.order?['notes'] as String? ?? '',
  );
  late bool _priority = widget.order?['high_priority'] == true;
  late TimeOfDay? _from = readTime(widget.order?['available_from'] as String?);
  late TimeOfDay? _until = readTime(
    widget.order?['available_until'] as String?,
  );
  late LatLng? _location = widget.order == null
      ? null
      : coordinates(widget.order!);
  late final _address = TextEditingController(
    text: widget.order?['delivery_address'] as String? ?? '',
  );
  late final _reference = TextEditingController(
    text: widget.order?['delivery_reference'] as String? ?? '',
  );
  RecordData? _client;
  List<RecordData>? _clients;
  bool _busy = false, _loadingClients = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final controller in [_pork, _chicken, _porkPrice, _chickenPrice]) {
      controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final controller in [
      _pork,
      _chicken,
      _porkPrice,
      _chickenPrice,
      _notes,
      _address,
      _reference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickClient() async {
    if (_loadingClients || _busy) return;
    setState(() {
      _loadingClients = true;
      _error = null;
    });
    try {
      _clients ??= await widget.repository.clients();
      if (!mounted) return;
      final picked = await showDialog<RecordData>(
        context: context,
        builder: (_) => ClientPicker(clients: _clients!),
      );
      if (picked != null && mounted) {
        setState(() {
          _client = picked;
          _location = coordinates(picked);
          _address.text = picked['address'] as String? ?? '';
          _reference.text = picked['reference'] as String? ?? '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudieron cargar los clientes. Revisa la conexión y vuelve a seleccionarlos.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  Future<void> _pickTime(bool from) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (from ? _from : _until) ?? const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() {
        if (from) {
          _from = picked;
        } else {
          _until = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final pork = parseQuantity(_pork.text)!;
    final chicken = parseQuantity(_chicken.text)!;
    String? validation;
    if (widget.order == null && _client == null) {
      validation = 'Selecciona un cliente.';
    } else if (pork + chicken == 0) {
      validation = 'Agrega al menos un tamal de chancho o de pollo.';
    } else if (_from != null &&
        _until != null &&
        (_from!.hour * 60 + _from!.minute) >
            (_until!.hour * 60 + _until!.minute)) {
      validation =
          'La hora final debe ser igual o posterior a la hora inicial.';
    }
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final original = widget.order;
      await widget.repository.saveOrder({
        'id': _id,
        'sale_id': widget.sale['id'],
        'client_id': original?['client_id'] ?? _client!['id'],
        'pork_quantity': pork,
        'chicken_quantity': chicken,
        'pork_price_cents': parseCents(_porkPrice.text),
        'chicken_price_cents': parseCents(_chickenPrice.text),
        'notes': _notes.text.trim(),
        'high_priority': _priority,
        'available_from': _from == null ? null : timeValue(_from!),
        'available_until': _until == null ? null : timeValue(_until!),
        'delivery_address': _address.text.trim(),
        'delivery_reference': _reference.text.trim(),
        'latitude': _location?.latitude,
        'longitude': _location?.longitude,
      }, creating: original == null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = financeError(
            error,
            'No se pudo confirmar el guardado. Reintenta aquí sin crear otro pedido.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total =
        (parseQuantity(_pork.text) ?? 0) * (parseCents(_porkPrice.text) ?? 0) +
        (parseQuantity(_chicken.text) ?? 0) *
            (parseCents(_chickenPrice.text) ?? 0);
    final existingClient = widget.order?['clients'] as Map?;
    final name = widget.order == null
        ? (_client?['name'])
        : (existingClient?['name']);
    return PopScope(
      canPop: !_busy && !_loadingClients,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.order == null ? 'Nuevo pedido' : 'Editar pedido'),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(name as String? ?? 'Seleccionar cliente'),
                subtitle: Text(
                  _loadingClients
                      ? 'Cargando clientes…'
                      : widget.order == null
                      ? 'Usar un cliente guardado'
                      : 'Cliente de este pedido',
                ),
                trailing: widget.order == null
                    ? const Icon(Icons.search)
                    : null,
                onTap: _busy || widget.order != null ? null : _pickClient,
              ),
              TextFormField(
                controller: _address,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Dirección de esta entrega',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reference,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Referencia de esta entrega',
                ),
              ),
              LocationField(
                value: _location,
                onChanged: (v) => setState(() => _location = v),
              ),
              const SizedBox(height: 16),
              for (final entry in [
                (_pork, _porkPrice, 'Chancho'),
                (_chicken, _chickenPrice, 'Pollo'),
              ]) ...[
                Text(entry.$3, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: entry.$1,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                        ),
                        validator: (v) => parseQuantity(v ?? '') == null
                            ? 'Cantidad entera, hasta 999999.'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: entry.$2,
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Precio unitario',
                        ),
                        validator: (v) => parseCents(v ?? '') == null
                            ? 'Precio inválido.'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              Text(
                'Total: ${money(total, widget.sale['currency'] as String)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Prioridad alta'),
                value: _priority,
                onChanged: _busy ? null : (v) => setState(() => _priority = v),
              ),
              const Text('Disponibilidad de entrega (opcional)'),
              const SizedBox(height: 8),
              for (final from in [true, false])
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _pickTime(from),
                        child: Text(
                          '${from ? 'Desde' : 'Hasta'}: ${(from ? _from : _until) == null ? 'sin hora' : timeValue((from ? _from : _until)!)}',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar horario',
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              if (from) {
                                _from = null;
                              } else {
                                _until = null;
                              }
                            }),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                enabled: !_busy,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observaciones del pedido',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy || _loadingClients ? null : _save,
                child: Text(_busy ? 'Guardando…' : 'Guardar pedido'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClientPicker extends StatefulWidget {
  const ClientPicker({super.key, required this.clients});
  final List<RecordData> clients;
  @override
  State<ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<ClientPicker> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.clients
        .where(
          (client) => '${client['name']} ${client['phone'] ?? ''}'
              .toLowerCase()
              .contains(_search.toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: const Text('Elegir cliente'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Buscar cliente'),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.clients.isEmpty
                            ? 'Primero agrega clientes en la pestaña Clientes.'
                            : 'No hay coincidencias.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(filtered[index]['name'] as String),
                        subtitle: Text(
                          filtered[index]['phone'] as String? ?? '',
                        ),
                        onTap: () => Navigator.of(context).pop(filtered[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
