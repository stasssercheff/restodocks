import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import 'ai_service.dart';
import 'iiko_xlsx_sanitizer.dart';
import 'nutrition_api_service.dart';
import '../utils/dev_log.dart';
import '../utils/product_name_utils.dart';

/// Реализация AiService через Supabase Edge Functions.
/// Требует: задеплоенные функции и секрет OPENAI_API_KEY в Supabase.
class AiServiceSupabase implements AiService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Последняя ошибка парсинга списка продуктов (для диагностики, когда ИИ не распознал данные).
  static String? lastParseProductListError;

  /// Причина пустого результата при парсинге PDF ТТК (empty_text, ai_error, ai_no_cards и т.д.).
  static String? lastParseTechCardPdfReason;

  /// Причина пустого результата при парсинге Excel ТТК (ai_limit_exceeded и т.д.).
  static String? lastParseTechCardExcelReason;

  /// Ошибки парсинга (битые карточки) — показываются на экране просмотра.
  static List<TtkParseError>? lastParseTechCardErrors;

  /// Преобразует сырую ошибку API (JSON, 429 и т.д.) в понятное пользователю сообщение.
  static String _sanitizeAiError(String raw) {
    if (raw.isEmpty) return 'Неизвестная ошибка';
    final lower = raw.toLowerCase();
    if (lower.contains('429') || lower.contains('resource_exhausted') || lower.contains('quota')) {
      return 'Превышен лимит запросов к ИИ. Попробуйте позже или проверьте лимиты в AI Studio.';
    }
    if (lower.contains('gemini') && lower.contains('{')) {
      return 'Сервис ИИ временно недоступен. Используется локальный разбор.';
    }
    if (lower.contains('functionexception') || lower.contains('status: 500')) {
      return 'Ошибка сервера ИИ. Используется локальный разбор.';
    }
    if (raw.length > 200 || raw.contains('"status"') || raw.contains('"message"')) {
      return 'ИИ не смог обработать запрос. Используется локальный разбор.';
    }
    return raw;
  }

  /// Вызов Edge Function с retry при 5xx/сети (proxy/ EarlyDrop).
  Future<Map<String, dynamic>?> invoke(String name, Map<String, dynamic> body) async {
    const maxRetries = 3;
    const delays = [500, 1000];
    Object? lastError;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: delays[attempt - 1]));
      }
      try {
        final res = await _client.functions.invoke(name, body: body);
        if (res.status >= 200 && res.status < 300) {
          final data = res.data;
          if (data is Map<String, dynamic> && !data.containsKey('error')) return data;
          return null;
        }
        if (res.status >= 400 && res.status < 500) return null; // 4xx не retry
        lastError = 'HTTP ${res.status}';
      } catch (e) {
        lastError = e;
      }
    }
    return null;
  }

  @override
  Future<List<ParsedProductItem>> parseProductList({List<String>? rows, String? text, String? source, String? userLocale, String? mode}) async {
    lastParseProductListError = null;
    final body = <String, dynamic>{};
    if (rows != null && rows.isNotEmpty) body['rows'] = rows;
    if (text != null && text.trim().isNotEmpty) body['text'] = text;
    if (source != null && source.isNotEmpty) body['source'] = source;
    if (userLocale != null && userLocale.isNotEmpty) body['userLocale'] = userLocale;
    if (mode != null && mode.isNotEmpty) body['mode'] = mode;
    try {
      final res = await _client.functions.invoke('ai-parse-product-list', body: body);
      final data = res.data;
      if (res.status != 200) {
        lastParseProductListError = _sanitizeAiError('HTTP ${res.status}');
        return [];
      }
      if (data is! Map<String, dynamic>) {
        lastParseProductListError = 'Неверный формат ответа';
        return [];
      }
      if (data.containsKey('error') && data['error'] != null) {
        lastParseProductListError = _sanitizeAiError(data['error'].toString());
      }
      final raw = data['items'];
      if (raw is! List) return [];
      final list = raw.map((e) {
        if (e is! Map) return null;
        final m = Map<String, dynamic>.from(e as Map);
        return ParsedProductItem(
          name: (m['name'] as String?) ?? '',
          price: m['price'] != null ? (m['price'] as num).toDouble() : null,
          unit: m['unit'] as String?,
          currency: m['currency'] as String?,
        );
      }).whereType<ParsedProductItem>().toList();
      if (list.isEmpty && lastParseProductListError == null && data['error'] != null) {
        lastParseProductListError = _sanitizeAiError(data['error'].toString());
      }
      return list;
    } catch (e) {
      lastParseProductListError = _sanitizeAiError(e.toString());
      return [];
    }
  }

  @override
  Future<List<String>> normalizeProductNames(List<String> names) async {
    if (names.isEmpty) return [];
    final data = await invoke('ai-normalize-product-names', {'names': names});
    if (data == null) return names;
    final raw = data['normalized'];
    if (raw is! List) return names;
    return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }

  @override
  Future<List<List<String>>> findDuplicates(List<({String id, String name})> products) async {
    if (products.length < 2) return [];
    final data = await invoke('ai-find-duplicates', {
      'products': products.map((p) => {'id': p.id, 'name': p.name}).toList(),
    });
    if (data == null) return [];
    final raw = data['groups'];
    if (raw is! List) return [];
    return raw
        .map((g) => g is List ? g.map((e) => e.toString()).toList() : <String>[])
        .where((g) => g.length >= 2)
        .toList();
  }

  @override
  Future<GeneratedChecklist?> generateChecklistFromPrompt(String prompt, {Map<String, dynamic>? context}) async {
    final body = <String, dynamic>{'prompt': prompt};
    if (context != null) body['context'] = context;
    final data = await invoke('ai-generate-checklist', body);
    if (data == null) return null;
    final name = data['name'] as String? ?? '';
    final list = data['itemTitles'];
    final items = list is List ? list.map((e) => e.toString()).toList() : <String>[];
    return GeneratedChecklist(name: name, itemTitles: items);
  }

  @override
  Future<ReceiptRecognitionResult?> recognizeReceipt(Uint8List imageBytes) async {
    final base64 = base64Encode(imageBytes);
    final data = await invoke('ai-recognize-receipt', {'imageBase64': base64});
    if (data == null) return null;
    final raw = data['lines'];
    final list = raw is List ? raw : [];
    final lines = <ReceiptLine>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e as Map);
      lines.add(ReceiptLine(
        productName: (m['productName'] as String?) ?? '',
        quantity: (m['quantity'] is num) ? (m['quantity'] as num).toDouble() : 0,
        unit: m['unit'] as String?,
        price: m['price'] != null ? (m['price'] as num).toDouble() : null,
      ));
    }
    return ReceiptRecognitionResult(
      lines: lines,
      rawText: data['rawText'] as String?,
    );
  }

  @override
  Future<TechCardRecognitionResult?> recognizeTechCardFromImage(Uint8List imageBytes) async {
    final base64 = base64Encode(imageBytes);
    final data = await invoke('ai-recognize-tech-card', {'imageBase64': base64});
    return _parseTechCardResult(data);
  }

  @override
  Future<TechCardRecognitionResult?> parseTechCardFromExcel(Uint8List xlsxBytes) async {
    try {
      final list = await parseTechCardsFromExcel(xlsxBytes);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  /// Определение формата по magic bytes: docx/xlsx (ZIP), xls (OLE), csv (текст).
  static String _detectFormat(Uint8List bytes) {
    if (bytes.length < 8) return 'csv';
    if (bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) return 'ole';
    if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        if (archive.findFile('word/document.xml') != null) return 'docx';
      } catch (_) {}
      return 'xlsx';
    }
    return 'csv';
  }

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromExcel(Uint8List xlsxBytes, {String? establishmentId}) async {
    try {
      final fmt = _detectFormat(xlsxBytes);
      var rows = <List<String>>[];
      String source = 'excel';
      List<List<List<String>>>? docxTables;

      if (fmt == 'docx') {
        docxTables = _docxToAllTables(xlsxBytes);
        if (docxTables.isNotEmpty) {
          rows = docxTables.first;
          source = 'docx';
        } else {
          rows = _docxToRows(xlsxBytes);
          if (rows.isNotEmpty) source = 'docx';
        }
      } else if (fmt == 'ole') {
        rows = await _parseXlsViaServer(xlsxBytes);
        if (rows.isEmpty) rows = await _parseDocViaServer(xlsxBytes);
        source = rows.isNotEmpty ? 'xls' : 'doc';
      } else if (fmt == 'xlsx') {
        final allSheets = _xlsxToAllSheetsRows(xlsxBytes);
        if (allSheets.isNotEmpty) {
          final merged = <TechCardRecognitionResult>[];
          final kbzuPattern = RegExp(r'белки|жиры|углеводы|калори|бжу|кбжу|жирн|белк', caseSensitive: false);
          for (final sheetRows in allSheets) {
            var expanded = _expandSingleCellRows(sheetRows);
            if (expanded.length < 2) continue;
            final firstRows = expanded.take(3).expand((r) => r).map((c) => c.toLowerCase()).join(' ');
            if (kbzuPattern.hasMatch(firstRows) && expanded.length <= 6 && !firstRows.contains('брутто') && !firstRows.contains('нетто')) continue;
            var part = await _tryParseByStoredTemplates(expanded);
            if (part.isEmpty) {
              final excelErrors = <TtkParseError>[];
              part = AiServiceSupabase.parseTtkByTemplate(expanded, errors: excelErrors);
              if (part.isEmpty) part = AiServiceSupabase._tryParseKkFromRows(expanded);
            }
            final multiBlock = AiServiceSupabase._tryParseMultiColumnBlocks(expanded);
            if (_shouldPreferMultiBlock(part, multiBlock)) part = multiBlock;
            merged.addAll(part);
          }
          if (merged.isNotEmpty) {
            _saveTemplateFromKeywordParse(allSheets.first, 'xlsx');
            return merged;
          }
        }
        rows = _xlsxToRows(xlsxBytes);
      }
      if (rows.isEmpty) rows = _csvToRows(xlsxBytes);
      if (rows.isEmpty && fmt != 'docx') {
        docxTables = _docxToAllTables(xlsxBytes);
        if (docxTables.isNotEmpty) {
          rows = docxTables.first;
          source = 'docx';
        }
      }
      if (rows.isEmpty) rows = await _parseXlsViaServer(xlsxBytes);
      if (rows.isEmpty) rows = await _parseDocViaServer(xlsxBytes);
      if (rows.isEmpty) return [];
      rows = _expandSingleCellRows(rows);
      rows = _normalizeRowLengths(rows); // xls/SheetJS может вернуть строки разной длины
      if (rows.length < 2) return [];
      // DOCX: если много таблиц — парсим каждую; если одна и не парсится — пробуем все по очереди
      if (docxTables != null && docxTables.isNotEmpty) {
        final merged = <TechCardRecognitionResult>[];
        final kbzuPattern = RegExp(r'белки|жиры|углеводы|калори|бжу|кбжу|жирн|белк', caseSensitive: false);
        for (final tbl in docxTables) {
          var expanded = _expandSingleCellRows(tbl);
          if (expanded.length < 2) continue;
          // Таблица КБЖУ (ГОСТ): Белки г, Жиры г — не парсим как ТТК
          final firstRows = expanded.take(3).expand((r) => r).map((c) => c.toLowerCase()).join(' ');
          if (kbzuPattern.hasMatch(firstRows) && expanded.length <= 6 && !firstRows.contains('брутто') && !firstRows.contains('нетто')) continue;
          var part = await _tryParseByStoredTemplates(expanded);
          if (part.isEmpty) {
            part = AiServiceSupabase.parseTtkByTemplate(expanded);
            if (part.isEmpty) part = AiServiceSupabase._tryParseKkFromRows(expanded);
          }
          final multiBlock = AiServiceSupabase._tryParseMultiColumnBlocks(expanded);
          if (_shouldPreferMultiBlock(part, multiBlock)) part = multiBlock;
          merged.addAll(part);
        }
        if (merged.isNotEmpty) {
          _saveTemplateFromKeywordParse(rows, 'docx');
          return merged;
        }
      }
      // 1. СНАЧАЛА — сохранённые шаблоны (файлы, по которым уже были сохранены шаблоны, должны распознаваться по ним).
      lastParseTechCardErrors = null;
      var list = await _tryParseByStoredTemplates(rows);
      // 2. Только если шаблон не найден — эвристики: parseTtkByTemplate, КК.
      if (list.isEmpty) {
        final excelErrors = <TtkParseError>[];
        list = AiServiceSupabase.parseTtkByTemplate(rows, errors: excelErrors);
        if (excelErrors.isNotEmpty) lastParseTechCardErrors = excelErrors;
        if (list.isEmpty) list = AiServiceSupabase._tryParseKkFromRows(rows);
        final multiBlock = AiServiceSupabase._tryParseMultiColumnBlocks(rows);
        if (_shouldPreferMultiBlock(list, multiBlock)) list = multiBlock;
      }
      // 3. Только если и там пусто — вызываем AI (лимит 3/день)
      if (list.isEmpty) {
        lastParseTechCardExcelReason = null;
        final body = <String, dynamic>{'rows': rows};
        if (establishmentId != null && establishmentId.isNotEmpty) body['establishmentId'] = establishmentId;
        final data = await invoke('ai-recognize-tech-cards-batch', body);
        if (data == null) return [];
        final err = data['error'] as String? ?? data['reason'] as String?;
        if (err == 'limit_3_per_day' || err == 'ai_limit_exceeded') lastParseTechCardExcelReason = err;
        final raw = data['cards'];
        if (raw is! List) return [];
        list = <TechCardRecognitionResult>[];
        for (final e in raw) {
          if (e is! Map) continue;
          final card = _parseTechCardResult(Map<String, dynamic>.from(e as Map));
          if (card != null && (card.dishName != null && card.dishName!.isNotEmpty || card.ingredients.isNotEmpty)) {
            list.add(card);
          }
        }
        // 4. Обучение: сохраняем шаблон для следующих загрузок того же формата
        if (list.isNotEmpty) {
          _saveTemplateAfterAi(rows, list, source);
        }
      }
      if (list.isNotEmpty) lastParseTechCardExcelReason = null;
      return list;
    } catch (_) {
      lastParseTechCardExcelReason = null;
      return [];
    }
  }

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromText(String text, {String? establishmentId}) async {
    lastParseTechCardExcelReason = null;
    lastParseTechCardErrors = null;
    final rows = _textToRows(text);
    if (rows.length < 2) return [];
    var expanded = _expandSingleCellRows(rows);
    if (expanded.length < 2) return [];
    var list = await _tryParseByStoredTemplates(expanded);
    if (list.isEmpty) {
      final excelErrors = <TtkParseError>[];
      list = AiServiceSupabase.parseTtkByTemplate(expanded, errors: excelErrors);
      if (excelErrors.isNotEmpty) lastParseTechCardErrors = excelErrors;
      if (list.isEmpty) list = AiServiceSupabase._tryParseKkFromRows(expanded);
    }
    if (list.isNotEmpty) _saveTemplateFromKeywordParse(expanded, 'text');
    return list;
  }

  /// Текст → строки (split по \n, каждая строка по \t).
  List<List<String>> _textToRows(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final rows = <List<String>>[];
    for (final line in lines) {
      final cells = line.split('\t').map((s) => s.trim()).toList();
      if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
    }
    return rows;
  }

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromPdf(Uint8List pdfBytes, {String? establishmentId}) async {
    lastParseTechCardPdfReason = null;
    try {
      final body = <String, dynamic>{'pdfBase64': base64Encode(pdfBytes)};
      if (establishmentId != null && establishmentId.isNotEmpty) body['establishmentId'] = establishmentId;
      var data = await invoke('ai-parse-tech-cards-pdf', body);
      for (var retry = 0; data == null && retry < 2; retry++) {
        await Future<void>.delayed(Duration(milliseconds: retry == 0 ? 1500 : 3000));
        data = await invoke('ai-parse-tech-cards-pdf', body);
      }
      if (data == null) {
        lastParseTechCardPdfReason = 'invoke_null';
        return [];
      }
      lastParseTechCardPdfReason = data['reason'] as String? ?? (data['error'] as String?);
      final raw = data['cards'];
      if (raw is! List) return [];
      final parseErrorsRaw = data['parseErrors'];
      if (parseErrorsRaw is List && parseErrorsRaw.isNotEmpty) {
        lastParseTechCardErrors = parseErrorsRaw.map((e) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e as Map);
            return TtkParseError(
              dishName: m['dishName']?.toString(),
              error: m['error']?.toString() ?? '',
            );
          }
          return TtkParseError(error: e.toString());
        }).toList();
      } else {
        lastParseTechCardErrors = null;
      }
      final list = <TechCardRecognitionResult>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final card = _parseTechCardResult(Map<String, dynamic>.from(e as Map));
        if (card != null &&
            (card.dishName != null && card.dishName!.isNotEmpty || card.ingredients.isNotEmpty)) {
          list.add(card);
        }
      }
      // Обучение: сохраняем шаблон PDF для следующих загрузок (rows приходят при успешном AI)
      if (list.isNotEmpty) {
        lastParseTechCardPdfReason = null;
        final rowsRaw = data['rows'];
        if (rowsRaw is List && rowsRaw.isNotEmpty) {
          final rows = rowsRaw.map((r) => (r is List ? r : <String>[]).map((c) => c?.toString() ?? '').toList()).toList();
          if (rows.length >= 2) _saveTemplateAfterAi(rows, list, 'pdf');
        }
      }
      if (list.isEmpty) lastParseTechCardErrors = null;
      return list;
    } catch (e) {
      lastParseTechCardPdfReason = 'catch: $e';
      lastParseTechCardErrors = null;
      return [];
    }
  }

  List<List<String>> _csvToRows(Uint8List bytes) {
    try {
      var s = utf8.decode(bytes, allowMalformed: true);
      if (s.startsWith('\uFEFF')) s = s.substring(1);
      if (s.contains('\r')) s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      List<List<dynamic>> best = CsvToListConverter(eol: '\n').convert(s);
      if (best.isEmpty) return [];
      int bestCols = best.first is List ? (best.first as List).length : 0;
      for (final d in [';', '\t', '|']) {
        try {
          final decoded = CsvToListConverter(fieldDelimiter: d, eol: '\n').convert(s);
          if (decoded.isEmpty) continue;
          final cols = decoded.first is List ? (decoded.first as List).length : 0;
          if (cols >= 2 && cols > bestCols) {
            best = decoded;
            bestCols = cols;
          }
        } catch (_) {}
      }
      final rows = <List<String>>[];
      for (final row in best) {
        if (row is! List) continue;
        final strRow = row.map((c) => c?.toString().trim() ?? '').toList();
        if (strRow.any((c) => c.isNotEmpty)) rows.add(strRow);
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// Параграфы перед первой таблицей (название блюда в ГОСТ docx: «Салат Цезарь» и т.п.)
  List<List<String>> _docxLeadingRows(Uint8List bytes) {
    final lead = <List<String>>[];
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = archive.findFile('word/document.xml');
      if (doc == null) return lead;
      final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
      final body = xml.descendants.whereType<XmlElement>().where((e) => e.localName == 'body').firstOrNull;
      if (body == null) return lead;
      final skipStart = RegExp(r'^(ттк|технико-технологическая|технологическая карта|область применения|настоящая|органолептическ|внешний вид|консистенция|запах|вкус|цвет)', caseSensitive: false);
      for (final child in body.childElements) {
        if (child.localName == 'tbl') break; // первая таблица — стоп
        if (child.localName != 'p') continue;
        final texts = child.descendants.whereType<XmlElement>().where((e) => e.localName == 't').map((e) => e.innerText).toList();
        final line = texts.join('').trim();
        if (line.isEmpty || line.length > 80) continue;
        if (skipStart.hasMatch(line)) continue;
        if (RegExp(r'^\d+\.\s').hasMatch(line)) continue; // "1. ОБЛАСТЬ ПРИМЕНЕНИЯ"
        lead.add([line]);
        if (lead.length >= 3) break; // не более 3 строк (название + возможно подзаголовок)
      }
    } catch (_) {}
    return lead;
  }

  /// Все таблицы DOCX (для файлов с несколькими ТТК).
  List<List<List<String>>> _docxToAllTables(Uint8List bytes) {
    final result = <List<List<String>>>[];
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = archive.findFile('word/document.xml');
      if (doc == null) return result;
      final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
      final leading = _docxLeadingRows(bytes);
      var tableIndex = 0;
      for (final tbl in xml.descendants.whereType<XmlElement>().where((e) => e.localName == 'tbl')) {
        final tableRows = <List<String>>[];
        for (final tr in tbl.children.whereType<XmlElement>().where((e) => e.localName == 'tr')) {
          final cells = <String>[];
          for (final tc in tr.children.whereType<XmlElement>().where((e) => e.localName == 'tc')) {
            final texts = tc.descendants.whereType<XmlElement>().where((e) => e.localName == 't').map((e) => e.innerText).toList();
            cells.add(texts.join('').trim());
          }
          if (cells.any((c) => c.isNotEmpty)) tableRows.add(cells);
        }
        if (tableRows.length >= 2) {
          if (tableIndex == 0 && leading.isNotEmpty) {
            result.add([...leading, ...tableRows]);
          } else {
            result.add(tableRows);
          }
          tableIndex++;
        }
      }
    } catch (_) {}
    return result;
  }

  List<List<String>> _docxToRows(Uint8List bytes) {
    try {
      final tables = _docxToAllTables(bytes);
      if (tables.isNotEmpty) return tables.first;
      // 2. Fallback: параграфы (документ без таблицы)
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = archive.findFile('word/document.xml');
      if (doc == null) return [];
      final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
      final paras = xml.descendants.whereType<XmlElement>().where((e) => e.localName == 'p');
      final rows = <List<String>>[];
      for (final p in paras) {
        final texts = p.descendants.whereType<XmlElement>().where((e) => e.localName == 't').map((e) => e.innerText).toList();
        final line = texts.join('').trim();
        if (line.isNotEmpty) rows.add([line]);
      }
      if (rows.isEmpty) {
        final allT = xml.descendants.whereType<XmlElement>().where((e) => e.localName == 't').map((e) => e.innerText).join(' ');
        if (allT.trim().isNotEmpty) {
          for (final s in allT.split(RegExp(r'\s+')).where((s) => s.length > 1)) {
            rows.add([s]);
          }
        }
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// Все листы xlsx как список rows (для парсинга многолистовых файлов).
  List<List<List<String>>> _xlsxToAllSheetsRows(Uint8List bytes) {
    try {
      final decodable = IikoXlsxSanitizer.ensureDecodable(bytes);
      final excel = Excel.decodeBytes(decodable.toList());
      final result = <List<List<String>>>[];
      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName]!;
        final rows = <List<String>>[];
        for (var r = 0; r < sheet.maxRows; r++) {
          final row = <String>[];
          for (var c = 0; c < sheet.maxColumns; c++) {
            final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
            row.add(_cellValueToString(cell.value));
          }
          if (row.any((s) => s.trim().isNotEmpty)) rows.add(row);
        }
        if (rows.length >= 2) result.add(rows);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  List<List<String>> _xlsxToRows(Uint8List bytes) {
    try {
      final decodable = IikoXlsxSanitizer.ensureDecodable(bytes);
      final excel = Excel.decodeBytes(decodable.toList());
      final sheetName = excel.tables.keys.isNotEmpty ? excel.tables.keys.first : null;
      if (sheetName == null) return [];
      final sheet = excel.tables[sheetName]!;
      final rows = <List<String>>[];
      for (var r = 0; r < sheet.maxRows; r++) {
        final row = <String>[];
        for (var c = 0; c < sheet.maxColumns; c++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
          final v = cell.value;
          row.add(_cellValueToString(v));
        }
        if (row.any((s) => s.trim().isNotEmpty)) rows.add(row);
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// Парсинг .xls (BIFF) через Supabase Edge Function — Dart excel пакет .xls не поддерживает
  Future<List<List<String>>> _parseXlsViaServer(Uint8List bytes) async {
    try {
      final res = await _client.functions.invoke(
        'parse-xls-bytes',
        body: {'bytes': base64Encode(bytes), 'rawRows': true},
      ).timeout(const Duration(seconds: 20));
      if (res.status != 200) return [];
      final data = res.data;
      if (data is! Map) return [];
      final raw = data['rows'];
      if (raw is! List) return [];
      final rows = <List<String>>[];
      for (final r in raw) {
        if (r is! List) continue;
        rows.add(r.map((c) => (c ?? '').toString().trim()).toList());
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// Парсинг .doc (Word 97–2003) через Supabase Edge Function — word-extractor
  Future<List<List<String>>> _parseDocViaServer(Uint8List bytes) async {
    try {
      final res = await _client.functions.invoke(
        'parse-doc-bytes',
        body: {'bytes': base64Encode(bytes)},
      ).timeout(const Duration(seconds: 25));
      if (res.status != 200) return [];
      final data = res.data;
      if (data is! Map) return [];
      final raw = data['rows'];
      if (raw is! List) return [];
      final rows = <List<String>>[];
      for (final r in raw) {
        if (r is! List) continue;
        rows.add(r.map((c) => (c ?? '').toString().trim()).toList());
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  static String _cellValueToString(CellValue? v) {
    if (v == null) return '';
    if (v is TextCellValue) {
      final val = v.value;
      // excel 4.x: value can be String or TextSpan
      if (val is String) return val as String;
      try {
        final t = (val as dynamic).text;
        if (t != null) return t is String ? t : t.toString();
      } catch (_) {}
      return val.toString();
    }
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    return v.toString();
  }

  /// Разворачивает строки с одной ячейкой в несколько (для DOCX: каждая строка — один параграф).
  static List<List<String>> _expandSingleCellRows(List<List<String>> rows) {
    if (rows.isEmpty) return rows;
    final singleCell = rows.every((r) => r.length <= 1);
    if (!singleCell) return rows;
    final expanded = <List<String>>[];
    for (final row in rows) {
      final line = row.isEmpty ? '' : (row[0] as String).trim();
      if (line.isEmpty) continue;
      List<String> cells;
      final byTab = line.split('\t').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (byTab.length >= 3) {
        cells = byTab;
      } else {
        final bySpaces = line.split(RegExp(r'\s{2,}')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (bySpaces.length >= 3) {
          cells = bySpaces;
        } else {
          // "1 Т. Крылья... кг 0,150 0,150" — числа в конце
          final trailing = RegExp(r'([\d,.\-]+\s*)+$').firstMatch(line);
          if (trailing != null) {
            final numsPart = trailing.group(0)!.trim();
            final nums = numsPart.split(RegExp(r'\s+'));
            final rest = line.substring(0, line.length - numsPart.length).trim();
            final numStart = RegExp(r'^(\d+)\s+(.+)$').firstMatch(rest);
            cells = numStart != null
                ? [numStart.group(1)!, numStart.group(2)!, ...nums]
                : [rest, ...nums];
          } else {
            cells = line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          }
        }
      }
      if (cells.isNotEmpty) expanded.add(cells);
    }
    return expanded;
  }

  /// Приводит строки к одной длине (макс. число колонок) — parse-xls-bytes может вернуть разную длину.
  static List<List<String>> _normalizeRowLengths(List<List<String>> rows) {
    if (rows.isEmpty) return rows;
    final maxLen = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    if (maxLen <= 0) return rows;
    return rows.map((r) {
      if (r.length >= maxLen) return r;
      return [...r, ...List.filled(maxLen - r.length, '')];
    }).toList();
  }

  /// КК (калькуляционная карта) из таблицы — когда есть колонки Цена, Сумма, Норма.
  static List<TechCardRecognitionResult> _tryParseKkFromRows(List<List<String>> rows) {
    if (rows.length < 2) return [];
    int headerIdx = -1, productCol = -1, normCol = -1, unitCol = -1, priceCol = -1;
    for (var r = 0; r < rows.length && r < 15; r++) {
      final row = rows[r].map((c) => c.trim().toLowerCase()).toList();
      bool hasPrice = false;
      bool hasProduct = false;
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell.contains('цена') || cell.contains('price')) { headerIdx = r; priceCol = c; hasPrice = true; }
        if (cell.contains('сумма') || cell.contains('sum')) hasPrice = true;
        if (cell.contains('норма') || cell.contains('norm')) { headerIdx = r; normCol = c; }
        if (cell.contains('продукт') || cell.contains('наименование') || cell.contains('сырьё')) { headerIdx = r; productCol = c; hasProduct = true; }
        if (cell.contains('ед') && cell.contains('изм')) { headerIdx = r; unitCol = c; }
      }
      if (headerIdx >= 0 && hasPrice && (productCol >= 0 || normCol >= 0)) {
        if (productCol < 0) productCol = 1;
        if (normCol < 0 && row.length > 2) normCol = 2;
        if (priceCol < 0 && row.length > 4) priceCol = 4;
        break;
      }
      headerIdx = -1;
      productCol = -1;
      normCol = -1;
      priceCol = -1;
    }
    if (headerIdx < 0 || productCol < 0) return [];
    String? dishName;
    for (var r = 0; r < headerIdx; r++) {
      for (final c in rows[r]) {
        final s = c.trim();
        if (s.length >= 4 && s.length < 80 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(s) && !s.toLowerCase().contains('калькуляционная') && !s.toLowerCase().contains('оп-1')) {
          dishName = s;
          break;
        }
      }
      if (dishName != null) break;
    }
    final ingredients = <TechCardIngredientLine>[];
    for (var r = headerIdx + 1; r < rows.length; r++) {
      final cells = rows[r].map((c) => c.trim()).toList();
      if (cells.length <= productCol) continue;
      final productVal = cells[productCol];
      if (productVal.isEmpty || productVal.toLowerCase() == 'итого' || productVal.toLowerCase().startsWith('общая стоимость')) break;
      if (!RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(productVal)) continue;
      final norm = normCol >= 0 && normCol < cells.length ? _parseNum(cells[normCol]) : null;
      final price = priceCol >= 0 && priceCol < cells.length ? _parseNum(cells[priceCol]) : null;
      if (norm == null || norm <= 0) continue;
      final unitCell = unitCol >= 0 && unitCol < cells.length ? cells[unitCol].toLowerCase() : 'кг';
      double grams = norm;
      if (unitCell.contains('кг') || unitCell == 'kg') grams = norm * 1000;
      else if (unitCell.contains('л') || unitCell == 'l') grams = norm * 1000;
      double? pricePerKg;
      if (price != null && price > 0) {
        if (unitCell.contains('кг') || unitCell.contains('л') || unitCell == 'kg' || unitCell == 'l') pricePerKg = price;
        else if (unitCell.contains('шт')) pricePerKg = norm > 0 ? (price / norm) * 1000 : null;
      }
      String cleanName = productVal.replaceFirst(RegExp(r'^Т\.\s*', caseSensitive: false), '').replaceFirst(RegExp(r'^П/Ф\s*', caseSensitive: false), '').trim();
      if (cleanName.isEmpty) cleanName = productVal;
      ingredients.add(TechCardIngredientLine(
        productName: cleanName,
        grossGrams: grams,
        netGrams: grams,
        primaryWastePct: null,
        unit: unitCell.contains('л') ? 'ml' : unitCell.contains('шт') ? 'pcs' : 'g',
        ingredientType: RegExp(r'^П/Ф\s', caseSensitive: false).hasMatch(productVal) ? 'semi_finished' : 'product',
        pricePerKg: pricePerKg,
      ));
    }
    if (ingredients.isEmpty) return [];
    return [TechCardRecognitionResult(dishName: dishName ?? 'Без названия', ingredients: ingredients, isSemiFinished: false)];
  }

  /// Ищет следующую валидную шапку ТТК после ошибки. Ищем по полному содержимому строки.
  static int _findNextValidHeader(List<List<String>> rows, int nameCol, int productCol, int fromRow) {
    final newCardPattern = RegExp(r'ттк\s*№|карта\s*№|технол\.?\s*карта\s*№|рецепт\s*№|т\.?\s*к\.?\s*№|наименование\s+блюда', caseSensitive: false);
    for (var r = fromRow; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;
      final cells = row.map((c) => c.trim()).toList();
      if (cells.every((c) => c.isEmpty)) continue;
      final rowText = cells.join(' ').toLowerCase();
      if (newCardPattern.hasMatch(rowText)) return r; // маркер новой карточки в любом столбце
      final productVal = productCol < cells.length ? cells[productCol] : '';
      final low = productVal.toLowerCase();
      if (low == 'итого' || low.startsWith('всего')) return r + 1;
      final nameVal = nameCol < cells.length ? cells[nameCol] : '';
      if (nameVal.isNotEmpty && !RegExp(r'^[\d\s.,]+$').hasMatch(nameVal) && low != 'итого') return r;
    }
    return rows.length;
  }

  /// Формат «Полное пособие Кухня» / супы.xlsx: [название] [№|Наименование продукта|Вес] [ингредиенты] [Выход] — повтор блоков.
  static List<TechCardRecognitionResult> _tryParsePolnoePosobieFormat(List<List<String>> rows) {
    final results = <TechCardRecognitionResult>[];
    var r = 0;
    while (r < rows.length) {
      final row = rows[r];
      final cells = row.map((c) => (c ?? '').toString().trim()).toList();
      if (cells.every((c) => c.isEmpty)) { r++; continue; }
      final c0 = cells.isNotEmpty ? cells[0].trim().toLowerCase() : '';
      // Конец блока
      if (c0 == 'выход') { r++; continue; }
      // Строка заголовка №|Наименование продукта
      if (c0 == '№' && cells.length > 1) {
        final c1 = cells[1].toLowerCase();
        if (c1.contains('наименование') && c1.contains('продукт')) { r++; continue; }
      }
      // Ищем блок: следующая строка — №|Наименование продукта
      if (r + 1 >= rows.length) { r++; continue; }
      final nextRow = rows[r + 1].map((c) => (c ?? '').toString().trim()).toList();
      final next0 = nextRow.isNotEmpty ? nextRow[0].toLowerCase() : '';
      final next1 = nextRow.length > 1 ? nextRow[1].toLowerCase() : '';
      if (next0 != '№' || !next1.contains('наименование') || !next1.contains('продукт')) {
        r++;
        continue;
      }
      final dishName = cells.isNotEmpty ? cells[0].trim() : '';
      if (dishName.length < 3 || !RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(dishName) ||
          RegExp(r'^№$|^выход$|^декор$', caseSensitive: false).hasMatch(dishName)) {
        r++;
        continue;
      }
      final ingredients = <TechCardIngredientLine>[];
      String? technologyText;
      var dataRow = r + 2;
      while (dataRow < rows.length) {
        final dr = rows[dataRow].map((c) => (c ?? '').toString().trim()).toList();
        if (dr.every((c) => c.isEmpty)) { dataRow++; continue; }
        final d0 = dr.isNotEmpty ? dr[0].toLowerCase() : '';
        if (d0 == 'выход') break;
        if (d0 == '№' && dr.length > 1 && dr[1].toLowerCase().contains('наименование')) break;
        final product = dr.length > 1 ? dr[1].trim() : '';
        final grossStr = dr.length > 2 ? dr[2].trim() : '';
        final looksLikeIngredient = product.isNotEmpty && (RegExp(r'\d').hasMatch(grossStr) || grossStr.toLowerCase().contains('шт'));
        if (looksLikeIngredient) {
          // Не сбрасываем technologyText — технология может идти до или после ингредиентов
        } else {
          final rowText = dr.join(' ');
          if (rowText.toLowerCase().contains('технология')) {
            final techParts = <String>[];
            for (var c = 0; c < dr.length; c++) {
              final cell = dr[c].trim();
              if (cell.isEmpty || cell.toLowerCase().contains('технология')) continue;
              if (cell.length > 10 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(cell)) techParts.add(cell);
            }
            if (techParts.isNotEmpty) technologyText = (technologyText != null ? '$technologyText\n' : '') + techParts.join(' ');
            dataRow++;
            continue;
          }
          if (technologyText != null) {
            final more = dr.where((c) => c.length > 15 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(c)).join(' ').trim();
            if (more.isNotEmpty) technologyText = '$technologyText\n$more';
            dataRow++;
            continue;
          }
        }
        if (product.isEmpty) { dataRow++; continue; }
        if (product.toLowerCase() == 'декор') { dataRow++; continue; }
        final gross = _parseNum(grossStr);
        if (gross == null && !RegExp(r'\d').hasMatch(grossStr)) { dataRow++; continue; }
        final grossVal = gross ?? 0.0;
        if (grossVal <= 0 && grossStr.replaceAll(RegExp(r'[^\d]'), '').isEmpty) { dataRow++; continue; }
        var unit = 'g';
        if (grossStr.toLowerCase().contains('шт') || grossStr.toLowerCase().contains('л')) unit = 'pcs';
        final isPf = RegExp(r'^П/Ф\s|п/ф|пф(?!\w)', caseSensitive: false).hasMatch(product) ||
            RegExp(r'\sп/ф\s*$|\sпф\s*$', caseSensitive: false).hasMatch(product);
        ingredients.add(TechCardIngredientLine(
          productName: product.replaceFirst(RegExp(r'^П/Ф\s*', caseSensitive: false), '').trim(),
          grossGrams: grossVal,
          netGrams: grossVal,
          outputGrams: grossVal,
          primaryWastePct: null,
          unit: unit,
          ingredientType: isPf ? 'semi_finished' : 'product',
        ));
        dataRow++;
      }
      if (dishName.isNotEmpty && ingredients.isNotEmpty) {
        results.add(TechCardRecognitionResult(
          dishName: dishName,
          ingredients: ingredients,
          isSemiFinished: dishName.toLowerCase().contains('пф'),
          technologyText: technologyText?.trim().isNotEmpty == true ? technologyText!.trim() : null,
        ));
      }
      r = dataRow;
    }
    return results;
  }

  /// пф гц / пф хц: блоки [название п/ф] [""|№|наименование|Ед.изм|Норма…] [№|продукт|ед|норма|технология]... [Выход]
  static List<TechCardRecognitionResult> _tryParsePfGcFormat(List<List<String>> rows) {
    if (rows.length < 4) return [];
    final results = <TechCardRecognitionResult>[];
    var r = 0;
    while (r < rows.length) {
      final row = rows[r].map((c) => (c ?? '').toString().trim()).toList();
      if (row.every((c) => c.isEmpty)) { r++; continue; }
      final dishName = row.isNotEmpty ? row[0].trim() : '';
      if (dishName.length < 3 || !RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(dishName) ||
          RegExp(r'^№$|^выход$|^итого$|^наименование$', caseSensitive: false).hasMatch(dishName.toLowerCase())) {
        r++;
        continue;
      }
      if (r + 1 >= rows.length) break;
      final headerRow = rows[r + 1].map((c) => (c ?? '').toString().trim()).toList();
      final h0 = headerRow.isNotEmpty ? headerRow[0].trim().toLowerCase() : '';
      final h1 = headerRow.length > 1 ? headerRow[1].trim().toLowerCase() : '';
      final h2 = headerRow.length > 2 ? headerRow[2].trim().toLowerCase() : '';
      final h3 = headerRow.length > 3 ? headerRow[3].trim().toLowerCase() : '';
      final hasNormInHeader = h3.contains('норма') || h3.contains('закладк') || h2.contains('норма');
      final headerOk = (h0.isEmpty || h0 == '№') &&
          h1.contains('наименование') &&
          (h2.contains('ед') || h2.contains('изм'));
      if (!headerOk && !(hasNormInHeader && h1.contains('наименование'))) {
        r++;
        continue;
      }
      int techColByHeader = -1;
      for (var i = 0; i < headerRow.length; i++) {
        if (headerRow[i].toLowerCase().contains('технол')) {
          techColByHeader = i;
          break;
        }
      }
      final hasTechCol = techColByHeader >= 0;
      final ingredients = <TechCardIngredientLine>[];
      String? technologyText;
      double? outputGrams;
      var dataR = r + 2;
      while (dataR < rows.length) {
        final dr = rows[dataR].map((c) => (c ?? '').toString().trim()).toList();
        if (dr.every((c) => c.isEmpty)) { dataR++; continue; }
        final d0 = dr.isNotEmpty ? dr[0].toLowerCase().trim() : '';
        final d1 = dr.length > 1 ? dr[1].trim().toLowerCase() : '';
        if (d0 == 'выход' || (d0.startsWith('выход') && d0.length < 20)) {
          // Значение может быть в col 2 или 3; единица кг — в col 1 или 2 (формат: Выход | | кг | 0.7)
          num? outVal;
          for (var i = 2; i < dr.length && i < 5; i++) {
            outVal = _parseNum(dr[i]);
            if (outVal != null && outVal > 0) break;
          }
          if (outVal != null && outVal > 0) {
            final unitCell = d0 + (dr.length > 1 ? dr[1] : '') + (dr.length > 2 ? dr[2] : '');
            outputGrams = (unitCell.toLowerCase().contains('кг') && outVal < 100 ? outVal * 1000 : outVal).toDouble();
          }
          break;
        }
        if (d0 == '№' && d1.contains('наименование')) break;
        final prodCol = (dr.length > 1 && RegExp(r'^\d+$').hasMatch(dr[0])) ? 1 : (dr[0].isEmpty && dr.length > 1 ? 1 : 0);
        final product = dr.length > prodCol ? dr[prodCol].trim() : '';
        if (product.toLowerCase().contains('наименование') && product.toLowerCase().contains('продукт')) {
          dataR++; continue;
        }
        // Вариант без Ед.изм: Наименование | Норма | Технология — норма в col prodCol+1
        final h2 = headerRow.length > 2 ? headerRow[2].toLowerCase() : '';
        final normInCol2 = h2.contains('норма') && !h2.contains('ед') && !h2.contains('изм');
        final unitCol = normInCol2 ? -1 : prodCol + 1;
        final normCol = normInCol2 ? prodCol + 1 : prodCol + 2;
        final techCol = hasTechCol ? techColByHeader : prodCol + 3;
        final unit = unitCol >= 0 && dr.length > unitCol ? dr[unitCol].trim().toLowerCase() : '';
        final normStr = dr.length > normCol ? dr[normCol].trim() : '';
        if (product.isEmpty) {
          if (hasTechCol && dr.length > techCol && dr[techCol].trim().length > 10) {
            technologyText = (technologyText != null ? '$technologyText\n' : '') + dr[techCol].trim();
          }
          dataR++; continue;
        }
        final norm = _parseNum(normStr);
        if (norm == null && !RegExp(r'\d').hasMatch(normStr)) {
          if (hasTechCol && dr.length > techCol && dr[techCol].trim().length > 10) {
            technologyText = (technologyText != null ? '$technologyText\n' : '') + dr[techCol].trim();
          }
          dataR++; continue;
        }
        var grams = norm ?? 0.0;
        if (unit.contains('кг') && grams > 0 && grams < 100) grams *= 1000;
        if (unit.contains('л') && grams > 0 && grams < 10) grams *= 1000;
        if (unit.isEmpty && grams > 0 && grams < 50) grams *= 1000; // формат без Ед.изм — числа в кг
        if (grams <= 0) {
          if (hasTechCol && dr.length > techCol && dr[techCol].trim().length > 10) {
            technologyText = (technologyText != null ? '$technologyText\n' : '') + dr[techCol].trim();
          }
          dataR++; continue;
        }
        if (hasTechCol && dr.length > techCol && dr[techCol].trim().length > 10) {
          technologyText = (technologyText != null ? '$technologyText\n' : '') + dr[techCol].trim();
        }
        final isPf = RegExp(r'п/ф|пф\s', caseSensitive: false).hasMatch(product);
        ingredients.add(TechCardIngredientLine(
          productName: product.replaceFirst(RegExp(r'^П/Ф\s*', caseSensitive: false), '').trim(),
          grossGrams: grams,
          netGrams: grams,
          outputGrams: grams,
          primaryWastePct: null,
          unit: unit.contains('л') ? 'ml' : (unit.contains('шт') ? 'pcs' : 'g'),
          ingredientType: isPf ? 'semi_finished' : 'product',
        ));
        dataR++;
      }
      if (dishName.isNotEmpty && ingredients.isNotEmpty) {
        results.add(TechCardRecognitionResult(
          dishName: dishName,
          technologyText: technologyText?.trim().isNotEmpty == true ? technologyText!.trim() : null,
          ingredients: ingredients,
          isSemiFinished: dishName.toLowerCase().contains('пф'),
          yieldGrams: outputGrams,
        ));
      }
      final hitNextHeader = dataR < rows.length && rows[dataR].isNotEmpty &&
          rows[dataR][0].trim().toLowerCase() == '№' &&
          (rows[dataR].length > 1 && rows[dataR][1].trim().toLowerCase().contains('наименование'));
      r = hitNextHeader && dataR > 0 ? dataR - 1 : dataR + 1;
    }
    return results;
  }

  /// Не заменять корректный парсинг (с ингредиентами) на multiBlock без ингредиентов (Мясная к пенному и т.п.).
  static bool _shouldPreferMultiBlock(List<TechCardRecognitionResult> part, List<TechCardRecognitionResult> multiBlock) {
    if (multiBlock.length <= part.length) return false;
    final partHasIngredients = part.any((c) => c.ingredients.isNotEmpty);
    final multiHasIngredients = multiBlock.any((c) => c.ingredients.isNotEmpty);
    if (partHasIngredients && !multiHasIngredients) return false; // не ломать рабочий парсинг
    return true;
  }

  /// Несколько блоков таблиц на одном листе (карточки в колонках K, R и т.д.). Привязка к данным, не к колонке.
  static List<TechCardRecognitionResult> _tryParseMultiColumnBlocks(List<List<String>> rows) {
    if (rows.length < 2) return [];
    final maxCol = rows.fold<int>(0, (m, r) => m > r.length ? m : r.length);
    if (maxCol < 12) return [];
    const headerWords = ['наименование', 'продукт', 'брутто', 'нетто', 'сырьё', 'сырья', 'расход', 'норма'];
    final headerCols = <int>[];
    for (var c = 0; c < maxCol && c < 30; c++) {
      for (var r = 0; r < rows.length && r < 20; r++) {
        final cell = r < rows.length && c < rows[r].length ? rows[r][c].trim().toLowerCase() : '';
        if (headerWords.any((w) => cell.contains(w))) {
          headerCols.add(c);
          break;
        }
      }
    }
    if (headerCols.isEmpty) return [];
    headerCols.sort();
    final blocks = <List<int>>[];
    for (final c in headerCols) {
      if (blocks.isEmpty || c - blocks.last.last > 4) {
        blocks.add([c]);
      } else {
        blocks.last.add(c);
      }
    }
    final merged = <TechCardRecognitionResult>[];
    final seen = <String>{};
    for (final block in blocks) {
      if (block.length < 2) continue;
      final start = block.first;
      final end = (block.last + 6).clamp(start + 3, maxCol);
      final subRows = rows.map((row) {
        if (row.length <= start) return <String>[];
        return row.sublist(start, end.clamp(0, row.length));
      }).where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
      if (subRows.length < 2) continue;
      final part = parseTtkByTemplate(subRows);
      for (final card in part) {
        if (card.ingredients.isEmpty) continue;
        final key = '${card.dishName ?? ""}|${card.ingredients.map((i) => i.productName).join(",")}';
        if (seen.contains(key)) continue;
        seen.add(key);
        merged.add(card);
      }
    }
    return merged;
  }

  /// Единицы ("г", "кДж)") и КБЖУ — не названия блюд.
  static bool _isValidDishName(String s) {
    if (s.length < 4) return false;
    final t = s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^(г|кг|мл|л|шт|кдж\)?|ккал\)?)$').hasMatch(t)) return false;
    if (RegExp(r'^\d+\s*кдж\)?$', caseSensitive: false).hasMatch(s)) return false;
    if (RegExp(r'^\d+\s*ккал$', caseSensitive: false).hasMatch(s)) return false;
    return RegExp(r'[а-яА-ЯёЁa-zA-Z]{2,}').hasMatch(s);
  }

  /// Парсинг ТТК по шаблону (Наименование, Продукт, Брутто, Нетто...) — без вызова ИИ.
  /// [errors] — при не null: try-catch на каждую строку, битые карточки в errors, цикл продолжается.
  static List<TechCardRecognitionResult> parseTtkByTemplate(
    List<List<String>> rows, {
    List<TtkParseError>? errors,
  }) {
    if (rows.length < 2) return [];
    rows = _expandSingleCellRows(rows);
    if (rows.length < 2) return [];

    // Формат «Полное пособие Кухня» / супы.xlsx: блоки [название блюда] [№|Наименование продукта|Вес] [данные] [Выход]
    final polnoePosobie = _tryParsePolnoePosobieFormat(rows);
    if (polnoePosobie.isNotEmpty) return polnoePosobie;

    // пф гц: [название] ["" | наименование | Ед.изм | Норма закладки] [№ | продукт | ед | норма] [Выход] — повтор
    final pfGc = _tryParsePfGcFormat(rows);
    if (pfGc.isNotEmpty) return pfGc;

    final results = <TechCardRecognitionResult>[];
    int headerIdx = -1;
    int nameCol = -1, productCol = -1, grossCol = -1, netCol = -1, wasteCol = -1, outputCol = -1;

    final nameKeys = ['наименование', 'название', 'блюдо', 'пф', 'набор', 'name', 'dish'];
    final productKeys = ['продукт', 'продукты', 'сырьё', 'сырья', 'ингредиент', 'product', 'ingredient'];
    final grossKeys = ['брутто', 'бр', 'вес брутто', 'вес гр', '1 порция', 'расход', 'норма', 'норма закладки', 'масса', 'gross'];
    final netKeys = ['нетто', 'нт', 'вес нетто', 'net'];
    final wasteKeys = ['отход', 'отх', 'waste', 'процент отхода'];
    final outputKeys = ['выход', 'вес готового', 'вес готового продукта', 'готовый', 'output'];
    final unitKeys = ['ед. изм', 'ед изм', 'единица', 'unit'];

    int unitCol = -1;
    bool grossColIsKg = false;
    bool netColIsKg = false;

    // Динамическая детекция колонок: находим строку-заголовок с Наименование, Брутто, Нетто
    for (var r = 0; r < rows.length && r < 25; r++) {
      final row = rows[r].map((c) => c.trim().toLowerCase()).toList();
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell.isEmpty) continue;
        bool _matchKey(String key, String txt) {
          if (key.length <= 3) return txt == key || txt == 'п/ф'; // не "ПФ Крем"
          return txt.contains(key);
        }
        for (final k in nameKeys) {
          if (_matchKey(k, cell)) {
            headerIdx = r;
            nameCol = c;
            break;
          }
        }
        for (final k in productKeys) {
          if (cell.contains(k)) {
            // "Расход сырья на 1 порцию" — группа числовых колонок, не колонка продуктов
            final isNumericHeader = grossKeys.any((g) => cell.contains(g)) || netKeys.any((n) => cell.contains(n));
            if (!isNumericHeader) {
              headerIdx = r;
              productCol = c;
            }
            break;
          }
        }
        for (final k in grossKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            // Предпочитаем колонку с "кг" (Вес брутто, кг вместо Брутто в ед. изм.)
            if (grossCol < 0 || cell.contains('кг')) grossCol = c;
            break;
          }
        }
        for (final k in netKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            if (netCol < 0 || cell.contains('кг')) netCol = c;
            break;
          }
        }
        for (final k in wasteKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            wasteCol = c;
            break;
          }
        }
        for (final k in outputKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            outputCol = c;
            break;
          }
        }
        for (final k in unitKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            unitCol = c;
            break;
          }
        }
      }
      // Не break — собираем все колонки (Брутто/Нетто могут быть во 2-й строке заголовка)
    }
    if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) {
      for (var r = 0; r < rows.length && r < 15; r++) {
        final row = rows[r];
        if (row.length < 2) continue;
        final c0 = row[0].trim().toLowerCase();
        // пф гц: col 0 пусто, col 1 "наименование", col 2 "Ед.изм", col 3 "Норма закладки"
        final c1Low = row.length > 1 ? row[1].trim().toLowerCase() : '';
        if (c0.isEmpty && c1Low == 'наименование' && row.length >= 4) {
          final c2 = row[2].trim().toLowerCase();
          final c3 = row[3].trim().toLowerCase();
          if (c2.contains('ед') && (c2.contains('изм') || c2.contains('зм')) && (c3.contains('норма') || c3.contains('закладк'))) {
            headerIdx = r;
            nameCol = 1;
            productCol = 1;
            unitCol = 2;
            grossCol = 3; // Норма закладки
            break;
          }
        }
        // № | Наименование продукта (c1 может быть пустым — колонка между № и названием)
        if (c0 == '№' || c0 == 'n' || RegExp(r'^\d+$').hasMatch(c0)) {
          var foundProductCol = -1;
          for (var c = 1; c < row.length && c < 12; c++) {
            final h = row[c].trim().toLowerCase();
            if (h.contains('наименование') && h.contains('продукт')) {
              foundProductCol = c;
              break;
            }
          }
          if (foundProductCol >= 0) {
            headerIdx = r;
            nameCol = foundProductCol;
            productCol = foundProductCol;
            for (var c = foundProductCol + 1; c < row.length && c < 12; c++) {
              final h = row[c].trim().toLowerCase();
              if (h.contains('брутто') && (grossCol < 0 || h.contains('кг'))) grossCol = c;
              if (h.contains('нетто') && (netCol < 0 || h.contains('кг'))) netCol = c;
              if ((h.contains('вес гр') || h.contains('1 порция') || h.contains('вес брутто')) && grossCol < 0) grossCol = c;
            }
            if (grossCol < 0 && row.length >= foundProductCol + 2) grossCol = foundProductCol + 1;
            if (netCol < 0 && row.length >= foundProductCol + 4) netCol = foundProductCol + 2;
            break;
          }
        }
        final c1 = row.length > 1 ? row[1].trim() : '';
        if ((c0 == '№' || c0 == 'n') && c1.length >= 2 && !RegExp(r'^[\d,.\s]+$').hasMatch(c1)) {
          headerIdx = r;
          nameCol = 1;
          productCol = 1;
          for (var c = 2; c < row.length && c < 12; c++) {
            final h = row[c].trim().toLowerCase();
            if (h.contains('брутто') && (grossCol < 0 || h.contains('кг'))) grossCol = c;
            if (h.contains('нетто') && (netCol < 0 || h.contains('кг'))) netCol = c;
            if ((h.contains('вес гр') || h.contains('1 порция')) && grossCol < 0) grossCol = c;
          }
          if (grossCol < 0 && row.length >= 3) grossCol = 2;
          if (netCol < 0 && row.length >= 5) netCol = 3;
          if (row.length >= 6) outputCol = 5;
          break;
        }
      }
    }
    if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) return [];

    if (nameCol < 0) nameCol = 0;
    if (productCol < 0) productCol = 1;

    // Запомнили индексы: nameCol, productCol, grossCol, netCol — читаем данные СТРОГО по ним

    // Колонки с "кг" в заголовке — значения в килограммах, переводим в граммы
    final headerRow = headerIdx < rows.length ? rows[headerIdx].map((c) => c.trim().toLowerCase()).toList() : <String>[];
    if (grossCol >= 0 && grossCol < headerRow.length && headerRow[grossCol].contains('кг')) grossColIsKg = true;
    if (netCol >= 0 && netCol < headerRow.length && headerRow[netCol].contains('кг')) netColIsKg = true;

    // Название блюда может быть в строках выше заголовка (DOCX iiko/ГОСТ)
    String? currentDish;
    for (var r = 0; r < headerIdx && r < rows.length; r++) {
      for (final c in rows[r]) {
        final s = c.trim();
        if (s.length < 3) continue;
        if (s.endsWith(':')) continue; // "Хранение:", "Область применения:"
        if (RegExp(r'^\d{1,2}\.\d{1,2}\.\d{2,4}').hasMatch(s)) continue; // дата
        if (s.toLowerCase().startsWith('технологическая карта')) continue;
        if (s.toLowerCase().contains('название на чеке') || s.toLowerCase().contains('название чека')) continue;
        if (s.toLowerCase().contains('органолептическ') || s.toLowerCase().contains('внешний вид') || s.toLowerCase().contains('консистенция') || s.toLowerCase().contains('запах') || s.toLowerCase().contains('вкус') || s.toLowerCase().contains('цвет')) continue;
        if (!_isValidDishName(s)) continue;
        currentDish = s;
        break;
      }
      if (currentDish != null) break;
    }
    final currentIngredients = <TechCardIngredientLine>[];

    void flushCard() {
      if (currentDish != null && (currentDish!.isNotEmpty || currentIngredients.isNotEmpty)) {
        results.add(TechCardRecognitionResult(
          dishName: currentDish,
          ingredients: List.from(currentIngredients),
          isSemiFinished: currentDish?.toLowerCase().contains('пф') ?? false,
        ));
      }
      currentIngredients.clear();
    }

    void clearCurrentCard() {
      currentIngredients.clear();
      currentDish = null;
    }

    var r = headerIdx + 1;
    while (r < rows.length) {
      final row = rows[r];
      if (row.isEmpty) { r++; continue; }
      final cells = row.map((c) => (c ?? '').toString().trim()).toList();
      if (cells.every((c) => c.isEmpty)) { r++; continue; } // пустая строка — continue, не break

      bool processRow() {
      // Если колонок мало (DOCX: № продукт n n n), productCol может указывать на число — берём col 1
      var pCol = productCol;
      var gCol = grossCol;
      var nCol = netCol;
      if (cells.length >= 3 && cells.length <= 8) {
        final atProduct = productCol < cells.length ? cells[productCol] : '';
        if (atProduct.isNotEmpty && RegExp(r'^[\d,.\-\s]+$').hasMatch(atProduct)) {
          pCol = 1;
          if (cells.length >= 4) { gCol = 2; nCol = 3; }
        }
      }
      final nameVal = nameCol < cells.length ? cells[nameCol] : '';
      final productVal = pCol < cells.length ? cells[pCol] : '';
      final grossVal = gCol >= 0 && gCol < cells.length ? cells[gCol] : '';
      final netVal = nCol >= 0 && nCol < cells.length ? cells[nCol] : '';
      final wasteVal = wasteCol >= 0 && wasteCol < cells.length ? cells[wasteCol] : '';
      final outputVal = outputCol >= 0 && outputCol < cells.length ? cells[outputCol] : '';

      // Выход — завершение карточки (формат «Полное пособие Кухня», супы.xlsx)
      final c0 = cells.isNotEmpty ? cells[0].trim().toLowerCase() : '';
      if (c0 == 'выход') {
        flushCard();
        currentDish = null;
        return true;
      }
      // пф гц: новая карточка — название в col 0, col 1 пусто (Песто пф, База на лигурию п/ф)
      final c0Val = cells.isNotEmpty ? cells[0].trim() : '';
      if (c0Val.length >= 3 &&
          _isValidDishName(c0Val) &&
          RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(c0Val) &&
          !RegExp(r'^№$|^выход$|^итого$|^декор$|^наименование$', caseSensitive: false).hasMatch(c0Val.toLowerCase()) &&
          productVal.isEmpty &&
          !RegExp(r'^\d+$').hasMatch(c0Val)) {
        if (currentDish != null || currentIngredients.isNotEmpty) flushCard();
        currentDish = c0Val;
        return true;
      }
      // Новая карточка: строка с названием блюда в col 0, след. строка — №|Наименование продукта (повтор заголовка)
      if (r + 1 < rows.length) {
        final nextRow = rows[r + 1].map((c) => (c ?? '').toString().trim()).toList();
        final nextC0 = nextRow.isNotEmpty ? nextRow[0].toLowerCase() : '';
        final nextC1 = nextRow.length > 1 ? nextRow[1].toLowerCase() : '';
        if (nextC0 == '№' && nextC1.contains('наименование') && nextC1.contains('продукт')) {
          final dishInCol0 = cells.isNotEmpty ? cells[0].trim() : '';
          if (dishInCol0.length >= 3 && _isValidDishName(dishInCol0) && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(dishInCol0) &&
              !RegExp(r'^№$|^выход$|^декор$', caseSensitive: false).hasMatch(dishInCol0)) {
            if (currentDish != null || currentIngredients.isNotEmpty) flushCard();
            currentDish = dishInCol0;
            // Следующая итерация — пропустить строку заголовка (r+1). Сместим r в основном цикле.
            return true;
          }
        }
      }
      // Повтор заголовка №|Наименование продукта — пропуск (второй блок и далее)
      if (c0 == '№' && productVal.toLowerCase().contains('наименование') && productVal.toLowerCase().contains('продукт')) return true;
      // Точки отсечения: Итого и Технология
      if (nameVal.toLowerCase() == 'итого' || productVal.toLowerCase() == 'итого' || productVal.toLowerCase().startsWith('всего')) {
        flushCard();
        currentDish = null;
        return true;
      }
      final rowText = cells.join(' ').toLowerCase();
      if (RegExp(r'^технология\s|^технология\s*:|технология\s+приготовления').hasMatch(rowText) ||
          (rowText.trim().startsWith('технология') && cells.length <= 3)) {
        flushCard();
        currentDish = null;
        return true; // skip — у каждой карточки своя технология, конец ингредиентов
      }
      // Парсер-сканер: начало новой карточки — ищем в полном содержимом строки (не только nameCol)
      // ТТК №, Карта №, Технол. карта №, Рецепт №, Т.к. №, Наименование блюда
      if (RegExp(r'ттк\s*№|карта\s*№|технол\.?\s*карта\s*№|рецепт\s*№|т\.?\s*к\.?\s*№|наименование\s+блюда', caseSensitive: false).hasMatch(rowText)) {
        if (currentDish != null || currentIngredients.isNotEmpty) flushCard();
        clearCurrentCard();
        final dishMatch = RegExp(r'наименование\s+блюда\s*:?\s*([^\n]+)', caseSensitive: false).firstMatch(cells.join(' '));
        final dm = dishMatch?.group(1)?.trim();
        currentDish = (dm != null && dm.isNotEmpty && _isValidDishName(dm)) ? dm : null;
        if (currentDish == null || currentDish!.isEmpty) {
          for (final c in cells) {
            if (c.length > 2 && _isValidDishName(c) && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(c) && !RegExp(r'ттк|карта|брутто|нетто|наименование').hasMatch(c.toLowerCase())) {
              currentDish = c;
              break;
            }
          }
        }
        return true;
      }
      // Повторяющийся заголовок «Наименование | Брутто | Нетто» — признак начала новой ТТК
      if (rowText.contains('брутто') && rowText.contains('нетто') &&
          (rowText.contains('наименование') || rowText.contains('продукт')) && cells.length <= 10) {
        if (r > headerIdx && (currentDish != null || currentIngredients.isNotEmpty)) flushCard();
        currentDish = null;
        return true;
      }
      // Новая карточка: в nameCol новое блюдо (напр. "ПФ Биск,Креветки" — имя и первый ингредиент в одной строке).
      // Не срабатывает при nameCol==pCol (DOCX: имя и продукт из одной колонки).
      if (nameCol != pCol &&
          nameVal.isNotEmpty &&
          !RegExp(r'^[\d\s\.\,]+$').hasMatch(nameVal) &&
          nameVal.toLowerCase() != 'итого') {
        if (currentDish != null && currentDish != nameVal && currentIngredients.isNotEmpty) {
          flushCard();
        }
        if (_isValidDishName(nameVal)) currentDish = nameVal;
      }
      // CSV-формат: при пустом Наименовании название новой карточки может быть в Продукте (ПФ ..., блюдо)
      if (nameCol != pCol && nameVal.isEmpty && productVal.isNotEmpty &&
          RegExp(r'^ПФ\s|^П/Ф\s', caseSensitive: false).hasMatch(productVal) &&
          productVal.length > 5 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(productVal)) {
        if (currentDish != null || currentIngredients.isNotEmpty) flushCard();
        if (_isValidDishName(productVal)) currentDish = productVal;
        // Та же строка может содержать первый ингредиент в col[grossCol] (сдвиг колонок)
        if (gCol >= 0 && gCol + 2 < cells.length) {
          final shiftedProduct = cells[gCol].trim();
          final shiftedGross = gCol + 1 < cells.length ? cells[gCol + 1] : '';
          final shiftedNet = gCol + 3 < cells.length ? cells[gCol + 3] : (nCol < cells.length ? cells[nCol] : '');
          if (shiftedProduct.isNotEmpty && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(shiftedProduct) &&
              shiftedProduct.toLowerCase() != 'итого' &&
              (RegExp(r'\d').hasMatch(shiftedGross) || RegExp(r'\d').hasMatch(shiftedNet))) {
            final sg = _parseNum(shiftedGross);
            final sn = _parseNum(shiftedNet);
            if (sg != null && sg > 0 || sn != null && sn > 0) {
              currentIngredients.add(TechCardIngredientLine(
                productName: shiftedProduct.replaceFirst(RegExp(r'^П/Ф\s*', caseSensitive: false), '').trim(),
                grossGrams: sg,
                netGrams: sn,
                outputGrams: sn,
                primaryWastePct: null,
                unit: 'g',
                ingredientType: RegExp(r'^П/Ф\s', caseSensitive: false).hasMatch(shiftedProduct) ? 'semi_finished' : 'product',
              ));
            }
          }
        }
        return true;
      }
      if (productVal.toLowerCase().contains('выход блюда') || productVal.toLowerCase().startsWith('выход одного')) return true;
      if (productVal.toLowerCase() == 'декор') return true; // секция, не ингредиент
      // Пропускаем, если productVal — только цифры/пробелы (ошибочная колонка)
      if (RegExp(r'^[\d\s\.\,\-\+]+$').hasMatch(productVal)) return true;
      // Мусор: пусто в Наименовании (продукт/название)
      if (productVal.trim().isEmpty && nameVal.trim().isEmpty) return true;
      // Мусор: нет цифр в Брутто (и в Нетто) — строка без веса
      final hasDigitsInGross = gCol >= 0 && RegExp(r'\d').hasMatch(grossVal);
      final hasDigitsInNet = nCol >= 0 && RegExp(r'\d').hasMatch(netVal);
      if (productVal.isNotEmpty && !hasDigitsInGross && !hasDigitsInNet) return true;
      // Строка с продуктом (ингредиент)
      if (productVal.isNotEmpty) {
        if (currentDish == null && nameVal.isNotEmpty && _isValidDishName(nameVal)) currentDish = nameVal;
        var gross = _parseNum(grossVal);
        var net = _parseNum(netVal);
        var output = _parseNum(outputVal);
        final unitCell = unitCol >= 0 && unitCol < cells.length ? cells[unitCol].trim().toLowerCase() : '';
        final unitIsKg = unitCell.contains('кг') || unitCell == 'kg';
        if (grossColIsKg || (unitIsKg && gross != null && gross > 0 && gross < 100)) {
          if (gross != null && gross > 0 && gross < 100) gross = gross * 1000;
        }
        if (netColIsKg || (unitIsKg && net != null && net > 0 && net < 100)) {
          if (net != null && net > 0 && net < 100) net = net * 1000;
        }
        var outputG = output;
        if (outputCol >= 0 && outputCol < headerRow.length && headerRow[outputCol].contains('кг')) {
          if (output != null && output > 0 && output < 100) outputG = output * 1000;
        }
        var waste = _parseNum(wasteVal);
        if (gross != null && gross > 0 && net != null && net > 0 && net < gross && (waste == null || waste == 0)) {
          waste = (1.0 - net / gross) * 100.0;
        }
        String unit = 'g';
        if (unitCell.contains('л') || unitCell == 'l') unit = 'ml';
        else if (unitCell.contains('шт') || unitCell == 'pcs') unit = 'pcs';
        String cleanName = productVal.replaceFirst(RegExp(r'^Т\.\s*', caseSensitive: false), '').replaceFirst(RegExp(r'^П/Ф\s*', caseSensitive: false), '').trim();
        if (cleanName.isEmpty) cleanName = productVal;
        final isPf = RegExp(r'^П/Ф\s', caseSensitive: false).hasMatch(productVal);
        final effectiveNet = net ?? gross; // Норма закладки — одно значение
        currentIngredients.add(TechCardIngredientLine(
          productName: cleanName,
          grossGrams: gross,
          netGrams: effectiveNet,
          outputGrams: outputG,
          primaryWastePct: waste,
          unit: unit,
          ingredientType: isPf ? 'semi_finished' : 'product',
        ));
      }
      return false; // processed
      } // processRow

      if (errors != null) {
        try {
          final skip = processRow();
          if (skip) { r++; continue; }
        } catch (e, st) {
          devLog('parseTtkByTemplate ОШИБКА на строке $r: $e');
          devLog('parseTtkByTemplate stack: $st');
          errors.add(TtkParseError(dishName: currentDish, error: e.toString()));
          clearCurrentCard();
          r = _findNextValidHeader(rows, nameCol, productCol, r + 1);
          continue;
        }
      } else {
        final skip = processRow();
        if (skip) { r++; continue; }
      }
      r++;
    }
    flushCard();
    return results;
  }

  /// Безопасный парсинг числа: «0.5 кг», «1/2 шт», запятые, пробелы. Никогда не бросает.
  static double safeParseDouble(dynamic value, {double def = 0.0}) {
    if (value == null) return def;
    if (value is num) return value.toDouble();
    final s = value.toString().trim();
    if (s.isEmpty) return def;
    // Запятая → точка, удаляем буквы (кг, г, шт)
    final cleaned = s.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.\-]'), '');
    if (cleaned.isEmpty) return def;
    // Дробь 1/2
    final fracMatch = RegExp(r'^(\d+)/(\d+)$').firstMatch(s.replaceAll(' ', ''));
    if (fracMatch != null) {
      final a = int.tryParse(fracMatch.group(1) ?? '');
      final b = int.tryParse(fracMatch.group(2) ?? '');
      if (a != null && b != null && b != 0) return a / b;
    }
    return double.tryParse(cleaned) ?? def;
  }

  /// Парсинг веса: вычищаем мусор RegExp(r'[^0-9.,\-]'), запятая → точка.
  static double? _parseNum(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final fracMatch = RegExp(r'^(\d+)/(\d+)$').firstMatch(t.replaceAll(' ', ''));
    if (fracMatch != null) {
      final a = int.tryParse(fracMatch.group(1) ?? ''), b = int.tryParse(fracMatch.group(2) ?? '');
      if (a != null && b != null && b != 0) return a / b;
    }
    final cleaned = t.replaceAll(RegExp(r'[^0-9.,\-]'), '').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static String _headerSignature(List<String> headerCells) {
    return headerCells.map((c) => c.trim().toLowerCase()).where((c) => c.isNotEmpty).join('|');
  }

  /// Парсинг по сохранённому шаблону (колонки заданы явно).
  static List<TechCardRecognitionResult> parseTtkByStoredTemplate(
    List<List<String>> rows, {
    required int headerIdx,
    required int nameCol,
    required int productCol,
    int grossCol = -1,
    int netCol = -1,
    int wasteCol = -1,
    int outputCol = -1,
  }) {
    if (rows.length <= headerIdx + 1) return [];
    String? currentDish;
    final currentIngredients = <TechCardIngredientLine>[];
    final results = <TechCardRecognitionResult>[];

    void flushCard() {
      if (currentDish != null && (currentDish!.isNotEmpty || currentIngredients.isNotEmpty)) {
        results.add(TechCardRecognitionResult(
          dishName: currentDish,
          ingredients: List.from(currentIngredients),
          isSemiFinished: currentDish?.toLowerCase().contains('пф') ?? false,
        ));
      }
      currentIngredients.clear();
    }

    for (var r = 0; r < headerIdx && r < rows.length; r++) {
      for (final c in rows[r]) {
        final s = c.trim();
        if (s.length < 3) continue;
        if (s.endsWith(':')) continue;
        if (RegExp(r'^\d{1,2}\.\d{1,2}\.\d{2,4}').hasMatch(s)) continue;
        if (s.toLowerCase().startsWith('технологическая карта')) continue;
        if (s.toLowerCase().contains('органолептическ') || s.toLowerCase().contains('внешний вид') || s.toLowerCase().contains('консистенция') || s.toLowerCase().contains('запах') || s.toLowerCase().contains('вкус') || s.toLowerCase().contains('цвет')) continue;
        if (!_isValidDishName(s)) continue;
        currentDish = s;
        break;
      }
      if (currentDish != null) break;
    }

    for (var r = headerIdx + 1; r < rows.length; r++) {
      final cells = rows[r].map((c) => c.trim()).toList();
      if (cells.isEmpty) continue;
      var pCol = productCol;
      var gCol = grossCol;
      var nCol = netCol;
      if (cells.length >= 3 && cells.length <= 8) {
        final atProduct = productCol < cells.length ? cells[productCol] : '';
        if (atProduct.isNotEmpty && RegExp(r'^[\d,.\-\s]+$').hasMatch(atProduct)) {
          pCol = 1;
          if (cells.length >= 4) { gCol = 2; nCol = 3; }
        }
      }
      final nameVal = nameCol < cells.length ? cells[nameCol] : '';
      final productVal = pCol < cells.length ? cells[pCol] : '';
      final grossVal = gCol >= 0 && gCol < cells.length ? cells[gCol] : '';
      final netVal = nCol >= 0 && nCol < cells.length ? cells[nCol] : '';
      final wasteVal = wasteCol >= 0 && wasteCol < cells.length ? cells[wasteCol] : '';
      final outputVal = outputCol >= 0 && outputCol < cells.length ? cells[outputCol] : '';

      if (nameVal.toLowerCase() == 'итого' || productVal.toLowerCase() == 'итого') {
        flushCard();
        currentDish = null;
        continue;
      }
      // CSV: при пустом Наименовании название новой карточки может быть в Продукте (ПФ ...)
      if (nameCol != pCol && nameVal.isEmpty && productVal.isNotEmpty &&
          RegExp(r'^ПФ\s|^П/Ф\s', caseSensitive: false).hasMatch(productVal) &&
          productVal.length > 5) {
        if (currentDish != null || currentIngredients.isNotEmpty) flushCard();
        if (_isValidDishName(productVal)) currentDish = productVal;
        if (gCol >= 0 && gCol + 2 < cells.length) {
          final shiftedProduct = cells[gCol].trim();
          final shiftedGross = gCol + 1 < cells.length ? cells[gCol + 1] : '';
          final shiftedNet = gCol + 3 < cells.length ? cells[gCol + 3] : (nCol < cells.length ? cells[nCol] : '');
          if (shiftedProduct.isNotEmpty && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(shiftedProduct) &&
              shiftedProduct.toLowerCase() != 'итого' &&
              (RegExp(r'\d').hasMatch(shiftedGross) || RegExp(r'\d').hasMatch(shiftedNet))) {
            final sg = _parseNum(shiftedGross);
            final sn = _parseNum(shiftedNet);
            if ((sg != null && sg > 0) || (sn != null && sn > 0)) {
              currentIngredients.add(TechCardIngredientLine(
                productName: shiftedProduct.replaceFirst(RegExp(r'^П/Ф\s*', caseSensitive: false), '').trim(),
                grossGrams: sg,
                netGrams: sn,
                outputGrams: sn,
                primaryWastePct: null,
                unit: 'g',
                ingredientType: RegExp(r'^П/Ф\s', caseSensitive: false).hasMatch(shiftedProduct) ? 'semi_finished' : 'product',
              ));
            }
          }
        }
        continue;
      }
      final rowText = cells.join(' ').toLowerCase();
      // Маркеры новой карточки — ищем в полном содержимом строки
      if (RegExp(r'ттк\s*№|карта\s*№|технол\.?\s*карта\s*№|рецепт\s*№|т\.?\s*к\.?\s*№|наименование\s+блюда', caseSensitive: false).hasMatch(rowText)) {
        if (currentDish != null || currentIngredients.isNotEmpty) flushCard();
        currentDish = null;
        final dishMatch = RegExp(r'наименование\s+блюда\s*:?\s*([^\n]+)', caseSensitive: false).firstMatch(cells.join(' '));
        final extracted = dishMatch?.group(1)?.trim();
        if (extracted != null && extracted.isNotEmpty) currentDish = extracted;
        else {
          for (final c in cells) {
            if (c.length > 2 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(c) && !RegExp(r'ттк|карта|брутто|нетто|наименование').hasMatch(c.toLowerCase())) {
              currentDish = c;
              break;
            }
          }
        }
        continue;
      }
      // Повтор заголовка Наименование|Брутто|Нетто — flush текущей, пропуск
      if (rowText.contains('брутто') && rowText.contains('нетто') &&
          (rowText.contains('наименование') || rowText.contains('продукт')) && cells.length <= 10) {
        if (currentDish != null || currentIngredients.isNotEmpty) flushCard();
        currentDish = null;
        continue;
      }
      // Новая карточка: новое блюдо в nameCol (как в parseTtkByTemplate)
      final effectiveNameCol = nameCol;
      final effectiveProductCol = pCol;
      if (effectiveNameCol != effectiveProductCol &&
          nameVal.isNotEmpty &&
          !RegExp(r'^[\d\s\.\,]+$').hasMatch(nameVal) &&
          nameVal.toLowerCase() != 'итого') {
        if (currentDish != null && currentDish != nameVal && currentIngredients.isNotEmpty) {
          flushCard();
        }
        if (_isValidDishName(nameVal)) currentDish = nameVal;
      } else if (nameVal.isNotEmpty && !RegExp(r'^[\d\s\.\,]+$').hasMatch(nameVal) && productVal.isEmpty) {
        if (currentDish != null && currentIngredients.isNotEmpty) flushCard();
        currentDish = nameVal;
      }
      if (productVal.isNotEmpty) {
        if (currentDish == null && nameVal.isNotEmpty && _isValidDishName(nameVal)) currentDish = nameVal;
        final gross = _parseNum(grossVal);
        final net = _parseNum(netVal);
        var waste = _parseNum(wasteVal);
        final output = _parseNum(outputVal);
        if (gross != null && gross > 0 && net != null && net > 0 && net < gross && (waste == null || waste == 0)) {
          waste = (1.0 - net / gross) * 100.0;
        }
        currentIngredients.add(TechCardIngredientLine(
          productName: productVal,
          grossGrams: gross,
          netGrams: net,
          outputGrams: output,
          primaryWastePct: waste,
          unit: 'g',
        ));
      }
    }
    flushCard();
    return results;
  }

  /// Парсинг по шаблонам — через Edge Function (service_role). Без лимитов, без AI.
  /// Так надёжно работает независимо от сессии; иначе на 3-й загрузке упираемся в лимит AI.
  Future<List<TechCardRecognitionResult>> _tryParseByStoredTemplates(List<List<String>> rows) async {
    try {
      final data = await invoke('parse-ttk-by-templates', {'rows': rows});
      if (data == null) return [];
      final raw = data['cards'];
      if (raw is! List || raw.isEmpty) return [];
      final list = <TechCardRecognitionResult>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final card = _parseTechCardResult(Map<String, dynamic>.from(e as Map));
        if (card != null && (card.dishName != null && card.dishName!.isNotEmpty || card.ingredients.isNotEmpty)) {
          list.add(card);
        }
      }
      return list;
    } catch (e) {
      devLog('parse-ttk-by-templates: $e');
      return [];
    }
  }

  /// Сохранить шаблон при успешном парсинге по ключевым словам (без AI). Повторная загрузка — из каталога.
  void _saveTemplateFromKeywordParse(List<List<String>> rows, String source) {
    try {
      int headerIdx = -1;
      int nameCol = -1, productCol = -1, grossCol = -1, netCol = -1, wasteCol = -1, outputCol = -1;
      const nameKeys = ['наименование', 'название', 'блюдо', 'пф', 'name', 'dish'];
      const productKeys = ['продукт', 'сырьё', 'ингредиент', 'product', 'ingredient'];
      const grossKeys = ['брутто', 'бр', 'вес брутто', 'gross'];
      const netKeys = ['нетто', 'нт', 'вес нетто', 'net'];
      const wasteKeys = ['отход', 'отх', 'waste', 'процент отхода'];
      const outputKeys = ['выход', 'вес готового', 'готовый', 'output'];
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r].map((c) => c.trim().toLowerCase()).toList();
        for (var c = 0; c < row.length; c++) {
          final cell = row[c];
          if (cell.isEmpty) continue;
          for (final k in nameKeys) {
            if (cell.contains(k)) { headerIdx = r; nameCol = c; break; }
          }
          for (final k in productKeys) {
            if (cell.contains(k)) { headerIdx = r; productCol = c; break; }
          }
          for (final k in grossKeys) {
            if (cell.contains(k)) { headerIdx = r; grossCol = c; break; }
          }
          for (final k in netKeys) {
            if (cell.contains(k)) { headerIdx = r; netCol = c; break; }
          }
          for (final k in wasteKeys) {
            if (cell.contains(k)) { headerIdx = r; wasteCol = c; break; }
          }
          for (final k in outputKeys) {
            if (cell.contains(k)) { headerIdx = r; outputCol = c; break; }
          }
        }
        if (headerIdx >= 0 && (nameCol >= 0 || productCol >= 0)) break;
      }
      if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) return;
      if (nameCol < 0) nameCol = 0;
      if (productCol < 0) productCol = 1;
      final sig = _headerSignature(rows[headerIdx].map((c) => c.trim()).toList());
      if (sig.isEmpty) return;
      _client.from('tt_parse_templates').upsert({
        'header_signature': sig,
        'header_row_index': headerIdx,
        'name_col': nameCol,
        'product_col': productCol,
        'gross_col': grossCol >= 0 ? grossCol : -1,
        'net_col': netCol >= 0 ? netCol : -1,
        'waste_col': wasteCol >= 0 ? wasteCol : -1,
        'output_col': outputCol >= 0 ? outputCol : -1,
        'source': source,
      }, onConflict: 'header_signature').then((_) {}).catchError((_) {});
    } catch (_) {}
  }

  void _saveTemplateAfterAi(List<List<String>> rows, List<TechCardRecognitionResult> cards, String source) {
    try {
      final allNames = cards.expand((c) => c.ingredients.map((i) => stripIikoPrefix(i.productName).trim().toLowerCase())).where((s) => s.length > 2).toSet().toList();
      if (allNames.isEmpty) return;
      int bestHeaderIdx = -1;
      int bestProductCol = -1;
      int bestScore = 0;

      for (var hr = 0; hr < rows.length && hr < 30; hr++) {
        if (hr + 1 >= rows.length) break;
        final headerRow = rows[hr];
        if (headerRow.length < 3) continue;
        for (var pc = 0; pc < headerRow.length; pc++) {
          var score = 0;
          for (var r = hr + 1; r < rows.length && r < hr + 100; r++) {
            final cells = rows[r].map((c) => c.trim()).toList();
            if (pc >= cells.length) continue;
            final cell = stripIikoPrefix(cells[pc]).toLowerCase();
            if (allNames.any((n) => cell.contains(n) || n.contains(cell))) score++;
          }
          if (score > bestScore) {
            bestScore = score;
            bestHeaderIdx = hr;
            bestProductCol = pc;
          }
        }
      }
      if (bestHeaderIdx < 0 || bestProductCol < 0 || bestScore < 2) return;

      int grossCol = -1;
      int netCol = -1;
      final hr = bestHeaderIdx;
      for (var c = 0; c < (rows[hr].length < 12 ? rows[hr].length : 12); c++) {
        if (c == bestProductCol) continue;
        if (hr + 1 >= rows.length) break;
        final v = rows[hr + 1].length > c ? rows[hr + 1][c].trim() : '';
        if (RegExp(r'^[\d,.\-\s]+$').hasMatch(v)) {
          if (grossCol < 0) grossCol = c;
          else if (netCol < 0) { netCol = c; break; }
        }
      }

      final sig = _headerSignature(rows[bestHeaderIdx].map((c) => c.trim()).toList());
      if (sig.isEmpty) return;

      _client.from('tt_parse_templates').upsert({
        'header_signature': sig,
        'header_row_index': bestHeaderIdx,
        'name_col': bestProductCol,
        'product_col': bestProductCol,
        'gross_col': grossCol,
        'net_col': netCol,
        'waste_col': -1,
        'output_col': -1,
        'source': source,
      }, onConflict: 'header_signature').then((_) {}).catchError((_) {});
    } catch (_) {}
  }

  TechCardRecognitionResult? _parseTechCardResult(Map<String, dynamic>? data) {
    if (data == null) return null;
    final ingredients = <TechCardIngredientLine>[];
    final raw = data['ingredients'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e as Map);
        final it = (m['ingredientType'] as String?)?.toLowerCase();
        ingredients.add(TechCardIngredientLine(
          productName: (m['productName'] as String?) ?? '',
          grossGrams: m['grossGrams'] != null ? (m['grossGrams'] as num).toDouble() : null,
          netGrams: m['netGrams'] != null ? (m['netGrams'] as num).toDouble() : null,
          outputGrams: m['outputGrams'] != null ? (m['outputGrams'] as num).toDouble() : null,
          unit: m['unit'] as String?,
          cookingMethod: m['cookingMethod'] as String?,
          primaryWastePct: m['primaryWastePct'] != null ? (m['primaryWastePct'] as num).toDouble() : null,
          cookingLossPct: m['cookingLossPct'] != null ? (m['cookingLossPct'] as num).toDouble() : null,
          ingredientType: (it == 'product' || it == 'semi_finished') ? it : null,
          pricePerKg: m['pricePerKg'] != null ? (m['pricePerKg'] as num).toDouble() : null,
        ));
      }
    }
    return TechCardRecognitionResult(
      dishName: data['dishName'] as String?,
      technologyText: data['technologyText'] as String?,
      ingredients: ingredients,
      isSemiFinished: data['isSemiFinished'] as bool?,
    );
  }

  @override
  Future<ProductRecognitionResult?> recognizeProduct(String userInput) async {
    final data = await invoke('ai-recognize-product', {'userInput': userInput});
    if (data == null) return null;
    return ProductRecognitionResult(
      normalizedName: (data['normalizedName'] as String?) ?? userInput,
      suggestedCategory: data['suggestedCategory'] as String?,
      suggestedUnit: data['suggestedUnit'] as String?,
      suggestedWastePct: data['suggestedWastePct'] != null ? (data['suggestedWastePct'] as num).toDouble() : null,
    );
  }

  @override
  Future<ProductVerificationResult?> verifyProduct(
    String productName, {
    double? currentPrice,
    NutritionResult? currentNutrition,
  }) async {
    final body = <String, dynamic>{
      'productName': productName,
    };
    if (currentPrice != null) body['currentPrice'] = currentPrice;
    if (currentNutrition != null) {
      body['currentCalories'] = currentNutrition.calories;
      body['currentProtein'] = currentNutrition.protein;
      body['currentFat'] = currentNutrition.fat;
      body['currentCarbs'] = currentNutrition.carbs;
    }
    final data = await invoke('ai-verify-product', body);
    if (data == null) return null;
    return ProductVerificationResult(
      normalizedName: data['normalizedName'] as String?,
      suggestedCategory: data['suggestedCategory'] as String?,
      suggestedUnit: data['suggestedUnit'] as String?,
      suggestedPrice: data['suggestedPrice'] != null ? (data['suggestedPrice'] as num).toDouble() : null,
      suggestedCalories: data['suggestedCalories'] != null ? (data['suggestedCalories'] as num).toDouble() : null,
      suggestedProtein: data['suggestedProtein'] != null ? (data['suggestedProtein'] as num).toDouble() : null,
      suggestedFat: data['suggestedFat'] != null ? (data['suggestedFat'] as num).toDouble() : null,
      suggestedCarbs: data['suggestedCarbs'] != null ? (data['suggestedCarbs'] as num).toDouble() : null,
    );
  }

  @override
  Future<NutritionResult?> refineOrGetNutrition(String productName, NutritionResult? existing) async {
    final nameForSearch = stripIikoPrefix(productName).trim();
    final body = <String, dynamic>{'productName': nameForSearch.isEmpty ? productName : nameForSearch};
    if (existing != null) {
      body['existing'] = {
        'calories': existing.calories,
        'protein': existing.protein,
        'fat': existing.fat,
        'carbs': existing.carbs,
      };
    }
    final data = await invoke('ai-refine-nutrition', body);
    if (data == null) return null;
    return NutritionResult(
      calories: data['calories'] != null ? (data['calories'] as num).toDouble() : null,
      protein: data['protein'] != null ? (data['protein'] as num).toDouble() : null,
      fat: data['fat'] != null ? (data['fat'] as num).toDouble() : null,
      carbs: data['carbs'] != null ? (data['carbs'] as num).toDouble() : null,
    );
  }
}

