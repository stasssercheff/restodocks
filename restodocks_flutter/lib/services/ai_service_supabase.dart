import 'dart:async' show unawaited, TimeoutException;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
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

  /// header_signature последнего успешного парсинга (для записи правок пользователя).
  static String? lastParseHeaderSignature;

  /// Строки последнего парсинга (для обучения: ищем corrected в них и сохраняем позицию).
  static List<List<String>>? lastParsedRows;

  /// true, если карточки получены не по сохранённому шаблону (первая загрузка формата) — показать предупреждение.
  static bool lastParseWasFirstTimeFormat = false;

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
  /// При 5xx на последней попытке возвращает res.data (если Map) — для извлечения error/details.
  Future<Map<String, dynamic>?> invoke(String name, Map<String, dynamic> body) async {
    const maxRetries = 3;
    const delays = [500, 1000];
    Object? lastError;
    Map<String, dynamic>? lastErrorBody;
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
        if (res.data is Map<String, dynamic>) lastErrorBody = res.data as Map<String, dynamic>;
      } catch (e) {
        lastError = e;
      }
    }
    return lastErrorBody; // чтобы _saveLearningViaEdgeFunction мог извлечь error/details
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
  Future<List<TechCardRecognitionResult>> parseTechCardsFromExcel(Uint8List xlsxBytes, {String? establishmentId, int? sheetIndex}) async {
    lastParseHeaderSignature = null;
    lastParsedRows = null;
    lastParseWasFirstTimeFormat = true; // сбросится в false, если сработает шаблон
    try {
      final fmt = _detectFormat(xlsxBytes);
      var rows = <List<String>>[];
      String source = 'excel';
      List<List<List<String>>>? docxTables;

      if (fmt == 'xlsx' && sheetIndex != null) {
        rows = _xlsxToSheetRowsByIndex(xlsxBytes, sheetIndex);
        if (rows.isNotEmpty) source = 'xlsx';
      } else if (fmt == 'docx') {
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
        if (allSheets.isNotEmpty && sheetIndex == null) {
          final merged = <TechCardRecognitionResult>[];
          final kbzuPattern = RegExp(r'белки|жиры|углеводы|калори|бжу|кбжу|жирн|белк', caseSensitive: false);
          for (final sheetRows in allSheets) {
            var expanded = _expandSingleCellRows(sheetRows);
            if (expanded.length < 2) continue;
            final firstRows = expanded.take(3).expand((r) => r).map((c) => c.toLowerCase()).join(' ');
            if (kbzuPattern.hasMatch(firstRows) && expanded.length <= 6 && !firstRows.contains('брутто') && !firstRows.contains('нетто')) continue;
            // пф хц/пф гц: много блоков [название][заголовок][данные][Выход] — парсим Dart-парсером, иначе EF может вернуть одну карточку со всеми строками
            var part = AiServiceSupabase._tryParsePfGcFormat(expanded);
            if (part.length < 2) {
              part = await _tryParseByStoredTemplates(expanded);
              if (part.isEmpty) {
                final excelErrors = <TtkParseError>[];
                part = AiServiceSupabase.parseTtkByTemplate(expanded, errors: excelErrors);
                if (part.isEmpty) part = AiServiceSupabase._tryParseKkFromRows(expanded);
              }
            }
            final multiBlock = AiServiceSupabase._tryParseMultiColumnBlocks(expanded);
            if (_shouldPreferMultiBlock(part, multiBlock)) part = multiBlock;
            merged.addAll(part);
          }
          if (merged.isNotEmpty) {
            await _saveTemplateFromKeywordParse(allSheets.first, 'xlsx');
            lastParsedRows = allSheets.first;
            if (lastParseHeaderSignature == null || lastParseHeaderSignature!.isEmpty) {
              lastParseHeaderSignature = _headerSignatureFromRows(allSheets.first);
            }
            return _applyParseCorrections(merged, lastParseHeaderSignature, establishmentId);
          }
        }
        rows = _xlsxToRows(xlsxBytes);
        // Специальный формат «Полное пособие Кухня» / супы.xlsx:
        // один лист, блоки [Название] [№|Наименование продукта|Вес гр/шт] [ингредиенты] [Выход] + технология текстом.
        // Для него надёжнее всего работает Dart-парсер _tryParsePolnoePosobieFormat, который умеет вытаскивать технологию.
        if (rows.isNotEmpty) {
          final polnoe = _tryParsePolnoePosobieFormat(rows);
          if (polnoe.isNotEmpty) {
            lastParsedRows = rows;
            if (lastParseHeaderSignature == null || lastParseHeaderSignature!.isEmpty) {
              lastParseHeaderSignature = _headerSignatureFromRows(rows) ??
                  (rows.isNotEmpty && rows[0].isNotEmpty ? _headerSignature(rows[0].map((c) => c.toString().trim()).toList()) : null);
            }
            return _applyParseCorrections(polnoe, lastParseHeaderSignature, establishmentId);
          }
        }
      }
      if (rows.isEmpty) rows = _csvToRows(xlsxBytes);
      // CSV-формат "Наименование,Продукт,Брутто,...,Технология" (как в ттк.csv)
      if (rows.isNotEmpty) {
        final csvWithTech = AiServiceSupabase._tryParseCsvWithTechnologyColumn(rows);
        if (csvWithTech.isNotEmpty) {
          lastParsedRows = rows;
          lastParseHeaderSignature = _headerSignatureFromRows(rows) ??
              (rows.isNotEmpty && rows[0].isNotEmpty
                  ? _headerSignature(rows[0].map((c) => c.toString().trim()).toList())
                  : null);
          return _applyParseCorrections(csvWithTech, lastParseHeaderSignature, establishmentId);
        }
      }
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
          expanded = _normalizeRowLengths(expanded);
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
          await _saveTemplateFromKeywordParse(rows, 'docx');
          // ГОСТ DOCX: извлечь технологию из раздела «4. ТЕХНОЛОГИЧЕСКИЙ ПРОЦЕСС» и подставить во все карточки, где её ещё нет
          final docxTech = _docxExtractTechnology(xlsxBytes);
          if (docxTech != null && docxTech.length >= 20) {
            for (var i = 0; i < merged.length; i++) {
              final c = merged[i];
              final hasTech = (c.technologyText ?? '').trim().length >= 20;
              if (!hasTech) merged[i] = c.copyWith(technologyText: docxTech);
            }
          }
          lastParsedRows = docxTables!.expand((t) => t).toList();
          if (lastParseHeaderSignature == null || lastParseHeaderSignature!.isEmpty) {
            lastParseHeaderSignature = _headerSignatureFromRows(rows);
          }
          final yieldFromRows = _extractYieldFromRows(lastParsedRows!);
          if (yieldFromRows != null && yieldFromRows > 0) {
            for (var i = 0; i < merged.length; i++) {
              final c = merged[i];
              if (c.yieldGrams == null || c.yieldGrams! <= 0) merged[i] = c.copyWith(yieldGrams: yieldFromRows);
            }
          }
          return _applyParseCorrections(merged, lastParseHeaderSignature, establishmentId);
        }
      }
      // Для одного листа (xls/csv): если Dart-парсер дал карточки с составом — предпочитаем его (шаблон мог дать только название).
      lastParseTechCardErrors = null;
      final excelErrors = <TtkParseError>[];
      final listByTemplate = AiServiceSupabase.parseTtkByTemplate(rows, errors: excelErrors);
      if (excelErrors.isNotEmpty) lastParseTechCardErrors = excelErrors;
      final listByStored = await _tryParseByStoredTemplates(rows);
      final hasTemplateWithIngredients = listByTemplate.isNotEmpty && listByTemplate.any((c) => c.ingredients.isNotEmpty);
      var list = (hasTemplateWithIngredients || listByStored.isEmpty) ? listByTemplate : listByStored;
      if (list.isEmpty) {
        list = AiServiceSupabase._tryParseKkFromRows(rows);
        final multiBlock = AiServiceSupabase._tryParseMultiColumnBlocks(rows);
        if (_shouldPreferMultiBlock(list, multiBlock)) list = multiBlock;
      }
      // 2b. iiko/1С (печенная свекла.xls): если 0 карточек — пробуем извлечь название из первых строк и парсить по iiko-заголовку
      if (list.isEmpty && rows.length >= 4) {
        String? extractedDish;
        for (var r = 0; r < rows.length && r < 15; r++) {
          for (final cell in rows[r]) {
            final s = (cell is String ? cell : cell?.toString() ?? '').trim();
            if (s.length >= 10 && s.length <= 120 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(s) &&
                !RegExp(r'^(№|наименование|брутто|нетто|технология|органолептическ|хранение|область)', caseSensitive: false).hasMatch(s) &&
                !s.toLowerCase().contains('название на чеке')) {
              extractedDish = s;
              break;
            }
          }
          if (extractedDish != null) break;
        }
        if (extractedDish != null) {
          final iiko = AiServiceSupabase._tryParseIikoStyleFallback(rows, extractedDish);
          if (iiko.isNotEmpty && iiko.first.ingredients.isNotEmpty) list = iiko;
        }
      }
      // 3. Только если и там пусто — вызываем AI (лимит 3/день)
      if (list.isEmpty) {
        lastParseTechCardExcelReason = null;
        final body = <String, dynamic>{'rows': _rowsForJson(rows)};
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
          await _saveTemplateAfterAi(rows, list, source);
        }
      }
      if (list.isNotEmpty) {
        lastParseTechCardExcelReason = null;
        lastParsedRows = rows;
        if (lastParseHeaderSignature == null || lastParseHeaderSignature!.isEmpty) {
          lastParseHeaderSignature = _headerSignatureFromRows(rows) ??
              (rows.isNotEmpty && rows[0].isNotEmpty ? _headerSignature(rows[0].map((c) => c.toString().trim()).toList()) : null);
        }
        // Обучение: сохранить шаблон при первом успешном парсинге нового формата (keyword), чтобы база шаблонов росла
        if (list == listByTemplate && listByTemplate.isNotEmpty) {
          await _saveTemplateFromKeywordParse(rows, source);
        }
        final yieldFromRows = _extractYieldFromRows(rows);
        if (yieldFromRows != null && yieldFromRows > 0) {
          list = list.map((c) => c.yieldGrams == null || c.yieldGrams! <= 0 ? c.copyWith(yieldGrams: yieldFromRows) : c).toList();
        }
      }
      // Постобработка технологии: для форматов типа «Полное пособие» пытаемся
      // дополнительно подтянуть технологию только из соответствующих колонок,
      // не трогая ингредиенты и выход.
      if (rows.isNotEmpty) {
        list = _mergeTechnologyFromPolnoePosobie(rows, list);
      }
      final corrected = await _applyParseCorrections(list, lastParseHeaderSignature, establishmentId);
      final validationErrors = _validateParsedCards(corrected);
      if (validationErrors != null) {
        final existing = lastParseTechCardErrors ?? [];
        lastParseTechCardErrors = [...existing, ...validationErrors];
      }
      return corrected;
    } catch (_) {
      lastParseTechCardExcelReason = null;
      return [];
    }
  }

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromText(String text, {String? establishmentId}) async {
    lastParseTechCardExcelReason = null;
    lastParseTechCardErrors = null;
    lastParsedRows = null;
    lastParseHeaderSignature = null;
    lastParseWasFirstTimeFormat = true;
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
    if (list.isNotEmpty) {
      await _saveTemplateFromKeywordParse(expanded, 'text');
      lastParsedRows = expanded;
      if (lastParseHeaderSignature == null || lastParseHeaderSignature!.isEmpty) {
        lastParseHeaderSignature = _headerSignatureFromRows(expanded);
      }
      return _applyParseCorrections(list, lastParseHeaderSignature, establishmentId);
    }
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

  /// Таймаут парсинга PDF (извлечение текста + шаблон/AI). Supabase EF ~60s, плюс cold start.
  static const _pdfParseTimeout = Duration(seconds: 90);

  /// Заглушка для совместимости с tech_cards_list_screen (прогрев PDF EF добавлен позже eb9659f).
  void warmPdfParser() {}

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromPdf(Uint8List pdfBytes, {String? establishmentId}) async {
    lastParseTechCardPdfReason = null;
    try {
      final body = <String, dynamic>{'pdfBase64': base64Encode(pdfBytes)};
      if (establishmentId != null && establishmentId.isNotEmpty) body['establishmentId'] = establishmentId;
      var data = await invoke('ai-parse-tech-cards-pdf', body)
          .timeout(_pdfParseTimeout, onTimeout: () => null);
      for (var retry = 0; data == null && retry < 2; retry++) {
        await Future<void>.delayed(Duration(milliseconds: retry == 0 ? 1500 : 3000));
        data = await invoke('ai-parse-tech-cards-pdf', body)
            .timeout(_pdfParseTimeout, onTimeout: () => null);
      }
      if (data == null) {
        lastParseTechCardPdfReason = 'timeout_or_network';
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
      // Обучение и метаданные для дообучения: rows приходят при template/stored/AI
      if (list.isNotEmpty) {
        lastParseTechCardPdfReason = null;
        final rowsRaw = data['rows'];
        String? sig;
        if (rowsRaw is List && rowsRaw.isNotEmpty) {
          final rows = rowsRaw.map((r) => (r is List ? r : <String>[]).map((c) => c?.toString() ?? '').toList()).toList();
          if (rows.length >= 2) {
            await _saveTemplateAfterAi(rows, list, 'pdf');
            lastParsedRows = rows;
            sig = _headerSignatureFromRows(rows);
            if (sig != null && sig.isNotEmpty) lastParseHeaderSignature = sig;
          }
        } else {
          lastParsedRows = null;
          lastParseHeaderSignature = null;
        }
        return await _applyParseCorrections(list, sig ?? lastParseHeaderSignature, establishmentId);
      }
      lastParsedRows = null;
      lastParseHeaderSignature = null;
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
      final firstLine = s.split('\n').first.trim().toLowerCase();
      // Формат «Наименование,Продукт,Брутто» (ПФ-ПФ.csv) — строго запятая и кавычки для полей с переносами
      final preferComma = firstLine.contains(',') && firstLine.contains('наименование') && firstLine.contains('продукт');
      List<List<dynamic>> best;
      if (preferComma) {
        best = CsvToListConverter(fieldDelimiter: ',', eol: '\n', textDelimiter: '"').convert(s);
      } else {
        best = CsvToListConverter(eol: '\n').convert(s);
        if (best.isNotEmpty) {
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
        }
      }
      if (best.isEmpty) return [];
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

  /// Из DOCX извлекает текст раздела «4. ТЕХНОЛОГИЧЕСКИЙ ПРОЦЕСС» до «5. ТРЕБОВАНИЯ» или «6. ПОКАЗАТЕЛИ».
  String? _docxExtractTechnology(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = archive.findFile('word/document.xml');
      if (doc == null) return null;
      final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
      final paras = xml.descendants.whereType<XmlElement>().where((e) => e.localName == 'p');
      final startMark = RegExp(r'^\d*\.?\s*технологический\s+процесс', caseSensitive: false);
      final stopMark = RegExp(r'^\d+\.\s*(требования|показатели|пищевая|органолептическ)', caseSensitive: false);
      final lines = <String>[];
      var found = false;
      for (final p in paras) {
        final texts = p.descendants.whereType<XmlElement>().where((e) => e.localName == 't').map((e) => e.innerText).toList();
        final line = texts.join('').trim();
        if (line.isEmpty) continue;
        if (startMark.hasMatch(line)) {
          found = true;
          continue;
        }
        if (found) {
          if (stopMark.hasMatch(line)) break;
          lines.add(line);
        }
      }
      if (lines.isEmpty) return null;
      return lines.join('\n').trim();
    } catch (_) {}
    return null;
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
    return _xlsxToSheetRowsByIndex(bytes, 0);
  }

  /// Строки одного листа xlsx по индексу (0-based). Для выбора листа пользователем.
  List<List<String>> _xlsxToSheetRowsByIndex(Uint8List bytes, int sheetIndex) {
    try {
      final decodable = IikoXlsxSanitizer.ensureDecodable(bytes);
      final excel = Excel.decodeBytes(decodable.toList());
      final names = excel.tables.keys.toList();
      if (sheetIndex < 0 || sheetIndex >= names.length) return [];
      final sheetName = names[sheetIndex];
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
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// Имена листов xlsx (для диалога выбора). Только для .xlsx; для .xls возвращает пустой список.
  static Future<List<String>> getExcelSheetNames(Uint8List bytes) async {
    if (bytes.length < 4) return [];
    if (bytes[0] != 0x50 || bytes[1] != 0x4B) return []; // not zip/xlsx
    try {
      final decodable = IikoXlsxSanitizer.ensureDecodable(bytes);
      final excel = Excel.decodeBytes(decodable.toList());
      return excel.tables.keys.toList();
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

  /// Дополнительно подтянуть технологию из формата «Полное пособие»,
  /// не трогая ингредиенты и выход. Работает поверх уже распарсенных карточек.
  static List<TechCardRecognitionResult> _mergeTechnologyFromPolnoePosobie(
    List<List<String>> rows,
    List<TechCardRecognitionResult> cards,
  ) {
    if (rows.isEmpty || cards.isEmpty) return cards;
    final parsed = _tryParsePolnoePosobieFormat(rows);
    if (parsed.isEmpty) return cards;

    String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    final techByName = <String, String>{};
    for (final c in parsed) {
      final name = (c.dishName ?? '').trim();
      final tech = (c.technologyText ?? '').trim();
      if (name.isEmpty || tech.length < 20) continue;
      final key = _norm(name);
      // Не перезаписываем, если уже есть технология для этого названия
      techByName.putIfAbsent(key, () => tech);
    }
    if (techByName.isEmpty) return cards;

    return cards.map((c) {
      final existingTech = (c.technologyText ?? '').trim();
      final name = (c.dishName ?? '').trim();
      if (name.isEmpty) return c;
      final key = _norm(name);
      final tech = techByName[key];
      if (tech == null) return c;
      // Не трогаем карточки, где уже есть внятная технология
      if (existingTech.length >= 20) return c;
      return c.copyWith(technologyText: tech);
    }).toList();
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
      final next0 = nextRow.isNotEmpty ? nextRow[0].trim().toLowerCase() : '';
      final next1 = nextRow.length > 1 ? nextRow[1].toLowerCase() : '';
      final headerOk = (next0 == '№' || next0.isEmpty) && next1.contains('наименование') && next1.contains('продукт');
      if (!headerOk) {
        r++;
        continue;
      }
      final dishName = cells.isNotEmpty ? cells[0].trim() : '';
      final c1 = cells.length > 1 ? cells[1].trim() : '';
      final col1LooksLikeWeight = c1.isNotEmpty && (_parseNum(c1) != null || RegExp(r'^\d+\s*шт\.?$', caseSensitive: false).hasMatch(c1.toLowerCase()));
      if (dishName.length < 3 || !RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(dishName) ||
          RegExp(r'^№$|^выход$|^декор$', caseSensitive: false).hasMatch(dishName) ||
          dishName.toLowerCase().startsWith('доставка') ||
          col1LooksLikeWeight /* строка ингредиента (название | вес), не заголовок блюда */) {
        r++;
        continue;
      }
      final ingredients = <TechCardIngredientLine>[];
      String? technologyText;
      double? yieldGrams;
      var dataRow = r + 2;
      while (dataRow < rows.length) {
        final dr = rows[dataRow].map((c) => (c ?? '').toString().trim()).toList();
        if (dr.every((c) => c.isEmpty)) { dataRow++; continue; }
        final d0 = dr.isNotEmpty ? dr[0].toLowerCase() : '';
        if (d0 == 'выход') {
          // Извлечь значение выхода (400, 420/70 → 420, 600/100/20 → 600) для веса порции
          for (var i = 1; i < dr.length && i < 5; i++) {
            final v = _parseNum(dr[i]);
            if (v != null && v > 0) {
              yieldGrams = v < 100 ? v * 1000 : v; // кг → г
              break;
            }
            if (dr[i].contains('/')) {
              final first = _parseNum(dr[i].split('/').first.trim());
              if (first != null && first > 0) { yieldGrams = first < 100 ? first * 1000 : first; break; }
            }
          }
          break;
        }
        if (d0 == '№' && dr.length > 1 && dr[1].toLowerCase().contains('наименование')) break;
        final product = dr.length > 1 ? dr[1].trim() : '';
        final grossStr = dr.length > 2 ? dr[2].trim() : '';
        final looksLikeIngredient = product.isNotEmpty && (RegExp(r'\d').hasMatch(grossStr) || grossStr.toLowerCase().contains('шт'));

        // Строки, где вместе с ингредиентом в конце лежит длинный текст технологии (как в супы.xlsx):
        // извлекаем текст технологии независимо от того, считаем ли строку ингредиентом.
        final rowTextLower = dr.join(' ').toLowerCase();
        final hasTechnologyWord = rowTextLower.contains('технология');
        final hasLongTextCell = dr.any((c) {
          final t = c.trim();
          return t.length > 40 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(t) && _parseNum(t) == null;
        });
        if ((hasTechnologyWord || technologyText != null) && hasLongTextCell) {
          final techFromRow = dr.where((c) {
            final t = c.trim();
            return t.length > 40 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(t) && _parseNum(t) == null;
          }).join(' ').trim();
          if (techFromRow.isNotEmpty) {
            technologyText = (technologyText != null && technologyText!.isNotEmpty)
                ? '$technologyText\n$techFromRow'
                : techFromRow;
          }
        }

        if (looksLikeIngredient) {
          // Не сбрасываем technologyText — технология может идти до или после ингредиентов
        } else {
          final rowText = dr.join(' ');
          if (rowText.toLowerCase().contains('технология')) {
            int? techCol;
            for (var ci = 0; ci < dr.length; ci++) {
              if (dr[ci].toLowerCase().contains('технология')) { techCol = ci; break; }
            }
            final techParts = <String>[];
            for (var ci = (techCol != null ? techCol! + 1 : 0); ci < dr.length; ci++) {
              final cell = dr[ci].trim();
              if (cell.isEmpty) continue;
              if (cell.length > 15 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(cell) && _parseNum(cell) == null) techParts.add(cell);
            }
            if (techParts.isNotEmpty) {
              technologyText = (technologyText != null ? '$technologyText\n' : '') + techParts.join(' ');
            } else {
              technologyText ??= ''; // заголовок «Технология» — текст в следующих строках
            }
            dataRow++;
            continue;
          }
          if (technologyText != null) {
            final more = dr.where((c) => c.length > 15 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(c) && _parseNum(c.trim()) == null).join(' ').trim();
            if (more.isNotEmpty) {
              technologyText = (technologyText!.isEmpty ? '' : '$technologyText\n') + more;
              dataRow++;
              continue;
            }
          }
        }
        // Строка без продукта, но с длинным текстом (технология в отдельной строке/ячейке после ингредиентов)
        if (product.isEmpty) {
          final techFromRow = dr.where((c) {
            final t = c.trim();
            return t.length > 20 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(t) && _parseNum(t) == null &&
                !RegExp(r'^№$|^выход$|^декор$', caseSensitive: false).hasMatch(t.toLowerCase());
          }).join(' ').trim();
          if (techFromRow.isNotEmpty) {
            technologyText = (technologyText != null ? '$technologyText\n' : '') + techFromRow;
            dataRow++;
            continue;
          }
          dataRow++;
          continue;
        }
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
          yieldGrams: yieldGrams,
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
      List<String> headerRow;
      int dataStartR;
      // Вариант 1: заголовок в следующей строке (классический пф хц)
      if (r + 1 < rows.length) {
        final nextRow = rows[r + 1].map((c) => (c ?? '').toString().trim()).toList();
        final h0 = nextRow.isNotEmpty ? nextRow[0].trim().toLowerCase() : '';
        final h1 = nextRow.length > 1 ? nextRow[1].trim().toLowerCase() : '';
        final h2 = nextRow.length > 2 ? nextRow[2].trim().toLowerCase() : '';
        final h3 = nextRow.length > 3 ? nextRow[3].trim().toLowerCase() : '';
        final hasNormInHeader = h3.contains('норма') || h3.contains('закладк') || h2.contains('норма');
        final firstCellOk = h0.isEmpty || h0 == '№' || (h0.contains('наименование') && (h0.contains('продукт') || h0.contains('сырья')));
        final headerOk = firstCellOk &&
            (h1.contains('наименование') || h1.contains('ед') || h2.contains('ед')) &&
            (h2.contains('ед') || h2.contains('изм') || h2.contains('норма') || h3.contains('норма') || h3.contains('закладк'));
        if (headerOk || (hasNormInHeader && (h1.contains('наименование') || h0.contains('наименование')))) {
          headerRow = nextRow;
          dataStartR = r + 2;
        } else {
          headerRow = [];
          dataStartR = -1;
        }
      } else {
        headerRow = [];
        dataStartR = -1;
      }
      // Вариант 2: заголовок в той же строке, что и название (xlsx: название в A1, Наименование продукта|Ед.изм|Норма в B1..F1)
      if (dataStartR < 0 && row.length >= 3) {
        final rest = row.sublist(1).map((c) => c.toLowerCase()).toList();
        final hasNaimen = rest.any((c) => c.contains('наименование') && (c.contains('продукт') || c.contains('сырья')));
        final hasEdNorm = rest.any((c) => c.contains('ед') || c.contains('изм') || c.contains('норма') || c.contains('закладк'));
        if (hasNaimen && hasEdNorm) {
          headerRow = row.sublist(1);
          dataStartR = r + 1;
        }
      }
      if (dataStartR < 0 || headerRow.isEmpty) {
        r++;
        continue;
      }
      final h0 = headerRow.isNotEmpty ? headerRow[0].trim().toLowerCase() : '';
      final h1 = headerRow.length > 1 ? headerRow[1].trim().toLowerCase() : '';
      final h2 = headerRow.length > 2 ? headerRow[2].trim().toLowerCase() : '';
      final h3 = headerRow.length > 3 ? headerRow[3].trim().toLowerCase() : '';
      final hasNormInHeader = h3.contains('норма') || h3.contains('закладк') || h2.contains('норма');
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
      var dataR = dataStartR;
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
        // Вариант без Ед.изм: Наименование | Норма | Технология — норма в col prodCol+1; иначе №|продукт|ед.изм|норма
        final h1H = headerRow.length > 1 ? headerRow[1].toLowerCase() : '';
        final h2 = headerRow.length > 2 ? headerRow[2].toLowerCase() : '';
        final hasUnitCol = h1H.contains('ед') || h1H.contains('изм') || h2.contains('ед') || h2.contains('изм');
        final normInCol2 = h2.contains('норма') && !h2.contains('ед') && !h2.contains('изм') && !hasUnitCol;
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

  /// Органолептика, подзаголовки — не названия блюд.
  static bool _isSkipForDishName(String s) {
    final low = s.trim().toLowerCase();
    return low.contains('органолептическ') ||
        low.contains('внешний вид') ||
        low.contains('консистенция') ||
        low.contains('запах') ||
        low.contains('вкус') ||
        low.contains('цвет');
  }

  /// ГОСТ: убрать строки "3. РЕЦЕПТУРА" перед заголовком таблицы (Наименование, Брутто).
  static List<List<String>> _skipGostSectionHeaders(List<List<String>> rows) {
    final gostSection = RegExp(r'^\d+\.\s*рецептура', caseSensitive: false);
    final filtered = <List<String>>[];
    var foundHeader = false;
    for (final row in rows) {
      if (row.isEmpty) {
        if (!foundHeader) filtered.add(row);
        continue;
      }
      final first = row.first.trim().toLowerCase();
      final rowText = row.join(' ').toLowerCase();
      if (rowText.contains('наименование') || rowText.contains('брутто') || rowText.contains('расход сырья')) {
        foundHeader = true;
        filtered.add(row);
      } else if (!foundHeader && (gostSection.hasMatch(first) || first == 'рецептура') && row.length <= 2) {
        continue; // пропустить "3. РЕЦЕПТУРА"
      } else {
        filtered.add(row);
      }
    }
    return filtered;
  }

  /// Из объединённой ячейки "Мясная к пенному ... Органолептические показатели: № ..." извлечь название.
  static String? _extractDishBeforeOrganoleptic(String cell) {
    final idx = cell.toLowerCase().indexOf('органолептическ');
    if (idx <= 0) return null;
    final before = cell.substring(0, idx).trim();
    if (before.length < 4) return null;
    // Берем первый осмысленный фрагмент (до "Технологическая карта", "Название на чеке" и т.п.)
    final stop = RegExp(
      r'технологическая карта|название на чеке|область применения|хранение|срок хранения',
      caseSensitive: false,
    );
    final stopMatch = stop.firstMatch(before);
    final segment = stopMatch != null ? before.substring(0, stopMatch.start).trim() : before;
    final words = segment.split(RegExp(r'\s+')).where((w) => w.length > 1).take(6).toList();
    if (words.isEmpty) return null;
    final candidate = words.join(' ').trim();
    if (candidate.length >= 4 && _isValidDishName(candidate) && !_isSkipForDishName(candidate)) {
      return candidate;
    }
    return null;
  }

  /// Строки-заголовки и разделители — не ингредиенты (ТРЕБОВАНИЯ К ОФОРМЛЕНИЮ, ИТОГО, вес готового блюда).
  static bool _isJunkProductName(String s) {
    final low = s.trim().toLowerCase();
    return low.contains('требования к оформлению') || low.contains('требования к подаче') ||
        low.contains('вес готового блюда') || low.contains('вес готового изделия') ||
        low.contains('в расчете на') || low.contains('порц') ||
        low.contains('органолептическ') || low.contains('органолет') || low == 'итого' ||
        low.contains('хранение') || low.startsWith('срок хранен') ||
        RegExp(r'^ед\.?\s*изм\.?\.?$').hasMatch(low) || RegExp(r'^ед\s*изм').hasMatch(low) ||
        low.contains('ресторан') || RegExp(r'^ресторан\s*[«""]').hasMatch(low) || low == 'блюдо' ||
        RegExp(r'^способ\s*(приготовления|оформления)?$').hasMatch(low);
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

    // ГОСТ: строка "3. РЕЦЕПТУРА" — пропустить, заголовок в следующей строке
    rows = _skipGostSectionHeaders(rows);

    // Формат «Полное пособие Кухня» / супы.xlsx: блоки [название блюда] [№|Наименование продукта|Вес] [данные] [Выход]
    final polnoePosobie = _tryParsePolnoePosobieFormat(rows);
    if (polnoePosobie.isNotEmpty) return polnoePosobie;

    // пф гц: [название] ["" | наименование | Ед.изм | Норма закладки] [№ | продукт | ед | норма] [Выход] — повтор
    final pfGc = _tryParsePfGcFormat(rows);
    if (pfGc.isNotEmpty) return pfGc;

    final results = <TechCardRecognitionResult>[];
    int headerIdx = -1;
    int nameCol = -1, productCol = -1, grossCol = -1, netCol = -1, wasteCol = -1, outputCol = -1, techCol = -1;

    final nameKeys = ['наименование', 'название', 'блюдо', 'пф', 'набор', 'name', 'dish'];
    final productKeys = ['продукт', 'продукты', 'сырьё', 'сырья', 'ингредиент', 'product', 'ingredient'];
    // iiko DOCX: "Вес брутто, кг" приоритетнее "Брутто в ед. изм."
    final grossKeys = ['вес брутто', 'масса брутто', 'брутто', 'бр', 'вес гр', '1 порция', 'расход', 'норма', 'норма закладки', 'масса', 'gross'];
    final netKeys = ['вес нетто', 'масса нетто', 'нетто', 'нт', 'net'];
    final wasteKeys = ['отход', 'отх', 'waste', 'процент отхода'];
    final outputKeys = ['выход', 'вес готового', 'вес готового продукта', 'готовый', 'output'];
    final unitKeys = ['ед. изм', 'ед изм', 'единица', 'unit'];
    final technologyKeys = ['технология', 'приготовления', 'способ приготовления', 'technology'];

    int unitCol = -1;
    bool grossColIsKg = false;
    bool netColIsKg = false;

    // Динамическая детекция колонок: находим строку-заголовок с Наименование, Брутто, Нетто
    for (var r = 0; r < rows.length && r < 25; r++) {
      final row = rows[r].map((c) => (c is String ? c : c?.toString() ?? '').trim().toLowerCase()).toList();
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
            // "Расход сырья на 1 порцию" — заголовок группы колонок (Брутто/Нетто), не колонка наименований (ГОСТ 2-row header)
            if (cell.contains('расход') && cell.contains('сырья') && (cell.contains('на 1 порцию') || cell.contains('порцию'))) break;
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
            // "Брутто в ед. изм." — единицы г/шт, не кг; iiko: предпочитаем "Вес брутто, кг"
            final isBruttoInEdIzm = cell.contains('брутто') && (cell.contains('в ед') || cell.contains('ед.изм') || cell.contains('ед изм')) && !cell.contains('вес брутто') && !cell.contains('масса брутто');
            if (isBruttoInEdIzm) {
              if (grossCol < 0) grossCol = c; // только если лучшей колонки нет
            } else {
              if (grossCol < 0 || cell.contains('кг')) grossCol = c;
            }
            break;
          }
        }
        for (final k in netKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            final isNettoInEdIzm = cell.contains('нетто') && (cell.contains('в ед') || cell.contains('ед.изм') || cell.contains('ед изм')) && !cell.contains('вес нетто') && !cell.contains('масса нетто');
            if (isNettoInEdIzm) {
              if (netCol < 0) netCol = c;
            } else {
              if (netCol < 0 || cell.contains('кг')) netCol = c;
            }
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
        for (final k in technologyKeys) {
          if (cell.contains(k)) {
            headerIdx = r;
            techCol = c;
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
              final brEd = h.contains('брутто') && (h.contains('в ед') || h.contains('ед.изм')) && !h.contains('вес брутто');
              final ntEd = h.contains('нетто') && (h.contains('в ед') || h.contains('ед.изм')) && !h.contains('вес нетто');
              if (h.contains('брутто') && (brEd ? grossCol < 0 : (grossCol < 0 || h.contains('кг')))) grossCol = c;
              if (h.contains('нетто') && (ntEd ? netCol < 0 : (netCol < 0 || h.contains('кг')))) netCol = c;
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
            final brEd = h.contains('брутто') && (h.contains('в ед') || h.contains('ед.изм')) && !h.contains('вес брутто');
            final ntEd = h.contains('нетто') && (h.contains('в ед') || h.contains('ед.изм')) && !h.contains('вес нетто');
            if (h.contains('брутто') && (brEd ? grossCol < 0 : (grossCol < 0 || h.contains('кг')))) grossCol = c;
            if (h.contains('нетто') && (ntEd ? netCol < 0 : (netCol < 0 || h.contains('кг')))) netCol = c;
            if ((h.contains('вес гр') || h.contains('1 порция') || h.contains('вес брутто')) && grossCol < 0) grossCol = c;
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
    if (productCol < 0) productCol = (nameCol >= 0 ? nameCol : 1);

    // Запомнили индексы: nameCol, productCol, grossCol, netCol — читаем данные СТРОГО по ним

    // Колонки с "кг" в заголовке — значения в килограммах, переводим в граммы
    final headerRow = headerIdx < rows.length ? rows[headerIdx].map((c) => c.trim().toLowerCase()).toList() : <String>[];
    if (grossCol >= 0 && grossCol < headerRow.length && headerRow[grossCol].contains('кг')) grossColIsKg = true;
    if (netCol >= 0 && netCol < headerRow.length && headerRow[netCol].contains('кг')) netColIsKg = true;

    // Название блюда может быть в строках выше заголовка или в той же строке (iiko: Мясная к пенному | ... | Органолептические показатели: № ...)
    String? currentDish;
    for (var r = 0; r <= headerIdx && r < rows.length; r++) {
      final row = rows[r];
      final limitCol = (r == headerIdx && (productCol > 0 || nameCol > 0))
          ? (productCol > 0 ? productCol : nameCol)
          : row.length;
      for (var ci = 0; ci < row.length && ci < limitCol; ci++) {
        final s = (row[ci] ?? '').toString().trim();
        if (s.length < 3) continue;
        if (s.endsWith(':')) continue; // "Хранение:", "Область применения:"
        if (RegExp(r'^\d{1,2}\.\d{1,2}\.\d{2,4}').hasMatch(s)) continue; // дата
        if (s.toLowerCase().startsWith('технологическая карта')) continue;
        if (s.toLowerCase().contains('название на чеке') || s.toLowerCase().contains('название чека')) continue;
        if (_isSkipForDishName(s)) {
          final extracted = _extractDishBeforeOrganoleptic(s);
          if (extracted != null) {
            currentDish = extracted;
            break;
          }
          continue;
        }
        if (!_isValidDishName(s)) continue;
        currentDish = s;
        break;
      }
      if (currentDish != null) break;
    }
    final currentIngredients = <TechCardIngredientLine>[];
    String? currentTechnologyText;

    void flushCard({double? yieldGrams}) {
      if (currentDish != null && (currentDish!.isNotEmpty || currentIngredients.isNotEmpty)) {
        final tech = currentTechnologyText?.trim();
        results.add(TechCardRecognitionResult(
          dishName: currentDish,
          technologyText: tech != null && tech.length >= 15 ? tech : null,
          ingredients: List.from(currentIngredients),
          isSemiFinished: currentDish?.toLowerCase().contains('пф') ?? false,
          yieldGrams: yieldGrams,
        ));
      }
      currentIngredients.clear();
      currentTechnologyText = null;
    }

    void clearCurrentCard() {
      currentIngredients.clear();
      currentTechnologyText = null;
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
      if (techCol >= 0 && techCol < cells.length) {
        final techVal = cells[techCol].trim();
        if (techVal.length > 15 && !RegExp(r'^технология\s|наименование|брутто|нетто', caseSensitive: false).hasMatch(techVal)) {
          currentTechnologyText = (currentTechnologyText != null ? '$currentTechnologyText\n' : '') + techVal;
        }
      }

      // Выход — завершение карточки (формат «Полное пособие Кухня», ГОСТ «Выход блюда (в граммах): 190»). Парсим значение выхода для веса порции (блюдо).
      final c0 = cells.isNotEmpty ? cells[0].trim().toLowerCase() : '';
      final isYieldRow = c0 == 'выход' || (c0.contains('выход') && (c0.contains('блюда') || c0.contains('грамм') || c0.contains('порцию') || c0.contains('готовой')));
      if (isYieldRow) {
        double? outG;
        if (outputCol >= 0 && outputCol < cells.length) {
          outG = _parseNum(cells[outputCol]);
        }
        if (outG == null && cells.length > 1) outG = _parseNum(cells[1]);
        if (outG == null) {
          for (var i = 1; i < cells.length && i < 5; i++) {
            outG = _parseNum(cells[i]);
            if (outG != null && outG > 0) break;
          }
        }
        if (outG != null && outG > 0 && outG < 100) outG = outG * 1000; // кг → г
        flushCard(yieldGrams: outG);
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
        final nextC0 = nextRow.isNotEmpty ? nextRow[0].trim().toLowerCase() : '';
        final nextC1 = nextRow.length > 1 ? nextRow[1].toLowerCase() : '';
        final nextLooksLikeHeader = (nextC0 == '№' || nextC0.isEmpty) && nextC1.contains('наименование') && nextC1.contains('продукт');
        if (nextLooksLikeHeader) {
          var dishInCol0 = cells.isNotEmpty ? cells[0].trim() : '';
          if (_isSkipForDishName(dishInCol0)) {
            dishInCol0 = _extractDishBeforeOrganoleptic(dishInCol0) ?? '';
          }
          if (dishInCol0.length >= 3 && !_isSkipForDishName(dishInCol0) && _isValidDishName(dishInCol0) && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(dishInCol0) &&
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
      // Точки отсечения: Итого и Технология. Парсим выход из колонки Выход для веса порции (блюдо).
      if (nameVal.toLowerCase() == 'итого' || productVal.toLowerCase() == 'итого' || productVal.toLowerCase().startsWith('всего')) {
        double? outG = _parseNum(outputVal);
        if (outG != null && outG > 0 && outG < 100) outG = outG * 1000; // кг → г
        flushCard(yieldGrams: outG);
        currentDish = null;
        return true;
      }
      final rowText = cells.join(' ').toLowerCase();
      // Строка «Технология приготовления» — собираем текст из этой строки (ячейки после заголовка) и не сбрасываем карточку
      if (RegExp(r'^технология\s|^технология\s*:|технология\s+приготовления').hasMatch(rowText) ||
          (rowText.trim().startsWith('технология') && cells.length <= 3)) {
        int? techCol;
        for (var ci = 0; ci < cells.length; ci++) {
          if (cells[ci].toLowerCase().contains('технология')) { techCol = ci; break; }
        }
        if (techCol != null && techCol + 1 < cells.length) {
          final parts = <String>[];
          for (var ci = techCol + 1; ci < cells.length; ci++) {
            final cell = cells[ci].trim();
            if (cell.length > 15 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(cell) && _parseNum(cell) == null) {
              parts.add(cell);
            }
          }
          if (parts.isNotEmpty) {
            currentTechnologyText = (currentTechnologyText != null ? '$currentTechnologyText\n' : '') + parts.join(' ');
          }
        }
        if (currentTechnologyText == null) currentTechnologyText = '';
        return true; // skip строку заголовка технологии
      }
      // Продолжение технологии: строка без ингредиента, но с длинным текстом (рецепт в отдельной строке)
      if (currentTechnologyText != null &&
          productVal.isEmpty &&
          nameVal.trim().isEmpty &&
          (gCol < 0 || _parseNum(grossVal) == null) &&
          (nCol < 0 || _parseNum(netVal) == null)) {
        final textParts = cells.where((c) {
          final t = c.trim();
          return t.length > 20 && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(t) && _parseNum(t) == null;
        }).toList();
        if (textParts.isNotEmpty) {
          currentTechnologyText = (currentTechnologyText!.isEmpty ? '' : '$currentTechnologyText\n') + textParts.join(' ');
          return true;
        }
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
            if (c.length > 2 && !_isSkipForDishName(c) && _isValidDishName(c) && RegExp(r'[а-яА-ЯёЁa-zA-Z]').hasMatch(c) && !RegExp(r'ттк|карта|брутто|нетто|наименование').hasMatch(c.toLowerCase())) {
              currentDish = c;
              break;
            }
            if (_isSkipForDishName(c)) {
              final extracted = _extractDishBeforeOrganoleptic(c);
              if (extracted != null) {
                currentDish = extracted;
                break;
              }
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
      // Новая карточка: в nameCol новое блюдо. Не считать блюдом строку с весом в колонках брутто/нетто — это ингредиент.
      if (nameCol != pCol &&
          nameVal.isNotEmpty &&
          !RegExp(r'^[\d\s\.\,]+$').hasMatch(nameVal) &&
          nameVal.toLowerCase() != 'итого') {
        final hasWeightInRow = (grossCol >= 0 && grossCol < cells.length && _parseNum(cells[grossCol]) != null) ||
            (netCol >= 0 && netCol < cells.length && _parseNum(cells[netCol]) != null);
        if (!hasWeightInRow) {
          if (currentDish != null && currentDish != nameVal && currentIngredients.isNotEmpty) {
            flushCard();
          }
          if (_isValidDishName(nameVal)) currentDish = nameVal;
        }
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
              !_isJunkProductName(shiftedProduct) &&
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
      // Секции DOCX — не ингредиенты (Хранение:, Область применения:, Срок Хранения:, Название на чеке и т.д.)
      final pLow = productVal.trim().toLowerCase();
      if (pLow == 'хранение:' || pLow.startsWith('хранение:') ||
          pLow.contains('область применения') || pLow.startsWith('срок хранен') ||
          pLow.contains('название на чеке') || pLow.contains('органолептическ')) return true;
      final nLow = nameVal.trim().toLowerCase();
      if (nLow == 'хранение:' || nLow.startsWith('хранение:') || nLow.startsWith('срок хранен') ||
          nLow.contains('область применения') || nLow.contains('название на чеке') || nLow.contains('органолептическ')) return true;
      // Название блюда в ячейке продукта (дубликат заголовка) — не добавлять как ингредиент
      if (currentDish != null && productVal.trim().isNotEmpty &&
          (productVal.trim() == currentDish || productVal.trim() == currentDish!.trim())) return true;
      // Пропускаем, если productVal — только цифры/пробелы (ошибочная колонка)
      if (RegExp(r'^[\d\s\.\,\-\+]+$').hasMatch(productVal)) return true;
      // Мусор: пусто в Наименовании (продукт/название)
      if (productVal.trim().isEmpty && nameVal.trim().isEmpty) return true;
      // По структуре таблицы: в колонках брутто/нетто должны быть числа, не текст (футер, объединённые ячейки)
      final grossCellLooksLikeText = gCol >= 0 && grossVal.trim().length > 12 && RegExp(r'[а-яА-ЯёЁa-zA-Z]{3,}').hasMatch(grossVal);
      final netCellLooksLikeText = nCol >= 0 && netVal.trim().length > 12 && RegExp(r'[а-яА-ЯёЁa-zA-Z]{3,}').hasMatch(netVal);
      if (grossCellLooksLikeText || netCellLooksLikeText) return true;
      // Мусор: нет цифр в Брутто (и в Нетто) — строка без веса
      final hasDigitsInGross = gCol >= 0 && RegExp(r'\d').hasMatch(grossVal);
      final hasDigitsInNet = nCol >= 0 && RegExp(r'\d').hasMatch(netVal);
      if (productVal.isNotEmpty && !hasDigitsInGross && !hasDigitsInNet) return true;
      // Строка с продуктом (ингредиент). Не считать название блюдом, если в строке есть вес — это ингредиент.
      if (productVal.isNotEmpty) {
        final rowHasWeight = (gCol >= 0 && gCol < cells.length && _parseNum(grossVal) != null) ||
            (nCol >= 0 && nCol < cells.length && _parseNum(netVal) != null) ||
            (cells.length > 2 && RegExp(r'\d').hasMatch(cells[2]));
        if (currentDish == null && nameVal.isNotEmpty && _isValidDishName(nameVal) && !rowHasWeight) currentDish = nameVal;
        var gross = _parseNum(grossVal);
        var net = _parseNum(netVal);
        var output = _parseNum(outputVal);
        final unitCell = unitCol >= 0 && unitCol < cells.length ? cells[unitCol].trim().toLowerCase() : '';
        final unitIsKgOrL = unitCell.contains('кг') || unitCell == 'kg' || unitCell.contains('л') || unitCell == 'l';
        final grossRawLooksLikeKg = RegExp(r'^\s*0[,.]\d{1,3}\s*$').hasMatch(grossVal.trim());
        final netRawLooksLikeKg = RegExp(r'^\s*0[,.]\d{1,3}\s*$').hasMatch(netVal.trim());
        if (grossColIsKg || unitIsKgOrL || grossRawLooksLikeKg) {
          if (gross != null && gross > 0 && gross < 100) gross = gross * 1000;
        }
        if (netColIsKg || unitIsKgOrL || netRawLooksLikeKg) {
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
        if (_isJunkProductName(cleanName)) return false;
        // По структуре: строка ингредиента должна иметь хотя бы один вес (брутто или нетто)
        if ((gross == null || gross <= 0) && (net == null || net <= 0)) return false;
        // iiko DOCX: при gross==net==100 часто читаем «брутто в ед. изм» вместо кг; строка с названием блюда («Мясная к пенному») — не продукт
        final gEq = gross != null && net != null && (gross - net).abs() < 0.01;
        final both100 = gEq && gross! > 99 && gross < 101;
        final looksLikeDishName = RegExp(r'^[а-яА-ЯёЁ\s]+\s+к\s+[а-яА-ЯёЁ\s]+$').hasMatch(cleanName) && cleanName.length < 30;
        if (both100 && looksLikeDishName) return false;
        // Яйца: в карте часто 1 шт брутто, 26 г нетто (съедобная часть). Приводим к граммам: ~50 г брутто на 1 шт.
        if (cleanName.toLowerCase().contains('яйц') && gross == 1 && net != null && net >= 20 && net <= 60) {
          gross = 50.0;
        }
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
    // Резерв для iiko/1С (печенная свекла.xls): если получилась одна карточка только с названием — пробуем явный поиск заголовка №|Наименование продукта|…|Вес брутто, кг|Вес нетто
    if (results.length == 1 &&
        results.single.ingredients.isEmpty &&
        results.single.dishName != null &&
        results.single.dishName!.trim().isNotEmpty) {
      final iiko = _tryParseIikoStyleFallback(rows, results.single.dishName!);
      if (iiko.isNotEmpty && iiko.first.ingredients.isNotEmpty) return iiko;
    }
    return results;
  }

  /// Специальный парсер CSV-формата "Наименование,Продукт,Брутто,...,Технология"
  /// как в ттк.csv: каждая строка с непустым "Наименование" = начало новой карты,
  /// ингредиенты идут до строки "Итого", технология лежит в последнем столбце.
  static List<TechCardRecognitionResult> _tryParseCsvWithTechnologyColumn(
      List<List<String>> rows) {
    if (rows.length < 2) return [];
    final header = rows.first.map((c) => (c ?? '').toString().trim().toLowerCase()).toList();
    final nameCol = header.indexWhere((c) => c == 'наименование');
    final productCol = header.indexWhere((c) => c == 'продукт');
    final bruttoCol = header.indexWhere((c) => c == 'брутто');
    final nettoCol = header.indexWhere((c) => c == 'нетто');
    final yieldCol = header.indexWhere((c) => c == 'выход');
    final techCol = header.indexWhere((c) => c == 'технология');
    if (nameCol < 0 || productCol < 0 || bruttoCol < 0 || techCol < 0) return [];

    final results = <TechCardRecognitionResult>[];
    String? currentDish;
    final currentIngredients = <TechCardIngredientLine>[];
    String? currentTech;
    double? currentYield;

    void flush() {
      if (currentDish != null && currentDish!.trim().isNotEmpty && currentIngredients.isNotEmpty) {
        results.add(
          TechCardRecognitionResult(
            dishName: currentDish,
            ingredients: List.from(currentIngredients),
            isSemiFinished: currentDish!.toLowerCase().contains('пф'),
            technologyText: currentTech != null && currentTech!.trim().length > 10
                ? currentTech!.trim()
                : null,
            yieldGrams: currentYield,
          ),
        );
      }
      currentDish = null;
      currentIngredients.clear();
      currentTech = null;
      currentYield = null;
    }

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r].map((c) => (c ?? '').toString().trim()).toList();
      if (row.isEmpty || row.every((c) => c.isEmpty)) continue;

      final name = nameCol < row.length ? row[nameCol] : '';
      final product = productCol < row.length ? row[productCol] : '';
      final bruttoStr = bruttoCol < row.length ? row[bruttoCol] : '';
      final nettoStr = nettoCol >= 0 && nettoCol < row.length ? row[nettoCol] : '';
      final yieldStr = yieldCol >= 0 && yieldCol < row.length ? row[yieldCol] : '';
      final techStr = techCol < row.length ? row[techCol] : '';

      final lowName = name.toLowerCase();
      final lowProduct = product.toLowerCase();

      // Строка "Итого" завершает текущую карту
      if (lowProduct == 'итого' || lowName == 'итого') {
        final y = _parseNum(yieldStr);
        if (y != null && y > 0) {
          currentYield = y < 100 ? y * 1000 : y;
        }
        flush();
        continue;
      }

      // Новая карта: непустое "Наименование"
      if (name.isNotEmpty) {
        // если уже что-то собирали — сохранить предыдущую
        if (currentDish != null && currentIngredients.isNotEmpty) {
          flush();
        }
        currentDish = name;
        // Технология может быть уже в первой строке
        if (techStr.isNotEmpty) {
          currentTech = techStr;
        }
      } else {
        // Продолжение технологии в последующих строках того же блока
        if (techStr.isNotEmpty) {
          if (currentTech == null || currentTech!.isEmpty) {
            currentTech = techStr;
          } else {
            currentTech = '$currentTech\n$techStr';
          }
        }
      }

      // Строка ингредиента: есть продукт и брутто
      if (product.isNotEmpty && lowProduct != 'итого') {
        final g = _parseNum(bruttoStr);
        var n = _parseNum(nettoStr);
        if (g == null && n == null) continue;
        final gross = g ?? n ?? 0;
        if (gross <= 0) continue;
        n ??= gross;

        currentIngredients.add(
          TechCardIngredientLine(
            productName: product,
            grossGrams: gross,
            netGrams: n,
            outputGrams: n,
            primaryWastePct: null,
            unit: 'g',
            ingredientType:
                RegExp(r'^пф\s', caseSensitive: false).hasMatch(product) ? 'semi_finished' : 'product',
          ),
        );
      }
    }
    flush();
    return results;
  }

  /// Резервный парсинг формата iiko/1С: № | Наименование продукта | Ед. изм. | Брутто в ед. изм. | Вес брутто, кг | Вес нетто… | Вес готового… | Технология
  static List<TechCardRecognitionResult> _tryParseIikoStyleFallback(List<List<String>> rows, String dishName) {
    if (rows.length < 3) return [];
    int headerIdx = -1;
    int productCol = 1;
    int grossCol = 4;
    int netCol = 5;
    int outputCol = 6;
    for (var r = 0; r < rows.length && r < 35; r++) {
      final row = rows[r].map((c) => (c is String ? c : c?.toString() ?? '').trim()).toList();
      if (row.length < 4) continue;
      final c0 = row[0].toLowerCase();
      // № в первой ячейке или в любой (xls с объединёнными ячейками — первая может быть пустой)
      final hasNum = c0 == '№' || c0 == 'n' || RegExp(r'^\d+$').hasMatch(c0) ||
          (c0.isEmpty && row.length > 1 && (row[1].toLowerCase() == '№' || row[1].toLowerCase() == 'n' || RegExp(r'^\d+$').hasMatch(row[1].trim())));
      bool hasProduct = false;
      bool hasBrutto = false;
      bool hasNetto = false;
      for (var c = 1; c < row.length && c < 12; c++) {
        final h = row[c].toLowerCase();
        if (h.contains('наименование') && h.contains('продукт')) hasProduct = true;
        if (h.contains('брутто') || h.contains('вес брутто')) hasBrutto = true;
        if (h.contains('нетто') || h.contains('вес нетто') || (h.contains('п/ф') && h.contains('кг'))) hasNetto = true;
      }
      if (hasNum && hasProduct && hasBrutto && hasNetto) {
        headerIdx = r;
        for (var c = 1; c < row.length && c < 12; c++) {
          final h = row[c].toLowerCase();
          if (h.contains('наименование') && h.contains('продукт')) productCol = c;
          if ((h.contains('вес брутто') || h.contains('брутто')) && (h.contains('кг') || h.contains('ед'))) grossCol = c;
          if ((h.contains('вес нетто') || h.contains('нетто') || h.contains('п/ф')) && (h.contains('кг') || h.contains('п/ф'))) netCol = c;
          if (h.contains('вес готового') || (h.contains('выход') && c > netCol)) outputCol = c;
        }
        break;
      }
    }
    if (headerIdx < 0) return [];
    final headerRow = rows[headerIdx].map((c) => (c is String ? c : c?.toString() ?? '').trim().toLowerCase()).toList();
    final grossIsKg = grossCol < headerRow.length && headerRow[grossCol].contains('кг');
    final netIsKg = netCol < headerRow.length && headerRow[netCol].contains('кг');
    final ingredients = <TechCardIngredientLine>[];
    for (var r = headerIdx + 1; r < rows.length; r++) {
      final cells = rows[r].map((c) => (c is String ? c : c?.toString() ?? '').trim()).toList();
      if (cells.length <= productCol) continue;
      final c0 = cells[0].toLowerCase();
      if (c0 == 'итого' || c0.startsWith('всего') || (c0.contains('вес готового') && cells.length < 5)) break;
      // Номер строки в первой ячейке или во второй (xls с объединённой первой колонкой)
      final firstIsNum = RegExp(r'^\d+$').hasMatch(c0);
      final secondIsNum = cells.length > 1 && RegExp(r'^\d+$').hasMatch(cells[1].trim());
      if (!firstIsNum && !(c0.isEmpty && secondIsNum)) continue;
      final int pCol = (c0.isEmpty && secondIsNum && cells.length > 2) ? 2 : productCol;
      final productVal = cells.length > pCol ? cells[pCol].trim() : '';
      if (productVal.isEmpty || productVal.length < 2) continue;
      var gross = _parseNum(cells.length > grossCol ? cells[grossCol] : '');
      var net = _parseNum(cells.length > netCol ? cells[netCol] : '');
      var output = outputCol < cells.length ? _parseNum(cells[outputCol]) : null;
      if (grossIsKg && gross != null && gross > 0 && gross < 100) gross = gross * 1000;
      if (netIsKg && net != null && net > 0 && net < 100) net = net * 1000;
      if (output != null && output > 0 && output < 100 && outputCol < headerRow.length && headerRow[outputCol].contains('кг')) output = output * 1000;
      if ((gross == null || gross <= 0) && (net == null || net <= 0)) continue;
      final cleanName = productVal.replaceFirst(RegExp(r'^Т\.\s*', caseSensitive: false), '').replaceFirst(RegExp(r'^П/Ф\s*', caseSensitive: false), '').trim();
      if (cleanName.isEmpty || _isJunkProductName(cleanName)) continue;
      ingredients.add(TechCardIngredientLine(
        productName: cleanName,
        grossGrams: gross ?? net ?? 0,
        netGrams: net ?? gross ?? 0,
        outputGrams: output,
        primaryWastePct: null,
        unit: 'g',
        ingredientType: RegExp(r'^П/Ф\s', caseSensitive: false).hasMatch(productVal) ? 'semi_finished' : 'product',
      ));
    }
    if (ingredients.isEmpty) return [];
    return [
      TechCardRecognitionResult(
        dishName: dishName,
        ingredients: ingredients,
        isSemiFinished: dishName.toLowerCase().contains('пф'),
      ),
    ];
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

  /// Ячейка похожа на заголовок колонки (брутто, нетто, наименование...), а не на название блюда.
  static bool _isStructuralHeaderCell(String cell) {
    final low = cell.trim().toLowerCase();
    if (low.isEmpty || low.length > 80) return false;
    if (RegExp(r'^[а-яА-ЯёЁ\s]+\s+к\s+[а-яА-ЯёЁ\s]+$').hasMatch(cell.trim()) && cell.trim().length < 35) return false;
    const structural = [
      'наименование', 'продукт', 'брутто', 'нетто', 'название', 'сырьё', 'ингредиент', 'расход', 'норма',
      'ед.изм', 'ед изм', 'единица', 'отход', 'выход', '№', 'n',
    ];
    return structural.any((k) => low.contains(k)) || low == 'бр' || low == 'нт';
  }

  static String _headerSignature(List<String> headerCells) {
    final normalize = (String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final structural = headerCells
        .map(normalize)
        .where((c) => c.isNotEmpty && _isStructuralHeaderCell(c));
    if (structural.isEmpty) return headerCells.map(normalize).where((c) => c.isNotEmpty).join('|');
    return structural.join('|');
  }

  /// Найти заголовок ТТК в rows и вернуть его подпись (для дообучения). Подпись строится только из
  /// структурных ячеек (колонки брутто/нетто/наименование и т.д.), чтобы один и тот же формат таблицы
  /// давал одну подпись у разных файлов (Мясная к пенному / Мясная к ХУЮ) и обучение применялось ко всем.
  static String? _headerSignatureFromRows(List<List<String>> rows) {
    const keywords = [
      'наименование', 'продукт', 'брутто', 'нетто', 'название', 'сырьё', 'ингредиент', 'расход сырья',
    ];
    for (var r = 0; r < rows.length && r < 50; r++) {
      final row = rows[r].map((c) => (c is String ? c : c.toString()).trim().toLowerCase()).toList();
      if (row.length < 2) continue;
      final hasKeyword = row.any((c) => keywords.any((k) => c.contains(k)));
      if (hasKeyword) {
        final sig = _headerSignature(rows[r].map((c) => (c is String ? c : c.toString()).trim().replaceAll(RegExp(r'\s+'), ' ')).toList());
        if (sig.isNotEmpty) return sig;
        break;
      }
    }
    return null;
  }

  /// Извлечь «Выход блюда (в граммах): 190» из rows (ГОСТ и др.) для подстановки в вес порции.
  static double? _extractYieldFromRows(List<List<String>> rows) {
    final yieldNum = RegExp(r'(\d{2,4})\s*г');
    final anyNum = RegExp(r'\b(\d{2,4})\b');
    for (var r = 0; r < rows.length && r < 80; r++) {
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final s = (row[c] is String ? row[c] as String : row[c].toString()).trim().toLowerCase();
        if (s.isEmpty) continue;
        if (s.contains('выход') && (s.contains('грамм') || s.contains('г)'))) {
          final m = yieldNum.firstMatch(s);
          if (m != null) {
            final n = double.tryParse(m.group(1) ?? '');
            if (n != null && n >= 10 && n <= 5000) return n;
          }
        }
        if (s.contains('выход блюда') || s.contains('выход готовой')) {
          final m = anyNum.firstMatch(s);
          if (m != null) {
            final n = double.tryParse(m.group(1) ?? '');
            if (n != null && n >= 10 && n <= 5000) return n;
          }
          for (var j = c + 1; j < row.length && j < c + 4; j++) {
            final next = (row[j] is String ? row[j] as String : row[j].toString()).trim();
            final nn = double.tryParse(next.replaceAll(',', '.'));
            if (nn != null && nn >= 10 && nn <= 5000) return nn;
          }
          // ГОСТ: число выхода часто в следующей строке
          if (r + 1 < rows.length) {
            for (var j = 0; j < (rows[r + 1]?.length ?? 0) && j < 5; j++) {
              final next = (rows[r + 1]![j] is String ? rows[r + 1]![j] as String : rows[r + 1]![j].toString()).trim();
              final nn = double.tryParse(next.replaceAll(',', '.'));
              if (nn != null && nn >= 10 && nn <= 5000) return nn;
            }
          }
        }
      }
    }
    return null;
  }

  /// Последняя ошибка при обучении (для диагностики).
  static String? lastLearningError;

  /// Обратный маппинг: по скорректированным данным находим источник в rows и сохраняем колонки.
  /// Вызывать после сохранения импорта — один раз со всеми карточками для голосования.
  static Future<void> learnColumnMappingFromCorrections(
    SupabaseClient client,
    List<List<String>> rows,
    String headerSignature,
    List<({
      String dishName,
      String? originalDishName,
      List<({String productName, double grossWeight, double netWeight})> ingredients,
      String? technologyText,
    })> correctedCards,
  ) async {
    if (rows.isEmpty || headerSignature.isEmpty || correctedCards.isEmpty) return;
    int headerIdx = -1;
    for (var r = 0; r < rows.length && r < 80; r++) {
      final sig = _headerSignature(rows[r].map((c) => (c is String ? c : c.toString()).trim()).toList());
      if (sig == headerSignature) {
        headerIdx = r;
        break;
      }
    }
    if (headerIdx < 0) return;

    int dishRowOffset = 0;
    int dishCol = 0;
    bool hasDish = false;
    final productColVotes = <int, int>{};
    final grossColVotes = <int, int>{};
    final netColVotes = <int, int>{};
    final technologyColVotes = <int, int>{};

    String _norm(String s) => stripIikoPrefix(s).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    bool _productMatch(String corrected, String cell) {
      final cn = _norm(corrected);
      final cellNorm = _norm(cell);
      if (cn.isEmpty || cellNorm.isEmpty) return false;
      return cn == cellNorm || cellNorm.contains(cn) || cn.contains(cellNorm);
    }
    bool _numMatches(double? parsed, double weight) {
      if (parsed == null || parsed <= 0) return false;
      if ((parsed - weight).abs() < 0.02) return true; // г
      if ((parsed * 1000 - weight).abs() < 2) return true; // кг
      return false;
    }

    for (final card in correctedCards) {
      final dishName = card.dishName.trim();
      final origName = card.originalDishName?.trim();
      for (final candidate in [dishName, if (origName != null && origName.isNotEmpty) origName]) {
        if (candidate.isEmpty) continue;
        for (var r = 0; r < rows.length && r < 80; r++) {
          final row = rows[r];
          for (var c = 0; c < row.length; c++) {
            final cell = (row[c] is String ? row[c] as String : row[c].toString()).trim();
            if (cell == candidate || cell.toLowerCase() == candidate.toLowerCase() || _productMatch(candidate, cell)) {
              dishRowOffset = r - headerIdx;
              dishCol = c;
              hasDish = true;
              break;
            }
          }
          if (hasDish) break;
        }
        if (hasDish) break;
      }

      for (final ing in card.ingredients) {
        final pName = ing.productName.trim();
        if (pName.isEmpty) continue;
        int? foundProductCol, foundGrossCol, foundNetCol;
        for (var r = headerIdx + 1; r < rows.length && r < headerIdx + 200; r++) {
          final row = rows[r];
          for (var c = 0; c < row.length; c++) {
            final cell = (row[c] is String ? row[c] as String : row[c].toString()).trim();
            if (!_productMatch(pName, cell)) continue;
            foundProductCol = c;
            for (var gc = 0; gc < row.length; gc++) {
              if (gc == c) continue;
              final pn = _parseNum(row[gc] is String ? row[gc] as String : row[gc].toString());
              if (_numMatches(pn, ing.grossWeight)) {
                foundGrossCol = gc;
                break;
              }
            }
            for (var nc = 0; nc < row.length; nc++) {
              if (nc == c) continue;
              final pn = _parseNum(row[nc] is String ? row[nc] as String : row[nc].toString());
              if (_numMatches(pn, ing.netWeight)) {
                foundNetCol = nc;
                break;
              }
            }
            break;
          }
          if (foundProductCol != null) break;
        }
        if (foundProductCol != null) {
          productColVotes[foundProductCol] = (productColVotes[foundProductCol] ?? 0) + 1;
          if (foundGrossCol != null) grossColVotes[foundGrossCol] = (grossColVotes[foundGrossCol] ?? 0) + 1;
          if (foundNetCol != null) netColVotes[foundNetCol] = (netColVotes[foundNetCol] ?? 0) + 1;
        }
      }

      // Колонка технологии: ищем ячейку, текст которой совпадает с пользовательской технологией
      final techText = card.technologyText?.trim();
      if (techText != null && techText.length >= 20) {
        final techNorm = _norm(techText);
        final techChunk = techNorm.length >= 40 ? techNorm.substring(0, 40) : techNorm;
        for (var r = headerIdx; r < rows.length && r < headerIdx + 200; r++) {
          final row = rows[r];
          for (var c = 0; c < row.length; c++) {
            final cell = (row[c] is String ? row[c] as String : row[c].toString()).trim();
            if (cell.length < 20) continue;
            final cellNorm = _norm(cell);
            if (techNorm.contains(cellNorm) || cellNorm.contains(techChunk)) {
              technologyColVotes[c] = (technologyColVotes[c] ?? 0) + 1;
              break;
            }
          }
        }
      }
    }

    int? bestProductCol;
    int? bestGrossCol;
    int? bestNetCol;
    if (productColVotes.isNotEmpty) {
      bestProductCol = productColVotes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    if (grossColVotes.isNotEmpty) {
      bestGrossCol = grossColVotes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    if (netColVotes.isNotEmpty) {
      bestNetCol = netColVotes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    int? bestTechnologyCol;
    if (technologyColVotes.isNotEmpty) {
      bestTechnologyCol = technologyColVotes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    try {
      final payload = <String, dynamic>{
        'header_signature': headerSignature,
        'dish_name_row_offset': hasDish ? dishRowOffset : 0,
        'dish_name_col': hasDish ? dishCol : 0,
      };
      if (bestProductCol != null) payload['product_col'] = bestProductCol;
      if (bestGrossCol != null) payload['gross_col'] = bestGrossCol;
      // Не перезаписываем net_col колонкой брутто (если пользователь не правил нетто — оба совпадают).
      if (bestNetCol != null && bestNetCol != bestGrossCol) payload['net_col'] = bestNetCol;
      if (bestTechnologyCol != null) payload['technology_col'] = bestTechnologyCol;
      if (!hasDish && bestProductCol == null && bestTechnologyCol == null) return; // нечего сохранять
      final res = await client.functions.invoke('tt-parse-save-learning', body: {'learned_dish_name': payload});
      if (res.status >= 200 && res.status < 300) {
        devLog('[tt_parse] learned columns: sig=$headerSignature product=$bestProductCol gross=$bestGrossCol net=$bestNetCol technology=$bestTechnologyCol');
      } else {
        final err = (res.data as Map?)?['error'] ?? res.data ?? 'HTTP ${res.status}';
        lastLearningError = err.toString();
        debugPrint('[tt_parse] learnColumnMapping failed: $err');
      }
    } catch (e, st) {
      lastLearningError = e.toString();
      devLog('[tt_parse] learnColumnMapping failed: $e\n$st');
    }
  }

  /// Сохранить правку (correction) через Edge Function. Вызывается из экранов импорта/редактирования.
  static Future<void> saveLearningCorrection({
    required String headerSignature,
    required String field,
    required String correctedValue,
    String? originalValue,
    String? establishmentId,
  }) async {
    lastLearningError = null;
    try {
      final client = Supabase.instance.client;
      final res = await client.functions.invoke('tt-parse-save-learning', body: {
        'correction': {
          'header_signature': headerSignature,
          'field': field,
          'original_value': originalValue,
          'corrected_value': correctedValue,
          'establishment_id': establishmentId,
        },
      });
      if (res.status >= 200 && res.status < 300) {
        devLog('[tt_parse] correction saved: $originalValue -> $correctedValue');
      } else {
        final err = (res.data as Map?)?['error'] ?? res.data ?? 'HTTP ${res.status}';
        lastLearningError = err.toString();
        debugPrint('[tt_parse] correction insert failed: $err');
      }
    } catch (e, st) {
      lastLearningError = e.toString();
      devLog('[tt_parse] correction insert failed: $e\n$st');
      debugPrint('[tt_parse] correction insert failed: $e');
    }
  }

  /// Применить сохранённые правки (original → corrected) к результатам парсинга.
  Future<List<TechCardRecognitionResult>> _applyParseCorrections(
    List<TechCardRecognitionResult> list,
    String? headerSignature,
    String? establishmentId,
  ) async {
    lastLearningError = null;
    if (headerSignature == null || headerSignature.isEmpty || list.isEmpty) return list;
    try {
      final raw = await _client
          .from('tt_parse_corrections')
          .select('original_value, corrected_value')
          .eq('header_signature', headerSignature)
          .eq('field', 'dish_name');
      final res = raw is List ? raw : (raw as dynamic).data as List? ?? [];
      if (res.isEmpty) return list;
      final map = <String, String>{};
      for (final r in res) {
        final orig = (r['original_value'] as String?)?.trim();
        final corr = (r['corrected_value'] as String?)?.trim();
        if (orig != null && orig.isNotEmpty && corr != null && corr.isNotEmpty && !map.containsKey(orig)) {
          map[orig] = corr;
        }
      }
      if (map.isEmpty) return list;
      return list.map((c) {
        final name = c.dishName?.trim();
        if (name == null || name.isEmpty) return c;
        final corrected = map[name];
        if (corrected == null) return c;
        return c.copyWith(dishName: corrected);
      }).toList();
    } catch (e, st) {
      lastLearningError = e.toString();
      devLog('[tt_parse] apply corrections: $e\n$st');
      debugPrint('[tt_parse] apply corrections: $e'); // В release тоже в консоль браузера
      return list;
    }
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

    void flushCard({double? yieldGrams}) {
      if (currentDish != null && (currentDish!.isNotEmpty || currentIngredients.isNotEmpty)) {
        results.add(TechCardRecognitionResult(
          dishName: currentDish,
          ingredients: List.from(currentIngredients),
          isSemiFinished: currentDish?.toLowerCase().contains('пф') ?? false,
          yieldGrams: yieldGrams,
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
        double? outG = _parseNum(outputVal);
        if (outG != null && outG > 0 && outG < 100) outG = outG * 1000;
        flushCard(yieldGrams: outG);
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
              !_isJunkProductName(shiftedProduct) &&
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
        if (!_isJunkProductName(productVal)) {
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
    }
    flushCard();
    return results;
  }

  /// Обучение: при правке ищем corrected в rows и сохраняем позиции (dish name + колонки).
  /// [correctedIngredients] — ингредиенты для вывода product_col, gross_col, net_col (опционально).
  /// [originalDishName] — исходное распознанное название (ищем его, если corrected не найден в rows).
  /// [technologyText] — технология (в т.ч. ручной ввод) — для маппинга technology_col.
  /// Устаревший вызов — делегирует в learnColumnMappingFromCorrections (обратная совместимость).
  static Future<void> learnDishNamePosition(
    SupabaseClient client,
    List<List<String>> rows,
    String headerSignature,
    String correctedDishName, {
    List<({String productName, double grossWeight, double netWeight})>? correctedIngredients,
    String? originalDishName,
    String? technologyText,
  }) async {
    await learnColumnMappingFromCorrections(
      client,
      rows,
      headerSignature,
      [(
        dishName: correctedDishName,
        originalDishName: originalDishName,
        ingredients: correctedIngredients ?? [],
        technologyText: technologyText,
      )],
    );
  }

  /// Валидация «на лету»: дичь в названии/ингредиентах — пользователь должен проверить.
  static List<TtkParseError>? _validateParsedCards(List<TechCardRecognitionResult> list) {
    final errors = <TtkParseError>[];
    final garbageDish = RegExp(r'органолептическ|внешний вид|консистенция|запах|вкус|цвет|показатели', caseSensitive: false);
    final numericOnly = RegExp(r'^[\d\s.,\-]+$');
    for (final c in list) {
      final name = c.dishName?.trim() ?? '';
      if (name.isNotEmpty && garbageDish.hasMatch(name)) {
        errors.add(TtkParseError(dishName: name, error: 'Название похоже на раздел ГОСТ. Проверьте и исправьте.'));
      }
      for (final i in c.ingredients) {
        final p = (i.productName).trim();
        if (p.isNotEmpty && numericOnly.hasMatch(p)) {
          errors.add(TtkParseError(dishName: name, error: 'Название продукта «$p» — число. Проверьте колонки.'));
        }
        final g = i.grossGrams;
        final n = i.netGrams;
        if (g != null && (g.isNaN || g.isInfinite || g < 0)) {
          errors.add(TtkParseError(dishName: name, error: 'Брутто содержит некорректное значение.'));
        }
        if (n != null && (n.isNaN || n.isInfinite || n < 0)) {
          errors.add(TtkParseError(dishName: name, error: 'Нетто содержит некорректное значение.'));
        }
      }
    }
    return errors.isEmpty ? null : errors;
  }

  /// Привести rows к гарантированному string[][] для JSON (Edge Function 400 при num/NaN).
  static List<List<String>> _rowsForJson(List<List<String>> rows) {
    return rows.map((r) => r.map((c) {
      final s = c.trim();
      if (s == 'NaN' || s == 'Infinity' || s == '-Infinity') return '';
      return s;
    }).toList()).toList();
  }

  /// Парсинг по шаблонам — через Edge Function (service_role). Без лимитов, без AI.
  /// Так надёжно работает независимо от сессии; иначе на 3-й загрузке упираемся в лимит AI.
  Future<List<TechCardRecognitionResult>> _tryParseByStoredTemplates(List<List<String>> rows) async {
    try {
      final safeRows = _rowsForJson(rows);
      final data = await invoke('parse-ttk-by-templates', {'rows': safeRows});
      if (data == null) return [];
      final sig = data['header_signature'] as String?;
      if (sig != null && sig.isNotEmpty) lastParseHeaderSignature = sig;
      final sanity = data['sanity_issues'];
      if (sanity is List) {
        final issues = sanity.whereType<String>().where((s) => s.isNotEmpty).toList();
        if (issues.isNotEmpty) {
          lastParseTechCardErrors = issues.map((msg) => TtkParseError(error: msg)).toList();
        }
      }
      final raw = data['cards'];
      if (raw is! List || raw.isEmpty) return [];
      lastParseWasFirstTimeFormat = false; // формат известен, шаблон сработал
      if (raw.isNotEmpty) {
        final c = raw.first as Map<String, dynamic>?;
        final ing = (c?['ingredients'] as List?)?.cast<Map<String, dynamic>>().take(5) ?? [];
        final g = ing.map((i) {
          final n = (i['productName'] ?? '').toString();
          return '${n.length > 15 ? n.substring(0, 15) : n}: ${i['grossGrams']}';
        }).join('; ');
        final net = ing.map((i) {
          final name = (i['productName'] ?? '').toString();
          return '${name.length > 15 ? name.substring(0, 15) : name}: ${i['netGrams']}';
        }).join('; ');
        debugPrint('[tt_parse] EF returned: ${raw.length} cards, first ingr grossGrams: $g');
        debugPrint('[tt_parse] EF first ingr netGrams: $net');
      }
      final list = <TechCardRecognitionResult>[];
      const headerWords = ['наименование', 'продукт', 'название', 'брутто', 'нетто', 'сырьё'];
      for (final e in raw) {
        if (e is! Map) continue;
        final card = _parseTechCardResult(Map<String, dynamic>.from(e as Map));
        if (card == null) continue;
        final dn = (card.dishName ?? '').trim().toLowerCase();
        final hasName = dn.isNotEmpty && !headerWords.any((w) => dn == w || dn.startsWith('$w '));
        final hasIng = card.ingredients.any((i) => (i.productName ?? '').trim().length > 2);
        if (hasName || hasIng) list.add(card);
      }
      return _applyEggGrossFix(list);
    } catch (e) {
      devLog('parse-ttk-by-templates: $e');
      return [];
    }
  }

  /// Сохранить обучение через Edge Function (service_role, обход RLS)
  Future<void> _saveLearningViaEdgeFunction(Map<String, dynamic> payload) async {
    try {
      final data = await invoke('tt-parse-save-learning', payload);
      if (data != null && data['ok'] == true) return;
      final err = data?['error']?.toString();
      final details = data?['details'];
      lastLearningError = err ?? (details is List
          ? details.map((e) => e.toString()).join('; ')
          : details?.toString()) ?? 'Unknown';
      debugPrint('[tt_parse] Edge Function save failed: $lastLearningError');
    } catch (e, st) {
      lastLearningError = e.toString();
      devLog('[tt_parse] Edge Function save error: $e\n$st');
      debugPrint('[tt_parse] Edge Function save error: $e');
    }
  }

  /// Сохранить шаблон при успешном парсинге по ключевым словам (без AI). Повторная загрузка — из каталога.
  /// База шаблонов (tt_parse_templates) растёт при каждой новой загрузке формата: если EF не нашёл шаблон,
  /// keyword/AI парсит → шаблон сохраняется. Правки пользователя на экране проверки → tt_parse_learned_dish_name
  /// и tt_parse_corrections. Так распознавание постоянно обучается и расширяется под разные варианты файлов.
  Future<void> _saveTemplateFromKeywordParse(List<List<String>> rows, String source) async {
    try {
      int headerIdx = -1;
      int nameCol = -1, productCol = -1, grossCol = -1, netCol = -1, wasteCol = -1, outputCol = -1;
      const nameKeys = ['наименование', 'название', 'блюдо', 'пф', 'name', 'dish'];
      const productKeys = ['продукт', 'сырьё', 'ингредиент', 'product', 'ingredient'];
      const grossKeys = ['брутто', 'бр', 'вес брутто', 'gross'];
      const netKeys = ['нетто', 'нт', 'вес нетто', 'net'];
      const wasteKeys = ['отход', 'отх', 'waste', 'процент отхода'];
      const outputKeys = ['выход', 'вес готового', 'готовый', 'output'];
      // Сканируем минимум 3 строки: ГОСТ 2-row header — «Брутто»/«Нетто» во второй строке.
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
        // Не выходить по первой строке: у ГОСТ «Брутто»/«Нетто» во второй строке.
        final hasNameOrProduct = headerIdx >= 0 && (nameCol >= 0 || productCol >= 0);
        final hasWeights = grossCol >= 0 || netCol >= 0;
        if (hasNameOrProduct && (hasWeights || r >= 2)) break;
      }
      if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) return;
      if (nameCol < 0) nameCol = 0;
      // ГОСТ 2-row: наименование и продукт в одной колонке — иначе при парсинге пропускается первая колонка с весом.
      if (productCol < 0) productCol = nameCol >= 0 ? nameCol : 1;
      final sig = _headerSignature(rows[headerIdx].map((c) => c.trim()).toList());
      if (sig.isEmpty) return;
      lastParseHeaderSignature = sig;
      await _saveLearningViaEdgeFunction({
        'template': {
          'header_signature': sig,
          'header_row_index': headerIdx,
          'name_col': nameCol,
          'product_col': productCol,
          'gross_col': grossCol >= 0 ? grossCol : -1,
          'net_col': netCol >= 0 ? netCol : -1,
          'waste_col': wasteCol >= 0 ? wasteCol : -1,
          'output_col': outputCol >= 0 ? outputCol : -1,
          'source': source,
        },
      });
      devLog('[tt_parse] template saved: sig=$sig (keyword)');
    } catch (_) {}
  }

  Future<void> _saveTemplateAfterAi(List<List<String>> rows, List<TechCardRecognitionResult> cards, String source) async {
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
      lastParseHeaderSignature = sig;
      await _saveLearningViaEdgeFunction({
        'template': {
          'header_signature': sig,
          'header_row_index': bestHeaderIdx,
          'name_col': bestProductCol,
          'product_col': bestProductCol,
          'gross_col': grossCol,
          'net_col': netCol,
          'waste_col': -1,
          'output_col': -1,
          'source': source,
        },
      });
      devLog('[tt_parse] template saved: sig=$sig (ai)');
    } catch (_) {}
  }

  /// После парсинга (в т.ч. из EF): яйца 1 шт брутто, 26 г нетто → 50 г брутто.
  static List<TechCardRecognitionResult> _applyEggGrossFix(List<TechCardRecognitionResult> list) {
    return list.map((card) {
      final fixed = card.ingredients.map((i) {
        final name = (i.productName ?? '').trim().toLowerCase();
        final gross = i.grossGrams;
        final net = i.netGrams;
        // Яйца: храним 50 г брутто (для веса), unit=шт — в UI покажем «1 шт», стоимость за 1 шт.
        if (name.contains('яйц') && gross == 1 && net != null && net >= 20 && net <= 60) {
          return TechCardIngredientLine(
            productName: i.productName,
            grossGrams: 50.0,
            netGrams: i.netGrams,
            outputGrams: i.outputGrams,
            unit: 'шт',
            cookingMethod: i.cookingMethod,
            primaryWastePct: i.primaryWastePct,
            cookingLossPct: i.cookingLossPct,
            ingredientType: i.ingredientType,
            pricePerKg: i.pricePerKg,
          );
        }
        return i;
      }).toList();
      return card.ingredients == fixed ? card : card.copyWith(ingredients: fixed);
    }).toList();
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
      yieldGrams: data['yieldGrams'] != null ? (data['yieldGrams'] as num).toDouble() : null,
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

