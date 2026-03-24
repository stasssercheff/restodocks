import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dev_log.dart';
import 'product_store_supabase.dart';
import 'tech_card_service_supabase.dart';

/// Фоновая синхронизация данных:
/// - offline-first (UI использует локальный кэш),
/// - realtime-подписки на изменения в БД,
/// - периодический sync как fallback после восстановления сети.
class RealtimeSyncService {
  static final RealtimeSyncService _instance = RealtimeSyncService._internal();
  factory RealtimeSyncService() => _instance;
  RealtimeSyncService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  final ProductStoreSupabase _products = ProductStoreSupabase();
  final TechCardServiceSupabase _techCards = TechCardServiceSupabase();

  Timer? _periodicTimer;
  Timer? _debounceTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _techCardsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _productsSub;

  String? _activeEstablishmentId;
  String? _activeDataEstablishmentId;
  bool _syncInProgress = false;

  Future<void> startForEstablishment({
    required String establishmentId,
    required String dataEstablishmentId,
  }) async {
    final sameBinding = _activeEstablishmentId == establishmentId &&
        _activeDataEstablishmentId == dataEstablishmentId;
    if (sameBinding) return;

    await stop();
    _activeEstablishmentId = establishmentId;
    _activeDataEstablishmentId = dataEstablishmentId;

    // Первая синхронизация сразу при входе/переключении заведения.
    unawaited(syncNow(reason: 'initial_bind'));

    // Realtime: изменения ТТК по текущему dataEstablishment.
    _techCardsSub = _client
        .from('tech_cards')
        .stream(primaryKey: ['id'])
        .eq('establishment_id', dataEstablishmentId)
        .listen(
          (_) => _scheduleSync('realtime_tech_cards'),
          onError: (_) => _scheduleSync('realtime_tech_cards_error'),
        );

    // Realtime: изменения продуктов (глобальный справочник).
    _productsSub = _client.from('products').stream(primaryKey: ['id']).listen(
      (_) => _scheduleSync('realtime_products'),
      onError: (_) => _scheduleSync('realtime_products_error'),
    );

    // Fallback, если realtime/сеть временно недоступны.
    _periodicTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _scheduleSync('periodic');
    });
  }

  Future<void> stop() async {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _techCardsSub?.cancel();
    _techCardsSub = null;
    await _productsSub?.cancel();
    _productsSub = null;
    _activeEstablishmentId = null;
    _activeDataEstablishmentId = null;
  }

  void _scheduleSync(String reason) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(syncNow(reason: reason));
    });
  }

  Future<void> syncNow({String reason = 'manual'}) async {
    final establishmentId = _activeEstablishmentId;
    final dataEstablishmentId = _activeDataEstablishmentId;
    if (establishmentId == null || dataEstablishmentId == null) return;
    if (_syncInProgress) return;

    _syncInProgress = true;
    try {
      await _products.loadProducts(force: true);
      if (dataEstablishmentId == establishmentId) {
        await _products.loadNomenclature(establishmentId);
      } else {
        await _products.loadNomenclatureForBranch(
            establishmentId, dataEstablishmentId);
      }
      await _techCards.refreshTechCardsFromServer(dataEstablishmentId);
    } catch (e) {
      // Не валим приложение при плохой сети: продолжаем работать с локальным кэшем.
      devLog('RealtimeSyncService.syncNow($reason) failed: $e');
    } finally {
      _syncInProgress = false;
    }
  }
}
