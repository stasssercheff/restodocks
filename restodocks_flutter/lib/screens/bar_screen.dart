import 'package:flutter/material.dart';

/// Экран бара
class BarScreen extends StatelessWidget {
  const BarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Бар'),
      ),
      body: const Center(
        child: Text('Экран бара (в разработке)'),
      ),
    );
  }
}