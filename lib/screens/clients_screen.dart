import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../data/sales_repository.dart';
import 'repository_observer.dart';
import 'import_contacts_screen.dart';
import 'location_editor.dart';
import 'delete_record.dart';
import '../data/delivery.dart';
import 'package:latlong2/latlong.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, required this.repository});
  final SalesRepository repository;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen>
    with RepositoryObserver<ClientsScreen> {
  @override
  SalesRepository get observedRepository => widget.repository;
  @override
  Future<void> reloadRepository() => _load();
  List<Map<String, dynamic>> _clients = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading && _clients.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.clients();
      if (mounted) setState(() => _clients = data);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'PGRST205' || error.code == '42P01'
              ? 'Primero hay que instalar las tablas del proyecto en Supabase.'
              : 'No se pudieron cargar los clientes. Inténtalo de nuevo.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo conectar. Revisa tu conexión.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? client]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ClientEditor(client: client, repository: widget.repository),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _importContacts() async {
    final count = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ImportContactsScreen(repository: widget.repository),
      ),
    );
    if (!mounted) return;
    await _load();
    if (count != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count cliente(s) importado(s).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _clients
        .where(
          (client) => '${client['name']} ${client['phone'] ?? ''}'
              .toLowerCase()
              .contains(_search.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Importar contactos',
            icon: const Icon(Icons.contacts_outlined),
            onPressed: _importContacts,
          ),
          IconButton(
            onPressed: refreshRepository,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _importContacts,
              icon: const Icon(Icons.contacts_outlined),
              label: const Text('Importar contactos'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar nombre o teléfono',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: refreshRepository,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: refreshRepository,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      children: filtered.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  _clients.isEmpty
                                      ? 'Agrega tu primer cliente. Sus datos quedarán guardados para las próximas ventas.'
                                      : 'No hay clientes que coincidan.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ]
                          : filtered
                                .map(
                                  (client) => Card(
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        child: Icon(Icons.person_outline),
                                      ),
                                      title: Text(client['name'] as String),
                                      subtitle: Text(
                                        [client['phone'], client['address']]
                                            .whereType<String>()
                                            .where((v) => v.isNotEmpty)
                                            .join('\n'),
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _edit(client),
                                    ),
                                  ),
                                )
                                .toList(),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        label: const Text('Nuevo cliente'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class ClientEditor extends StatefulWidget {
  const ClientEditor({super.key, this.client, required this.repository});
  final Map<String, dynamic>? client;
  final SalesRepository repository;

  @override
  State<ClientEditor> createState() => _ClientEditorState();
}

class _ClientEditorState extends State<ClientEditor> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.client?['id'] as String? ?? const Uuid().v4();
  late final Map<String, TextEditingController> _fields;
  late LatLng? _location = widget.client == null
      ? null
      : coordinates(widget.client!);
  bool _saving = false;
  String? _error;
  static const _labels = {
    'name': 'Nombre',
    'phone': 'Teléfono con código de país',
    'address': 'Dirección',
    'reference': 'Referencia de la dirección',
    'notes': 'Observaciones',
  };

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final field in _labels.keys)
        field: TextEditingController(
          text: widget.client?[field] as String? ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = <String, dynamic>{
      for (final field in _fields.entries) field.key: field.value.text.trim(),
    };
    try {
      await widget.repository.saveClient({
        ...data,
        'id': _id,
        'latitude': _location?.latitude,
        'longitude': _location?.longitude,
      }, creating: widget.client == null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo confirmar el guardado. Comprueba la conexión y revisa la lista antes de volver a crear el cliente.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.client == null ? 'Nuevo cliente' : 'Editar cliente',
          ),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final field in _labels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: _fields[field.key],
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: field.value,
                      hintText: field.key == 'phone' ? '+593…' : null,
                    ),
                    keyboardType: field.key == 'phone'
                        ? TextInputType.phone
                        : TextInputType.text,
                    maxLines: field.key == 'notes' || field.key == 'address'
                        ? 2
                        : 1,
                    validator: (value) {
                      if (field.key == 'name' &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Ingresa el nombre del cliente.';
                      }
                      if (field.key == 'phone' &&
                          value != null &&
                          value.trim().isNotEmpty &&
                          !RegExp(
                            r'^\+[1-9]\d{6,14}$',
                          ).hasMatch(value.trim())) {
                        return 'Usa + y el código de país, sin espacios.';
                      }
                      return null;
                    },
                  ),
                ),
              LocationField(
                value: _location,
                onChanged: (v) => setState(() => _location = v),
              ),
              if (widget.client != null)
                ContactButtons(client: widget.client!, location: _location),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (widget.client != null)
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final deleted = await deleteRecord(
                            context,
                            widget.repository,
                            'clients',
                            _id,
                            'cliente',
                          );
                          if (!context.mounted) return;
                          if (deleted) {
                            Navigator.pop(context, true);
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar cliente sin pedidos'),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Guardando…' : 'Guardar cliente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
