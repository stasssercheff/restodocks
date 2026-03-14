import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

import '../services/documentation_image_upload_service.dart';

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
    final source = await showModalBottomSheet<InsertImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Галерея'),
              onTap: () => Navigator.pop(ctx, InsertImageSource.gallery),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Камера'),
                onTap: () => Navigator.pop(ctx, InsertImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Ссылка'),
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
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text('Вставка ссылки на изображение'),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'https://example.com/image.jpg',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(ctx, v.trim().isNotEmpty ? v.trim() : null),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim().isNotEmpty ? controller.text.trim() : null),
                  child: const Text('Вставить'),
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
    if (widget.readOnly) {
      return Container(
        constraints: BoxConstraints(minHeight: widget.minHeight),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
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
      );
    }

    return Column(
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
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: QuillEditor(
            focusNode: _focusNode,
            scrollController: _scrollController,
            controller: widget.controller,
            config: QuillEditorConfig(
              padding: const EdgeInsets.all(16),
              placeholder: 'Введите текст...',
              embedBuilders: kIsWeb
                  ? FlutterQuillEmbeds.editorWebBuilders()
                  : FlutterQuillEmbeds.editorBuilders(),
            ),
          ),
        ),
      ],
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
