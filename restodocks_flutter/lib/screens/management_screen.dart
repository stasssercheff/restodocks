import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Экран управления
class ManagementScreen extends StatelessWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.read<LocalizationService>().t('management')),
      ),
      body: Center(
        child: Text(context.read<LocalizationService>().t('screen_in_dev')),
      ),
    );
  }
}