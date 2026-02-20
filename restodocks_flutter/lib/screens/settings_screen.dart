import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Экран только настроек: язык, тема, валюта и т.д. Без данных профиля (профиль — отдельная кнопка).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Основные валюты мира (как в Numbers/Excel)
  static const List<Map<String, String>> _currencies = [
    {'code': 'RUB', 'symbol': '₽', 'name': 'Российский рубль'},
    {'code': 'USD', 'symbol': '\$', 'name': 'Доллар США'},
    {'code': 'EUR', 'symbol': '€', 'name': 'Евро'},
    {'code': 'GBP', 'symbol': '£', 'name': 'Фунт стерлингов'},
    {'code': 'CHF', 'symbol': 'Fr', 'name': 'Швейцарский франк'},
    {'code': 'JPY', 'symbol': '¥', 'name': 'Японская иена'},
    {'code': 'CNY', 'symbol': '¥', 'name': 'Китайский юань'},
    {'code': 'VND', 'symbol': '₫', 'name': 'Вьетнамский донг'},
    {'code': 'KZT', 'symbol': '₸', 'name': 'Казахстанский тенге'},
    {'code': 'UAH', 'symbol': '₴', 'name': 'Украинская гривна'},
    {'code': 'BYN', 'symbol': 'Br', 'name': 'Белорусский рубль'},
    {'code': 'PLN', 'symbol': 'zł', 'name': 'Польский злотый'},
    {'code': 'CZK', 'symbol': 'Kč', 'name': 'Чешская крона'},
    {'code': 'TRY', 'symbol': '₺', 'name': 'Турецкая лира'},
    {'code': 'INR', 'symbol': '₹', 'name': 'Индийская рупия'},
    {'code': 'BRL', 'symbol': 'R\$', 'name': 'Бразильский реал'},
    {'code': 'MXN', 'symbol': '\$', 'name': 'Мексиканское песо'},
    {'code': 'KRW', 'symbol': '₩', 'name': 'Южнокорейская вона'},
    {'code': 'SGD', 'symbol': 'S\$', 'name': 'Сингапурский доллар'},
    {'code': 'HKD', 'symbol': 'HK\$', 'name': 'Гонконгский доллар'},
    {'code': 'THB', 'symbol': '฿', 'name': 'Тайский бат'},
    {'code': 'CAD', 'symbol': 'C\$', 'name': 'Канадский доллар'},
    {'code': 'AUD', 'symbol': 'A\$', 'name': 'Австралийский доллар'},
    {'code': 'SEK', 'symbol': 'kr', 'name': 'Шведская крона'},
    {'code': 'NOK', 'symbol': 'kr', 'name': 'Норвежская крона'},
    {'code': 'DKK', 'symbol': 'kr', 'name': 'Датская крона'},
    {'code': 'IDR', 'symbol': 'Rp', 'name': 'Индонезийская рупия'},
    {'code': 'PHP', 'symbol': '₱', 'name': 'Филиппинское песо'},
    {'code': 'MYR', 'symbol': 'RM', 'name': 'Малайзийский ринггит'},
    {'code': 'AED', 'symbol': 'د.إ', 'name': 'Дирхам ОАЭ'},
    {'code': 'SAR', 'symbol': '﷼', 'name': 'Саудовский риал'},
    {'code': 'ILS', 'symbol': '₪', 'name': 'Израильский шекель'},
    {'code': 'EGP', 'symbol': 'E£', 'name': 'Египетский фунт'},
    {'code': 'ZAR', 'symbol': 'R', 'name': 'Южноафриканский рэнд'},
    {'code': 'NGN', 'symbol': '₦', 'name': 'Нигерийская найра'},
    {'code': 'GEL', 'symbol': '₾', 'name': 'Грузинский лари'},
    {'code': 'AMD', 'symbol': '֏', 'name': 'Армянский драм'},
    {'code': 'AZN', 'symbol': '₼', 'name': 'Азербайджанский манат'},
    {'code': 'UZS', 'symbol': 'soʻm', 'name': 'Узбекский сум'},
  ];

  String _homeButtonActionLabel(LocalizationService loc, HomeButtonAction action) {
    switch (action) {
      case HomeButtonAction.schedule:
        return loc.t('schedule');
      case HomeButtonAction.checklists:
        return loc.t('checklists');
      case HomeButtonAction.ttk:
        return loc.t('tech_cards');
      case HomeButtonAction.productOrder:
        return loc.t('product_order');
    }
  }

  void _showProRequiredDialog(BuildContext context, LocalizationService loc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${loc.t('home_button_config')} (${loc.t('pro')})'),
        content: Text(loc.t('pro_required_hint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  void _showHomeButtonPicker(BuildContext context, LocalizationService loc, HomeButtonConfigService homeBtn) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('home_button_config')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: HomeButtonAction.values.map((action) {
            final selected = homeBtn.action == action;
            return ListTile(
              leading: Icon(action.icon, color: selected ? Theme.of(ctx).colorScheme.primary : null),
              title: Text(_homeButtonActionLabel(loc, action)),
              trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                await homeBtn.setAction(action);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            );
          }).toList(),
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

  void _showCurrencyPicker(BuildContext context, LocalizationService loc) {
    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    if (establishment == null) return;

    final currentCode = establishment.defaultCurrency.toUpperCase();
    final customController = TextEditingController();
    var useOther = !_currencies.any((c) => c['code'] == currentCode);
    if (useOther) customController.text = currentCode;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx2).dialogBackgroundColor,
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
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Text(
                          loc.t('currency'),
                          style: Theme.of(ctx2).textTheme.titleMedium,
                        ),
                      ),
                      CheckboxListTile(
                        value: useOther,
                        onChanged: (v) => setDialogState(() => useOther = v ?? false),
                        title: Text(loc.t('custom_currency'), style: const TextStyle(fontSize: 14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (useOther)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: TextField(
                            controller: customController,
                            decoration: InputDecoration(
                              labelText: loc.t('currency_code'),
                              hintText: loc.t('currency_hint'),
                              border: const OutlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 3,
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            children: _currencies.map((c) {
                              final code = c['code']!;
                              final symbol = c['symbol']!;
                              final name = c['name']!;
                              final selected = currentCode == code;
                              return ListTile(
                                leading: Text(symbol, style: const TextStyle(fontSize: 20)),
                                title: Text('$code — $name'),
                                trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                                onTap: () async {
                                  final updated = establishment.copyWith(
                                    defaultCurrency: code,
                                    updatedAt: DateTime.now(),
                                  );
                                  await account.updateEstablishment(updated);
                                  if (ctx2.mounted) {
                                    Navigator.of(ctx2).pop();
                                    ScaffoldMessenger.of(ctx2).showSnackBar(
                                      SnackBar(content: Text('${loc.t('currency_saved')}: $code')),
                                    );
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      if (useOther)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx2).pop(),
                                child: Text(MaterialLocalizations.of(ctx2).cancelButtonLabel),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () async {
                                  final code = customController.text.trim().toUpperCase();
                                  if (code.length != 3) return;
                                  final updated = establishment.copyWith(
                                    defaultCurrency: code,
                                    updatedAt: DateTime.now(),
                                  );
                                  await account.updateEstablishment(updated);
                                  if (ctx2.mounted) {
                                    Navigator.of(ctx2).pop();
                                    ScaffoldMessenger.of(ctx2).showSnackBar(
                                      SnackBar(content: Text('${loc.t('currency_saved')}: $code')),
                                    );
                                  }
                                },
                                child: Text(loc.t('save')),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) => customController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;
    final establishment = accountManager.establishment;
    final localization = context.watch<LocalizationService>();

    if (currentEmployee == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(localization.t('settings')),
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
            Consumer<ThemeService>(
              builder: (_, themeService, __) => SwitchListTile(
                secondary: const Icon(Icons.palette),
                title: Text(localization.t('appearance')),
                subtitle: Text(themeService.isDark ? localization.t('dark_theme') : localization.t('light_theme')),
                value: themeService.isDark,
                onChanged: (dark) => themeService.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light),
              ),
            ),
            // Валюта заведения — только у владельца и шеф-повара в настройках
            if (currentEmployee.hasRole('owner') || currentEmployee.hasRole('executive_chef')) ...[
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: Text(localization.t('currency')),
                subtitle: Text(establishment?.currencySymbol ?? '₽'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showCurrencyPicker(context, localization),
              ),
            ],
            Consumer2<HomeButtonConfigService, AccountManagerSupabase>(
              builder: (_, homeBtn, account, __) {
                final isPro = account.hasProSubscription;
                return ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text('${localization.t('home_button_config')} (${localization.t('pro')})'),
                  subtitle: Text(isPro ? _homeButtonActionLabel(localization, homeBtn.action) : localization.t('pro_required_hint')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => isPro ? _showHomeButtonPicker(context, localization, homeBtn) : _showProRequiredDialog(context, localization),
                );
              },
            ),
            if (currentEmployee.hasRole('owner'))
              ListTile(
                leading: const Icon(Icons.star),
                title: Text(localization.t('pro_purchase')),
                trailing: const Icon(Icons.chevron_right),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                localization.t('logout'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () async {
                await accountManager.logout();
                if (context.mounted) context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}
