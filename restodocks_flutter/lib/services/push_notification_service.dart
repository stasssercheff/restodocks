import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/dev_log.dart';

/// Подготовка к push (iOS/Android): запрос разрешения на показ уведомлений.
///
/// **Важно:** пока доставка идёт через Supabase Realtime, уведомления приходят
/// только пока приложение активно или удерживает соединение. Чтобы пуши
/// приходили в свёрнутом/закрытом состоянии, нужны APNs/FCM и серверная отправка
/// (Edge Function + токен устройства в БД). После подключения Firebase вызовите
/// регистрацию FCM здесь и сохраните токен в Supabase.
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
