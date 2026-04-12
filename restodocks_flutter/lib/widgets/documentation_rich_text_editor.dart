import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

import '../services/documentation_image_upload_service.dart';
import '../services/services.dart';

/// Rich text editor для документов: форматирование, изображения, вставка из Word/HTML.
class DocumentationRichTextEditor extends StatefulWidget {
  const DocumentationRichTextEditor({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.minHeight = 200,
  });

  final QuillController controller;
  final bool readOnly;
  final double minHeight;

  @override
  State<DocumentationRichTextEditor> createState() => _DocumentationRichTextEditorState();
}

class _DocumentationRichTextEditorState extends State<DocumentationRichTextEditor> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<String?> _onRequestPickImage(BuildContext context) async {
    final loc = LocalizationService();
    final source = await showModalBottomSheet<InsertImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(loc.t('documentation_image_source_gallery')),
              onTap: () => Navigator.pop(ctx, InsertImageSource.gallery),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(loc.t('documentation_image_source_camera')),
                onTap: () => Navigator.pop(ctx, InsertImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(loc.t('documentation_image_source_link')),
              onTap: () => Navigator.pop(ctx, InsertImageSource.link),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return null;

    switch (source) {
      case InsertImageSource.gallery:
        return DocumentationImageUploadService.pickAndUploadImage();
      case InsertImageSource.camera:
        return DocumentationImageUploadService.takePhotoAndUpload();
      case InsertImageSource.link:
        final url = await showDialog<String>(
          context: context,
          builder: (ctx) {
            final l = LocalizationService();
            final controller = TextEditingController();
            return AlertDialog(
              title: Text(l.t('documentation_insert_image_url_dialog_title')),
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: l.t('documentation_insert_image_url_hint'),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(ctx, v.trim().isNotEmpty ? v.trim() : null),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim().isNotEmpty ? controller.text.trim() : null),
                  child: Text(l.t('documentation_insert_image_button')),
                ),
              ],
            );
          },
        );
        return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocalizationService(),
      builder: (context, _) {
        final loc = LocalizationService();
        final placeholder = loc.t('documentation_editor_placeholder');
        final appLocale = loc.currentLocale;

        Widget withAppLocale(Widget child) {
          // Quill/Material pick up the nearest Localizations; keep toolbar and editor
          // aligned with LocalizationService (avoids mixed app language vs device/UI).
          // Kazakh Quill strings: [FlutterQuillKkDelegate] in main.dart.
          return Localizations.override(
            context: context,
            locale: appLocale,
            child: child,
          );
        }

        if (widget.readOnly) {
          return withAppLocale(
            Container(
              constraints: BoxConstraints(minHeight: widget.minHeight),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: QuillEditor(
                focusNode: _focusNode,
                scrollController: _scrollController,
                controller: widget.controller,
                config: QuillEditorConfig(
                  padding: EdgeInsets.zero,
                  placeholder: '',
                  embedBuilders: kIsWeb
                      ? FlutterQuillEmbeds.editorWebBuilders()
                      : FlutterQuillEmbeds.editorBuilders(),
                ),
              ),
            ),
          );
        }

        return withAppLocale(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              QuillSimpleToolbar(
                controller: widget.controller,
                config: QuillSimpleToolbarConfig(
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: true,
                  showFontFamily: true,
                  showFontSize: true,
                  showIndent: true,
                  showAlignmentButtons: true,
                  showHeaderStyle: true,
                  showListNumbers: true,
                  showListBullets: true,
                  showListCheck: true,
                  showCodeBlock: true,
                  showInlineCode: true,
                  showLink: true,
                  showClipboardCut: true,
                  showClipboardCopy: true,
                  showClipboardPaste: true,
                  showUndo: true,
                  showRedo: true,
                  showClearFormat: true,
                  embedButtons: FlutterQuillEmbeds.toolbarButtons(
                    imageButtonOptions: QuillToolbarImageButtonOptions(
                      imageButtonConfig: QuillToolbarImageConfig(
                        onRequestPickImage: _onRequestPickImage,
                      ),
                    ),
                    videoButtonOptions: null,
                  ),
                ),
              ),
              Container(
                constraints: BoxConstraints(minHeight: widget.minHeight),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QuillEditor(
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  controller: widget.controller,
                  config: QuillEditorConfig(
                    padding: const EdgeInsets.all(16),
                    placeholder: placeholder,
                    embedBuilders: kIsWeb
                        ? FlutterQuillEmbeds.editorWebBuilders()
                        : FlutterQuillEmbeds.editorBuilders(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Преобразует body (plain text или Delta JSON) в Document.
Document documentFromBody(String? body) {
  if (body == null || body.trim().isEmpty) {
    return Document();
  }
  final trimmed = body.trim();
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    try {
      final json = jsonDecode(body);
      return Document.fromJson(json);
    } catch (_) {}
  }
  return Document()..insert(0, trimmed);
}

/// Сериализует Document в JSON string для сохранения.
String bodyFromDocument(Document doc) {
  final delta = doc.toDelta().toJson();
  return jsonEncode(delta);
}
