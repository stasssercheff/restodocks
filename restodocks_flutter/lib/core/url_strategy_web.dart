// HashUrlStrategy: URL с # (site.com/#/schedule). F5 стабильно сохраняет путь.
// pathname всегда / — сервер не трогает хэш; SW и кэш не влияют.
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void initUrlStrategy() {
  setUrlStrategy(const HashUrlStrategy());
}
