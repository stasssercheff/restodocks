import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dev_log.dart';
import 'establishment_local_hydration_service.dart';
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

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

    if (!kIsWeb) {
      _connectivitySub?.cancel();
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        (results) {
          final online = results.any((r) => r != ConnectivityResult.none);
          if (!online) return;
          _scheduleSync('connectivity');
        },
        onError: (_) => _scheduleSync('connectivity_error'),
      );
    }
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
    await _connectivitySub?.cancel();
    _connectivitySub = null;
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
      try {
        await _products.loadProducts(force: false);
        if (dataEstablishmentId == establishmentId) {
          await _products.loadNomenclature(establishmentId);
        } else {
          await _products.loadNomenclatureForBranch(
              establishmentId, dataEstablishmentId);
        }
      } catch (e) {
        devLog('RealtimeSyncService.syncNow($reason) catalog/nom: $e');
      }
      unawaited(_techCards.refreshTechCardsFromServer(dataEstablishmentId));
      if (!kIsWeb) {
        unawaited(
          EstablishmentLocalHydrationService.instance.runSnapshotsOnlySync(
            establishmentId: establishmentId,
            dataEstablishmentId: dataEstablishmentId,
          ),
        );
      }
    } finally {
      _syncInProgress = false;
    }
  }
}
