import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Кнопка «Домой» для AppBar — единообразная на всех экранах (кроме самой домашней).
Widget appBarHomeButton(BuildContext context) {
  final loc = context.read<LocalizationService>();
  return IconButton(
    icon: const Icon(Icons.home),
    onPressed: () => context.go('/home'),
    tooltip: loc.t('home'),
  );
}
