import 'dart:html' as html;

import '../utils/dev_log.dart';

/// Сервис для валидации домена приложения
class DomainValidationService {
  /// Разрешенные домены для работы приложения
  /// ВНИМАНИЕ: При добавлении нового домена обновите этот список
  static const List<String> _allowedDomains = [
    'restodocks.vercel.app',  // Vercel deployment
    'restodocks.com',         // Основной домен (добавить когда будет)
    'www.restodocks.com',     // WWW версия основного домена
    // Добавьте сюда дополнительные домены по мере необходимости
  ];

  /// Домены Vercel (все preview и production деплои)
  /// Формат: restodocks-xxx-stassserchefs-projects.vercel.app и т.п.
  static bool _isVercelDomain(String domain) {
    return domain.endsWith('.vercel.app');
  }

  /// Дополнительные домены для разработки
  static const List<String> _devDomains = [
    'localhost',
    '127.0.0.1',
  ];

  /// Проверяет, является ли домен доменом разработки
  static bool _isDevDomain(String domain) {
    return _devDomains.contains(domain) ||
           domain.startsWith('localhost:') ||
           domain.startsWith('127.0.0.1:');
  }

  /// Проверяет, разрешен ли текущий домен
  static bool isDomainAllowed() {
    if (!isWebPlatform()) return true; // Для мобильных приложений всегда разрешено

    final hostname = html.window.location.hostname;
    if (hostname == null) return true; // Если hostname null, разрешаем (для edge cases)

    final currentDomain = hostname.toLowerCase();

    // Проверяем основные домены
    if (_allowedDomains.contains(currentDomain)) {
      return true;
    }

    // Проверяем домены Vercel (preview + production)
    if (_isVercelDomain(currentDomain)) {
      return true;
    }

    // Проверяем домены разработки
    if (_isDevDomain(currentDomain)) {
      return true;
    }

    return false;
  }

  /// Получает текущий домен
  static String getCurrentDomain() {
    if (!isWebPlatform()) return 'mobile_app';
    return html.window.location.hostname ?? 'unknown';
  }

  /// Проверяет, запущено ли приложение в браузере
  static bool isWebPlatform() {
    try {
      return html.window != null;
    } catch (e) {
      return false;
    }
  }

  /// Отправляет алерт о подозрительном домене (опционально)
  static void reportSuspiciousDomain() {
    if (!isWebPlatform()) return;

    final domain = getCurrentDomain();
    final userAgent = html.window.navigator.userAgent;
    final referrer = html.document.referrer;
    final timestamp = DateTime.now().toIso8601String();

    // Логируем в консоль для анализа
    devLog('🚨 DOMAIN SECURITY ALERT 🚨');
    devLog('Time: $timestamp');
    devLog('Domain: $domain');
    devLog('User-Agent: $userAgent');
    devLog('Referrer: $referrer');
    devLog('URL: ${html.window.location.href}');

    // В будущем можно отправить на сервер для мониторинга
    // _sendSecurityAlert({
    //   'type': 'domain_violation',
    //   'domain': domain,
    //   'userAgent': userAgent,
    //   'referrer': referrer,
    //   'timestamp': timestamp,
    //   'url': html.window.location.href,
    // });
  }

  /// Показывает предупреждение о неавторизованном домене
  static void showDomainWarning() {
    if (!isWebPlatform()) return;

    // Создаем overlay с предупреждением
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