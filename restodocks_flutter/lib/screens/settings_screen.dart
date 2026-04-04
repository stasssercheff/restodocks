import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/haccp_log_type.dart';
import '../models/models.dart';
import '../core/feature_flags.dart';
import '../services/haccp_agreement_pdf_service.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../services/home_layout_config_service.dart';
import '../services/screen_layout_preference_service.dart';
import '../utils/pos_hall_permissions.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/getting_started_document.dart';
import '../widgets/long_operation_progress_dialog.dart';
import '../widgets/post_registration_trial_dialog.dart';
import '../widgets/pro_settings_owner_section.dart';
import '../widgets/sales_financials_management_tile.dart';

const _adminEmails = <String>{'stasssercheff@gmail.com'};
bool _isPlatformAdminEmail(String email) =>
    _adminEmails.contains(email.toLowerCase().trim());

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      if (est != null) context.read<HaccpConfigService>().load(est.id);
    });
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
      if (mounted)
        setState(() {
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

  String _homeButtonActionLabel(
      LocalizationService loc, HomeButtonAction action) {
    switch (action) {
      case HomeButtonAction.inbox:
        return loc.t('inbox');
      case HomeButtonAction.messages:
        return loc.t('inbox_tab_messages') ?? 'Сообщения';
      case HomeButtonAction.schedule:
        return loc.t('schedule');
      case HomeButtonAction.productOrder:
        return loc.t('product_order');
      case HomeButtonAction.menu:
        return loc.t('menu');
      case HomeButtonAction.ttk:
        return loc.t('tech_cards');
      case HomeButtonAction.checklists:
        return loc.t('checklists');
      case HomeButtonAction.nomenclature:
        return loc.t('nomenclature');
      case HomeButtonAction.inventory:
        return loc.t('inventory_blank');
      case HomeButtonAction.expenses:
        return loc.t('expenses');
    }
  }

  String _getRoleDisplayName(EmployeeRole? role, LocalizationService loc) =>
      _getPositionDisplayName(role?.code, loc);

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

  void _showInviteCoOwnerDialog(BuildContext context, LocalizationService loc,
      AccountManagerSupabase accountManager) {
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
              if (email.isEmpty ||
                  !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                      .hasMatch(email)) {
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
          .map((code) =>
              {'code': code, 'name': _getPositionDisplayName(code, loc)}),
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
            final isPositionSelected = !pref.viewAsOwner &&
                code != null &&
                code == currentEmployee.positionRole;
            final isSelected = isOwnerSelected || isPositionSelected;
            return ListTile(
              title: Text(p['name']!),
              trailing: isSelected
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
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
    'executive_chef',
    'bar_manager',
    'floor_manager',
    'general_manager',
  ];

  void _showPositionPicker(BuildContext context, LocalizationService loc,
      Employee currentEmployee, AccountManagerSupabase accountManager) {
    final availablePositions = [
      {'code': null, 'name': loc.t('no_position')},
      ..._visiblePositionCodes.map(
          (code) => {'code': code, 'name': _getPositionDisplayName(code, loc)}),
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
              trailing: isSelected
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
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
                      SnackBar(
                          content: Text('${loc.t('error') ?? 'Ошибка'}: $e')),
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

  void _showDeleteEstablishmentConfirm(BuildContext context,
      LocalizationService loc, Establishment establishment) {
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
                        hintText: loc.t('enter_company_pin') ??
                            'Введите PIN компании',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return loc.t('company_pin_required') ??
                              'PIN обязателен';
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
                        if (v == null || v.trim().isEmpty)
                          return loc.t('email_required') ?? 'Email обязателен';
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
                  SnackBar(
                      content: Text(loc.t('delete_establishment_wrong_pin') ??
                          'Неверный PIN')),
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
              Text(loc.t('delete_establishment_progress') ??
                  'Удаление заведения...'),
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
        if (context.mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
        if (context.mounted) {
          final remaining = await accountManager.getEstablishmentsForOwner();
          if (remaining.isEmpty) {
            await accountManager.logout();
            if (context.mounted) context.go('/login');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(loc.t('delete_establishment_done') ??
                      'Заведение удалено'),
                  backgroundColor: Colors.green),
            );
            setState(() => _ownerEstablishments = remaining);
            if (context.mounted) context.go('/home');
          }
        }
      } catch (e) {
        if (context.mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
        if (context.mounted) {
          final msg = e.toString();
          String snack =
              loc.t('delete_establishment_wrong_pin') ?? 'Неверный PIN';
          if (msg.contains('Email') || msg.contains('email'))
            snack = loc.t('delete_establishment_wrong_email') ??
                'Email не совпадает';
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(snack), backgroundColor: Colors.red));
        }
      }
    });
  }

  void _showClearAllTtkConfirm(BuildContext context, LocalizationService loc) {
    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    if (establishment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.t('establishment') ?? 'Не найдено заведение')),
      );
      return;
    }
    final pinController = TextEditingController();
    final pinKey = GlobalKey<FormState>();
    showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('clear_all_ttk') ?? 'Удалить все ТТК?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.t('clear_all_ttk_enter_pin') ??
                  'Введите PIN заведения для подтверждения:',
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
                  hintText:
                      loc.t('enter_company_pin') ?? 'Введите PIN компании',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return loc.t('company_pin_required') ?? 'PIN обязателен';
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(loc.t('clear_nomenclature_wrong_pin') ??
                          'Неверный PIN')),
                );
                return;
              }
              Navigator.of(ctx).pop(pin);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(loc.t('clear_all_ttk') ?? 'Удалить все ТТК'),
          ),
        ],
      ),
    ).then((pinVerified) async {
      if (pinVerified == null || !context.mounted) return;
      final techCardSvc = context.read<TechCardServiceSupabase>();
      final account = context.read<AccountManagerSupabase>();
      final estId = account.dataEstablishmentId;
      if (estId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(loc.t('establishment') ?? 'Не найдено заведение')),
          );
        }
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(loc.t('settings_clearing_ttk')),
                ],
              ),
            ),
          ),
        ),
      );
      try {
        final count = await techCardSvc.deleteAllTechCards(estId);
        if (context.mounted) {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) nav.pop();
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${loc.t('clear_all_ttk_done') ?? 'Удалено ТТК'}: $count'),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${loc.t('error') ?? 'Ошибка'}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  void _showClearNomenclatureConfirm(
      BuildContext context, LocalizationService loc) {
    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    if (establishment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.t('establishment') ?? 'Не найдено заведение')),
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
              loc.t('clear_nomenclature_enter_pin') ??
                  'Введите PIN заведения для подтверждения:',
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
                  hintText:
                      loc.t('enter_company_pin') ?? 'Введите PIN компании',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return loc.t('company_pin_required') ?? 'PIN обязателен';
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
                  SnackBar(
                      content: Text(loc.t('clear_nomenclature_wrong_pin') ??
                          'Неверный PIN')),
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
            SnackBar(
                content:
                    Text(loc.t('establishment') ?? 'Не найдено заведение')),
          );
        }
        return;
      }
      final count = store.getNomenclatureProducts(estId).length;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => LongOperationProgressDialog(
          message:
              loc.t('clear_nomenclature_progress') ?? 'Очищаем номенклатуру',
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
              content: Text(loc.t('clear_nomenclature_done') ??
                  'Вся номенклатура очищена'),
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
        title:
            Text(loc.t('ttk_branch_display') ?? 'Отображение ТТК по филиалам'),
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
      order = order
          .where((id) =>
              id != HomeTileId.banquetMenu && id != HomeTileId.banquetTtk)
          .toList();
    }
    final isHall = emp.department == 'hall' || emp.department == 'dining_room';
    final isKitchenOrBar =
        emp.department == 'kitchen' || emp.department == 'bar';
    if (!isHall) {
      order = order
          .where((id) =>
              id != HomeTileId.hallOrders &&
              id != HomeTileId.hallCashRegister &&
              id != HomeTileId.hallTables)
          .toList();
    }
    if (!isKitchenOrBar) {
      order = order
          .where((id) =>
              id != HomeTileId.departmentOrders &&
              id != HomeTileId.departmentSales)
          .toList();
    }
    if (!FeatureFlags.posModuleEnabled) {
      order = order
          .where((id) =>
              id != HomeTileId.hallOrders &&
              id != HomeTileId.hallCashRegister &&
              id != HomeTileId.hallTables &&
              id != HomeTileId.departmentOrders &&
              id != HomeTileId.departmentSales &&
              id != HomeTileId.inventory)
          .toList();
    }
    final tileLabels = <HomeTileId, String>{
      HomeTileId.messages: loc.t('inbox_tab_messages') ?? 'Сообщения',
      HomeTileId.schedule: loc.t('schedule'),
      HomeTileId.documentation: loc.t('documentation') ?? 'Документация',
      HomeTileId.productOrder: loc.t('product_order'),
      HomeTileId.suppliers:
          loc.t('suppliers') ?? loc.t('order_tab_suppliers') ?? 'Поставщики',
      HomeTileId.menu: loc.t('menu'),
      HomeTileId.ttk:
          emp.department == 'bar' ? loc.t('ttk_bar') : loc.t('ttk_kitchen'),
      HomeTileId.banquetMenu:
          '${loc.t('menu')} — ${loc.t('banquet_catering') ?? 'Банкет / Кейтринг'}',
      HomeTileId.banquetTtk:
          '${loc.t('ttk_kitchen')} — ${loc.t('banquet_catering') ?? 'Банкет / Кейтринг'}',
      HomeTileId.checklists: loc.t('checklists'),
      HomeTileId.nomenclature: loc.t('nomenclature'),
      HomeTileId.inventory: loc.t('inventory_blank'),
      HomeTileId.writeoffs: loc.t('writeoffs') ?? 'Списания',
      HomeTileId.hallOrders: loc.t('order_tab_orders'),
      HomeTileId.hallCashRegister: loc.t('pos_nav_cash_register'),
      HomeTileId.hallTables: loc.t('pos_nav_tables'),
      HomeTileId.departmentOrders: loc.t('order_tab_orders'),
      HomeTileId.departmentSales: loc.t('sales_title') ?? 'Продажи',
    };
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => AlertDialog(
          title:
              Text(loc.t('home_layout_config') ?? 'Настройка домашнего экрана'),
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

  void _showHomeButtonPicker(BuildContext context, LocalizationService loc,
      HomeButtonConfigService homeBtn) {
    final accountManager = context.read<AccountManagerSupabase>();
    final emp = accountManager.currentEmployee;
    final actions = homeButtonActionsFor(emp,
        hasProSubscription: accountManager.hasProSubscription);
    final effective = homeBtn.effectiveAction(emp,
        hasProSubscription: accountManager.hasProSubscription);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('home_button_config')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: actions.map((action) {
              final selected = effective == action;
              return ListTile(
                leading: Icon(action.icon,
                    color: selected ? Theme.of(ctx).colorScheme.primary : null),
                title: Text(_homeButtonActionLabel(loc, action)),
                trailing: selected
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  await homeBtn.setAction(action);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(
      BuildContext context, LocalizationService localization) {
    unawaited(localization.showLocalePickerDialog(
      context,
      afterApplied: (code) async {
        scheduleMicrotask(() async {
          if (!context.mounted) return;
          await context.read<AccountManagerSupabase>().savePreferredLanguage(code);
          if (!context.mounted) return;
          _translateMissingForLanguage(context, code);
        });
      },
    ));
  }

  /// При смене языка в настройках: в фоне добирает переводы продуктов и названий ТТК
  /// на выбранный язык (если их ещё нет в данных). DeepL через Edge Functions.
  /// Уведомления показываются только если включены в настройках экрана.
  void _translateMissingForLanguage(BuildContext context, String targetLang) {
    final store = context.read<ProductStoreSupabase>();
    final techSvc = context.read<TechCardServiceSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final screenPref = context.read<ScreenLayoutPreferenceService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final loc = context.read<LocalizationService>();
    final showNotif = screenPref.showTranslationNotifications;

    Future(() async {
      await store.loadProducts(force: true);
      final needProducts = <Product>[];
      for (final p in store.allProducts) {
        final names = p.names ?? {};
        if ((names[targetLang] ?? '').trim().isNotEmpty) continue;
        if ((p.name).trim().isEmpty) continue;
        needProducts.add(p);
      }

      var needTtk = <TechCard>[];
      if (targetLang != 'ru') {
        final estId = account.dataEstablishmentId;
        if (estId != null) {
          try {
            final cards = await techSvc.getTechCardsForEstablishment(
              estId,
              includeIngredients: false,
            );
            for (final tc in cards) {
              if (tc.dishName.trim().isEmpty) continue;
              final has = tc.dishNameLocalized?.containsKey(targetLang) == true &&
                  (tc.dishNameLocalized![targetLang]?.trim().isNotEmpty ?? false);
              if (has) continue;
              needTtk.add(tc);
            }
          } catch (_) {}
        }
      }

      if (needProducts.isEmpty && needTtk.isEmpty) return;

      if (showNotif) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(loc.t('translating_products')),
              ],
            ),
            duration: const Duration(hours: 1),
          ),
        );
      }

      var updatedProducts = 0;
      for (final p in needProducts) {
        try {
          final result = await store.translateProductAwait(p.id);
          if (result != null && (result[targetLang] ?? '').trim().isNotEmpty) {
            updatedProducts++;
          }
        } catch (_) {}
      }

      var updatedTtk = 0;
      var i = 0;
      for (final tc in needTtk) {
        if (i > 0 && i % 2 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        i++;
        try {
          final t = await techSvc
              .translateTechCardName(tc.id, tc.dishName, targetLang)
              .timeout(const Duration(seconds: 8), onTimeout: () => null);
          if (t != null && t.trim().isNotEmpty) updatedTtk++;
        } catch (_) {}
      }

      if (showNotif) {
        scaffoldMessenger.removeCurrentSnackBar();
        final n = updatedProducts + updatedTtk;
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
                n > 0 ? '${loc.t('translate_done')} (+$n)' : loc.t('translate_done')),
            backgroundColor: n > 0 ? Colors.green : null,
          ),
        );
      }
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
                  constraints:
                      const BoxConstraints(maxWidth: 400, maxHeight: 500),
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
                        onChanged: (v) =>
                            setDialogState(() => useOther = v ?? false),
                        title: Text(loc.t('custom_currency'),
                            style: const TextStyle(fontSize: 14)),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
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
                                leading: Text(symbol,
                                    style: const TextStyle(fontSize: 20)),
                                title: Text('$code — $name'),
                                trailing: selected
                                    ? const Icon(Icons.check,
                                        color: Colors.green)
                                    : null,
                                onTap: () async {
                                  final updated = establishment.copyWith(
                                    defaultCurrency: code,
                                    updatedAt: DateTime.now(),
                                  );
                                  await account.updateEstablishment(updated);
                                  if (ctx2.mounted) {
                                    Navigator.of(ctx2).pop();
                                    ScaffoldMessenger.of(ctx2).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              '${loc.t('currency_saved')}: $code')),
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
                                child: Text(MaterialLocalizations.of(ctx2)
                                    .cancelButtonLabel),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () async {
                                  final code = customController.text
                                      .trim()
                                      .toUpperCase();
                                  if (code.length != 3) return;
                                  final updated = establishment.copyWith(
                                    defaultCurrency: code,
                                    updatedAt: DateTime.now(),
                                  );
                                  await account.updateEstablishment(updated);
                                  if (ctx2.mounted) {
                                    Navigator.of(ctx2).pop();
                                    ScaffoldMessenger.of(ctx2).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              '${loc.t('currency_saved')}: $code')),
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

  void _showBirthdayNotifyDaysPicker(BuildContext context,
      LocalizationService loc, ScreenLayoutPreferenceService screenPref) {
    final current = screenPref.birthdayNotifyDays;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(loc.t('birthday_notify_days') ?? 'Оповещение о днях рождения'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [0, 1, 2, 3, 4, 5].map((days) {
              final label = days == 0
                  ? (loc.t('birthday_notify_off') ?? 'Без уведомления')
                  : (loc.t('birthday_notify_days_value') ?? 'За %s дн. до ДР')
                      .replaceAll('%s', '$days');
              final selected = current == days;
              return ListTile(
                title: Text(label),
                trailing: selected
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  await screenPref.setBirthdayNotifyDays(days);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showBirthdayNotifyTimePicker(BuildContext context,
      LocalizationService loc, ScreenLayoutPreferenceService screenPref) {
    final options = birthdayNotifyTimeOptions;
    final current = screenPref.birthdayNotifyTime;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('birthday_notify_time') ?? 'Время уведомления'),
        content: SizedBox(
          width: 200,
          height: 320,
          child: ListView.builder(
            itemCount: options.length,
            itemBuilder: (_, i) {
              final time = options[i];
              final selected = current == time;
              return ListTile(
                dense: true,
                title: Text(time),
                trailing: selected
                    ? const Icon(Icons.check, color: Colors.green, size: 20)
                    : null,
                onTap: () async {
                  await screenPref.setBirthdayNotifyTime(time);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  static const _trainingVideos = <String, String>{
    'training_video_checklist_create_ttk_inbox': 'https://youtu.be/goZ20v6DV2s',
    'training_video_checklist_fill': 'https://youtu.be/ggc8es-ivJc',
    'training_video_ttk_create_view': 'https://youtu.be/MixDi9UC2kg',
    'training_video_inventory_iiko_blank_upload':
        'https://youtu.be/JjMe-Tb04ZM',
    'training_video_product_order_email': 'https://youtu.be/e5DJHk_pSbE',
    'training_video_employees_setup': 'https://youtu.be/bGVJtSdpid0',
    'training_video_owner_role_switch': 'https://youtu.be/nkk9BpyIkuQ',
    'training_video_inventory_iiko_blank_export':
        'https://youtu.be/rFXg9gJ5qUw',
    'training_video_inventory_iiko_merge_1': 'VFSGL0Zj7fc',
    'training_video_inventory_iiko_merge_2': 'WQruFDlDQ',
    'training_video_schedule_edit': 'https://youtu.be/sF26hjgdjO8',
    'training_video_messages': 'https://youtu.be/zgH9ITDHU4U',
    'training_video_messages_with_translation': 'https://youtu.be/ZICdajkAbNY',
    'training_video_salary_payment_export': 'https://youtu.be/tO4ihTk8bDM',
    'training_video_products_price_change': 'https://youtu.be/p9I1rsNgXpU',
    'training_video_products_nomenclature_file': 'https://youtu.be/po5_brrXdVw',
    'training_video_products_nomenclature_text': 'https://youtu.be/66Q9iUyuqso',
    'training_video_products_text_from_table': 'https://youtu.be/tYsFlIll954',
  };

  /// Извлекает video ID из URL или возвращает как есть, если уже ID (напр. tJvjUcNRnsc-1)
  static String? _videoId(String urlOrId) {
    final s = urlOrId.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) return s; // уже ID
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return uri.queryParameters['v'];
  }

  static String _fallbackYoutubeUrl(String urlOrId) {
    final id = _videoId(urlOrId);
    if (id == null) return urlOrId;
    final baseId = id.contains('-') ? id.split('-').first : id;
    return 'https://youtu.be/$baseId';
  }

  void _showTrainingDialog(BuildContext context, LocalizationService loc) {
    final accountManager = context.read<AccountManagerSupabase>();
    final tourService = context.read<PageTourService>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('training') ?? 'Обучение'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              // Секция: Тур (весь и частями)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  loc.t('training_section_tour') ?? 'Тур',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.tour_outlined),
                title: Text(loc.t('tour_replay') ?? 'Пройти тур'),
                subtitle: Text(loc.t('tour_replay_subtitle') ??
                    'Подсветка рабочего стола и нижней панели'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(ctx).pop();
                  tourService.requestTourReplay(PageTourKeys.home);
                  context.go('/home');
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(loc.t('tour_replay_ttk') ?? 'Пройти тур ТТК'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(ctx).pop();
                  tourService.requestTourReplay(PageTourKeys.techCards);
                  context.go('/tech-cards/kitchen');
                },
              ),
              const Divider(),
              // Секция: Видео
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  loc.t('training_section_videos') ?? 'Видео',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              ..._trainingVideos.entries.map((e) {
                final title = loc.t(e.key) == e.key ? e.key : loc.t(e.key);
                return ListTile(
                  leading:
                      const Icon(Icons.play_circle_outline, color: Colors.red),
                  title: Text(title, style: const TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  dense: true,
                  onTap: () async {
                    final videoId = _videoId(e.value);
                    String? url = _fallbackYoutubeUrl(e.value);
                    if (videoId != null) {
                      try {
                        final res = await accountManager
                            .supabase.client.functions
                            .invoke(
                          'get-training-video-url',
                          queryParameters: {'id': videoId},
                        );
                        if (res.status == 200 && res.data is Map) {
                          final data = res.data as Map<String, dynamic>;
                          url = data['url']?.toString();
                        }
                      } catch (_) {}
                    }
                    if (url != null) {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                );
              }),
              const Divider(),
              // Секция: Начало работы
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  loc.t('training_section_getting_started') ?? 'Начало работы',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(
                    loc.t('getting_started') ?? 'Начало работы с Restodocks'),
                subtitle: Text(loc.t('getting_started_subtitle') ??
                    'Текстовая инструкция с раскрывающимися разделами'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showGettingStartedTextDialog(context, loc);
                },
              ),
            ],
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

  void _showGettingStartedTextDialog(
      BuildContext context, LocalizationService loc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('getting_started') ?? 'Начало работы (текст)'),
        content: SizedBox(
          width: 400,
          height: 500,
          child: const GettingStartedDocument(showTitle: true),
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
      BuildContext context,
      LocalizationService loc,
      Employee emp,
      AccountManagerSupabase accountManager) {
    final prefs = context.watch<NotificationPreferencesService>();
    final empId = emp.id;
    final isOwner = emp.hasRole('owner');
    final isManagement = emp.department == 'management' ||
        emp.hasRole('executive_chef') ||
        emp.hasRole('sous_chef') ||
        emp.hasRole('bar_manager') ||
        emp.hasRole('floor_manager');
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
              NotificationDisplayType.banner =>
                loc.t('notification_banner') ?? 'Плашка сверху',
              NotificationDisplayType.modal =>
                loc.t('notification_modal') ?? 'Окошко в центре',
              NotificationDisplayType.disabled =>
                loc.t('notification_disabled') ?? 'Отключены',
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
            if (prefs.messages) ...[
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.t('notification_show_message_text')),
                  subtitle: Text(
                    loc.t('notification_show_message_text_hint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  value: prefs.showMessageBodyInNotifications,
                  onChanged: (v) => prefs.setShowMessageBodyInNotifications(v, empId),
                ),
              ),
            ],
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
                title: Text(
                    loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko'),
                value: prefs.iikoInventory,
                onChanged: (v) => prefs.setIikoInventory(v, empId),
              ),
              SwitchListTile(
                title: Text(loc.t('checklists') ?? 'Чеклисты'),
                subtitle: Text(
                  loc.t('notification_incoming_checklists_hint') ??
                      'Входящие: заполненные чеклисты',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: prefs.checklists,
                onChanged: (v) => prefs.setChecklists(v, empId),
              ),
              SwitchListTile(
                title: Text(loc.t('writeoffs') ?? 'Списания'),
                subtitle: Text(
                  loc.t('notification_incoming_writeoffs_hint') ??
                      'Входящие: документы списания',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: prefs.writeoffs,
                onChanged: (v) => prefs.setWriteoffs(v, empId),
              ),
            ],
            SwitchListTile(
              title: Text(loc.t('inbox_tab_notifications') ?? 'Уведомления'),
              subtitle: Text(
                isLineStaff
                    ? (loc.t('notification_checklist_assigned') ??
                        'Чеклисты, назначенные на вас')
                    : (loc.t('notification_schedule_changes') ??
                        'Изменения штатного расписания'),
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

  Future<void> _toggleHaccpJournal(
    BuildContext context,
    HaccpConfigService config,
    String establishmentId,
    HaccpLogType logType,
    bool enabled,
    LocalizationService loc,
  ) async {
    try {
      await config.setEnabled(establishmentId, logType, enabled);
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString().contains('404') ||
                e.toString().contains('does not exist')
            ? (loc.t('haccp_config_table_missing') ??
                'Таблица настроек журналов не найдена. Примените миграции Supabase (supabase db push или миграции 20260313).')
            : '${loc.t('error')}: $e';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
      }
    }
  }

  Future<void> _downloadHaccpAgreement(
      BuildContext context, LocalizationService loc) async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    final emp = account.currentEmployee;
    if (est == null || emp == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  loc.t('establishment_not_found') ?? 'Заведение не выбрано')),
        );
      }
      return;
    }
    try {
      // Выбор языка соглашения
      String selectedLang = loc.currentLanguageCode;
      final pickedLang = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setState) => AlertDialog(
            title: Text(loc.t('haccp_agreement_lang_title') ??
                loc.t('language') ??
                'Language'),
            content: Wrap(
              spacing: 8,
              children: LocalizationService.productLanguageCodes.map((code) {
                return ChoiceChip(
                  label: Text(loc.getLanguageName(code)),
                  selected: selectedLang == code,
                  onSelected: (_) => setState(() => selectedLang = code),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx2).pop(),
                child: Text(MaterialLocalizations.of(ctx2).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx2).pop(selectedLang),
                child: Text(loc.t('download') ?? 'Download'),
              ),
            ],
          ),
        ),
      );
      if (pickedLang == null || !context.mounted) return;

      final lang = pickedLang;
      final roleCode =
          emp.positionRole ?? (emp.roles.contains('owner') ? 'owner' : null);
      final employerPosition =
          roleCode != null ? (loc.tForLanguage(lang, 'role_$roleCode')) : null;
      final bytes = await HaccpAgreementPdfService.buildAgreementPdfBytes(
        establishment: est,
        employerEmployee: emp,
        organizationLabel: loc.tForLanguage(lang, 'haccp_agreement_org'),
        innBinLabel: loc.tForLanguage(lang, 'haccp_agreement_inn_bin'),
        addressLabel: loc.tForLanguage(lang, 'haccp_agreement_address'),
        documentTitle: loc.tForLanguage(lang, 'haccp_agreement_doc_title'),
        documentSubtitle:
            loc.tForLanguage(lang, 'haccp_agreement_doc_subtitle'),
        agreementHeading: loc.tForLanguage(lang, 'haccp_agreement_heading'),
        workerLabel: loc.tForLanguage(lang, 'haccp_agreement_worker'),
        workerFioHint:
            loc.tForLanguage(lang, 'haccp_agreement_worker_fio_hint'),
        positionLabel: loc.tForLanguage(lang, 'haccp_agreement_position'),
        dateLine: loc.tForLanguage(lang, 'haccp_agreement_date_line'),
        employerLabel: loc.tForLanguage(lang, 'haccp_agreement_employer'),
        stampHint: loc.tForLanguage(lang, 'haccp_agreement_stamp_hint'),
        workerSignLabel: loc.tForLanguage(lang, 'haccp_agreement_worker_sign'),
        agreementBody: loc.tForLanguage(lang, 'haccp_agreement_body'),
        employerPositionLabel:
            (employerPosition != null && employerPosition != 'role_$roleCode')
                ? employerPosition
                : null,
      );
      await saveFileBytes('haccp_agreement_employee.pdf', bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t('haccp_agreement_saved') ?? 'PDF saved')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('error')}: $e')),
        );
      }
    }
  }

  void _showSupportEmailForm(BuildContext context, LocalizationService loc) {
    final accountManager = context.read<AccountManagerSupabase>();
    final authEmail =
        Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';
    final userEmail = authEmail.isNotEmpty
        ? authEmail
        : (accountManager.currentEmployee?.email ?? '').trim();

    final categories = [
      loc.t('support_category_pro_testing'),
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
                Text(
                  loc.t('support_account_email'),
                  style: Theme.of(ctx2).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(ctx2).dividerColor,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    userEmail.isEmpty ? '—' : userEmail,
                    style: Theme.of(ctx2).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                Text(loc.t('support_category'),
                    style: Theme.of(ctx2).textTheme.labelMedium),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), isDense: true),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: isSending
                      ? null
                      : (v) => setDialogState(
                          () => selectedCategory = v ?? selectedCategory),
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
                const SizedBox(height: 16),
                InkWell(
                  onTap: isSending
                      ? null
                      : () async {
                          final uri = Uri.parse('https://t.me/restodocks');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                  child: Row(
                    children: [
                      const Icon(Icons.telegram, color: Color(0xFF2AABEE)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Telegram @restodocks',
                          style: Theme.of(ctx2).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx2).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                        ),
                      ),
                    ],
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
                      if (userEmail.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(loc.t('support_missing_account_email'))),
                        );
                        return;
                      }
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
                                  child: Text(MaterialLocalizations.of(context)
                                      .okButtonLabel),
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
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
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
                  child: Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_ownerEstablishments.length > 1) ...[
                ..._ownerEstablishments.map((est) {
                  final parentName =
                      est.isBranch && est.parentEstablishmentId != null
                          ? _ownerEstablishments
                              .where((e) => e.id == est.parentEstablishmentId)
                              .firstOrNull
                              ?.name
                          : null;
                  return ListTile(
                    leading: Icon(
                      est.id == establishment?.id
                          ? Icons.check_circle
                          : (est.isBranch ? Icons.account_tree : Icons.store),
                      color: est.id == establishment?.id
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(est.name),
                    subtitle: est.id == establishment?.id
                        ? Text(localization.t('current') ?? 'Текущее')
                        : (est.isBranch && parentName != null
                            ? Text(
                                '${localization.t('branch_of') ?? 'Филиал'}: $parentName')
                            : (est.isMain
                                ? Text(localization.t('main_establishment') ??
                                    'Основное')
                                : null)),
                    trailing: est.id == establishment?.id
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: est.id == establishment?.id
                        ? null
                        : () async {
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
                  title: Text(localization.t('add_establishment') ??
                      'Добавить заведение'),
                  subtitle: Text(
                    (localization.t('establishments_counter') ??
                            '{current} из {max}')
                        .replaceAll('{current}',
                            '${(_ownerEstablishments.length - 1).clamp(0, _maxEstablishmentsPerOwner)}')
                        .replaceAll('{max}', '$_maxEstablishmentsPerOwner'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: (_ownerEstablishments.length - 1) >=
                          _maxEstablishmentsPerOwner
                      ? null
                      : () => context.push('/add-establishment'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(
                    localization.t('delete_establishment') ??
                        'Удалить заведение',
                    style: const TextStyle(color: Colors.red),
                  ),
                  subtitle: Text(localization.t('delete_establishment_hint') ??
                      'Удалить заведение и все связанные данные безвозвратно'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: establishment != null
                      ? () => _showDeleteEstablishmentConfirm(
                          context, localization, establishment!)
                      : null,
                ),
              ],
              const Divider(),
            ],
            ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.dashboard_customize),
              title: Text(localization.t('home_layout_config') ??
                  'Настройка домашнего экрана'),
              children: [
                if (MediaQuery.of(context).size.shortestSide < 600)
                  Consumer<MobileUiScaleService>(
                    builder: (_, uiScale, __) => ListTile(
                      leading: const SizedBox(width: 24),
                      title: Text(localization.t('mobile_ui_scale') ??
                          'Масштаб (мобильная версия)'),
                      subtitle: Text(
                        uiScale.preset == 1
                            ? '80%'
                            : uiScale.preset == 2
                                ? '90%'
                                : '100%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(localization.t('mobile_ui_scale') ??
                              'Масштаб (мобильная версия)'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RadioListTile<int>(
                                value: 1,
                                groupValue: uiScale.preset,
                                title: const Text('80%'),
                                onChanged: (v) async {
                                  if (v == null) return;
                                  await uiScale.setPreset(v);
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                },
                              ),
                              RadioListTile<int>(
                                value: 2,
                                groupValue: uiScale.preset,
                                title: const Text('90%'),
                                onChanged: (v) async {
                                  if (v == null) return;
                                  await uiScale.setPreset(v);
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                },
                              ),
                              RadioListTile<int>(
                                value: 3,
                                groupValue: uiScale.preset,
                                title: const Text('100%'),
                                onChanged: (v) async {
                                  if (v == null) return;
                                  await uiScale.setPreset(v);
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: Text(localization.t('home_layout_config_hint') ??
                      'Изменить порядок кнопок на главной'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showHomeLayoutConfig(context, localization),
                ),
                Consumer<HomeButtonConfigService>(
                  builder: (_, homeBtn, __) => ListTile(
                    leading: const SizedBox(width: 24),
                    title: Text(localization.t('button_display_config') ??
                        'Настройка кнопки'),
                    subtitle: Text(localization.t('central_button_hint') ??
                        'Выбор для отображения желаемого'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _showHomeButtonPicker(context, localization, homeBtn),
                  ),
                ),
                Consumer<ScreenLayoutPreferenceService>(
                  builder: (_, screenPref, __) => SwitchListTile(
                    secondary: const Icon(Icons.restaurant_menu),
                    title: Text(localization.t('show_banquet_catering') ??
                        'Показ «банкеты и кейтринг» на экране'),
                    subtitle: Text(localization
                            .t('show_banquet_catering_hint') ??
                        'Показывать «Меню — Банкет/Кейтринг» и «ТТК — Банкет/Кейтринг»'),
                    value: screenPref.showBanquetCatering,
                    onChanged: (v) => screenPref.setShowBanquetCatering(v),
                  ),
                ),
                if (currentEmployee.hasRole('owner')) ...[
                  Consumer<ScreenLayoutPreferenceService>(
                    builder: (_, screenPref, __) => SwitchListTile(
                      secondary: const Icon(Icons.local_bar),
                      title: Text(localization.t('show_bar_section') ??
                          'Раздел «Бар» на главной'),
                      subtitle: Text(localization.t('show_bar_section_hint') ??
                          'Показывать секцию Бар (график, меню, ТТК и др.)'),
                      value: screenPref.showBarSection,
                      onChanged: (v) => screenPref.setShowBarSection(v),
                    ),
                  ),
                  Consumer<ScreenLayoutPreferenceService>(
                    builder: (_, screenPref, __) => SwitchListTile(
                      secondary: const Icon(Icons.table_restaurant),
                      title: Text(localization.t('show_hall_section') ??
                          'Раздел «Зал» на главной'),
                      subtitle: Text(localization.t('show_hall_section_hint') ??
                          'Показывать секцию Зал (график, меню, чеклисты и др.)'),
                      value: screenPref.showHallSection,
                      onChanged: (v) => screenPref.setShowHallSection(v),
                    ),
                  ),
                ],
              ],
            ),
            if (FeatureFlags.posModuleEnabled &&
                posCanConfigureOrdersDisplay(currentEmployee))
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(localization.t('pos_orders_display_settings_title') ??
                    'Отображение заказов'),
                subtitle: Text(
                  localization.t('pos_orders_display_settings_subtitle') ??
                      'Таймер и размеры шрифтов на экранах заказов',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/orders-display'),
              ),
            if (FeatureFlags.posModuleEnabled)
              SalesFinancialsManagementTile(employee: currentEmployee),
            if (FeatureFlags.posModuleEnabled &&
                posCanManageFiscalTaxSettings(currentEmployee))
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(localization.t('fiscal_settings_title')),
                subtitle: Text(
                  localization.t('fiscal_settings_subtitle'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/fiscal-tax'),
              ),
            // Журнал ошибок — см. FeatureFlags.showSystemErrorsJournal (beta, не restodocks.com; все платформы).
            if (FeatureFlags.showSystemErrorsJournal &&
                (posCanRunWarehouseHealthCheck(currentEmployee) ||
                    _isPlatformAdminEmail(currentEmployee.email)))
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(localization.t('settings_system_errors_title') ??
                    'Журнал ошибок'),
                subtitle: Text(
                  localization.t('settings_system_errors_subtitle') ??
                      'POS, склад, фоновые сбои',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/system-errors'),
              ),
            if (posCanConfigureOrdersDisplay(currentEmployee))
              ExpansionTile(
                initiallyExpanded: false,
                leading: const Icon(Icons.people),
                title:
                    Text(localization.t('settings_employees') ?? 'Сотрудники'),
                subtitle: Text(
                  localization.t('settings_employees_hint') ??
                      'Имена транслитом и уведомления о днях рождения',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [
                  Consumer<ScreenLayoutPreferenceService>(
                    builder: (_, screenPref, __) => SwitchListTile(
                      secondary: const Icon(Icons.translate),
                      title: Text(localization.t('show_name_translit') ??
                          'Показывать имена транслитом'),
                      subtitle: Text(localization
                              .t('show_name_translit_hint') ??
                          'Отображать ФИО сотрудников латиницей (например, Иванов → Ivanov)'),
                      value: screenPref.showNameTranslit,
                      onChanged: (v) => screenPref.setShowNameTranslit(v),
                    ),
                  ),
                  Consumer<ScreenLayoutPreferenceService>(
                    builder: (_, screenPref, __) {
                      final days = screenPref.birthdayNotifyDays;
                      return ListTile(
                        leading: const Icon(Icons.cake),
                        title: Text(localization.t('birthday_notify_days') ??
                            'Оповещение о днях рождения'),
                        subtitle: Text(
                          days == 0
                              ? (localization.t('birthday_notify_off') ??
                                  'Без уведомления')
                              : (localization.t('birthday_notify_days_value') ??
                                      'За %s дн. до ДР')
                                  .replaceAll('%s', '$days'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showBirthdayNotifyDaysPicker(
                            context, localization, screenPref),
                      );
                    },
                  ),
                  if (context
                          .read<ScreenLayoutPreferenceService>()
                          .birthdayNotifyDays >
                      0)
                    Consumer<ScreenLayoutPreferenceService>(
                      builder: (_, screenPref, __) => ListTile(
                        leading: const Icon(Icons.schedule),
                        title: Text(localization.t('birthday_notify_time') ??
                            'Время уведомления'),
                        subtitle: Text(
                          screenPref.birthdayNotifyTime,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showBirthdayNotifyTimePicker(
                            context, localization, screenPref),
                      ),
                    ),
                ],
              ),
            Consumer<ScreenLayoutPreferenceService>(
              builder: (_, screenPref, __) => SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: Text(localization.t('show_translation_notifications') ??
                    'Уведомления о переводах'),
                subtitle: Text(
                    localization.t('show_translation_notifications_hint') ??
                        'Плашка «Переводы обновлены» при смене языка'),
                value: screenPref.showTranslationNotifications,
                onChanged: (v) => screenPref.setShowTranslationNotifications(v),
              ),
            ),
            // Журналы и ХАССП (включая юридическую легитимность) — для руководителей.
            if (currentEmployee.hasRole('owner') ||
                currentEmployee.department == 'management' ||
                currentEmployee.hasRole('executive_chef') ||
                currentEmployee.hasRole('sous_chef') ||
                currentEmployee.hasRole('bar_manager') ||
                currentEmployee.hasRole('floor_manager') ||
                currentEmployee.hasRole('general_manager')) ...[
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(localization.t('documentation') ?? 'Документация'),
                subtitle: Text(localization.t('documentation_haccp_subtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/haccp-documentation'),
              ),
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: Text(localization.t('public_offer')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/legal/offer'),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(localization.t('privacy_policy')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/legal/privacy'),
              ),
              ExpansionTile(
                initiallyExpanded: false,
                leading: const Icon(Icons.assignment),
                title:
                    Text(localization.t('haccp_journals') ?? 'Журналы и ХАССП'),
                subtitle: Text(
                  localization.t('haccp_journals_settings_hint') ??
                      'Выбор журналов для заведения',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [
                  Consumer<HaccpConfigService>(
                    builder: (_, config, __) {
                      final est = establishment;
                      if (est == null) return const SizedBox.shrink();
                      final enabled = config.getEnabledLogTypes(est.id);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localization.t('haccp_enabled_journals') ??
                                  'Включённые журналы',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            ...HaccpLogType.supportedInApp.map((t) {
                              final isOn = enabled.contains(t.code);
                              return ListTile(
                                leading: Checkbox(
                                  value: isOn,
                                  onChanged: (v) => _toggleHaccpJournal(
                                      context,
                                      config,
                                      est.id,
                                      t,
                                      v ?? false,
                                      localization),
                                ),
                                title: Text(
                                    localization.t(t.displayNameKey) ??
                                        t.displayNameRu,
                                    style: const TextStyle(fontSize: 14)),
                                onTap: () => _toggleHaccpJournal(context,
                                    config, est.id, t, !isOn, localization),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
            ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.notifications),
              title: Text(
                  localization.t('notification_settings') ?? 'Уведомления'),
              subtitle: Text(localization.t('notification_settings_hint') ??
                  'Вид уведомлений и какие включены'),
              children: [
                _buildNotificationSettings(
                    context, localization, currentEmployee, accountManager),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(localization.t('language')),
              subtitle: Text(localization
                  .getLanguageName(localization.currentLanguageCode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguagePicker(context, localization),
            ),
            Consumer<ThemeService>(
              builder: (_, themeService, __) => SwitchListTile(
                secondary: const Icon(Icons.palette),
                title: Text(localization.t('appearance')),
                subtitle: Text(themeService.isDark
                    ? localization.t('dark_theme')
                    : localization.t('light_theme')),
                value: themeService.isDark,
                onChanged: (dark) => themeService
                    .setThemeMode(dark ? ThemeMode.dark : ThemeMode.light),
              ),
            ),
            // Валюта заведения — только у владельца и шеф-повара в настройках
            if (currentEmployee.hasRole('owner') ||
                currentEmployee.hasRole('executive_chef')) ...[
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: Text(localization.t('currency')),
                subtitle: Text(establishment?.currencySymbol ??
                    Establishment.currencySymbolFor(
                        establishment?.defaultCurrency ?? 'VND')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showCurrencyPicker(context, localization),
              ),
            ],
            // Очистить номенклатуру — шеф, барменеджер, менеджер зала
            if (currentEmployee.hasRole('executive_chef') ||
                currentEmployee.hasRole('bar_manager') ||
                currentEmployee.hasRole('floor_manager')) ...[
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(localization.t('clear_nomenclature') ??
                    'Очистить номенклатуру'),
                subtitle: Text(localization.t('clear_nomenclature_hint') ??
                    'Удалить все продукты из номенклатуры заведения'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    _showClearNomenclatureConfirm(context, localization),
              ),
              // Только в Beta-tools: удалить все ТТК (в Prod не показывается)
              if (FeatureFlags.betaToolsEnabled)
                ListTile(
                  leading:
                      const Icon(Icons.restaurant_menu, color: Colors.orange),
                  title: Text(
                      localization.t('clear_all_ttk') ?? 'Удалить все ТТК'),
                  subtitle: Text(localization.t('settings_beta_admin_subtitle')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showClearAllTtkConfirm(context, localization),
                ),
            ],
            if (currentEmployee.hasRole('owner')) ...[
              ProSettingsOwnerSection(
                localization: localization,
                accountManager: accountManager,
              ),
              // 1. Должность — добавляемая должность для собственника (не «собственник»)
              ListTile(
                leading: const Icon(Icons.work),
                title: Text(localization.t('position')),
                subtitle: Text(_getPositionDisplayName(
                    currentEmployee.positionRole, localization)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showPositionPicker(
                    context, localization, currentEmployee, accountManager),
              ),
              // 2. Выбор роли — список «Собственник» или должность (не переключатель)
              if (currentEmployee.positionRole != null)
                Consumer<OwnerViewPreferenceService>(
                  builder: (_, pref, __) => ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(localization.t('role_selection')),
                    subtitle: Text(pref.viewAsOwner
                        ? localization.t('owner')
                        : _getPositionDisplayName(
                            currentEmployee.positionRole, localization)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showRolePicker(context, localization,
                        currentEmployee, accountManager, pref),
                  ),
                ),
              if (!accountManager.isViewOnlyOwner)
                ListTile(
                  leading: const Icon(Icons.person_add),
                  title: Text(localization.t('invite_co_owner')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showInviteCoOwnerDialog(
                      context, localization, accountManager),
                ),
              if ((currentEmployee.hasRole('executive_chef') ||
                      currentEmployee.hasRole('sous_chef')) &&
                  accountManager.establishment?.isMain == true)
                FutureBuilder<List<Establishment>>(
                  future: accountManager.getBranchesForEstablishment(
                      accountManager.establishment!.id),
                  builder: (ctx, snap) {
                    if (!snap.hasData || snap.data!.isEmpty)
                      return const SizedBox.shrink();
                    final branches = snap.data!;
                    return Consumer<TtkBranchFilterService>(
                      builder: (_, branchFilter, __) {
                        final selId = branchFilter.selectedBranchId;
                        final name = selId == null
                            ? (localization.t('main_establishment') ??
                                'Основное')
                            : branches
                                    .where((b) => b.id == selId)
                                    .map((b) => b.name)
                                    .firstOrNull ??
                                selId;
                        return ListTile(
                          leading: const Icon(Icons.account_tree),
                          title: Text(localization.t('ttk_branch_display') ??
                              'Отображение ТТК по филиалам'),
                          subtitle: Text(name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showTtkBranchFilterPicker(
                              context, localization, accountManager, branches),
                        );
                      },
                    );
                  },
                ),
              if (accountManager.isViewOnlyOwner)
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: Text(localization.t('view_only_mode') ??
                      'Режим только просмотр'),
                  subtitle: Text(localization.t('view_only_mode_hint') ??
                      'Соучредитель при нескольких заведениях'),
                ),
            ],
            // Кнопка платформенного кабинета — видна только владельцу платформы
            if (_isPlatformAdminEmail(currentEmployee.email)) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings,
                    color: Colors.deepPurple),
                title: Text(
                  localization.t('settings_platform_admin_title'),
                  style: const TextStyle(color: Colors.deepPurple),
                ),
                subtitle: Text(localization.t('settings_platform_admin_subtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin'),
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(localization.t('training') ?? 'Обучение'),
              subtitle: Text(localization.t('training_subtitle') ??
                  'Видео, тур и начало работы'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTrainingDialog(context, localization),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: Text(localization.t('contact_support')),
              subtitle: Text(localization.t('contact_support_subtitle')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showSupportEmailForm(context, localization),
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

class _RequisitesForm extends StatefulWidget {
  const _RequisitesForm({
    required this.establishment,
    required this.onSave,
    required this.loc,
  });

  final Establishment establishment;
  final Future<void> Function(Establishment) onSave;
  final LocalizationService loc;

  @override
  State<_RequisitesForm> createState() => _RequisitesFormState();
}

class _RequisitesFormState extends State<_RequisitesForm> {
  late TextEditingController _legalNameController;
  late TextEditingController _innBinController;
  late TextEditingController _addressController;
  late TextEditingController _ogrnOgrnipController;
  late TextEditingController _kppController;
  late TextEditingController _bankRsController;
  late TextEditingController _bankBikController;
  late TextEditingController _bankNameController;
  late TextEditingController _directorFioController;
  late TextEditingController _directorPositionController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _legalNameController = TextEditingController(
        text: widget.establishment.legalName ?? widget.establishment.name);
    _innBinController =
        TextEditingController(text: widget.establishment.innBin ?? '');
    _addressController =
        TextEditingController(text: widget.establishment.address ?? '');
    _ogrnOgrnipController =
        TextEditingController(text: widget.establishment.ogrnOgrnip ?? '');
    _kppController =
        TextEditingController(text: widget.establishment.kpp ?? '');
    _bankRsController =
        TextEditingController(text: widget.establishment.bankRs ?? '');
    _bankBikController =
        TextEditingController(text: widget.establishment.bankBik ?? '');
    _bankNameController =
        TextEditingController(text: widget.establishment.bankName ?? '');
    _directorFioController =
        TextEditingController(text: widget.establishment.directorFio ?? '');
    _directorPositionController = TextEditingController(
        text: widget.establishment.directorPosition ?? '');
  }

  @override
  void dispose() {
    _legalNameController.dispose();
    _innBinController.dispose();
    _addressController.dispose();
    _ogrnOgrnipController.dispose();
    _kppController.dispose();
    _bankRsController.dispose();
    _bankBikController.dispose();
    _bankNameController.dispose();
    _directorFioController.dispose();
    _directorPositionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _legalNameController,
            decoration: InputDecoration(
              labelText:
                  widget.loc.t('requisites_organization') ?? 'Юр. название',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _innBinController,
            decoration: InputDecoration(
              labelText: widget.loc.t('requisites_inn_bin') ?? 'ИНН / БИН',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ogrnOgrnipController,
            decoration: InputDecoration(
              labelText: 'ОГРН / ОГРНИП',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kppController,
            decoration: InputDecoration(
              labelText: 'КПП',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bankRsController,
            decoration: InputDecoration(
              labelText: 'Р/С',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bankBikController,
            decoration: InputDecoration(
              labelText: 'БИК',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bankNameController,
            decoration: InputDecoration(
              labelText: 'Банк',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _directorFioController,
            decoration: InputDecoration(
              labelText: 'ФИО руководителя',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _directorPositionController,
            decoration: InputDecoration(
              labelText: 'Должность руководителя',
              border: const OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: widget.loc.t('requisites_address') ?? 'Адрес',
              border: const OutlineInputBorder(),
              filled: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      final legalName = _legalNameController.text.trim();
                      final updated = widget.establishment.copyWith(
                        legalName: legalName.isEmpty ? null : legalName,
                        innBin: _innBinController.text.trim().isEmpty
                            ? null
                            : _innBinController.text.trim(),
                        address: _addressController.text.trim().isEmpty
                            ? null
                            : _addressController.text.trim(),
                        ogrnOgrnip: _ogrnOgrnipController.text.trim().isEmpty
                            ? null
                            : _ogrnOgrnipController.text.trim(),
                        kpp: _kppController.text.trim().isEmpty
                            ? null
                            : _kppController.text.trim(),
                        bankRs: _bankRsController.text.trim().isEmpty
                            ? null
                            : _bankRsController.text.trim(),
                        bankBik: _bankBikController.text.trim().isEmpty
                            ? null
                            : _bankBikController.text.trim(),
                        bankName: _bankNameController.text.trim().isEmpty
                            ? null
                            : _bankNameController.text.trim(),
                        directorFio: _directorFioController.text.trim().isEmpty
                            ? null
                            : _directorFioController.text.trim(),
                        directorPosition:
                            _directorPositionController.text.trim().isEmpty
                                ? null
                                : _directorPositionController.text.trim(),
                        updatedAt: DateTime.now(),
                      );
                      await widget.onSave(updated);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(widget.loc.t('saved') ?? 'Сохранено')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: Text(_saving
                ? (widget.loc.t('saving') ?? 'Сохранение...')
                : (widget.loc.t('save') ?? 'Сохранить')),
          ),
        ],
      ),
    );
  }
}
