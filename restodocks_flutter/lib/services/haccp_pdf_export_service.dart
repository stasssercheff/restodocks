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
          build: (ctx) => pw.Stack(
            children: [
              pw.Positioned(
                top: 0,
                right: 0,
                child: pw.Text(
                  sanpinRef,
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              ),
              pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      journalTitle.toUpperCase(),
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Text(
                      establishmentName,
                      style: pw.TextStyle(fontSize: 14),
                    ),
                    pw.SizedBox(height: 24),
                    pw.Text(
                      'Период: ${dateFmt.format(dateFrom)} — ${dateFmt.format(dateTo)}',
                      style: pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final colKeys = logs.isNotEmpty
        ? _collectColumnKeys(logs)
        : _defaultColumnKeysForType(logType);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.fromLTRB(24, 50, 24, 40),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.SizedBox.shrink(),
                pw.Text(
                  journalTitle.toUpperCase(),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  sanpinRef,
                  style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                establishmentName,
                style: pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        build: (ctx) {
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
          const blankRowCount = 25;
          final rowCount = logs.isEmpty ? blankRowCount : logs.length;
          for (var i = 0; i < rowCount; i++) {
            final cells = <pw.Widget>[
              _cell('${i + 1}'),
              _cell(logs.length > i ? dateTimeFmt.format(logs[i].createdAt) : ''),
              ...colKeys.map((k) => _cell(
                  logs.length > i ? (logs[i].toPdfRow()[k] ?? '') : '')),
              _cell(logs.length > i
                  ? (employeeIdToName[logs[i].createdByEmployeeId] ?? logs[i].createdByEmployeeId)
                  : ''),
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

  /// Колонки для пустого бланка по типу журнала.
  static List<String> _defaultColumnKeysForType(HaccpLogType logType) {
    switch (logType.targetTable) {
      case HaccpLogTable.numeric:
        return switch (logType) {
          HaccpLogType.uvLamps => ['value1', 'note'],
          HaccpLogType.fridgeTemperature => ['value1', 'equipment', 'note'],
          HaccpLogType.warehouseTempHumidity => ['value1', 'value2', 'note'],
          HaccpLogType.disinfectantConcentration => ['value1', 'note'],
          _ => ['value1', 'value2', 'equipment', 'note'],
        };
      case HaccpLogTable.status:
        return switch (logType) {
          HaccpLogType.healthHygiene || HaccpLogType.pediculosis => ['status', 'note'],
          HaccpLogType.dishwasherControl => ['status', 'status2', 'note'],
          HaccpLogType.glassCeramicsBreakage => ['description', 'location'],
          HaccpLogType.emergencyIncidents => ['description', 'note'],
          _ => ['status', 'status2', 'description', 'location', 'note'],
        };
      case HaccpLogTable.quality:
        return switch (logType) {
          HaccpLogType.finishedProductBrakerage ||
          HaccpLogType.incomingRawBrakerage => ['product', 'result', 'note'],
          HaccpLogType.fryingOil => ['action', 'oil_name', 'note'],
          HaccpLogType.foodWaste => ['weight', 'reason', 'note'],
          HaccpLogType.disinsectionDeratization => ['agent', 'note'],
          _ => ['product', 'result', 'weight', 'reason', 'action', 'agent', 'concentration', 'note'],
        };
    }
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
