import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/models.dart';
import '../services/haccp_agreement_pdf_service.dart';
import '../services/haccp_order_pdf_service.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

class HaccpDocumentationScreen extends StatefulWidget {
  const HaccpDocumentationScreen({super.key});

  @override
  State<HaccpDocumentationScreen> createState() =>
      _HaccpDocumentationScreenState();
}

class _HaccpDocumentationScreenState extends State<HaccpDocumentationScreen> {
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

      final roleCode =
          emp.positionRole ?? (emp.roles.contains('owner') ? 'owner' : null);
      final employerPosition = roleCode != null
          ? (loc.tForLanguage(pickedLang, 'role_$roleCode'))
          : null;

      final bytes = await HaccpAgreementPdfService.buildAgreementPdfBytes(
        establishment: est,
        employerEmployee: emp,
        organizationLabel: loc.tForLanguage(pickedLang, 'haccp_agreement_org'),
        innBinLabel: loc.tForLanguage(pickedLang, 'haccp_agreement_inn_bin'),
        addressLabel: loc.tForLanguage(pickedLang, 'haccp_agreement_address'),
        documentTitle:
            loc.tForLanguage(pickedLang, 'haccp_agreement_doc_title'),
        documentSubtitle:
            loc.tForLanguage(pickedLang, 'haccp_agreement_doc_subtitle'),
        agreementHeading:
            loc.tForLanguage(pickedLang, 'haccp_agreement_heading'),
        workerLabel: loc.tForLanguage(pickedLang, 'haccp_agreement_worker'),
        workerFioHint:
            loc.tForLanguage(pickedLang, 'haccp_agreement_worker_fio_hint'),
        positionLabel: loc.tForLanguage(pickedLang, 'haccp_agreement_position'),
        dateLine: loc.tForLanguage(pickedLang, 'haccp_agreement_date_line'),
        employerLabel: loc.tForLanguage(pickedLang, 'haccp_agreement_employer'),
        stampHint: loc.tForLanguage(pickedLang, 'haccp_agreement_stamp_hint'),
        workerSignLabel:
            loc.tForLanguage(pickedLang, 'haccp_agreement_worker_sign'),
        agreementBody: loc.tForLanguage(pickedLang, 'haccp_agreement_body'),
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

  Future<void> _downloadHaccpOrder(
      BuildContext context, LocalizationService loc) async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;

    final employees = await account.getEmployeesForEstablishment(est.id);
    if (context.mounted == false) return;

    final thirdPageMode = await showDialog<HaccpOrderThirdPageModeAndSelection>(
      context: context,
      builder: (ctx) {
        HaccpOrderThirdPageMode mode = HaccpOrderThirdPageMode.empty;
        final selectedIds = employees.map((e) => e.id).toSet();

        return StatefulBuilder(
          builder: (ctx2, setState) {
            bool filled = mode == HaccpOrderThirdPageMode.filled;
            return AlertDialog(
              title: Text('Приказ и приложение (печать)'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<HaccpOrderThirdPageMode>(
                      value: HaccpOrderThirdPageMode.empty,
                      groupValue: mode,
                      title: const Text('Пустой бланк (заполнение вручную)'),
                      onChanged: (v) => setState(
                          () => mode = v ?? HaccpOrderThirdPageMode.empty),
                    ),
                    RadioListTile<HaccpOrderThirdPageMode>(
                      value: HaccpOrderThirdPageMode.filled,
                      groupValue: mode,
                      title: const Text(
                          'Заполненный бланк (ФИО/должности автоматически)'),
                      onChanged: (v) => setState(
                          () => mode = v ?? HaccpOrderThirdPageMode.filled),
                    ),
                    if (filled) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Выберите сотрудников для листа ознакомления:',
                        style: Theme.of(ctx2).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 260,
                        width: 360,
                        child: ListView.builder(
                          itemCount: employees.length,
                          itemBuilder: (ctx3, i) {
                            final e = employees[i];
                            final checked = selectedIds.contains(e.id);
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(e.fullName.trim().isNotEmpty
                                  ? '${e.fullName}${e.surname != null && e.surname!.trim().isNotEmpty ? ' ${e.surname}' : ''}'
                                  : e.id),
                              subtitle: Text(
                                  e.positionRole ??
                                      (e.hasRole('owner')
                                          ? (est.directorPosition ?? '')
                                          : ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              value: checked,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true)
                                    selectedIds.add(e.id);
                                  else
                                    selectedIds.remove(e.id);
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              selectedIds
                                ..clear()
                                ..addAll(employees.map((e) => e.id));
                            }),
                            child: const Text('Выбрать всех'),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => selectedIds.clear()),
                            child: const Text('Очистить'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx2).pop(),
                  child: Text(MaterialLocalizations.of(ctx2).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () async {
                    final selected = employees
                        .where((e) => selectedIds.contains(e.id))
                        .toList();
                    Navigator.of(ctx2).pop(
                      HaccpOrderThirdPageModeAndSelection(
                          mode: mode, selectedEmployees: selected),
                    );
                  },
                  child: Text(loc.t('download') ?? 'Скачать'),
                ),
              ],
            );
          },
        );
      },
    );

    if (thirdPageMode == null || !context.mounted) return;
    try {
      final bytes = await HaccpOrderPdfService.buildOrderPdfBytes(
        establishment: est,
        thirdPageMode: thirdPageMode.mode,
        selectedEmployees: thirdPageMode.selectedEmployees,
      );
      await saveFileBytes('haccp_order.pdf', bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t('haccp_agreement_saved') ?? 'PDF saved')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${loc.t('error')}: $e')));
      }
    }
  }

  bool _canSeeLegalDocs(Employee emp) {
    return emp.hasRole('owner') ||
        emp.department == 'management' ||
        emp.hasRole('executive_chef') ||
        emp.hasRole('sous_chef') ||
        emp.hasRole('bar_manager') ||
        emp.hasRole('floor_manager') ||
        emp.hasRole('general_manager');
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final emp = account.currentEmployee;

    if (emp == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_canSeeLegalDocs(emp)) {
      return Scaffold(
        appBar: AppBar(
            leading: appBarBackButton(context),
            title: Text(loc.t('documentation') ?? 'Документация')),
        body: Center(child: Text(loc.t('access_denied') ?? 'Доступ запрещен')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('documentation') ?? 'Документация'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (emp.hasRole('owner') && account.establishment != null)
              ExpansionTile(
                initiallyExpanded: false,
                leading: const Icon(Icons.business),
                title: Text(loc.t('requisites') ?? 'Реквизиты'),
                subtitle: Text(
                  loc.t('requisites_hint') ?? 'Для бланков и приказов',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [
                  _RequisitesForm(
                    establishment: account.establishment!,
                    onSave: (e) async {
                      await context
                          .read<AccountManagerSupabase>()
                          .updateEstablishment(e);
                      if (mounted) setState(() {});
                    },
                    loc: loc,
                  ),
                ],
              ),
            ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.rule_outlined),
              title: Text(loc.t('haccp_legal_legitimacy') ??
                  'Юридическая легитимность'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    loc.t('haccp_legal_text') ??
                        'Легитимность цифровых журналов: допускается ведение производственных журналов в электронном виде...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.document_scanner_outlined),
              title:
                  Text(loc.t('haccp_legal_sp_extract') ?? 'Извлечение из СП'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    loc.t('haccp_legal_sp_paragraphs') ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(loc.t('public_offer')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/legal/offer'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(loc.t('privacy_policy')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/legal/privacy'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _downloadHaccpAgreement(context, loc),
              icon: const Icon(Icons.download),
              label: Text(loc.t('haccp_download_agreement') ??
                  'Скачать Соглашение с сотрудником'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _downloadHaccpOrder(context, loc),
              icon: const Icon(Icons.download),
              label: const Text('Скачать приказ (3 страницы)'),
            ),
            const SizedBox(height: 8),
            Text(
              'После скачивания PDF распечатайте и заполните вручную там, где стоят линии.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class HaccpOrderThirdPageModeAndSelection {
  final HaccpOrderThirdPageMode mode;
  final List<Employee> selectedEmployees;

  const HaccpOrderThirdPageModeAndSelection({
    required this.mode,
    required this.selectedEmployees,
  });
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
