import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/sales_repository.dart';
import 'sale_detail_screen.dart';
import 'repository_observer.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, required this.repository});
  final SalesRepository repository;
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with RepositoryObserver<SalesScreen> {
  @override
  SalesRepository get observedRepository => widget.repository;
  @override
  Future<void> reloadRepository() => _load();
  final _sales = <RecordData>[];
  bool _busy = false, _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.sales(
        offset: reset ? 0 : _sales.length,
      );
      if (mounted) {
        setState(() {
          if (reset) _sales.clear();
          _sales.addAll(rows);
          _more = rows.length == 20;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'No se pudieron cargar las ventas. Revisa tu conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final sale = await Navigator.of(context).push<RecordData>(
      MaterialPageRoute(
        builder: (_) => SaleEditor(repository: widget.repository),
      ),
    );
    if (!mounted || sale == null) return;
    await _open(sale);
  }

  Future<void> _open(RecordData sale) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SaleDetailScreen(sale: sale, repository: widget.repository),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ventas de tamales'),
      actions: [
        IconButton(
          onPressed: _busy ? null : refreshRepository,
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: refreshRepository,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Organiza los pedidos y la preparación de cada fecha.'),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          if (!_busy && _sales.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Crea tu primera venta y agrega los pedidos de tus clientes.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final sale in _sales)
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(
                  (sale['title'] as String).isEmpty
                      ? 'Venta de tamales'
                      : sale['title'] as String,
                ),
                subtitle: Text(dateLabel(sale['sale_date'] as String)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(sale),
              ),
            ),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          if (!_busy && _more && _sales.isNotEmpty)
            TextButton(
              onPressed: () => _load(reset: false),
              child: const Text('Ver más ventas'),
            ),
          if (!_busy && _error != null)
            TextButton(
              onPressed: refreshRepository,
              child: const Text('Reintentar'),
            ),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('Nueva venta'),
    ),
  );
}

class SaleEditor extends StatefulWidget {
  const SaleEditor({super.key, required this.repository, this.sale});
  final SalesRepository repository;
  final RecordData? sale;
  @override
  State<SaleEditor> createState() => _SaleEditorState();
}

class _SaleEditorState extends State<SaleEditor> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.sale?['id'] as String? ?? const Uuid().v4();
  late final _title = TextEditingController(
    text: widget.sale?['title'] as String? ?? '',
  );
  late final _pork = TextEditingController(
    text: widget.sale == null
        ? ''
        : decimalPrice(widget.sale!['pork_price_cents'] as int),
  );
  late final _chicken = TextEditingController(
    text: widget.sale == null
        ? ''
        : decimalPrice(widget.sale!['chicken_price_cents'] as int),
  );
  late DateTime _date = widget.sale == null
      ? DateTime.now()
      : DateTime.parse(widget.sale!['sale_date'] as String);
  late final _currency = TextEditingController(
    text: widget.sale?['currency'] as String? ?? 'USD',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _pork.dispose();
    _chicken.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await widget.repository.saveSale({
        'id': _id,
        'title': _title.text.trim(),
        'sale_date': dateValue(_date),
        'currency': _currency.text.trim().toUpperCase(),
        'pork_price_cents': parseCents(_pork.text),
        'chicken_price_cents': parseCents(_chicken.text),
      }, creating: widget.sale == null);
      if (mounted) Navigator.of(context).pop(row);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo confirmar el guardado. Puedes reintentar sin crear otra venta.',
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
        title: Text(widget.sale == null ? 'Nueva venta' : 'Editar venta'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha de entrega'),
              subtitle: Text(dateLabel(dateValue(_date))),
              trailing: const Icon(Icons.calendar_month),
              onTap: _busy
                  ? null
                  : () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (selected != null && mounted) {
                        setState(() => _date = selected);
                      }
                    },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Nombre de la venta (opcional)',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _currency,
              enabled: !_busy && widget.sale == null,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Moneda',
                helperText: 'USD: dólares estadounidenses',
              ),
              validator: (v) =>
                  RegExp(r'^[A-Z]{3}$').hasMatch((v ?? '').trim().toUpperCase())
                  ? null
                  : 'Usa tres letras, por ejemplo USD.',
            ),
            const SizedBox(height: 24),
            const Text('Precio por tamal'),
            const SizedBox(height: 12),
            for (final entry in {'Chancho': _pork, 'Pollo': _chicken}.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  controller: entry.value,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: entry.key,
                    hintText: '0.00',
                  ),
                  validator: (v) => parseCents(v ?? '') == null
                      ? 'Ingresa un precio válido, con hasta dos decimales.'
                      : null,
                ),
              ),
            if (widget.sale != null)
              const Text(
                'Los precios nuevos se aplicarán a los próximos pedidos. Los pedidos existentes conservan su precio.',
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Guardando…' : 'Guardar venta'),
            ),
          ],
        ),
      ),
    ),
  );
}
