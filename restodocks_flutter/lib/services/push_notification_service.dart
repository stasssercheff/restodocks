import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/dev_log.dart';

/// Подготовка к push (iOS/Android): запрос разрешения на показ уведомлений.
///
/// **Сейчас:** входящие и сообщения показываются как in-app (плашка/модал) в
/// `InboxNotificationListener`, тексты — с типом данных и «от кого»; для сообщений
/// учитывается настройка «показывать текст сообщения» в уведомлениях.
///
/// **Системные push (свёрнуто/закрыто):** нужны FCM (или прямой APNs) + хранение
/// токена устройства в БД + Edge Function/cron, который шлёт уведомление при INSERT
/// во входящие таблицы / `employee_direct_messages`. Полезный payload для паритета
/// с UI: `category` (messages|orders|inventory|…), `type_label`, `from_name`,
/// `body` (только для сообщений и только если пользователь не отключил превью текста),
/// `deep_link` (например `/inbox/chat/{senderId}`).
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
