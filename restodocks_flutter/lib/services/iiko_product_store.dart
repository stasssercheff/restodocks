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
  Future<void> replaceAll(String establishmentId, List<IikoProduct> items) async {
    _isLoading = true;
    notifyListeners();
    try {
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
    notifyListeners();
  }
}
