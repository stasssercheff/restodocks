import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

/// Toast overlay — компактное светлокрасное окошко. Скрывается по тапу в любое место.
/// show — модальное окошко в центре (для сохранений, отправок, feedback).
/// showBanner — плашка сверху (для входящих уведомлений).
class AppToastService {
  AppToastService._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static OverlayEntry? _entry;
  static VoidCallback? _pendingOnTap;
  static Timer? _autoHideTimer;

  /// Call from MaterialApp build — pass the navigator key so we can access the overlay.
  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  /// Плашка сверху экрана (slide-in). Для уведомлений о входящих.
  static void showBanner(String message, {VoidCallback? onTap}) {
    hide();
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;
    _pendingOnTap = onTap;

    _entry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final bgColor = Color.lerp(Colors.white, AppTheme.primaryColor, 0.12) ?? theme.colorScheme.errorContainer;
        final textColor = theme.brightness == Brightness.dark ? Colors.white : const Color(0xFF5C1F21);

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                _pendingOnTap?.call();
                hide();
              },
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active, color: AppTheme.primaryColor, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(color: textColor, fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
  }

  /// Окошко в центре экрана. Тап в любое место — закрыть. Опционально автоскрытие через [duration].
  static void show(String message, {VoidCallback? onTap, Duration? duration}) {
    hide();
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;
    _pendingOnTap = onTap;
    _autoHideTimer?.cancel();
    if (duration != null && duration > Duration.zero) {
      _autoHideTimer = Timer(duration, hide);
    }

    _entry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final lightRed = Color.lerp(Colors.white, AppTheme.primaryColor, 0.12) ?? theme.colorScheme.errorContainer;
        final textColor = theme.brightness == Brightness.dark ? Colors.white : const Color(0xFF5C1F21);

        return Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                _pendingOnTap?.call();
                hide();
              },
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: lightRed,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
      },
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _entry?.remove();
    _entry = null;
    _pendingOnTap = null;
  }

  /// Переход во входящие → Уведомления (для уведомления о днях рождения).
  static void goToInboxNotifications() {
    hide();
    final ctx = _navigatorKey?.currentState?.context ?? AppRouter.rootNavigatorKey.currentContext;
    if (ctx != null) {
      GoRouter.of(ctx).go('/inbox?tab=notifications');
    }
  }
}
