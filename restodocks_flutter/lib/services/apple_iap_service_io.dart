import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import '../core/iap_constants.dart';
import '../utils/dev_log.dart';
import 'account_manager_supabase.dart';
import 'edge_function_http.dart';

enum _IapPurchasePreflight {
  proceed,
  blockedConflict,
  alreadyActivated,
}

/// In-App Purchase (iOS): подписка Pro → Edge `billing-verify-apple` → `establishments`.
class AppleIapService extends ChangeNotifier {
  AppleIapService({
    required AccountManagerSupabase accountManager,
  }) : _account = accountManager;

  final AccountManagerSupabase _account;

  static bool get isIOSPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Timer? _busyWatchdog;

  bool _ready = false;
  bool _busy = false;
  bool _storeLoaded = false;
  final Map<String, ProductDetails> _products = {};
  String? _lastError;
  int _successToken = 0;

  bool get ready => _ready;
  bool get busy => _busy;

  /// Обратная совместимость: продукт подписки Pro (если есть в витрине).
  ProductDetails? get product => _products[kRestodocksProMonthlyProductId];

  /// Подписки Pro / Ultra, найденные в App Store (для цен и покупки).
  List<ProductDetails> get subscriptionProducts {
    final out = <ProductDetails>[];
    final p = _products[kRestodocksProMonthlyProductId];
    final u = _products[kRestodocksUltraMonthlyProductId];
    if (p != null) out.add(p);
    if (u != null) out.add(u);
    return out;
  }

  /// Доп. пакеты (+5 сотрудников, +1 филиал), если настроены в App Store Connect.
  List<ProductDetails> get addonProducts {
    final out = <ProductDetails>[];
    final e = _products[kRestodocksAddonEmployeePack5ProductId];
    final b = _products[kRestodocksAddonBranchPack1ProductId];
    if (e != null) out.add(e);
    if (b != null) out.add(b);
    return out;
  }

  String? get lastError => _lastError;

  void _setBusy(bool value, {bool notify = true}) {
    if (value) {
      _busy = true;
      _busyWatchdog?.cancel();
      _busyWatchdog = Timer(const Duration(seconds: 10), () {
        if (!_busy) return;
        devLog('IAP watchdog: force-stop busy state after timeout');
        _busy = false;
        notifyListeners();
      });
    } else {
      _busy = false;
      _busyWatchdog?.cancel();
      _busyWatchdog = null;
    }
    if (notify) notifyListeners();
  }

  /// Увеличивается после успешной проверки чека и обновления заведения (для SnackBar в UI).
  int get successToken => _successToken;

  /// StoreKit 2 кладёт в [PurchaseVerificationData.serverVerificationData] JWS транзакции;
  /// legacy Apple `verifyReceipt` принимает только base64 **app receipt** (как у StoreKit 1).
  static bool _isStoreKit2Jws(String s) {
    if (s.isEmpty) return false;
    return s.startsWith('eyJ') && s.split('.').length == 3;
  }

  /// Legacy `verifyReceipt` нужен base64 app receipt. После покупки чек на диске может
  /// обновиться с задержкой — несколько refresh с паузами.
  Future<String?> _receiptForLegacyVerify(PurchaseDetails purchase) async {
    final add =
        _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();

    // 1) Unified app receipt из бандла (verifyReceipt на сервере ждёт base64 ASN.1, не JWS транзакции).
    try {
      final direct = await SKReceiptManager.retrieveReceiptData();
      if (direct.isNotEmpty && !_isStoreKit2Jws(direct)) {
        return direct;
      }
    } catch (e, st) {
      devLog('IAP retrieveReceiptData (direct): $e $st');
    }

    // 2) StoreKit 2: синхронизация с App Store, затем снова чтение чека (после покупки файл может запаздывать).
    try {
      await add.sync();
    } catch (e, st) {
      devLog('IAP StoreKit sync: $e $st');
    }
    try {
      final afterSync = await SKReceiptManager.retrieveReceiptData();
      if (afterSync.isNotEmpty && !_isStoreKit2Jws(afterSync)) {
        return afterSync;
      }
    } catch (e, st) {
      devLog('IAP retrieveReceiptData (after sync): $e $st');
    }

    const pauseMs = <int>[
      400, 500, 700, 1000, 1200, 1500, 1800, 2200, 2800,
    ];
    for (var i = 0; i < pauseMs.length; i++) {
      await Future<void>.delayed(Duration(milliseconds: pauseMs[i]));
      try {
        final v = await add.refreshPurchaseVerificationData();
        final r = v?.serverVerificationData ?? v?.localVerificationData ?? '';
        if (r.isNotEmpty && !_isStoreKit2Jws(r)) {
          return r;
        }
      } catch (e, st) {
        devLog('IAP refresh receipt attempt ${i + 1}: $e $st');
      }
    }

    final fromPurchase = purchase.verificationData.serverVerificationData;
    if (fromPurchase.isNotEmpty && !_isStoreKit2Jws(fromPurchase)) {
      return fromPurchase;
    }
    return null;
  }

