import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../firebase_options.dart';

/// Обработчик сообщений FCM в фоне (отдельный isolate). Должен быть top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (DefaultFirebaseOptions.currentPlatform.projectId.isEmpty) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Системный трей при свёрнутом приложении приходит из payload notification;
  // data доступна при необходимости (логирование / локальное сохранение).
}
