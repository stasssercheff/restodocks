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

  bool _ready = false;
  bool _busy = false;
  bool _storeLoaded = false;
  ProductDetails? _product;
  String? _lastError;
  int _successToken = 0;

  bool get ready => _ready;
  bool get busy => _busy;
  ProductDetails? get product => _product;
  String? get lastError => _lastError;

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

    final res = await _postBillingVerifyApple(
      establishmentId: est.id,
      receiptData: receiptData,
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

    await _loadProduct();
    notifyListeners();
  }

  Future<void> _loadProduct() async {
    if (!isIOSPlatform || !_ready) return;
    final ids = {kRestodocksProMonthlyProductId};
    final response = await _iap.queryProductDetails(ids);
    if (response.error != null) {
      devLog('IAP queryProductDetails: ${response.error}');
      _lastError = response.error?.message;
    }
    if (response.productDetails.isEmpty) {
      _lastError = 'product_not_found';
      return;
    }
    _product = response.productDetails.first;
    _storeLoaded = true;
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != kRestodocksProMonthlyProductId) continue;

      if (p.status == PurchaseStatus.pending) {
        notifyListeners();
        continue;
      }
      if (p.status == PurchaseStatus.error) {
        _lastError = p.error?.message ?? 'purchase_error';
        _busy = false;
        notifyListeners();
        continue;
      }
      if (p.status == PurchaseStatus.canceled) {
        _busy = false;
        notifyListeners();
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
    _busy = false;
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
      _busy = false;
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
        _busy = false;
        notifyListeners();
        await _iap.completePurchase(purchase);
        return;
      }

      var res = await _postBillingVerifyApple(
        establishmentId: est.id,
        receiptData: receiptData,
      );

      if (res.status != 200 &&
          (res.status == 401 || res.status == 403)) {
        devLog(
          'IAP billing-verify-apple ${res.status} → aggressive session + one retry',
        );
        await _ensureSessionForPayment(aggressive: true);
        res = await _postBillingVerifyApple(
          establishmentId: est.id,
          receiptData: receiptData,
        );
      }

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
        _busy = false;
        notifyListeners();
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
      _busy = false;
      notifyListeners();
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

  /// Оформить подписку (автопродление).
  Future<bool> purchasePro() async {
    if (!isIOSPlatform) return false;
    await init();
    if (!_ready || !_storeLoaded || _product == null) {
      _lastError = 'product_not_ready';
      notifyListeners();
      return false;
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      if (!await _ensureSessionForPayment()) {
        if (!await _ensureSessionForPayment(aggressive: true)) {
          _lastError = 'iap_session_unavailable_pre_store';
          _busy = false;
          notifyListeners();
          return false;
        }
      }
      final est = _account.establishment;
      if (est == null) {
        _lastError = 'not_owner';
        _busy = false;
        notifyListeners();
        return false;
      }
      // Один Apple ID → один owner_id: Pro на все заведения этого владельца (см. billing-verify-apple).
      final param = PurchaseParam(
        productDetails: _product!,
        applicationUserName: est.ownerId,
      );
      await _iap.buyNonConsumable(purchaseParam: param);
      return true;
    } catch (e) {
      _lastError = e.toString();
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Восстановить покупки (на другом устройстве).
  Future<void> restorePurchases() async {
    if (!isIOSPlatform) return;
    await init();
    if (!_ready) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await _iap.restorePurchases();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
