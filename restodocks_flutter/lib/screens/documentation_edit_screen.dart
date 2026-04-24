import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/documentation_image_upload_service.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/documentation_rich_text_editor.dart';

/// Создание или редактирование документа. Владелец и менеджмент.
class DocumentationEditScreen extends StatefulWidget {
  const DocumentationEditScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<DocumentationEditScreen> createState() => _DocumentationEditScreenState();
}

class _DocumentationEditScreenState extends State<DocumentationEditScreen> {
  EstablishmentDocument? _doc;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late final TextEditingController _nameController;
  late final TextEditingController _topicController;
  late final QuillController _quillController;
  DocumentVisibilityType _visibilityType = DocumentVisibilityType.all;
  List<String> _visibilityIds = [];
  List<Employee> _employees = [];

  bool get _isNew => widget.documentId == 'new';

  static const _departmentCodes = ['kitchen', 'bar', 'hall', 'management'];
  static const _sectionCodes = [
    'hot_kitchen', 'cold_kitchen', 'grill', 'pizza', 'sushi',
    'prep', 'pastry', 'bakery', 'cleaning', 'banquet_catering',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _topicController = TextEditingController();
    _quillController = QuillController.basic(
      config: QuillControllerConfig(
        clipboardConfig: QuillClipboardConfig(
          enableExternalRichPaste: true,
          onImagePaste: (bytes) async {
            final url = await DocumentationImageUploadService.uploadImage(bytes);
            return url;
          },
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) {
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
      List<Employee> emps = await acc.getEmployeesForEstablishment(est.id);
      EstablishmentDocument? doc;
      if (!_isNew) {
        doc = await context.read<DocumentationServiceSupabase>().getDocumentById(widget.documentId);
      }
      if (mounted) {
        setState(() {
          _employees = emps;
          _doc = doc;
          _loading = false;
          if (doc != null) {
            _nameController.text = doc.name;
            _topicController.text = doc.topic ?? '';
            _quillController.document = documentFromBody(doc.body);
            _visibilityType = doc.visibilityType;
            _visibilityIds = List.from(doc.visibilityIds);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      final loc = context.read<LocalizationService>();
      AppToastService.show(loc.t('documentation_name_required'));
      return;
    }
    setState(() => _saving = true);
    try {
      final svc = context.read<DocumentationServiceSupabase>();
      final loc = context.read<LocalizationService>();
      final translationManager = context.read<TranslationManager>();
      if (_isNew) {
        final created = await svc.createDocument(
          establishmentId: est.id,
          createdBy: emp.id,
          name: name,
          topic: _topicController.text.trim().isEmpty ? null : _topicController.text.trim(),
          visibilityType: _visibilityType,
          visibilityIds: _visibilityIds,
          body: bodyFromDocument(_quillController.document),
        );
        final topic = _topicController.text.trim();
        final tf = <String, String>{'name': name};
        if (topic.isNotEmpty) tf['topic'] = topic;
        unawaited(translationManager.handleEntitySave(
          entityType: TranslationEntityType.document,
          entityId: created.id,
          textFields: tf,
          sourceLanguage: loc.currentLanguageCode,
          userId: emp.id,
        ));
        AppToastService.show(loc.t('documentation_created'));
      } else {
        final updated = _doc!.copyWith(
          name: name,
          topic: _topicController.text.trim().isEmpty ? null : _topicController.text.trim(),
          visibilityType: _visibilityType,
          visibilityIds: _visibilityIds,
          body: bodyFromDocument(_quillController.document),
        );
        await svc.updateDocument(updated);
        final topic = _topicController.text.trim();
        final tf = <String, String>{'name': name};
        if (topic.isNotEmpty) tf['topic'] = topic;
        unawaited(translationManager.handleEntitySave(
          entityType: TranslationEntityType.document,
          entityId: updated.id,
          textFields: tf,
          sourceLanguage: loc.currentLanguageCode,
          userId: emp.id,
        ));
        AppToastService.show(loc.t('documentation_updated'));
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        AppToastService.show(e.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _getDepartmentLabel(String code, LocalizationService loc) {
    switch (code) {
      case 'kitchen': return loc.t('kitchen');
      case 'bar': return loc.t('bar');
      case 'hall': return loc.t('dining_room');
      case 'management': return loc.t('management');
      default: return code;
    }
  }

  String _getSectionLabel(String code, LocalizationService loc) {
    final s = KitchenSection.fromCode(code);
    return s?.getLocalizedName(loc.currentLanguageCode) ?? code;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final canEdit = emp?.canEditDocumentation ?? false;

    if (!canEdit) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('documentation'))),
        body: Center(child: Text(loc.t('access_denied'))),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('documentation'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && !_isNew && _doc == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('documentation'))),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back'))),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(_isNew ? loc.t('documentation_create') : loc.t('documentation_edit')),
        actions: [
          if (!_isNew && _doc != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : () => _confirmDelete(loc),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: loc.t('documentation_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _topicController,
              decoration: InputDecoration(
                labelText: loc.t('documentation_topic'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(loc.t('documentation_visibility'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<DocumentVisibilityType>(
              value: _visibilityType,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: DocumentVisibilityType.all, child: Text(loc.t('documentation_visibility_all'))),
                DropdownMenuItem(value: DocumentVisibilityType.department, child: Text(loc.t('documentation_visibility_department'))),
                DropdownMenuItem(value: DocumentVisibilityType.section, child: Text(loc.t('documentation_visibility_section'))),
                DropdownMenuItem(value: DocumentVisibilityType.employee, child: Text(loc.t('documentation_visibility_employee'))),
              ],
              onChanged: (v) => setState(() {
                _visibilityType = v ?? DocumentVisibilityType.all;
                _visibilityIds = [];
              }),
            ),
            if (_visibilityType == DocumentVisibilityType.department) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _departmentCodes.map((code) {
                  final selected = _visibilityIds.contains(code);
                  return FilterChip(
                    label: Text(_getDepartmentLabel(code, loc)),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) _visibilityIds.add(code);
                      else _visibilityIds.remove(code);
                    }),
                  );
                }).toList(),
              ),
            ],
            if (_visibilityType == DocumentVisibilityType.section) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _sectionCodes.map((code) {
                  final selected = _visibilityIds.contains(code);
                  return FilterChip(
                    label: Text(_getSectionLabel(code, loc)),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) _visibilityIds.add(code);
                      else _visibilityIds.remove(code);
                    }),
                  );
                }).toList(),
              ),
            ],
            if (_visibilityType == DocumentVisibilityType.employee) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _employees.map((e) {
                  final selected = _visibilityIds.contains(e.id);
                  return FilterChip(
                    label: Text(e.fullName),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) _visibilityIds.add(e.id);
                      else _visibilityIds.remove(e.id);
                    }),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Text(loc.t('documentation_body'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DocumentationRichTextEditor(
              controller: _quillController,
              readOnly: false,
              minHeight: 250,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(LocalizationService loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('documentation_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(loc.t('cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(loc.t('delete'))),
        ],
      ),
    );
    if (ok != true || !mounted || _doc == null) return;
    setState(() => _saving = true);
    try {
      await context.read<DocumentationServiceSupabase>().deleteDocument(_doc!.id);
      if (mounted) {
        AppToastService.show(loc.t('documentation_deleted'));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToastService.show(e.toString());
      }
    }
  }
}
