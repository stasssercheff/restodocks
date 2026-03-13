import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';

/// Экспорт журналов ХАССП в PDF.
/// Обложка, шапка СанПиН, лист прошивки.
class HaccpPdfExportService {
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

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  /// Параметры экспорта.
  static Future<Uint8List> buildJournalPdf({
    required String establishmentName,
    required String journalTitle,
    required String sanpinRef,
    required HaccpLogType logType,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateTime dateFrom,
    required DateTime dateTo,
    bool includeCover = true,
    bool includeStitchingSheet = true,
  }) async {
    final theme = await _getTheme();
    final doc = pw.Document(theme: theme);
    final dateFmt = DateFormat('dd.MM.yyyy');
    final dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');

    if (includeCover) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(40),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                establishmentName,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                journalTitle,
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 16),
              pw.Text('Период: с ${dateFmt.format(dateFrom)} по ${dateFmt.format(dateTo)}'),
              pw.SizedBox(height: 8),
              pw.Text(sanpinRef, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ],
          ),
        ),
      );
    }

    final colKeys = _collectColumnKeys(logs);
    final hasLogs = logs.isNotEmpty;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(24, 50, 24, 40),
        header: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              sanpinRef,
              style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ],
        ),
        build: (ctx) {
          if (!hasLogs) {
            return [
              pw.Padding(
                padding: pw.EdgeInsets.all(24),
                child: pw.Text(
                  'Нет записей за выбранный период',
                  style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                ),
              ),
            ];
          }
          final rows = <pw.TableRow>[
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _cell('№', bold: true),
                _cell('Дата и время', bold: true),
                ...colKeys.map((k) => _cell(_humanKey(k), bold: true)),
                _cell('ФИО, должность', bold: true),
              ],
            ),
          ];
          for (var i = 0; i < logs.length; i++) {
            final log = logs[i];
            final cells = <pw.Widget>[
              _cell('${i + 1}'),
              _cell(dateTimeFmt.format(log.createdAt)),
              ...colKeys.map((k) => _cell(log.toPdfRow()[k] ?? '—')),
              _cell(employeeIdToName[log.createdByEmployeeId] ?? log.createdByEmployeeId),
            ];
            rows.add(pw.TableRow(children: cells));
          }
          return [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(1.5),
                ...Map.fromIterables(
                  List.generate(colKeys.length, (i) => 2 + i),
                  colKeys.map((_) => const pw.FlexColumnWidth(1.5)),
                ),
                colKeys.length + 2: const pw.FlexColumnWidth(2),
              },
              children: rows,
            ),
          ];
        },
      ),
    );

    if (includeStitchingSheet) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(40),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Divider(),
              pw.SizedBox(height: 16),
              pw.Text(
                'В настоящем журнале пронумеровано и прошнуровано _____ листов.',
                style: pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 24),
              pw.Text('М.П. _______________________ / [Подпись руководителя]', style: pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  static List<String> _collectColumnKeys(List<HaccpLog> logs) {
    final set = <String>{};
    for (final log in logs) {
      for (final k in log.toPdfRow().keys) {
        if (k.isNotEmpty) set.add(k);
      }
    }
    return set.toList()..sort();
  }

  static String _humanKey(String key) {
    const m = {
      'value1': 'Значение 1',
      'value2': 'Влажность %',
      'equipment': 'Оборудование',
      'status': 'Статус',
      'status2': 'Статус 2',
      'description': 'Описание',
      'location': 'Место',
      'product': 'Продукция',
      'result': 'Результат',
      'weight': 'Вес',
      'reason': 'Причина',
      'action': 'Действие',
      'oil_name': 'Масло',
      'agent': 'Средство',
      'concentration': 'Концентрация',
      'note': 'Примечание',
    };
    return m[key] ?? key;
  }
}
