import 'package:flutter/foundation.dart';

/// Feature flags. Default: false (safe for prod).
/// Enable via --dart-define=ENABLE_XXX=true at build time.
class FeatureFlags {
  FeatureFlags._();

  /// TТК import from Excel/PDF. Off by default.
  static const bool _ttkImportFromBuild = bool.fromEnvironment(
    'ENABLE_TTK_IMPORT',
    defaultValue: false,
  );

  /// Кнопка импорта ТТК: build-flag И не прод-домен.
  /// На restodocks.com кнопка всегда скрыта, чтобы не зависеть от настроек Cloudflare.
  static bool get ttkImportEnabled {
    if (!_ttkImportFromBuild) return false;
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      if (host == 'restodocks.com' || host == 'www.restodocks.com') return false;
    }
    return true;
  }
}
