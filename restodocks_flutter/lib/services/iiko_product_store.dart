import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/iiko_product.dart';

/// Хранилище iiko-продуктов (отдельная номенклатура для инвентаризации iiko).
/// Не связано с основными products / establishment_products.
class IikoProductStore extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<IikoProduct> _products = [];
  String? _loadedEstablishmentId;
  bool _isLoading = false;

  /// Байты оригинального xlsx-бланка — хранятся в памяти для экспорта.
  /// При следующей загрузке нового бланка перезаписываются.
  Uint8List? originalBlankBytes;

  /// Индекс колонки «Остаток фактический» в оригинальном бланке (0-based).
  int? originalQuantityColumnIndex;

  List<IikoProduct> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  bool get hasProducts => _products.isNotEmpty;
  String? get loadedEstablishmentId => _loadedEstablishmentId;

  /// Загружает iiko-продукты для заведения. Если уже загружены — пропускает (если не force).
  Future<void> loadProducts(String establishmentId, {bool force = false}) async {
    if (!force && _loadedEstablishmentId == establishmentId && _products.isNotEmpty) return;
    _isLoading = true;
    notifyListeners();
    try {
      final data = await _supabase
          .from('iiko_products')
          .select()
          .eq('establishment_id', establishmentId)
          .order('sort_order')
          .order('name');
      _products = (data as List).map((e) => IikoProduct.fromJson(e as Map<String, dynamic>)).toList();
      _loadedEstablishmentId = establishmentId;
    } catch (e) {
      debugPrint('IikoProductStore.loadProducts error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Полная замена iiko-продуктов для заведения (при загрузке нового бланка).
  /// [blankBytes] — байты оригинального xlsx-файла для последующего экспорта.
  /// [quantityColumnIndex] — индекс колонки «Остаток фактический» (0-based).
  Future<void> replaceAll(
    String establishmentId,
    List<IikoProduct> items, {
    Uint8List? blankBytes,
    int? quantityColumnIndex,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Сохраняем оригинальный файл в памяти
      if (blankBytes != null) {
        originalBlankBytes = blankBytes;
        originalQuantityColumnIndex = quantityColumnIndex;
      }

      // Удаляем старые
      await _supabase.from('iiko_products').delete().eq('establishment_id', establishmentId);
      // Вставляем новые пачками по 200
      const batchSize = 200;
      for (var i = 0; i < items.length; i += batchSize) {
        final batch = items.skip(i).take(batchSize).toList();
        await _supabase.from('iiko_products').insert(
              batch.map((p) => p.toJson()..remove('id')).toList(),
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

  /// Очистить кэш (при выходе из заведения).
  void clear() {
    _products = [];
    _loadedEstablishmentId = null;
    originalBlankBytes = null;
    originalQuantityColumnIndex = null;
    notifyListeners();
  }
}
