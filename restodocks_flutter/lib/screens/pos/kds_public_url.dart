import 'package:flutter/foundation.dart';

/// Путь закладки браузера для гостевого KDS (`?kds_token=…`).
String kdsPublicDisplayPath(String department, String token) {
  final d = department.trim().toLowerCase();
  final t = Uri.encodeQueryComponent(token);
  return '/display/kds/$d?kds_token=$t';
}

/// Полный URL на web (монитор / планшет без входа).
String? kdsPublicDisplayFullUrl(String department, String token) {
  if (!kIsWeb) return null;
  final path = kdsPublicDisplayPath(department, token);
  final origin = Uri.base.origin;
  return '$origin$path';
}
