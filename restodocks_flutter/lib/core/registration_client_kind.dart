import 'registration_client_kind_stub.dart'
    if (dart.library.io) 'registration_client_kind_io.dart'
    if (dart.library.html) 'registration_client_kind_web.dart' as _impl;

/// Для Edge `register-metadata` и отображения в админке.
/// Значения: `ios_app`, `android_app`, `web_mobile`, `web_desktop`, `native_other`.
String getRegistrationClientKind() => _impl.getRegistrationClientKind();
