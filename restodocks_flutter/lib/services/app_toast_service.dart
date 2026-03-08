import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Toast overlay — компактное светлокрасное окошко по центру экрана. Скрывается по тапу (внутри или снаружи).
/// Use for success/delete messages. Keep SnackBar for errors that need user attention.
class AppToastService {
  AppToastService._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static OverlayEntry? _entry;
  static VoidCallback? _pendingOnTap;

  /// Call from MaterialApp build — pass the navigator key so we can access the overlay.
  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  static void show(String message, {VoidCallback? onTap}) {
    hide();
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;
    _pendingOnTap = onTap;

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
    _entry?.remove();
    _entry = null;
    _pendingOnTap = null;
  }
}
