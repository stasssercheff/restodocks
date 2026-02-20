import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Заполнение чеклиста: пункты с ячейками (количество, галочка, выпадающий список), кнопка Отправить.
class ChecklistFillScreen extends StatefulWidget {
  const ChecklistFillScreen({super.key, required this.checklistId});

  final String checklistId;

  @override
  State<ChecklistFillScreen> createState() => _ChecklistFillScreenState();
}

class _ChecklistFillScreenState extends State<ChecklistFillScreen> {
  Checklist? _checklist;
  bool _loading = true;
  String? _error;
  final Map<String, dynamic> _values = {};

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final c = await svc.getChecklistById(widget.checklistId);
      if (!mounted) return;
      setState(() {
        _checklist = c;
        _loading = false;
        if (c != null) {
          for (final it in c.items) {
            if (it.cellType == ChecklistCellType.checkbox) {
              _values[it.id] = false;
            } else if (it.cellType == ChecklistCellType.quantity) {
              _values[it.id] = '';
            } else if (it.cellType == ChecklistCellType.dropdown) {
              _values[it.id] = it.dropdownOptions.isNotEmpty ? it.dropdownOptions.first : '';
            }
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final c = _checklist;
    if (c == null) return;
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (emp == null || est == null) return;

    final chefs = await acc.getExecutiveChefsForEstablishment(est.id);
    if (chefs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('checklist_no_chef') ?? 'Нет шеф-повара для отправки')),
        );
      }
      return;
    }

    final loc = context.read<LocalizationService>();
    final rows = <Map<String, dynamic>>[];
    for (final it in c.items) {
      final v = _values[it.id];
      rows.add({
        'itemId': it.id,
        'title': it.title,
        'cellType': it.cellType.value,
        'value': v is bool ? v : v?.toString() ?? '',
      });
    }
    final payload = {
      'checklist_name': c.name,
      'filled_by_name': emp.fullName,
      'filled_by_role': emp.roles.isNotEmpty ? emp.roles.first : null,
      'filled_at': DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
      'rows': rows,
    };

    final svc = context.read<ChecklistServiceSupabase>();
    final sub = await svc.submitChecklist(
      establishmentId: est.id,
      checklistId: c.id,
      checklistName: c.name,
      filledByEmployeeId: emp.id,
      filledByName: emp.fullName,
      filledByRole: emp.roles.isNotEmpty ? emp.roles.first : null,
      payload: payload,
      recipientChefId: chefs.first.id,
    );

    if (mounted) {
      if (sub != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('checklist_submitted') ?? 'Чеклист отправлен')),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', 'Ошибка отправки'))),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final canEdit = context.watch<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('checklist_fill') ?? 'Заполнить чеклист'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _checklist == null) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()), title: Text(loc.t('checklists'))),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error ?? 'Чеклист не найден', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back'))),
            ],
          ),
        ),
      );
    }

    final list = _checklist!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(list.name),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => context.push('/checklists/${list.id}/edit'),
              tooltip: loc.t('edit'),
            ),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...list.items.map((it) => _buildItemRow(it, loc)),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(loc.t('checklist_submit') ?? 'Отправить'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(ChecklistItem it, LocalizationService loc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: _buildCell(it, loc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(ChecklistItem it, LocalizationService loc) {
    switch (it.cellType) {
      case ChecklistCellType.quantity:
        return TextField(
          key: ValueKey(it.id),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: '0',
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: (v) => setState(() => _values[it.id] = v),
        );
      case ChecklistCellType.checkbox:
        return Checkbox(
          value: _values[it.id] as bool? ?? false,
          onChanged: (v) => setState(() => _values[it.id] = v ?? false),
        );
      case ChecklistCellType.dropdown:
        final opts = it.dropdownOptions;
        if (opts.isEmpty) return const SizedBox.shrink();
        return DropdownButtonFormField<String>(
          value: (_values[it.id] as String?)?.isNotEmpty == true ? _values[it.id] as String? : opts.first,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _values[it.id] = v ?? opts.first),
        );
    }
  }
}
