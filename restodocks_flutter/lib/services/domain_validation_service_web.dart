// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../utils/dev_log.dart';

/// Сервис для валидации домена приложения
class DomainValidationService {
  static const List<String> _allowedDomains = [
    'restodocks.vercel.app',
    'restodocks.com',
    'www.restodocks.com',
  ];

  static bool _isVercelDomain(String domain) => domain.endsWith('.vercel.app');

  static const List<String> _devDomains = ['localhost', '127.0.0.1'];

  static bool _isDevDomain(String domain) {
    return _devDomains.contains(domain) ||
        domain.startsWith('localhost:') ||
        domain.startsWith('127.0.0.1:');
  }

  static bool isDomainAllowed() {
    if (!isWebPlatform()) return true;
    final hostname = html.window.location.hostname;
    if (hostname == null) return true;

    final currentDomain = hostname.toLowerCase();
    if (_allowedDomains.contains(currentDomain)) return true;
    if (_isVercelDomain(currentDomain)) return true;
    if (_isDevDomain(currentDomain)) return true;
    return false;
  }

  static String getCurrentDomain() {
    if (!isWebPlatform()) return 'mobile_app';
    return html.window.location.hostname ?? 'unknown';
  }

  static bool isWebPlatform() {
    try {
      return html.window != null;
    } catch (_) {
      return false;
    }
  }

  static void reportSuspiciousDomain() {
    if (!isWebPlatform()) return;

    final domain = getCurrentDomain();
    final userAgent = html.window.navigator.userAgent;
    final referrer = html.document.referrer;
    final timestamp = DateTime.now().toIso8601String();

    devLog('🚨 DOMAIN SECURITY ALERT 🚨');
    devLog('Time: $timestamp');
    devLog('Domain: $domain');
    devLog('User-Agent: $userAgent');
    devLog('Referrer: $referrer');
    devLog('URL: ${html.window.location.href}');
  }

  static void showDomainWarning() {
    if (!isWebPlatform()) return;

    final overlay = html.DivElement()
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'rgba(0, 0, 0, 0.8)'
      ..style.zIndex = '9999'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.fontFamily = 'Arial, sans-serif';

    final message = html.DivElement()
      ..style.backgroundColor = '#ff4444'
      ..style.color = 'white'
      ..style.padding = '20px'
      ..style.borderRadius = '8px'
      ..style.maxWidth = '400px'
      ..style.textAlign = 'center'
      ..innerHtml = '''
        <h2>🚫 Доступ запрещен</h2>
        <p>Это приложение может работать только на официальных доменах.</p>
        <p>Текущий домен: ${getCurrentDomain()}</p>
        <br>
        <small>Если вы считаете, что это ошибка, обратитесь в поддержку.</small>
      ''';

    overlay.append(message);
    html.document.body?.append(overlay);
  }
}
