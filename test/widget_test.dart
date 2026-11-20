import 'package:app_tamales/main.dart';
import 'package:app_tamales/screens/device_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Explains missing configuration without initializing Supabase', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TamalesApp(
        startupError: 'Falta configurar la conexión con Supabase.',
      ),
    );
    expect(
      find.text('Falta configurar la conexión con Supabase.'),
      findsOneWidget,
    );
  });

  testWidgets('Unapproved device has no access and no login form', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: DeviceGate(resolveOwner: () async => null)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('autorización inicial'), findsOneWidget);
    expect(find.text('Clientes'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('Connection failure allows a new authorization check', (
    tester,
  ) async {
    var attempts = 0;
    Future<String?> resolve() async {
      attempts++;
      if (attempts == 1) throw Exception('offline');
      return null;
    }

    await tester.pumpWidget(
      MaterialApp(home: DeviceGate(resolveOwner: resolve)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('autorización inicial'), findsOneWidget);
  });
}
