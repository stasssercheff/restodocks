import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Список чеклистов-шаблонов. Шеф может править и создавать по аналогии.
class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  List<Checklist> _list = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) {
      setState(() {
        _loading = false;
        _error = 'Нет заведения или сотрудника';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final list = await svc.getChecklistsForEstablishment(est.id);
      if (mounted) setState(() {
        _list = list;
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

  Future<void> _createNew() async {
    final loc = context.read<LocalizationService>();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(loc.t('create_checklist')),
          content: TextField(
            controller: c,
            decoration: InputDecoration(
              labelText: loc.t('checklist_name'),
              hintText: loc.t('checklist_name_hint'),
            ),
            autofocus: true,
            onSubmitted: (_) => Navigator.of(ctx).pop(c.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.t('back')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
              child: Text(loc.t('save')),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty || !mounted) return;
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment!;
    final emp = acc.currentEmployee!;
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final created = await svc.createChecklist(
        establishmentId: est.id,
        createdBy: emp.id,
        name: name,
      );
      if (mounted) {
        await _load();
        context.push('/checklists/${created.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final canEdit = emp?.canEditChecklistsAndTechCards ?? false;
    final isKitchen = emp?.department == 'kitchen' ?? false;

    if (emp != null && !isKitchen) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('checklists')),
          actions: [
            IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  loc.t('checklists_kitchen_only'),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home),
                  label: Text(loc.t('home')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('checklists')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
      ),
      body: _body(loc),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: _loading ? null : _createNew,
              child: const Icon(Icons.add),
              tooltip: loc.t('create_checklist'),
            )
          : null,
    );
  }

  Widget _body(LocalizationService loc) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text(loc.t('refresh')),
              ),
            ],
          ),
        ),
      );
    }
    if (_list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.checklist, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                loc.t('no_checklists'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('no_checklists_hint'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _list.length,
        itemBuilder: (context, i) {
          final c = _list[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(c.name),
              subtitle: Text('${c.items.length} пунктов'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/checklists/${c.id}'),
            ),
          );
        },
      ),
    );
  }
}
