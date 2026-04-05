import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/router/app_router.dart';
import '../models/models.dart';
import '../utils/dev_log.dart';
import 'account_manager_supabase.dart';
import 'documentation_service_supabase.dart';
import 'establishment_fiscal_settings_service.dart';
import 'haccp_config_service.dart';
import 'iiko_product_store.dart';
import 'local_snapshot_store.dart';
import 'menu_stop_go_service.dart';
import 'offline_cache_service.dart';
import 'pos_dining_layout_service.dart';
import 'product_store_supabase.dart';
import 'sales_plan_storage_service.dart';
import 'schedule_storage_service.dart';
import 'supabase_service.dart';
import 'tech_card_service_supabase.dart';

/// Полная выгрузка данных заведения в локальные кэши (фоном) и периодическое обновление.
/// Тяжёлый jsonEncode для SQLite — в отдельном isolate (не блокирует UI).
///
/// [runBackgroundDeltaSync] на мобильных реже перекачивает весь каталог (длинный TTL);
/// чаще обновляются «лёгкие» сущности — сеть после офлайна не должна тянуть 100% данных каждый раз.
class EstablishmentLocalHydrationService {
  EstablishmentLocalHydrationService._();
  static final EstablishmentLocalHydrationService instance =
      EstablishmentLocalHydrationService._();

  final OfflineCacheService _offlineCache = OfflineCacheService();
  final LocalSnapshotStore _snapshots = LocalSnapshotStore.instance;
  final SupabaseService _supabase = SupabaseService();

  bool _fullHydrationRunning = false;
  Timer? _periodicTimer;
  DateTime? _lastDeltaAt;

  static const _productsCacheDataset = 'products_all';
  static const _nomenclatureCacheDataset = 'nomenclature';
  static const _deltaMinInterval = Duration(minutes: 8);

