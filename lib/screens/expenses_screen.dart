import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/sales_repository.dart';
import 'payments_screen.dart';
import 'repository_observer.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({
    super.key,
    required this.repository,
    required this.sale,
  });
  final SalesRepository repository;
  final RecordData sale;
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with RepositoryObserver<ExpensesScreen> {
  @override
  SalesRepository get observedRepository => widget.repository;
  @override
  Future<void> reloadRepository() => _load();
  List<RecordData> _expenses = [];
  bool _loading = false, _deleting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.expenses(
        widget.sale['id'] as String,
      );
      if (mounted) setState(() => _expenses = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'No se pudieron cargar los gastos. Revisa la conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([RecordData? expense]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEditor(
          repository: widget.repository,
          sale: widget.sale,
          expense: expense,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _remove(RecordData expense) async {
    if (!await confirmRemoval(
      context,
      'Se eliminará este gasto y se recalculará el resultado de la venta.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.deleteExpense(expense['id'] as String);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo confirmar la eliminación. Actualiza la lista.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold<int>(
      0,
      (sum, e) => sum + (e['amount_cents'] as int),
    );
    final currency = widget.sale['currency'] as String;
    final busy = _loading || _deleting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos de la venta'),
        actions: [
          IconButton(
            onPressed: busy ? null : refreshRepository,
            tooltip: 'Actualizar gastos',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshRepository,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Text(dateLabel(widget.sale['sale_date'] as String)),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (!_loading && _error == null)
              Text(
                'Total de gastos: ${money(total, currency)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            const SizedBox(height: 20),
            if (!_loading && _expenses.isEmpty && _error == null)
              const Text(
                'Registra las compras de ingredientes, transporte y otros gastos de esta preparación.',
              ),
            for (final expense in _expenses)
              Card(
                child: ListTile(
                  title: Text(money(expense['amount_cents'] as int, currency)),
                  subtitle: Text(
                    '${(expense['description'] as String).isEmpty ? 'Sin descripción' : expense['description']}\n${dateLabel(expense['spent_on'] as String)}',
                  ),
                  onTap: busy ? null : () => _edit(expense),
                  trailing: IconButton(
                    tooltip: 'Eliminar gasto',
                    onPressed: busy ? null : () => _remove(expense),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            if (_error != null)
              TextButton(
                onPressed: refreshRepository,
                child: const Text('Reintentar'),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo gasto'),
      ),
    );
  }
}

class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({
    super.key,
    required this.repository,
    required this.sale,
    this.expense,
  });
  final SalesRepository repository;
  final RecordData sale;
  final RecordData? expense;
  @override
  State<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<ExpenseEditor> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.expense?['id'] as String? ?? const Uuid().v4();
  late final _amount = TextEditingController(
    text: widget.expense == null
        ? ''
        : decimalPrice(widget.expense!['amount_cents'] as int),
  );
  late final _description = TextEditingController(
    text: widget.expense?['description'] as String? ?? '',
  );
  late DateTime _date = widget.expense == null
      ? DateTime.now()
      : DateTime.parse(widget.expense!['spent_on'] as String);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveExpense({
        'id': _id,
        'sale_id': widget.sale['id'],
        'amount_cents': parseCents(_amount.text),
        'description': _description.text.trim(),
        'spent_on': dateValue(_date),
      }, creating: widget.expense == null);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo confirmar el gasto. Reintenta en este formulario para no duplicarlo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.expense == null ? 'Nuevo gasto' : 'Editar gasto'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Importe (${widget.sale['currency']})',
              ),
              validator: (value) => (parseCents(value ?? '') ?? 0) <= 0
                  ? 'Ingresa un importe mayor que cero.'
                  : null,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _description,
              enabled: !_busy,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                hintText: 'Por ejemplo: pollo, hojas o transporte',
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha del gasto'),
              subtitle: Text(dateLabel(dateValue(_date))),
              trailing: const Icon(Icons.calendar_month),
              onTap: _busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (date != null && mounted) setState(() => _date = date);
                    },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Guardando…' : 'Guardar gasto'),
            ),
          ],
        ),
      ),
    ),
  );
}
