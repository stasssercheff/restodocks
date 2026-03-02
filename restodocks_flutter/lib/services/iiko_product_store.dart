import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/iiko_product.dart';

/// Хранилище iiko-продуктов. Использует RPC-функции вместо прямых запросов
/// к таблице, чтобы обойти возможные проблемы с кэшем схемы PostgREST.
class IikoProductStore extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<IikoProduct> _products = [];
  String? _loadedEstablishmentId;
  bool _isLoading = false;

  static const _kBlankBytesKey   = 'iiko_blank_bytes_b64';
  static const _kQtyColKey       = 'iiko_blank_qty_col';
  static const _kSheetNamesKey   = 'iiko_blank_sheet_names';
  static const _kSheetQtyColsKey = 'iiko_blank_sheet_qty_cols';
  static const _kStorageBucket   = 'iiko-blanks';

  /// Байты оригинального xlsx-бланка для экспорта (персистируются в localStorage + Supabase Storage).
  Uint8List? originalBlankBytes;

  /// Индекс колонки «Остаток фактический» в оригинальном бланке (0-based) — для первого листа.
  int? originalQuantityColumnIndex;

  /// Упорядоченный список имён листов бланка (пуст если бланк не загружен или лист один).
  List<String> sheetNames = [];

  /// Индекс колонки qty для каждого листа: { sheetName → colIndex }.
  Map<String, int> sheetQtyColumns = {};

  List<IikoProduct> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  bool get hasProducts => _products.isNotEmpty;
  String? get loadedEstablishmentId => _loadedEstablishmentId;

  /// Загружает байты бланка: сначала localStorage, потом Supabase Storage.
  /// Вызывается перед экспортом и при загрузке iiko-экрана.
  Future<void> restoreBlankFromStorage({String? establishmentId}) async {
    // Если байты уже есть, но sheetNames пусты — восстанавливаем метаданные
    if (originalBlankBytes != null) {
      if (sheetNames.isEmpty) {
        await _restoreSheetNamesOnly();
      }
      // Если продукты загружены без sheetName — проставляем из бланка
      if (_products.isNotEmpty && _products.every((p) => p.sheetName == null)) {
        await _assignSheetNamesInMemory();
        notifyListeners();
      }
      return;
    }

    // 1) localStorage (быстро, работает без сети)
    try {
      final prefs = await SharedPreferences.getInstance();
      final b64 = prefs.getString(_kBlankBytesKey);
      if (b64 != null) {
        originalBlankBytes = base64Decode(b64);
        originalQuantityColumnIndex = prefs.getInt(_kQtyColKey);
        // Восстанавливаем имена листов и колонки
        final sheetNamesJson = prefs.getString(_kSheetNamesKey);
        if (sheetNamesJson != null) {
          sheetNames = (jsonDecode(sheetNamesJson) as List).cast<String>();
        }
        final sheetQtyColsJson = prefs.getString(_kSheetQtyColsKey);
        if (sheetQtyColsJson != null) {
          sheetQtyColumns = (jsonDecode(sheetQtyColsJson) as Map)
              .map((k, v) => MapEntry(k as String, v as int));
        }
        debugPrint('IikoProductStore: blank restored from localStorage '
            '(${originalBlankBytes!.length} bytes, qtyCol=$originalQuantityColumnIndex, sheets=${sheetNames.length})');
        // Если продукты уже загружены но без sheetName — проставляем из бланка
        if (_products.isNotEmpty && _products.every((p) => p.sheetName == null)) {
          await _assignSheetNamesInMemory();
        }
        notifyListeners(); // обновляем вкладки листов в UI
        return;
      }
    } catch (e) {
      debugPrint('IikoProductStore.restoreBlankFromStorage(local) error: $e');
    }

    // 2) Supabase Storage (инкогнито / другое устройство)
    final estId = establishmentId ?? _loadedEstablishmentId;
    if (estId == null) return;
    await _restoreBlankFromServer(estId);
    // Если продукты уже загружены но без sheetName — проставляем из бланка
    if (_products.isNotEmpty && _products.every((p) => p.sheetName == null)) {
      await _assignSheetNamesInMemory();
    }
    notifyListeners(); // обновляем вкладки листов после загрузки с сервера
  }

  /// Скачивает бланк с Supabase Storage и сохраняет в память + localStorage.
  Future<void> _restoreBlankFromServer(String establishmentId) async {
    try {
      // Читаем метаданные (индекс колонки, имена листов, qty-колонки)
      final meta = await _supabase
          .from('iiko_blank_meta')
          .select('qty_col_index, sheet_names, sheet_qty_cols')
          .eq('establishment_id', establishmentId)
          .maybeSingle();
      if (meta == null) return;

      final storagePath = '$establishmentId/blank.xlsx';
      final bytes = await _supabase.storage
          .from(_kStorageBucket)
          .download(storagePath);

      originalBlankBytes = Uint8List.fromList(bytes);
      originalQuantityColumnIndex = meta['qty_col_index'] as int?;

      // Восстанавливаем имена листов из метаданных
      final sheetNamesRaw = meta['sheet_names'];
      if (sheetNamesRaw is List) {
        sheetNames = sheetNamesRaw.cast<String>();
      }
      final sheetQtyColsRaw = meta['sheet_qty_cols'];
      if (sheetQtyColsRaw is Map) {
        sheetQtyColumns = sheetQtyColsRaw.map((k, v) => MapEntry(k as String, v as int));
      }

      // Кэшируем в localStorage
      await _persistBlank(originalBlankBytes!, originalQuantityColumnIndex);
      debugPrint('IikoProductStore: blank restored from Supabase Storage '
          '(${originalBlankBytes!.length} bytes, qtyCol=$originalQuantityColumnIndex, sheets=${sheetNames.length})');
    } catch (e) {
      debugPrint('IikoProductStore._restoreBlankFromServer error: $e');
    }
  }

  Future<void> _persistBlank(Uint8List bytes, int? qtyCol) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBlankBytesKey, base64Encode(bytes));
      if (qtyCol != null) {
        await prefs.setInt(_kQtyColKey, qtyCol);
      } else {
        await prefs.remove(_kQtyColKey);
      }
      // Сохраняем имена листов и колонки
      if (sheetNames.isNotEmpty) {
        await prefs.setString(_kSheetNamesKey, jsonEncode(sheetNames));
        await prefs.setString(_kSheetQtyColsKey, jsonEncode(sheetQtyColumns));
      } else {
        await prefs.remove(_kSheetNamesKey);
        await prefs.remove(_kSheetQtyColsKey);
      }
      debugPrint('IikoProductStore: blank saved to localStorage '
          '(${bytes.length} bytes, qtyCol=$qtyCol, sheets=${sheetNames.length})');
    } catch (e) {
      debugPrint('IikoProductStore._persistBlank error: $e');
    }
  }

  /// Загружает байты бланка в Supabase Storage и сохраняет метаданные.
  Future<void> _uploadBlankToServer(
      String establishmentId, Uint8List bytes, int? qtyCol) async {
    try {
      final storagePath = '$establishmentId/blank.xlsx';
      await _supabase.storage
          .from(_kStorageBucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              upsert: true,
            ),
          );
      // Сохраняем / обновляем метаданные
      await _supabase.from('iiko_blank_meta').upsert(
        {
          'establishment_id': establishmentId,
          'storage_path': storagePath,
          'qty_col_index': qtyCol ?? 5,
          'sheet_names': sheetNames.isEmpty ? null : sheetNames,
          'sheet_qty_cols': sheetQtyColumns.isEmpty ? null : sheetQtyColumns,
          'uploaded_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'establishment_id',
      );
      debugPrint('IikoProductStore: blank uploaded to Supabase Storage ($storagePath)');
    } catch (e) {
      debugPrint('IikoProductStore._uploadBlankToServer error: $e');
    }
  }

  /// Восстанавливает только sheetNames/sheetQtyColumns из localStorage или Supabase
  /// когда байты бланка уже есть в памяти, но метаданные листов утеряны.
  Future<void> _restoreSheetNamesOnly() async {
    // Сначала пробуем localStorage
    try {
      final prefs = await SharedPreferences.getInstance();
      final sheetNamesJson = prefs.getString(_kSheetNamesKey);
      if (sheetNamesJson != null) {
        sheetNames = (jsonDecode(sheetNamesJson) as List).cast<String>();
        final sheetQtyColsJson = prefs.getString(_kSheetQtyColsKey);
        if (sheetQtyColsJson != null) {
          sheetQtyColumns = (jsonDecode(sheetQtyColsJson) as Map)
              .map((k, v) => MapEntry(k as String, v as int));
        }
        if (sheetNames.isNotEmpty) {
          debugPrint('IikoProductStore: sheetNames restored from localStorage: $sheetNames');
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('IikoProductStore._restoreSheetNamesOnly(local) error: $e');
    }
    // Если в localStorage нет — читаем из Supabase метаданные
    final estId = _loadedEstablishmentId;
    if (estId == null) return;
    try {
      final meta = await _supabase
          .from('iiko_blank_meta')
          .select('sheet_names, sheet_qty_cols')
          .eq('establishment_id', estId)
          .maybeSingle();
      if (meta == null) return;
      final sheetNamesRaw = meta['sheet_names'];
      if (sheetNamesRaw is List) {
        sheetNames = sheetNamesRaw.cast<String>();
      }
      final sheetQtyColsRaw = meta['sheet_qty_cols'];
      if (sheetQtyColsRaw is Map) {
        sheetQtyColumns =
            sheetQtyColsRaw.map((k, v) => MapEntry(k as String, v as int));
      }
      debugPrint('IikoProductStore: sheetNames restored from Supabase: $sheetNames');
      notifyListeners();
    } catch (e) {
      debugPrint('IikoProductStore._restoreSheetNamesOnly(server) error: $e');
    }
  }

  Future<void> _clearPersistedBlank() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kBlankBytesKey);
      await prefs.remove(_kQtyColKey);
      await prefs.remove(_kSheetNamesKey);
      await prefs.remove(_kSheetQtyColsKey);
    } catch (_) {}
  }

  Future<void> loadProducts(String establishmentId, {bool force = false}) async {
    if (!force && _loadedEstablishmentId == establishmentId && _products.isNotEmpty) return;
    _isLoading = true;
    notifyListeners();
    try {
      final data = await _supabase.rpc(
        'get_iiko_products',
        params: {'p_establishment_id': establishmentId},
      );
      _products = (data as List)
          .map((e) => IikoProduct.fromJson(e as Map<String, dynamic>))
          .toList();
      _loadedEstablishmentId = establishmentId;

      // Если у продуктов нет sheetName — восстанавливаем из бланка in-memory.
      // Это нужно как для старых данных (sheetName=NULL в БД), так и для случая
      // когда sheetNames ещё не были сохранены в localStorage.
      if (_products.isNotEmpty && _products.every((p) => p.sheetName == null)) {
        await _assignSheetNamesInMemory();
      }
    } catch (e) {
      debugPrint('IikoProductStore.loadProducts error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Читает бланк и проставляет sheetName для каждого продукта in-memory.
  /// Также заполняет sheetNames если они ещё не были восстановлены.
  Future<void> _assignSheetNamesInMemory() async {
    if (originalBlankBytes == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final b64 = prefs.getString(_kBlankBytesKey);
        if (b64 != null) originalBlankBytes = base64Decode(b64);
      } catch (_) {}
    }
    if (originalBlankBytes == null) return;

    try {
      final excel = Excel.decodeBytes(originalBlankBytes!.toList());
      // Строим карту: код → sheetName
      final codeToSheet = <String, String>{};
      final foundSheets = <String>[];

      for (final sName in excel.tables.keys) {
        final sheet = excel.tables[sName];
        if (sheet == null) continue;
        // Ищем колонку кода (первые 20 строк)
        int codeCol = 2;
        for (var r = 0; r < sheet.maxRows && r < 20; r++) {
          for (var c = 0; c < (sheet.maxColumns > 15 ? 15 : sheet.maxColumns); c++) {
            final v = _excelCellStr(sheet, r, c).toLowerCase();
            if (v == 'код' || v == 'code') { codeCol = c; break; }
          }
        }
        var hasProducts = false;
        for (var r = 0; r < sheet.maxRows; r++) {
          final code = _excelCellStr(sheet, r, codeCol).trim();
          if (code.isNotEmpty) {
            codeToSheet[code] = sName;
            hasProducts = true;
          }
        }
        if (hasProducts) foundSheets.add(sName);
      }

      if (codeToSheet.isEmpty) return;

      // Заполняем sheetNames если пусты
      if (sheetNames.length <= 1 && foundSheets.length > 1) {
        sheetNames = foundSheets;
        debugPrint('IikoProductStore: restored sheetNames from blank: $sheetNames');
      }

      _products = _products.map((p) {
        final s = p.code != null ? codeToSheet[p.code!.trim()] : null;
        return s != null ? p.copyWith(sheetName: s) : p;
      }).toList();
      debugPrint('IikoProductStore: assigned sheetName in-memory for '
          '${_products.where((p) => p.sheetName != null).length}/${_products.length} products');
    } catch (e) {
      debugPrint('IikoProductStore._assignSheetNamesInMemory error: $e');
    }
  }

  static String _excelCellStr(Sheet sheet, int row, int col) {
    try {
      final v = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value;
      if (v == null) return '';
      if (v is TextCellValue) return v.value.toString().trim();
      if (v is IntCellValue) return v.value.toString();
      if (v is DoubleCellValue) return v.value.toString();
      return v.toString().trim();
    } catch (_) { return ''; }
  }

  Future<void> replaceAll(
    String establishmentId,
    List<IikoProduct> items, {
    Uint8List? blankBytes,
    int? quantityColumnIndex,
    List<String>? newSheetNames,
    Map<String, int>? newSheetQtyColumns,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      if (blankBytes != null) {
        originalBlankBytes = blankBytes;
        originalQuantityColumnIndex = quantityColumnIndex;
        if (newSheetNames != null) sheetNames = newSheetNames;
        if (newSheetQtyColumns != null) sheetQtyColumns = newSheetQtyColumns;
        // Сохраняем в localStorage (быстро)
        await _persistBlank(blankBytes, quantityColumnIndex);
        // Сохраняем в Supabase Storage (работает в инкогнито и на других устройствах)
        await _uploadBlankToServer(establishmentId, blankBytes, quantityColumnIndex);
      }

      // Удаляем старые через rpc
      await _supabase.rpc(
        'delete_iiko_products',
        params: {'p_establishment_id': establishmentId},
      );

      // Вставляем все за один RPC-вызов — батчинг по 50 иногда тихо обрывался
      // после первого батча из-за особенностей Supabase Dart SDK
      const batchSize = 100;
      for (var i = 0; i < items.length; i += batchSize) {
        final batch = items.skip(i).take(batchSize).toList();
        final jsonItems = batch.map((p) => p.toJson()..remove('id')).toList();
        try {
          await _supabase.rpc(
            'insert_iiko_products',
            params: {'p_items': jsonItems},
          );
          debugPrint('IikoProductStore: batch ${i ~/ batchSize + 1} OK (${batch.length} items)');
        } catch (batchErr) {
          debugPrint('IikoProductStore: batch ${i ~/ batchSize + 1} failed: $batchErr');
          // Если батч не прошёл — пробуем по одной записи
          for (final p in batch) {
            try {
              await _supabase.rpc(
                'insert_iiko_products',
                params: {'p_items': [p.toJson()..remove('id')]},
              );
            } catch (singleErr) {
              debugPrint('IikoProductStore: single insert failed: ${p.code} — $singleErr');
            }
          }
        }
      }

      await loadProducts(establishmentId, force: true);
    } catch (e) {
      debugPrint('IikoProductStore.replaceAll error: $e');
      // Не rethrow — даже при частичной ошибке загружаем что вставили
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Удаляет все iiko-продукты заведения из базы и сбрасывает локальное состояние.
  Future<void> deleteAll(String establishmentId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _supabase.rpc(
        'delete_iiko_products',
        params: {'p_establishment_id': establishmentId},
      );
      _products = [];
      _loadedEstablishmentId = null;
      originalBlankBytes = null;
      originalQuantityColumnIndex = null;
      sheetNames = [];
      sheetQtyColumns = {};
      await _clearPersistedBlank();
    } catch (e) {
      debugPrint('IikoProductStore.deleteAll error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _products = [];
    _loadedEstablishmentId = null;
    originalBlankBytes = null;
    originalQuantityColumnIndex = null;
    sheetNames = [];
    sheetQtyColumns = {};
    _clearPersistedBlank();
    notifyListeners();
  }
}
