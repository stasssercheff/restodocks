import 'package:flutter_web_plugins/url_strategy.dart' as impl;

/// Web: включить path-based URLs (/path вместо /#/path) для сохранения URL при обновлении
void initUrlStrategy() {
  impl.usePathUrlStrategy();
}
