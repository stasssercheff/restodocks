import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/services.dart';

/// Раскладывающаяся секция «Банкет / Кейтринг» — внутри Меню и ТТК.
/// [department] — 'kitchen' (банкет кухни) или 'bar' (банкет бара, разграничение данных).
class ExpandableBanquetSection extends StatelessWidget {
  const ExpandableBanquetSection({
    super.key,
    required this.loc,
    this.department = 'kitchen',
  });

  final LocalizationService loc;
  final String department;

  String get _menuRoute => department == 'bar' ? '/menu/banquet-catering-bar' : '/menu/banquet-catering';
  String get _ttkRoute => department == 'bar' ? '/tech-cards/banquet-catering-bar' : '/tech-cards/banquet-catering';
  String get _ttkLabel => department == 'bar' ? loc.t('ttk_bar') : loc.t('ttk_kitchen');

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.celebration),
        title: Text(loc.t('banquet_catering')),
        trailing: const Icon(Icons.chevron_right),
        children: [
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: Text(loc.t('menu')),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => context.go(_menuRoute),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: Text(_ttkLabel),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => context.go(_ttkRoute),
          ),
        ],
      ),
    );
  }
}
