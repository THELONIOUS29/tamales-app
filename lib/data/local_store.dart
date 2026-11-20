import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'sales_repository.dart';

const syncTables = ['clients', 'sales', 'orders', 'payments', 'expenses'];

class LocalMutation {
  LocalMutation({
    required this.sequence,
    required this.id,
    required this.table,
    required this.recordId,
    required this.kind,
    required this.payload,
    this.baseVersion,
    this.error,
  });
  final int sequence;
  final String id, table, recordId, kind;
  final RecordData payload;
  final String? baseVersion, error;
  factory LocalMutation.fromRow(RecordData row) => LocalMutation(
    sequence: row['seq'] as int,
    id: row['mutation_id'] as String,
    table: row['table_name'] as String,
    recordId: row['record_id'] as String,
    kind: row['kind'] as String,
    payload: jsonDecode(row['payload'] as String) as RecordData,
    baseVersion: row['base_version'] as String?,
    error: row['error'] as String?,
  );
}

/// Cada fila remota y cada operación pendiente son persistentes. Las vistas
/// locales se obtienen superponiendo la cola sobre el último estado del servidor.
class LocalStore {
  LocalStore(this.db);
  final Database db;
  static Future<LocalStore> open(String ownerId) async {
    final file = path.join(await getDatabasesPath(), 'tamales_$ownerId.sqlite');
    return LocalStore(
      await openDatabase(file, version: 1, onCreate: createSchema),
    );
  }

  static Future<void> createSchema(Database db, int version) async {
    await db.execute(
      'CREATE TABLE records (table_name TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(table_name,id))',
    );
    await db.execute(
      'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, mutation_id TEXT NOT NULL UNIQUE, table_name TEXT NOT NULL, record_id TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, base_version TEXT, error TEXT)',
    );
    await db.execute(
      'CREATE INDEX outbox_record ON outbox(table_name,record_id,seq)',
    );
  }

