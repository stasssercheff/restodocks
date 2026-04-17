import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import '../utils/number_format_utils.dart';
import 'localization_service.dart';

/// Excel и PDF: приёмки поставок для раздела «Расходы».
class ProcurementReceiptExportService {
  static pw.ThemeData? _pdfTheme;
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  static Future<pw.ThemeData> _theme() async {
    if (_pdfTheme != null) return _pdfTheme!;
    final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _fontRegular = pw.Font.ttf(baseData);
    _fontBold = pw.Font.ttf(boldData);
    _pdfTheme = pw.ThemeData.withFont(
      base: _fontRegular!,
      bold: _fontBold!,
      italic: _fontRegular!,
      boldItalic: _fontBold!,
    );
    return _pdfTheme!;
  }

  static String _unitLabel(String unitId, String lang) =>
      LocalizationService().unitLabelForLanguage(unitId, lang);

  static Future<Uint8List> buildExcelBytes({
    required List<Map<String, dynamic>> documents,
    required String Function(String key) t,
    required String currency,
    required String lang,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    final dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');
    final dec = NumberFormat.decimalPattern(lang);

    sheet.appendRow([
      TextCellValue(t('expenses_procurement_col_date')),
      TextCellValue(t('expenses_procurement_col_supplier')),
      TextCellValue(t('expenses_procurement_col_employee')),
      TextCellValue(t('expenses_procurement_col_dept')),
      TextCellValue(t('product_name')),
      TextCellValue(t('order_list_unit')),
      TextCellValue(t('procurement_receipt_ordered')),
      TextCellValue(t('procurement_receipt_ref_price')),
      TextCellValue(t('procurement_receipt_received_qty')),
      TextCellValue(t('procurement_receipt_actual_price')),
      TextCellValue(t('procurement_receipt_discount')),
      TextCellValue(t('procurement_receipt_line_total')),
      TextCellValue(t('expenses_procurement_col_doc_total')),
    ]);

    double sumDocGrands = 0;

    for (final doc in documents) {
      final payload = doc['payload'] as Map<String, dynamic>? ?? {};
      final header = payload['header'] as Map<String, dynamic>? ?? {};
      final items = payload['items'] as List<dynamic>? ?? [];
      final createdAt =
          DateTime.tryParse(doc['created_at']?.toString() ?? '');
      final dateStr = createdAt != null
          ? dateTimeFmt.format(createdAt.toLocal())
          : '—';
      final supplier = header['supplierName']?.toString() ?? '—';
      final employee = header['employeeName']?.toString() ?? '—';
      final dept = header['department']?.toString() ?? '—';
      final docGrand = (payload['grandTotal'] as num?)?.toDouble() ??
          (header['receivedGrandTotal'] as num?)?.toDouble() ??
          0.0;
      sumDocGrands += docGrand;
      final docTotalStr = NumberFormatUtils.formatSum(docGrand, currency);

      for (final it in items) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        final name = m['productName']?.toString() ?? '—';
        final unit = m['unit']?.toString() ?? 'kg';
        final ordered = (m['orderedQuantity'] as num?)?.toDouble() ?? 0;
        final ref = (m['referencePricePerUnit'] as num?)?.toDouble() ?? 0;
        final rec = (m['receivedQuantity'] as num?)?.toDouble() ?? 0;
        final act = (m['actualPricePerUnit'] as num?)?.toDouble() ?? 0;
        final disc = (m['discountPercent'] as num?)?.toDouble() ?? 0;
        final line = (m['lineTotal'] as num?)?.toDouble() ?? 0;

        sheet.appendRow([
          TextCellValue(dateStr),
          TextCellValue(supplier),
          TextCellValue(employee),
          TextCellValue(dept),
          TextCellValue(name),
          TextCellValue(_unitLabel(unit, lang)),
          TextCellValue(dec.format(ordered)),
          TextCellValue(
            ref > 0 ? NumberFormatUtils.formatSum(ref, currency) : '—',
          ),
          TextCellValue(dec.format(rec)),
          TextCellValue(
            act > 0 ? NumberFormatUtils.formatSum(act, currency) : '—',
          ),
          TextCellValue(dec.format(disc)),
          TextCellValue(NumberFormatUtils.formatSum(line, currency)),
          TextCellValue(docTotalStr),
        ]);
      }
    }

    sheet.appendRow(List.generate(13, (_) => TextCellValue('')));
    sheet.appendRow([
      TextCellValue(t('expenses_procurement_export_grand')),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(NumberFormatUtils.formatSum(sumDocGrands, currency)),
    ]);

    final out = excel.encode();
    if (out == null) {
      throw StateError('procurement excel encode');
    }
    return Uint8List.fromList(out);
  }

