import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр отправленного чеклиста из входящих.
class ChecklistInboxDetailScreen extends StatefulWidget {
  const ChecklistInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<ChecklistInboxDetailScreen> createState() => _ChecklistInboxDetailScreenState();
}

class _ChecklistInboxDetailScreenState extends State<ChecklistInboxDetailScreen> {
  ChecklistSubmission? _submission;
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final sub = await ChecklistSubmissionService().getById(widget.documentId);
    if (!mounted) return;
    setState(() {
      _submission = sub;
      _loading = false;
      if (sub == null) _error = 'Чеклист не найден';
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('checklist') ?? 'Чеклист'),
          actions: [appBarHomeButton(context)],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _submission == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('checklist') ?? 'Чеклист'),
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

    final sub = _submission!;
    final items = sub.items;
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm', 'ru');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(sub.checklistName),
        actions: [appBarHomeButton(context)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${loc.t('checklist_sent_by') ?? 'Отправлено'} ${sub.submittedByName}', style: Theme.of(context).textTheme.bodyLarge),
                    if (sub.section != null) Text('${loc.t('section') ?? 'Цех'}: ${sub.section}', style: Theme.of(context).textTheme.bodyMedium),
                    Text('${loc.t('date') ?? 'Дата'}: ${dateFormat.format(sub.createdAt)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(loc.t('checklist_items') ?? 'Пункты', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...List.generate(items.length, (i) {
              final it = items[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: it.done ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(it.done ? Icons.check : Icons.close, size: 18, color: it.done ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  title: Text(it.title),
                  subtitle: Text(it.done ? (loc.t('done') ?? 'Сделано') : (loc.t('not_done') ?? 'Не сделано'), style: Theme.of(context).textTheme.bodySmall),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
