import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/establishment_fiscal_settings.dart';
import '../../services/services.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../widgets/app_bar_home_button.dart';

/// Настройки налоговой зоны и режима цен (пресеты + переопределения).
class FiscalTaxSettingsScreen extends StatefulWidget {
  const FiscalTaxSettingsScreen({super.key});

  @override
  State<FiscalTaxSettingsScreen> createState() =>
      _FiscalTaxSettingsScreenState();
}

class _FiscalTaxSettingsScreenState extends State<FiscalTaxSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _presetVersion;
  List<String> _regionCodes = [];
  String _region = 'RU';
  String _mode = 'tax_included';
  final _vatOverride = TextEditingController();
  final _sectionId = TextEditingController();
  int _pendingOutbox = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _vatOverride.dispose();
    _sectionId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    final loc = context.read<LocalizationService>();
    if (est == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      await FiscalTaxPresetsService.instance.ensureLoaded();
      final codes = await FiscalTaxPresetsService.instance.regionCodes();
      final row =
          await EstablishmentFiscalSettingsService.instance.fetch(est.id);
      final pending = await PosFiscalService.instance.pendingOutboxCount(est.id);
      if (!mounted) return;
      setState(() {
        _presetVersion = FiscalTaxPresetsService.instance.version;
        _regionCodes = codes;
        if (row != null) {
          _region = row.taxRegion;
          _mode = row.priceTaxMode;
          _vatOverride.text = row.vatOverridePercent != null
              ? _trimNum(row.vatOverridePercent!)
              : '';
          _sectionId.text = row.fiscalSectionId ?? '';
        } else {
          _region = 'RU';
          _mode = 'tax_included';
        }
        _pendingOutbox = pending;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('error')}: $e')),
      );
    }
  }

  String _trimNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _regionTitle(LocalizationService loc, String code) {
    final key = 'fiscal_region_${code.toLowerCase()}';
    final t = loc.t(key);
    if (t != key) return t;
    return code;
  }

  Future<void> _save(LocalizationService loc) async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;
    final vatRaw = _vatOverride.text.replaceAll(',', '.').trim();
    double? vatOverride;
    if (vatRaw.isNotEmpty) {
      vatOverride = double.tryParse(vatRaw);
      if (vatOverride == null || vatOverride < 0 || vatOverride > 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('fiscal_vat_invalid'))),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final s = EstablishmentFiscalSettings(
        establishmentId: est.id,
        taxRegion: _region,
        priceTaxMode: _mode,
        vatOverridePercent: vatOverride,
        fiscalSectionId:
            _sectionId.text.trim().isEmpty ? null : _sectionId.text.trim(),
        updatedAt: DateTime.now().toUtc(),
      );
      await EstablishmentFiscalSettingsService.instance.upsert(s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('fiscal_settings_saved'))),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('error')}: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final allowed = posCanManageFiscalTaxSettings(emp);

    return Scaffold(
      appBar: AppBar(
        leading: shellReturnLeading(context) ?? appBarBackButton(context),
        title: Text(loc.t('fiscal_settings_title')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !allowed
              ? Center(child: Text(loc.t('fiscal_access_denied')))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      loc.t('fiscal_settings_subtitle'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    if (_presetVersion != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        loc.t('fiscal_presets_version', args: {'v': _presetVersion!}),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      loc.t('fiscal_pending_outbox', args: {'n': '$_pendingOutbox'}),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text(loc.t('fiscal_outbox_title')),
                      subtitle: Text(loc.t('fiscal_outbox_list_subtitle')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/fiscal-outbox'),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: _regionCodes.contains(_region) ? _region : 'RU',
                      decoration: InputDecoration(
                        labelText: loc.t('fiscal_region_label'),
                      ),
                      items: _regionCodes
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(_regionTitle(loc, c)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _region = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _mode,
                      decoration: InputDecoration(
                        labelText: loc.t('fiscal_price_mode_label'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'tax_included',
                          child: Text(loc.t('fiscal_price_mode_included')),
                        ),
                        DropdownMenuItem(
                          value: 'tax_excluded',
                          child: Text(loc.t('fiscal_price_mode_excluded')),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _mode = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _vatOverride,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: loc.t('fiscal_vat_override_label'),
                        hintText: loc.t('fiscal_vat_override_hint'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _sectionId,
                      decoration: InputDecoration(
                        labelText: loc.t('fiscal_section_id_label'),
                        hintText: loc.t('fiscal_section_id_hint'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : () => _save(loc),
                      child: Text(loc.t('fiscal_save')),
                    ),
                  ],
                ),
    );
  }
}
