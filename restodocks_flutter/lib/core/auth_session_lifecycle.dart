import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_visibility_resume_stub.dart'
    if (dart.library.html) 'auth_visibility_resume_web.dart' as auth_vis;
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
  DateTime? _lastRefreshAttempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      _visibilitySub =
          auth_vis.subscribeAuthResumeOnVisibility(_tryRefreshSessionThrottled);
    }
  }

  @override
  void dispose() {
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
    if (client.auth.currentSession == null) return;
    try {
      await client.auth.refreshSession();
    } catch (e, st) {
      devLog('[Auth] refreshSession after resume/visible: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
