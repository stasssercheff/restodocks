import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/home_layout_config_service.dart';
import '../services/screen_layout_preference_service.dart';
import '../widgets/app_bar_home_button.dart';

const _adminEmails = <String>{'stasssercheff@gmail.com'};
bool _isPlatformAdminEmail(String email) => _adminEmails.contains(email.toLowerCase().trim());

/// Экран только настроек: язык, тема, валюта и т.д. Без данных профиля (профиль — отдельная кнопка).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Establishment> _ownerEstablishments = [];
  bool _loadingEstablishments = false;

  @override
  void initState() {
    super.initState();
    _loadOwnerEstablishments();
  }

  Future<void> _loadOwnerEstablishments() async {
    final accountManager = context.read<AccountManagerSupabase>();
    if (accountManager.currentEmployee?.hasRole('owner') != true) return;
    setState(() => _loadingEstablishments = true);
    try {
      final list = await accountManager.getEstablishmentsForOwner();
      if (mounted) setState(() {
        _ownerEstablishments = list;
        _loadingEstablishments = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEstablishments = false);
    }
  }

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
    return loc.roleDisplayName(code);
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
  void _showRolePicker(
    BuildContext context,
    LocalizationService loc,
    Employee currentEmployee,
    AccountManagerSupabase accountManager,
    OwnerViewPreferenceService pref,
  ) {
    final positions = [
      {'code': null, 'name': loc.t('owner')},
      ...currentEmployee.roles
          .where((r) => r != 'owner' && _visiblePositionCodes.contains(r))
          .map((code) => {'code': code, 'name': _getPositionDisplayName(code, loc)}),
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('role_selection')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: positions.map((p) {
            final code = p['code'] as String?;
            final isOwnerSelected = pref.viewAsOwner && code == null;
            final isPositionSelected = !pref.viewAsOwner && code != null && code == currentEmployee.positionRole;
            final isSelected = isOwnerSelected || isPositionSelected;
            return ListTile(
              title: Text(p['name']!),
              trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                await pref.setViewAsOwner(code == null);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Должности, не скрытые при регистрации (совпадает с owner_registration).
  static const List<String> _visiblePositionCodes = [
    'executive_chef', 'sous_chef', 'bar_manager', 'floor_manager', 'general_manager',
  ];

  void _showPositionPicker(BuildContext context, LocalizationService loc, Employee currentEmployee, AccountManagerSupabase accountManager) {
    final availablePositions = [
      {'code': null, 'name': loc.t('no_position')},
      ..._visiblePositionCodes.map((code) => {'code': code, 'name': _getPositionDisplayName(code, loc)}),
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
                try {
                  await accountManager.updateEmployee(updatedEmployee);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${loc.t('error') ?? 'Ошибка'}: $e')),
                    );
                  }
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showTtkBranchFilterPicker(
    BuildContext context,
    LocalizationService loc,
    AccountManagerSupabase accountManager,
    List<Establishment> branches,
  ) {
    final branchFilter = context.read<TtkBranchFilterService>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('ttk_branch_display') ?? 'Отображение ТТК по филиалам'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.store),
              title: Text(loc.t('main_establishment') ?? 'Основное'),
              trailing: branchFilter.selectedBranchId == null
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () async {
                await branchFilter.setBranchFilter(null);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            ...branches.map((b) => ListTile(
                  leading: const Icon(Icons.account_tree),
                  title: Text(b.name),
                  trailing: branchFilter.selectedBranchId == b.id
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () async {
                    await branchFilter.setBranchFilter(b.id);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showHomeLayoutConfig(BuildContext context, LocalizationService loc) {
    final account = context.read<AccountManagerSupabase>();
    final emp = account.currentEmployee;
    if (emp == null) return;
    final layoutSvc = context.read<HomeLayoutConfigService>();
    var order = List<HomeTileId>.from(layoutSvc.getOrder(emp.id));
    final showBanquet = emp.department == 'kitchen';
    if (!showBanquet) {
      order = order.where((id) => id != HomeTileId.banquetMenu && id != HomeTileId.banquetTtk).toList();
    }
    final tileLabels = <HomeTileId, String>{
      HomeTileId.messages: loc.t('inbox_tab_messages') ?? 'Сообщения',
      HomeTileId.schedule: loc.t('schedule'),
      HomeTileId.productOrder: loc.t('product_order'),
      HomeTileId.suppliers: loc.t('order_tab_suppliers') ?? 'Поставщики',
      HomeTileId.menu: loc.t('menu'),
      HomeTileId.ttk: emp.department == 'bar' ? loc.t('ttk_bar') : loc.t('ttk_kitchen'),
      HomeTileId.banquetMenu: '${loc.t('menu')} — ${loc.t('banquet_catering') ?? 'Банкет / Кейтринг'}',
      HomeTileId.banquetTtk: '${loc.t('ttk_kitchen')} — ${loc.t('banquet_catering') ?? 'Банкет / Кейтринг'}',
      HomeTileId.checklists: loc.t('checklists'),
      HomeTileId.nomenclature: loc.t('nomenclature'),
      HomeTileId.inventory: loc.t('inventory_blank'),
    };
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => AlertDialog(
          title: Text(loc.t('home_layout_config') ?? 'Настройка домашнего экрана'),
          content: SizedBox(
            width: 320,
            height: 400,
            child: ReorderableListView.builder(
              itemCount: order.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = order.removeAt(oldIndex);
                  order.insert(newIndex, item);
                });
              },
              itemBuilder: (ctx, i) {
                final id = order[i];
                return ListTile(
                  key: ValueKey(id.key),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(tileLabels[id] ?? id.key),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () async {
                await layoutSvc.setOrder(emp.id, order);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(loc.t('save')),
            ),
          ],
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
                            final code = language['code']!;
                            await localization.setLocale(Locale(code));
                            // Сохраняем язык в профиле сотрудника в Supabase (работает в любом браузере / инкогнито)
                            if (ctx.mounted) {
                              await ctx.read<AccountManagerSupabase>().savePreferredLanguage(code);
                              Navigator.of(ctx).pop();
                            }
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

  void _showSupportDialog(BuildContext context, LocalizationService loc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('contact_support')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.telegram, color: Color(0xFF2AABEE)),
              title: const Text('Telegram'),
              subtitle: const Text('@restodocks'),
              onTap: () async {
                final uri = Uri.parse('https://t.me/restodocks');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined, color: Colors.redAccent),
              title: Text(loc.t('email')),
              subtitle: const Text('stassserchef@gmail.com'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showSupportEmailForm(context, loc);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  void _showSupportEmailForm(BuildContext context, LocalizationService loc) {
    final accountManager = context.read<AccountManagerSupabase>();
    final userEmail = accountManager.currentEmployee?.email ?? '';

    final categories = [
      loc.t('support_category_bug'),
      loc.t('support_category_question'),
      loc.t('support_category_suggestion'),
      loc.t('support_category_other'),
    ];

    String selectedCategory = categories.first;
    final subjectController = TextEditingController();
    final messageController = TextEditingController();
    bool isSending = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          title: Text(loc.t('support_form_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.t('support_category'), style: Theme.of(ctx2).textTheme.labelMedium),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: isSending ? null : (v) => setDialogState(() => selectedCategory = v ?? selectedCategory),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  enabled: !isSending,
                  decoration: InputDecoration(
                    labelText: loc.t('support_subject'),
                    hintText: loc.t('support_subject_hint'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  enabled: !isSending,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: loc.t('support_message'),
                    hintText: loc.t('support_message_hint'),
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.of(ctx2).pop(),
              child: Text(MaterialLocalizations.of(ctx2).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: isSending
                  ? null
                  : () async {
                      final subject = subjectController.text.trim();
                      final message = messageController.text.trim();
                      if (subject.isEmpty || message.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(loc.t('support_fill_all'))),
                        );
                        return;
                      }
                      setDialogState(() => isSending = true);
                      final result = await EmailService().sendSupportEmail(
                        fromEmail: userEmail,
                        category: selectedCategory,
                        subject: subject,
                        message: message,
                      );
                      if (ctx2.mounted) {
                        Navigator.of(ctx2).pop();
                        if (result.ok) {
                          showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(loc.t('support_sent_title')),
                              content: Text(loc.t('support_sent_body')),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                                ),
                              ],
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(loc.t('support_error'))),
                          );
                        }
                      }
                    },
              child: isSending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(loc.t('support_send')),
            ),
          ],
        ),
      ),
    ).then((_) {
      subjectController.dispose();
      messageController.dispose();
    });
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
        leading: appBarBackButton(context),
        title: Text(localization.t('settings')),
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
            if (currentEmployee.hasRole('owner')) ...[
              Text(
                localization.t('establishment') ?? 'Заведение',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_loadingEstablishments)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_ownerEstablishments.length > 1) ...[
                ..._ownerEstablishments.map((est) {
                  final parentName = est.isBranch && est.parentEstablishmentId != null
                      ? _ownerEstablishments.where((e) => e.id == est.parentEstablishmentId).firstOrNull?.name
                      : null;
                  return ListTile(
                    leading: Icon(
                      est.id == establishment?.id ? Icons.check_circle : (est.isBranch ? Icons.account_tree : Icons.store),
                      color: est.id == establishment?.id ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(est.name),
                    subtitle: est.id == establishment?.id
                        ? Text(localization.t('current') ?? 'Текущее')
                        : (est.isBranch && parentName != null
                            ? Text('${localization.t('branch_of') ?? 'Филиал'}: $parentName')
                            : (est.isMain ? Text(localization.t('main_establishment') ?? 'Основное') : null)),
                    trailing: est.id == establishment?.id ? const Icon(Icons.check, color: Colors.green) : null,
                    onTap: est.id == establishment?.id ? null : () async {
                      await accountManager.switchEstablishment(est);
                      if (context.mounted) context.go('/home');
                    },
                  );
                }),
                const SizedBox(height: 8),
              ],
              if (!accountManager.isViewOnlyOwner)
                ListTile(
                  leading: const Icon(Icons.add_business),
                  title: Text(localization.t('add_establishment') ?? 'Добавить заведение'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/add-establishment'),
                ),
              const Divider(),
            ],
            ExpansionTile(
              leading: const Icon(Icons.dashboard_customize),
              title: Text(localization.t('home_layout_config') ?? 'Настройка домашнего экрана'),
              children: [
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: Text(localization.t('home_layout_config_hint') ?? 'Изменить порядок кнопок на главной'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showHomeLayoutConfig(context, localization),
                ),
                if (currentEmployee.hasRole('owner'))
                  Consumer<HomeButtonConfigService>(
                    builder: (_, homeBtn, __) => ListTile(
                      leading: const SizedBox(width: 24),
                      title: Text(localization.t('central_button') ?? 'Центральная кнопка'),
                      subtitle: Text(_homeButtonActionLabel(localization, homeBtn.action)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showHomeButtonPicker(context, localization, homeBtn),
                    ),
                  ),
              ],
            ),
            Consumer<ScreenLayoutPreferenceService>(
              builder: (_, screenPref, __) => SwitchListTile(
                secondary: const Icon(Icons.translate),
                title: Text(localization.t('show_name_translit') ?? 'Показывать имена транслитом'),
                subtitle: Text(localization.t('show_name_translit_hint') ?? 'Отображать ФИО сотрудников латиницей'),
                value: screenPref.showNameTranslit,
                onChanged: (v) => screenPref.setShowNameTranslit(v),
              ),
            ),
            Consumer<ScreenLayoutPreferenceService>(
              builder: (_, screenPref, __) => SwitchListTile(
                secondary: const Icon(Icons.restaurant_menu),
                title: Text(localization.t('show_banquet_catering') ?? 'Банкеты и кейтринг в меню'),
                subtitle: Text(localization.t('show_banquet_catering_hint') ?? 'Показывать «Меню — Банкет/Кейтринг» и «ТТК — Банкет/Кейтринг»'),
                value: screenPref.showBanquetCatering,
                onChanged: (v) => screenPref.setShowBanquetCatering(v),
              ),
            ),
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
                subtitle: Text(establishment?.currencySymbol ?? Establishment.currencySymbolFor(establishment?.defaultCurrency ?? 'VND')),
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
              // 1. Должность — добавляемая должность для собственника (не «собственник»)
              ListTile(
                leading: const Icon(Icons.work),
                title: Text(localization.t('position')),
                subtitle: Text(_getPositionDisplayName(currentEmployee.positionRole, localization)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showPositionPicker(context, localization, currentEmployee, accountManager),
              ),
              // 2. Выбор роли — список «Собственник» или должность (не переключатель)
              if (currentEmployee.positionRole != null)
                Consumer<OwnerViewPreferenceService>(
                  builder: (_, pref, __) => ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(localization.t('role_selection')),
                    subtitle: Text(pref.viewAsOwner ? localization.t('owner') : _getPositionDisplayName(currentEmployee.positionRole, localization)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showRolePicker(context, localization, currentEmployee, accountManager, pref),
                  ),
                ),
              if (!accountManager.isViewOnlyOwner)
                ListTile(
                  leading: const Icon(Icons.person_add),
                  title: Text(localization.t('invite_co_owner')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showInviteCoOwnerDialog(context, localization, accountManager),
                ),
              if ((currentEmployee.hasRole('executive_chef') || currentEmployee.hasRole('sous_chef')) &&
                  accountManager.establishment?.isMain == true)
                FutureBuilder<List<Establishment>>(
                  future: accountManager.getBranchesForEstablishment(accountManager.establishment!.id),
                  builder: (ctx, snap) {
                    if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                    final branches = snap.data!;
                    return Consumer<TtkBranchFilterService>(
                      builder: (_, branchFilter, __) {
                        final selId = branchFilter.selectedBranchId;
                        final name = selId == null
                            ? (localization.t('main_establishment') ?? 'Основное')
                            : branches.where((b) => b.id == selId).map((b) => b.name).firstOrNull ?? selId;
                        return ListTile(
                          leading: const Icon(Icons.account_tree),
                          title: Text(localization.t('ttk_branch_display') ?? 'Отображение ТТК по филиалам'),
                          subtitle: Text(name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showTtkBranchFilterPicker(context, localization, accountManager, branches),
                        );
                      },
                    );
                  },
                ),
              if (accountManager.isViewOnlyOwner)
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: Text(localization.t('view_only_mode') ?? 'Режим только просмотр'),
                  subtitle: Text(localization.t('view_only_mode_hint') ?? 'Соучредитель при нескольких заведениях'),
                ),
            ],
            // Кнопка платформенного кабинета — видна только владельцу платформы
            if (_isPlatformAdminEmail(currentEmployee.email)) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.deepPurple),
                title: const Text('Platform Admin', style: TextStyle(color: Colors.deepPurple)),
                subtitle: const Text('Промокоды и управление'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin'),
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: Text(localization.t('contact_support')),
              subtitle: Text(localization.t('contact_support_subtitle')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showSupportDialog(context, localization),
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