  void ensurePeriodicSyncStarted() {
    if (_periodicTimer != null) return;
    _periodicTimer = Timer.periodic(const Duration(minutes: 12), (_) {
      unawaited(runBackgroundDeltaSync());
    });
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<String> _encodeLarge(Object? data) async {
    if (kIsWeb) return jsonEncode(data);
    try {
      return await Isolate.run(() => jsonEncode(data));
    } catch (_) {
      return jsonEncode(data);
    }
  }

  /// [includeCatalog]: false — если каталог и номенклатура уже загружены вызывающим кодом (избегаем дубля).
  Future<void> runFullHydration({
    required String establishmentId,
    required String dataEstablishmentId,
    required ProductStoreSupabase productStore,
    Establishment? establishment,
    bool includeCatalog = true,
  }) async {
    if (_fullHydrationRunning) return;
    final acc = AccountManagerSupabase();
    if (!acc.isLoggedInSync) return;

    _fullHydrationRunning = true;
    try {
      await Future<void>.delayed(Duration.zero);
      devLog(
          'EstablishmentLocalHydration: full sync start $establishmentId (catalog=$includeCatalog)');

      final futures = <Future<void>>[
        if (includeCatalog) productStore.loadProducts(force: true),
        if (includeCatalog) productStore.loadNomenclatureForce(dataEstablishmentId),
        _hydrateEmployees(establishmentId),
        _hydrateDocuments(establishmentId),
        loadSchedule(establishmentId),
        _prefetchOrderListsPrefs(establishmentId),
        _hydrateChecklistsSnapshot(establishmentId),
        _hydrateTechCards(dataEstablishmentId),
        _hydrateHaccp(establishmentId),
        _hydratePosTables(establishmentId),
        _hydrateMenuStopGo(establishmentId),
        _hydrateSalesPlans(establishmentId),
        _hydrateFiscal(establishmentId),
        _hydrateInventoryDrafts(establishmentId),
      ];
      if (!kIsWeb) {
        futures.add(_hydrateIikoIfPossible(establishmentId));
      }
      if (includeCatalog &&
          establishment != null &&
          establishment.isBranch &&
          establishment.parentEstablishmentId != null &&
          establishment.parentEstablishmentId!.isNotEmpty) {
        futures.add(
          productStore.loadNomenclatureForBranch(
            establishment.id,
            establishment.dataEstablishmentId,
          ),
        );
      }

      await Future.wait(
        futures.map(
          (f) => f.catchError((Object e, StackTrace st) {
            devLog('EstablishmentLocalHydration: task error $e');
          }),
        ),
      );

      await _touchProductCaches(dataEstablishmentId);
      await _mirrorEmployeesToSqlite(establishmentId);

      devLog('EstablishmentLocalHydration: full sync done $establishmentId');
    } finally {
      _fullHydrationRunning = false;
    }
  }

  Future<void> _touchProductCaches(String dataEstablishmentId) async {
    try {
      final pk = await _offlineCache.scopedKey(
        dataset: _productsCacheDataset,
        establishmentId: 'global',
      );
      await _offlineCache.touchKey(pk);
      final nk = await _offlineCache.scopedKey(
        dataset: _nomenclatureCacheDataset,
        establishmentId: dataEstablishmentId,
        suffix: 'main',
      );
      await _offlineCache.touchKey(nk);
    } catch (e) {
      devLog('EstablishmentLocalHydration: touch caches $e');
    }
  }

  Future<void> _mirrorEmployeesToSqlite(String establishmentId) async {
    if (kIsWeb) return;
    try {
      final acc = AccountManagerSupabase();
      final list = await acc.getEmployeesForEstablishment(establishmentId);
      final raw = list.map((e) => e.toJson()).toList();
      await _snapshots.put(
        '$establishmentId:employees',
        await _encodeLarge(raw),
      );
    } catch (e) {
      devLog('EstablishmentLocalHydration: sqlite employees $e');
    }
  }

  Future<void> _hydrateEmployees(String establishmentId) async {
    await AccountManagerSupabase().getEmployeesForEstablishment(establishmentId);
  }

  Future<void> _hydrateDocuments(String establishmentId) async {
    await DocumentationServiceSupabase().prefetchDocumentsCacheForMobile(establishmentId);
  }

  Future<void> _prefetchOrderListsPrefs(String establishmentId) async {
    try {
      final res = await _supabase.client
          .from('establishment_order_list_data')
          .select('data')
          .eq('establishment_id', establishmentId)
          .maybeSingle();
      if (res == null || res['data'] == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'restodocks_order_lists_$establishmentId',
        jsonEncode(res['data']),
      );
    } catch (e) {
      devLog('EstablishmentLocalHydration: order lists $e');
    }
  }

  /// Один запрос всех чеклистов с пунктами — без тройного SELECT.
  Future<void> _hydrateChecklistsSnapshot(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('checklists')
          .select(
            '*, checklist_items(id, checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit)',
          )
          .eq('establishment_id', establishmentId)
          .order('updated_at', ascending: false);
      final list = List<dynamic>.from(data as List);
      await _snapshots.put(
        '$establishmentId:checklists_raw',
        await _encodeLarge(list),
      );
    } catch (e) {
      devLog('EstablishmentLocalHydration: checklists $e');
    }
  }

  Future<void> _hydrateTechCards(String dataEstablishmentId) async {
    try {
      await TechCardServiceSupabase().refreshTechCardsFromServer(dataEstablishmentId);
    } catch (e) {
      devLog('EstablishmentLocalHydration: tech cards $e');
    }
  }

  Future<void> _hydrateHaccp(String establishmentId) async {
    try {
      await HaccpConfigService().load(establishmentId, notify: false);
    } catch (e) {
      devLog('EstablishmentLocalHydration: haccp $e');
    }
  }

  Future<void> _hydratePosTables(String establishmentId) async {
    try {
      final tables =
          await PosDiningLayoutService.instance.fetchTables(establishmentId);
      final raw = tables
          .map(
            (e) => <String, dynamic>{
              'id': e.id,
              'establishment_id': e.establishmentId,
              'floor_name': e.floorName,
              'room_name': e.roomName,
              'table_number': e.tableNumber,
              'sort_order': e.sortOrder,
              'status': e.status.toApi(),
            },
          )
          .toList();
      await _snapshots.put(
        '$establishmentId:pos_dining_tables',
        await _encodeLarge(raw),
      );
    } catch (e) {
      devLog('EstablishmentLocalHydration: pos tables $e');
    }
  }

  Future<void> _hydrateMenuStopGo(String establishmentId) async {
    try {
      final map = await MenuStopGoService().loadStopGoMap(establishmentId);
      await _snapshots.put(
        '$establishmentId:menu_stop_go',
        await _encodeLarge(map),
      );
    } catch (e) {
      devLog('EstablishmentLocalHydration: menu_stop_go $e');
    }
  }

