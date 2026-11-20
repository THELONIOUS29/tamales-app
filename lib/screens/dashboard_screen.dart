import 'dart:async';
import 'package:flutter/material.dart';
import '../data/dashboard.dart';
import '../data/finances.dart';
import '../data/sales_repository.dart';
import 'repository_observer.dart';
import 'sale_detail_screen.dart';
import 'sales_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.repository,
    this.now,
    this.onShowSales,
  });
  final SalesRepository repository;
  final DateTime Function()? now;
  final VoidCallback? onShowSales;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, RepositoryObserver<DashboardScreen> {
  @override
  SalesRepository get observedRepository => widget.repository;
  @override
  Future<void> reloadRepository() => _load();
  DateTime get _now => (widget.now ?? DateTime.now)();
  late String _date = dateValue(_now);
  bool _followingToday = true, _busy = false, _again = false;
  DashboardData? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    if (_busy) {
      _again = true;
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      if (_followingToday) {
        final today = dateValue(_now);
        if (_date != today) _data = null;
        _date = today;
      }
    });
    try {
      final snapshot = await widget.repository.dashboardSnapshot();
      if (mounted) setState(() => _data = DashboardData(snapshot, _date));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = financeError(
            e,
            'No se pudo cargar el resumen. Vuelve a intentarlo.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_again) {
          _again = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _select(String date) async {
    setState(() {
      _date = date;
      _followingToday = date == dateValue(_now);
      _data = null;
    });
    await _load();
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (chosen != null && mounted) await _select(dateValue(chosen));
  }

  Future<void> _open(RecordData sale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SaleDetailScreen(sale: sale, repository: widget.repository),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final sale = await Navigator.push<RecordData>(
      context,
      MaterialPageRoute(
        builder: (_) => SaleEditor(repository: widget.repository),
      ),
    );
    if (sale == null || !mounted) return;
    await _select(sale['sale_date'] as String);
    if (mounted) await _open(sale);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(
            tooltip: 'Cómo se calcula',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => const SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.insights_rounded, size: 32),
                      SizedBox(height: 16),
                      Text(
                        'Tu resumen',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Ganancia = total vendido menos gastos. Disponible = cobrado menos gastos.',
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Los importes corresponden a las ventas de la fecha elegida, aunque sus cobros o gastos se registren otro día.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar resumen',
            onPressed: _busy ? null : refreshRepository,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshRepository,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tu día, de un vistazo',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ventas y reparto',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Nueva venta',
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_rounded, size: 20),
                    label: Text(
                      '${_date == dateValue(_now) ? 'Hoy · ' : ''}${dateLabel(_date)}',
                    ),
                  ),
                ),
                if (_date != dateValue(_now))
                  TextButton(
                    onPressed: () => _select(dateValue(_now)),
                    child: const Text('Hoy'),
                  ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            if (data != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _counter(
                    Icons.storefront_outlined,
                    '${data.selected.length} ventas',
                  ),
                  _counter(
                    Icons.receipt_long_outlined,
                    '${data.quantities.count} pedidos',
                  ),
                  _counter(
                    Icons.people_outline_rounded,
                    '${data.clientCount} clientes',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              for (final entry in data.finances.entries)
                _financialCard(entry.key, entry.value),
              _section('Preparación', Icons.restaurant_rounded),
              Row(
                children: [
                  Expanded(
                    child: _quantityCard(
                      'Chancho',
                      data.quantities.pork,
                      data.quantities.remainingPork,
                      Icons.restaurant_menu_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _quantityCard(
                      'Pollo',
                      data.quantities.chicken,
                      data.quantities.remainingChicken,
                      Icons.lunch_dining_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Entregas',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '${data.quantities.delivered} / ${data.quantities.count}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: data.quantities.count == 0
                            ? 0
                            : data.quantities.delivered / data.quantities.count,
                        minHeight: 7,
                        backgroundColor: colors.surfaceContainerHighest,
                      ),
                    ),
                    if (data.highPriority > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.priority_high_rounded,
                              size: 18,
                              color: colors.error,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${data.highPriority} con prioridad',
                              style: TextStyle(color: colors.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (data.selected.isEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_note_rounded,
                        size: 30,
                        color: colors.outline,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sin ventas en esta fecha',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (data.upcoming.isNotEmpty)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.centerLeft,
                                ),
                                onPressed: () => _select(
                                  data.upcoming.first.sale['sale_date']
                                      as String,
                                ),
                                child: Text(
                                  'Próxima: ${dateLabel(data.upcoming.first.sale['sale_date'] as String)}',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                _section('Ventas del día', Icons.storefront_outlined),
                for (final sale in data.selected) _saleCard(sale),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nueva venta'),
              ),
              if (data.previousPending.isNotEmpty) ...[
                _section('Pendientes anteriores', Icons.history_rounded),
                for (final sale in data.previousPending.take(5))
                  _saleCard(sale, pending: true),
                if (data.previousPending.length > 5 &&
                    widget.onShowSales != null)
                  TextButton(
                    onPressed: widget.onShowSales,
                    child: const Text('Ver todas las ventas'),
                  ),
              ],
              if (data.upcoming.isNotEmpty) ...[
                _section('Próximas ventas', Icons.event_available_outlined),
                for (final sale in data.upcoming.take(3)) _saleCard(sale),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _counter(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _section(String label, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _quantityCard(String label, int total, int remaining, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$total',
            key: ValueKey('quantity-$label'),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'por preparar',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text(
            '$remaining por entregar',
            style: TextStyle(
              fontSize: 12,
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _financialCard(String currency, FinancialTotals f) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.trending_up_rounded,
                      color: colors.onPrimary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ganancia',
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      currency,
                      style: TextStyle(
                        color: colors.onPrimary.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  money(f.result, currency),
                  key: ValueKey('result-$currency'),
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      color: colors.onPrimary.withValues(alpha: 0.8),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Disponible: ${money(f.cashBalance, currency)}',
                        style: TextStyle(
                          color: colors.onPrimary.withValues(alpha: 0.9),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _moneyTile(
                    width,
                    'Vendido',
                    f.sold,
                    currency,
                    Icons.shopping_bag_outlined,
                    colors.primary,
                  ),
                  _moneyTile(
                    width,
                    'Cobrado',
                    f.paid,
                    currency,
                    Icons.check_circle_outline_rounded,
                    colors.primary,
                  ),
                  _moneyTile(
                    width,
                    'Por cobrar',
                    f.pending,
                    currency,
                    Icons.schedule_rounded,
                    const Color(0xFF9A6200),
                  ),
                  _moneyTile(
                    width,
                    'Gastos',
                    f.spent,
                    currency,
                    Icons.receipt_outlined,
                    colors.error,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _moneyTile(
    double width,
    String label,
    int cents,
    String currency,
    IconData icon,
    Color color,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            money(cents, currency),
            key: ValueKey('money-$label-$currency'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _saleCard(SaleOverview s, {bool pending = false}) {
    final q = s.quantities, f = s.finances;
    final colors = Theme.of(context).colorScheme;
    final title = s.sale['title'] as String? ?? '';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: colors.secondaryContainer,
          child: Icon(
            pending ? Icons.history_rounded : Icons.storefront_outlined,
            color: colors.onSecondaryContainer,
          ),
        ),
        title: Text(
          title.isEmpty ? 'Venta de tamales' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${dateLabel(s.sale['sale_date'] as String)} · ${q.count - q.delivered} por entregar\nPor cobrar: ${money(f.pending, s.sale['currency'] as String)}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _open(s.sale),
      ),
    );
  }
}
