import 'package:flutter/material.dart';

/// Toast overlay at the top of the screen. Replaces previous on new show. Dismiss on tap.
/// Use for success/delete messages. Keep SnackBar for errors that need user attention.
class AppToastService {
  AppToastService._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static OverlayEntry? _entry;

  /// Call from MaterialApp build — pass the navigator key so we can access the overlay.
  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  static void show(String message, {VoidCallback? onTap}) {
    hide();
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {
              onTap?.call();
              hide();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Text(
                  message,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}
