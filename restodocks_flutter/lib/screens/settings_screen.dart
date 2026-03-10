import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/home_layout_config_service.dart';
import '../services/screen_layout_preference_service.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/long_operation_progress_dialog.dart';

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
  int _maxEstablishmentsPerOwner = 5;
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
      final results = await Future.wait([
        accountManager.getEstablishmentsForOwner(),
        accountManager.getMaxEstablishmentsPerOwner(),
      ]);
      if (mounted) setState(() {
        _ownerEstablishments = results[0] as List<Establishment>;
        _maxEstablishmentsPerOwner = results[1] as int;
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

  void _showDeleteEstablishmentConfirm(BuildContext context, LocalizationService loc, Establishment establishment) {
    final account = context.read<AccountManagerSupabase>();
    final ownerEmail = account.currentEmployee?.email ?? '';
    final pinController = TextEditingController();
    final emailController = TextEditingController(text: ownerEmail);
    final formKey = GlobalKey<FormState>();
    showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete_establishment') ?? 'Удалить заведение?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${establishment.name}\n\n${loc.t('delete_establishment_enter_pin_email') ?? 'Введите PIN и email для подтверждения:'}',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Form(
                key: formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: pinController,
                      obscureText: true,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: loc.t('company_pin') ?? 'PIN компании',
                        hintText: loc.t('enter_company_pin') ?? 'Введите PIN компании',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return loc.t('company_pin_required') ?? 'PIN обязателен';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: loc.t('email'),
                        hintText: loc.t('enter_email') ?? 'Введите email',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return loc.t('email_required') ?? 'Email обязателен';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final pin = pinController.text.trim();
              final email = emailController.text.trim();
              if (!establishment.verifyPinCode(pin)) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(loc.t('delete_establishment_wrong_pin') ?? 'Неверный PIN')),
                );
                return;
              }
              Navigator.of(ctx).pop('$pin|$email');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(loc.t('delete_establishment') ?? 'Удалить'),
          ),
        ],
      ),
    ).then((result) async {
      pinController.dispose();
      emailController.dispose();
      if (result == null || !context.mounted) return;
      final parts = result.split('|');
      if (parts.length != 2) return;
      final pin = parts[0];
      final email = parts[1];
      final accountManager = context.read<AccountManagerSupabase>();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(loc.t('delete_establishment_progress') ?? 'Удаление заведения...'),
            ],
          ),
        ),
      );
      try {
        await accountManager.deleteEstablishment(
          establishmentId: establishment.id,
          pinCode: pin,
          email: email,
        );
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        if (context.mounted) {
          final remaining = await accountManager.getEstablishmentsForOwner();
          if (remaining.isEmpty) {
            await accountManager.logout();
            if (context.mounted) context.go('/login');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(loc.t('delete_establishment_done') ?? 'Заведение удалено'), backgroundColor: Colors.green),
            );
            setState(() => _ownerEstablishments = remaining);
            if (context.mounted) context.go('/home');
          }
        }
      } catch (e) {
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        if (context.mounted) {
          final msg = e.toString();
          String snack = loc.t('delete_establishment_wrong_pin') ?? 'Неверный PIN';
          if (msg.contains('Email') || msg.contains('email')) snack = loc.t('delete_establishment_wrong_email') ?? 'Email не совпадает';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(snack), backgroundColor: Colors.red));
        }
      }
    });
  }

  void _showClearNomenclatureConfirm(BuildContext context, LocalizationService loc) {
    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    if (establishment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('establishment') ?? 'Не найдено заведение')),
      );
      return;
    }
    final pinController = TextEditingController();
    final pinKey = GlobalKey<FormState>();
    showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('clear_nomenclature') ?? 'Очистить номенклатуру?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.t('clear_nomenclature_enter_pin') ?? 'Введите PIN заведения для подтверждения:',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Form(
              key: pinKey,
              child: TextFormField(
                controller: pinController,
                obscureText: true,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: loc.t('company_pin') ?? 'PIN компании',
                  hintText: loc.t('enter_company_pin') ?? 'Введите PIN компании',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return loc.t('company_pin_required') ?? 'PIN обязателен';
                  return null;
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          ElevatedButton(
            onPressed: () {
              if (!pinKey.currentState!.validate()) return;
              final pin = pinController.text.trim();
              if (!establishment.verifyPinCode(pin)) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(loc.t('clear_nomenclature_wrong_pin') ?? 'Неверный PIN')),
                );
                return;
              }
              Navigator.of(ctx).pop(pin);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(loc.t('clear_nomenclature') ?? 'Удалить всё'),
          ),
        ],
      ),
    ).then((pinVerified) async {
      if (pinVerified == null || !context.mounted) return;
      final store = context.read<ProductStoreSupabase>();
      final account = context.read<AccountManagerSupabase>();
      final estId = account.dataEstablishmentId;
      if (estId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('establishment') ?? 'Не найдено заведение')),
          );
        }
        return;
      }
      final count = store.getNomenclatureProducts(estId).length;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => LongOperationProgressDialog(
          message: loc.t('clear_nomenclature_progress') ?? 'Очищаем номенклатуру',
          hint: null,
          productCount: count > 0 ? count : null,
        ),
      );
      try {
        await store.clearAllNomenclature(estId).timeout(
          const Duration(minutes: 2),
          onTimeout: () => throw TimeoutException(
            loc.t('clear_nomenclature_timeout') ??
                'Операция заняла слишком много времени (2 мин). Обновите страницу — данные могли уже удалиться.',
          ),
        );
        if (context.mounted) {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) nav.pop();
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc.t('clear_nomenclature_done') ?? 'Вся номенклатура очищена'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) nav.pop();
        }
        if (context.mounted) {
          final message = e is TimeoutException
              ? (e.message ?? loc.t('clear_nomenclature_timeout'))
              : '${loc.t('error') ?? 'Ошибка'}: $e';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message ?? 'Ошибка'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
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
                            if (ctx.mounted) {
                              await ctx.read<AccountManagerSupabase>().savePreferredLanguage(code);
                              Navigator.of(ctx).pop();
                              // Фоновая подстановка переводов продуктов через Edge Function (DeepL)
                              _translateProductsForLanguage(context, code);
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

  /// Переводит продукты, у которых нет имени на выбранном языке (в фоне).
  /// Использует Edge Function auto-translate-product (DeepL) — работает на web.
  void _translateProductsForLanguage(BuildContext context, String targetLang) {
    final store = context.read<ProductStoreSupabase>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final loc = context.read<LocalizationService>();

    final needTranslation = <Product>[];
    Future(() async {
      await store.loadProducts(force: true);
      for (final p in store.allProducts) {
        final names = p.names ?? {};
        if ((names[targetLang] ?? '').trim().isNotEmpty) continue;
        if ((p.name).trim().isEmpty) continue;
        needTranslation.add(p);
      }
      if (needTranslation.isEmpty) return;

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(loc.t('translating_products')),
            ],
          ),
          duration: const Duration(hours: 1),
        ),
      );

      int updated = 0;
      for (final p in needTranslation) {
        try {
          final result = await store.translateProductAwait(p.id);
          if (result != null && (result[targetLang] ?? '').trim().isNotEmpty) {
            updated++;
          }
        } catch (_) {}
      }

      scaffoldMessenger.removeCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(updated > 0 ? '${loc.t('translate_done')} (+$updated)' : loc.t('translate_done')),
          backgroundColor: updated > 0 ? Colors.green : null,
        ),
      );
    });
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

  static const _trainingVideos = <String, String>{
    'Чеклист создание + ТТК, отображение во входящих': 'https://youtu.be/goZ20v6DV2s',
    'Чеклист заполнение': 'https://youtu.be/ggc8es-ivJc',
    'Создание ТТК + просмотр': 'https://youtu.be/MixDi9UC2kg',
    'Инвентаризация iiko с загрузкой бланка': 'https://youtu.be/JjMe-Tb04ZM',
    'Заказ продуктов с отправкой по почте': 'https://youtu.be/e5DJHk_pSbE',
    'Сотрудники настройка': 'https://youtu.be/bGVJtSdpid0',
    'Смена роли собственника': 'https://youtu.be/nkk9BpyIkuQ',
    'Инвента iiko выгрузка бланка': 'https://youtu.be/rFXg9gJ5qUw',
    'График правка': 'https://youtu.be/sF26hjgdjO8',
    'Сообщения': 'https://youtu.be/zgH9ITDHU4U',
    'Расчет выплаты за период + выгрузка': 'https://youtu.be/tO4ihTk8bDM',
    'Загрузка продуктов изменение цены': 'https://youtu.be/p9I1rsNgXpU',
    'Загрузка продуктов в номенклатуру файл': 'https://youtu.be/po5_brrXdVw',
    'Загрузка продуктов в номенклатуру текст': 'https://youtu.be/66Q9iUyuqso',
    'Загрузка продуктов текст из таблицы': 'https://youtu.be/tYsFlIll954',
  };

  void _showTrainingDialog(BuildContext context, LocalizationService loc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('training') ?? 'Обучение'),
        content: SizedBox(
          width: 340,
          child: ListView(
            shrinkWrap: true,
            children: _trainingVideos.entries.map((e) {
              return ListTile(
                leading: const Icon(Icons.play_circle_outline, color: Colors.red),
                title: Text(e.key, style: const TextStyle(fontSize: 14)),
                trailing: const Icon(Icons.open_in_new, size: 18),
                dense: true,
                onTap: () async {
                  final uri = Uri.parse(e.value);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              );
            }).toList(),
          ),
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

  Widget _buildNotificationSettings(
    BuildContext context, LocalizationService loc, Employee emp, AccountManagerSupabase accountManager) {
    final prefs = context.watch<NotificationPreferencesService>();
    final empId = emp.id;
    final isOwner = emp.hasRole('owner');
    final isManagement = emp.department == 'management' ||
        emp.hasRole('executive_chef') || emp.hasRole('sous_chef') ||
        emp.hasRole('bar_manager') || emp.hasRole('floor_manager');
    final isLineStaff = !isOwner && !isManagement;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.t('notification_display_type') ?? 'Вид уведомлений',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...NotificationDisplayType.values.map((t) {
            final label = switch (t) {
              NotificationDisplayType.banner => loc.t('notification_banner') ?? 'Плашка сверху',
              NotificationDisplayType.modal => loc.t('notification_modal') ?? 'Окошко в центре',
              NotificationDisplayType.disabled => loc.t('notification_disabled') ?? 'Отключены',
            };
            return RadioListTile<NotificationDisplayType>(
              title: Text(label),
              value: t,
              groupValue: prefs.displayType,
              onChanged: (v) async {
                if (v != null) await prefs.setDisplayType(v, empId);
              },
            );
          }),
          if (prefs.displayType != NotificationDisplayType.disabled) ...[
            const SizedBox(height: 16),
            Text(
              loc.t('notification_categories') ?? 'Какие уведомления включены',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(loc.t('inbox_tab_messages') ?? 'Сообщения'),
              value: prefs.messages,
              onChanged: (v) => prefs.setMessages(v, empId),
            ),
            SwitchListTile(
              title: Text(loc.t('inbox_tab_order') ?? 'Заказы'),
              value: prefs.orders,
              onChanged: (v) => prefs.setOrders(v, empId),
            ),
            if (isOwner || isManagement) ...[
              SwitchListTile(
                title: Text(loc.t('inbox_tab_inventory') ?? 'Инвентаризация'),
                value: prefs.inventory,
                onChanged: (v) => prefs.setInventory(v, empId),
              ),
              SwitchListTile(
                title: Text(loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko'),
                value: prefs.iikoInventory,
                onChanged: (v) => prefs.setIikoInventory(v, empId),
              ),
            ],
            SwitchListTile(
              title: Text(loc.t('inbox_tab_notifications') ?? 'Уведомления'),
              subtitle: Text(
                isLineStaff
                    ? (loc.t('notification_checklist_assigned') ?? 'Чеклисты, назначенные на вас')
                    : (loc.t('notification_schedule_changes') ?? 'Изменения штатного расписания'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: prefs.notifications,
              onChanged: (v) => prefs.setNotifications(v, empId),
            ),
          ],
        ],
      ),
    );
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
              if (!accountManager.isViewOnlyOwner) ...[
                ListTile(
                  leading: const Icon(Icons.add_business),
                  title: Text(localization.t('add_establishment') ?? 'Добавить заведение'),
                  subtitle: Text(
                    (localization.t('establishments_counter') ?? '{current} из {max}')
                        .replaceAll('{current}', '${(_ownerEstablishments.length - 1).clamp(0, _maxEstablishmentsPerOwner)}')
                        .replaceAll('{max}', '$_maxEstablishmentsPerOwner'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: (_ownerEstablishments.length - 1) >= _maxEstablishmentsPerOwner
                      ? null
                      : () => context.push('/add-establishment'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(
                    localization.t('delete_establishment') ?? 'Удалить заведение',
                    style: const TextStyle(color: Colors.red),
                  ),
                  subtitle: Text(localization.t('delete_establishment_hint') ?? 'Удалить заведение и все связанные данные безвозвратно'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: establishment != null ? () => _showDeleteEstablishmentConfirm(context, localization, establishment!) : null,
                ),
              ],
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
                      title: Text(localization.t('button_display_config') ?? 'Настройка кнопки'),
                      subtitle: Text(localization.t('central_button_hint') ?? 'Выбор для отображения желаемого'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showHomeButtonPicker(context, localization, homeBtn),
                    ),
                  ),
                Consumer<ScreenLayoutPreferenceService>(
                  builder: (_, screenPref, __) => SwitchListTile(
                    secondary: const Icon(Icons.restaurant_menu),
                    title: Text(localization.t('show_banquet_catering') ?? 'Показ «банкеты и кейтринг» на экране'),
                    subtitle: Text(localization.t('show_banquet_catering_hint') ?? 'Показывать «Меню — Банкет/Кейтринг» и «ТТК — Банкет/Кейтринг»'),
                    value: screenPref.showBanquetCatering,
                    onChanged: (v) => screenPref.setShowBanquetCatering(v),
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
            ExpansionTile(
              leading: const Icon(Icons.notifications),
              title: Text(localization.t('notification_settings') ?? 'Уведомления'),
              subtitle: Text(localization.t('notification_settings_hint') ?? 'Вид уведомлений и какие включены'),
              children: [
                _buildNotificationSettings(context, localization, currentEmployee, accountManager),
              ],
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
            // Очистить номенклатуру — шеф, барменеджер, менеджер зала
            if (currentEmployee.hasRole('executive_chef') || currentEmployee.hasRole('bar_manager') || currentEmployee.hasRole('floor_manager')) ...[
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(localization.t('clear_nomenclature') ?? 'Очистить номенклатуру'),
                subtitle: Text(localization.t('clear_nomenclature_hint') ?? 'Удалить все продукты из номенклатуры заведения'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showClearNomenclatureConfirm(context, localization),
              ),
            ],
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
              leading: const Icon(Icons.school),
              title: Text(localization.t('training') ?? 'Обучение'),
              subtitle: Text(localization.t('training_subtitle') ?? 'Видеоинструкции по работе с приложением'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTrainingDialog(context, localization),
            ),
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