  /// App Store receipt (base64) без экрана покупки: синхронизация Pro, если подписка уже есть у Apple ID.
  Future<String?> _appReceiptBase64ForProSync() async {
    final add =
        _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
    try {
      final direct = await SKReceiptManager.retrieveReceiptData();
      if (direct.isNotEmpty && !_isStoreKit2Jws(direct)) return direct;
    } catch (e, st) {
      devLog('IAP sync receipt direct: $e $st');
    }
    try {
      await add.sync();
    } catch (e, st) {
      devLog('IAP sync receipt StoreKit sync: $e $st');
    }
    try {
      final after = await SKReceiptManager.retrieveReceiptData();
      if (after.isNotEmpty && !_isStoreKit2Jws(after)) return after;
    } catch (e, st) {
      devLog('IAP sync receipt after sync: $e $st');
    }
    try {
      await _iap.restorePurchases();
    } catch (e, st) {
      devLog('IAP restorePurchases for receipt sync: $e $st');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    try {
      await add.sync();
    } catch (_) {}
    try {
      final afterRestore = await SKReceiptManager.retrieveReceiptData();
      if (afterRestore.isNotEmpty && !_isStoreKit2Jws(afterRestore)) {
        return afterRestore;
      }
    } catch (e, st) {
      devLog('IAP sync receipt after restore: $e $st');
    }
    const pauseMs = <int>[300, 500, 800, 1200];
    for (final ms in pauseMs) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      try {
        final v = await add.refreshPurchaseVerificationData();
        final r = v?.serverVerificationData ?? v?.localVerificationData ?? '';
        if (r.isNotEmpty && !_isStoreKit2Jws(r)) return r;
      } catch (_) {}
    }
    return null;
  }

  /// Если в App Store уже активна подписка Pro, а на сервере ещё нет — шлём чек на Edge и подтягиваем Pro без «Оплатить».
  ///
  /// [silentFailures]: не выставлять [lastError] при ошибке (фоновый sync при открытии настроек — без ложных SnackBar).
  Future<bool> trySyncProFromStoreReceipt({bool silentFailures = false}) async {
    if (!isIOSPlatform) return false;
    await init();
    if (!_ready) return false;
    final est = _account.establishment;
    final emp = _account.currentEmployee;
    if (est == null || emp == null || !emp.hasRole('owner')) return false;
    if (_account.establishment?.hasPaidProAccess ?? false) return true;

    final receiptData = await _appReceiptBase64ForProSync();
    if (receiptData == null || receiptData.isEmpty) {
      devLog('IAP trySyncProFromStoreReceipt: no receipt');
      return false;
    }

    final res = await _verifyReceiptWithRetries(
      establishmentId: est.id,
      receiptData: receiptData,
      aggressive: true,
    );
    if (res.status != 200) {
      devLog(
        'IAP trySyncProFromStoreReceipt: verify ${res.status} ${res.data}',
      );
      if (!silentFailures) {
        if (res.status == 409) {
          final d = res.data;
          final buf = StringBuffer('verify_failed_http_409');
          if (d != null && d['error'] != null) {
            buf.write('|');
            buf.write(
              d['error'].toString().trim().replaceAll('|', '/'),
            );
          }
          _lastError = buf.toString();
          notifyListeners();
        }
      }
      return false;
    }
    try {
      await _account.syncEstablishmentAccessFromServer();
    } catch (e, st) {
      devLog('IAP trySyncPro sync establishment: $e $st');
    }
    _lastError = null;
    final ok = _account.establishment?.hasPaidProAccess ?? false;
    if (ok) {
      _successToken++;
    }
    notifyListeners();
    return ok;
  }

