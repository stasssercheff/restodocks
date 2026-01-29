import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../models/models.dart';

/// Экран профиля пользователя
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;
    final establishment = accountManager.establishment;
    final localization = context.watch<LocalizationService>();

    if (currentEmployee == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())
            : null,
        title: Text(localization.t('profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: localization.t('home'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Информация о профиле
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Фото профиля
                    Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          size: 50,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Имя
                    Text(
                      currentEmployee.fullName,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),

                    // Роли и отдел (все роли: Владелец, Шеф-повар и т.д.)
                    Text(
                      '${currentEmployee.rolesDisplayText} • ${currentEmployee.departmentDisplayName}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                      textAlign: TextAlign.center,
                    ),

                    // Email
                    Text(
                      currentEmployee.email,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Информация о компании
            if (establishment != null) ...[
              Text(
                localization.t('company_info'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        establishment.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('PIN: ${establishment.pinCode}'),
                      if (establishment.phone != null) ...[
                        const SizedBox(height: 4),
                        Text('Телефон: ${establishment.phone}'),
                      ],
                      if (establishment.email != null) ...[
                        const SizedBox(height: 4),
                        Text('Email: ${establishment.email}'),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            if (!currentEmployee.hasRole('owner')) ...[
              Text(
                localization.t('schedule'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: Text(localization.t('schedule')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/schedule'),
              ),
              ListTile(
                leading: const Icon(Icons.numbers),
                title: Text(localization.t('shift_count')),
                subtitle: Text('0'),
                trailing: const Icon(Icons.chevron_right),
              ),
              const SizedBox(height: 24),
            ],

            Text(
              localization.t('data'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(leading: const Icon(Icons.person), title: Text(localization.t('name')), subtitle: Text(currentEmployee.fullName)),
                  ListTile(leading: const Icon(Icons.badge), title: Text('${localization.t('surname')} (${localization.t('pro')})'), subtitle: const Text('—')),
                  ListTile(leading: const Icon(Icons.email), title: Text(localization.t('email')), subtitle: Text(currentEmployee.email)),
                  ListTile(leading: const Icon(Icons.cake), title: Text('${localization.t('birth_date')} (${localization.t('pro')})'), subtitle: const Text('—')),
                  ListTile(leading: const Icon(Icons.flag), title: Text(localization.t('citizenship')), subtitle: const Text('—')),
                  ListTile(leading: const Icon(Icons.photo_camera), title: Text('${localization.t('photo')} (${localization.t('pro')})'), subtitle: const Text('—')),
                  ListTile(leading: const Icon(Icons.payments), title: Text(localization.t('pay_rate')), subtitle: const Text('—')),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              localization.t('notifications'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: Text(localization.t('notifications')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/notifications'),
            ),
            const SizedBox(height: 20),

            Text(
              localization.t('settings'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(localization.t('language')),
              subtitle: Text(localization.getLanguageName(localization.currentLanguageCode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguagePicker(context, localization),
            ),
            ListTile(
              leading: const Icon(Icons.palette),
              title: Text(localization.t('appearance')),
              subtitle: Text(localization.t('light_theme')),
              trailing: const Icon(Icons.chevron_right),
            ),
            if (currentEmployee.canManageSchedule) ...[
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: Text(localization.t('currency')),
                subtitle: Text(establishment?.currencySymbol ?? '₽'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showCurrencyPicker(context, localization),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text('${localization.t('home_button_config')} (${localization.t('pro')})'),
              trailing: const Icon(Icons.chevron_right),
            ),
            if (currentEmployee.hasRole('owner'))
              ListTile(
                leading: const Icon(Icons.star),
                title: Text(localization.t('pro_purchase')),
                trailing: const Icon(Icons.chevron_right),
              ),
            const SizedBox(height: 8),

            const Divider(),

            ListTile(
              leading: const Icon(Icons.cloud, color: Colors.blue),
              title: Text(localization.t('supabase_test')),
              subtitle: const Text('Проверить подключение'),
              onTap: () => context.push('/supabase-test'),
            ),

            const Divider(),

            // Выход
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                localization.t('logout'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, LocalizationService localization) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 400),
              decoration: BoxDecoration(
                color: Theme.of(ctx).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(
                      localization.t('language'),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: localization.availableLanguages.map((language) {
                        return ListTile(
                          leading: Text(language['flag']!, style: const TextStyle(fontSize: 24)),
                          title: Text(language['name']!),
                          onTap: () async {
                            await localization.setLocale(Locale(language['code']!));
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCurrencyPicker(BuildContext context, LocalizationService localization) {
    final currencies = [
      {'code': 'RUB', 'name': 'Рубль (₽)', 'symbol': '₽'},
      {'code': 'USD', 'name': 'Доллар (\$)', 'symbol': '\$'},
      {'code': 'EUR', 'name': 'Евро (€)', 'symbol': '€'},
      {'code': 'GBP', 'name': 'Фунт (£)', 'symbol': '£'},
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: currencies.map((currency) {
              return ListTile(
                leading: Text(currency['symbol']!, style: const TextStyle(fontSize: 20)),
                title: Text(currency['name']!),
                onTap: () {
                  // TODO: Сохранить выбранную валюту
                  context.pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Валюта изменена на ${currency['name']}')),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    final accountManager = context.read<AccountManagerSupabase>();
    await accountManager.logout();
    if (context.mounted) context.go('/login');
  }
}