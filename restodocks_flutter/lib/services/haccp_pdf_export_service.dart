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

  static pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Align(
          alignment: align == pw.TextAlign.center ? pw.Alignment.center : pw.Alignment.centerLeft,
          child: pw.Text(
            text,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      );

  static const _sanpinHealthHygiene = 'Приложение № 1 к СанПиН 2.3/2.4.3590-20';
  static const _titleHealthHygiene = 'ГИГИЕНИЧЕСКИЙ ЖУРНАЛ (СОТРУДНИКИ)';

  /// Гигиенический журнал: макет по Приложению № 1 СанПиН 2.3/2.4.3590-20.
  /// Графы: № п/п, Дата, Ф.И.О., Должность, подпись об отсутствии инфекц., подпись об отсутствии ОРВИ/гнойничк., результат осмотра (допущен/отстранен), подпись ответственного.
  static pw.Widget _buildHealthHygienePage({
    required String establishmentName,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
  }) {
    (String name, String position) _parseEmp(String s) {
      final idx = s.lastIndexOf(', ');
      if (idx > 0) return (s.substring(0, idx).trim(), s.substring(idx + 2).trim());
      return (s, '');
    }

    const border = pw.BorderSide(color: PdfColors.black, width: 0.5);
    final tableBorder = pw.TableBorder(
      left: border,
      top: border,
      right: border,
      bottom: border,
      horizontalInside: border,
      verticalInside: border,
    );

    pw.Widget _headerCell(String text) => pw.Padding(
          padding: pw.EdgeInsets.all(2),
          child: pw.Center(
            child: pw.Text(text, style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          ),
        );

    final colWidths = {
      0: const pw.FlexColumnWidth(0.3),
      1: const pw.FlexColumnWidth(0.9),
      2: const pw.FlexColumnWidth(1.4),
      3: const pw.FlexColumnWidth(0.8),
      4: const pw.FlexColumnWidth(1.3),
      5: const pw.FlexColumnWidth(1.5),
      6: const pw.FlexColumnWidth(0.9),
      7: const pw.FlexColumnWidth(1.2),
    };

    final headerRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _headerCell('№ п/п'),
          _headerCell('Дата'),
          _headerCell('Ф.И.О. работника\n(последнее при наличии)'),
          _headerCell('Должность'),
          _headerCell('Подпись сотрудника об отсутствии признаков инфекционных заболеваний у сотрудника и членов семьи'),
          _headerCell('Подпись сотрудника об отсутствии заболеваний верхних дыхательных путей и гнойничковых заболеваний кожи рук и открытых поверхностей тела'),
          _headerCell('Результат осмотра\n(допущен / отстранен)'),
          _headerCell('Подпись медицинского работника\n(ответственного лица)'),
        ],
      ),
    ];

    String col5(HaccpLog? log) {
      if (log == null) return '';
      if (log.statusOk == true) return 'Да';
      return '';
    }

    String col6(HaccpLog? log) {
      if (log == null) return '';
      if (log.status2Ok == true) return 'Да';
      if (log.status2Ok == false) return 'Нет';
      return '';
    }

    String col7(HaccpLog? log) {
      if (log == null) return '';
      return log.statusOk == true ? 'допущен' : (log.statusOk == false ? 'отстранен' : '');
    }

    final dateFmt = DateFormat('dd.MM.yyyy');

    final rowCount = logs.isEmpty ? 25 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      final full = log != null ? (employeeIdToName[log.createdByEmployeeId] ?? '') : '';
      final (name, position) = _parseEmp(full);
      headerRows.add(
        pw.TableRow(
          children: [
            _tableCell('${i + 1}'),
            _tableCell(log != null ? dateFmt.format(log.createdAt) : ''),
            _tableCell(name),
            _tableCell(position),
            _tableCell(col5(log)),
            _tableCell(col6(log)),
            _tableCell(col7(log)),
            _tableCell(full),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(establishmentName, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        pw.Table(border: tableBorder, columnWidths: colWidths, children: headerRows),
      ],
    );
  }

  static pw.Widget _tableCell(String text) => pw.Padding(
        padding: pw.EdgeInsets.all(3),
        child: pw.Center(
          child: pw.Text(text, style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
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

    final isHealthHygiene = logType == HaccpLogType.healthHygiene;
    final sanpin = isHealthHygiene ? _sanpinHealthHygiene : sanpinRef;
    final title = isHealthHygiene ? _titleHealthHygiene : journalTitle.toUpperCase();

    if (includeCover) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(40),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(sanpin, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 32),
              pw.Center(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(establishmentName, style: pw.TextStyle(fontSize: 14)),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(
                  'Период: ${dateFmt.format(dateFrom)} — ${dateFmt.format(dateTo)}',
                  style: pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isHealthHygiene) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(24, 50, 24, 40),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(sanpin, style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 24),
              _buildHealthHygienePage(
                establishmentName: establishmentName,
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
              ),
            ],
          ),
        ),
      );
    } else {
      final colKeys = logs.isNotEmpty
          ? _collectColumnKeys(logs)
          : _defaultColumnKeysForType(logType);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(24, 50, 24, 40),
          header: (ctx) => pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(sanpinRef, style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  journalTitle.toUpperCase(),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(establishmentName, style: pw.TextStyle(fontSize: 9)),
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
                border: pw.TableBorder.all(color: PdfColors.black),
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
    }

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
