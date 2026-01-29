import 'package:flutter/material.dart';

/// Экран зала
class DiningRoomScreen extends StatelessWidget {
  const DiningRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Зал'),
      ),
      body: const Center(
        child: Text('Экран зала (в разработке)'),
      ),
    );
  }
}