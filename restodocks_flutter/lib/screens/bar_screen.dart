import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Экран бара
class BarScreen extends StatelessWidget {
  const BarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('bar')),
      ),
      body: Center(
        child: Text(loc.t('screen_in_dev')),
      ),
    );
  }
}