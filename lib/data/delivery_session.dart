import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'delivery.dart';
import 'delivery_notifications.dart';
import 'finances.dart';
import 'offline_repository.dart';
import 'sales_repository.dart';

/// Only one phone is the courier. Its itinerary survives closing the app;
/// orders, delivery flags and payments continue to sync across all phones.
class DeliverySession extends ChangeNotifier {
  DeliverySession(this.repository);
  final OfflineRepository repository;
  RecordData? settings;
  bool _disposed = false, _refreshing = false, _again = false;
  Future<void> initialize() async {
    final raw = await repository.store.meta('active_delivery');
    if (raw != null && raw.isNotEmpty) settings = jsonDecode(raw) as RecordData;
    repository.addListener(refresh);
    await refresh();
  }

  Future<void> start(RecordData value) async {
    await repository.store.setMeta('active_delivery', jsonEncode(value));
    settings = value;
    await refresh();
  }

  Future<void> stop() async {
    await repository.store.setMeta('active_delivery', '');
    settings = null;
    await DeliveryNotifications.cancel();
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_refreshing) {
      _again = true;
      return;
    }
    _refreshing = true;
    try {
      final data = settings;
      if (data == null || repository.revoked) {
        await DeliveryNotifications.cancel();
        return;
      }
      final orders = await repository.orders(data['sale_id'] as String);
      final ids = (data['ids'] as List).cast<String>();
      final byId = {for (final o in orders) o['id']: o};
      final pending = ids
          .map((id) => byId[id])
          .whereType<RecordData>()
          .where((o) => o['delivered'] != true)
          .toList();
      if (pending.isEmpty) {
        await stop();
        return;
      }
      final first = pending.first;
      final client = first['clients'] as Map? ?? {};
      final p = coordinates(first);
      await DeliveryNotifications.show(
        saleId: data['sale_id'] as String,
        title: 'Siguiente: ${client['name'] ?? 'Cliente'}',
        body:
            '${first['pork_quantity']} chancho · ${first['chicken_quantity']} pollo\n'
            'Por cobrar: ${money(balanceFor(first), data['currency'] as String)}\n'
            '${first['delivery_address'] ?? ''}\nQuedan ${pending.length} entregas',
        destination: p == null
            ? (first['delivery_address'] as String? ?? '')
            : '${p.latitude},${p.longitude}',
      );
    } finally {
      _refreshing = false;
      if (!_disposed) notifyListeners();
      if (_again && !_disposed) {
        _again = false;
        unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    repository.removeListener(refresh);
    super.dispose();
  }
}

DeliverySession? activeDeliverySession;
