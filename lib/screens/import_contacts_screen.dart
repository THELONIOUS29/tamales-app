import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../data/phone_contacts.dart';
import '../data/sales_repository.dart';

class ImportContactsScreen extends StatefulWidget {
  const ImportContactsScreen({super.key, required this.repository});
  final SalesRepository repository;

  @override
  State<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

class _ImportContactsScreenState extends State<ImportContactsScreen> {
  List<PhoneContact> _contacts = [];
  final _selected = <String>{};
  final _existing = <String>{};
  final _ids = <String, String>{};
  bool _loading = true, _saving = false, _review = false;
  String _search = '';
  String? _error;
  int _imported = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final existing = await widget.repository.clients();
      final contacts = await PhoneContacts.read();
      if (!mounted) return;
      setState(() {
        _existing.addAll(
          existing
              .map((c) => contactPhone(c['phone'] as String? ?? ''))
              .whereType<String>(),
        );
        _contacts = contacts;
        _selected.removeAll(_existing);
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'permission_denied'
              ? 'Permite el acceso a tus contactos en Ajustes.'
              : 'No se pudieron leer los contactos. IntÃ©ntalo de nuevo.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudieron cargar los contactos. IntÃ©ntalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Recheck local clients in case another screen or device added one.
      final current = await widget.repository.clients();
      _existing.addAll(
        current
            .map((c) => contactPhone(c['phone'] as String? ?? ''))
            .whereType<String>(),
      );
      for (final contact
          in _contacts.where((c) => _selected.contains(c.phone)).toList()) {
        if (!_existing.contains(contact.phone)) {
          final id = _ids.putIfAbsent(contact.phone, () => const Uuid().v4());
          await widget.repository.saveClient({
            'id': id,
            'name': contact.name,
            'phone': contact.phone,
            'address': '',
            'reference': '',
            'notes': '',
            'latitude': null,
            'longitude': null,
          }, creating: true);
          _existing.add(contact.phone);
          _imported++;
        }
        _selected.remove(contact.phone);
      }
      if (mounted) Navigator.pop(context, _imported);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Se guardaron $_imported contacto(s). No se pudo completar la importaciÃ³n. Puedes reintentar los restantes.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(PhoneContact contact) => setState(() {
    if (!_selected.remove(contact.phone)) _selected.add(contact.phone);
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = _contacts
        .where(
          (c) =>
              (!_review || _selected.contains(c.phone)) && c.matches(_search),
        )
        .toList();
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_review ? 'Confirmar clientes' : 'Tus contactos'),
          actions: [
            IconButton(
              tooltip: 'Ayuda',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => const SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.contact_phone_outlined, size: 32),
                        SizedBox(height: 16),
                        Text(
                          'Importar desde tu agenda',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Solo guardamos nombre y teléfono de los contactos que elijas. Los números repetidos se omiten.',
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Usamos +593 para números locales de Ecuador. Para otros países, guarda el código internacional en tu agenda.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            _review
                                ? Icons.person_add_alt_1_rounded
                                : Icons.contacts_rounded,
                            color: colors.onPrimaryContainer,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _review
                                    ? 'Todo listo'
                                    : 'Agrega a tus clientes',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _review
                                    ? '${_selected.length} seleccionados'
                                    : 'Elige uno o varios contactos',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: colors.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!_review)
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('Reintentar'),
                                ),
                                TextButton(
                                  onPressed: () => PhoneContacts.channel
                                      .invokeMethod<void>('settings'),
                                  child: const Text('Abrir ajustes'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  if (!_review)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        enabled: !_saving,
                        decoration: InputDecoration(
                          hintText: 'Buscar contacto',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _review
                                ? 'NUEVOS CLIENTES'
                                : '${visible.length} CONTACTOS',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (!_review)
                          TextButton.icon(
                            icon: Icon(
                              _selected.isEmpty
                                  ? Icons.done_all_rounded
                                  : Icons.deselect_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _selected.isEmpty
                                  ? 'Seleccionar todos'
                                  : 'Limpiar',
                            ),
                            onPressed: () => setState(() {
                              if (_selected.isEmpty) {
                                _selected.addAll(
                                  visible
                                      .where(
                                        (c) => !_existing.contains(c.phone),
                                      )
                                      .map((c) => c.phone),
                                );
                              } else {
                                _selected.clear();
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_search_outlined,
                                      size: 54,
                                      color: colors.outline,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _search.isEmpty
                                          ? 'No hay contactos disponibles'
                                          : 'Sin coincidencias',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _search.isEmpty
                                          ? 'Revisa los números de tu agenda.'
                                          : 'Prueba con otro nombre o número.',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final c = visible[index];
                              final exists = _existing.contains(c.phone);
                              final selected = _selected.contains(c.phone);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Material(
                                  color: selected
                                      ? colors.primaryContainer.withValues(
                                          alpha: 0.45,
                                        )
                                      : colors.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: exists
                                          ? colors.surfaceContainerHighest
                                          : colors.secondaryContainer,
                                      foregroundColor:
                                          colors.onSecondaryContainer,
                                      child: exists
                                          ? const Icon(
                                              Icons.person_outline_rounded,
                                            )
                                          : Text(
                                              c.name.characters.first
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                    ),
                                    title: Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${c.phone}${exists ? ' · Ya es cliente' : ''}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: exists
                                        ? Icon(
                                            Icons.check_circle_outline_rounded,
                                            color: colors.outline,
                                          )
                                        : Checkbox(
                                            value: selected,
                                            shape: const CircleBorder(),
                                            onChanged: _saving
                                                ? null
                                                : (_) => _toggle(c),
                                          ),
                                    onTap: _saving || exists
                                        ? null
                                        : () => _toggle(c),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 16,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                top: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                if (_review)
                  IconButton(
                    tooltip: 'Cambiar selección',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _review = false;
                            _search = '';
                          }),
                  ),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _saving || _selected.isEmpty
                        ? null
                        : _review
                        ? _save
                        : () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _review = true;
                              _search = '';
                            });
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _review
                                ? Icons.person_add_alt_1_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                    label: Text(
                      _saving
                          ? 'Importando…'
                          : _review
                          ? 'Importar (${_selected.length})'
                          : 'Continuar (${_selected.length})',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
