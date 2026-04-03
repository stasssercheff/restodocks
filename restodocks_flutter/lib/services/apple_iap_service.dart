/// In-App Purchase: на web — заглушка (нет StoreKit); иначе — реализация с StoreKit для iOS.
export 'apple_iap_service_io.dart' if (dart.library.html) 'apple_iap_service_stub.dart';