  Future<String?> meta(String key) async {
    final rows = await db.query('metadata', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> setMeta(String key, String value) async {
    await db.insert('metadata', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<RecordData?> remote(String table, String id) async {
    final rows = await db.query(
      'records',
      where: 'table_name=? AND id=?',
      whereArgs: [table, id],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['data'] as String) as RecordData;
  }

  Future<List<LocalMutation>> queue() async => (await db.query(
    'outbox',
    orderBy: 'seq',
  )).map(LocalMutation.fromRow).toList();

  Future<List<RecordData>> rows(String table) => db.transaction((tx) async {
    final server = await tx.query(
      'records',
      where: 'table_name=?',
      whereArgs: [table],
    );
    final pending = (await tx.query(
      'outbox',
      orderBy: 'seq',
    )).map(LocalMutation.fromRow).toList();
    return _project(table, server, pending);
  });

  /// All dashboard figures use one SQLite snapshot, including queued edits and
  /// deletions. No network request or separate query per sale is necessary.
  Future<Map<String, List<RecordData>>> snapshot() =>
      db.transaction((tx) async {
        final server = await tx.query('records');
        final pending = (await tx.query(
          'outbox',
          orderBy: 'seq',
        )).map(LocalMutation.fromRow).toList();
        return {
          for (final table in syncTables)
            table: _project(
              table,
              server.where((r) => r['table_name'] == table).toList(),
              pending,
            ),
        };
      });

  List<RecordData> _project(
    String table,
    List<RecordData> server,
    List<LocalMutation> pending,
  ) {
    final combined = <String, RecordData>{
      for (final row in server)
        row['id'] as String: jsonDecode(row['data'] as String) as RecordData,
    };
    for (final operation in pending) {
      if (operation.kind == 'delete_tree') {
        final graph = operation.payload['_expected'] as Map;
        if (operation.table == table) combined.remove(operation.recordId);
        for (final row in graph[table] as List? ?? []) {
          combined.remove((row as Map)['id']);
        }
        continue;
      }
      if (operation.table != table) continue;
      if (operation.kind == 'delete') {
        combined.remove(operation.recordId);
      } else {
        combined[operation.recordId] = {
          ...?combined[operation.recordId],
          ...operation.payload,
          'id': operation.recordId,
          '_sync_pending': true,
          if (operation.error != null) '_sync_error': operation.error,
        };
      }
    }
    return combined.values.toList();
  }

  Future<void> enqueue({
    required String mutationId,
    required String table,
    required String id,
    required String kind,
    required RecordData payload,
  }) async {
    await db.transaction((tx) async {
      final existing = await tx.query(
        'records',
        where: 'table_name=? AND id=?',
        whereArgs: [table, id],
      );
      final remote = existing.isEmpty
          ? null
          : jsonDecode(existing.single['data'] as String) as RecordData;
      await tx.insert('outbox', {
        'mutation_id': mutationId,
        'table_name': table,
        'record_id': id,
        'kind': kind,
        'payload': jsonEncode(payload),
        'base_version': remote?['updated_at'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<void> bootstrap(RecordData snapshot) async {
    await db.transaction((tx) async {
      await tx.delete('records');
      final tables = snapshot['tables'] as Map;
      final batch = tx.batch();
      for (final table in syncTables) {
        for (final raw in (tables[table] as List? ?? [])) {
          final row = Map<String, dynamic>.from(raw as Map);
          batch.insert('records', {
            'table_name': table,
            'id': row['id'],
            'data': jsonEncode(row),
          });
        }
      }
      batch.insert('metadata', {
        'key': 'cursor',
        'value': '${snapshot['cursor']}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      batch.insert('metadata', {
        'key': 'initialized',
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }

  Future<void> applyChanges(List<RecordData> events) async {
    if (events.isEmpty) return;
    await db.transaction((tx) async {
      final batch = tx.batch();
      for (final event in events) {
        if (event['record_data'] == null) {
          batch.delete(
            'records',
            where: 'table_name=? AND id=?',
            whereArgs: [event['table_name'], event['record_id']],
          );
        } else {
          batch.insert('records', {
            'table_name': event['table_name'],
            'id': event['record_id'],
            'data': jsonEncode(event['record_data']),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      batch.insert('metadata', {
        'key': 'cursor',
        'value': '${events.last['sequence']}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }

  Future<void> acknowledge(LocalMutation mutation, RecordData? record) async {
    await db.transaction((tx) async {
      if (mutation.kind == 'delete_tree') {
        final graph = mutation.payload['_expected'] as Map;
        for (final table in ['orders', 'payments', 'expenses']) {
          for (final row in graph[table] as List? ?? []) {
            await tx.delete(
              'records',
              where: 'table_name=? AND id=?',
              whereArgs: [table, (row as Map)['id']],
            );
          }
        }
      }
      if (record == null) {
        await tx.delete(
          'records',
          where: 'table_name=? AND id=?',
          whereArgs: [mutation.table, mutation.recordId],
        );
      } else {
        final clean = {...record}
          ..removeWhere((key, value) => key.startsWith('_sync'));
        await tx.insert('records', {
          'table_name': mutation.table,
          'id': mutation.recordId,
          'data': jsonEncode(clean),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await tx.delete('outbox', where: 'seq=?', whereArgs: [mutation.sequence]);
      if (record?['_sync_rebase'] != false) {
        await tx.update(
          'outbox',
          {'base_version': record?['updated_at']},
          where: 'table_name=? AND record_id=? AND seq>?',
          whereArgs: [mutation.table, mutation.recordId, mutation.sequence],
        );
      }
    });
  }

  Future<void> fail(int sequence, String error) => db.update(
    'outbox',
    {'error': error},
    where: 'seq=?',
    whereArgs: [sequence],
  );
  Future<void> retry(int sequence) => db.update(
    'outbox',
    {'error': null},
    where: 'seq=?',
    whereArgs: [sequence],
  );
  Future<void> discard(int sequence) =>
      db.delete('outbox', where: 'seq=?', whereArgs: [sequence]);
  Future<void> close() => db.close();
}
