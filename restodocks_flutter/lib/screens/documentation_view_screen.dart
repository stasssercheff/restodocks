import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../core/subscription_entitlements.dart';
import '../models/models.dart';
import '../services/inventory_download.dart';
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
  String? _translatedBodyPlain;
  bool _bodyTranslationPending = false;
  QuillController? _quillController;

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
          _translatedBodyPlain = null;
          _bodyTranslationPending = false;
        });
      }
      return;
    }
    try {
      final translationSvc = context.read<TranslationService>();
      final plainBody = documentFromBody(_doc!.body).toPlainText().trim();
      if (mounted) {
        setState(() {
          _bodyTranslationPending = plainBody.isNotEmpty;
          _translatedBodyPlain = null;
        });
      }
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
      if (plainBody.isNotEmpty) {
        final tb = await translationSvc.translate(
          entityType: TranslationEntityType.document,
          entityId: _doc!.id,
          fieldName: 'body',
          text: plainBody,
          from: sourceLang,
          to: targetLang,
        );
        if (mounted) {
          setState(() {
            _bodyTranslationPending = false;
            if (tb != null && tb.trim().isNotEmpty) _translatedBodyPlain = tb;
          });
        }
      } else if (mounted) {
        setState(() => _bodyTranslationPending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _bodyTranslationPending = false);
    }
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

  String? _prevUiLang;

  void _syncTranslationLanguageIfNeeded(LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    if (_prevUiLang != null && lang != _prevUiLang) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _doc != null) _loadTranslations();
      });
    }
    _prevUiLang = lang;
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

    _syncTranslationLanguageIfNeeded(loc);

    final name = _translatedName ?? _doc!.name;
    final topic = _translatedTopic ?? _doc!.topic ?? '';
    final hasBody = _doc!.body?.trim().isNotEmpty == true;
    final uiLang = loc.currentLanguageCode;
    final showTranslatedBody =
        uiLang != 'ru' && (_translatedBodyPlain?.trim().isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: loc.t('documentation_save_pdf') ?? 'Сохранить PDF',
            onPressed: () => _onSavePdfTapped(),
          ),
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
            if (hasBody && _bodyTranslationPending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (hasBody && showTranslatedBody)
              SelectableText(
                _translatedBodyPlain!,
                style: Theme.of(context).textTheme.bodyLarge,
              )
            else if (hasBody && _quillController != null)
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

  Future<void> _onSavePdfTapped() async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final ent = SubscriptionEntitlements.from(acc.establishment);
    if (ent.isLiteTier) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(loc.t('subscription_required_lite_body'))),
      );
      return;
    }
    final exportLang = await showDialog<String>(
      context: this.context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('order_export_language_title')),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.t('order_export_language_subtitle')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DocPdfLangButton(
                    flag: '🇷🇺',
                    label: loc.t('order_export_language_ru'),
                    onTap: () => Navigator.of(ctx).pop('ru')),
                _DocPdfLangButton(
                    flag: '🇺🇸',
                    label: loc.t('order_export_language_en'),
                    onTap: () => Navigator.of(ctx).pop('en')),
                _DocPdfLangButton(
                    flag: '🇪🇸',
                    label: loc.t('order_export_language_es'),
                    onTap: () => Navigator.of(ctx).pop('es')),
                _DocPdfLangButton(
                    flag: '🇮🇹',
                    label: loc.t('order_export_language_it') ?? 'Italiano',
                    onTap: () => Navigator.of(ctx).pop('it')),
                _DocPdfLangButton(
                    flag: '🇹🇷',
                    label: loc.t('order_export_language_tr') ?? 'Türkçe',
                    onTap: () => Navigator.of(ctx).pop('tr')),
                _DocPdfLangButton(
                    flag: '🇰🇿',
                    label: loc.t('order_export_language_kk') ?? 'Қазақша',
                    onTap: () => Navigator.of(ctx).pop('kk')),
              ],
            ),
          ],
        ),
      ),
    );
    if (exportLang == null || !mounted || _doc == null) return;

    try {
      if (!mounted) return;
      final translationSvc = context.read<TranslationService>();
      const sourceLang = 'ru';
      String title = _doc!.name;
      String topicLine = _doc!.topic?.trim() ?? '';
      final plainBody = documentFromBody(_doc!.body).toPlainText().trim();

      Future<String?> tr(String field, String text) async {
        if (text.isEmpty) return text;
        if (exportLang == sourceLang) return text;
        final out = await translationSvc.translate(
          entityType: TranslationEntityType.document,
          entityId: _doc!.id,
          fieldName: field,
          text: text,
          from: sourceLang,
          to: exportLang,
        );
        return out ?? text;
      }

      title = (await tr('name', title)) ?? title;
      if (topicLine.isNotEmpty) {
        topicLine = (await tr('topic', topicLine)) ?? topicLine;
      }
      var bodyOut = plainBody;
      if (plainBody.isNotEmpty && exportLang != sourceLang) {
        bodyOut = (await tr('body', plainBody)) ?? plainBody;
      }

      final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      );
      final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
      );

      final pdf = pw.Document();
      final dateStr =
          DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now().toLocal());
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
          build: (_) => [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              dateStr,
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
            if (topicLine.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                topicLine,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
            ],
            pw.SizedBox(height: 16),
            if (bodyOut.isEmpty)
              pw.Text(
                loc.t('documentation_empty_body') ?? '',
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
              )
            else
              pw.Text(
                bodyOut,
                style: const pw.TextStyle(fontSize: 11),
              ),
          ],
        ),
      );

      final est = acc.establishment;
      if (est != null && acc.isTrialOnlyWithoutPaid) {
        await acc.trialIncrementDeviceSaveOrThrow(
          establishmentId: est.id,
          docKind: TrialDeviceSaveKinds.documentation,
        );
      }

      final safe = _doc!.name
          .replaceAll(RegExp(r'[^\w\-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .trim();
      final base = safe.isEmpty
          ? 'document'
          : safe.substring(0, min(safe.length, 60));
      final fileName = '${base}_$exportLang.pdf';
      await saveFileBytes(fileName, await pdf.save());
      if (!mounted) return;
      final msg = (loc.t('documentation_pdf_saved') ?? 'Saved: %s')
          .replaceFirst('%s', fileName);
      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('${loc.t('error')}: $e')),
      );
    }
  }
}

class _DocPdfLangButton extends StatelessWidget {
  const _DocPdfLangButton({
    required this.flag,
    required this.label,
    required this.onTap,
  });

  final String flag;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
