import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../core/iap_constants.dart';
import '../utils/dev_log.dart';
import 'account_manager_supabase.dart';
import 'supabase_service.dart';

/// In-App Purchase (iOS): подписка Pro → Edge `billing-verify-apple` → `establishments`.
class AppleIapService extends ChangeNotifier {
  AppleIapService({
    required AccountManagerSupabase accountManager,
    SupabaseService? supabase,
  })  : _account = accountManager,
        _supabase = supabase ?? SupabaseService();

  final AccountManagerSupabase _account;
  final SupabaseService _supabase;

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
      var receiptData = purchase.verificationData.serverVerificationData;
      if (receiptData.isEmpty || _isStoreKit2Jws(receiptData)) {
        final add =
            _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
        final v = await add.refreshPurchaseVerificationData();
        receiptData = v?.serverVerificationData ?? v?.localVerificationData ?? '';
      }
      if (receiptData.isEmpty) {
        _lastError = 'no_receipt';
        _busy = false;
        notifyListeners();
        await _iap.completePurchase(purchase);
        return;
      }

      final res = await _supabase.client.functions.invoke(
        'billing-verify-apple',
        body: {
          'establishment_id': est.id,
          'receipt_data': receiptData,
        },
      );

      if (res.status != 200) {
        devLog('IAP billing-verify-apple failed: ${res.status} ${res.data}');
        final err = res.data is Map
            ? (res.data as Map)['error']?.toString()
            : 'HTTP ${res.status}';
        _lastError = err ?? 'verify_failed';
        _busy = false;
        notifyListeners();
        await _iap.completePurchase(purchase);
        return;
      }

      await _account.refreshCurrentEstablishmentFromServer();
      _lastError = null;
      _busy = false;
      _successToken++;
      notifyListeners();
      await _iap.completePurchase(purchase);
    } catch (e, st) {
      devLog('IAP verify: $e $st');
      _lastError = e.toString();
      _busy = false;
      notifyListeners();
      try {
        await _iap.completePurchase(purchase);
      } catch (_) {}
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
