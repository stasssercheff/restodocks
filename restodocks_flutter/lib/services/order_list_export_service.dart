import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

  /// Шрифт с поддержкой кириллицы для PDF.
  static pw.ThemeData? _pdfTheme;

  // Кешированные шрифты — переиспользуются между вызовами
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;
  static pw.Font? _fontItalic;

  static Future<pw.ThemeData> _getPdfTheme() async {
    if (_pdfTheme != null) return _pdfTheme!;
    final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final italicData = await rootBundle.load('assets/fonts/Roboto-Italic.ttf');
    _fontRegular = pw.Font.ttf(baseData);
    _fontBold = pw.Font.ttf(boldData);
    _fontItalic = pw.Font.ttf(italicData);
    _pdfTheme = pw.ThemeData.withFont(
      base: _fontRegular!,
      bold: _fontBold!,
      italic: _fontItalic!,
      // boldItalic = используем italic (у нас нет отдельного файла)
      boldItalic: _fontItalic!,
    );
    return _pdfTheme!;
  }

  /// Получить italic-шрифт с гарантией кириллицы.
  static pw.TextStyle _italicStyle({double fontSize = 9}) {
    return pw.TextStyle(
      font: _fontItalic,
      fontSize: fontSize,
    );
  }

  /// Построить PDF заказа (для вложения в письмо или сохранения).
  static Future<Uint8List> buildOrderPdfBytes({
    required OrderList list,
    required String companyName,
    required List<OrderListItem> itemsWithQuantities,
    required String lang,
    required DateTime documentDate,
    required String Function(String) t,
  }) async {
    final theme = await _getPdfTheme();
    final doc = pw.Document(theme: theme);
    final orderForStr = list.orderForDate != null
        ? DateFormat('dd.MM.yyyy').format(list.orderForDate!)
        : '—';
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(documentDate);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              t('product_order'),
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Paragraph(text: '${t('order_export_from')}: $companyName'),
          pw.Paragraph(text: '${t('order_export_to')}: ${list.supplierName}'),
          pw.Paragraph(text: '${t('order_export_date_time')}: $dateStr'),
          pw.Paragraph(text: '${t('order_export_order_for')}: $orderForStr'),
          pw.SizedBox(height: 16),
          pw.Text(
            '${t('order_export_list')}:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.8),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pdfCell(t('order_export_no'), bold: true),
                  _pdfCell(t('inventory_item_name'), bold: true),
                  _pdfCell(t('order_list_unit'), bold: true),
                  _pdfCell(t('order_list_quantity'), bold: true),
                ],
              ),
              ...itemsWithQuantities.asMap().entries.map((e) {
                final i = e.key + 1;
                final item = e.value;
                final qty = item.quantity == item.quantity.truncateToDouble()
                    ? item.quantity.toInt().toString()
                    : item.quantity.toStringAsFixed(1);
                return pw.TableRow(
                  children: [
                    _pdfCell('$i'),
                    _pdfCell(item.productName),
                    _pdfCell(_unitLabel(item.unit, lang)),
                    _pdfCell(qty),
                  ],
                );
              }),
            ],
          ),
          if (list.comment.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Paragraph(
              text: '${t('order_list_comment')}: ${list.comment.trim()}',
              style: _italicStyle(fontSize: 10),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
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

  /// Построить PDF из payload входящих (с ценами и итогом).
  static Future<Uint8List> buildOrderPdfBytesFromPayload({
    required Map<String, dynamic> payload,
    required String Function(String) t,
  }) async {
    final theme = await _getPdfTheme();
    final doc = pw.Document(theme: theme);
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final items = payload['items'] as List<dynamic>? ?? [];
    final grandTotal = (payload['grandTotal'] as num?)?.toDouble() ?? 0;
    final comment = (payload['comment'] as String?)?.trim() ?? '';

    final companyName = header['establishmentName'] ?? '—';
    final supplierName = header['supplierName'] ?? '—';
    final employeeName = header['employeeName'] ?? '—';
    final createdAt = header['createdAt'] != null ? DateTime.tryParse(header['createdAt'].toString()) : null;
    final orderForDate = header['orderForDate'] != null ? DateTime.tryParse(header['orderForDate'].toString()) : null;
    final dateStr = createdAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt) : '—';
    final orderForStr = orderForDate != null ? DateFormat('dd.MM.yyyy').format(orderForDate) : '—';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              t('product_order'),
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Paragraph(text: '${t('order_export_from')}: $companyName'),
          pw.Paragraph(text: '${t('order_export_to')}: $supplierName'),
          pw.Paragraph(text: '${t('order_export_date_time')}: $dateStr'),
          pw.Paragraph(text: '${t('order_export_order_for')}: $orderForStr'),
          pw.Paragraph(text: '${t('inbox_header_employee') ?? 'Сотрудник'}: $employeeName'),
          pw.SizedBox(height: 16),
          pw.Text(
            '${t('order_export_list')}:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(2.5),
              2: const pw.FlexColumnWidth(0.8),
              3: const pw.FlexColumnWidth(0.8),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pdfCell(t('order_export_no'), bold: true),
                  _pdfCell(t('inventory_item_name'), bold: true),
                  _pdfCell(t('order_list_unit'), bold: true),
                  _pdfCell(t('order_list_quantity'), bold: true),
                  _pdfCell(t('order_list_unit_price') ?? 'Цена за ед.', bold: true),
                  _pdfCell(t('order_list_line_total') ?? 'Сумма', bold: true),
                ],
              ),
              ...items.asMap().entries.map((e) {
                final i = e.key + 1;
                final item = e.value as Map<String, dynamic>;
                final name = item['productName']?.toString() ?? '';
                final unit = item['unit']?.toString() ?? '';
                final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
                final pricePerUnit = (item['pricePerUnit'] as num?)?.toDouble() ?? 0;
                final lineTotal = (item['lineTotal'] as num?)?.toDouble() ?? 0;
                final qtyStr = qty == qty.truncateToDouble() ? qty.toInt().toString() : qty.toStringAsFixed(1);
                return pw.TableRow(
                  children: [
                    _pdfCell('$i'),
                    _pdfCell(name),
                    _pdfCell(unit),
                    _pdfCell(qtyStr),
                    _pdfCell(pricePerUnit.toStringAsFixed(2)),
                    _pdfCell(lineTotal.toStringAsFixed(2)),
                  ],
                );
              }),
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pdfCell('', bold: true),
                  _pdfCell(t('order_list_grand_total') ?? 'Итого:', bold: true),
                  _pdfCell('', bold: true),
                  _pdfCell('', bold: true),
                  _pdfCell('', bold: true),
                  _pdfCell(grandTotal.toStringAsFixed(2), bold: true),
                ],
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Paragraph(
              text: '${t('order_list_comment')}: $comment',
              style: _italicStyle(fontSize: 10),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /// Построить Excel из payload входящих (с ценами и итогом).
  static Future<Uint8List> buildOrderExcelBytesFromPayload({
    required Map<String, dynamic> payload,
    required String Function(String) t,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final items = payload['items'] as List<dynamic>? ?? [];
    final grandTotal = (payload['grandTotal'] as num?)?.toDouble() ?? 0;

    final companyName = header['establishmentName'] ?? '—';
    final supplierName = header['supplierName'] ?? '—';
    final employeeName = header['employeeName'] ?? '—';
    final createdAt = header['createdAt'] != null ? DateTime.tryParse(header['createdAt'].toString()) : null;
    final orderForDate = header['orderForDate'] != null ? DateTime.tryParse(header['orderForDate'].toString()) : null;

    sheet.appendRow([TextCellValue('${t('order_export_from')}: $companyName')]);
    sheet.appendRow([TextCellValue('${t('order_export_to')}: $supplierName')]);
    sheet.appendRow([TextCellValue('${t('inbox_header_employee') ?? 'Сотрудник'}: $employeeName')]);
    sheet.appendRow([TextCellValue('${t('order_export_date_time')}: ${createdAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt) : '—'}')]);
    sheet.appendRow([TextCellValue('${t('order_export_order_for')}: ${orderForDate != null ? DateFormat('dd.MM.yyyy').format(orderForDate) : '—'}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue(t('order_export_no')),
      TextCellValue(t('inventory_item_name')),
      TextCellValue(t('order_list_unit')),
      TextCellValue(t('order_list_quantity')),
      TextCellValue(t('order_list_unit_price') ?? 'Цена за ед.'),
      TextCellValue(t('order_list_line_total') ?? 'Сумма'),
    ]);
    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue((item['productName'] ?? '').toString()),
        TextCellValue((item['unit'] ?? '').toString()),
        DoubleCellValue((item['quantity'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((item['pricePerUnit'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((item['lineTotal'] as num?)?.toDouble() ?? 0),
      ]);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(t('order_list_grand_total') ?? 'Итого:'),
      TextCellValue(''),
      DoubleCellValue(grandTotal),
    ]);

    final comment = (payload['comment'] as String?)?.trim();
    if ((comment ?? '').isNotEmpty) {
      sheet.appendRow([]);
      sheet.appendRow([TextCellValue('${t('order_list_comment')}: $comment')]);
    }

    final out = excel.encode();
    return Uint8List.fromList(out ?? []);
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
