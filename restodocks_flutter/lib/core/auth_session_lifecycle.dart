import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/realtime_sync_service.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_visibility_resume_stub.dart'
    if (dart.library.html) 'auth_visibility_resume_web.dart' as auth_vis;
import '../services/account_manager_supabase.dart';
import '../services/account_ui_sync_service.dart';
import '../services/establishment_local_hydration_service.dart';
import '../utils/dev_log.dart';

/// На вебе при простое истекает access_token; без refresh роль становится anon, RLS на
/// product_nutrition_links даёт 403. Обновляем сессию при возврате в приложение / вкладку.
class AuthSessionLifecycle extends StatefulWidget {
  const AuthSessionLifecycle({super.key, required this.child});

  final Widget child;

  @override
  State<AuthSessionLifecycle> createState() => _AuthSessionLifecycleState();
}

class _AuthSessionLifecycleState extends State<AuthSessionLifecycle>
    with WidgetsBindingObserver {
  StreamSubscription? _visibilitySub;
  Timer? _periodicWebRefresh;
  /// На iOS/Android без этого access_token истекает при долгой работе в foreground → 401 на Edge/RLS.
  Timer? _periodicMobileRefresh;
  DateTime? _lastRefreshAttempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      _visibilitySub =
          auth_vis.subscribeAuthResumeOnVisibility(_tryRefreshSessionThrottled);
      // Инкогнито и фоновые вкладки сильнее режут таймеры GoTrue — подстраховка, пока окно жило.
      _periodicWebRefresh = Timer.periodic(const Duration(minutes: 4), (_) {
        unawaited(_tryRefreshSession());
      });
    } else {
      _periodicMobileRefresh = Timer.periodic(const Duration(minutes: 5), (_) {
        unawaited(_tryRefreshSession());
      });
    }
  }

  @override
  void dispose() {
    _periodicWebRefresh?.cancel();
    _periodicMobileRefresh?.cancel();
    _visibilitySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tryRefreshSessionThrottled();
    }
  }

  void _tryRefreshSessionThrottled() {
    final now = DateTime.now();
    if (_lastRefreshAttempt != null &&
        now.difference(_lastRefreshAttempt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastRefreshAttempt = now;
    unawaited(_tryRefreshSession());
  }

  Future<void> _tryRefreshSession() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) {
      try {
        await client.auth.refreshSession();
      } catch (e, st) {
        devLog('[Auth] refreshSession after resume/visible: $e\n$st');
      }
    }
    // В т.ч. legacy-вход без JWT: проверка промо/Pro на сервере при возврате в приложение.
    unawaited(AccountManagerSupabase().syncEstablishmentAccessFromServer());
    unawaited(AccountUiSyncService.instance.refreshEmployeeProfileFromServer());
    unawaited(EstablishmentLocalHydrationService.instance.runBackgroundDeltaSync());
    if (!kIsWeb) {
      unawaited(RealtimeSyncService().syncNow(reason: 'app_resumed'));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
