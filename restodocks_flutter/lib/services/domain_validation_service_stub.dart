/// Non-web fallback for domain validation.
class DomainValidationService {
  static bool isDomainAllowed() => true;
  static String getCurrentDomain() => 'mobile_app';
  static bool isWebPlatform() => false;
  static void reportSuspiciousDomain() {}
  static void showDomainWarning() {}
}
