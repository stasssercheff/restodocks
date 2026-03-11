import 'package:flutter/foundation.dart';

/// Логи только в debug. В release не выводятся.
void devLog(Object? message) {
  if (kDebugMode) {
    debugPrint(message?.toString());
  }
}
