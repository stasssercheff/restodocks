import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/schedule_storage_service.dart';
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

  Future<Map<String, dynamic>?> _gatherContext() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) return null;
    final store = context.read<ProductStoreSupabase>();
    final techSvc = context.read<TechCardServiceSupabase>();
    final lang = context.read<LocalizationService>().currentLanguageCode;
    await store.ensureNomenclatureLoaded(est.id);
    final products = store.getNomenclatureProducts(est.id);
    final employees = await acc.getEmployeesForEstablishment(est.id);
    final techCards = await techSvc.getTechCardsForEstablishment(est.id);
    final schedule = await loadSchedule(est.id);
    final sectionNames = schedule.sections.map((s) => s.nameKey.replaceFirst('section_', '')).join(', ');
    final slotNames = schedule.slots.map((s) => s.name).join(', ');
    return {
      'items': products.map((p) => {'id': p.id, 'name': p.getLocalizedName(lang)}).toList(),
      'recipes': techCards.map((t) => {'id': t.id, 'name': t.getDisplayNameInLists(lang)}).toList(),
      'employees': employees.map((e) => e.fullName).toList(),
      'scheduleSummary': 'Цеха: $sectionNames. Должности/слоты: $slotNames',
    };
  }

  Future<void> _generateByPrompt() async {
    final loc = context.read<LocalizationService>();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.auto_awesome, color: Theme.of(ctx).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(loc.t('checklist_with_ai') ?? 'Чеклист с ИИ')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('checklist_ai_context_hint') ?? 'ИИ учтёт ваши продукты, сотрудников, график и ТТК. Опишите, какой чеклист нужен:',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                decoration: InputDecoration(
                  hintText: loc.t('generate_checklist_prompt_hint'),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                minLines: 2,
                autofocus: true,
                onSubmitted: (_) => Navigator.of(ctx).pop(c.text.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.t('cancel')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(loc.t('generate') ?? 'Создать'),
            ),
          ],
        );
      },
    );
    if (prompt == null || prompt.isEmpty || !mounted) return;
    final contextMap = await _gatherContext();
    if (!mounted) return;
    final ai = context.read<AiService>();
    final generated = await ai.generateChecklistFromPrompt(prompt, context: contextMap);
    if (!mounted) return;
    if (generated == null || generated.itemTitles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('ai_no_result'))),
      );
      return;
    }
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final items = generated.itemTitles
          .asMap()
          .entries
          .map((e) => ChecklistItem.template(title: e.value, sortOrder: e.key))
          .toList();
      final created = await svc.createChecklist(
        establishmentId: est.id,
        createdBy: emp.id,
        name: generated.name,
        items: items,
      );
      if (mounted) {
        await _load();
        context.push('/checklists/${created.id}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('generate_checklist_by_prompt')} ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
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
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
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
    // Шеф и су-шеф могут открывать и создавать чеклисты даже с отделом «Управление»
    final canAccessChecklists = isKitchen || canEdit;

    if (emp != null && !canAccessChecklists) {
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
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: _loading ? null : _generateByPrompt,
              tooltip: loc.t('generate_checklist_by_prompt'),
            ),
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
      body: _body(loc, canEdit),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: _loading ? null : _createNew,
              child: const Icon(Icons.add),
              tooltip: loc.t('create_checklist'),
            )
          : null,
    );
  }

  Widget _buildAiChecklistButton(LocalizationService loc) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
      child: InkWell(
        onTap: _loading ? null : _generateByPrompt,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 32, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.t('checklist_with_ai') ?? 'Чеклист с ИИ',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.t('checklist_ai_short_hint') ?? 'Опишите запрос — ИИ создаст чеклист с учётом продуктов, сотрудников, графика',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(LocalizationService loc, bool canEdit) {
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
              if (canEdit) ...[
                const SizedBox(height: 24),
                _buildAiChecklistButton(loc),
              ],
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _list.length + (canEdit ? 1 : 0),
        itemBuilder: (context, i) {
          if (canEdit && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildAiChecklistButton(loc),
            );
          }
          final c = _list[canEdit ? i - 1 : i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(c.name),
              subtitle: Text('${c.items.length} ${loc.t('items_count')}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/checklists/${c.id}'),
            ),
          );
        },
      ),
    );
  }
}