  Future<void> _hydrateSalesPlans(String establishmentId) async {
    try {
      final plans = await SalesPlanStorageService.instance.loadAll(establishmentId);
      await _snapshots.put(
        '$establishmentId:pos_sales_plans',
        await _encodeLarge(plans.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      devLog('EstablishmentLocalHydration: sales plans $e');
    }
  }

  Future<void> _hydrateFiscal(String establishmentId) async {
    try {
      final row =
          await EstablishmentFiscalSettingsService.instance.fetch(establishmentId);
      if (row == null) {
        await _snapshots.put('$establishmentId:fiscal_settings', '{}');
        return;
      }
      await _snapshots.put(
        '$establishmentId:fiscal_settings',
        await _encodeLarge(<String, dynamic>{
          'establishment_id': row.establishmentId,
          'tax_region': row.taxRegion,
          'price_tax_mode': row.priceTaxMode,
          'vat_override_percent': row.vatOverridePercent,
          'fiscal_section_id': row.fiscalSectionId,
          'updated_at': row.updatedAt.toIso8601String(),
        }),
      );
    } catch (e) {
      devLog('EstablishmentLocalHydration: fiscal $e');
    }
  }

  Future<void> _hydrateInventoryDrafts(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from('inventory_drafts')
          .select()
          .eq('establishment_id', establishmentId);
      final list = List<dynamic>.from(rows as List);
      await _snapshots.put(
        '$establishmentId:inventory_drafts',
        await _encodeLarge(list),
      );
    } catch (e) {
      devLog('EstablishmentLocalHydration: inventory_drafts $e');
    }
  }

  Future<void> _hydrateIikoIfPossible(String establishmentId) async {
    final ctx = AppRouter.rootNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      final iiko = Provider.of<IikoProductStore>(ctx, listen: false);
      await iiko.loadProducts(establishmentId, force: true);
    } catch (e) {
      devLog('EstablishmentLocalHydration: iiko $e');
    }
  }

  Future<void> runBackgroundDeltaSync() async {
    final acc = AccountManagerSupabase();
    if (!acc.isLoggedInSync) return;
    final now = DateTime.now();
    if (_lastDeltaAt != null &&
        now.difference(_lastDeltaAt!) < _deltaMinInterval) {
      return;
    }
    _lastDeltaAt = now;

    final estId = acc.establishment?.id;
    final dataId = acc.dataEstablishmentId;
    if (estId == null || dataId == null || dataId.isEmpty) return;

    try {
      await acc.syncEstablishmentAccessFromServer();
      final ps = ProductStoreSupabase();

      final pk = await _offlineCache.scopedKey(
        dataset: _productsCacheDataset,
        establishmentId: 'global',
      );
      final productTtl = kIsWeb
          ? const Duration(minutes: 25)
          : const Duration(minutes: 120);
      if (!await _offlineCache.isKeyFresh(pk, productTtl)) {
        await ps.loadProducts(force: true);
      }

      final nk = await _offlineCache.scopedKey(
        dataset: _nomenclatureCacheDataset,
        establishmentId: dataId,
        suffix: 'main',
      );
      final nomTtl = kIsWeb
          ? const Duration(minutes: 15)
          : const Duration(minutes: 60);
      if (!await _offlineCache.isKeyFresh(nk, nomTtl)) {
        await ps.loadNomenclatureForce(dataId);
      }

      await Future.wait([
        _hydrateEmployees(estId),
        DocumentationServiceSupabase().prefetchDocumentsCacheForMobile(estId),
        loadSchedule(estId),
        _prefetchOrderListsPrefs(estId),
        _hydrateChecklistsSnapshot(estId),
        _hydrateTechCards(dataId),
        _hydrateHaccp(estId),
        _hydratePosTables(estId),
        _hydrateMenuStopGo(estId),
        _hydrateSalesPlans(estId),
        _hydrateFiscal(estId),
        _hydrateInventoryDrafts(estId),
      ].map((f) => f.catchError((Object e, _) {
            devLog('EstablishmentLocalHydration: delta task $e');
          })));

      if (!kIsWeb) {
        await _mirrorEmployeesToSqlite(estId);
        await _hydrateIikoIfPossible(estId);
      }
    } catch (e, st) {
      devLog('EstablishmentLocalHydration: delta $e $st');
    }
  }
}
