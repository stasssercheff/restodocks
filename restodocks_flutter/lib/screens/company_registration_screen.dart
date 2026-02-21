import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/countries_cities_data.dart';
import '../services/services.dart';

/// Регистрация компании: язык, название, страна/город (выпадающие с поиском), PIN автоген + копирование.
class CompanyRegistrationScreen extends StatefulWidget {
  const CompanyRegistrationScreen({super.key});

  @override
  State<CompanyRegistrationScreen> createState() => _CompanyRegistrationScreenState();
}

class _CompanyRegistrationScreenState extends State<CompanyRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  late String _pinCode;
  bool _isLoading = false;
  String? _errorMessage;
  CountryItem? _selectedCountry;
  CityItem? _selectedCity;

  @override
  void initState() {
    super.initState();
    _pinCode = Establishment.generatePinCode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _copyPin() {
    Clipboard.setData(ClipboardData(text: _pinCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocalizationService>().t('pin_copied'))),
    );
  }

  static bool _isDuplicatePinError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('duplicate') || s.contains('unique') || s.contains('23505');
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    const maxRetries = 3;
    String? errorMsg;
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Проверяем, что страна и город выбраны
        if (_selectedCountry == null || _selectedCity == null) {
          errorMsg = loc.t('country_and_city_required') ?? 'Выберите страну и город';
          break;
        }

        final accountManager = context.read<AccountManagerSupabase>();
        final name = _nameController.text.trim();
        final country = _selectedCountry!;
        final city = _selectedCity!;
        final address = '${city.name(lang)}, ${country.name(lang)}';

        final establishment = await accountManager.createEstablishment(
          name: name,
          pinCode: _pinCode,
          address: address,
        );

        if (!mounted) return;
        context.push('/register-owner', extra: establishment);
        return;
      } catch (e) {
        if (!mounted) return;
        print('Ошибка при регистрации компании: $e'); // Для отладки
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
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final searchHint = loc.t('search');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('register_company')),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
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
                    await loc.setLocale(l);
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
                    searchFieldProps: TextFieldProps(
                      decoration: InputDecoration(hintText: searchHint),
                    ),
                  ),
                  validator: (v) => v == null ? loc.t('country_required') : null,
                  onChanged: (c) {
                    setState(() {
                      _selectedCountry = c;
                      _selectedCity = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownSearch<CityItem>(
                  selectedItem: _selectedCity,
                  enabled: _selectedCountry != null,
                  decoratorProps: DropDownDecoratorProps(
                    decoration: InputDecoration(
                      labelText: loc.t('city'),
                      hintText: loc.t('enter_city'),
                      prefixIcon: const Icon(Icons.location_city),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  items: (filter, loadProps) async {
                    if (_selectedCountry == null) return <CityItem>[];
                    final list = await CountriesCitiesData.citiesForCountry(_selectedCountry!.code);
                    if (filter.trim().isEmpty) return list;
                    final f = filter.trim().toLowerCase();
                    return list.where((c) => c.name(lang).toLowerCase().contains(f)).toList();
                  },
                  itemAsString: (c) => c.name(lang),
                  compareFn: (a, b) => a?.id == b?.id,
                  popupProps: PopupProps.menu(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(
                      decoration: InputDecoration(hintText: searchHint),
                    ),
                  ),
                  validator: (v) => v == null ? loc.t('city_required') : null,
                  onChanged: (c) => setState(() => _selectedCity = c),
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
