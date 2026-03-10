import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/inbox_viewed_service.dart';
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
  /// Переводы пунктов: index -> переведённый текст
  final Map<int, String> _translatedTitles = {};
  /// Перевод названия чеклиста
  String? _translatedChecklistName;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _translatedTitles.clear();
      _translatedChecklistName = null;
    });
    final sub = await ChecklistSubmissionService().getById(widget.documentId);
    if (!mounted) return;
    setState(() {
      _submission = sub;
      _loading = false;
      if (sub == null) _error = 'Чеклист не найден';
    });
    if (sub != null && mounted) {
      final estId = context.read<AccountManagerSupabase>().establishment?.id;
      context.read<InboxViewedService>().addViewed(estId, widget.documentId);
      _loadTranslations(sub);
    }
  }

  Future<void> _loadTranslations(ChecklistSubmission sub) async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    // Язык оригинала: берём из payload, иначе 'ru' по умолчанию
    final sourceLang = (sub.payload['sourceLang'] as String?)?.trim().isNotEmpty == true
        ? sub.payload['sourceLang'] as String
        : 'ru';
    if (targetLang == sourceLang) return;

    try {
      final translationSvc = context.read<TranslationService>();

      // Перевод названия чеклиста
      if (sub.checklistName.trim().isNotEmpty) {
        final translatedName = await translationSvc.translate(
          entityType: TranslationEntityType.checklist,
          entityId: sub.checklistId,
          fieldName: 'checklist_name',
          text: sub.checklistName,
          from: sourceLang,
          to: targetLang,
        );
        if (translatedName != null && translatedName != sub.checklistName && mounted) {
          setState(() => _translatedChecklistName = translatedName);
        }
      }

      // Перевод пунктов чеклиста
      final items = sub.items;
      for (var i = 0; i < items.length; i++) {
        final title = items[i].title;
        if (title.trim().isEmpty) continue;
        final translated = await translationSvc.translate(
          entityType: TranslationEntityType.checklist,
          entityId: sub.checklistId,
          fieldName: 'item_$i',
          text: title,
          from: sourceLang,
          to: targetLang,
        );
        if (translated != null && translated != title && mounted) {
          setState(() => _translatedTitles[i] = translated);
        }
      }
    } catch (_) {}
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
          leading: appBarBackButton(context),
          title: Text(loc.t('checklist')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _submission == null) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('checklist')),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error ?? loc.t('checklist_not_found'), textAlign: TextAlign.center),
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
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    final submittedByName = sub.submittedByName.isNotEmpty
        ? sub.submittedByName
        : sub.payload['submittedByName'] as String? ?? '—';

    final startTime = sub.payload['startTime'] != null
        ? DateTime.tryParse(sub.payload['startTime'].toString())
        : null;
    final endTime = sub.payload['endTime'] != null
        ? DateTime.tryParse(sub.payload['endTime'].toString())
        : null;
    final comments = sub.payload['comments'] as String?;
    final position = sub.payload['position'] as String?;
    final displayName = _translatedChecklistName ?? sub.checklistName;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(displayName),
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
                    Text(submittedByName, style: Theme.of(context).textTheme.titleMedium),
                    if (position != null && position.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(position, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                    if (sub.section != null) ...[
                      const SizedBox(height: 4),
                      Text('${loc.t('section')}: ${sub.section}', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${loc.t('date')}: ${dateFormat.format(sub.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    if (startTime != null || endTime != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${loc.t('checklist_start_time')}: ${startTime != null ? '${startTime.hour.toString().padLeft(2,'0')}:${startTime.minute.toString().padLeft(2,'0')}' : '—'}'
                        '  ${loc.t('checklist_end_time')}: ${endTime != null ? '${endTime.hour.toString().padLeft(2,'0')}:${endTime.minute.toString().padLeft(2,'0')}' : '—'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(loc.t('checklist_items'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...List.generate(items.length, (i) {
              final it = items[i];
              final displayTitle = _translatedTitles[i] ?? it.title;
              final rawPayload = (sub.payload['items'] as List<dynamic>?)?[i];
              final itemData = rawPayload is Map ? Map<String, dynamic>.from(rawPayload) : <String, dynamic>{};
              final techCardId = itemData['techCardId']?.toString();
              final numericValue = itemData['numericValue']?.toString();
              final dropdownValue = itemData['dropdownValue']?.toString();

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: it.done
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      it.done ? Icons.check : Icons.close,
                      size: 18,
                      color: it.done
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: techCardId != null && techCardId.isNotEmpty
                      ? InkWell(
                          onTap: () => context.push('/tech-cards/$techCardId'),
                          child: Row(
                            children: [
                              Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  displayTitle,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(displayTitle),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.done ? loc.t('done') : loc.t('not_done'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (numericValue != null && numericValue.isNotEmpty)
                        Text(numericValue, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      if (dropdownValue != null && dropdownValue.isNotEmpty)
                        Text(dropdownValue, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              );
            }),
            if (comments != null && comments.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(loc.t('checklist_comments'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(comments, style: Theme.of(context).textTheme.bodyMedium),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
