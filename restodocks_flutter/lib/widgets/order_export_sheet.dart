import 'package:flutter/material.dart';
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
    this.onExportToInbox,
  });

  final OrderList list;
  final List<OrderListItem> itemsWithQuantities;
  final String companyName;
  final LocalizationService loc;
  final void Function(String message) onSaved;
  /// Язык документа (может отличаться от языка UI). Если null — используется текущий язык UI.
  final String? exportLang;
  /// Вызывается после успешного экспорта — сохраняет заказ во входящие
  final Future<void> Function()? onExportToInbox;

  @override
  State<OrderExportSheet> createState() => _OrderExportSheetState();
}

class _OrderExportSheetState extends State<OrderExportSheet> {
  /// Переведённые названия продуктов: оригинал -> перевод
  final Map<String, String> _translatedNames = {};
  bool _translating = false;

  String get _docLang => widget.exportLang ?? widget.loc.currentLanguageCode;
  String _t(String key) => widget.loc.tForLanguage(_docLang, key);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preTranslateNames());
  }

  /// Переводим названия продуктов заранее, чтобы PDF/письмо/текст были переведены
  Future<void> _preTranslateNames() async {
    final sourceLang = widget.loc.currentLanguageCode;
    if (sourceLang == _docLang) return;
    if (!mounted) return;

    setState(() => _translating = true);
    try {
      final translationSvc = context.read<TranslationService>();
      final seen = <String>{};
      for (final item in widget.itemsWithQuantities) {
        final name = item.productName.trim();
        if (name.isEmpty || seen.contains(name)) continue;
        seen.add(name);
        // Для ручного ввода (productId == null) используем имя как id
        final entityId = item.productId ?? name;
        final translated = await translationSvc.translate(
          entityType: TranslationEntityType.product,
          entityId: entityId,
          fieldName: 'name',
          text: name,
          from: sourceLang,
          to: _docLang,
        );
        if (translated != null && translated != name && mounted) {
          setState(() => _translatedNames[name] = translated);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _translating = false);
  }

  /// Список продуктов с переведёнными именами
  List<OrderListItem> get _translatedItems => widget.itemsWithQuantities.map((item) {
    final translated = _translatedNames[item.productName.trim()];
    return translated != null ? item.copyWith(productName: translated) : item;
  }).toList();

  String _buildText() {
    return OrderListExportService.buildOrderText(
      list: widget.list,
      companyName: widget.companyName,
      itemsWithQuantities: _translatedItems,
      lang: _docLang,
      documentDate: DateTime.now(),
      t: _t,
    );
  }

  // ─── Закрыть лист немедленно, затем выполнить action в фоне ───────────────

  void _runAction(BuildContext context, Future<void> Function() action) {
    Navigator.of(context).pop();
    action();
  }

  Future<void> _saveExcelBg() async {
    try {
      final fileName = await OrderListExportService.saveExcelFile(
        list: widget.list,
        companyName: widget.companyName,
        itemsWithQuantities: _translatedItems,
        lang: _docLang,
        documentDate: DateTime.now(),
        t: _t,
      );
      await widget.onExportToInbox?.call();
      widget.onSaved('${_t('order_export_excel_saved')}: $fileName');
    } catch (e) {
      widget.onSaved('${_t('error_short')}: $e');
    }
  }

  Future<void> _saveTextBg() async {
    try {
      final content = _buildText();
      final fileName = await OrderListExportService.saveTextFile(
        content: content,
        listName: widget.list.name,
      );
      await widget.onExportToInbox?.call();
      widget.onSaved('${_t('order_export_text_saved')}: $fileName');
    } catch (e) {
      widget.onSaved('${_t('error_short')}: $e');
    }
  }

  Future<void> _savePdfBg() async {
    try {
      final pdfBytes = await OrderListExportService.buildOrderPdfBytes(
        list: widget.list,
        companyName: widget.companyName,
        itemsWithQuantities: _translatedItems,
        lang: _docLang,
        documentDate: DateTime.now(),
        t: _t,
      );
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      final safeName = widget.list.name.replaceAll(RegExp(r'[^\w\-.\s]'), '_');
      final fileName = 'order_${safeName}_$dateStr.pdf';
      await saveFileBytes(fileName, pdfBytes);
      await widget.onExportToInbox?.call();
      widget.onSaved('${_t('order_export_pdf_saved')}: $fileName');
    } catch (e) {
      widget.onSaved('${_t('error_short')}: $e');
    }
  }

  Future<void> _copyToClipboardBg() async {
    final content = _buildText();
    await Clipboard.setData(ClipboardData(text: content));
    await widget.onExportToInbox?.call();
    widget.onSaved(_t('order_export_copied'));
  }

  Future<void> _sendEmailBg() async {
    final to = widget.list.email!.trim();
    final content = _buildText();
    final subject = '${_t('product_order')}: ${widget.companyName}';
    final htmlBody = '<pre style="font-family: sans-serif; white-space: pre-wrap;">${_escapeHtml(content)}</pre>';
    final dateStr = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final safeCompany = widget.companyName.replaceAll(RegExp(r'[^\w\-.\s]'), '_');
    final safeListName = widget.list.name.replaceAll(RegExp(r'[^\w\-.\s]'), '_');
    final pdfFileName = 'order_${safeCompany}_${safeListName}_$dateStr.pdf';

    try {
      final pdfBytes = await OrderListExportService.buildOrderPdfBytes(
        list: widget.list,
        companyName: widget.companyName,
        itemsWithQuantities: _translatedItems,
        lang: _docLang,
        documentDate: DateTime.now(),
        t: _t,
      );
      final result = await EmailService().sendOrderEmail(
        to: to,
        subject: subject,
        html: htmlBody,
        pdfBytes: pdfBytes,
        pdfFileName: pdfFileName,
      );
      if (result.ok) {
        await widget.onExportToInbox?.call();
        widget.onSaved(_t('order_export_email_sent'));
      } else {
        widget.onSaved('${_t('error_short')}: ${result.error}');
      }
    } catch (e) {
      widget.onSaved('${_t('error_short')}: $e');
    }
  }

  Future<void> _sendWhatsAppBg() async {
    final content = _buildText();
    final phone = widget.list.whatsapp?.isNotEmpty == true ? widget.list.whatsapp! : widget.list.phone;
    final url = OrderListExportService.whatsAppUrl(phone, content);
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      await widget.onExportToInbox?.call();
    }
  }

  Future<void> _sendTelegramBg() async {
    final content = _buildText();
    final url = OrderListExportService.telegramUrl(widget.list.telegram, content);
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      await widget.onExportToInbox?.call();
    }
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
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
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
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  _ActionTile(
                    icon: Icons.table_chart,
                    label: _t('order_export_save_excel'),
                    onTap: () => _runAction(context, _saveExcelBg),
                  ),
                  _ActionTile(
                    icon: Icons.picture_as_pdf,
                    label: _t('order_export_save_pdf'),
                    onTap: () => _runAction(context, _savePdfBg),
                  ),
                  _ActionTile(
                    icon: Icons.description,
                    label: _t('order_export_save_text'),
                    onTap: () => _runAction(context, _saveTextBg),
                  ),
                  _ActionTile(
                    icon: Icons.copy,
                    label: _t('order_export_copy'),
                    onTap: () => _runAction(context, _copyToClipboardBg),
                  ),
                  if (_hasEmail)
                    _ActionTile(
                      icon: Icons.email,
                      label: '${_t('order_export_send_email')} (${widget.list.email})',
                      onTap: () => _runAction(context, _sendEmailBg),
                    ),
                  if (_hasWhatsApp)
                    _ActionTile(
                      icon: Icons.chat,
                      label: _t('order_export_send_whatsapp'),
                      onTap: () => _runAction(context, _sendWhatsAppBg),
                    ),
                  if (_hasTelegram)
                    _ActionTile(
                      icon: Icons.send,
                      label: _t('order_export_send_telegram'),
                      onTap: () => _runAction(context, _sendTelegramBg),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}
