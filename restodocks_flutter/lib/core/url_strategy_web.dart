// PathUrlStrategy: URL без # (site.com/schedule). F5 сохраняет путь.
// Vercel rewrites все пути на index.html — SPA routing работает.
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void initUrlStrategy() {
  setUrlStrategy(PathUrlStrategy());
}
