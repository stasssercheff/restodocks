// HashUrlStrategy — единственный надёжный вариант при F5 в текущей среде.
// PathUrlStrategy даёт pathname=/ при перезагрузке (SW/кэш/редирект).
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void initUrlStrategy() {
  setUrlStrategy(const HashUrlStrategy());
}
