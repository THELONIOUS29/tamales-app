import 'package:supabase_flutter/supabase_flutter.dart';

import 'finances.dart';
import 'local_store.dart';
import 'sales_repository.dart';

class SyncConflict implements Exception {
  SyncConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class SyncGateway {
  Future<String?> authorizedOwner();
  Future<RecordData> bootstrap();
  Future<List<RecordData>> changes(int after);
  Future<RecordData?> push(LocalMutation mutation);
  Future<RecordData> deletionPreview(String table, String id) =>
      throw UnimplementedError();
}

class SupabaseSyncGateway implements SyncGateway {
  SupabaseSyncGateway(this.ownerId);
  final String ownerId;
  final _db = Supabase.instance.client;

  @override
  Future<String?> authorizedOwner() async {
    final session = _db.auth.currentSession;
    if (session != null && session.isExpired) await _db.auth.refreshSession();
    return await _db.rpc('device_owner') as String?;
  }

  @override
  Future<RecordData> bootstrap() async =>
      Map<String, dynamic>.from(await _db.rpc('sync_bootstrap') as Map);
  @override
  Future<List<RecordData>> changes(int after) async =>
      (await _db.rpc('sync_changes', params: {'p_after': after, 'p_limit': 500})
              as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

  @override
  Future<RecordData> deletionPreview(String table, String id) async =>
      Map<String, dynamic>.from(
        await _db.rpc(
              'deletion_preview',
              params: {'p_table': table, 'p_id': id},
            )
            as Map,
      );

  Future<RecordData?> _read(String table, String id) =>
      _db.from(table).select().eq('id', id).maybeSingle();
  bool _matches(RecordData row, RecordData payload) =>
      payload.entries.every((entry) {
        if (entry.key.startsWith('_') || entry.key == 'created_at') return true;
        final actual = row[entry.key];
        if (entry.key == 'available_from' || entry.key == 'available_until') {
          return actual?.toString().substring(0, 5) ==
              entry.value?.toString().substring(0, 5);
        }
        return actual == entry.value;
      });

  @override
  Future<RecordData?> push(LocalMutation mutation) async {
    final payload = Map<String, dynamic>.from(mutation.payload)
      ..removeWhere((key, value) => key.startsWith('_') || key == 'created_at');
    try {
      if (mutation.kind == 'delete_tree') {
        await _db.rpc(
          'delete_business_record',
          params: {
            'p_table': mutation.table,
            'p_id': mutation.recordId,
            'p_expected': mutation.payload['_expected'],
          },
        );
        return null;
      }
      if (mutation.kind == 'payment') {
        final result = await _db.rpc(
          'record_payment',
          params: {
            'p_id': mutation.recordId,
            'p_order_id': payload['order_id'],
            'p_amount_cents': payload['amount_cents'],
            'p_paid_at': payload['paid_at'],
            'p_method': payload['method'],
            'p_notes': payload['notes'],
            'p_settle': false,
          },
        );
        if (result is Map) return Map<String, dynamic>.from(result);
        if (result is List && result.isNotEmpty) {
          return Map<String, dynamic>.from(result.first as Map);
        }
        return await _read('payments', mutation.recordId);
      }
      var current = await _read(mutation.table, mutation.recordId);
      if (mutation.kind == 'delete') {
        if (current == null) {
          return null; // Reintento de una eliminación ya confirmada.
        }
        if (current['updated_at'] != mutation.baseVersion) {
          throw SyncConflict(
            'Otro teléfono modificó este registro antes de su eliminación. Revisa la versión actual.',
          );
        }
        final removed = await _db
            .from(mutation.table)
            .delete()
            .eq('id', mutation.recordId)
            .eq('updated_at', mutation.baseVersion!)
            .select('id');
        if (removed.isEmpty &&
            await _read(mutation.table, mutation.recordId) != null) {
          throw SyncConflict(
            'El registro cambió mientras se eliminaba. Actualiza y revisa.',
          );
        }
        return null;
      }
      if (current == null && mutation.kind == 'create') {
        try {
          return await _db
              .from(mutation.table)
              .insert({
                ...payload,
                'id': mutation.recordId,
                'owner_id': ownerId,
              })
              .select()
              .single();
        } on PostgrestException catch (error) {
          if (error.code != '23505') rethrow;
          current = await _read(mutation.table, mutation.recordId);
        }
      }
      // Si se perdió la respuesta de una escritura, se acepta el mismo resultado
      // sin volver a sobrescribir campos modificados por otro teléfono.
      if (current != null && _matches(current, payload)) {
        return {...current, '_sync_rebase': mutation.kind == 'create'};
      }
      if (current == null ||
          current['updated_at'] != mutation.baseVersion ||
          mutation.kind == 'create') {
        throw SyncConflict(
          'Otro teléfono cambió o eliminó este registro. El cambio local necesita revisión.',
        );
      }
      final updated = await _db
          .from(mutation.table)
          .update(payload)
          .eq('id', mutation.recordId)
          .eq('updated_at', mutation.baseVersion!)
          .select();
      if (updated.isEmpty) {
        throw SyncConflict(
          'El registro cambió durante el guardado. Revisa el cambio pendiente.',
        );
      }
      return updated.single;
    } on PostgrestException catch (error) {
      if (error.message.contains('delete_graph_changed')) {
        throw SyncConflict(
          'La venta o el pedido cambió desde que confirmaste la eliminación. Descarta esta eliminación y vuelve a eliminar para revisar los importes actuales.',
        );
      }
      if (['23514', '23503', '23505'].contains(error.code)) {
        throw SyncConflict(
          financeError(
            error,
            'No se pudo aceptar este cambio. Revisa los importes y registros relacionados.',
          ),
        );
      }
      rethrow;
    }
  }
}
