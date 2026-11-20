import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/device_gate.dart';
import 'screens/sync_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  String? startupError;
  if (url.isEmpty || key.isEmpty) {
    startupError = 'Falta configurar la conexión con Supabase.';
  } else {
    try {
      await Supabase.initialize(url: url, publishableKey: key);
    } catch (_) {
      startupError = 'No se pudo iniciar la conexión. Cierra y abre la app.';
    }
  }
  runApp(TamalesApp(startupError: startupError));
}

class TamalesApp extends StatelessWidget {
  const TamalesApp({super.key, this.startupError});
  final String? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tamales',
      navigatorKey: appNavigatorKey,
      builder: (context, child) => SyncFrame(child: child!),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF426B35)),
        scaffoldBackgroundColor: const Color(0xFFFFFBF3),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        useMaterial3: true,
      ),
      home: startupError != null
          ? Scaffold(body: Center(child: Text(startupError!)))
          : const DeviceGate(),
    );
  }
}
