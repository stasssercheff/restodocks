import 'dart:convert';

import 'package:excel/excel.dart' hide TextSpan;
import 'package:intl/intl.dart';

import '../models/models.dart';
import 'inventory_download.dart';

/// Формирование текста и Excel для списка заказа (экспорт / отправка).
class OrderListExportService {
  static String _unitLabel(String unitId, String lang) =>
      CulinaryUnits.displayName(unitId, lang);

  /// Построить текст заказа в формате:
  /// От кого (компания)
  /// Кому (поставщик)
  /// Дата, время
  /// На когда заказ (дата)
  /// Список: №/наименование/ед.изм/количество
  static String buildOrderText({
    required OrderList list,
    required String companyName,
    required List<OrderListItem> itemsWithQuantities,
    required String lang,
    required DateTime documentDate,
    required String Function(String) t,
  }) {
    final lines = <String>[];
    lines.add('${t('order_export_from')}: $companyName');
    lines.add('${t('order_export_to')}: ${list.supplierName}');
    lines.add('${t('order_export_date_time')}: ${DateFormat('dd.MM.yyyy HH:mm').format(documentDate)}');
    lines.add('${t('order_export_order_for')}: ${list.orderForDate != null ? DateFormat('dd.MM.yyyy').format(list.orderForDate!) : '—'}');
    lines.add('');
    lines.add('${t('order_export_list')}:');
    lines.add('${t('order_export_no')}\t${t('inventory_item_name')}\t${t('order_list_unit')}\t${t('order_list_quantity')}');
    for (var i = 0; i < itemsWithQuantities.length; i++) {
      final item = itemsWithQuantities[i];
      final qty = item.quantity == item.quantity.truncateToDouble()
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      lines.add('${i + 1}\t${item.productName}\t${_unitLabel(item.unit, lang)}\t$qty');
    }
    final commentText = list.comment.trim();
    if (commentText.isNotEmpty) {
      lines.add('');
      lines.add('${t('order_list_comment')}: $commentText');
    }
    return lines.join('\n');
  }

  /// Сохранить текст в файл.
  static Future<String> saveTextFile({
    required String content,
    required String listName,
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fileName = 'order_${listName.replaceAll(RegExp(r'[^\w\-.\s]'), '_')}_$dateStr.txt';
    final bytes = utf8.encode(content);
    await saveFileBytes(fileName, bytes);
    return fileName;
  }

  /// Построить Excel и сохранить.
  static Future<String> saveExcelFile({
    required OrderList list,
    required String companyName,
    required List<OrderListItem> itemsWithQuantities,
    required String lang,
    required DateTime documentDate,
    required String Function(String) t,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];

    sheet.appendRow([TextCellValue('${t('order_export_from')}: $companyName')]);
    sheet.appendRow([TextCellValue('${t('order_export_to')}: ${list.supplierName}')]);
    sheet.appendRow([TextCellValue('${t('order_export_date_time')}: ${DateFormat('dd.MM.yyyy HH:mm').format(documentDate)}')]);
    sheet.appendRow([TextCellValue('${t('order_export_order_for')}: ${list.orderForDate != null ? DateFormat('dd.MM.yyyy').format(list.orderForDate!) : '—'}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue(t('order_export_no')),
      TextCellValue(t('inventory_item_name')),
      TextCellValue(t('order_list_unit')),
      TextCellValue(t('order_list_quantity')),
    ]);
    for (var i = 0; i < itemsWithQuantities.length; i++) {
      final item = itemsWithQuantities[i];
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(item.productName),
        TextCellValue(_unitLabel(item.unit, lang)),
        DoubleCellValue(item.quantity),
      ]);
    }
    final commentText = list.comment.trim();
    if (commentText.isNotEmpty) {
      sheet.appendRow([]);
      sheet.appendRow([TextCellValue('${t('order_list_comment')}: $commentText')]);
    }

    final out = excel.encode();
    if (out == null || out.isEmpty) throw StateError('Failed to encode Excel');

    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fileName = 'order_${list.name.replaceAll(RegExp(r'[^\w\-.\s]'), '_')}_$dateStr.xlsx';
    await saveFileBytes(fileName, out);
    return fileName;
  }

  /// URL для WhatsApp: wa.me/PHONE?text=MESSAGE (телефон без +, только цифры).
  static String? whatsAppUrl(String? phone, String message) {
    final p = phone?.replaceAll(RegExp(r'[\s\-\(\)]'), '') ?? '';
    if (p.isEmpty) return null;
    final digits = p.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;
    return 'https://wa.me/$digits?text=${Uri.encodeComponent(message)}';
  }

  /// URL для Telegram: t.me/USERNAME?text=MESSAGE или t.me/+PHONE?text=MESSAGE.
  static String? telegramUrl(String? telegram, String message) {
    final t = telegram?.trim();
    if (t == null || t.isEmpty) return null;
    final clean = t.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (clean.isEmpty) return null;
    final digits = clean.replaceAll(RegExp(r'[^\d]'), '');
    final isPhone = digits.length >= 10;
    final path = isPhone
        ? (clean.startsWith('+') ? clean : '+$digits')
        : clean.replaceFirst(RegExp(r'^@'), '');
    return 'https://t.me/$path?text=${Uri.encodeComponent(message)}';
  }

  /// URL для Email: mailto:EMAIL?subject=...&body=...
  static String? mailToUrl(String? email, String subject, String body) {
    final e = email?.trim();
    if (e == null || e.isEmpty) return null;
    return 'mailto:$e?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
  }
}
