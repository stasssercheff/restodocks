import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/iiko_product.dart';

/// Хранилище iiko-продуктов. Использует RPC-функции вместо прямых запросов
/// к таблице, чтобы обойти возможные проблемы с кэшем схемы PostgREST.
class IikoProductStore extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<IikoProduct> _products = [];
  String? _loadedEstablishmentId;
  bool _isLoading = false;

  /// Байты оригинального xlsx-бланка для экспорта.
  Uint8List? originalBlankBytes;

  /// Индекс колонки «Остаток фактический» в оригинальном бланке (0-based).
  int? originalQuantityColumnIndex;

  List<IikoProduct> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  bool get hasProducts => _products.isNotEmpty;
  String? get loadedEstablishmentId => _loadedEstablishmentId;

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
      }

      // Удаляем старые через rpc
      await _supabase.rpc(
        'delete_iiko_products',
        params: {'p_establishment_id': establishmentId},
      );

      // Вставляем новые пачками по 200 через rpc
      const batchSize = 200;
      for (var i = 0; i < items.length; i += batchSize) {
        final batch = items.skip(i).take(batchSize).toList();
        final jsonItems = batch.map((p) => p.toJson()..remove('id')).toList();
        await _supabase.rpc(
          'insert_iiko_products',
          params: {'p_items': jsonItems},
        );
      }

      await loadProducts(establishmentId, force: true);
    } catch (e) {
      debugPrint('IikoProductStore.replaceAll error: $e');
      rethrow;
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
    notifyListeners();
  }
}
