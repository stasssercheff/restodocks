import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Кнопка «назад»: если есть стек — pop(), иначе — переход на главную
/// с обратной анимацией (экран уходит вправо).
Widget appBarBackButton(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.only(left: 6),
    child: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        if (GoRouter.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/home', extra: {'back': true});
        }
      },
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    ),
  );
}
