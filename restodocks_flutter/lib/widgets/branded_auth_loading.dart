import 'package:flutter/material.dart';

/// Экран ожидания при переходе по ссылке подтверждения и т.п.: только логотип, без подписи «Вход».
class BrandedAuthLoading extends StatelessWidget {
  const BrandedAuthLoading({
    super.key,
    this.logoWidth = 168,
    this.fullscreenLogo = false,
  });

  final double logoWidth;
  final bool fullscreenLogo;

  @override
  Widget build(BuildContext context) {
    if (fullscreenLogo) {
      return Semantics(
        label: 'Restodocks',
        child: ColoredBox(
          // Match the red splash background from `web/index.html` so the transition
          // doesn't look like a "second logo".
          color: Theme.of(context).colorScheme.primary,
          child: SizedBox.expand(
            child: Image.asset(
              'assets/images/welcome_logo.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Semantics(
          label: 'Restodocks',
          child: Image.asset(
            'assets/images/welcome_logo.png',
            width: logoWidth,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
