import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'account_manager_supabase.dart';

/// Web: без StoreKit; публичный API как у реализации для iOS.
class AppleIapService extends ChangeNotifier {
  AppleIapService({
    required AccountManagerSupabase accountManager,
  }) : _account = accountManager;

  // ignore: unused_field
  final AccountManagerSupabase _account;

  static bool get isIOSPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get ready => false;
  bool get busy => false;
  ProductDetails? get product => null;
  String? get lastError => null;
  int get successToken => 0;

  Future<void> init() async {}

  Future<bool> purchasePro() async => false;

  Future<void> restorePurchases() async {}

  Future<bool> trySyncProFromStoreReceipt({bool silentFailures = false}) async =>
      false;

  void clearErrorIfProActive() {}
}
