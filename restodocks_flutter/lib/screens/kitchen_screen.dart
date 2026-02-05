import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';

/// Экран кухни
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;
    final localization = context.watch<LocalizationService>();

    if (currentEmployee == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.t('kitchen')),
        actions: [
          if (currentEmployee.canEditChecklistsAndTechCards)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _createTechCard(context),
              tooltip: localization.t('create_tech_card'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Статистика кухни
            _buildKitchenStats(localization),

            const SizedBox(height: 24),

            // Кнопки быстрого доступа
            Text(
              localization.t('quick_actions'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _buildQuickActionCard(
                  context,
                  icon: Icons.restaurant_menu,
                  title: localization.t('tech_cards'),
                  subtitle: localization.t('manage_recipes'),
                  onTap: () => _navigateToTechCards(context),
                ),
                _buildQuickActionCard(
                  context,
                  icon: Icons.schedule,
                  title: localization.t('schedule'),
                  subtitle: localization.t('manage_schedule'),
                  onTap: () => _navigateToSchedule(context),
                ),
                _buildQuickActionCard(
                  context,
                  icon: Icons.inventory,
                  title: localization.t('inventory'),
                  subtitle: localization.t('check_stock'),
                  onTap: () => _navigateToInventory(context),
                ),
                _buildQuickActionCard(
                  context,
                  icon: Icons.analytics,
                  title: localization.t('reports'),
                  subtitle: localization.t('kitchen_reports'),
                  onTap: () => _navigateToReports(context),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Текущие задачи
            Text(
              localization.t('current_tasks'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            _buildTasksList(localization),
          ],
        ),
      ),
    );
  }

  Widget _buildKitchenStats(LocalizationService localization) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localization.t('kitchen_overview'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  localization.t('active_orders'),
                  '12',
                  Icons.shopping_cart,
                  Colors.blue,
                ),
                _buildStatItem(
                  localization.t('pending_prep'),
                  '5',
                  Icons.pending,
                  Colors.orange,
                ),
                _buildStatItem(
                  localization.t('ready_dishes'),
                  '8',
                  Icons.check_circle,
                  Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: Theme.of(context).primaryColor),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasksList(LocalizationService localization) {
    final tasks = [
      {'title': localization.t('prepare_sauces'), 'priority': 'high', 'time': '10 мин'},
      {'title': localization.t('chop_vegetables'), 'priority': 'medium', 'time': '15 мин'},
      {'title': localization.t('marinate_meat'), 'priority': 'low', 'time': '30 мин'},
    ];

    return Column(
      children: tasks.map((task) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              Icons.task,
              color: _getPriorityColor(task['priority']!),
            ),
            title: Text(task['title']!),
            subtitle: Text('${localization.t('time_remaining')}: ${task['time']}'),
            trailing: IconButton(
              icon: const Icon(Icons.check),
              onPressed: () {
                // TODO: Отметить задачу как выполненную
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${localization.t('task_completed')}: ${task['title']}')),
                );
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _createTechCard(BuildContext context) {
    context.push('/tech-cards/new');
  }

  void _navigateToTechCards(BuildContext context) {
    context.push('/tech-cards');
  }

  void _navigateToSchedule(BuildContext context) {
    context.push('/schedule');
  }

  void _navigateToInventory(BuildContext context) {
    context.push('/inventory');
  }

  void _navigateToReports(BuildContext context) {
    // TODO: Навигация к отчетам
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocalizationService>().t('reports_in_dev'))),
    );
  }
}