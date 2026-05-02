import 'dart:io' show Platform;

/// iOS/Android/macOS/… — для админки и register-metadata.
String getRegistrationClientKind() {
  if (Platform.isIOS) return 'ios_app';
  if (Platform.isAndroid) return 'android_app';
  return 'native_other';
}
