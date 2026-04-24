import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../core/subscription_entitlements.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../utils/documentation_pdf_export.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/documentation_rich_text_editor.dart';
import '../widgets/subscription_required_dialog.dart';

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

  void _onLocaleChanged() {
    if (!mounted || _doc == null || _loading) return;
    _loadTranslations();
  }

  void _rebuildQuillFromDocBody() {
    if (_doc == null) return;
    _quillController?.dispose();
    _quillController = QuillController(
      document: documentFromBody(_doc!.body),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  Future<void> _loadTranslations() async {
    if (!mounted || _doc == null) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    const sourceLang = 'ru';

    if (targetLang == sourceLang) {
      if (mounted) {
        setState(() {
          _translatedName = null;
          _translatedTopic = null;
        });
        _rebuildQuillFromDocBody();
      }
      return;
    }

    try {
      final translationSvc = context.read<TranslationService>();
      String? nameT;
      String? topicT;
      if (_doc!.name.trim().isNotEmpty) {
        nameT = await translationSvc.translate(
          entityType: TranslationEntityType.document,
          entityId: _doc!.id,
          fieldName: 'name',
          text: _doc!.name,
          from: sourceLang,
          to: targetLang,
        );
      }
      if (_doc!.topic?.trim().isNotEmpty == true) {
        topicT = await translationSvc.translate(
          entityType: TranslationEntityType.document,
          entityId: _doc!.id,
          fieldName: 'topic',
          text: _doc!.topic!,
          from: sourceLang,
          to: targetLang,
        );
      }

      final plain = documentFromBody(_doc!.body).toPlainText().trim();
      String? bodyT;
      if (plain.isNotEmpty) {
        bodyT = await translationSvc.translate(
          entityType: TranslationEntityType.document,
          entityId: _doc!.id,
          fieldName: 'body',
          text: plain,
          from: sourceLang,
          to: targetLang,
        );
      }

      if (!mounted) return;
      if (context.read<LocalizationService>().currentLanguageCode != targetLang) {
        return;
      }

      setState(() {
        _translatedName =
            (nameT != null && nameT.isNotEmpty && nameT != _doc!.name) ? nameT : null;
        _translatedTopic = (topicT != null &&
                topicT.isNotEmpty &&
                topicT != _doc!.topic)
            ? topicT
            : null;
      });

      final useTranslatedBody =
          bodyT != null && bodyT.isNotEmpty && bodyT != plain;
      if (useTranslatedBody) {
        _quillController?.dispose();
        _quillController = QuillController(
          document: Document()..insert(0, bodyT),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
      } else {
        _rebuildQuillFromDocBody();
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final docSvc = context.read<DocumentationServiceSupabase>();
    if (acc.establishment == null || acc.currentEmployee == null) {
      setState(() {
        _loading = false;
        _error = loc.t('error_no_establishment_or_employee');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await docSvc.getDocumentById(widget.documentId);
      if (!mounted) return;
      if (doc == null) {
        setState(() {
          _loading = false;
          _error = loc.t('document_not_found');
        });
        return;
      }
      final emp = acc.currentEmployee!;
      final docs =
          await docSvc.getDocumentsForEmployee(acc.establishment!.id, emp);
      if (!mounted) return;
      if (!docs.any((d) => d.id == doc.id)) {
        setState(() {
          _loading = false;
          _error = loc.t('access_denied');
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
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _exportPdf(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final translationSvc = context.read<TranslationService>();
    final exportOk =
        SubscriptionEntitlements.from(account.establishment).canExportSalaryPayrollToDevice;
    if (!exportOk) {
      await showSubscriptionRequiredDialog(context);
      return;
    }
    if (_doc == null) return;

    final selectedLang = await showDialog<String>(
      context: context,
      builder: (ctx) => _DocumentationPdfLanguageDialog(loc: loc),
    );
    if (selectedLang == null) return;
    if (!context.mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(loc.t('loading')),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final est = account.establishment;
      if (est != null && account.isTrialOnlyWithoutPaid) {
        await account.trialIncrementDeviceSaveOrThrow(
          establishmentId: est.id,
          docKind: TrialDeviceSaveKinds.documentation,
        );
      }
      if (!context.mounted) return;

      const sourceLang = 'ru';
      final d = _doc!;

      Future<String> trField(String fieldName, String text) async {
        if (text.trim().isEmpty) return text;
        if (selectedLang == sourceLang) return text;
        final t = await translationSvc.translate(
          entityType: TranslationEntityType.document,
          entityId: d.id,
          fieldName: fieldName,
          text: text,
          from: sourceLang,
          to: selectedLang,
        );
        return (t != null && t.isNotEmpty) ? t : text;
      }

      final nameOut = await trField('name', d.name);
      final topicOut = d.topic == null ? '' : await trField('topic', d.topic!);
      final plain = documentFromBody(d.body).toPlainText().trim();
      final bodyOut = plain.isEmpty ? '' : await trField('body', plain);

      final bytes = await buildDocumentationPdfBytes(
        title: nameOut,
        topic: topicOut,
        bodyPlain: bodyOut,
      );

      final safe = d.name.replaceAll(RegExp(r'[^\w\-.\s]'), '_').trim();
      final fname = 'documentation_${safe.isEmpty ? d.id : safe}.pdf';

      if (context.mounted) Navigator.of(context).pop();

      await Printing.sharePdf(bytes: bytes, filename: fname);

      if (context.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(loc.t('documentation_pdf_ready'))),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('${loc.t('error_short')}: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    LocalizationService().addListener(_onLocaleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    LocalizationService().removeListener(_onLocaleChanged);
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
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('documentation'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _doc == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('documentation'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error ?? loc.t('document_not_found'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back'))),
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
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: loc.t('documentation_save_pdf'),
            onPressed: () => _exportPdf(context),
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: loc.t('edit'),
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
                  loc.t('documentation_empty_body'),
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

class _DocumentationPdfLanguageDialog extends StatefulWidget {
  const _DocumentationPdfLanguageDialog({required this.loc});

  final LocalizationService loc;

  @override
  State<_DocumentationPdfLanguageDialog> createState() =>
      _DocumentationPdfLanguageDialogState();
}

class _DocumentationPdfLanguageDialogState extends State<_DocumentationPdfLanguageDialog> {
  late String _selectedLang;

  @override
  void initState() {
    super.initState();
    _selectedLang = widget.loc.currentLanguageCode;
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    return AlertDialog(
      title: Text(loc.t('documentation_pdf_dialog_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.t('documentation_pdf_language'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: LocalizationService.productLanguageCodes.map((code) {
              return ChoiceChip(
                label: Text(loc.getLanguageName(code)),
                selected: _selectedLang == code,
                onSelected: (_) => setState(() => _selectedLang = code),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedLang),
          child: Text(loc.t('documentation_pdf_export_btn')),
        ),
      ],
    );
  }
}
