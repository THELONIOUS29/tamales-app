import 'package:flutter/material.dart';
import 'dart:async';

import '../data/offline_repository.dart';
import 'clients_screen.dart';
import 'sales_screen.dart';
import 'dashboard_screen.dart';
import '../data/delivery_session.dart';
import '../data/delivery_notifications.dart';
import 'delivery_screen.dart';
import 'sync_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.ownerId});
  final String ownerId;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  late final Future<OfflineRepository> _opening;
  OfflineRepository? _repository;
  Widget? _clients;
  Widget? _sales;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _opening = OfflineRepository.open(widget.ownerId).then((repository) async {
      _repository = repository;
      activeOfflineRepository.value = repository;
      final session = DeliverySession(repository);
      activeDeliverySession = session;
      await session.initialize();
      DeliveryNotifications.listen(_openDelivery);
      final pending = await DeliveryNotifications.pendingSale();
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openDelivery(pending),
        );
      }
      return repository;
    });
  }

  bool _openingDelivery = false;
  Future<void> _openDelivery(String id) async {
    if (_openingDelivery || _repository == null || !mounted) return;
    _openingDelivery = true;
    try {
      final sale = await _repository!.sale(id);
      if (mounted) {
        await appNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) =>
                DeliveryScreen(repository: _repository!, sale: sale),
          ),
        );
      }
    } catch (_) {
      /* A deleted or inaccessible sale cannot be opened. */
    } finally {
      _openingDelivery = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _repository?.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final repository = _repository;
    if (repository != null) {
      if (activeOfflineRepository.value == repository) {
        activeOfflineRepository.value = null;
      }
      activeDeliverySession?.dispose();
      activeDeliverySession = null;
      repository.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<OfflineRepository>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(
            child: Text(
              'No se pudo abrir el almacenamiento del teléfono. Cierra y vuelve a abrir la app.',
            ),
          ),
        );
      }
      final repository = snapshot.data;
      if (repository == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            DashboardScreen(
              repository: repository,
              onShowSales: () => setState(() {
                _tab = 1;
                _sales ??= SalesScreen(repository: repository);
              }),
            ),
            _sales ?? const SizedBox.shrink(),
            _clients ?? const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() {
            _tab = value;
            if (value == 1) _sales ??= SalesScreen(repository: repository);
            if (value == 2) _clients ??= ClientsScreen(repository: repository);
          }),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'Ventas',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              label: 'Clientes',
            ),
          ],
        ),
      );
    },
  );
}
