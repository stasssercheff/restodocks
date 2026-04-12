import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/employee.dart';
import '../models/establishment.dart';

enum HaccpOrderThirdPageMode {
  empty,
  filled,
}

/// Перевод строк PDF приказа (те же ключи, что в [LocalizationService.t]).
typedef HaccpOrderPdfTranslate = String Function(
  String key, {
  Map<String, String>? args,
});

class HaccpOrderPdfService {
  static pw.ThemeData? _theme;
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  static Future<pw.ThemeData> _getTheme() async {
    if (_theme != null) return _theme!;
    final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _fontRegular = pw.Font.ttf(baseData);
    _fontBold = pw.Font.ttf(boldData);
    _theme = pw.ThemeData.withFont(
      base: _fontRegular!,
      bold: _fontBold!,
      italic: _fontRegular!,
      boldItalic: _fontBold!,
    );
    return _theme!;
  }

  static String _employeeFullName(Employee e) {
    final parts = <String>[];
    if (e.fullName.trim().isNotEmpty) parts.add(e.fullName.trim());
    if (e.surname != null && e.surname!.trim().isNotEmpty) {
      parts.add(e.surname!.trim());
    }
    return parts.join(' ');
  }

  static String _employeePositionLine(
    Employee e,
    Establishment establishment,
    HaccpOrderPdfTranslate tr,
  ) {
    final role = e.positionRole?.trim();
    if (role != null && role.isNotEmpty) {
      final key = 'role_$role';
      final out = tr(key);
      if (out != key) return out;
      return role;
    }
    if (e.hasRole('owner')) {
      final d = establishment.directorPosition?.trim();
      if (d != null && d.isNotEmpty) return d;
      return tr('haccp_order_pdf_default_director_title');
    }
    return '';
  }

  static String _directorFioOrUnderline(String? directorFio) {
    final v = (directorFio ?? '').trim();
    return v.isNotEmpty ? v : '______________';
  }

  static String _underline([String text = '______________']) => text;

