import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/documentation_rich_text_editor.dart';

/// Просмотр документа. Тема, текст. Владелец/менеджмент: кнопка редактирования.
class DocumentationViewScreen extends StatefulWidget {
  const DocumentationViewScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<DocumentationViewScreen> createState() => _DocumentationViewScreenState();
}

class _DocumentationViewScreenState extends State<DocumentationViewScreen> {
  EstablishmentDocument? _doc;
  bool _loading = true;
  String? _error;
  String? _translatedName;
  String? _translatedTopic;
  QuillController? _quillController;

  Future<void> _loadTranslations() async {
    if (!mounted || _doc == null) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    const sourceLang = 'ru';
    if (targetLang == sourceLang) return;
    try {
      final translationSvc = context.read<TranslationService>();
      if (_doc!.name.trim().isNotEmpty) {
        final t = await translationSvc.translate(
          entityType: TranslationEntityType.document,
          entityId: _doc!.id,
          fieldName: 'name',
          text: _doc!.name,
          from: sourceLang,
          to: targetLang,
        );
        if (t != null && t != _doc!.name && mounted) setState(() => _translatedName = t);
      }
      if (_doc!.topic?.trim().isNotEmpty == true) {
        final t = await translationSvc.translate(
          entityType: TranslationEntityType.document,
          entityId: _doc!.id,
          fieldName: 'topic',
          text: _doc!.topic!,
          from: sourceLang,
          to: targetLang,
        );
        if (t != null && t != _doc!.topic && mounted) setState(() => _translatedTopic = t);
      }
      // Body (Delta JSON) — перевод не поддерживается для rich text
    } catch (_) {}
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    if (acc.establishment == null || acc.currentEmployee == null) {
      setState(() {
        _loading = false;
        _error = context.read<LocalizationService>().t('error_no_establishment_or_employee');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await context.read<DocumentationServiceSupabase>().getDocumentById(widget.documentId);
      if (doc == null) {
        setState(() {
          _loading = false;
          _error = context.read<LocalizationService>().t('document_not_found');
        });
        return;
      }
      final emp = acc.currentEmployee!;
      final docs = await context.read<DocumentationServiceSupabase>().getDocumentsForEmployee(acc.establishment!.id, emp);
      if (!docs.any((d) => d.id == doc.id)) {
        setState(() {
          _loading = false;
          _error = context.read<LocalizationService>().t('access_denied') ?? 'Доступ запрещён';
        });
        return;
      }
      if (mounted) {
        _quillController?.dispose();
        _quillController = QuillController(
          document: documentFromBody(doc.body),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
        setState(() {
          _doc = doc;
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
  void dispose() {
    _quillController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final canEdit = emp?.canEditDocumentation ?? false;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('documentation') ?? 'Документация')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _doc == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('documentation') ?? 'Документация')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error ?? loc.t('document_not_found'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back') ?? 'Назад')),
              ],
            ),
          ),
        ),
      );
    }

    final name = _translatedName ?? _doc!.name;
    final topic = _translatedTopic ?? _doc!.topic ?? '';
    final hasBody = _doc!.body?.trim().isNotEmpty == true;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: loc.t('edit') ?? 'Редактировать',
              onPressed: () async {
                await context.push('/documentation/${_doc!.id}/edit');
                if (mounted) _load();
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (topic.isNotEmpty) ...[
              Text(
                topic,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 16),
            ],
            if (hasBody && _quillController != null)
              DocumentationRichTextEditor(
                controller: _quillController!,
                readOnly: true,
                minHeight: 150,
              )
            else if (!hasBody)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  loc.t('documentation_empty_body') ?? 'Текст отсутствует',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
