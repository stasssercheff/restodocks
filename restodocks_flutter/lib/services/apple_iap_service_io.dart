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

    const pauseMs = <int>[400, 500, 700, 1000, 1200, 1500];
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
      // Не использовать `functions.invoke`: при 4xx SDK бросает [FunctionException],
      // из-за этого ветка с разбором тела ответа не выполнялась.
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

      // Access token часто истекает во время диалога App Store; Edge getUser(JWT) → 401.
      // Обновляем сессию до запроса и один повтор после 401 (см. edge_function_http).
      final res = await postEdgeFunctionWithRetry(
        'billing-verify-apple',
        {
          'establishment_id': est.id,
          'receipt_data': receiptData,
        },
        refreshSessionBeforeFirstPost: true,
        retryOnceOn401AfterSessionRefresh: true,
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
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (e, st) {
        devLog('IAP purchasePro refreshSession: $e $st');
      }
      final param = PurchaseParam(productDetails: _product!);
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
