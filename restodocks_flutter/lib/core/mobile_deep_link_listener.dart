import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'deep_link_bootstrap.dart';

/// Под [MaterialApp.router]: открытие приложения по Universal Link, пока оно в фоне.
class MobileDeepLinkListener extends StatefulWidget {
  const MobileDeepLinkListener({super.key, required this.child});

  final Widget child;

  @override
  State<MobileDeepLinkListener> createState() => _MobileDeepLinkListenerState();
}

class _MobileDeepLinkListenerState extends State<MobileDeepLinkListener> {
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    _sub = DeepLinkBootstrap.uriLinkStream().listen(_onLink);
  }

  void _onLink(Uri uri) {
    if (!DeepLinkBootstrap.isOurHttpsLink(uri)) return;
    final path = DeepLinkBootstrap.pathAndQuery(uri);
    if (!DeepLinkBootstrap.shouldDispatchPath(path)) return;
    DeepLinkBootstrap.rememberAuthConfirmUri(uri);
    final hasTokens = uri.fragment.contains('access_token') ||
        uri.query.contains('access_token');
    if (hasTokens) {
      unawaited(Supabase.instance.client.auth.getSessionFromUrl(uri));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(path);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
