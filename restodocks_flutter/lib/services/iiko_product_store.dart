import 'dart:convert';
import 'dart:typed_data';

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

  static const _kBlankBytesKey = 'iiko_blank_bytes_b64';
  static const _kQtyColKey     = 'iiko_blank_qty_col';

  /// Байты оригинального xlsx-бланка для экспорта (персистируются в localStorage).
  Uint8List? originalBlankBytes;

  /// Индекс колонки «Остаток фактический» в оригинальном бланке (0-based).
  int? originalQuantityColumnIndex;

  List<IikoProduct> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  bool get hasProducts => _products.isNotEmpty;
  String? get loadedEstablishmentId => _loadedEstablishmentId;

  /// Загружает байты бланка из localStorage если они ещё не в памяти.
  Future<void> restoreBlankFromStorage() async {
    if (originalBlankBytes != null) return; // уже в памяти
    try {
      final prefs = await SharedPreferences.getInstance();
      final b64 = prefs.getString(_kBlankBytesKey);
      if (b64 != null) {
        originalBlankBytes = base64Decode(b64);
        originalQuantityColumnIndex = prefs.getInt(_kQtyColKey);
        debugPrint('IikoProductStore: blank restored from localStorage '
            '(${originalBlankBytes!.length} bytes, qtyCol=$originalQuantityColumnIndex)');
      }
    } catch (e) {
      debugPrint('IikoProductStore.restoreBlankFromStorage error: $e');
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
      debugPrint('IikoProductStore: blank saved to localStorage '
          '(${bytes.length} bytes, qtyCol=$qtyCol)');
    } catch (e) {
      debugPrint('IikoProductStore._persistBlank error: $e');
    }
  }

  Future<void> _clearPersistedBlank() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kBlankBytesKey);
      await prefs.remove(_kQtyColKey);
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
    } catch (e) {
      debugPrint('IikoProductStore.loadProducts error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> replaceAll(
    String establishmentId,
    List<IikoProduct> items, {
    Uint8List? blankBytes,
    int? quantityColumnIndex,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      if (blankBytes != null) {
        originalBlankBytes = blankBytes;
        originalQuantityColumnIndex = quantityColumnIndex;
        // Сохраняем байты бланка в localStorage — переживают перезагрузку страницы
        await _persistBlank(blankBytes, quantityColumnIndex);
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
    _clearPersistedBlank();
    notifyListeners();
  }
}
