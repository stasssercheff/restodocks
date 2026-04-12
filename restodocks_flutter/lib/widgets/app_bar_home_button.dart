import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/shell_return_service.dart';

/// Кнопка «назад» на сохранённый рабочий экран (нижняя панель → кабинет / середина).
/// Иначе `null` — использовать обычный [appBarBackButton] или свой leading.
Widget? shellReturnLeading(BuildContext context) {
  final shell = context.watch<ShellReturnService>();
  if (!shell.shouldOfferReturnTo(context)) return null;
  return Padding(
    padding: const EdgeInsets.only(left: 6),
    child: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        final target = context.read<ShellReturnService>().takePending();
        if (target == null) return;
        context.go(target);
      },
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    ),
  );
}

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
