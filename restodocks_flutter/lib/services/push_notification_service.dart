import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/dev_log.dart';

/// Локальный диалог разрешений (iOS/Android) до первого FCM-запроса.
///
/// **In-app:** входящие и сообщения — плашки в `InboxNotificationListener`; для
/// сообщений учитывается настройка «показывать текст сообщения».
///
/// **Фоновые push (FCM):** при настроенном Firebase — `FcmPushService` регистрирует
/// токен в `register_push_token`, сервер шлёт уведомления через Edge Function
/// `push-inbox-dispatch`; в data есть `route` для перехода (например `/inbox/chat/...`).
class PushNotificationService {
  PushNotificationService._();

  static const _keyAsked = 'restodocks_notification_permission_asked_v1';

  /// Один раз после входа — системный диалог «Разрешить уведомления» (нужен для будущих remote push).
  static Future<void> requestPermissionOnceAfterLogin() async {
    if (kIsWeb) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyAsked) == true) return;
      final status = await Permission.notification.request();
      if (status.isGranted || status.isDenied || status.isPermanentlyDenied) {
        await prefs.setBool(_keyAsked, true);
      }
    } catch (e, st) {
      devLog('PushNotificationService.requestPermission: $e $st');
    }
  }
}