  static Future<Uint8List> buildPdfBytes({
    required List<Map<String, dynamic>> documents,
    required String Function(String key) t,
    required String currency,
    required String lang,
  }) async {
    final theme = await _theme();
    final doc = pw.Document(theme: theme);
    final dec = NumberFormat.decimalPattern(lang);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text(
                t('expenses_procurement_export_pdf_title'),
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 12),
          ];

          double sumDocGrands = 0;

          for (final d in documents) {
            final payload = d['payload'] as Map<String, dynamic>? ?? {};
            final header = payload['header'] as Map<String, dynamic>? ?? {};
            final items = payload['items'] as List<dynamic>? ?? [];
            final createdAt =
                DateTime.tryParse(d['created_at']?.toString() ?? '');
            final dateStr = createdAt != null
                ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt.toLocal())
                : '—';
            final supplier = header['supplierName']?.toString() ?? '—';
            final employee = header['employeeName']?.toString() ?? '—';
            final dept = header['department']?.toString() ?? '—';
            final docGrand = (payload['grandTotal'] as num?)?.toDouble() ??
                (header['receivedGrandTotal'] as num?)?.toDouble() ??
                0.0;
            sumDocGrands += docGrand;

            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6, top: 8),
                child: pw.Text(
                  '$dateStr · $supplier · ${t('inbox_header_employee')}: $employee · '
                  '${t('expenses_procurement_col_dept')}: $dept · '
                  '${t('salary_total_all')}: ${NumberFormatUtils.formatSum(docGrand, currency)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            );

            final tableRows = <pw.TableRow>[
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pc(t('procurement_receipt_col_no')),
                  _pc(t('product_name')),
                  _pc(t('order_list_unit')),
                  _pc(t('procurement_receipt_ordered')),
                  _pc(t('procurement_receipt_ref_price')),
                  _pc(t('procurement_receipt_received_qty')),
                  _pc(t('procurement_receipt_actual_price')),
                  _pc(t('procurement_receipt_discount')),
                  _pc(t('procurement_receipt_line_total')),
                ],
              ),
            ];

            for (var i = 0; i < items.length; i++) {
              final it = items[i];
              if (it is! Map) continue;
              final m = Map<String, dynamic>.from(it);
              final name = m['productName']?.toString() ?? '—';
              final unit = m['unit']?.toString() ?? 'kg';
              final ordered = (m['orderedQuantity'] as num?)?.toDouble() ?? 0;
              final ref =
                  (m['referencePricePerUnit'] as num?)?.toDouble() ?? 0;
              final rec =
                  (m['receivedQuantity'] as num?)?.toDouble() ?? 0;
              final act =
                  (m['actualPricePerUnit'] as num?)?.toDouble() ?? 0;
              final disc =
                  (m['discountPercent'] as num?)?.toDouble() ?? 0;
              final line = (m['lineTotal'] as num?)?.toDouble() ?? 0;
              tableRows.add(
                pw.TableRow(
                  children: [
                    _pc('${i + 1}'),
                    _pc(name),
                    _pc(_unitLabel(unit, lang)),
                    _pc(dec.format(ordered)),
                    _pc(ref > 0 ? NumberFormatUtils.formatSum(ref, currency) : '—'),
                    _pc(dec.format(rec)),
                    _pc(act > 0 ? NumberFormatUtils.formatSum(act, currency) : '—'),
                    _pc(dec.format(disc)),
                    _pc(NumberFormatUtils.formatSum(line, currency)),
                  ],
                ),
              );
            }

            widgets.add(
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey500),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.4),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(0.7),
                  3: const pw.FlexColumnWidth(0.7),
                  4: const pw.FlexColumnWidth(0.9),
                  5: const pw.FlexColumnWidth(0.8),
                  6: const pw.FlexColumnWidth(0.9),
                  7: const pw.FlexColumnWidth(0.6),
                  8: const pw.FlexColumnWidth(1),
                },
                children: tableRows,
              ),
            );
          }

          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 16),
              child: pw.Text(
                '${t('expenses_procurement_export_grand')}: '
                '${NumberFormatUtils.formatSum(sumDocGrands, currency)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          );

          return widgets;
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _pc(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
    );
  }
}
