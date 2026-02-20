import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Входящие: отправленные чеклисты (время заполнения, имя и должность исполнителя).
class ChecklistReceivedScreen extends StatefulWidget {
  const ChecklistReceivedScreen({super.key});

  @override
  State<ChecklistReceivedScreen> createState() => _ChecklistReceivedScreenState();
}

class _ChecklistReceivedScreenState extends State<ChecklistReceivedScreen> {
  List<ChecklistSubmission> _list = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final chefId = context.read<AccountManagerSupabase>().currentEmployee?.id;
    if (chefId == null) {
      setState(() { _loading = false; _error = 'Не авторизован'; });
      return;
    }
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final list = await svc.listSubmissionsForChef(chefId);
      if (mounted) setState(() { _list = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('checklist_received') ?? 'Чеклисты'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: _buildBody(loc),
    );
  }

  Widget _buildBody(LocalizationService loc) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(loc.t('retry') ?? 'Повторить')),
          ],
        ),
      );
    }
    if (_list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.checklist, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                loc.t('checklist_received_hint') ?? 'Отправленные чеклисты будут здесь',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _list.length,
        itemBuilder: (_, i) {
          final sub = _list[i];
          final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(sub.filledAt);
          final roleStr = sub.filledByRole != null ? ' · ${sub.filledByRole}' : '';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.checklist)),
              title: Text(sub.checklistName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('$dateStr\n${sub.filledByName}$roleStr'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showDetails(sub, loc),
            ),
          );
        },
      ),
    );
  }

  void _showDetails(ChecklistSubmission sub, LocalizationService loc) {
    final rows = sub.payload['rows'] as List<dynamic>? ?? [];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                sub.checklistName,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${DateFormat('dd.MM.yyyy HH:mm').format(sub.filledAt)} · ${sub.filledByName}${sub.filledByRole != null ? ' · ${sub.filledByRole}' : ''}',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: rows.map((r) {
                    final m = r as Map<String, dynamic>;
                    final title = m['title'] as String? ?? '—';
                    final value = m['value'];
                    String valueStr = '';
                    if (value is bool) {
                      valueStr = value ? '✓' : '—';
                    } else {
                      valueStr = value?.toString() ?? '—';
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: Text(title)),
                          Expanded(child: Text(valueStr, textAlign: TextAlign.end)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
