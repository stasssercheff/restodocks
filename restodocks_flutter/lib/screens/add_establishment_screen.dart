import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/public_app_origin.dart';
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

enum _EstablishmentType { newEst, branch, copy }

class _AddEstablishmentScreenState extends State<AddEstablishmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinSourceController = TextEditingController();
  final _pinTargetController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  CountryItem? _selectedCountry;
  _EstablishmentType _type = _EstablishmentType.newEst;
  Establishment? _selectedParent;
  Establishment? _cloneSource;
  Establishment? _cloneTarget;
  List<Establishment> _mainEstablishments = [];
  List<Establishment> _ownerEstablishments = [];
  bool _loadingEstablishments = true;
  bool _optNomenclature = true;
  bool _optTechCards = true;
  bool _optOrderLists = false;

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
        _ownerEstablishments = all;
        _mainEstablishments = all.where((e) => e.isMain).toList();
        _loadingEstablishments = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinSourceController.dispose();
    _pinTargetController.dispose();
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

  Future<void> _requestCloneEmail() async {
    final loc = context.read<LocalizationService>();
    if (_cloneSource == null || _cloneTarget == null) {
      setState(() => _errorMessage = loc.t('clone_validation_select_both'));
      return;
    }
    if (_cloneSource!.id == _cloneTarget!.id) {
      setState(() => _errorMessage = loc.t('clone_validation_select_both'));
      return;
    }
    final ps = _pinSourceController.text.trim();
    final pt = _pinTargetController.text.trim();
    if (ps.isEmpty || pt.isEmpty) {
      setState(() => _errorMessage = loc.t('clone_validation_pins'));
      return;
    }
    if (!_optNomenclature && !_optTechCards && !_optOrderLists) {
      setState(() => _errorMessage = loc.t('clone_validation_options'));
      return;
    }

    final email = Supabase.instance.client.auth.currentUser?.email ??
        context.read<AccountManagerSupabase>().currentEmployee?.email;
    if (email == null || email.isEmpty) {
      setState(() => _errorMessage = loc.t('error'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final accountManager = context.read<AccountManagerSupabase>();
      final result = await accountManager.requestEstablishmentDataClone(
        sourceEstablishmentId: _cloneSource!.id,
        targetEstablishmentId: _cloneTarget!.id,
        sourcePin: ps,
        targetPin: pt,
        copyNomenclature: _optNomenclature,
        copyTechCards: _optTechCards,
        copyOrderLists: _optOrderLists,
      );
      final token = result['token'] as String?;
      if (token == null || token.isEmpty) throw Exception('no_token');

      final origin = publicAppOrigin;
      final link =
          '$origin/confirm-establishment-clone?token=${Uri.encodeComponent(token)}';
      final html = loc.t('clone_email_html', args: {'link': link}) ?? '';

      await accountManager.sendEstablishmentCloneConfirmationEmail(
        to: email,
        subject: loc.t('clone_email_subject') ?? 'Restodocks',
        htmlBody: html,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('clone_email_sent') ?? '')),
      );
      context.pop();
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
                  _type == _EstablishmentType.copy
                      ? (loc.t('establishment_copy_hint') ??
                          '')
                      : (loc.t('add_establishment_hint') ??
                          'Добавьте ещё одно заведение к вашему аккаунту. Владелец уже зарегистрирован.'),
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
                    ButtonSegment(
                      value: _EstablishmentType.copy,
                      label: Text(loc.t('establishment_copy_short') ?? 'Копирование'),
                      icon: const Icon(Icons.copy_all_outlined),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() {
                    _type = s.first;
                    if (_type == _EstablishmentType.newEst) _selectedParent = null;
                    _errorMessage = null;
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
                if (_type == _EstablishmentType.copy) ...[
                  const SizedBox(height: 16),
                  if (_loadingEstablishments)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    ))
                  else ...[
                    DropdownButtonFormField<Establishment>(
                      value: _cloneSource,
                      decoration: InputDecoration(
                        labelText: loc.t('clone_source') ?? 'Откуда',
                        prefixIcon: const Icon(Icons.outbox_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      items: _ownerEstablishments
                          .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (e) => setState(() {
                        _cloneSource = e;
                        if (_cloneTarget?.id == e?.id) _cloneTarget = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Establishment>(
                      value: _cloneTarget,
                      decoration: InputDecoration(
                        labelText: loc.t('clone_target') ?? 'Куда',
                        prefixIcon: const Icon(Icons.move_to_inbox_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      items: _ownerEstablishments
                          .where((e) => e.id != _cloneSource?.id)
                          .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (e) => setState(() => _cloneTarget = e),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pinSourceController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: loc.t('clone_pin_source'),
                        prefixIcon: const Icon(Icons.pin_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pinTargetController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: loc.t('clone_pin_target'),
                        prefixIcon: const Icon(Icons.pin_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: _optNomenclature,
                      onChanged: (v) => setState(() => _optNomenclature = v ?? true),
                      title: Text(loc.t('clone_opt_nomenclature') ?? ''),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: _optTechCards,
                      onChanged: (v) => setState(() => _optTechCards = v ?? true),
                      title: Text(loc.t('clone_opt_tech_cards') ?? ''),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: _optOrderLists,
                      onChanged: (v) => setState(() => _optOrderLists = v ?? false),
                      title: Text(loc.t('clone_opt_order_lists') ?? ''),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ],
                if (_type != _EstablishmentType.copy) ...[
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
                ],
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
                  onPressed: _isLoading
                      ? null
                      : (_type == _EstablishmentType.copy ? _requestCloneEmail : _addEstablishment),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _type == _EstablishmentType.copy
                              ? (loc.t('clone_send_email') ?? 'Отправить ссылку')
                              : (loc.t('add_establishment') ?? 'Добавить заведение'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
