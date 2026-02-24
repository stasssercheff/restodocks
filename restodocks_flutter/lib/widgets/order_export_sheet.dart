import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Bottom sheet с выбором: сохранить Excel, сохранить текст, копировать в буфер, отправить по почте/WhatsApp/Telegram.
class OrderExportSheet extends StatelessWidget {
  const OrderExportSheet({
    super.key,
    required this.list,
    required this.itemsWithQuantities,
    required this.companyName,
    required this.loc,
    required this.onSaved,
  });

  final OrderList list;
  final List<OrderListItem> itemsWithQuantities;
  final String companyName;
  final LocalizationService loc;
  final void Function(String message) onSaved;

  String _t(String key) => loc.t(key);

  List<OrderListItem> get _items => itemsWithQuantities;

  String _buildText() {
    final docDate = DateTime.now();
    return OrderListExportService.buildOrderText(
      list: list,
      companyName: companyName,
      itemsWithQuantities: _items,
      lang: loc.currentLanguageCode,
      documentDate: docDate,
      t: _t,
    );
  }

  Future<void> _saveExcel(BuildContext context) async {
    try {
      final fileName = await OrderListExportService.saveExcelFile(
        list: list,
        companyName: companyName,
        itemsWithQuantities: _items,
        lang: loc.currentLanguageCode,
        documentDate: DateTime.now(),
        t: _t,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        onSaved('${_t('order_export_excel_saved')}: $fileName');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t('error_short')}: $e')),
        );
      }
    }
  }

  Future<void> _saveText(BuildContext context) async {
    try {
      final content = _buildText();
      final fileName = await OrderListExportService.saveTextFile(
        content: content,
        listName: list.name,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        onSaved('${_t('order_export_text_saved')}: $fileName');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t('error_short')}: $e')),
        );
      }
    }
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    final content = _buildText();
    await Clipboard.setData(ClipboardData(text: content));
    if (context.mounted) {
      Navigator.of(context).pop();
      onSaved(_t('order_export_copied'));
    }
  }

  Future<void> _sendEmail(BuildContext context) async {
    final to = list.email!.trim();
    final content = _buildText();
    final subject = '${_t('product_order')}: $companyName';
    final htmlBody = '<pre style="font-family: sans-serif; white-space: pre-wrap;">${_escapeHtml(content)}</pre>';
    final dateStr = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final safeCompany = companyName.replaceAll(RegExp(r'[^\w\-.\s]'), '_');
    final safeListName = list.name.replaceAll(RegExp(r'[^\w\-.\s]'), '_');
    final pdfFileName = 'order_${safeCompany}_${safeListName}_$dateStr.pdf';

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('sending'))),
      );
    }

    final pdfBytes = await OrderListExportService.buildOrderPdfBytes(
      list: list,
      companyName: companyName,
      itemsWithQuantities: _items,
      lang: loc.currentLanguageCode,
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

    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (result.ok) {
      onSaved(_t('order_export_email_sent'));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('error_short')}: ${result.error}')),
      );
    }
  }

  static String _escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  Future<void> _sendWhatsApp(BuildContext context) async {
    final content = _buildText();
    final phone = list.whatsapp?.isNotEmpty == true ? list.whatsapp! : list.phone;
    final url = OrderListExportService.whatsAppUrl(phone, content);
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _sendTelegram(BuildContext context) async {
    final content = _buildText();
    final url = OrderListExportService.telegramUrl(list.telegram, content);
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  bool get _hasEmail => list.email?.trim().isNotEmpty == true;
  bool get _hasWhatsApp =>
      (list.whatsapp?.trim().isNotEmpty ?? false) || (list.phone?.trim().isNotEmpty ?? false);
  bool get _hasTelegram => list.telegram?.trim().isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
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
            const SizedBox(height: 16),
            Text(
              _t('order_export_subtitle'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  _ActionTile(
                    icon: Icons.table_chart,
                    label: _t('order_export_save_excel'),
                    onTap: () => _saveExcel(context),
                  ),
                  _ActionTile(
                    icon: Icons.description,
                    label: _t('order_export_save_text'),
                    onTap: () => _saveText(context),
                  ),
                  _ActionTile(
                    icon: Icons.copy,
                    label: _t('order_export_copy'),
                    onTap: () => _copyToClipboard(context),
                  ),
                  if (_hasEmail)
                    _ActionTile(
                      icon: Icons.email,
                      label: '${_t('order_export_send_email')} (${list.email})',
                      onTap: () => _sendEmail(context),
                    ),
                  if (_hasWhatsApp)
                    _ActionTile(
                      icon: Icons.chat,
                      label: _t('order_export_send_whatsapp'),
                      onTap: () => _sendWhatsApp(context),
                    ),
                  if (_hasTelegram)
                    _ActionTile(
                      icon: Icons.send,
                      label: _t('order_export_send_telegram'),
                      onTap: () => _sendTelegram(context),
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
