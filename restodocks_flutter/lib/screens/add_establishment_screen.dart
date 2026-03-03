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

enum _EstablishmentType { newEst, branch }

class _AddEstablishmentScreenState extends State<AddEstablishmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  CountryItem? _selectedCountry;
  _EstablishmentType _type = _EstablishmentType.newEst;
  Establishment? _selectedParent;
  List<Establishment> _mainEstablishments = [];
  bool _loadingEstablishments = true;

  @override
  void initState() {
    super.initState();
    _loadMainEstablishments();
  }

  Future<void> _loadMainEstablishments() async {
    final acc = context.read<AccountManagerSupabase>();
    final all = await acc.getEstablishmentsForOwner();
    if (mounted) {
      setState(() {
        _mainEstablishments = all.where((e) => e.isMain).toList();
        _loadingEstablishments = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addEstablishment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == _EstablishmentType.branch && _selectedParent == null) return;

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
        parentEstablishmentId: _type == _EstablishmentType.branch ? _selectedParent!.id : null,
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
                  loc.t('establishment_type') ?? 'Тип заведения',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<_EstablishmentType>(
                  segments: [
                    ButtonSegment(
                      value: _EstablishmentType.newEst,
                      label: Text(loc.t('new_establishment') ?? 'Новое заведение'),
                      icon: const Icon(Icons.add_business_outlined),
                    ),
                    ButtonSegment(
                      value: _EstablishmentType.branch,
                      label: Text(loc.t('branch_of') ?? 'Филиал'),
                      icon: const Icon(Icons.account_tree_outlined),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() {
                    _type = s.first;
                    if (_type == _EstablishmentType.newEst) _selectedParent = null;
                  }),
                ),
                if (_type == _EstablishmentType.branch) ...[
                  const SizedBox(height: 16),
                  Text(
                    loc.t('branch_of_establishment') ?? 'Филиал какого заведения?',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (_loadingEstablishments)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    ))
                  else
                    DropdownButtonFormField<Establishment>(
                      value: _selectedParent,
                      decoration: InputDecoration(
                        labelText: loc.t('main_establishment') ?? 'Основное заведение',
                        prefixIcon: const Icon(Icons.store),
                        border: const OutlineInputBorder(),
                      ),
                      items: _mainEstablishments
                          .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (e) => setState(() => _selectedParent = e),
                      validator: (v) => _type == _EstablishmentType.branch && v == null
                          ? (loc.t('select_main_establishment') ?? 'Выберите основное заведение')
                          : null,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    loc.t('branch_sync_hint') ?? 'Номенклатура и ТТК будут синхронизироваться с основным заведением.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
                  validator: (v) => _type == _EstablishmentType.newEst && v == null ? loc.t('country_required') : null,
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
