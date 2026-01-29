import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// Заглушка раздела подразделения (кухня/бар/зал/менеджмент).
class DepartmentPlaceholderScreen extends StatelessWidget {
  const DepartmentPlaceholderScreen({super.key, required this.department});

  final String department;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final label = _label(loc, department);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(label),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icon(department), size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }

  String _label(LocalizationService loc, String d) {
    switch (d) {
      case 'kitchen': return loc.t('kitchen');
      case 'bar': return loc.t('bar');
      case 'hall': return loc.t('dining_room');
      case 'management': return loc.t('management');
      default: return d;
    }
  }

  IconData _icon(String d) {
    switch (d) {
      case 'kitchen': return Icons.restaurant;
      case 'bar': return Icons.local_bar;
      case 'hall': return Icons.table_restaurant;
      case 'management': return Icons.admin_panel_settings;
      default: return Icons.folder;
    }
  }
}
