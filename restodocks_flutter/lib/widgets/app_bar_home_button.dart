import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

Widget appBarHomeButton(BuildContext context) {
  final loc = context.read<LocalizationService>();
  return IconButton(
    icon: const Icon(Icons.home),
    onPressed: () => GoRouter.of(context).go('/home?tab=0'),
    tooltip: loc.t('home'),
  );
}
