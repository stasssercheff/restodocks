import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/router/app_router.dart';
import '../firebase_options.dart';
import '../utils/dev_log.dart';
import 'fcm_background.dart';

/// FCM: регистрация токена в Supabase, локальные уведомления на переднем плане, переход по [route] из data.
class FcmPushService {
  FcmPushService._();

  static const _prefsTokenKey = 'restodocks_fcm_token_registered_v1';
  static const _androidChannelId = 'restodocks_inbox_v1';
  static bool _setupDone = false;
  static FlutterLocalNotificationsPlugin? _local;
  static int _notifId = 0;

  static bool get isFirebaseConfigured =>
      DefaultFirebaseOptions.currentPlatform.projectId.isNotEmpty;

  static bool get _supportsNativePush {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
  }

  /// Вызвать один раз из [main] / bootstrap после [WidgetsFlutterBinding.ensureInitialized].
  static Future<void> setup() async {
    if (_setupDone) return;
    _setupDone = true;
    if (!_supportsNativePush || !isFirebaseConfigured) {
      devLog('FcmPushService: skipped (no native push or Firebase not configured)');
      return;
    }

    // Регистрация до остальных вызовов FirebaseMessaging (требование flutterfire).
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    await _initLocalNotifications();

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromRemoteMessage);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openFromRemoteMessage(initial);
      });
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_registerTokenWithSupabase(token));
    });

    devLog('FcmPushService: Firebase Messaging initialized');
  }

  /// После входа и запроса разрешений — зарегистрировать токен в БД.
  static Future<void> syncRegistrationAfterLogin() async {
    if (!_supportsNativePush || !isFirebaseConfigured) return;
    if (Supabase.instance.client.auth.currentUser == null) return;

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        devLog('FcmPushService: notification permission denied');
        return;
      }

      if (Platform.isIOS || Platform.isMacOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerTokenWithSupabase(token);
      }
    } catch (e, st) {
      devLog('FcmPushService.syncRegistrationAfterLogin: $e $st');
    }
  }

  /// Перед [signOut]: снять регистрацию токена (пока сессия ещё есть).
  static Future<void> unregisterBeforeLogout() async {
    if (!_supportsNativePush || !isFirebaseConfigured) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsTokenKey);
    try {
      if (last != null && last.isNotEmpty) {
        if (Supabase.instance.client.auth.currentUser != null) {
          await Supabase.instance.client.rpc(
            'unregister_push_token',
            params: {'p_fcm_token': last},
          );
        }
      }
      await FirebaseMessaging.instance.deleteToken();
      await prefs.remove(_prefsTokenKey);
    } catch (e, st) {
      devLog('FcmPushService.unregisterBeforeLogout: $e $st');
    }
  }

  static Future<void> _initLocalNotifications() async {
    _local = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _local!.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationResponse,
    );

    final androidPlugin = _local!
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChannelId,
        'Входящие',
        description: 'Уведомления о сообщениях и входящих документах',
        importance: Importance.high,
      ),
    );
  }

  static void _onLocalNotificationResponse(NotificationResponse response) {
    final p = response.payload;
    if (p != null && p.isNotEmpty) {
      _goRoute(p);
    }
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title'] ?? 'Restodocks';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    final route = message.data['route'] ?? '';
    final ln = _local;
    if (ln == null) return;

    final androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      'Входящие',
      channelDescription: 'Уведомления о сообщениях и входящих документах',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    await ln.show(
      id: _notifId++,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      ),
      payload: route.isEmpty ? null : route,
    );
  }

  static void _openFromRemoteMessage(RemoteMessage message) {
    final route = message.data['route'];
    if (route != null && route.isNotEmpty) {
      _goRoute(route);
    }
  }

  static void _goRoute(String route) {
    try {
      final ctx = AppRouter.rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        GoRouter.of(ctx).go(route);
      }
    } catch (e, st) {
      devLog('FcmPushService._goRoute: $e $st');
    }
  }

  static Future<void> _registerTokenWithSupabase(String token) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final platform = _platformTag();
    await Supabase.instance.client.rpc(
      'register_push_token',
      params: {
        'p_fcm_token': token,
        'p_platform': platform,
      },
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTokenKey, token);
  }

  static String _platformTag() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }
}
