// HashStrategy: URL с # (site.com/#/inventory).
// F5 работает без настройки сервера — хэш не отправляется на сервер.
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void initUrlStrategy() {
  setUrlStrategy(const HashUrlStrategy());
}
