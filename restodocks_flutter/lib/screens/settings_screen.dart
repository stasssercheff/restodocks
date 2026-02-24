import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
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
      case HomeButtonAction.inbox:
        return loc.t('inbox');
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

  String _getRoleDisplayName(EmployeeRole? role, LocalizationService loc) => _getPositionDisplayName(role?.code, loc);

  String _getPositionDisplayName(String? code, LocalizationService loc) {
    if (code == null || code.isEmpty) return loc.t('no_position');
    switch (code) {
      case 'executive_chef': return loc.t('executive_chef');
      case 'sous_chef': return loc.t('sous_chef');
      case 'bartender': return loc.t('bartender');
      case 'waiter': return loc.t('waiter');
      case 'bar_manager': return loc.t('bar_manager');
      case 'floor_manager': return loc.t('floor_manager');
      case 'general_manager': return loc.t('general_manager');
      case 'manager': return loc.t('manager');
      default: return code;
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

  void _showInviteCoOwnerDialog(BuildContext context, LocalizationService loc, AccountManagerSupabase accountManager) {
    final emailController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('invite_co_owner')),
        content: TextField(
          controller: emailController,
          decoration: InputDecoration(
            labelText: loc.t('email'),
            hintText: loc.t('enter_email'),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.t('invalid_email'))),
                );
                return;
              }

              final establishment = accountManager.establishment;
              if (establishment == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.t('establishment_not_found'))),
                );
                return;
              }

              try {
                await accountManager.inviteCoOwner(email, establishment.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${loc.t('invitation_sent')} $email')),
                );
                Navigator.of(ctx).pop();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${loc.t('error')}: $e')),
                );
              }
            },
            child: Text(loc.t('send_invitation')),
          ),
        ],
      ),
    ).then((_) => emailController.dispose());
  }

  /// Одно окно «Настройки про»: статус подписки, ввод промокода, настройка кнопки «Домой»
  void _showProSettingsDialog(BuildContext context, LocalizationService loc, AccountManagerSupabase accountManager, HomeButtonConfigService homeBtn) {
    final hasPro = accountManager.hasProSubscription;
    final establishment = accountManager.establishment;
    final codeController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) {
          return AlertDialog(
            title: Text(loc.t('pro_settings')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Статус подписки
                  Text(
                    '${loc.t('subscription_status')}: ${hasPro ? loc.t('active') : loc.t('inactive')}',
                    style: Theme.of(ctx2).textTheme.titleSmall,
                  ),
                  if (hasPro && establishment?.subscriptionPlan != null)
                    Text('${loc.t('subscription_plan')}: ${establishment!.subscriptionPlan}'),
                  const SizedBox(height: 16),

                  // Ввод промокода (если нет Pro)
                  if (!hasPro) ...[
                    Text(loc.t('activation_code'), style: Theme.of(ctx2).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: codeController,
                      decoration: InputDecoration(
                        hintText: loc.t('enter_activation_code'),
                        border: const OutlineInputBorder(),
                        filled: true,
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Настройка кнопки «Домой» (только для Pro)
                  if (hasPro) ...[
                    Text(loc.t('home_button_config'), style: Theme.of(ctx2).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ...HomeButtonAction.values.map((action) => ListTile(
                      dense: true,
                      title: Text(_homeButtonActionLabel(loc, action)),
                      trailing: homeBtn.action == action ? const Icon(Icons.check, color: Colors.green, size: 20) : null,
                      onTap: () async {
                        await homeBtn.setAction(action);
                        if (ctx2.mounted) setState(() {});
                      },
                    )),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx2).pop(),
                child: Text(MaterialLocalizations.of(ctx2).cancelButtonLabel),
              ),
              if (!hasPro)
                FilledButton(
                  onPressed: () async {
                    final code = codeController.text.trim();
                    if (code.isEmpty) return;
                    // TODO: логика активации кода
                    if (ctx2.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${loc.t('code_activated')}: $code')),
                      );
                      Navigator.of(ctx2).pop();
                    }
                  },
                  child: Text(loc.t('activate')),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(ctx2).pop(),
                  child: Text(MaterialLocalizations.of(ctx2).okButtonLabel),
                ),
            ],
          );
        },
      ),
    ).then((_) => codeController.dispose());
  }

  /// Выбор должности (owner — дополнительная роль, не должность; «Без должности» = только собственник)
  void _showPositionPicker(BuildContext context, LocalizationService loc, Employee currentEmployee, AccountManagerSupabase accountManager) {
    final availablePositions = [
      {'code': null, 'name': loc.t('no_position')},
      {'code': 'executive_chef', 'name': loc.t('executive_chef')},
      {'code': 'sous_chef', 'name': loc.t('sous_chef')},
      {'code': 'bartender', 'name': loc.t('bartender')},
      {'code': 'waiter', 'name': loc.t('waiter')},
      {'code': 'bar_manager', 'name': loc.t('bar_manager')},
      {'code': 'floor_manager', 'name': loc.t('floor_manager')},
      {'code': 'general_manager', 'name': loc.t('general_manager')},
    ];

    final currentPosition = currentEmployee.positionRole;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('select_position')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: availablePositions.map((pos) {
            final code = pos['code'] as String?;
            final isSelected = code == currentPosition;
            return ListTile(
              title: Text(pos['name']!),
              trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                if (isSelected) {
                  Navigator.of(ctx).pop();
                  return;
                }
                final newRoles = ['owner'];
                if (code != null && code.isNotEmpty) newRoles.add(code);

                final updatedEmployee = currentEmployee.copyWith(
                  roles: newRoles,
                  updatedAt: DateTime.now(),
                );
                await accountManager.updateEmployee(updatedEmployee);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            );
          }).toList(),
        ),
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
            // Настройки про — одна кнопка: статус, промокод, кнопка «Домой»
            Consumer2<HomeButtonConfigService, AccountManagerSupabase>(
              builder: (_, homeBtn, account, __) {
                final isPro = account.hasProSubscription;
                final subtitle = isPro
                    ? '${localization.t('active')} • ${_homeButtonActionLabel(localization, homeBtn.action)}'
                    : localization.t('pro_required_hint');
                return ListTile(
                  leading: const Icon(Icons.star),
                  title: Text(localization.t('pro_settings')),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showProSettingsDialog(context, localization, accountManager, homeBtn),
                );
              },
            ),
            if (currentEmployee.hasRole('owner')) ...[
              Consumer<HomeButtonConfigService>(
                builder: (_, homeBtn, __) => ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(localization.t('central_button')),
                  subtitle: Text(_homeButtonActionLabel(localization, homeBtn.action)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showHomeButtonPicker(context, localization, homeBtn),
                ),
              ),
              // 1. Должность — добавляемая должность для собственника (не «собственник»)
              ListTile(
                leading: const Icon(Icons.work),
                title: Text(localization.t('position')),
                subtitle: Text(_getPositionDisplayName(currentEmployee.positionRole, localization)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showPositionPicker(context, localization, currentEmployee, accountManager),
              ),
              // 2. Выбор роли — переключение интерфейса (собственник ↔ должность), только если есть должность
              if (currentEmployee.positionRole != null)
                Consumer<OwnerViewPreferenceService>(
                  builder: (_, pref, __) => SwitchListTile(
                    secondary: const Icon(Icons.swap_horiz),
                    title: Text(localization.t('role_selection')),
                    subtitle: Text(pref.viewAsOwner ? localization.t('owner') : _getPositionDisplayName(currentEmployee.positionRole, localization)),
                    value: pref.viewAsOwner,
                    onChanged: (v) => pref.setViewAsOwner(v),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: Text(localization.t('invite_co_owner')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showInviteCoOwnerDialog(context, localization, accountManager),
              ),
            ],
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
