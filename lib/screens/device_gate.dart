import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';

/// Identifica la instalación sin formularios ni credenciales incorporadas.
/// El administrador autoriza esta identidad en Supabase una sola vez.
class DeviceGate extends StatefulWidget {
  const DeviceGate({super.key, this.resolveOwner});
  final Future<String?> Function()? resolveOwner;

  @override
  State<DeviceGate> createState() => _DeviceGateState();
}

class _DeviceGateState extends State<DeviceGate> {
  late Future<String?> _access;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _access = _resolve();
  }

  Future<String?> _resolve() => widget.resolveOwner?.call() ?? _connect();

  Future<String?> _connect() async {
    final db = Supabase.instance.client;
    if (db.auth.currentSession == null) {
      await db.auth.signInAnonymously();
    }
    _deviceId = db.auth.currentUser!.id;
    final preferences = await SharedPreferences.getInstance();
    final cacheKey = 'authorized_owner_$_deviceId';
    final cachedOwner = preferences.getString(cacheKey);
    if (cachedOwner != null) return cachedOwner;
    final owner =
        await db.rpc('device_owner').timeout(const Duration(seconds: 10))
            as String?;
    if (owner != null) await preferences.setString(cacheKey, owner);
    return owner;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _access,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasError && snapshot.data != null) {
          return HomeScreen(ownerId: snapshot.data!);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Tamales')),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? 'No se pudo conectar. Revisa internet y la configuración inicial de Supabase.'
                        : 'Este teléfono necesita autorización inicial para acceder a los datos del negocio.',
                  ),
                  if (_deviceId != null) ...[
                    const SizedBox(height: 16),
                    const Text('Identificador de este teléfono:'),
                    SelectableText(_deviceId!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      final nextAccess = _resolve();
                      setState(() {
                        _access = nextAccess;
                      });
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
