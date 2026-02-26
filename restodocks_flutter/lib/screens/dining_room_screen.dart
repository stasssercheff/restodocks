import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Экран зала
class DiningRoomScreen extends StatelessWidget {
  const DiningRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('dining_room')),
      ),
      body: Center(
        child: Text(loc.t('screen_in_dev')),
      ),
    );
  }
}