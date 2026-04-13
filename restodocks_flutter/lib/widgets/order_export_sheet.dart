import 'package:flutter/material.dart';
import '../utils/dev_log.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';

/// Bottom sheet с выбором: сохранить Excel, сохранить текст, PDF, копировать, отправить по почте/WhatsApp/Telegram.
/// При любом действии — автоматически сохраняет заказ во входящие (шефу и собственнику).
/// Лист закрывается сразу при нажатии; долгие операции (email, PDF) выполняются в фоне.
class OrderExportSheet extends StatefulWidget {
  const OrderExportSheet({
    super.key,
    required this.list,
    required this.itemsWithQuantities,
    required this.companyName,
    required this.loc,
    required this.onSaved,
    this.exportLang,
    this.commentSourceLang,
    this.itemsSourceLang,
    this.onExportToInbox,
  });

  final OrderList list;
  final List<OrderListItem> itemsWithQuantities;
  final String companyName;
  final LocalizationService loc;
  final void Function(String message) onSaved;
  /// Язык документа (может отличаться от языка UI). Если null — используется текущий язык UI.
  final String? exportLang;
  /// Язык, на котором написан комментарий. Если null — используется текущий язык UI.
  final String? commentSourceLang;
  /// Язык, на котором записаны productName в itemsWithQuantities. Если null — текущий язык UI.
  final String? itemsSourceLang;
  /// Вызывается после успешного экспорта — сохраняет заказ во входящие.
  final Future<void> Function()? onExportToInbox;

  @override
  State<OrderExportSheet> createState() => _OrderExportSheetState();
}

/// Снимок всех данных, необходимых для фоновых операций после закрытия листа.
class _ExportSnapshot {
  final OrderList list;
  final List<OrderListItem> items;  // уже переведённые
  final String companyName;
  final String docLang;
  final String Function(String) t;
  final void Function(String) onSaved;
  final Future<void> Function()? onExportToInbox;

  const _ExportSnapshot({
    required this.list,
    required this.items,
    required this.companyName,
    required this.docLang,
    required this.t,
    required this.onSaved,
    required this.onExportToInbox,
  });
}

class _OrderExportSheetState extends State<OrderExportSheet> {
  /// Переведённые названия продуктов: оригинал -> перевод
  final Map<String, String> _translatedNames = {};
  /// Переведённый комментарий
  String? _translatedComment;
  bool _translating = false;

