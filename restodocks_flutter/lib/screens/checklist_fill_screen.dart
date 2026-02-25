import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Заполнение чеклиста: №, наименование, сделано/не сделано.
/// При отправке — во входящие шефу и су-шефу.
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
  late List<bool> _done;

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
        _done = List.filled(c?.items.length ?? 0, false);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _submit() async {
    final c = _checklist;
    if (c == null) return;
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;

    final employees = await acc.getEmployeesForEstablishment(est.id);
    final chefs = employees.where((e) => e.hasRole('executive_chef') || e.hasRole('sous_chef')).map((e) => e.id).toSet().toList();
    if (chefs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocalizationService>().t('no_chef_sous_chef') ?? 'Нет шефа/су-шефа в заведении')),
      );
      return;
    }

    final items = <({String title, bool done})>[];
    for (var i = 0; i < c.items.length; i++) {
      items.add((title: c.items[i].title, done: i < _done.length ? _done[i] : false));
    }

    try {
      final subSvc = context.read<ChecklistSubmissionService>();
      await subSvc.submit(
        establishmentId: est.id,
        checklistId: c.id,
        submittedByEmployeeId: emp.id,
        submittedByName: emp.fullName,
        checklistName: c.name,
        section: c.assignedSection,
        items: items,
        recipientChefIds: chefs,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('checklist_sent') ?? 'Чеклист отправлен шефу и су-шефу')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final canAccessChecklists = emp?.canViewDepartment('kitchen') ?? false;

    if (emp != null && !canAccessChecklists) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('fill_checklist') ?? 'Заполнить чеклист'),
          actions: [appBarHomeButton(context)],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(loc.t('checklists_kitchen_only'), style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: () => context.go('/home'), icon: const Icon(Icons.home), label: Text(loc.t('home'))),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('fill_checklist') ?? 'Заполнить чеклист'),
          actions: [appBarHomeButton(context)],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _checklist == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('fill_checklist') ?? 'Заполнить чеклист'),
          actions: [appBarHomeButton(context)],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error ?? 'Чеклист не найден', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back'))),
              ],
            ),
          ),
        ),
      );
    }

    final c = _checklist!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(c.name),
        actions: [appBarHomeButton(context)],
      ),
      body: Column(
        children: [
          // Таблица: №, наименование, сделано/не сделано
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Заголовок
                  Row(
                    children: [
                      SizedBox(width: 48, child: Text(loc.t('checklist_number') ?? '№', style: Theme.of(context).textTheme.labelLarge)),
                      Expanded(child: Text(loc.t('checklist_name') ?? 'Наименование', style: Theme.of(context).textTheme.labelLarge)),
                      SizedBox(width: 120, child: Text(loc.t('checklist_done') ?? 'Сделано', style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.center)),
                    ],
                  ),
                  const Divider(height: 24),
                  ...List.generate(c.items.length, (i) {
                    final it = c.items[i];
                    final done = i < _done.length ? _done[i] : false;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(width: 48, child: Text('${i + 1}', style: Theme.of(context).textTheme.bodyMedium)),
                            Expanded(child: Text(it.title, style: Theme.of(context).textTheme.bodyMedium)),
                            SizedBox(
                              width: 140,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: done,
                                    tristate: false,
                                    onChanged: (v) {
                                      setState(() {
                                        if (i < _done.length) _done[i] = v ?? false;
                                      });
                                    },
                                  ),
                                  Text(done ? (loc.t('done') ?? 'Сделано') : (loc.t('not_done') ?? 'Не сделано'), style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.send),
                label: Text(loc.t('checklist_send') ?? 'Отправить шефу и су-шефу'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
