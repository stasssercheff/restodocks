import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_service.dart';
import 'nutrition_api_service.dart';

/// Реализация AiService через Supabase Edge Functions.
/// Требует: задеплоенные функции и секрет OPENAI_API_KEY в Supabase.
class AiServiceSupabase implements AiService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>?> invoke(String name, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(name, body: body);
      if (res.status != 200) {
        return null;
      }
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data.containsKey('error')) return null;
        return data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ParsedProductItem>> parseProductList({List<String>? rows, String? text}) async {
    final body = <String, dynamic>{};
    if (rows != null && rows.isNotEmpty) body['rows'] = rows;
    if (text != null && text.trim().isNotEmpty) body['text'] = text;
    final data = await invoke('ai-parse-product-list', body);
    if (data == null) return [];
    final raw = data['items'];
    if (raw is! List) return [];
    return raw.map((e) {
      if (e is! Map) return null;
      final m = Map<String, dynamic>.from(e as Map);
      return ParsedProductItem(
        name: (m['name'] as String?) ?? '',
        price: m['price'] != null ? (m['price'] as num).toDouble() : null,
        unit: m['unit'] as String?,
      );
    }).whereType<ParsedProductItem>().toList();
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
  Future<List<TechCardRecognitionResult>> parseTechCardsFromExcel(Uint8List xlsxBytes) async {
    try {
      final rows = _xlsxToRows(xlsxBytes);
      if (rows.isEmpty) return [];
      final data = await invoke('ai-recognize-tech-cards-batch', {'rows': rows});
      if (data == null) return [];
      final raw = data['cards'];
      if (raw is! List) return [];
      final list = <TechCardRecognitionResult>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final card = _parseTechCardResult(Map<String, dynamic>.from(e as Map));
        if (card != null && (card.dishName != null && card.dishName!.isNotEmpty || card.ingredients.isNotEmpty)) {
          list.add(card);
        }
      }
      return list;
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

  TechCardRecognitionResult? _parseTechCardResult(Map<String, dynamic>? data) {
    if (data == null) return null;
    final ingredients = <TechCardIngredientLine>[];
    final raw = data['ingredients'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e as Map);
        ingredients.add(TechCardIngredientLine(
          productName: (m['productName'] as String?) ?? '',
          grossGrams: m['grossGrams'] != null ? (m['grossGrams'] as num).toDouble() : null,
          netGrams: m['netGrams'] != null ? (m['netGrams'] as num).toDouble() : null,
          unit: m['unit'] as String?,
          cookingMethod: m['cookingMethod'] as String?,
          primaryWastePct: m['primaryWastePct'] != null ? (m['primaryWastePct'] as num).toDouble() : null,
          cookingLossPct: m['cookingLossPct'] != null ? (m['cookingLossPct'] as num).toDouble() : null,
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
    final body = <String, dynamic>{'productName': productName};
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

