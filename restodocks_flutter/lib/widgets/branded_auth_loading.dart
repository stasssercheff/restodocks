import 'package:flutter/material.dart';

/// Экран ожидания при переходе по ссылке подтверждения и т.п.: только логотип, без подписи «Вход».
class BrandedAuthLoading extends StatelessWidget {
  const BrandedAuthLoading({super.key, this.logoWidth = 168});

  final double logoWidth;

  @override
  Widget build(BuildContext context) {
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
