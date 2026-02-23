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
            _TileData(icon: Icons.calendar_month, title: loc.t('schedule'), subtitle: loc.t('all_employees_schedule'), onTap: () => context.push('/schedule')),
            _TileData(icon: Icons.inbox, title: 'Входящие', onTap: () => context.push('/inbox')),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Кухня'),
          _buildTilesGrid(context, [
            _TileData(icon: Icons.schedule, title: 'График', onTap: () => context.push('/schedule/kitchen')),
            _TileData(icon: Icons.restaurant_menu, title: 'Меню', onTap: () => context.push('/menu/kitchen')),
            _TileData(icon: Icons.description, title: 'Технологические карты', onTap: () => context.push('/tech-cards/kitchen')),
            _TileData(icon: Icons.assignment, title: 'Номенклатура', onTap: () => context.push('/nomenclature/kitchen')),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Бар (pro)'),
          _buildTilesGrid(context, [
            _TileData(icon: Icons.schedule, title: 'График', onTap: () => context.push('/schedule/bar')),
            _TileData(icon: Icons.wine_bar, title: 'Меню', onTap: () => context.push('/menu/bar')),
            _TileData(icon: Icons.description, title: 'Технологические карты', onTap: () => context.push('/tech-cards/bar')),
            _TileData(icon: Icons.assignment, title: 'Номенклатура', onTap: () => context.push('/nomenclature/bar')),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Зал'),
          _buildTilesGrid(context, [
            _TileData(icon: Icons.schedule, title: 'График', onTap: () => context.push('/schedule/hall')),
            _TileData(icon: Icons.assignment, title: 'Номенклатура', onTap: () => context.push('/nomenclature/hall')),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Управление'),
          _buildTilesGrid(context, [
            _TileData(icon: Icons.schedule, title: 'График', onTap: () => context.push('/schedule/management')),
            _TileData(icon: Icons.people, title: 'Сотрудники', onTap: () => context.push('/employees')),
          ]),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Расходы (pro)'),
          _buildTilesGrid(context, [
            _TileData(icon: Icons.payments, title: 'ФЗП', subtitle: loc.t('salary_expenses'), onTap: () => context.push('/expenses/salary')),
            _TileData(icon: Icons.business, title: 'Аренда', subtitle: loc.t('rent_expenses'), onTap: () => context.push('/expenses/rent')),
            _TileData(icon: Icons.shopping_cart, title: 'Закупка', subtitle: loc.t('purchase_expenses'), onTap: () => context.push('/expenses/purchase')),
            _TileData(icon: Icons.settings, title: loc.t('custom_expense'), subtitle: loc.t('configurable_expense_name'), onTap: () => context.push('/expenses/custom')),
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
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
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
        itemBuilder: (context, index) => _Tile(data: tiles[index]),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.data});

  final _TileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(data.icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                data.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (data.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  data.subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