  Map<String, dynamic>? _normalizeEdgeJson(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  /// Несколько попыток [refreshSession] — окно Apple может длиться долго, JWT успевает протухнуть.
  /// [aggressive]: больше пауз — реже показываем пользователю ошибку сессии до/после оплаты.
  Future<bool> _ensureSessionForPayment({bool aggressive = false}) async {
    final delaysMs = aggressive
        ? <int>[0, 120, 280, 500, 800, 1200, 1700, 2400, 3200]
        : <int>[0, 100, 250, 500, 800, 1200];
    for (var i = 0; i < delaysMs.length; i++) {
      if (delaysMs[i] > 0) {
        await Future<void>.delayed(Duration(milliseconds: delaysMs[i]));
      }
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (e, st) {
        devLog('IAP ensureSession refresh $i: $e $st');
      }
      final t = Supabase.instance.client.auth.currentSession?.accessToken;
      if (t != null && t.isNotEmpty) return true;
    }
    return false;
  }

  /// Сначала [functions.invoke] (тот же JWT, что у RPC), при не-2xx — [postEdgeFunctionWithRetry] с несколькими 401-retry.
  Future<({int status, Map<String, dynamic>? data})> _postBillingVerifyApple({
    required String establishmentId,
    required String receiptData,
  }) async {
    var ok = await _ensureSessionForPayment();
    if (!ok) {
      ok = await _ensureSessionForPayment(aggressive: true);
    }
    if (!ok) {
      return (
        status: 401,
        data: <String, dynamic>{'error': 'iap_session_unavailable'},
      );
    }

    final body = <String, dynamic>{
      'establishment_id': establishmentId,
      'receipt_data': receiptData,
    };

    Future<({int status, Map<String, dynamic>? data})> invokeOnce() async {
      try {
        final res = await Supabase.instance.client.functions.invoke(
          'billing-verify-apple',
          body: body,
        );
        return (status: res.status, data: _normalizeEdgeJson(res.data));
      } on FunctionException catch (e) {
        return (status: e.status, data: _normalizeEdgeJson(e.details));
      }
    }

    try {
      var r = await invokeOnce();
      if (r.status == 401 || r.status == 403) {
        devLog('IAP billing invoke ${r.status} → refresh + retry');
        try {
          await Supabase.instance.client.auth.refreshSession();
        } catch (_) {}
        r = await invokeOnce();
      }
      if (r.status >= 200 && r.status < 300) {
        return r;
      }
      devLog('IAP billing invoke HTTP ${r.status}, fallback Dio');
      return await postEdgeFunctionWithRetry(
        'billing-verify-apple',
        body,
        refreshSessionBeforeFirstPost: true,
        retryOnceOn401AfterSessionRefresh: true,
        max401RecoveryAttempts: 2,
      );
    } catch (e, st) {
      devLog('IAP billing invoke exception → fallback Dio: $e $st');
      return await postEdgeFunctionWithRetry(
        'billing-verify-apple',
        body,
        refreshSessionBeforeFirstPost: true,
        retryOnceOn401AfterSessionRefresh: true,
        max401RecoveryAttempts: 2,
      );
    }
  }

  bool _isRetryableVerifyStatus(int status) =>
      status == 400 || status == 401 || status == 403 || status == 429 || status >= 500;

  bool _isRetryableVerifyError(String? code) {
    final c = (code ?? '').trim().toLowerCase();
    if (c.isEmpty) return false;
    return c.contains('receipt_missing_app_account_binding') ||
        c.contains('receipt_bound_to_other_establishment') ||
        c.contains('iap_session_unavailable') ||
        c.contains('apple receipt validation') ||
        c.contains('too many requests');
  }

  /// Повторяем verify с короткими паузами: после покупки App Store может
  /// отдать чек/привязку не сразу, особенно в TestFlight/Sandbox.
  Future<({int status, Map<String, dynamic>? data})> _verifyReceiptWithRetries({
    required String establishmentId,
    required String receiptData,
    bool aggressive = false,
  }) async {
    final delays = aggressive
        ? <int>[0, 1200, 2400, 4200, 6500]
        : <int>[0, 900, 1800];
    ({int status, Map<String, dynamic>? data}) last = (status: 599, data: null);

    for (var i = 0; i < delays.length; i++) {
      if (delays[i] > 0) {
        await Future<void>.delayed(Duration(milliseconds: delays[i]));
      }
      if (i > 0) {
        await _ensureSessionForPayment(aggressive: true);
      }
      final res = await _postBillingVerifyApple(
        establishmentId: establishmentId,
        receiptData: receiptData,
      );
      last = res;
      if (res.status == 200) return res;

      final errCode = res.data?['error']?.toString();
      if (!_isRetryableVerifyStatus(res.status) && !_isRetryableVerifyError(errCode)) {
        return res;
      }
    }
    return last;
  }

  Future<void> init() async {
    if (!isIOSPlatform) return;
    if (_ready) return;
    _ready = await _iap.isAvailable();
    if (!_ready) {
      _lastError = 'store_unavailable';
      notifyListeners();
      return;
    }

    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onDone: () {},
      onError: (Object e) => devLog('IAP stream: $e'),
    );

    await _loadProducts();
    notifyListeners();
  }

