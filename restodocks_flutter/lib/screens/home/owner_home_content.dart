import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// Домашняя страница владельца: график, кухня, бар, зал, менеджмент, уведомления, расходы.
class OwnerHomeContent extends StatelessWidget {
  const OwnerHomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SectionTitle(title: loc.t('schedule')),
          _buildTilesGrid(context, [
            _TileData(
              icon: Icons.calendar_month,
              title: loc.t('schedule'),
              subtitle: loc.t('manage_schedule'),
              onTap: () => context.push('/schedule'),
              color: Colors.blue,
            ),
            _TileData(
              icon: Icons.description,
              title: loc.t('tech_cards'),
              onTap: () => context.push('/tech-cards'),
              color: Colors.green,
            ),
            _TileData(
              icon: Icons.library_books,
              title: loc.t('products'),
              subtitle: loc.t('product_database'),
              onTap: () => context.push('/products'),
              color: Colors.teal,
            ),
            _TileData(
              icon: Icons.upload_file,
              title: loc.t('upload_products'),
              subtitle: loc.t('upload_products_desc'),
              onTap: () => context.push('/products/upload'),
              color: Colors.purple,
            ),
            _TileData(
              icon: Icons.assignment,
              title: loc.t('inventory_blank'),
              onTap: () => context.push('/inventory'),
              color: Colors.purple,
            ),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: loc.t('kitchen')),
          _buildTilesGrid(context, [
            _TileData(
              icon: Icons.restaurant,
              title: loc.t('schedule'),
              subtitle: loc.t('payroll_kitchen'),
              onTap: () => context.push('/department/kitchen'),
              color: Colors.red,
            ),
            _TileData(
              icon: Icons.restaurant_menu,
              title: loc.t('dish_cards'),
              onTap: () => context.push('/products'),
              color: Colors.teal,
            ),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: loc.t('bar')),
          _buildTilesGrid(context, [
            _TileData(
              icon: Icons.local_bar,
              title: loc.t('schedule'),
              subtitle: loc.t('payroll_bar'),
              onTap: () => context.push('/department/bar'),
              color: Colors.indigo,
            ),
            _TileData(
              icon: Icons.wine_bar,
              title: loc.t('drink_cards'),
              onTap: () => context.push('/products'),
              color: Colors.amber,
            ),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: loc.t('dining_room')),
          _buildTilesGrid(context, [
            _TileData(
              icon: Icons.table_restaurant,
              title: loc.t('schedule'),
              subtitle: loc.t('payroll_hall'),
              onTap: () => context.push('/department/hall'),
              color: Colors.brown,
            ),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: loc.t('management')),
          _buildTilesGrid(context, [
            _TileData(
              icon: Icons.admin_panel_settings,
              title: loc.t('schedule'),
              subtitle: loc.t('payroll_management'),
              onTap: () => context.push('/department/management'),
              color: Colors.grey,
            ),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: loc.t('notifications')),
          _buildTilesGrid(context, [
            _TileData(
              icon: Icons.notifications,
              title: loc.t('notifications'),
              onTap: () => context.push('/notifications'),
              color: Colors.cyan,
            ),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: '${loc.t('expenses')} (${loc.t('pro')})'),
          _buildTilesGrid(context, [
            _TileData(
              icon: Icons.savings,
              title: loc.t('expenses'),
              subtitle: '${loc.t('payroll_plan')}, ${loc.t('rent_plan')}, ...',
              onTap: () => context.push('/expenses'),
              color: Colors.deepPurple,
            ),
          ]),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _TileData {
  const _TileData({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
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
                      color: Color(0x80000000),
                      offset: Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (data.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  data.subtitle!,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    shadows: [
                      const Shadow(
                        color: Color(0x80000000),
                        offset: Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