  String get _docLang => widget.exportLang ?? widget.loc.currentLanguageCode;
  String _t(String key) => widget.loc.tForLanguage(_docLang, key);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preTranslate());
  }

  /// Переводим названия продуктов и комментарий.
  /// Если docLang == 'ru' — продукты уже хранятся на русском, перевод не нужен.
  /// Если docLang != 'ru' — берём getLocalizedName(_docLang) по productId.
  /// Комментарий: переводим если commentSourceLang != _docLang.
  Future<void> _preTranslate() async {
    final uiLang = widget.loc.currentLanguageCode;
    final commentSrcLang = widget.commentSourceLang ?? uiLang;
    if (!mounted) return;

    // Продукты переводим только если docLang != 'ru' (имена хранятся на русском)
    final needProductTranslation = _docLang != 'ru' &&
        widget.itemsWithQuantities.any((i) => i.productName.trim().isNotEmpty);
    final needCommentTranslation = commentSrcLang != _docLang &&
        widget.list.comment.trim().isNotEmpty;

    if (!needProductTranslation && !needCommentTranslation) return;

    setState(() => _translating = true);
    try {
      final translationSvc = context.read<TranslationService>();
      final productStore = context.read<ProductStoreSupabase>();

      if (needProductTranslation) {
        // Загружаем продукты если ещё не загружены
        if (productStore.allProducts.isEmpty) await productStore.loadProducts();

        // Переводим каждый продукт по productId → getLocalizedName(_docLang)
        for (final item in widget.itemsWithQuantities) {
          if (!mounted) break;
          final name = item.productName.trim();
          if (name.isEmpty) continue;

          final productId = item.productId;
          final product = (productId != null && productId.isNotEmpty)
              ? productStore.allProducts.where((p) => p.id == productId).firstOrNull
              : null;

          if (product != null) {
            final locName = product.getLocalizedName(_docLang);
            if (locName != name && mounted) {
              setState(() => _translatedNames[name] = locName);
            } else if (locName == name) {
              // Перевода нет в names[] — запрашиваем через pipeline с таймаутом
              final updatedNames = await productStore
                  .translateProductAwait(productId!)
                  .timeout(const Duration(seconds: 5), onTimeout: () => null);
              final translated = updatedNames?[_docLang];
              if (translated != null && translated != name && mounted) {
                setState(() => _translatedNames[name] = translated);
              }
            }
          }
        }
      }

      // Переводим комментарий (язык написания → язык документа)
      if (needCommentTranslation && mounted) {
        final comment = widget.list.comment.trim();
        // Включаем хеш текста в entityId — при изменении комментария кеш не применяется
        final commentHash = comment.hashCode.toRadixString(16);
        final translatedComment = await translationSvc.translate(
          entityType: TranslationEntityType.ui,
          entityId: 'order_comment_${widget.list.id}_$commentHash',
          fieldName: 'comment',
          text: comment,
          from: commentSrcLang,
          to: _docLang,
        );
        if (translatedComment != null && translatedComment != comment && mounted) {
          setState(() => _translatedComment = translatedComment);
        }
      }
    } catch (e) {
      devLog('OrderExportSheet _preTranslate error: $e');
    }
    if (mounted) setState(() => _translating = false);
  }

  /// Список продуктов с переведёнными именами
  List<OrderListItem> get _translatedItems => widget.itemsWithQuantities.map((item) {
    final translated = _translatedNames[item.productName.trim()];
    return translated != null ? item.copyWith(productName: translated) : item;
  }).toList();

  /// OrderList с переведённым комментарием
  OrderList get _translatedList {
    final comment = _translatedComment ?? widget.list.comment;
    return widget.list.copyWith(comment: comment);
  }

  // ─── Снимок состояния и закрытие листа ────────────────────────────────────

  /// Снимаем всё необходимое ДО pop(), затем запускаем фоновую задачу.
  void _runAction(BuildContext context, Future<void> Function(_ExportSnapshot) action) {
    // Snapshot captured while State is still alive
    final snap = _ExportSnapshot(
      list: _translatedList,
      items: _translatedItems,
      companyName: widget.companyName,
      docLang: _docLang,
      t: _t,
      onSaved: widget.onSaved,
      onExportToInbox: widget.onExportToInbox,
    );
    Navigator.of(context).pop();
    action(snap);
  }

  Future<bool> _consumeTrialSaveForProductOrder() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null || !account.isTrialOnlyWithoutPaid) return true;
    try {
      await account.trialIncrementDeviceSaveOrThrow(
        establishmentId: est.id,
        docKind: TrialDeviceSaveKinds.productOrder,
      );
      return true;
    } catch (e) {
      if (e.toString().contains('TRIAL_DEVICE_SAVE_CAP')) {
        widget.onSaved(
          'В первые 72 часа можно сохранить не более 3 файлов этого типа.',
        );
        return false;
      }
      rethrow;
    }
  }

  // ─── Фоновые задачи (получают snapshot, не обращаются к State) ───────────

  static Future<void> _saveExcelBg(_ExportSnapshot s) async {
    try {
      final fileName = await OrderListExportService.saveExcelFile(
        list: s.list,
        companyName: s.companyName,
        itemsWithQuantities: s.items,
        lang: s.docLang,
        documentDate: DateTime.now(),
        t: s.t,
      );
      await s.onExportToInbox?.call();
      s.onSaved('${s.t('order_export_excel_saved')}: $fileName');
    } catch (e) {
      s.onSaved('${s.t('error_short')}: $e');
    }
  }

  static Future<void> _saveTextBg(_ExportSnapshot s) async {
    try {
      final content = _buildText(s);
      final fileName = await OrderListExportService.saveTextFile(
        content: content,
        listName: s.list.name,
      );
      await s.onExportToInbox?.call();
      s.onSaved('${s.t('order_export_text_saved')}: $fileName');
    } catch (e) {
      s.onSaved('${s.t('error_short')}: $e');
    }
  }

  static Future<void> _savePdfBg(_ExportSnapshot s) async {
    try {
      final pdfBytes = await OrderListExportService.buildOrderPdfBytes(
        list: s.list,
        companyName: s.companyName,
        itemsWithQuantities: s.items,
        lang: s.docLang,
        documentDate: DateTime.now(),
        t: s.t,
      );
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      final safeName = s.list.name.replaceAll(RegExp(r'[^\w\-.\s]'), '_');
      final fileName = 'order_${safeName}_$dateStr.pdf';
      await saveFileBytes(fileName, pdfBytes);
      await s.onExportToInbox?.call();
      s.onSaved('${s.t('order_export_pdf_saved')}: $fileName');
    } catch (e) {
      s.onSaved('${s.t('error_short')}: $e');
    }
  }

  static Future<void> _copyToClipboardBg(_ExportSnapshot s) async {
    final content = _buildText(s);
    await Clipboard.setData(ClipboardData(text: content));
    await s.onExportToInbox?.call();
    s.onSaved(s.t('order_export_copied'));
  }

  static Future<void> _sendEmailBg(_ExportSnapshot s) async {
    final to = s.list.email!.trim();
    final content = _buildText(s);
    final subject = '${s.t('product_order')}: ${s.companyName}';
    final htmlBody = '<pre style="font-family: sans-serif; white-space: pre-wrap;">${_escapeHtml(content)}</pre>';
    final dateStr = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final safeCompany = s.companyName.replaceAll(RegExp(r'[^\w\-.\s]'), '_');
    final safeListName = s.list.name.replaceAll(RegExp(r'[^\w\-.\s]'), '_');
    final pdfFileName = 'order_${safeCompany}_${safeListName}_$dateStr.pdf';

    // Генерируем PDF — если не получилось, письмо уйдёт без вложения.
    // lightweight=true: только Regular шрифт (~500KB вместо ~1.7MB) — меньший base64 в запросе.
    List<int>? pdfBytes;
    String? pdfError;
    try {
      pdfBytes = await OrderListExportService.buildOrderPdfBytes(
        list: s.list,
        companyName: s.companyName,
        itemsWithQuantities: s.items,
        lang: s.docLang,
        documentDate: DateTime.now(),
        t: s.t,
        lightweight: true,
      );
      devLog('OrderExportSheet: PDF generated (lightweight), size=${pdfBytes.length} bytes');
    } catch (e) {
      pdfError = e.toString();
      devLog('OrderExportSheet: PDF generation failed: $e');
    }

    try {
      devLog('OrderExportSheet: sending email to=$to, pdfBytes=${pdfBytes?.length ?? 0} bytes, pdfError=$pdfError');
      final result = await EmailService().sendOrderEmail(
        to: to,
        subject: subject,
        html: htmlBody,
        pdfBytes: pdfBytes,
        pdfFileName: pdfFileName,
      );
      devLog('OrderExportSheet: sendOrderEmail result ok=${result.ok} error=${result.error}');
      if (result.ok) {
        await s.onExportToInbox?.call();
        if (pdfError != null) {
          s.onSaved('${s.t('order_export_email_sent')} (PDF error: $pdfError)');
        } else if (pdfBytes == null || pdfBytes.isEmpty) {
          s.onSaved('${s.t('order_export_email_sent')} (no PDF)');
        } else {
          s.onSaved(s.t('order_export_email_sent'));
        }
      } else {
        s.onSaved('${s.t('error_short')}: ${result.error}');
      }
    } catch (e) {
      devLog('OrderExportSheet: sendOrderEmail exception: $e');
      s.onSaved('${s.t('error_short')}: $e');
    }
  }

  static Future<void> _sendWhatsAppBg(_ExportSnapshot s) async {
    final content = _buildText(s);
    final phone = s.list.whatsapp?.isNotEmpty == true ? s.list.whatsapp! : s.list.phone;
    final url = OrderListExportService.whatsAppUrl(phone, content);
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      await s.onExportToInbox?.call();
    }
  }

  static Future<void> _sendTelegramBg(_ExportSnapshot s) async {
    final content = _buildText(s);
    final url = OrderListExportService.telegramUrl(s.list.telegram, content);
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      await s.onExportToInbox?.call();
    }
  }

  // ─── Вспомогательные статические методы ───────────────────────────────────

  static String _buildText(_ExportSnapshot s) {
    return OrderListExportService.buildOrderText(
      list: s.list,
      companyName: s.companyName,
      itemsWithQuantities: s.items,
      lang: s.docLang,
      documentDate: DateTime.now(),
      t: s.t,
    );
  }

  static String _escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  bool get _hasEmail => widget.list.email?.trim().isNotEmpty == true;
  bool get _hasWhatsApp =>
      (widget.list.whatsapp?.trim().isNotEmpty ?? false) ||
      (widget.list.phone?.trim().isNotEmpty ?? false);
  bool get _hasTelegram => widget.list.telegram?.trim().isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t('order_export_title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _t('order_export_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (_translating) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(
                      _t('loading'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Скроллируемый список действий с ограниченной высотой
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionTile(
                        icon: Icons.table_chart,
                        label: _t('order_export_save_excel'),
                        onTap: _translating
                            ? null
                            : () async {
                                if (!await _consumeTrialSaveForProductOrder()) return;
                                _runAction(context, _saveExcelBg);
                              },
                      ),
                      _ActionTile(
                        icon: Icons.picture_as_pdf,
                        label: _t('order_export_save_pdf'),
                        onTap: _translating
                            ? null
                            : () async {
                                if (!await _consumeTrialSaveForProductOrder()) return;
                                _runAction(context, _savePdfBg);
                              },
                      ),
                      _ActionTile(
                        icon: Icons.description,
                        label: _t('order_export_save_text'),
                        onTap: _translating
                            ? null
                            : () async {
                                if (!await _consumeTrialSaveForProductOrder()) return;
                                _runAction(context, _saveTextBg);
                              },
                      ),
                      _ActionTile(
                        icon: Icons.copy,
                        label: _t('order_export_copy'),
                        onTap: _translating ? null : () => _runAction(context, _copyToClipboardBg),
                      ),
                      if (_hasEmail)
                        _ActionTile(
                          icon: Icons.email,
                          label: '${_t('order_export_send_email')} (${widget.list.email})',
                          onTap: _translating ? null : () => _runAction(context, _sendEmailBg),
                        ),
                      if (_hasWhatsApp)
                        _ActionTile(
                          icon: Icons.chat,
                          label: _t('order_export_send_whatsapp'),
                          onTap: _translating ? null : () => _runAction(context, _sendWhatsAppBg),
                        ),
                      if (_hasTelegram)
                        _ActionTile(
                          icon: Icons.send,
                          label: _t('order_export_send_telegram'),
                          onTap: _translating ? null : () => _runAction(context, _sendTelegramBg),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_t('cancel')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}
