import 'dart:async';

import 'package:flutter/material.dart';
import '../data/sales_repository.dart';
import '../data/offline_repository.dart';

mixin RepositoryObserver<T extends StatefulWidget> on State<T> {
  SalesRepository get observedRepository;
  Future<void> reloadRepository();
  Future<void> refreshRepository() async {
    final repository = observedRepository;
    if (repository is OfflineRepository) await repository.synchronize();
    if (mounted) await reloadRepository();
  }

  Listenable? _observed;
  @override
  void initState() {
    super.initState();
    final repository = observedRepository;
    if (repository is Listenable) {
      _observed = repository as Listenable;
      _observed!.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) unawaited(reloadRepository());
  }

  @override
  void dispose() {
    _observed?.removeListener(_changed);
    super.dispose();
  }
}
