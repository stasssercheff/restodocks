import 'package:flutter/material.dart';

/// Экран управления
class ManagementScreen extends StatelessWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление'),
      ),
      body: const Center(
        child: Text('Экран управления (в разработке)'),
      ),
    );
  }
}