  Future<void> _loadProducts() async {
    if (!isIOSPlatform || !_ready) return;
    final response = await _iap.queryProductDetails(kRestodocksAllIapProductIds);
    if (response.error != null) {
      devLog('IAP queryProductDetails: ${response.error}');
      _lastError = response.error?.message;
    }
    _products.clear();
    for (final d in response.productDetails) {
      _products[d.id] = d;
    }
    final hasSubscriptionSku = kRestodocksSubscriptionProductIds.any(
      _products.containsKey,
    );
    if (!hasSubscriptionSku) {
      _lastError = 'product_not_found';
      _storeLoaded = false;
      return;
    }
    _storeLoaded = true;
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (!kRestodocksSubscriptionProductIds.contains(p.productID)) continue;

      if (p.status == PurchaseStatus.pending) {
        notifyListeners();
        continue;
      }
      if (p.status == PurchaseStatus.error) {
        _lastError = p.error?.message ?? 'purchase_error';
        _setBusy(false);
        continue;
      }
      if (p.status == PurchaseStatus.canceled) {
        _setBusy(false);
        continue;
      }

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        await _verifyReceiptAndComplete(p);
      }
    }
  }

  /// Сервер уже выставил Pro (другой вызов verify / дубликат события StoreKit).
  bool get _paidProActiveOnServer =>
      _account.establishment?.hasPaidProAccess ?? false;

  /// Единый успех: sync заведения, сброс ошибки, completePurchase в StoreKit.
  /// [countAsNewSuccess]: false — дубликат StoreKit после уже удачной верификации (без второго SnackBar).
  Future<void> _finalizeVerifiedPurchase(
    PurchaseDetails purchase, {
    bool countAsNewSuccess = true,
  }) async {
    try {
      await _account.syncEstablishmentAccessFromServer();
    } catch (e, st) {
      devLog('IAP finalize sync: $e $st');
      try {
        await _account.refreshCurrentEstablishmentFromServer();
      } catch (_) {}
    }
    _lastError = null;
    _setBusy(false, notify: false);
    if (countAsNewSuccess) {
      _successToken++;
    }
    notifyListeners();
    try {
      await _iap.completePurchase(purchase);
    } catch (e, st) {
      devLog('IAP completePurchase after finalize: $e $st');
    }
  }

  Future<void> _verifyReceiptAndComplete(PurchaseDetails purchase) async {
    final est = _account.establishment;
    final emp = _account.currentEmployee;
    if (est == null || emp == null || !emp.hasRole('owner')) {
      _lastError = 'not_owner';
      _setBusy(false, notify: false);
      await _iap.completePurchase(purchase);
      notifyListeners();
      return;
    }

    try {
      final receiptData = await _receiptForLegacyVerify(purchase);
      if (receiptData == null || receiptData.isEmpty) {
        try {
          await _account.refreshCurrentEstablishmentFromServer();
        } catch (_) {}
        if (_paidProActiveOnServer) {
          devLog('IAP no_receipt but Pro already active — duplicate StoreKit event');
          await _finalizeVerifiedPurchase(purchase, countAsNewSuccess: false);
          return;
        }
        _lastError = 'no_receipt';
        _setBusy(false);
        await _iap.completePurchase(purchase);
        return;
      }

      final res = await _verifyReceiptWithRetries(
        establishmentId: est.id,
        receiptData: receiptData,
        aggressive: true,
      );

      if (res.status != 200) {
        devLog('IAP billing-verify-apple failed: ${res.status} ${res.data}');
        try {
          await _account.refreshCurrentEstablishmentFromServer();
        } catch (_) {}
        if (_paidProActiveOnServer) {
          devLog(
            'IAP verify HTTP ${res.status} but Pro already active — ignoring spurious failure (duplicate StoreKit / race)',
          );
          await _finalizeVerifiedPurchase(purchase, countAsNewSuccess: false);
          return;
        }
        // Дополнительный fallback: если чек уже на сервере, но текущая verify попытка дала
        // временный binding/session ответ, пробуем синхронизацию из app receipt.
        final synced = await trySyncProFromStoreReceipt(silentFailures: true);
        if (synced || _paidProActiveOnServer) {
          devLog(
            'IAP verify HTTP ${res.status} recovered by trySyncProFromStoreReceipt',
          );
          await _finalizeVerifiedPurchase(purchase, countAsNewSuccess: false);
          return;
        }
        // Всегда сохраняем HTTP-статус первым сегментом — иначе UI показывает общий текст
        // и теряет различие между 401 / 403 / 400 / 5xx.
        final d = res.data;
        final buf = StringBuffer('verify_failed_http_${res.status}');
        if (d != null) {
          if (d['error'] != null) {
            buf.write('|');
            buf.write(
              d['error'].toString().trim().replaceAll('|', '/'),
            );
          }
          if (d['status'] != null) {
            buf.write('|apple_status_${d['status']}');
          }
        }
        _lastError = buf.toString();
        _setBusy(false);
        await _iap.completePurchase(purchase);
        return;
      }

      await _finalizeVerifiedPurchase(purchase);
    } catch (e, st) {
      devLog('IAP verify: $e $st');
      try {
        await _account.refreshCurrentEstablishmentFromServer();
      } catch (_) {}
      if (_paidProActiveOnServer) {
        devLog('IAP exception but Pro already active — treating as success');
        await _finalizeVerifiedPurchase(purchase, countAsNewSuccess: false);
        return;
      }
      _lastError =
          'iap_client_exception|${e.runtimeType}|${e.toString().replaceAll('|', '/')}';
      _setBusy(false);
      try {
        await _iap.completePurchase(purchase);
      } catch (_) {}
    }
  }

  /// Убрать ложную ошибку в UI, если заведение уже Pro (после refresh с сервера).
  void clearErrorIfProActive() {
    if (_paidProActiveOnServer && _lastError != null) {
      _lastError = null;
      notifyListeners();
    }
  }

  /// Перед открытием листа оплаты App Store: если в локальном чеке уже подписка,
  /// привязанная к другому владельцу — не вызывать покупку (снижает риск лишнего списания).
  Future<_IapPurchasePreflight> _preflightBeforeStoreKitPurchase() async {
    final est = _account.establishment;
    final emp = _account.currentEmployee;
    if (est == null || emp == null || !emp.hasRole('owner')) {
      return _IapPurchasePreflight.proceed;
    }

    final receiptData = await _appReceiptBase64ForProSync();
    if (receiptData == null || receiptData.isEmpty) {
      return _IapPurchasePreflight.proceed;
    }

    final res = await _postBillingVerifyApple(
      establishmentId: est.id,
      receiptData: receiptData,
    );

    if (res.status == 409) {
      final d = res.data;
      final buf = StringBuffer('verify_failed_http_409_preflight');
      if (d != null && d['error'] != null) {
        buf.write('|');
        buf.write(
          d['error'].toString().trim().replaceAll('|', '/'),
        );
      }
      _lastError = buf.toString();
      return _IapPurchasePreflight.blockedConflict;
    }

    if (res.status == 200) {
      try {
        await _account.syncEstablishmentAccessFromServer();
      } catch (e, st) {
        devLog('IAP preflight sync: $e $st');
      }
      if (_account.establishment?.hasPaidProAccess ?? false) {
        _lastError = null;
        _successToken++;
        return _IapPurchasePreflight.alreadyActivated;
      }
    }

    return _IapPurchasePreflight.proceed;
  }

  /// Оформить подписку Pro (автопродление).
  Future<bool> purchasePro() async =>
      purchaseSubscription(kRestodocksProMonthlyProductId);

  /// Оформить подписку по идентификатору продукта App Store (`restodocks_pro_monthly` / `restodocks_ultra_monthly`).
  Future<bool> purchaseSubscription(String productId) async {
    if (!isIOSPlatform) return false;
    if (!kRestodocksSubscriptionProductIds.contains(productId)) {
      _lastError = 'product_not_supported';
      notifyListeners();
      return false;
    }
    await init();
    final details = _products[productId];
    if (!_ready || !_storeLoaded || details == null) {
      _lastError = 'product_not_ready';
      notifyListeners();
      return false;
    }
    _setBusy(true, notify: false);
    _lastError = null;
    notifyListeners();
    try {
      if (!await _ensureSessionForPayment()) {
        if (!await _ensureSessionForPayment(aggressive: true)) {
          _lastError = 'iap_session_unavailable_pre_store';
          _setBusy(false);
          return false;
        }
      }
      final est = _account.establishment;
      if (est == null) {
        _lastError = 'not_owner';
        _setBusy(false);
        return false;
      }

      final pre = await _preflightBeforeStoreKitPurchase();
      if (pre == _IapPurchasePreflight.blockedConflict) {
        _setBusy(false);
        return false;
      }
      if (pre == _IapPurchasePreflight.alreadyActivated) {
        _setBusy(false);
        return false;
      }

      // Один Apple ID → один owner_id: подписка на все заведения этого владельца (см. billing-verify-apple).
      final param = PurchaseParam(
        productDetails: details,
        applicationUserName: est.ownerId,
      );
      await _iap.buyNonConsumable(purchaseParam: param);
      return true;
    } catch (e) {
      _lastError = e.toString();
      _setBusy(false);
      return false;
    }
  }

  /// Восстановить покупки (на другом устройстве).
  Future<void> restorePurchases() async {
    if (!isIOSPlatform) return;
    await init();
    if (!_ready) return;
    _setBusy(true, notify: false);
    _lastError = null;
    notifyListeners();
    try {
      await _iap.restorePurchases().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          devLog('IAP restorePurchases timeout: continue with receipt sync');
        },
      );
      // В ряде сценариев StoreKit не присылает restored event сразу.
      // Дотягиваем server-state напрямую по app receipt, чтобы убрать ложное "не удалось".
      await trySyncProFromStoreReceipt(silentFailures: true);
    } finally {
      _setBusy(false);
    }
  }

  @override
  void dispose() {
    _busyWatchdog?.cancel();
    _busyWatchdog = null;
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
