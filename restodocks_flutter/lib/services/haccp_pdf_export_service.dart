import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../haccp/haccp_country_profile.dart';
import '../legal/legal_compliance_provider.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import 'localization_service.dart';

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

  static pw.Widget _cell(String text,
          {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Align(
          alignment: align == pw.TextAlign.center
              ? pw.Alignment.center
              : pw.Alignment.centerLeft,
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

  static pw.Widget _euPdfComplianceFooter(String? text) {
    if (text == null || text.isEmpty) return pw.SizedBox.shrink();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Center(
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 6.2, color: PdfColors.grey700),
        ),
      ),
    );
  }

  /// Гигиенический журнал: макет по образцу — графы как в рекомендуемой форме.
  static pw.Widget _buildHealthHygienePage({
    required LocalizationService loc,
    required String pdfLanguageCode,
    required String Function(String key, {Map<String, String>? args}) tr,
    required String establishmentName,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
  }) {
    (String name, String position) _parseEmp(String s) {
      final idx = s.lastIndexOf(', ');
      if (idx > 0)
        return (s.substring(0, idx).trim(), s.substring(idx + 2).trim());
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
            child: pw.Text(text,
                style:
                    pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center),
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
          _headerCell(tr('haccp_tbl_pp_no')),
          _headerCell(tr('haccp_tbl_date')),
          _headerCell(tr('haccp_tbl_employee_fio_long')),
          _headerCell(tr('haccp_tbl_position')),
          _headerCell(tr('haccp_tbl_sign_family_infect')),
          _headerCell(tr('haccp_tbl_sign_skin_resp')),
          _headerCell(tr('haccp_tbl_exam_outcome')),
          _headerCell(tr('haccp_tbl_med_worker_sign')),
        ],
      ),
    ];

    String col5(HaccpLog? log) {
      if (log == null) return '';
      if (log.statusOk == true) return tr('haccp_bool_yes');
      return '';
    }

    String col6(HaccpLog? log) {
      if (log == null) return '';
      if (log.status2Ok == true) return tr('haccp_bool_yes');
      if (log.status2Ok == false) return tr('haccp_bool_no');
      return '';
    }

    String col7(HaccpLog? log) {
      if (log == null) return '';
      return log.statusOk == true
          ? tr('haccp_status_admitted')
          : (log.statusOk == false ? tr('haccp_status_suspended') : '');
    }

    final dateFmt = DateFormat('dd.MM.yyyy');

    final rowCount = logs.isEmpty ? 25 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      String name = '';
      String position = '';
      String creatorFull = '';
      if (log != null) {
        final parsed = HaccpLog.parseHealthHygieneDescription(log.description);
        final subjectId = parsed.subjectEmployeeId ?? log.createdByEmployeeId;
        final full = employeeIdToName[subjectId] ?? '';
        final parsedEmp = _parseEmp(full);
        final rawName = parsed.employeeNameSnapshot ?? parsedEmp.$1;
        name = loc.displayPersonNameForLanguage(rawName, pdfLanguageCode);
        final rawPos = (parsed.positionOverride != null &&
                parsed.positionOverride!.trim().isNotEmpty)
            ? parsed.positionOverride!.trim()
            : parsedEmp.$2.trim();
        position = loc.formatStoredHealthPositionForLanguage(
            rawPos.isEmpty ? null : rawPos, pdfLanguageCode);
        final cf = employeeIdToName[log.createdByEmployeeId] ?? '';
        creatorFull = loc.displayPersonNameForLanguage(cf, pdfLanguageCode);
      }
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
            _tableCell(creatorFull),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Table(
            border: tableBorder, columnWidths: colWidths, children: headerRows),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text(
            tr('haccp_pdf_health_form_caption'),
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableCell(String text) => pw.Padding(
        padding: pw.EdgeInsets.all(3),
        child: pw.Center(
          child: pw.Text(text,
              style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
        ),
      );

  static pw.TableBorder get _tableBorder {
    const b = pw.BorderSide(color: PdfColors.black, width: 0.5);
    return pw.TableBorder(
        left: b,
        top: b,
        right: b,
        bottom: b,
        horizontalInside: b,
        verticalInside: b);
  }

  static pw.Widget _headerCellSmall(String text) => pw.Padding(
        padding: pw.EdgeInsets.all(2),
        child: pw.Center(
          child: pw.Text(text,
              style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center),
        ),
      );

  static String _th(
    String Function(String key, {Map<String, String>? args}) tr,
    String key,
    String fallback,
  ) {
    final v = tr(key);
    return v == key ? fallback : v;
  }

  /// Журнал температуры в холодильном оборудовании: помещение, оборудование, дни 1–30 (образец).
  static pw.Widget _buildFridgeTemperaturePage({
    required String Function(String key, {Map<String, String>? args}) tr,
    required String footerSanpin,
    required String establishmentName,
    required List<HaccpLog> logs,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) {
    const dayCount = 30;
    final byEquipment = <String, Map<int, double>>{};
    for (final log in logs) {
      if (log.equipment == null || log.equipment!.isEmpty) continue;
      final day = log.createdAt.day;
      byEquipment.putIfAbsent(log.equipment!, () => {})[day] = log.value1 ?? 0;
    }
    final equipmentList = byEquipment.keys.toList()..sort();
    if (equipmentList.isEmpty) equipmentList.add('—');

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.2),
      1: const pw.FlexColumnWidth(1.5),
      ...List.generate(dayCount, (i) => i + 2)
          .asMap()
          .map((i, _) => MapEntry(i + 2, const pw.FlexColumnWidth(0.35))),
    };

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _headerCellSmall(tr('haccp_tbl_room_name_prod')),
          _headerCellSmall(tr('haccp_tbl_fridge_equipment_name')),
          ...List.generate(dayCount, (d) => _headerCellSmall('${d + 1}')),
        ],
      ),
      ...equipmentList.map((equip) {
        final dayValues = byEquipment[equip] ?? {};
        return pw.TableRow(
          children: [
            _tableCell(equipmentList.isNotEmpty && equip == equipmentList.first
                ? establishmentName
                : ''),
            _tableCell(equip),
            ...List.generate(dayCount, (d) {
              final v = dayValues[d + 1];
              return _tableCell(v != null ? v.toStringAsFixed(0) : '');
            }),
          ],
        );
      }),
    ];
    while (rows.length < 8) {
      rows.add(pw.TableRow(
        children: [
          _tableCell(''),
          _tableCell(''),
          ...List.generate(dayCount, (_) => _tableCell('')),
        ],
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Table(border: _tableBorder, columnWidths: colWidths, children: rows),
        pw.SizedBox(height: 10),
        pw.Center(
            child: pw.Text(footerSanpin,
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
      ],
    );
  }

  /// Журнал температурного режима: построчно по образцу docx (Дата, Время, Помещение/камера, Показатель сухой °С, Показатель влажности %, Ответственное лицо).
  static pw.Widget _buildTemperatureRowBasedPage({
    required String establishmentName,
    required String Function(String key, {Map<String, String>? args}) tr,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
    required bool includeHumidity,
  }) {
    final headerCells = <pw.Widget>[
      _headerCellSmall(_th(tr, 'haccp_tbl_pp_no', 'No.')),
      _headerCellSmall(_th(tr, 'haccp_tbl_date', 'Date')),
      _headerCellSmall(_th(tr, 'haccp_tbl_time', 'Time')),
      _headerCellSmall(_th(tr, 'haccp_tbl_room', 'Room/camera')),
      _headerCellSmall(_th(tr, 'haccp_tbl_temp_celsius', 'Dry indicator, C')),
    ];
    if (includeHumidity) {
      headerCells.add(_headerCellSmall(
          _th(tr, 'haccp_tbl_rel_humidity_pct', 'Humidity, %')));
    }
    headerCells.add(_headerCellSmall(
        _th(tr, 'haccp_tbl_responsible', 'Responsible person')));
    headerCells
        .add(_headerCellSmall(_th(tr, 'haccp_tbl_signature', 'Signature')));

    final colCount = headerCells.length;
    final colWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < colCount; i++) i: const pw.FlexColumnWidth(1.2),
    };

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: headerCells,
      ),
    ];
    final dateFmt = DateFormat('dd.MM.yyyy');
    final timeFmt = DateFormat('HH:mm');
    for (var i = 0; i < logs.length; i++) {
      final log = logs[i];
      final cells = <pw.Widget>[
        _tableCell('${i + 1}'),
        _tableCell(dateFmt.format(log.createdAt)),
        _tableCell(timeFmt.format(log.createdAt)),
        _tableCell(log.equipment ?? establishmentName),
        _tableCell(log.value1 != null ? log.value1!.toStringAsFixed(1) : ''),
      ];
      if (includeHumidity) {
        cells.add(_tableCell(
            log.value2 != null ? log.value2!.toStringAsFixed(0) : ''));
      }
      cells.add(_tableCell(employeeIdToName[log.createdByEmployeeId] ?? ''));
      cells.add(_tableCell(''));
      rows.add(pw.TableRow(children: cells));
    }
    const emptyRows = 15;
    for (var i = logs.length; i < emptyRows; i++) {
      rows.add(pw.TableRow(
        children: List.generate(
            colCount, (j) => _tableCell(j == 0 ? '${i + 1}' : '')),
      ));
    }

    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: rows);
  }

  /// Приложение № 3: 5 обязательных колонок. Группировка по наименованию помещения. Шрифт Roboto — кириллица.
  static pw.Widget _buildWarehouseTempHumidityPage({
    required String establishmentName,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateFmt,
    required String Function(String key, {Map<String, String>? args}) tr,
  }) {
    const colWidths = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(0.4),
      1: pw.FlexColumnWidth(1.2),
      2: pw.FlexColumnWidth(0.8),
      3: pw.FlexColumnWidth(0.9),
      4: pw.FlexColumnWidth(1.2),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall(_th(tr, 'haccp_tbl_pp_no', 'No.')),
        _headerCellSmall(_th(tr, 'haccp_tbl_date', 'Date')),
        _headerCellSmall(_th(tr, 'haccp_tbl_temp_c_label', 'Temperature, C')),
        _headerCellSmall(
            _th(tr, 'haccp_tbl_rel_humidity_pct', 'Relative humidity, %')),
        _headerCellSmall(
            _th(tr, 'haccp_tbl_responsible_sign', 'Responsible signature')),
      ],
    );

    final premisesList = logs
        .map((e) => e.equipment)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();
    premisesList.sort();
    if (premisesList.isEmpty) premisesList.add('—');

    final children = <pw.Widget>[];
    for (final premises in premisesList) {
      final premLogs = premises == '—'
          ? logs
              .where((l) => l.equipment == null || l.equipment!.trim().isEmpty)
              .toList()
          : logs.where((l) => l.equipment == premises).toList();
      premLogs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final rows = <pw.TableRow>[headerRow];
      for (var i = 0; i < premLogs.length; i++) {
        final log = premLogs[i];
        final sign = employeeIdToName[log.createdByEmployeeId] ?? '';
        rows.add(
          pw.TableRow(
            children: [
              _tableCell('${i + 1}'),
              _tableCell(dateFmt.format(log.createdAt)),
              _tableCell(
                  log.value1 != null ? log.value1!.toStringAsFixed(0) : ''),
              _tableCell(log.value2 != null
                  ? '${log.value2!.toStringAsFixed(0)}%'
                  : ''),
              _tableCell(sign),
            ],
          ),
        );
      }
      children.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                '${_th(tr, 'haccp_warehouse_premises', 'Warehouse premises')}: $premises',
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Table(
                border: _tableBorder, columnWidths: colWidths, children: rows),
            pw.SizedBox(height: 16),
          ],
        ),
      );
    }
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: children);
  }

  /// Приложение 4: Журнал бракеража готовой пищевой продукции — макет как в образце.
  static pw.Widget _buildBrakerageFinishedProductPage({
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
    required String Function(String key, {Map<String, String>? args}) tr,
  }) {
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.2),
      1: const pw.FlexColumnWidth(0.7),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FlexColumnWidth(1.2),
      4: const pw.FlexColumnWidth(0.9),
      5: const pw.FlexColumnWidth(0.9),
      6: const pw.FlexColumnWidth(0.9),
      7: const pw.FlexColumnWidth(0.8),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall(_th(tr, 'haccp_tbl_dish_made_at', 'Dish made at')),
        _headerCellSmall(
            _th(tr, 'haccp_tbl_brakerage_removed_at', 'Brakerage removed at')),
        _headerCellSmall(_th(tr, 'haccp_tbl_dish_name_ready', 'Dish name')),
        _headerCellSmall(
            _th(tr, 'haccp_tbl_organo_result', 'Organoleptic result')),
        _headerCellSmall(_th(tr, 'haccp_tbl_sale_allowed', 'Sale allowed')),
        _headerCellSmall(_th(tr, 'haccp_tbl_brakerage_commission_sigs',
            'Commission signatures')),
        _headerCellSmall(
            _th(tr, 'haccp_tbl_portion_weighing', 'Portion weighing')),
        _headerCellSmall(_th(tr, 'haccp_tbl_note_short', 'Note')),
      ],
    );
    final dataRows = <pw.TableRow>[headerRow];
    final rowCount = logs.isEmpty ? 20 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      dataRows.add(
        pw.TableRow(
          children: [
            _tableCell(log != null ? dateTimeFmt.format(log.createdAt) : ''),
            _tableCell(log?.timeBrakerage ?? ''),
            _tableCell(log?.productName ?? ''),
            _tableCell(log?.result ?? ''),
            _tableCell(log?.approvalToSell ?? ''),
            _tableCell(log?.commissionSignatures ?? ''),
            _tableCell(log?.weighingResult ?? ''),
            _tableCell(log?.note ?? ''),
          ],
        ),
      );
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  /// Приложение 5: Журнал бракеража скоропортящейся пищевой продукции — макет как в образце.
  static pw.Widget _buildBrakerageIncomingRawPage({
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
    required String Function(String key, {Map<String, String>? args}) tr,
  }) {
    final dateFmt = DateFormat('dd.MM.yyyy');
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(0.6),
      3: const pw.FlexColumnWidth(1),
      4: const pw.FlexColumnWidth(0.5),
      5: const pw.FlexColumnWidth(0.8),
      6: const pw.FlexColumnWidth(1),
      7: const pw.FlexColumnWidth(0.8),
      8: const pw.FlexColumnWidth(0.8),
      9: const pw.FlexColumnWidth(0.6),
      10: const pw.FlexColumnWidth(0.6),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall(_th(tr, 'haccp_tbl_received_at', 'Received at')),
        _headerCellSmall(_th(tr, 'haccp_tbl_name', 'Name')),
        _headerCellSmall(_th(tr, 'haccp_tbl_packaging', 'Packaging')),
        _headerCellSmall(_th(tr, 'haccp_tbl_manufacturer', 'Manufacturer')),
        _headerCellSmall(_th(tr, 'haccp_tbl_qty_short', 'Qty')),
        _headerCellSmall(_th(tr, 'haccp_tbl_doc_no', 'Doc no.')),
        _headerCellSmall(_th(tr, 'haccp_tbl_organo_short', 'Organo')),
        _headerCellSmall(_th(tr, 'haccp_tbl_storage_shelf', 'Storage/shelf')),
        _headerCellSmall(_th(tr, 'haccp_tbl_sale_date', 'Sale date')),
        _headerCellSmall(_th(tr, 'haccp_tbl_signature', 'Signature')),
        _headerCellSmall(_th(tr, 'haccp_tbl_note_short', 'Note')),
      ],
    );
    final dataRows = <pw.TableRow>[headerRow];
    final rowCount = logs.isEmpty ? 20 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      final dateSoldStr =
          log?.dateSold != null ? dateFmt.format(log!.dateSold!) : '';
      final empName =
          log != null ? (employeeIdToName[log.createdByEmployeeId] ?? '') : '';
      dataRows.add(
        pw.TableRow(
          children: [
            _tableCell(log != null ? dateTimeFmt.format(log.createdAt) : ''),
            _tableCell(log?.productName ?? ''),
            _tableCell(log?.packaging ?? ''),
            _tableCell(log?.manufacturerSupplier ?? ''),
            _tableCell(log?.quantityKg != null
                ? log!.quantityKg!.toStringAsFixed(2)
                : ''),
            _tableCell(log?.documentNumber ?? ''),
            _tableCell(log?.result ?? ''),
            _tableCell(log?.storageConditions ?? ''),
            _tableCell(dateSoldStr),
            _tableCell(empName),
            _tableCell(log?.note ?? ''),
          ],
        ),
      );
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  /// Приложение 8: Журнал учета использования фритюрных жиров — макет как в образце.
  static pw.Widget _buildFryingOilPage({
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
    required String Function(String key, {Map<String, String>? args}) tr,
  }) {
    final dateFmt = DateFormat('dd.MM.yyyy');
    final timeFmt = DateFormat('HH:mm');
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.7),
      1: const pw.FlexColumnWidth(0.5),
      2: const pw.FlexColumnWidth(0.8),
      3: const pw.FlexColumnWidth(0.9),
      4: const pw.FlexColumnWidth(0.9),
      5: const pw.FlexColumnWidth(0.8),
      6: const pw.FlexColumnWidth(0.6),
      7: const pw.FlexColumnWidth(0.9),
      8: const pw.FlexColumnWidth(0.5),
      9: const pw.FlexColumnWidth(0.5),
      10: const pw.FlexColumnWidth(0.8),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall(_th(tr, 'haccp_tbl_date', 'Date')),
        _headerCellSmall(_th(tr, 'haccp_tbl_time_start', 'Start time')),
        _headerCellSmall(_th(tr, 'haccp_tbl_fat_type', 'Fat type')),
        _headerCellSmall(_th(tr, 'haccp_tbl_score_start', 'Score start')),
        _headerCellSmall(_th(tr, 'haccp_tbl_equipment', 'Equipment')),
        _headerCellSmall(_th(tr, 'haccp_tbl_product_type', 'Product type')),
        _headerCellSmall(_th(tr, 'haccp_tbl_time_end', 'End time')),
        _headerCellSmall(_th(tr, 'haccp_tbl_score_end', 'Score end')),
        _headerCellSmall(_th(tr, 'haccp_tbl_carry_kg', 'Carry kg')),
        _headerCellSmall(_th(tr, 'haccp_tbl_utilized_kg', 'Utilized kg')),
        _headerCellSmall(_th(tr, 'haccp_tbl_controller', 'Controller')),
      ],
    );
    final dataRows = <pw.TableRow>[headerRow];
    final rowCount = logs.isEmpty ? 15 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      final empName = log != null
          ? (log.commissionSignatures ??
              employeeIdToName[log.createdByEmployeeId] ??
              '')
          : '';
      dataRows.add(
        pw.TableRow(
          children: [
            _tableCell(log != null ? dateFmt.format(log.createdAt) : ''),
            _tableCell(log != null ? timeFmt.format(log.createdAt) : ''),
            _tableCell(log?.oilName ?? ''),
            _tableCell(log?.organolepticStart ?? ''),
            _tableCell(log?.fryingEquipmentType ?? ''),
            _tableCell(log?.fryingProductType ?? ''),
            _tableCell(log?.fryingEndTime ?? ''),
            _tableCell(log?.organolepticEnd ?? ''),
            _tableCell(log?.carryOverKg != null
                ? log!.carryOverKg!.toStringAsFixed(2)
                : ''),
            _tableCell(log?.utilizedKg != null
                ? log!.utilizedKg!.toStringAsFixed(2)
                : ''),
            _tableCell(empName),
          ],
        ),
      );
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  /// Журнал учёта личных медицинских книжек: 7 колонок по бланку.
  static pw.Widget _buildMedBookPage({
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateFmt,
    required String Function(String key, {Map<String, String>? args}) tr,
  }) {
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.4),
      1: const pw.FlexColumnWidth(1.2),
      2: const pw.FlexColumnWidth(0.9),
      3: const pw.FlexColumnWidth(0.8),
      4: const pw.FlexColumnWidth(0.9),
      5: const pw.FlexColumnWidth(1),
      6: const pw.FlexColumnWidth(1),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall(_th(tr, 'haccp_tbl_pp_no', 'No.')),
        _headerCellSmall(_th(tr, 'haccp_tbl_fio_full', 'Full name')),
        _headerCellSmall(_th(tr, 'haccp_tbl_position', 'Position')),
        _headerCellSmall(_th(tr, 'haccp_tbl_med_book_no', 'Med book no.')),
        _headerCellSmall(_th(tr, 'haccp_tbl_med_book_valid', 'Valid until')),
        _headerCellSmall(_th(tr, 'haccp_tbl_med_book_receipt', 'Receipt')),
        _headerCellSmall(_th(tr, 'haccp_tbl_med_book_return', 'Return')),
      ],
    );
    final dataRows = <pw.TableRow>[headerRow];
    final rowCount = logs.isEmpty ? 20 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      final sign =
          log != null ? (employeeIdToName[log.createdByEmployeeId] ?? '') : '';
      final issued = log?.medBookIssuedAt != null
          ? dateFmt.format(log!.medBookIssuedAt!)
          : '';
      final returned = log?.medBookReturnedAt != null
          ? dateFmt.format(log!.medBookReturnedAt!)
          : '';
      dataRows.add(
        pw.TableRow(
          children: [
            _tableCell('${i + 1}'),
            _tableCell(log?.medBookEmployeeName ?? ''),
            _tableCell(log?.medBookPosition ?? ''),
            _tableCell(log?.medBookNumber ?? ''),
            _tableCell(log?.medBookValidUntil != null
                ? dateFmt.format(log!.medBookValidUntil!)
                : ''),
            _tableCell(issued.isEmpty ? '' : '$issued\n$sign'),
            _tableCell(returned.isEmpty ? '' : '$returned\n$sign'),
          ],
        ),
      );
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  static pw.Widget _buildMedExaminationsPdfPage(
      List<HaccpLog> logs,
      Map<String, String> employeeIdToName,
      DateFormat dateFmt,
      String Function(String key, {Map<String, String>? args}) tr) {
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.3),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(0.7),
      3: const pw.FlexColumnWidth(0.6),
      4: const pw.FlexColumnWidth(0.8),
      5: const pw.FlexColumnWidth(0.7),
      6: const pw.FlexColumnWidth(0.7)
    };
    final headerRow = pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _th(tr, 'haccp_tbl_serial_short', 'No.'),
          _th(tr, 'haccp_tbl_med_exam_fio', 'Full name'),
          _th(tr, 'haccp_tbl_position', 'Position'),
          _th(tr, 'haccp_tbl_exam_date', 'Exam date'),
          _th(tr, 'haccp_tbl_conclusion', 'Conclusion'),
          _th(tr, 'haccp_tbl_decision', 'Decision'),
          _th(tr, 'haccp_tbl_signature', 'Signature')
        ].map((h) => _headerCellSmall(h)).toList());
    final dataRows = <pw.TableRow>[headerRow];
    for (var i = 0; i < (logs.isEmpty ? 20 : logs.length); i++) {
      final log = i < logs.length ? logs[i] : null;
      dataRows.add(pw.TableRow(
          children: [
        '${i + 1}',
        log?.medExamEmployeeName ?? '',
        log?.medExamPosition ?? '',
        log?.medExamDate != null ? dateFmt.format(log!.medExamDate!) : '',
        log?.medExamConclusion ?? '',
        log?.medExamEmployerDecision ?? '',
        log != null ? (employeeIdToName[log.createdByEmployeeId] ?? '') : ''
      ].map((c) => _tableCell(c)).toList()));
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  static pw.Widget _buildDisinfectantPdfPage(
      List<HaccpLog> logs,
      Map<String, String> employeeIdToName,
      DateFormat dateFmt,
      String Function(String key, {Map<String, String>? args}) tr) {
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.6),
      1: const pw.FlexColumnWidth(1.2),
      2: const pw.FlexColumnWidth(0.5),
      3: const pw.FlexColumnWidth(0.6),
      4: const pw.FlexColumnWidth(0.8)
    };
    final headerRow = pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _th(tr, 'haccp_tbl_date', 'Date'),
          _th(tr, 'haccp_tbl_object_agent', 'Object/agent'),
          _th(tr, 'haccp_tbl_qty_short', 'Qty'),
          _th(tr, 'haccp_tbl_receipt', 'Receipt'),
          _th(tr, 'haccp_tbl_responsible', 'Responsible')
        ].map((h) => _headerCellSmall(h)).toList());
    final dataRows = <pw.TableRow>[headerRow];
    for (var i = 0; i < (logs.isEmpty ? 20 : logs.length); i++) {
      final log = i < logs.length ? logs[i] : null;
      dataRows.add(pw.TableRow(
          children: [
        log != null ? dateFmt.format(log.createdAt) : '',
        log?.disinfObjectName ?? log?.disinfAgentName ?? '',
        log?.disinfObjectCount?.toString() ??
            log?.disinfQuantity?.toString() ??
            '',
        log?.disinfReceiptDate != null
            ? dateFmt.format(log!.disinfReceiptDate!)
            : '',
        log != null
            ? (log.disinfResponsibleName ??
                employeeIdToName[log.createdByEmployeeId] ??
                '')
            : ''
      ].map((c) => _tableCell(c)).toList()));
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  static pw.Widget _buildEquipmentWashingPdfPage(
      List<HaccpLog> logs,
      Map<String, String> employeeIdToName,
      DateFormat dateFmt,
      String Function(String key, {Map<String, String>? args}) tr) {
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.6),
      1: const pw.FlexColumnWidth(0.4),
      2: const pw.FlexColumnWidth(1),
      3: const pw.FlexColumnWidth(0.8),
      4: const pw.FlexColumnWidth(0.8),
      5: const pw.FlexColumnWidth(0.7)
    };
    final headerRow = pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _th(tr, 'haccp_tbl_date', 'Date'),
          _th(tr, 'haccp_tbl_time', 'Time'),
          _th(tr, 'haccp_tbl_equipment', 'Equipment'),
          _th(tr, 'haccp_tbl_wash_solution', 'Wash solution'),
          _th(tr, 'haccp_tbl_disinfect_solution', 'Disinfect solution'),
          _th(tr, 'haccp_tbl_controller', 'Controller')
        ].map((h) => _headerCellSmall(h)).toList());
    final dataRows = <pw.TableRow>[headerRow];
    for (var i = 0; i < (logs.isEmpty ? 20 : logs.length); i++) {
      final log = i < logs.length ? logs[i] : null;
      dataRows.add(pw.TableRow(
          children: [
        log != null ? dateFmt.format(log.createdAt) : '',
        log?.washTime ?? '',
        log?.washEquipmentName ?? '',
        log?.washSolutionName ?? '',
        log?.washDisinfectantName ?? '',
        log != null
            ? (log.washControllerSignature ??
                employeeIdToName[log.createdByEmployeeId] ??
                '')
            : ''
      ].map((c) => _tableCell(c)).toList()));
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  static pw.Widget _buildGeneralCleaningPdfPage(
      List<HaccpLog> logs,
      Map<String, String> employeeIdToName,
      DateFormat dateFmt,
      String Function(String key, {Map<String, String>? args}) tr) {
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.3),
      1: const pw.FlexColumnWidth(1.2),
      2: const pw.FlexColumnWidth(0.6),
      3: const pw.FlexColumnWidth(0.8)
    };
    final headerRow = pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _th(tr, 'haccp_tbl_serial_short', 'No.'),
          _th(tr, 'haccp_tbl_room', 'Room'),
          _th(tr, 'haccp_tbl_date', 'Date'),
          _th(tr, 'haccp_tbl_responsible', 'Responsible')
        ].map((h) => _headerCellSmall(h)).toList());
    final dataRows = <pw.TableRow>[headerRow];
    for (var i = 0; i < (logs.isEmpty ? 20 : logs.length); i++) {
      final log = i < logs.length ? logs[i] : null;
      dataRows.add(pw.TableRow(
          children: [
        '${i + 1}',
        log?.genCleanPremises ?? '',
        log?.genCleanDate != null ? dateFmt.format(log!.genCleanDate!) : '',
        log != null
            ? (log.genCleanResponsible ??
                employeeIdToName[log.createdByEmployeeId] ??
                '')
            : ''
      ].map((c) => _tableCell(c)).toList()));
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  static pw.Widget _buildSieveFilterMagnetPdfPage(
      List<HaccpLog> logs,
      Map<String, String> employeeIdToName,
      DateFormat dateFmt,
      String Function(String key, {Map<String, String>? args}) tr) {
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.4),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(0.6),
      3: const pw.FlexColumnWidth(0.6),
      4: const pw.FlexColumnWidth(0.7),
      5: const pw.FlexColumnWidth(0.6)
    };
    final headerRow = pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _th(tr, 'haccp_tbl_sieve_magnet_no', 'Sieve/magnet No.'),
          _th(tr, 'haccp_tbl_name', 'Name'),
          _th(tr, 'haccp_tbl_condition', 'Condition'),
          _th(tr, 'haccp_tbl_cleaning_date', 'Cleaning date'),
          _th(tr, 'haccp_tbl_med_exam_fio', 'Full name'),
          _th(tr, 'haccp_tbl_comments', 'Comments')
        ].map((h) => _headerCellSmall(h)).toList());
    final dataRows = <pw.TableRow>[headerRow];
    for (var i = 0; i < (logs.isEmpty ? 20 : logs.length); i++) {
      final log = i < logs.length ? logs[i] : null;
      dataRows.add(pw.TableRow(
          children: [
        log?.sieveNo ?? '',
        log?.sieveNameLocation ?? '',
        log?.sieveCondition ?? '',
        log?.sieveCleaningDate != null
            ? dateFmt.format(log!.sieveCleaningDate!)
            : '',
        log != null
            ? (log.sieveSignature ??
                employeeIdToName[log.createdByEmployeeId] ??
                '')
            : '',
        log?.sieveComments ?? ''
      ].map((c) => _tableCell(c)).toList()));
    }
    return pw.Table(
        border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  /// Параметры экспорта.
  static Future<Uint8List> buildJournalPdf({
    required LocalizationService loc,
    required String pdfLanguageCode,
    required String establishmentName,
    required HaccpLogType logType,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateTime dateFrom,
    required DateTime dateTo,
    String? establishmentCountryCode,
    bool includeCover = true,
    bool includeStitchingSheet = true,
  }) async {
    final theme = await _getTheme();
    final dateFmt = DateFormat('dd.MM.yyyy');
    final dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');
    final isHealthHygiene = logType == HaccpLogType.healthHygiene;

    String tr(String key, {Map<String, String>? args}) =>
        loc.tForLanguage(pdfLanguageCode, key, args: args);

    final sanpinLine = HaccpCountryProfiles.journalLegalLine(
      establishmentCountryCode,
      logType,
    );
    final title = tr(logType.displayNameKey);
    final footerText = HaccpCountryProfiles.journalFooterLine(
      establishmentCountryCode,
      logType,
    );
    final selectedProfile = HaccpCountryProfiles.byCountryCode(
      establishmentCountryCode,
    );
    final templateProfileLine = HaccpCountryProfiles.templateCountryLabel(
      selectedProfile.countryCode,
      pdfLanguageCode,
    );
    final templateFrameworkLine = HaccpCountryProfiles.legalFrameworkLabel(
      selectedProfile.countryCode,
      pdfLanguageCode,
    );
    final recommendedSampleText =
        HaccpCountryProfiles.recommendedSampleLabel(establishmentCountryCode);
    final euPdfComplianceFooter =
        LegalComplianceProvider.journalPdfComplianceFooterByCountry(
      pdfLanguageCode,
      selectedProfile.countryCode,
    );

    final doc = pw.Document(
      theme: theme,
      title: title,
      subject: '${tr('haccp_pdf_document_subject')} [$templateProfileLine]',
      producer: tr('haccp_pdf_document_producer'),
    );

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
                child: pw.Text(sanpinLine, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 32),
              pw.Center(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(tr('haccp_pdf_org_name_label'),
                        style: pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text(establishmentName,
                        style: pw.TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(
                  templateProfileLine,
                  style: pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  templateFrameworkLine,
                  style: pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  tr('haccp_pdf_cover_period', args: {
                    'from': dateFmt.format(dateFrom),
                    'to': dateFmt.format(dateTo),
                  }),
                  style: pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.Spacer(),
              _euPdfComplianceFooter(euPdfComplianceFooter),
            ],
          ),
        ),
      );
    }

    if (isHealthHygiene) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(24, 40, 24, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(sanpinLine, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(recommendedSampleText,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(templateProfileLine,
                    style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(templateFrameworkLine,
                    style: pw.TextStyle(fontSize: 7)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildHealthHygienePage(
                loc: loc,
                pdfLanguageCode: pdfLanguageCode,
                tr: tr,
                establishmentName: establishmentName,
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text(footerText,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold))),
              _euPdfComplianceFooter(euPdfComplianceFooter),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.fridgeTemperature) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          margin: pw.EdgeInsets.fromLTRB(20, 40, 20, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(footerText, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(recommendedSampleText,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(templateProfileLine,
                    style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(templateFrameworkLine,
                    style: pw.TextStyle(fontSize: 7)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildFridgeTemperaturePage(
                tr: tr,
                footerSanpin: footerText,
                establishmentName: establishmentName,
                logs: logs,
                dateFrom: dateFrom,
                dateTo: dateTo,
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text(footerText,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold))),
              _euPdfComplianceFooter(euPdfComplianceFooter),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.warehouseTempHumidity) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          margin: pw.EdgeInsets.fromLTRB(20, 40, 20, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(footerText, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(recommendedSampleText,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(templateProfileLine,
                    style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(templateFrameworkLine,
                    style: pw.TextStyle(fontSize: 7)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildWarehouseTempHumidityPage(
                establishmentName: establishmentName,
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateFmt: dateFmt,
                tr: tr,
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text(footerText,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold))),
              _euPdfComplianceFooter(euPdfComplianceFooter),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.finishedProductBrakerage) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(footerText, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(recommendedSampleText,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(templateProfileLine,
                    style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(templateFrameworkLine,
                    style: pw.TextStyle(fontSize: 7)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildBrakerageFinishedProductPage(
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
                tr: tr,
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text(footerText,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold))),
              _euPdfComplianceFooter(euPdfComplianceFooter),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.incomingRawBrakerage) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(footerText, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(recommendedSampleText,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(templateProfileLine,
                    style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(templateFrameworkLine,
                    style: pw.TextStyle(fontSize: 7)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildBrakerageIncomingRawPage(
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
                tr: tr,
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text(footerText,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold))),
              _euPdfComplianceFooter(euPdfComplianceFooter),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.fryingOil) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(footerText, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(tr('haccp_pdf_frying_oil_subtitle'),
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(templateProfileLine,
                    style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(templateFrameworkLine,
                    style: pw.TextStyle(fontSize: 7)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildFryingOilPage(
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
                tr: tr,
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text(footerText,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold))),
              _euPdfComplianceFooter(euPdfComplianceFooter),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.medBookRegistry) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(footerText, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(recommendedSampleText,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildMedBookPage(
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateFmt: dateFmt,
                tr: tr,
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text(footerText,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold))),
              _euPdfComplianceFooter(euPdfComplianceFooter),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.medExaminations) {
      doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(footerText,
                            style: pw.TextStyle(fontSize: 9))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(recommendedSampleText,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(templateProfileLine,
                            style: pw.TextStyle(fontSize: 8))),
                    pw.SizedBox(height: 2),
                    pw.Center(
                        child: pw.Text(templateFrameworkLine,
                            style: pw.TextStyle(fontSize: 7))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 8),
                    _buildMedExaminationsPdfPage(
                        logs, employeeIdToName, dateFmt, tr),
                    pw.SizedBox(height: 10),
                    pw.Center(
                        child: pw.Text(footerText,
                            style: pw.TextStyle(
                                fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    _euPdfComplianceFooter(euPdfComplianceFooter),
                  ])));
    } else if (logType == HaccpLogType.disinfectantAccounting) {
      doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(footerText,
                            style: pw.TextStyle(fontSize: 9))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(recommendedSampleText,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(templateProfileLine,
                            style: pw.TextStyle(fontSize: 8))),
                    pw.SizedBox(height: 2),
                    pw.Center(
                        child: pw.Text(templateFrameworkLine,
                            style: pw.TextStyle(fontSize: 7))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 8),
                    _buildDisinfectantPdfPage(
                        logs, employeeIdToName, dateFmt, tr),
                    pw.SizedBox(height: 10),
                    pw.Center(
                        child: pw.Text(footerText,
                            style: pw.TextStyle(
                                fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    _euPdfComplianceFooter(euPdfComplianceFooter),
                  ])));
    } else if (logType == HaccpLogType.equipmentWashing) {
      doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(footerText,
                            style: pw.TextStyle(fontSize: 9))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(recommendedSampleText,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(templateProfileLine,
                            style: pw.TextStyle(fontSize: 8))),
                    pw.SizedBox(height: 2),
                    pw.Center(
                        child: pw.Text(templateFrameworkLine,
                            style: pw.TextStyle(fontSize: 7))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 8),
                    _buildEquipmentWashingPdfPage(
                        logs, employeeIdToName, dateFmt, tr),
                    pw.SizedBox(height: 10),
                    pw.Center(
                        child: pw.Text(footerText,
                            style: pw.TextStyle(
                                fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    _euPdfComplianceFooter(euPdfComplianceFooter),
                  ])));
    } else if (logType == HaccpLogType.generalCleaningSchedule) {
      doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(footerText,
                            style: pw.TextStyle(fontSize: 9))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(recommendedSampleText,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(templateProfileLine,
                            style: pw.TextStyle(fontSize: 8))),
                    pw.SizedBox(height: 2),
                    pw.Center(
                        child: pw.Text(templateFrameworkLine,
                            style: pw.TextStyle(fontSize: 7))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 8),
                    _buildGeneralCleaningPdfPage(
                        logs, employeeIdToName, dateFmt, tr),
                    pw.SizedBox(height: 10),
                    pw.Center(
                        child: pw.Text(footerText,
                            style: pw.TextStyle(
                                fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    _euPdfComplianceFooter(euPdfComplianceFooter),
                  ])));
    } else if (logType == HaccpLogType.sieveFilterMagnet) {
      doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(footerText,
                            style: pw.TextStyle(fontSize: 9))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(recommendedSampleText,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 4),
                    pw.Center(
                        child: pw.Text(title,
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 8),
                    _buildSieveFilterMagnetPdfPage(
                        logs, employeeIdToName, dateFmt, tr),
                    pw.SizedBox(height: 10),
                    pw.Center(
                        child: pw.Text(footerText,
                            style: pw.TextStyle(
                                fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    _euPdfComplianceFooter(euPdfComplianceFooter),
                  ])));
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
              pw.Center(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(establishmentName,
                    style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(templateProfileLine,
                    style: pw.TextStyle(fontSize: 8)),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(templateFrameworkLine,
                    style: pw.TextStyle(fontSize: 7)),
              ),
            ],
          ),
          footer: (ctx) {
            final eu = euPdfComplianceFooter;
            return pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Center(
                  child: pw.Text(
                    footerText,
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                if (eu != null && eu.isNotEmpty)
                  pw.Padding(
                    padding:
                        const pw.EdgeInsets.only(top: 6, left: 24, right: 24),
                    child: pw.Text(
                      eu,
                      textAlign: pw.TextAlign.center,
                      style:
                          pw.TextStyle(fontSize: 6.2, color: PdfColors.grey700),
                    ),
                  ),
              ],
            );
          },
          build: (ctx) {
            final rows = <pw.TableRow>[
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _cell('№', bold: true),
                  _cell(_th(tr, 'haccp_tbl_date', 'Date'), bold: true),
                  ...colKeys.map((k) => _cell(_humanKey(k, tr), bold: true)),
                  _cell(
                    '${_th(tr, 'haccp_tbl_med_exam_fio', 'Full name')}, ${_th(tr, 'haccp_tbl_position', 'Position')}',
                    bold: true,
                  ),
                ],
              ),
            ];
            const blankRowCount = 25;
            final rowCount = logs.isEmpty ? blankRowCount : logs.length;
            for (var i = 0; i < rowCount; i++) {
              final cells = <pw.Widget>[
                _cell('${i + 1}'),
                _cell(logs.length > i
                    ? dateTimeFmt.format(logs[i].createdAt)
                    : ''),
                ...colKeys.map((k) => _cell(
                    logs.length > i ? (logs[i].toPdfRow()[k] ?? '') : '')),
                _cell(logs.length > i
                    ? (employeeIdToName[logs[i].createdByEmployeeId] ??
                        logs[i].createdByEmployeeId)
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
                tr('haccp_pdf_stitching_body'),
                style: pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 24),
              pw.Text(tr('haccp_pdf_stitching_sign'),
                  style: pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 6),
              pw.Text(
                templateProfileLine,
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                templateFrameworkLine,
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
              _euPdfComplianceFooter(euPdfComplianceFooter),
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
          HaccpLogType.healthHygiene || HaccpLogType.pediculosis => [
              'status',
              'note'
            ],
          HaccpLogType.dishwasherControl => ['status', 'status2', 'note'],
          HaccpLogType.glassCeramicsBreakage => ['description', 'location'],
          HaccpLogType.emergencyIncidents => ['description', 'note'],
          _ => ['status', 'status2', 'description', 'location', 'note'],
        };
      case HaccpLogTable.quality:
        return switch (logType) {
          HaccpLogType.finishedProductBrakerage ||
          HaccpLogType.incomingRawBrakerage =>
            ['product', 'result', 'note'],
          HaccpLogType.fryingOil => ['action', 'oil_name', 'note'],
          HaccpLogType.foodWaste => ['weight', 'reason', 'note'],
          HaccpLogType.disinsectionDeratization => ['agent', 'note'],
          _ => [
              'product',
              'result',
              'weight',
              'reason',
              'action',
              'agent',
              'concentration',
              'note'
            ],
        };
    }
  }

  static String _humanKey(
    String key,
    String Function(String key, {Map<String, String>? args}) tr,
  ) {
    switch (key) {
      case 'value1':
        return _th(tr, 'haccp_tbl_temp_celsius', 'Temperature C');
      case 'value2':
        return _th(tr, 'haccp_tbl_rel_humidity_pct', 'Humidity %');
      case 'equipment':
        return _th(tr, 'haccp_tbl_equipment', 'Equipment');
      case 'status':
        return _th(tr, 'haccp_tbl_exam_outcome', 'Status');
      case 'status2':
        return _th(tr, 'haccp_tbl_organo_short', 'Organoleptic');
      case 'description':
        return _th(tr, 'haccp_tbl_description', 'Description');
      case 'location':
        return _th(tr, 'haccp_tbl_location', 'Location');
      case 'product':
        return _th(tr, 'haccp_product', 'Product');
      case 'result':
        return _th(tr, 'haccp_tbl_result', 'Result');
      case 'weight':
        return _th(tr, 'haccp_tbl_weight', 'Weight');
      case 'reason':
        return _th(tr, 'haccp_tbl_reason', 'Reason');
      case 'action':
        return _th(tr, 'haccp_tbl_action', 'Action');
      case 'oil_name':
        return _th(tr, 'haccp_tbl_fat_type', 'Oil type');
      case 'agent':
        return _th(tr, 'haccp_tbl_object_agent', 'Agent');
      case 'concentration':
        return _th(tr, 'haccp_tbl_concentration', 'Concentration');
      case 'note':
        return _th(tr, 'haccp_note', 'Note');
      default:
        return key;
    }
  }
}
