import 'deep_link_bootstrap.dart';

/// Мобильные платформы: стартовый путь из Universal Link (если есть).
String getInitialLocation() {
  final p = DeepLinkBootstrap.initialLocationPath;
  if (p != null && p.isNotEmpty && p != '/') return p;
  return '/';
}

String? getCachedInitialPath() => null;

String? getCurrentBrowserPath() => null;

void savePathForRefresh(String path) {}

String? getLastSavedPath() => null;
