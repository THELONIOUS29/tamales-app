import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/delivery.dart';

Future<LatLng> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('Activa la ubicación del teléfono e inténtalo de nuevo.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw Exception(
      'Permite la ubicación en Ajustes > Aplicaciones > Tamales > Permisos.',
    );
  }
  if (permission == LocationPermission.denied) {
    throw Exception(
      'No se concedió el permiso de ubicación. Puedes escribir las coordenadas.',
    );
  }
  final location = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );
  return LatLng(location.latitude, location.longitude);
}

Future<void> openExternal(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    /* Explain unavailable apps without losing the current form. */
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No se pudo abrir. Comprueba que tienes una aplicación compatible.',
        ),
      ),
    );
  }
}

class ContactButtons extends StatelessWidget {
  const ContactButtons({super.key, required this.client, this.location});
  final Map client;
  final LatLng? location;
  @override
  Widget build(BuildContext context) {
    final phone = (client['phone'] as String? ?? '').trim();
    return Wrap(
      spacing: 8,
      children: [
        if (phone.isNotEmpty) ...[
          TextButton.icon(
            onPressed: () =>
                openExternal(context, Uri(scheme: 'tel', path: phone)),
            icon: const Icon(Icons.call_outlined),
            label: const Text('Llamar'),
          ),
          TextButton.icon(
            onPressed: () => openExternal(
              context,
              Uri.https('wa.me', phone.replaceAll(RegExp(r'\D'), '')),
            ),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
          ),
        ],
        if (location != null)
          TextButton.icon(
            onPressed: () => openExternal(
              context,
              Uri.https('www.google.com', '/maps/dir/', {
                'api': '1',
                'destination': '${location!.latitude},${location!.longitude}',
                'travelmode': 'driving',
              }),
            ),
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Navegar'),
          ),
      ],
    );
  }
}

class LocationField extends StatelessWidget {
  const LocationField({
    super.key,
    this.value,
    required this.onChanged,
    this.label = 'Ubicación',
  });
  final LatLng? value;
  final ValueChanged<LatLng?> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.place_outlined),
        title: Text(label),
        subtitle: Text(
          value == null
              ? 'Sin coordenadas: no se puede ordenar en la ruta.'
              : '${value!.latitude.toStringAsFixed(6)}, ${value!.longitude.toStringAsFixed(6)}',
        ),
        trailing: value == null
            ? null
            : IconButton(
                tooltip: 'Quitar ubicación',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.clear),
              ),
        onTap: () async {
          final result = await Navigator.push<LatLng>(
            context,
            MaterialPageRoute(builder: (_) => LocationEditor(initial: value)),
          );
          if (result != null) onChanged(result);
        },
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final result = await Navigator.push<LatLng>(
            context,
            MaterialPageRoute(builder: (_) => LocationEditor(initial: value)),
          );
          if (result != null) onChanged(result);
        },
        icon: const Icon(Icons.map_outlined),
        label: const Text('Elegir ubicación'),
      ),
      const SizedBox(height: 16),
    ],
  );
}

class LocationEditor extends StatefulWidget {
  const LocationEditor({super.key, this.initial});
  final LatLng? initial;
  @override
  State<LocationEditor> createState() => _LocationEditorState();
}

class _LocationEditorState extends State<LocationEditor> {
  late LatLng? _point = widget.initial;
  late final _text = TextEditingController(
    text: widget.initial == null
        ? ''
        : '${widget.initial!.latitude}, ${widget.initial!.longitude}',
  );
  final _map = MapController();
  bool _busy = false, _showMap = false;
  String? _error;
  void _select(LatLng point) {
    setState(() {
      _point = point;
      _text.text =
          '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
      _error = null;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _gps() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final point = await currentPosition();
      if (mounted) {
        _select(point);
        if (_showMap) _map.move(point, 17);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ubicación de entrega')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Pega latitud, longitud o un enlace de Google Maps con query=latitud,longitud. Los enlaces cortos deben abrirse primero en Maps para copiar las coordenadas del punto.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          decoration: const InputDecoration(
            labelText: 'Coordenadas o enlace',
            hintText: '-2.170998, -79.922359',
          ),
          onChanged: (_) => _point = null,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            final p = parseLocation(_text.text);
            if (p == null) {
              setState(
                () => _error =
                    'Ingresa una latitud entre −90 y 90 y longitud entre −180 y 180.',
              );
            } else {
              _select(p);
              if (_showMap) _map.move(p, 17);
            }
          },
          child: const Text('Usar coordenadas'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _gps,
          icon: const Icon(Icons.my_location),
          label: Text(
            _busy ? 'Obteniendo ubicación…' : 'Usar mi ubicación actual',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mostrar mapa'),
          subtitle: const Text(
            'Consume datos solo al abrirlo. Toca el lugar de entrega.',
          ),
          value: _showMap,
          onChanged: (v) => setState(() => _showMap = v),
        ),
        if (_showMap)
          SizedBox(
            height: 320,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _point ?? const LatLng(-1.8312, -78.1834),
                initialZoom: _point == null ? 6 : 16,
                onTap: (_, p) => _select(p),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.tamales.app_tamales',
                  panBuffer: 0,
                  tileProvider: NetworkTileProvider(
                    cachingProvider:
                        BuiltInMapCachingProvider.getOrCreateInstance(
                          maxCacheSize: 32 * 1024 * 1024,
                        ),
                  ),
                ),
                if (_point != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _point!,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 42,
                        ),
                      ),
                    ],
                  ),
                SimpleAttributionWidget(
                  alignment: Alignment.topLeft,
                  source: const Text(
                    'OpenStreetMap contributors',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => openExternal(
                    context,
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                  ),
                ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  final p = parseLocation(_text.text) ?? _point;
                  if (p == null) {
                    setState(
                      () => _error =
                          'Selecciona un punto o ingresa coordenadas válidas.',
                    );
                    return;
                  }
                  Navigator.pop(context, p);
                },
          child: const Text('Guardar ubicación'),
        ),
      ],
    ),
  );
}