  static Future<Uint8List> buildOrderPdfBytes({
    required HaccpOrderPdfTranslate tr,
    required Establishment establishment,
    required HaccpOrderThirdPageMode thirdPageMode,
    required List<Employee> selectedEmployees,
  }) async {
    final theme = await _getTheme();
    final doc = pw.Document(theme: theme);

    final textStyle = pw.TextStyle(fontSize: 10);
    final titleStyle =
        pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
    final sectionTitleStyle =
        pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
    final smallStyle = pw.TextStyle(fontSize: 9);

    final directorFio = _directorFioOrUnderline(establishment.directorFio);
    final organizationName = (establishment.legalName ?? establishment.name).trim();
    final placeholderResponsible = tr('haccp_order_pdf_placeholder_position_fio');

    // -------------------- Page 1 --------------------
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(tr('haccp_order_pdf_order_number_title'), style: titleStyle),
              pw.SizedBox(height: 6),
              pw.Text(
                tr('haccp_order_pdf_order_subject'),
                style: smallStyle,
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                tr('haccp_order_pdf_date_place_template'),
                style: textStyle,
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                tr('haccp_order_pdf_p1_intro_sanpin'),
                style: textStyle,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                tr('haccp_order_pdf_i_hereby_order'),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                tr(
                  'haccp_order_pdf_p1_body_paragraphs',
                  args: {
                    'organization': organizationName,
                    'placeholder_responsible': placeholderResponsible,
                  },
                ),
                style: textStyle,
              ),
              pw.Spacer(),
              pw.SizedBox(height: 16),
              pw.Text(
                tr('haccp_order_pdf_sign_manager_line',
                    args: {'director_fio': directorFio}),
                style: textStyle,
              ),
              pw.Text(tr('haccp_order_pdf_caption_signature_fio'), style: smallStyle),
              pw.SizedBox(height: 6),
              pw.Text(tr('haccp_order_pdf_seal_initials'), style: smallStyle),
            ],
          );
        },
      ),
    );

    // -------------------- Page 2 --------------------
    final appendixData = <List<dynamic>>[];
    for (var i = 0; i < 12; i++) {
      final n = (i + 1).toString().padLeft(2, '0');
      appendixData.add([
        '${i + 1}',
        tr('haccp_order_pdf_jr${n}_name'),
        tr('haccp_order_pdf_row_format_mixed'),
        tr('haccp_order_pdf_jr${n}_resp'),
      ]);
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        build: (ctx) {
          final columnWidths = <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(0.2),
            1: const pw.FlexColumnWidth(2.1),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(2.0),
          };

          final headers = [
            tr('haccp_order_pdf_col_index'),
            tr('haccp_order_pdf_col_journal_name'),
            tr('haccp_order_pdf_col_record_format'),
            tr('haccp_order_pdf_col_responsible_role'),
          ];

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(tr('haccp_order_pdf_appendix1_heading'),
                  style: sectionTitleStyle),
              pw.SizedBox(height: 8),
              pw.Text(tr('haccp_order_pdf_appendix1_manifest_title'),
                  style: sectionTitleStyle),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: appendixData,
                cellPadding: const pw.EdgeInsets.all(3),
                cellHeight: 18,
                cellAlignment: pw.Alignment.topLeft,
                cellStyle: smallStyle,
                headerStyle:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                headerPadding: const pw.EdgeInsets.all(3),
                headerHeight: 22,
                columnWidths: columnWidths,
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
              ),
              pw.SizedBox(height: 12),
              pw.Text(tr('haccp_order_pdf_appendix_is_integral'), style: textStyle),
              pw.SizedBox(height: 26),
              pw.Text(tr('haccp_order_pdf_i_approve_caps'),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 8),
              pw.Text(
                tr('haccp_order_pdf_sign_manager_date_line',
                    args: {'director_fio': directorFio}),
                style: textStyle,
              ),
              pw.Text(tr('haccp_order_pdf_caption_signature_fio_date'),
                  style: smallStyle),
              pw.SizedBox(height: 10),
              pw.Text(tr('haccp_order_pdf_seal_initials'), style: smallStyle),
            ],
          );
        },
      ),
    );

    // -------------------- Page 3 --------------------
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        build: (ctx) {
          const rows = 25;
          final columnWidths = <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(0.18),
            1: const pw.FlexColumnWidth(1.9),
            2: const pw.FlexColumnWidth(1.35),
            3: const pw.FlexColumnWidth(0.85),
            4: const pw.FlexColumnWidth(0.95),
          };

          final headers = [
            tr('haccp_order_pdf_p3_col_index'),
            tr('haccp_order_pdf_p3_col_employee_fio'),
            tr('haccp_order_pdf_p3_col_position'),
            tr('haccp_order_pdf_p3_col_ack_date'),
            tr('haccp_order_pdf_p3_col_own_signature'),
          ];

          final filled = thirdPageMode == HaccpOrderThirdPageMode.filled;
          final selected = filled ? selectedEmployees : const <Employee>[];

          final data = <List<dynamic>>[];
          for (var i = 0; i < rows; i++) {
            final e = i < selected.length ? selected[i] : null;
            final fio = e != null ? _employeeFullName(e) : _underline('______________');
            final position = e != null
                ? _employeePositionLine(e, establishment, tr)
                : _underline('______________');
            data.add([
              '${i + 1}',
              fio,
              position,
              _underline('______________'),
              _underline('______________'),
            ]);
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(tr('haccp_order_pdf_ack_title'), style: sectionTitleStyle),
              pw.SizedBox(height: 10),
              pw.Text(
                tr('haccp_order_pdf_ack_statement'),
                style: textStyle,
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data,
                cellPadding: const pw.EdgeInsets.all(3),
                cellHeight: 16,
                cellAlignment: pw.Alignment.topLeft,
                cellStyle: smallStyle,
                headerStyle:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                headerPadding: const pw.EdgeInsets.all(3),
                headerHeight: 22,
                columnWidths: columnWidths,
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
              ),
              pw.SizedBox(height: 8),
              pw.Text(tr('haccp_order_pdf_ack_sheet_note'), style: textStyle),
              pw.Spacer(),
              pw.SizedBox(height: 18),
              pw.Text(tr('haccp_order_pdf_ack_keeper_line'), style: textStyle),
              pw.Text(tr('haccp_order_pdf_caption_signature_fio_short'),
                  style: smallStyle),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
