import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import 'ai_service.dart';
import 'nutrition_api_service.dart';
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
      if (rows.length < 2) return [];
      // DOCX: если много таблиц — парсим каждую; если одна и не парсится — пробуем все по очереди
      if (docxTables != null && docxTables.isNotEmpty) {
        final merged = <TechCardRecognitionResult>[];
        for (final tbl in docxTables) {
          var expanded = _expandSingleCellRows(tbl);
          if (expanded.length < 2) continue;
          var part = AiServiceSupabase.parseTtkByTemplate(expanded);
          if (part.isEmpty) part = AiServiceSupabase._tryParseKkFromRows(expanded);
          merged.addAll(part);
        }
        if (merged.isNotEmpty) {
          _saveTemplateFromKeywordParse(rows, 'docx');
          return merged;
        }
      }
      // Сначала шаблон ТТК (Брутто/Нетто, разбивка по Итого) — для CSV/Excel с несколькими карточками.
      // КК (норма/цена) — для простых калькуляционных карт без разбивки.
      var list = AiServiceSupabase.parseTtkByTemplate(rows);
      if (list.isEmpty) list = AiServiceSupabase._tryParseKkFromRows(rows);
      if (list.isNotEmpty) _saveTemplateFromKeywordParse(rows, 'excel'); // Обучение: повторная загрузка — без AI
      // 2. Если шаблон не сработал — пробуем сохранённые шаблоны (каталог)
      if (list.isEmpty) list = await _tryParseByStoredTemplates(rows);
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
      return list;
    } catch (e) {
      lastParseTechCardPdfReason = 'catch: $e';
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

  /// Все таблицы DOCX (для файлов с несколькими ТТК).
  List<List<List<String>>> _docxToAllTables(Uint8List bytes) {
    final result = <List<List<String>>>[];
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = archive.findFile('word/document.xml');
      if (doc == null) return result;
      final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
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
        if (tableRows.length >= 2) result.add(tableRows);
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

  List<List<String>> _xlsxToRows(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes.toList());
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

  /// Парсинг ТТК по шаблону (Наименование, Продукт, Брутто, Нетто...) — без вызова ИИ.
  /// [testFromRows] — для тестов: передать готовые rows, минуя парсинг файла.
  static List<TechCardRecognitionResult> parseTtkByTemplate(List<List<String>> rows) {
    if (rows.length < 2) return [];
    rows = _expandSingleCellRows(rows);
    if (rows.length < 2) return [];
    final results = <TechCardRecognitionResult>[];
    int headerIdx = -1;
    int nameCol = -1, productCol = -1, grossCol = -1, netCol = -1, wasteCol = -1, outputCol = -1;

    final nameKeys = ['наименование', 'название', 'блюдо', 'пф', 'набор', 'name', 'dish'];
    final productKeys = ['продукт', 'продукты', 'сырьё', 'сырья', 'ингредиент', 'product', 'ingredient'];
    final grossKeys = ['брутто', 'бр', 'вес брутто', 'расход', 'норма', 'масса', 'gross'];
    final netKeys = ['нетто', 'нт', 'вес нетто', 'net'];
    final wasteKeys = ['отход', 'отх', 'waste', 'процент отхода'];
    final outputKeys = ['выход', 'вес готового', 'вес готового продукта', 'готовый', 'output'];
    final unitKeys = ['ед. изм', 'ед изм', 'единица', 'unit'];

    int unitCol = -1;
    bool grossColIsKg = false;
    bool netColIsKg = false;

    // Поиск колонок (Наименование, Брутто, Нетто) — заголовок может быть в 2 строках (ГОСТ)
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
        if (row.length < 3) continue;
        final c0 = row[0].trim().toLowerCase();
        final c1 = row.length > 1 ? row[1].trim() : '';
        if ((c0 == '№' || c0 == 'n' || RegExp(r'^\d+$').hasMatch(c0)) && c1.length >= 2 && !RegExp(r'^[\d,.\s]+$').hasMatch(c1)) {
          headerIdx = r;
          nameCol = 1;
          productCol = 1;
          for (var c = 2; c < row.length && c < 12; c++) {
            final h = row[c].trim().toLowerCase();
            if (h.contains('брутто') && (grossCol < 0 || h.contains('кг'))) grossCol = c;
            if (h.contains('нетто') && (netCol < 0 || h.contains('кг'))) netCol = c;
          }
          if (grossCol < 0 && row.length >= 4) grossCol = 2;
          if (netCol < 0 && row.length >= 5) netCol = 3;
          if (row.length >= 6) outputCol = 5;
          break;
        }
      }
    }
    if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) return [];

    if (nameCol < 0) nameCol = 0;
    if (productCol < 0) productCol = 1;

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

    for (var r = headerIdx + 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;
      final cells = row.map((c) => c.trim()).toList();
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

      if (nameVal.toLowerCase() == 'итого' || productVal.toLowerCase() == 'итого' || productVal.toLowerCase().startsWith('всего')) {
        flushCard();
        currentDish = null;
        continue;
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
        currentDish = nameVal;
      }
      if (productVal.toLowerCase().contains('выход блюда') || productVal.toLowerCase().startsWith('выход одного')) continue;
      // Пропускаем, если productVal — только цифры/пробелы (ошибочная колонка)
      if (RegExp(r'^[\d\s\.\,\-\+]+$').hasMatch(productVal)) continue;
      // Строка с продуктом (ингредиент)
      if (productVal.isNotEmpty) {
        if (currentDish == null && nameVal.isNotEmpty) currentDish = nameVal;
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
        currentIngredients.add(TechCardIngredientLine(
          productName: cleanName,
          grossGrams: gross,
          netGrams: net,
          outputGrams: outputG,
          primaryWastePct: waste,
          unit: unit,
          ingredientType: isPf ? 'semi_finished' : 'product',
        ));
      }
    }
    flushCard();
    return results;
  }

  static double? _parseNum(String s) {
    if (s.isEmpty) return null;
    final n = double.tryParse(s.replaceAll(',', '.').replaceAll(RegExp(r'[^\d\.\-]'), ''));
    return n;
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
        currentDish = nameVal;
      } else if (nameVal.isNotEmpty && !RegExp(r'^[\d\s\.\,]+$').hasMatch(nameVal) && productVal.isEmpty) {
        if (currentDish != null && currentIngredients.isNotEmpty) flushCard();
        currentDish = nameVal;
      }
      if (productVal.isNotEmpty) {
        if (currentDish == null && nameVal.isNotEmpty) currentDish = nameVal;
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

  Future<List<TechCardRecognitionResult>> _tryParseByStoredTemplates(List<List<String>> rows) async {
    try {
      final keywords = ['наименование', 'продукт', 'брутто', 'нетто', 'название', 'сырьё', 'ингредиент'];
      for (var r = 0; r < rows.length && r < 50; r++) {
        final row = rows[r].map((c) => c.trim().toLowerCase()).toList();
        if (row.length < 3) continue;
        final hasKeyword = row.any((c) => keywords.any((k) => c.contains(k)));
        if (!hasKeyword) continue;
        final sig = _headerSignature(rows[r].map((c) => c.trim()).toList());
        if (sig.isEmpty) continue;
        final res = await _client.from('tt_parse_templates').select().eq('header_signature', sig).limit(1).maybeSingle();
        if (res == null) continue;
        final data = res as Map<String, dynamic>;
        final list = parseTtkByStoredTemplate(
          rows,
          headerIdx: r,
          nameCol: (data['name_col'] as num?)?.toInt() ?? 0,
          productCol: (data['product_col'] as num?)?.toInt() ?? 1,
          grossCol: (data['gross_col'] as num?)?.toInt() ?? -1,
          netCol: (data['net_col'] as num?)?.toInt() ?? -1,
          wasteCol: (data['waste_col'] as num?)?.toInt() ?? -1,
          outputCol: (data['output_col'] as num?)?.toInt() ?? -1,
        );
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return [];
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

