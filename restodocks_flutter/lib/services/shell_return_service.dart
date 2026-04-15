import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Якорь «рабочего» экрана при переходе с нижней панели на личный кабинет или
/// среднюю вкладку: кнопка «Назад» в AppBar ведёт на сохранённый маршрут.
class ShellReturnService extends ChangeNotifier {
  String? _pendingLocation;

  String? get pendingLocation => _pendingLocation;

  static String locationFromRouterState(GoRouterState state) {
    final loc = state.location;
    if (loc.isEmpty) return '/';
    return loc.startsWith('/') ? loc : '/$loc';
  }

  /// Path без query (для проверки «дом» / дерево кабинета).
  static String _pathOnly(GoRouterState state) {
    final loc = state.location;
    if (loc.isEmpty) return '/';
    final q = loc.indexOf('?');
    final raw = q < 0 ? loc : loc.substring(0, q);
    return raw.startsWith('/') ? raw : '/$raw';
  }

  bool _isHomePath(String path) => path == '/' || path == '/home';

  bool _isCabinetTreePath(String path) {
    return path.startsWith('/personal-cabinet') ||
        path.startsWith('/profile') ||
        path.startsWith('/settings') ||
        path.startsWith('/establishments');
  }

  bool _isSafeReturnLocation(String loc) {
    if (loc.isEmpty) return false;
    if (loc.contains('..') || loc.contains('://')) return false;
    return loc.startsWith('/');
  }

  /// Перед [context.go] из нижней панели: [tabIndex] 0 = домой, 1 = середина, 2 = кабинет.
  /// [middleRoute] — целевой путь средней кнопки (как в [HomeButtonAction.routeFor]).
  void onFooterWillNavigate(
    BuildContext context, {
    required int tabIndex,
    required String middleRoute,
  }) {
    if (tabIndex == 0) {
      if (_pendingLocation != null) {
        _pendingLocation = null;
        notifyListeners();
      }
      return;
    }

    final state = GoRouterState.of(context);
    final current = locationFromRouterState(state);
    final currentPath = _pathOnly(state);

    if (_isHomePath(currentPath)) {
      if (_pendingLocation != null) {
        _pendingLocation = null;
        notifyListeners();
      }
      return;
    }

    if (tabIndex == 1 || tabIndex == 2) {
      if (_isCabinetTreePath(currentPath) && _pendingLocation != null) {
        return;
      }
      if (_isCabinetTreePath(currentPath) && _pendingLocation == null) {
        return;
      }

      if (tabIndex == 1 && _locationsEquivalent(current, middleRoute)) {
        return;
      }
      if (tabIndex == 2 &&
          currentPath.startsWith('/personal-cabinet') &&
          _pendingLocation == null) {
        return;
      }

      if (!_isSafeReturnLocation(current)) return;

      _pendingLocation = current;
      notifyListeners();
    }
  }

  void clearPending() {
    if (_pendingLocation == null) return;
    _pendingLocation = null;
    notifyListeners();
  }

  String? takePending() {
    final v = _pendingLocation;
    _pendingLocation = null;
    if (v != null) notifyListeners();
    return v;
  }

  bool shouldOfferReturnTo(BuildContext context) {
    final p = _pendingLocation;
    if (p == null || !_isSafeReturnLocation(p)) return false;
    final cur = locationFromRouterState(GoRouterState.of(context));
    return !_locationsEquivalent(p, cur);
  }
}

bool shellReturnLocationsEquivalent(String a, String b) =>
    _locationsEquivalent(a, b);

bool _locationsEquivalent(String a, String b) {
  final pa = _splitPathQuery(a);
  final pb = _splitPathQuery(b);
  return pa.$1 == pb.$1 && pa.$2 == pb.$2;
}

/// Путь без query и строка query (как в URI), для сравнения маршрутов.
(String path, String query) _splitPathQuery(String loc) {
  final t = loc.trim();
  final i = t.indexOf('?');
  if (i < 0) {
    var path = t.isEmpty ? '/' : t;
    if (!path.startsWith('/')) path = '/$path';
    return (path, '');
  }
  var path = t.substring(0, i);
  if (path.isEmpty) {
    path = '/';
  } else if (!path.startsWith('/')) {
    path = '/$path';
  }
  return (path, t.substring(i + 1));
}
