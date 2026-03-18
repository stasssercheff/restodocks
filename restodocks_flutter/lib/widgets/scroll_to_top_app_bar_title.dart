import 'package:flutter/material.dart';

/// Оборачивает заголовок AppBar: тап = прокрутка PrimaryScrollController наверх.
///
/// Работает на телефоне и на вебе, если основной вертикальный скролл экрана
/// использует PrimaryScrollController (обычно это `ListView`/`SingleChildScrollView`
/// без явного controller).
class ScrollToTopAppBarTitle extends StatelessWidget {
  const ScrollToTopAppBarTitle({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
  });

  final Widget child;
  final Duration duration;

  void _scrollToTop(BuildContext context) {
    final c = PrimaryScrollController.maybeOf(context);
    if (c == null || !c.hasClients) return;
    c.animateTo(0, duration: duration, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _scrollToTop(context),
      child: child,
    );
  }
}

