import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../models/models.dart';

/// Домашняя страница менеджмента (шеф, барменеджер, менеджер зала, управляющий).
class ManagementHomeContent extends StatelessWidget {
  const ManagementHomeContent({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final roles = employee.roles;
    final isChef = roles.contains('executive_chef');
    final isBarManager = roles.contains('bar_manager');
    final isGeneral = roles.contains('general_manager');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTilesGrid(context, [
            _TileData(
              icon: Icons.calendar_month,
              title: loc.t('schedule'),
              onTap: () => context.push('/schedule'),
              color: Colors.blue,
            ),
            _TileData(
              icon: Icons.notifications,
              title: loc.t('notifications'),
              onTap: () => context.push('/notifications'),
              color: Colors.cyan,
            ),
            _TileData(
              icon: Icons.people,
              title: loc.t('employees'),
              onTap: () => context.push('/employees'),
              color: Colors.green,
            ),
            if (isChef || roles.contains('sous_chef'))
              _TileData(
                icon: Icons.how_to_reg,
                title: loc.t('shift_confirmation'),
                onTap: () => context.push('/shift-confirmation'),
                color: Colors.indigo,
              ),
            if (isChef)
              _TileData(
                icon: Icons.shopping_bag,
                title: loc.t('products'),
                onTap: () => context.push('/products'),
                color: Colors.orange,
              ),
            // Чеклисты: кухня или шеф/су-шеф (у шефа часто отдел «Управление» — иначе плитки нет)
            if (employee.department == 'kitchen' || isChef || roles.contains('sous_chef'))
              _TileData(
                icon: Icons.checklist,
                title: loc.t('checklists'),
                onTap: () => context.push('/checklists'),
                color: Colors.purple,
              ),
            _TileData(
              icon: Icons.description,
              title: isBarManager ? loc.t('ttk_bar') : loc.t('ttk_kitchen'),
              onTap: () => context.push('/tech-cards'),
              color: Colors.teal,
            ),
            _TileData(
              icon: Icons.inventory_2,
              title: loc.t('nomenclature'),
              onTap: () => context.push('/products'),
              color: Colors.deepOrange,
            ),
            _TileData(
              icon: Icons.library_books,
              title: loc.t('product_catalog'),
              onTap: () => context.push('/products/catalog'),
              color: Colors.deepPurple,
            ),
            if (isChef || isBarManager)
              _TileData(
                icon: Icons.shopping_cart,
                title: loc.t('product_order'),
                onTap: () => context.push('/product-order'),
                color: Colors.brown,
              ),
            if (isChef) ...[
              _TileData(
                icon: Icons.assignment,
                title: loc.t('inventory_blank'),
                onTap: () => context.push('/inventory'),
                color: Colors.amber,
              ),
              _TileData(
                icon: Icons.inbox,
                title: loc.t('inventory_received'),
                onTap: () => context.push('/inventory-received'),
                color: Colors.grey,
              ),
            ],
            if (isGeneral) ...[
              _TileData(
                icon: Icons.savings,
                title: '${loc.t('expenses')} (${loc.t('pro')})',
                onTap: () => context.push('/expenses'),
                color: Colors.red,
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

class _TileData {
  const _TileData({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color color;
}

Widget _buildTilesGrid(BuildContext context, List<_TileData> tiles) {
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.2,
        ),
        itemCount: tiles.length,
        itemBuilder: (context, index) => _Tile(
          data: tiles[index],
        ),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.data,
  });

  final _TileData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: data.color,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                data.icon,
                size: 32,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                data.title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    const Shadow(
                      color: Colors.black54,
                      offset: Offset(1, 1),
                      blurRadius: 3,
                    ),
                    const Shadow(
                      color: Colors.black26,
                      offset: Offset(0, 0),
                      blurRadius: 6,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
