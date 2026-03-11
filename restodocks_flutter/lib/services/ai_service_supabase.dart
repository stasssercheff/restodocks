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

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromExcel(Uint8List xlsxBytes, {String? establishmentId}) async {
    try {
      var rows = _xlsxToRows(xlsxBytes);
      if (rows.isEmpty) rows = _csvToRows(xlsxBytes);
      if (rows.isEmpty) rows = _docxToRows(xlsxBytes);
      if (rows.isEmpty) return [];
      // 1. Сначала парсим по шаблону (без ИИ) — лимит не применяется
      var list = AiServiceSupabase.parseTtkByTemplate(rows);
      // 2. Только если шаблон не сработал — вызываем AI (лимит 3/день)
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
      if (list.isNotEmpty) lastParseTechCardPdfReason = null;
      return list;
    } catch (e) {
      lastParseTechCardPdfReason = 'catch: $e';
      return [];
    }
  }

  List<List<String>> _csvToRows(Uint8List bytes) {
    try {
      var s = utf8.decode(bytes);
      if (s.contains('\r')) s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final decoded = CsvToListConverter(eol: '\n').convert(s);
      final rows = <List<String>>[];
      for (final row in decoded) {
        if (row is! List) continue;
        final strRow = row.map((c) => c?.toString().trim() ?? '').toList();
        if (strRow.any((c) => c.isNotEmpty)) rows.add(strRow);
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  List<List<String>> _docxToRows(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = archive.findFile('word/document.xml');
      if (doc == null) return [];
      final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
      // 1. Сначала пробуем таблицу w:tbl — сохраняем структуру строк (Наименование, Продукт, Брутто...)
      final tables = xml.descendants.whereType<XmlElement>().where((e) => e.localName == 'tbl');
      for (final tbl in tables) {
        final tableRows = <List<String>>[];
        for (final tr in tbl.children.whereType<XmlElement>().where((e) => e.localName == 'tr')) {
          final cells = <String>[];
          for (final tc in tr.children.whereType<XmlElement>().where((e) => e.localName == 'tc')) {
            final texts = tc.descendants.whereType<XmlElement>().where((e) => e.localName == 't').map((e) => e.innerText).toList();
            cells.add(texts.join('').trim());
          }
          if (cells.any((c) => c.isNotEmpty)) {
            tableRows.add(cells);
          }
        }
        if (tableRows.length >= 2) return tableRows;
      }
      // 2. Fallback: параграфы (документ без таблицы)
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

  /// Парсинг ТТК по шаблону (Наименование, Продукт, Брутто, Нетто...) — без вызова ИИ.
  /// [testFromRows] — для тестов: передать готовые rows, минуя парсинг файла.
  static List<TechCardRecognitionResult> parseTtkByTemplate(List<List<String>> rows) {
    if (rows.length < 2) return [];
    rows = _expandSingleCellRows(rows);
    if (rows.length < 2) return [];
    final results = <TechCardRecognitionResult>[];
    int headerIdx = -1;
    int nameCol = -1, productCol = -1, grossCol = -1, netCol = -1, wasteCol = -1;

    final nameKeys = ['наименование', 'название', 'блюдо', 'пф', 'name', 'dish'];
    final productKeys = ['продукт', 'сырьё', 'ингредиент', 'product', 'ingredient'];
    final grossKeys = ['брутто', 'бр', 'вес брутто', 'gross'];
    final netKeys = ['нетто', 'нт', 'вес нетто', 'net'];
    final wasteKeys = ['отход', 'отх', 'waste', 'процент отхода'];

    // Поиск строки с колонками (Наименование продукта, Брутто, Нетто) — может быть далеко от верха
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r].map((c) => c.trim().toLowerCase()).toList();
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell.isEmpty) continue;
        for (final k in nameKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            nameCol = c;
            break;
          }
        }
        for (final k in productKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            productCol = c;
            break;
          }
        }
        for (final k in grossKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            grossCol = c;
            break;
          }
        }
        for (final k in netKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            netCol = c;
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
      }
      if (headerIdx >= 0 && (nameCol >= 0 || productCol >= 0)) break;
    }
    if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) return [];

    if (nameCol < 0) nameCol = 0;
    if (productCol < 0) productCol = 1;

    // Название блюда может быть в строках выше заголовка (DOCX iiko/ГОСТ)
    String? currentDish;
    for (var r = 0; r < headerIdx && r < rows.length; r++) {
      for (final c in rows[r]) {
        final s = c.trim();
        if (s.length < 3) continue;
        if (s.endsWith(':')) continue; // "Хранение:", "Область применения:"
        if (RegExp(r'^\d{1,2}\.\d{1,2}\.\d{2,4}').hasMatch(s)) continue; // дата
        if (s.toLowerCase().startsWith('технологическая карта')) continue;
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

      if (nameVal.toLowerCase() == 'итого' || productVal.toLowerCase() == 'итого') {
        flushCard();
        currentDish = null;
        continue;
      }
      // Строка с названием блюда (начало новой карточки)
      if (nameVal.isNotEmpty && !RegExp(r'^[\d\s\.\,]+$').hasMatch(nameVal) && productVal.isEmpty) {
        if (currentDish != null && currentIngredients.isNotEmpty) flushCard();
        currentDish = nameVal;
      }
      // Строка с продуктом (ингредиент)
      if (productVal.isNotEmpty) {
        if (currentDish == null && nameVal.isNotEmpty) currentDish = nameVal;
        final gross = _parseNum(grossVal);
        final net = _parseNum(netVal);
        final waste = _parseNum(wasteVal);
        currentIngredients.add(TechCardIngredientLine(
          productName: productVal,
          grossGrams: gross,
          netGrams: net,
          primaryWastePct: waste,
          unit: 'g',
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
          unit: m['unit'] as String?,
          cookingMethod: m['cookingMethod'] as String?,
          primaryWastePct: m['primaryWastePct'] != null ? (m['primaryWastePct'] as num).toDouble() : null,
          cookingLossPct: m['cookingLossPct'] != null ? (m['cookingLossPct'] as num).toDouble() : null,
          ingredientType: (it == 'product' || it == 'semi_finished') ? it : null,
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

