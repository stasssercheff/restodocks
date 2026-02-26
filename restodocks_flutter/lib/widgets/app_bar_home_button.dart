import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Кнопка «назад»: если есть стек — pop(), иначе — переход на главную.
/// Решает проблему, когда после F5 или go() в стеке нечего pop'ать.
Widget appBarBackButton(BuildContext context) {
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      if (GoRouter.of(context).canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    },
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
  );
}
