import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/countries_cities_data.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Добавление заведения существующим владельцем (без регистрации владельца).
/// Похоже на регистрацию компании, но владелец уже зарегистрирован.
class AddEstablishmentScreen extends StatefulWidget {
  const AddEstablishmentScreen({super.key});

  @override
  State<AddEstablishmentScreen> createState() => _AddEstablishmentScreenState();
}

class _AddEstablishmentScreenState extends State<AddEstablishmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  CountryItem? _selectedCountry;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addEstablishment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;

    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final name = _nameController.text.trim();
      final address = _selectedCountry?.name(lang);

      final establishment = await accountManager.addEstablishmentForOwner(
        name: name,
        address: address,
      );

      if (!mounted) return;
      await accountManager.switchEstablishment(establishment);
      if (!mounted) return;
      context.go('/home');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('establishment_added') ?? 'Заведение добавлено'}: ${establishment.name}')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = loc.t('register_error', args: {'error': e.toString()});
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
        title: Text(loc.t('add_establishment') ?? 'Добавить заведение'),
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
                  loc.t('add_establishment_hint') ??
                      'Добавьте ещё одно заведение к вашему аккаунту. Владелец уже зарегистрирован.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
                    setState(() => _selectedCountry = c);
                  },
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
                  onPressed: _isLoading ? null : _addEstablishment,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(loc.t('add_establishment') ?? 'Добавить заведение'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
