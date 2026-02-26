// PathUrlStrategy — чистые URL без # (site.com/schedule вместо site.com/#/schedule).
// Vercel rewrites отдают index.html для всех путей, F5 сохраняет текущий маршрут.
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void initUrlStrategy() {
  setUrlStrategy(PathUrlStrategy());
}
