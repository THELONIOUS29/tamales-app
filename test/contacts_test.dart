import 'package:app_tamales/data/phone_contacts.dart';
import 'package:app_tamales/data/sales_repository.dart';
import 'package:app_tamales/screens/import_contacts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'sales_test.dart' show MemorySales;

class ContactRepository extends MemorySales {
  final rows = <RecordData>[
    {'id': 'old', 'name': 'Ana', 'phone': 'TELEFONO_DE_EJEMPLO'},
  ];
  bool fail = false;
  @override
  Future<List<RecordData>> clients() async => rows;
  @override
  Future<RecordData> saveClient(
    RecordData data, {
    required bool creating,
  }) async {
    if (fail && rows.length == 2) {
      fail = false;
      throw Exception('disk');
    }
    rows.removeWhere((r) => r['id'] == data['id']);
    rows.add({...data});
    return data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PhoneContacts.channel,
          (call) async => [
            {'name': 'Ana', 'phone': '099 999 9999'},
            {'name': 'Beto', 'phone': 'TELEFONO_DE_EJEMPLO'},
            {'name': 'Duplicado', 'phone': 'TELEFONO_DE_EJEMPLO'},
            {'name': 'Carla', 'phone': '+1 (202) 555-0123'},
            {'name': 'Invalido', 'phone': '123'},
          ],
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PhoneContacts.channel, null),
  );
  test(
    'Normalizes Ecuador and international phones without guessing ambiguous numbers',
    () {
      expect(contactPhone('099 999-9999'), 'TELEFONO_DE_EJEMPLO');
      expect(contactPhone('02 234 5678'), '+59322345678');
      expect(contactPhone('0051 987 654 321'), '+51987654321');
      expect(contactPhone('+1 (202) 555-0123'), '+12025550123');
      expect(contactPhone('999999999'), isNull);
      expect(contactPhone('TELEFONO_DE_EJEMPLO ext 2'), isNull);
    },
  );
  test(
    'Deduplicates equivalent phone entries and excludes invalid phones',
    () async {
      final contacts = await PhoneContacts.read();
      expect(contacts.length, 3);
      expect(contacts.map((c) => c.name), ['Ana', 'Beto', 'Carla']);
    },
  );
  test('Finds local and formatted international phone fragments', () {
    final c = PhoneContact('Beto', 'TELEFONO_DE_EJEMPLO');
    expect(c.matches('098 765'), isTrue);
    expect(c.matches('+593 98'), isTrue);
    expect(c.matches('beto'), isTrue);
    expect(c.matches('zz'), isFalse);
  });
  testWidgets(
    'Multiple selection, review, partial failure and retry preserve saved clients without duplicates',
    (tester) async {
      final repo = ContactRepository()..fail = true;
      await tester.pumpWidget(
        MaterialApp(home: ImportContactsScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Ya es cliente'), findsOneWidget);
      await tester.tap(find.text('Seleccionar todos'));
      await tester.pump();
      await tester.tap(find.text('Continuar (2)'));
      await tester.pumpAndSettle();
      expect(repo.rows.length, 1);
      await tester.tap(find.text('Importar (2)'));
      await tester.pumpAndSettle();
      expect(repo.rows.length, 2);
      expect(find.textContaining('Se guardaron 1 contacto(s)'), findsOneWidget);
      await tester.tap(find.text('Importar (1)'));
      await tester.pumpAndSettle();
      expect(repo.rows.length, 3);
      expect(repo.rows.map((r) => r['phone']).toSet().length, 3);
      expect(repo.rows.last['name'], 'Carla');
    },
  );
  testWidgets('Permission denial offers retry and settings without importing', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PhoneContacts.channel,
          (_) async => throw PlatformException(code: 'permission_denied'),
        );
    final repo = ContactRepository();
    await tester.pumpWidget(
      MaterialApp(home: ImportContactsScreen(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Abrir ajustes'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(repo.rows.length, 1);
  });
}
