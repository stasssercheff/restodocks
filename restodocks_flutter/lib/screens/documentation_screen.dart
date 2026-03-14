import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Список документов. Владелец и менеджмент: create/edit. Остальные: просмотр.
class DocumentationScreen extends StatefulWidget {
  const DocumentationScreen({super.key});

  @override
  State<DocumentationScreen> createState() => _DocumentationScreenState();
}

class _DocumentationScreenState extends State<DocumentationScreen> {
  List<EstablishmentDocument> _list = [];
  bool _loading = true;
  String? _error;
  final Map<String, String> _translatedNames = {};
  final Map<String, String> _translatedTopics = {};

  Future<void> _loadTranslations() async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    const sourceLang = 'ru';
    if (targetLang == sourceLang) return;
    try {
      final translationSvc = context.read<TranslationService>();
      for (final d in _list) {
        if (d.name.trim().isNotEmpty) {
          final translated = await translationSvc.translate(
            entityType: TranslationEntityType.document,
            entityId: d.id,
            fieldName: 'name',
            text: d.name,
            from: sourceLang,
            to: targetLang,
          );
          if (translated != null && translated != d.name && mounted) {
            setState(() => _translatedNames[d.id] = translated);
          }
        }
        if (d.topic?.trim().isNotEmpty == true) {
          final translated = await translationSvc.translate(
            entityType: TranslationEntityType.document,
            entityId: d.id,
            fieldName: 'topic',
            text: d.topic!,
            from: sourceLang,
            to: targetLang,
          );
          if (translated != null && translated != d.topic && mounted) {
            setState(() => _translatedTopics[d.id] = translated);
          }
        }
      }
    } catch (_) {}
  }

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
      _translatedNames.clear();
      _translatedTopics.clear();
    });
    try {
      final svc = context.read<DocumentationServiceSupabase>();
      final list = await svc.getDocumentsForEmployee(est.id, emp);
      if (mounted) {
        setState(() {
          _list = list;
          _loading = false;
        });
        _loadTranslations();
      }
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

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final canEdit = emp?.canEditDocumentation ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('documentation') ?? 'Документация'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh') ?? 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: Text(loc.t('retry') ?? 'Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : _list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          loc.t('documentation_empty') ?? 'Нет документов',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _list.length,
                      itemBuilder: (context, index) {
                        final doc = _list[index];
                        final name = _translatedNames[doc.id] ?? doc.name;
                        final topic = _translatedTopics[doc.id] ?? doc.topic ?? '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(name),
                            subtitle: topic.isNotEmpty ? Text(topic) : null,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/documentation/${doc.id}'),
                          ),
                        );
                      },
                    ),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: () async {
                await context.push('/documentation/new');
                if (mounted) _load();
              },
              child: const Icon(Icons.add),
              tooltip: loc.t('documentation_create') ?? 'Создать документ',
            )
          : null,
    );
  }
}
