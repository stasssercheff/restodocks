import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/countries_cities_data.dart';
import '../services/services.dart';
import '../utils/dev_log.dart';
import '../widgets/app_bar_home_button.dart';

/// Регистрация компании: язык, название, страна/город (выпадающие с поиском), PIN автоген + копирование.
/// [ownerFirst] — шаг после регистрации владельца (сессия auth); RPC register_first_establishment_*.
class CompanyRegistrationScreen extends StatefulWidget {
  const CompanyRegistrationScreen({super.key, this.ownerFirst = false});

  final bool ownerFirst;

  @override
  State<CompanyRegistrationScreen> createState() => _CompanyRegistrationScreenState();
}

class _CompanyRegistrationScreenState extends State<CompanyRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _promoController = TextEditingController();

  late String _pinCode;
  bool _isLoading = false;
  String? _errorMessage;
  CountryItem? _selectedCountry;

  @override
  void initState() {
    super.initState();
    _pinCode = Establishment.generatePinCode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  void _copyPin() {
    Clipboard.setData(ClipboardData(text: _pinCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocalizationService>().t('pin_copied'))),
    );
  }

  void _clearTestData() async {
    try {
      final accountManager = context.read<AccountManagerSupabase>();
      await accountManager.deleteTestEmployees();
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('dev_test_data_cleared'))),
        );
      }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              loc.t('dev_test_data_clear_error', args: {'error': '$e'}),
            ),
          ),
        );
      }
    }
  }

  static bool _isDuplicatePinError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('duplicate') || s.contains('unique') || s.contains('23505');
  }

  String? _promoErrorFromException(Object e, LocalizationService loc) {
    final msg = e.toString();
    if (msg.contains('PROMO_INVALID')) return loc.t('promo_code_invalid');
    if (msg.contains('PROMO_USED')) return loc.t('promo_code_used');
    if (msg.contains('PROMO_NOT_STARTED')) return loc.t('promo_code_not_started');
    if (msg.contains('PROMO_EXPIRED')) return loc.t('promo_code_expired');
    if (msg.contains('PROMO_DISABLED')) return loc.t('promo_code_disabled');
    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;

    try {
      if (_selectedCountry == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = loc.t('country_required');
        });
        return;
      }

      final promoRaw = _promoController.text.trim();
      final promoCode = promoRaw.toUpperCase();
      final accountManager = context.read<AccountManagerSupabase>();
      final name = _nameController.text.trim();
      final address = _selectedCountry!.name(lang);
      const maxRetries = 3;
      String? errorMsg;

      for (var attempt = 0; attempt < maxRetries; attempt++) {
        try {
          if (widget.ownerFirst) {
            final acc = accountManager as AccountManagerSupabase;
            if (Supabase.instance.client.auth.currentSession == null) {
              if (!mounted) return;
              setState(() {
                _isLoading = false;
                _errorMessage = loc.t('pro_iap_session_missing');
              });
              return;
            }
            final Map<String, dynamic> rpcResult;
            if (promoRaw.isEmpty) {
              rpcResult = await acc.registerFirstEstablishmentWithoutPromo(
                name: name,
                address: address,
                pinCode: _pinCode,
              );
            } else {
              rpcResult = await acc.registerFirstEstablishmentWithPromo(
                promoCode: promoCode,
                name: name,
                address: address,
                pinCode: _pinCode,
              );
            }
            await acc.loginFromOwnerFirstEstablishmentResult(
              rpcResult,
              interfaceLanguageCode: lang,
            );
            final estRaw = rpcResult['establishment'];
            final empRaw = rpcResult['employee'];
            if (estRaw is Map && empRaw is Map) {
              final empData = Map<String, dynamic>.from(empRaw);
              empData['password'] = '';
              empData['password_hash'] = '';
              final employee = Employee.fromJson(empData);
              final establishment = Establishment.fromJson(
                Map<String, dynamic>.from(estRaw),
              );
              final estId = establishment.id;
              // register-metadata в owner-first даёт шумные 403 в части окружений.
              // Не блокирует бизнес-логику, поэтому пропускаем.
              if (estId.isNotEmpty) {
                // acc.registerMetadataBestEffort(estId);
              }
              // Письмо о регистрации компании/PIN отправляется серверным триггером БД
              // (on_establishment_created_send_owner_email), чтобы не зависеть от клиентских 4xx.
            }
            if (!mounted) return;
            context.go('/home');
            return;
          }

          final establishment = promoRaw.isEmpty
              ? await accountManager.registerCompanyWithoutPromo(
                  name: name,
                  address: address,
                  pinCode: _pinCode,
                )
              : await accountManager.registerCompanyWithPromo(
                  promoCode: promoCode,
                  name: name,
                  address: address,
                  pinCode: _pinCode,
                );

          if (!mounted) return;
          context.push('/register-owner', extra: establishment);
          return;
        } catch (e) {
          if (!mounted) return;
          final promoErr = _promoErrorFromException(e, loc);
          if (promoErr != null) {
            setState(() {
              _isLoading = false;
              _errorMessage = promoErr;
            });
            return;
          }
          if (attempt < maxRetries - 1 && _isDuplicatePinError(e)) {
            setState(() => _pinCode = Establishment.generatePinCode());
            continue;
          }
          errorMsg = loc.t('register_error', args: {'error': e.toString()});
          break;
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (errorMsg != null) _errorMessage = errorMsg;
        });
      }
    } catch (e) {
      if (mounted) {
        final promoErr = _promoErrorFromException(e, loc);
        setState(() {
          _isLoading = false;
          _errorMessage = promoErr ?? loc.t('register_error', args: {'error': e.toString()});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final searchHint = loc.t('search');

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('register_company')),
        actions: [
          // Кнопка очистки тестовых данных (только для разработки)
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: () async {
              final loc = context.read<LocalizationService>();
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(loc.t('dev_clear_test_data_title')),
                  content: Text(loc.t('dev_clear_test_data_body')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(loc.t('cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(loc.t('delete')),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                _clearTestData();
              }
            },
            tooltip: loc.t('dev_clear_test_data_tooltip'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.t('language_at_registration'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<Locale>(
                  value: loc.currentLocale,
                  decoration: InputDecoration(
                    labelText: loc.t('language'),
                    prefixIcon: const Icon(Icons.language),
                    border: const OutlineInputBorder(),
                  ),
                  items: LocalizationService.supportedLocales.map((l) {
                    return DropdownMenuItem(
                      value: l,
                      child: Text(loc.getLanguageName(l.languageCode)),
                    );
                  }).toList(),
                  onChanged: (l) async {
                    if (l == null) return;
                    await loc.setLocale(l, userChoice: true);
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  loc.t('company_info'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: loc.t('company_name'),
                    hintText: loc.t('enter_company_name'),
                    prefixIcon: const Icon(Icons.business),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return loc.t('company_name_required');
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownSearch<CountryItem>(
                  selectedItem: _selectedCountry,
                  decoratorProps: DropDownDecoratorProps(
                    decoration: InputDecoration(
                      labelText: loc.t('country'),
                      hintText: loc.t('enter_country'),
                      prefixIcon: const Icon(Icons.flag),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  items: (filter, loadProps) async {
                    final list = await CountriesCitiesData.loadCountries();
                    if (filter.trim().isEmpty) return list;
                    final f = filter.trim().toLowerCase();
                    return list.where((c) => c.name(lang).toLowerCase().contains(f)).toList();
                  },
                  itemAsString: (c) => c.name(lang),
                  compareFn: (a, b) => a?.code == b?.code,
                  popupProps: PopupProps.menu(
                    showSearchBox: true,
                    emptyBuilder: (context, searchEntry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(loc.t('nothing_found')),
                      ),
                    ),
                    searchFieldProps: TextFieldProps(
                      autofocus: true,
                      decoration: InputDecoration(hintText: searchHint),
                    ),
                  ),
                  validator: (v) => v == null ? loc.t('country_required') : null,
                  onChanged: (c) {
                    setState(() {
                      _selectedCountry = c;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _promoController,
                  decoration: InputDecoration(
                    labelText: loc.t('promo_code_optional'),
                    hintText: loc.t('enter_promo_code_optional'),
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 20),
                Text(loc.t('generated_pin'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  loc.t('pin_auto_hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _pinCode,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      onPressed: _copyPin,
                      icon: const Icon(Icons.copy),
                      tooltip: loc.t('copy_pin'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700)),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: _isLoading ? null : _register,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(loc.t('register')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
