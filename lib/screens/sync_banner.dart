import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/offline_repository.dart';
import '../data/sales_repository.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

class SyncFrame extends StatelessWidget {
  const SyncFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<OfflineRepository?>(
    valueListenable: activeOfflineRepository,
    builder: (context, repository, _) {
      if (repository == null) return child;
      return AnimatedBuilder(
        animation: repository,
        builder: (context, _) => SafeArea(
          bottom: false,
          child: Column(
            children: [
              SyncBanner(repository: repository),
              Expanded(
                child: Stack(
                  children: [
                    Offstage(offstage: repository.revoked, child: child),
                    if (repository.revoked)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Este teléfono necesita autorización de nuevo. Los cambios pendientes siguen guardados aquí.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.repository});
  final OfflineRepository repository;
  @override
  Widget build(BuildContext context) {
    final pending = repository.pendingCount;
    final conflicts = repository.conflicts.length;
    final warning = repository.revoked || conflicts > 0 || pending > 0;
    final label = repository.revoked
        ? 'Teléfono sin autorización'
        : conflicts > 0
        ? '$conflicts cambio(s) necesitan revisión'
        : pending > 0
        ? 'Guardado aquí · $pending cambio(s) por enviar'
        : repository.syncing
        ? 'Sincronizando…'
        : !repository.initialized
        ? 'Conéctate una vez para descargar tus datos'
        : repository.online
        ? 'Sincronizado'
        : 'Sin conexión · datos guardados aquí';
    return Material(
      color: warning ? const Color(0xFFFFE7B5) : const Color(0xFFE7EEDD),
      child: InkWell(
        onTap: () {
          if (repository.revoked) {
            unawaited(repository.synchronize());
          } else if (pending > 0) {
            appNavigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => SyncQueueScreen(repository: repository),
              ),
            );
          } else {
            unawaited(repository.synchronize());
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Icon(
                conflicts > 0
                    ? Icons.warning_amber
                    : repository.online
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (repository.syncing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(pending > 0 ? Icons.chevron_right : Icons.sync, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

String entityLabel(String table) => switch (table) {
  'clients' => 'Cliente',
  'sales' => 'Venta',
  'orders' => 'Pedido',
  'payments' => 'Cobro',
  'expenses' => 'Gasto',
  _ => 'Registro',
};

class SyncQueueScreen extends StatelessWidget {
  const SyncQueueScreen({super.key, required this.repository});
  final OfflineRepository repository;

  Future<void> _discard(BuildContext context, LocalMutation operation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar este cambio local'),
        content: const Text(
          'Se quitará este cambio pendiente del teléfono y se conservará lo que tenga Supabase. Otros cambios relacionados podrían necesitar revisión. No se eliminarán datos del servidor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar cambio'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.discard(operation);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Cambios guardados en el teléfono')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Los cambios se enviarán en orden cuando haya conexión y la app esté abierta. Si un cobro supera el saldo de Supabase, se conservará aquí para revisarlo.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: repository.syncing ? null : repository.synchronize,
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar ahora'),
          ),
          if (repository.lastError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(repository.lastError!),
            ),
          if (repository.operations.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No quedan cambios pendientes.'),
            ),
          for (final operation in repository.operations)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entityLabel(operation.table)} · ${operation.kind.startsWith('delete') ? 'eliminación' : 'guardado'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (operation.payload['name'] != null)
                      Text(operation.payload['name'] as String),
                    if (operation.payload['description'] != null)
                      Text(operation.payload['description'] as String),
                    if (operation.payload['amount_cents'] != null)
                      Text(
                        'Importe: ${decimalPrice(operation.payload['amount_cents'] as int)}',
                      ),
                    Text(operation.error ?? 'Pendiente de enviar'),
                    if (operation.error != null)
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: repository.syncing
                                ? null
                                : () => repository.retry(operation),
                            child: const Text('Reintentar'),
                          ),
                          TextButton(
                            onPressed: repository.syncing
                                ? null
                                : () => _discard(context, operation),
                            child: const Text('Descartar este cambio'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
