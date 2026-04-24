import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/config/roles_config.dart';
import '../haccp/haccp_country_profile.dart';
import '../models/employee.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import '../models/product.dart';
import '../models/tech_card.dart';
import '../services/services.dart';
import '../utils/employee_display_utils.dart';
import '../widgets/app_bar_home_button.dart';

/// Одна строка формы гигиенического журнала (сотрудник + должность + допуск).
class _HealthHygieneRow {
  _HealthHygieneRow({
    required this.employeeId,
    this.positionOverride,
    this.positionIsCustom = false,
    this.statusOk = true,
    this.status2Ok = true,
  });
  final String employeeId;
  String? positionOverride;
  bool positionIsCustom;
  bool statusOk;
  bool status2Ok;
}

class _FinishedBrakerageChoice {
  const _FinishedBrakerageChoice({
    required this.displayName,
    required this.searchTokens,
    required this.typeLabel,
    this.techCardId,
    this.productName,
  });

  final String displayName;
  final String searchTokens;
  final String typeLabel;
  final String? techCardId;
  final String? productName;
}

/// Форма добавления записи в журнал ХАССП.
/// Только 5 журналов по СанПиН 2.3/2.4.3590-20, макет как в рекомендуемых образцах.
class HaccpEntryFormScreen extends StatefulWidget {
  const HaccpEntryFormScreen({super.key, required this.logTypeCode});

  final String logTypeCode;

  @override
  State<HaccpEntryFormScreen> createState() => _HaccpEntryFormScreenState();
}

class _HaccpEntryFormScreenState extends State<HaccpEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  double _tempValue = 4.0;
  double _humidityValue = 60;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  DateTime? _expiryDate;
  DateTime? _dateSold;

  /// Разрешение к реализации: true = разрешено, false = запрещено, null = не выбрано.
  bool? _approvalToSell;

  /// Журнал медкнижек: даты.
  DateTime? _medBookValidUntil;
  DateTime? _medBookIssuedAt;
  DateTime? _medBookReturnedAt;

  /// Мобильные блоки (алиасы для совместимости с полями).
  String? _medBookEmployeeId;
  String? _medExamEmployeeId;
  DateTime? get _medBookExpiryDate => _medBookValidUntil;
  set _medBookExpiryDate(DateTime? v) => _medBookValidUntil = v;
  DateTime? get _medBookReceivedDate => _medBookIssuedAt;
  set _medBookReceivedDate(DateTime? v) => _medBookIssuedAt = v;
  DateTime? get _medBookReturnedDate => _medBookReturnedAt;
  set _medBookReturnedDate(DateTime? v) => _medBookReturnedAt = v;

  /// Медосмотры, дезсредства, генуборки, сита.
  DateTime? _medExamHireDate;
  DateTime? _medExamDate;
  DateTime? _medExamNextDate;
  DateTime? _medExamExclusionDate;
  DateTime? _disinfReceiptDate;
  DateTime? _disinfExpiryDate;
  DateTime? _genCleanDate;
  DateTime? _sieveCleaningDate;

  DateTime? get _generalCleaningDate => _genCleanDate;
  set _generalCleaningDate(DateTime? v) => _genCleanDate = v;
  DateTime? get _sieveDate => _sieveCleaningDate;
  set _sieveDate(DateTime? v) => _sieveCleaningDate = v;

  /// Гигиенический журнал: список сотрудников заведения и строки таблицы (каждая — один сотрудник).
  List<Employee> _healthEmployees = [];
  List<_HealthHygieneRow> _healthRows = [];

  /// Журнал бракеража готовой продукции: ТТК для выбора блюда.
  List<TechCard> _finishedBrakerageTechCards = [];
  List<Product> _finishedBrakerageProducts = [];
  String? _selectedFinishedBrakerageTechCardId;
  final HaccpFormPresetService _presetService = HaccpFormPresetService();

  /// Сохранённые варианты по ключу поля формы (хранение в SharedPreferences под ключом logType:field).
  final Map<String, List<String>> _presetOptions = {};

  /// Сотрудники заведения для форм медкнижек, медосмотров и полей «ответственный»/«подпись».
  List<Employee> _formEmployees = [];

  HaccpLogType? get _logType {
    final t = HaccpLogType.fromCode(widget.logTypeCode);
    return t != null && HaccpLogType.supportedInApp.contains(t) ? t : null;
  }

  String _activeCountryCode() {
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return 'RU';
    return context.read<HaccpConfigService>().resolveCountryCodeForEstablishment(
          est,
        );
  }

  String _datePatternForCountry() {
    return HaccpCountryProfiles.datePatternForCountry(_activeCountryCode());
  }

  String _formatDate(DateTime value) =>
      DateFormat(_datePatternForCountry()).format(value);
  String _formatDateTime(DateTime value) =>
      DateFormat('${_datePatternForCountry()} HH:mm').format(value);
  String _formatTime(DateTime value) => DateFormat('HH:mm').format(value);
  String _logTypeTitle(HaccpLogType type, LocalizationService loc) =>
      HaccpCountryProfiles.resolveLogTypeTitle(
        logType: type,
        languageCode: loc.currentLanguageCode,
        localizedValue: loc.t(type.displayNameKey),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final est = context.read<AccountManagerSupabase>().establishment;
      if (est != null) {
        context.read<HaccpConfigService>().load(est.id, notify: false);
      }
    });
    if (_logType == HaccpLogType.healthHygiene) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadHealthEmployees());
    } else if (_logType == HaccpLogType.finishedProductBrakerage) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadFinishedBrakerageChoices());
    } else if (_logType == HaccpLogType.medBookRegistry ||
        _logType == HaccpLogType.medExaminations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFormEmployees());
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadSavedFieldOptions());
  }

  String _presetStorageKey(String fieldKey) =>
      '${_logType?.code ?? 'unknown'}:$fieldKey';

  List<String> _presetFieldsForCurrentLog() {
    switch (_logType) {
      case HaccpLogType.fridgeTemperature:
        return const ['equipment'];
      case HaccpLogType.warehouseTempHumidity:
        return const ['warehouse_premises'];
      case HaccpLogType.equipmentWashing:
        return const [
          'wash_equipment_name',
          'wash_solution_name',
          'wash_disinfectant_name',
        ];
      case HaccpLogType.generalCleaningSchedule:
        return const ['gen_clean_premises'];
      case HaccpLogType.sieveFilterMagnet:
        return const ['sieve_name_location', 'sieve_condition'];
      case HaccpLogType.fryingOil:
        return const [
          'oil_name',
          'frying_equipment_type',
          'frying_product_type'
        ];
      case HaccpLogType.incomingRawBrakerage:
        return const [
          'manufacturer_supplier',
          'storage_conditions',
          'packaging'
        ];
      case HaccpLogType.disinfectantAccounting:
        return const [
          'disinf_object_name',
          'disinf_treatment_type',
          'disinf_agent_name',
          'disinf_agent_name_receipt',
        ];
      default:
        return const [];
    }
  }

  static List<String> _mergeUniqueOptions(
      Iterable<String> a, Iterable<String> b) {
    final map = <String, String>{};
    for (final raw in [...a, ...b]) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      map.putIfAbsent(t.toLowerCase(), () => t);
    }
    final out = map.values.toList()
      ..sort((x, y) => x.toLowerCase().compareTo(y.toLowerCase()));
    return out;
  }

  Future<void> _loadFormEmployees() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) return;
    try {
      final list = await acc.getEmployeesForEstablishment(est.id);
      if (mounted)
        setState(() => _formEmployees = list.where((e) => e.isActive).toList());
    } catch (_) {}
  }

  Future<void> _loadHealthEmployees() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final current = acc.currentEmployee;
    if (est == null || current == null) return;
    try {
      final list = await acc.getEmployeesForEstablishment(est.id);
      if (mounted) {
        setState(() {
          _healthEmployees = list.where((e) => e.isActive).toList();
          if (_healthRows.isEmpty && _healthEmployees.isNotEmpty) {
            _healthRows = _healthEmployees
                .map((e) => _HealthHygieneRow(
                      employeeId: e.id,
                      positionOverride: null,
                      positionIsCustom: false,
                      statusOk: true,
                      status2Ok: true,
                    ))
                .toList();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSavedFieldOptions() async {
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null) return;
    try {
      final fields = _presetFieldsForCurrentLog();
      if (fields.isEmpty) return;
      final Map<String, List<String>> next = {};
      for (final f in fields) {
        final scoped = _presetStorageKey(f);
        var list = await _presetService.getOptions(
          establishmentId: est.id,
          fieldKey: scoped,
        );
        // Миграция со старых ключей (до разделения по журналам)
        if (_logType == HaccpLogType.fridgeTemperature && f == 'equipment') {
          final legacy = await _presetService.getOptions(
            establishmentId: est.id,
            fieldKey: 'fridge_equipment',
          );
          list = _mergeUniqueOptions(list, legacy);
        }
        if (_logType == HaccpLogType.warehouseTempHumidity &&
            f == 'warehouse_premises') {
          final legacy = await _presetService.getOptions(
            establishmentId: est.id,
            fieldKey: 'warehouse_premises',
          );
          list = _mergeUniqueOptions(list, legacy);
        }
        next[f] = list;
      }
      if (!mounted) return;
      setState(() {
        _presetOptions
          ..clear()
          ..addAll(next);
      });
    } catch (_) {}
  }

  Future<void> _saveCurrentOption({
    required String controllerKey,
    required String fieldKey,
    bool showFeedback = false,
  }) async {
    final est = context.read<AccountManagerSupabase>().establishment;
    final value = _getText(controllerKey);
    if (est == null || value.isEmpty) return;
    final storageKey = _presetStorageKey(fieldKey);
    final updated = await _presetService.addOption(
      establishmentId: est.id,
      fieldKey: storageKey,
      value: value,
    );
    if (!mounted) return;
    setState(() => _presetOptions[fieldKey] = updated);
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Вариант сохранён — выберите его из списка (стрелка) при следующей записи'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadFinishedBrakerageChoices() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    final dataEstId = est?.dataEstablishmentId;
    if (dataEstId == null || est == null) return;
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final store = context.read<ProductStoreSupabase>();
      final all = await svc.getTechCardsForEstablishment(dataEstId);
      await store.loadNomenclature(est.id);
      final visible = emp == null
          ? all
          : all.where((tc) => emp.canSeeTechCard(tc.sections)).toList();
      final products = List<Product>.from(store.getProducts());
      if (!mounted) return;
      setState(() {
        _finishedBrakerageTechCards = visible;
        _finishedBrakerageProducts = products;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  String _getText(String key) => _controllers[key]?.text.trim() ?? '';

  void _setText(String key, String value) {
    _controllers[key] ??= TextEditingController();
    _controllers[key]!.text = value;
  }

  double? _getNum(String key) {
    final s = _getText(key);
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  /// Выбор сотрудника для мобильных форм (медкнижки/медосмотры).
  Widget _employeePickerField(
    String key,
    String label,
    String? currentId,
    void Function(String?) onIdChanged,
    LocalizationService loc,
    bool showNameTranslit,
  ) {
    if (_formEmployees.isEmpty) {
      return const SizedBox.shrink();
    }
    final selected = _formEmployees.where((e) => e.id == currentId).firstOrNull;
    return DropdownButtonFormField<Employee?>(
      value: selected,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: _formEmployees
          .map((e) => DropdownMenuItem<Employee?>(
                value: e,
                child: Text(
                  displayStoredPersonName(
                    employeeFullNameRaw(e),
                    loc,
                    showNameTranslit: showNameTranslit,
                  ),
                ),
              ))
          .toList(),
      onChanged: (e) {
        onIdChanged(e?.id);
        // Дублируем ID в контроллер, чтобы сохранить в payload, даже если отдельные state-поля не используются.
        _setText(key, e?.id ?? '');
      },
    );
  }

  /// Выбор даты для мобильных форм.
  Widget _datePickerField(
    String key,
    String label,
    DateTime? value,
    void Function(DateTime?) onChanged,
  ) {
    final loc = context.read<LocalizationService>();
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        onChanged(d);
        if (d != null) _setText(key, d.toIso8601String());
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(value != null
            ? _formatDate(value)
            : _th(loc, 'haccp_pick_date_short', 'Выбрать')),
      ),
    );
  }

  Widget _tableHeaderCell(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );

  /// Локализованный заголовок таблицы; при отсутствии ключа — [fallback].
  String _th(LocalizationService loc, String key, String fallback) {
    final v = loc.t(key);
    return v == key ? fallback : v;
  }

  Widget _tableCell(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: child,
      );

  Widget _textField(String key, String label,
      {bool multiline = false, TextInputType? keyboardType}) {
    _controllers[key] ??= TextEditingController();
    return TextFormField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      maxLines: multiline ? 2 : 1,
      keyboardType: keyboardType,
    );
  }

  Future<String?> _showSavedOptionsPicker({
    required String title,
    required List<String> options,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: options.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Пока нет сохранённых вариантов.\nВведите текст в поле и нажмите «в список» (иконка с плюсом).',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  ...options.map((option) => ListTile(
                        title: Text(option),
                        onTap: () => Navigator.of(ctx).pop(option),
                      )),
                ],
              ),
      ),
    );
  }

  Widget _savedOptionTextField({
    required String key,
    required String label,
    required List<String> options,
    required String presetFieldKey,
    String? hintText,
    String? Function(String?)? validator,
    bool showHelperUnderField = false,
  }) {
    final loc = context.read<LocalizationService>();
    _controllers[key] ??= TextEditingController();
    return TextFormField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: showHelperUnderField
            ? loc.t('haccp_field_helper_plus_or_arrow')
            : null,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 96, minHeight: 40),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: loc.t('haccp_tooltip_save_to_journal_list'),
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _saveCurrentOption(
                controllerKey: key,
                fieldKey: presetFieldKey,
                showFeedback: true,
              ),
            ),
            IconButton(
              tooltip: loc.t('haccp_tooltip_pick_from_saved'),
              icon: const Icon(Icons.arrow_drop_down_circle_outlined),
              onPressed: () async {
                final picked = await _showSavedOptionsPicker(
                  title: label,
                  options: options,
                );
                if (picked == null) return;
                setState(() => _setText(key, picked));
              },
            ),
          ],
        ),
      ),
      validator: validator,
    );
  }

  String _finishedBrakerageTypeLabel(LocalizationService loc,
      {required bool isProduct, required bool isSemiFinished}) {
    if (isProduct) return loc.t('products');
    if (isSemiFinished) return loc.t('ttk_pf');
    return loc.t('ttk_dish');
  }

  List<_FinishedBrakerageChoice> _buildFinishedBrakerageChoices(
      LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    final choices = <_FinishedBrakerageChoice>[
      ..._finishedBrakerageProducts.map((product) {
        final label = product.getLocalizedName(lang);
        return _FinishedBrakerageChoice(
          displayName: label,
          searchTokens: '$label ${product.name} ${product.category}',
          typeLabel: _finishedBrakerageTypeLabel(loc,
              isProduct: true, isSemiFinished: false),
          productName: label,
        );
      }),
      ..._finishedBrakerageTechCards.map((tc) {
        final label = tc.getDisplayNameInLists(lang);
        return _FinishedBrakerageChoice(
          displayName: label,
          searchTokens: '$label ${tc.dishName} ${tc.category}',
          typeLabel: _finishedBrakerageTypeLabel(loc,
              isProduct: false, isSemiFinished: tc.isSemiFinished),
          techCardId: tc.id,
          productName: label,
        );
      }),
    ];
    choices.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return choices;
  }

  /// Селектор «Разрешение к реализации»: разрешено / запрещено.
  Widget _approvalSelector() {
    final loc = context.read<LocalizationService>();
    return DropdownButtonFormField<bool>(
      value: _approvalToSell,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      hint: Text(loc.t('haccp_approval_hint')),
      items: [
        DropdownMenuItem(
            value: true, child: Text(loc.t('haccp_approval_allowed'))),
        DropdownMenuItem(
            value: false, child: Text(loc.t('haccp_approval_denied'))),
      ],
      onChanged: (v) => setState(() => _approvalToSell = v),
    );
  }

  /// Выпадающий список выбора сотрудника (подставляет ФИО/должность в форму).
  Widget _employeeSelectorDropdown({
    required LocalizationService loc,
    required List<Employee> employees,
    required String label,
    required void Function(Employee?) onSelected,
    required bool showNameTranslit,
  }) {
    if (employees.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<Employee?>(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      value: null,
      items: [
        DropdownMenuItem<Employee?>(
            value: null, child: Text(loc.t('haccp_select_from_list'))),
        ...employees.map((e) => DropdownMenuItem<Employee?>(
              value: e,
              child: Text(
                '${displayStoredPersonName(employeeFullNameRaw(e), loc, showNameTranslit: showNameTranslit)} (${e.roles.isNotEmpty ? loc.roleDisplayName(e.roles.first) : ''})',
              ),
            )),
      ],
      onChanged: (e) => onSelected(e),
    );
  }

  /// Подпись — ФИО сотрудника из учётной записи (только отображение).
  Widget _signatureFromAccount() {
    return Consumer3<AccountManagerSupabase, LocalizationService,
        ScreenLayoutPreferenceService>(
      builder: (_, acc, loc, layout, __) {
        final emp = acc.currentEmployee;
        final name = emp != null
            ? displayStoredPersonName(
                employeeFullNameRaw(emp),
                loc,
                showNameTranslit: layout.showNameTranslit,
              )
            : '—';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(name, style: const TextStyle(fontSize: 13)),
        );
      },
    );
  }

  static const String _customPositionValue = '__custom_position__';

  /// Коды должностей: все роли из RolesConfig + роли из карточек сотрудников.
  List<String> _healthPositionRoleCodes(LocalizationService loc) {
    final codes = <String>{
      // Все роли из RolesConfig
      for (final section in RolesConfig.kitchen.values)
        for (final role in section) role.roleCode,
      for (final role in RolesConfig.bar) role.roleCode,
      for (final role in RolesConfig.hall) role.roleCode,
      for (final role in RolesConfig.management) role.roleCode,
      // Дополнительные роли менеджмента
      'general_manager',
      'bar_manager',
      // Роли из карточек сотрудников (на случай кастомных)
      for (final e in _healthEmployees)
        for (final role in e.roles) role,
    };
    final list = codes.toList()
      ..sort((a, b) => loc
          .roleDisplayName(a)
          .toLowerCase()
          .compareTo(loc.roleDisplayName(b).toLowerCase()));
    return list;
  }

  Employee? _healthEmployeeById(String id) => _healthEmployees
      .cast<Employee?>()
      .firstWhere((e) => e?.id == id, orElse: () => null);

  Widget _healthPositionDropdownForRow(int index, LocalizationService loc) {
    final row = _healthRows[index];
    final codes = _healthPositionRoleCodes(loc);
    final String effectiveValue;
    if (row.positionIsCustom) {
      effectiveValue = _customPositionValue;
    } else {
      final o = (row.positionOverride ?? '').trim();
      if (o.isNotEmpty && codes.contains(o)) {
        effectiveValue = o;
      } else {
        final emp = _healthEmployeeById(row.employeeId);
        final c = emp != null && emp.roles.isNotEmpty ? emp.roles.first : null;
        effectiveValue = (c != null && codes.contains(c))
            ? c
            : (codes.isNotEmpty ? codes.first : _customPositionValue);
      }
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: effectiveValue,
        isExpanded: true,
        isDense: true,
        items: [
          ...codes.map(
            (code) => DropdownMenuItem(
              value: code,
              child: Text(
                loc.roleDisplayName(code),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          DropdownMenuItem(
            value: _customPositionValue,
            child: Row(
              children: [
                Icon(Icons.add_circle_outline,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                    row.positionIsCustom &&
                            (row.positionOverride ?? '').isNotEmpty
                        ? 'Свой вариант: ${row.positionOverride}'
                        : 'Свой вариант',
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
        onChanged: (v) async {
          if (v == _customPositionValue) {
            final text =
                await _showCustomPositionDialog(initial: row.positionOverride);
            if (text != null && mounted) {
              setState(() {
                row.positionOverride = text;
                row.positionIsCustom = true;
              });
            }
            return;
          }
          if (v != null) {
            setState(() {
              row.positionOverride = v;
              row.positionIsCustom = false;
            });
          }
        },
      ),
    );
  }

  Future<String?> _showCustomPositionDialog({String? initial}) async {
    final loc = context.read<LocalizationService>();
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('haccp_position_custom_title')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: loc.t('haccp_position_custom_hint'),
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) => Navigator.of(ctx)
              .pop(ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }

  /// Выбор продукции/сырья для журнала бракеража готовой продукции:
  /// продукты из номенклатуры + ТТК ПФ + ТТК блюда.
  Widget _finishedProductPickerCell(LocalizationService loc) {
    _controllers['product'] ??= TextEditingController();
    final controller = _controllers['product']!;
    final title = controller.text.isNotEmpty
        ? controller.text
        : loc.t('haccp_product');
    return InkWell(
      onTap: () async {
        if (_finishedBrakerageTechCards.isEmpty &&
            _finishedBrakerageProducts.isEmpty) {
          await _loadFinishedBrakerageChoices();
        }
        final allChoices = _buildFinishedBrakerageChoices(loc);
        final picked = await showDialog<_FinishedBrakerageChoice?>(
          context: context,
          builder: (ctx) {
            final searchCtrl = TextEditingController();
            List<_FinishedBrakerageChoice> filtered = List.of(allChoices);
            void applyFilter() {
              final q = searchCtrl.text.trim().toLowerCase();
              filtered = q.isEmpty
                  ? List.of(allChoices)
                  : allChoices
                      .where(
                          (item) => item.searchTokens.toLowerCase().contains(q))
                      .toList();
            }

            applyFilter();
            return StatefulBuilder(
              builder: (ctx, setStateDialog) {
                return AlertDialog(
                  title: Text(loc.t('haccp_product')),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: searchCtrl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: loc.t('search'),
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            setStateDialog(() {
                              applyFilter();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: filtered.isEmpty
                              ? Text(loc.t('no_results'))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filtered.length,
                                  itemBuilder: (ctx, index) {
                                    final item = filtered[index];
                                    return ListTile(
                                      title: Text(item.displayName),
                                      subtitle: Text(item.typeLabel),
                                      onTap: () => Navigator.of(ctx).pop(item),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child:
                          Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (picked != null && mounted) {
          setState(() {
            controller.text = picked.productName ?? picked.displayName;
            _selectedFinishedBrakerageTechCardId = picked.techCardId;
          });
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: loc.t('haccp_product'),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  /// Форма по макету Приложения 1: Гигиенический журнал (сотрудники). Несколько строк — по одной на сотрудника; можно добавлять/удалять.
  Widget _buildHealthHygieneForm(
      LocalizationService loc, bool showNameTranslit) {
    final dateStr = _formatDate(DateTime.now());
    final currentEmp = context.watch<AccountManagerSupabase>().currentEmployee;
    final creatorName = currentEmp != null
        ? displayStoredPersonName(
            employeeFullNameRaw(currentEmp),
            loc,
            showNameTranslit: showNameTranslit,
          )
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(0.4),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1.8),
            5: FlexColumnWidth(1.8),
            6: FlexColumnWidth(1.2),
            7: FlexColumnWidth(1),
            8: FlexColumnWidth(0.35),
          },
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(
              children: [
                _tableHeaderCell(_th(loc, 'haccp_tbl_pp_no', '№ п/п')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_date', 'Дата')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_employee_fio_long',
                    'Ф. И. О. работника (последнее при наличии)')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_position', 'Должность')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_sign_family_infect',
                    'Подпись сотрудника об отсутствии признаков инфекционных заболеваний у сотрудника и членов семьи')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_sign_skin_resp',
                    'Подпись сотрудника об отсутствии заболеваний верхних дыхательных путей и гнойничковых заболеваний кожи рук и открытых поверхностей тела')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_exam_outcome',
                    'Результат осмотра медицинским работником (ответственным лицом) (допущен / отстранен)')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_med_worker_sign',
                    'Подпись медицинского работника (ответственного лица)')),
                _tableHeaderCell(''),
              ],
            ),
            ...List.generate(_healthRows.length, (i) {
              final row = _healthRows[i];
              final emp = _healthEmployeeById(row.employeeId);
              final name = emp != null
                  ? displayStoredPersonName(
                      employeeFullNameRaw(emp),
                      loc,
                      showNameTranslit: showNameTranslit,
                    )
                  : '—';
              return TableRow(
                children: [
                  _tableCell(Text('${i + 1}')),
                  _tableCell(Text(dateStr)),
                  _tableCell(Text(name)),
                  _tableCell(_healthPositionDropdownForRow(i, loc)),
                  _tableCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                          value: row.statusOk,
                          onChanged: (v) =>
                              setState(() => row.statusOk = v ?? true)),
                      Text(
                          row.statusOk
                              ? loc.t('answer_yes')
                              : loc.t('answer_no'),
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  row.statusOk ? Colors.green : Colors.orange)),
                    ],
                  )),
                  _tableCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                          value: row.status2Ok,
                          onChanged: (v) =>
                              setState(() => row.status2Ok = v ?? true)),
                      Text(
                          row.status2Ok
                              ? loc.t('answer_yes')
                              : loc.t('answer_no'),
                          style: TextStyle(
                              fontSize: 12,
                              color: row.status2Ok
                                  ? Colors.green
                                  : Colors.orange)),
                    ],
                  )),
                  _tableCell(Text(
                      row.statusOk
                          ? (loc.t('haccp_status_admitted'))
                          : (loc.t('haccp_status_suspended')),
                      style: const TextStyle(fontSize: 12))),
                  _tableCell(
                      Text(creatorName, style: const TextStyle(fontSize: 11))),
                  _tableCell(IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                    onPressed: () => setState(() => _healthRows.removeAt(i)),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  )),
                ],
              );
            }),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final usedIds = _healthRows.map((r) => r.employeeId).toSet();
            final available =
                _healthEmployees.where((e) => !usedIds.contains(e.id)).toList();
            if (available.isEmpty) {
              if (mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(loc.t('haccp_all_employees_added') ??
                          'Все сотрудники уже добавлены')),
                );
              return;
            }
            final picked = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(
                    loc.t('haccp_add_employee_row')),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: available.map((e) {
                      final name = displayStoredPersonName(
                          employeeFullNameRaw(e), loc,
                          showNameTranslit: showNameTranslit);
                      return ListTile(
                        title: Text(name),
                        subtitle: Text(
                          e.roles.isNotEmpty
                              ? loc.roleDisplayName(e.roles.first)
                              : '',
                        ),
                        onTap: () => Navigator.of(ctx).pop(e.id),
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
            if (picked != null && mounted)
              setState(() {
                _healthRows.add(_HealthHygieneRow(
                    employeeId: picked,
                    positionOverride: null,
                    positionIsCustom: false,
                    statusOk: true,
                    status2Ok: true));
              });
          },
          icon: const Icon(Icons.add),
          label: Text(loc.t('haccp_add_row')),
        ),
        const SizedBox(height: 8),
        _textField('note', loc.t('haccp_note')),
      ],
    );
  }

  /// Форма по макету Приложения 2: Журнал учета температурного режима холодильного оборудования.
  Widget _buildFridgeTemperatureForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.5),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell(_th(loc, 'haccp_tbl_room_name_prod',
                'Наименование производственного помещения')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_fridge_equipment_name',
                'Наименование холодильного оборудования')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_temp_celsius', 'Температура °C')),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Consumer<AccountManagerSupabase>(
              builder: (_, acc, __) => Text(acc.establishment?.name ?? '—'),
            )),
            _tableCell(_savedOptionTextField(
              key: 'equipment',
              label: loc.t('haccp_equipment'),
              options: _presetOptions['equipment'] ?? const [],
              presetFieldKey: 'equipment',
            )),
            _tableCell(Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_tempValue.toStringAsFixed(1)} °C'),
                Slider(
                  value: _tempValue,
                  min: -25,
                  max: 15,
                  divisions: 80,
                  onChanged: (v) => setState(() => _tempValue = v),
                ),
              ],
            )),
          ],
        ),
      ],
    );
  }

  /// Форма по макету Приложения 3: 5 обязательных колонок. Наименование помещения — в шапке журнала (сохраняется в записи).
  Widget _buildWarehouseTempHumidityForm(LocalizationService loc) {
    _controllers['warehouse_premises'] ??= TextEditingController();
    final tempOutOfRange = _tempValue > 25;
    final humidityOutOfRange = _humidityValue > 75;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _savedOptionTextField(
            key: 'warehouse_premises',
            label: loc.t('haccp_warehouse_premises') ??
                'Наименование складского помещения',
            hintText: loc.t('haccp_warehouse_premises_example_hint'),
            options: _presetOptions['warehouse_premises'] ?? const [],
            presetFieldKey: 'warehouse_premises',
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return loc.t('haccp_warehouse_premises_required');
              }
              return null;
            },
          ),
        ),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(0.5),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.2),
          },
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(
              children: [
                _tableHeaderCell(_th(loc, 'haccp_tbl_pp_no', '№ п/п')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_date', 'Дата')),
                _tableHeaderCell(
                    _th(loc, 'haccp_tbl_temp_c_label', 'Температура, °C')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_rel_humidity_pct',
                    'Относительная влажность, %')),
                _tableHeaderCell(_th(loc, 'haccp_tbl_responsible_sign',
                    'Подпись ответственного лица')),
              ],
            ),
            TableRow(
              children: [
                _tableCell(const Text('1')),
                _tableCell(
                    Text(_formatDate(DateTime.now()))),
                _tableCell(Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tempValue.toStringAsFixed(0),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: tempOutOfRange ? Colors.red : null,
                      ),
                    ),
                    Slider(
                      value: _tempValue,
                      min: -5,
                      max: 35,
                      divisions: 80,
                      onChanged: (v) => setState(() => _tempValue = v),
                    ),
                  ],
                )),
                _tableCell(Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_humidityValue.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: humidityOutOfRange ? Colors.red : null,
                      ),
                    ),
                    Slider(
                      value: _humidityValue,
                      min: 20,
                      max: 95,
                      divisions: 75,
                      onChanged: (v) => setState(() => _humidityValue = v),
                    ),
                  ],
                )),
                _tableCell(_signatureFromAccount()),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Форма по макету Приложения 4: Журнал бракеража готовой пищевой продукции.
  Widget _buildFinishedProductBrakerageForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(0.8),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1),
        6: FlexColumnWidth(1),
        7: FlexColumnWidth(0.8),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell(_th(loc, 'haccp_tbl_dish_made_at',
                'Дата и час изготовления блюда')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_brakerage_removed_at',
                'Время снятия бракеража')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_dish_name_ready',
                'Наименование готового блюда')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_organo_result',
                'Результаты органолептической оценки')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_sale_allowed', 'Разрешение к реализации')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_brakerage_commission_sigs',
                'Подписи членов бракеражной комиссии')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_portion_weighing',
                'Результаты взвешивания порционных блюд')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_note', 'Примечание')),
          ],
        ),
        TableRow(
          children: [
            _tableCell(
                Text(_formatDateTime(DateTime.now()))),
            _tableCell(_textField(
                'time_brakerage',
                _th(loc, 'haccp_placeholder_time_sample',
                    'Время (например 12:00)'))),
            _tableCell(_finishedProductPickerCell(loc)),
            _tableCell(_textField(
                'result', loc.t('haccp_result'),
                multiline: true)),
            _tableCell(_approvalSelector()),
            _tableCell(_signatureFromAccount()),
            _tableCell(_textField('weighing_result',
                _th(loc, 'haccp_cell_weighing', 'Взвешивание'))),
            _tableCell(_textField('note', loc.t('haccp_note'))),
          ],
        ),
      ],
    );
  }

  /// Форма по макету Приложения 5: Журнал бракеража скоропортящейся пищевой продукции.
  Widget _buildIncomingRawBrakerageForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(0.6),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(0.5),
        5: FlexColumnWidth(0.8),
        6: FlexColumnWidth(1),
        7: FlexColumnWidth(0.8),
        8: FlexColumnWidth(0.8),
        9: FlexColumnWidth(0.6),
        10: FlexColumnWidth(0.6),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_received_at', 'Дата и час поступления')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_name', 'Наименование')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_packaging', 'Фасовка')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_manufacturer', 'Изготовитель/поставщик')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_qty_short', 'Кол-во')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_doc_no', '№ документа')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_organo_short', 'Органолептическая оценка')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_storage_shelf',
                'Условия хранения, срок реализации')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_sale_date', 'Дата реализации')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_signature', 'Подпись')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_note_short', 'Прим.')),
          ],
        ),
        TableRow(
          children: [
            _tableCell(
                Text(_formatDateTime(DateTime.now()))),
            _tableCell(_textField(
                'product', loc.t('haccp_product'))),
            _tableCell(_savedOptionTextField(
              key: 'packaging',
              label: _th(loc, 'haccp_tbl_packaging', 'Фасовка'),
              options: _presetOptions['packaging'] ?? const [],
              presetFieldKey: 'packaging',
            )),
            _tableCell(_savedOptionTextField(
              key: 'manufacturer_supplier',
              label:
                  _th(loc, 'haccp_tbl_manufacturer', 'Изготовитель/поставщик'),
              options: _presetOptions['manufacturer_supplier'] ?? const [],
              presetFieldKey: 'manufacturer_supplier',
            )),
            _tableCell(_textField(
                'quantity_kg', _th(loc, 'haccp_cell_qty_kg_l_pcs', 'кг/л/шт'),
                keyboardType: TextInputType.number)),
            _tableCell(_textField(
                'document_number', _th(loc, 'haccp_doc_no_abbr', '№ док.'))),
            _tableCell(_textField('result', loc.t('haccp_result'),
                multiline: true)),
            _tableCell(_savedOptionTextField(
              key: 'storage_conditions',
              label: _th(loc, 'haccp_cell_storage_short', 'Условия, срок'),
              options: _presetOptions['storage_conditions'] ?? const [],
              presetFieldKey: 'storage_conditions',
            )),
            _tableCell(InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dateSold ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _dateSold = d);
              },
              child: Text(_dateSold != null
                  ? _formatDate(_dateSold!)
                  : _th(loc, 'haccp_pick_date_short', 'Выбрать')),
            )),
            _tableCell(_signatureFromAccount()),
            _tableCell(_textField('note', loc.t('haccp_note')),
          ],
        ),
      ],
    );
  }

  /// Выбор сотрудника для журнала медкнижек (десктоп): одно поле «Ф. И. О.», без дубляжа с отдельным TextField.
  Widget _medBookEmployeeDropdown(
      LocalizationService loc, bool showNameTranslit) {
    if (_formEmployees.isEmpty) {
      return _textField('med_book_employee_name',
          _th(loc, 'haccp_tbl_med_exam_fio', 'Ф. И. О.'));
    }
    final selected =
        _formEmployees.where((e) => e.id == _medBookEmployeeId).firstOrNull;
    return DropdownButtonFormField<Employee?>(
      value: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _th(loc, 'haccp_tbl_med_exam_fio', 'Ф. И. О.'),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: _formEmployees
          .map(
            (e) => DropdownMenuItem<Employee?>(
              value: e,
              child: Text(
                displayStoredPersonName(
                  employeeFullNameRaw(e),
                  loc,
                  showNameTranslit: showNameTranslit,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (e) {
        setState(() {
          _medBookEmployeeId = e?.id;
          _setText('med_book_employee_id', e?.id ?? '');
          if (e != null) {
            _setText(
              'med_book_employee_name',
              employeeFullNameRaw(e),
            );
            _setText(
              'med_book_position',
              e.roles.isNotEmpty ? loc.roleDisplayName(e.roles.first) : '',
            );
          } else {
            _setText('med_book_employee_name', '');
            _setText('med_book_position', '');
          }
        });
      },
    );
  }

  /// Форма по бланку: Журнал учёта личных медицинских книжек (1:1 с бумагой).
  Widget _buildMedBookForm(LocalizationService loc, bool showNameTranslit) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.4),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(0.9),
        4: FlexColumnWidth(1.2),
        5: FlexColumnWidth(1.2),
        6: FlexColumnWidth(1.2),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell(_th(loc, 'haccp_tbl_pp_no', '№ п/п')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_fio_full', 'Фамилия, имя, отчество')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_position', 'Должность')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_med_book_no', 'Номер медицинской книжки')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_med_book_valid',
                'Срок действия медицинской книжки')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_med_book_receipt',
                'Расписка и дата получения медицинской книжки')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_med_book_return',
                'Расписка и дата возврата медицинской книжки')),
          ],
        ),
        TableRow(
          children: [
            _tableCell(const Text('1')),
            _tableCell(_medBookEmployeeDropdown(loc, showNameTranslit)),
            _tableCell(_textField('med_book_position',
                _th(loc, 'haccp_tbl_position', 'Должность'))),
            _tableCell(_textField('med_book_number',
                _th(loc, 'haccp_tbl_med_book_no', 'Номер медкнижки'))),
            _tableCell(InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _medBookValidUntil ??
                      DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (d != null) setState(() => _medBookValidUntil = d);
              },
              child: Text(_medBookValidUntil != null
                  ? _formatDate(_medBookValidUntil!)
                  : _th(loc, 'haccp_tap_to_select_date', 'Выбрать дату')),
            )),
            _tableCell(Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _medBookIssuedAt ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _medBookIssuedAt = d);
                  },
                  child: Text(_medBookIssuedAt != null
                      ? _formatDate(_medBookIssuedAt!)
                      : _th(loc, 'haccp_med_placeholder_issue',
                          'Дата получения')),
                ),
                _signatureFromAccount(),
              ],
            )),
            _tableCell(Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _medBookReturnedAt ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _medBookReturnedAt = d);
                  },
                  child: Text(_medBookReturnedAt != null
                      ? _formatDate(_medBookReturnedAt!)
                      : _th(loc, 'haccp_med_placeholder_return',
                          'Дата возврата')),
                ),
                _signatureFromAccount(),
              ],
            )),
          ],
        ),
      ],
    );
  }

  /// Форма по макету Приложения 8: Учёт фритюрных жиров.
  Widget _buildFryingOilForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.9),
        1: FlexColumnWidth(0.7),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1.15),
        5: FlexColumnWidth(1.1),
        6: FlexColumnWidth(0.8),
        7: FlexColumnWidth(1.2),
        8: FlexColumnWidth(0.7),
        9: FlexColumnWidth(0.7),
        10: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(
          children: [
            _tableHeaderCell(_th(loc, 'haccp_tbl_date', 'Дата')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_oil_use_start',
                'Время начала использования жира')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_frying_fat_type', 'Вид фритюрного жира')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_organo_fry_start',
                'Органолептическая оценка на начало жарки')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_fryer_type', 'Тип жарочного оборудования')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_product_type', 'Вид продукции')),
            _tableHeaderCell(
                _th(loc, 'haccp_tbl_time_end', 'Время окончания жарки')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_organo_fry_end',
                'Органолептическая оценка по окончании жарки')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_carry_remainder_kg',
                'Переходящий остаток, кг')),
            _tableHeaderCell(_th(
                loc, 'haccp_tbl_fat_disposed_kg', 'Утилизированный жир, кг')),
            _tableHeaderCell(_th(loc, 'haccp_tbl_controller_fio_role',
                'Должность, Ф.И.О. контролера')),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Text(_formatDate(DateTime.now()))),
            _tableCell(Text(_formatTime(DateTime.now()))),
            _tableCell(_savedOptionTextField(
              key: 'oil_name',
              label: _th(loc, 'haccp_tbl_fat_type', 'Вид жира'),
              options: _presetOptions['oil_name'] ?? const [],
              presetFieldKey: 'oil_name',
            )),
            _tableCell(_textField('organoleptic_start',
                _th(loc, 'haccp_tbl_score_start', 'Оценка на начало'),
                multiline: true)),
            _tableCell(_savedOptionTextField(
              key: 'frying_equipment_type',
              label: _th(loc, 'haccp_tbl_fryer_type', 'Тип оборудования'),
              options: _presetOptions['frying_equipment_type'] ?? const [],
              presetFieldKey: 'frying_equipment_type',
            )),
            _tableCell(_savedOptionTextField(
              key: 'frying_product_type',
              label: _th(loc, 'haccp_tbl_product_type', 'Вид продукции'),
              options: _presetOptions['frying_product_type'] ?? const [],
              presetFieldKey: 'frying_product_type',
            )),
            _tableCell(_textField(
                'frying_end_time',
                _th(loc, 'haccp_placeholder_time_sample_14',
                    'Время (например 14:00)'))),
            _tableCell(_textField('organoleptic_end',
                _th(loc, 'haccp_tbl_score_end', 'Оценка по окончании'),
                multiline: true)),
            _tableCell(_textField(
                'carry_over_kg', _th(loc, 'haccp_tbl_carry_kg', 'кг'),
                keyboardType: TextInputType.number)),
            _tableCell(_textField(
                'utilized_kg', _th(loc, 'haccp_tbl_utilized_kg', 'кг'),
                keyboardType: TextInputType.number)),
            _tableCell(_signatureFromAccount()),
          ],
        ),
      ],
    );
  }

  Widget _buildMedExaminationsForm(
      LocalizationService loc, bool showNameTranslit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_th(loc, 'haccp_form_worker_data', 'Данные работника'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _employeeSelectorDropdown(
            loc: loc,
            employees: _formEmployees,
            label: _th(loc, 'haccp_form_pick_employee', 'Сотрудник'),
            showNameTranslit: showNameTranslit,
            onSelected: (e) {
              if (e != null) {
                _setText('med_exam_employee_name', employeeFullNameRaw(e));
                _setText(
                    'med_exam_dob',
                    e.birthday != null
                        ? _formatDate(e.birthday!)
                        : '');
                _setText(
                  'med_exam_position',
                  e.roles.isNotEmpty ? loc.roleDisplayName(e.roles.first) : '',
                );
                _setText('med_exam_department',
                    e.employeeDepartment?.displayName ?? e.department);
                setState(() {});
              }
            },
          ),
        ),
        Table(
          columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [
              _tableHeaderCell(_th(loc, 'haccp_tbl_med_exam_fio', 'Ф. И. О.')),
              _tableHeaderCell(
                  _th(loc, 'haccp_tbl_age_dob', 'Возраст (дата рождения)'))
            ]),
            TableRow(children: [
              _tableCell(_textField('med_exam_employee_name',
                  _th(loc, 'haccp_tbl_med_exam_fio', 'Ф. И. О.'))),
              _tableCell(_textField(
                  'med_exam_dob', _th(loc, 'birth_date', 'Дата рождения')))
            ]),
            TableRow(children: [
              _tableHeaderCell(_th(loc, 'haccp_tbl_gender_short', 'Пол')),
              _tableHeaderCell(_th(loc, 'haccp_tbl_position', 'Должность'))
            ]),
            TableRow(children: [
              _tableCell(_textField('med_exam_gender',
                  _th(loc, 'haccp_tbl_gender_short', 'Пол'))),
              _tableCell(_textField('med_exam_position',
                  _th(loc, 'haccp_tbl_position', 'Должность')))
            ]),
            TableRow(children: [
              _tableHeaderCell(_th(
                  loc, 'haccp_tbl_struct_unit', 'Структурное подразделение')),
              _tableHeaderCell(
                  _th(loc, 'haccp_tbl_hire_date', 'Дата приёма на работу'))
            ]),
            TableRow(children: [
              _tableCell(_textField('med_exam_department',
                  _th(loc, 'haccp_tbl_struct_unit', 'Подразделение'))),
              _tableCell(_datePickerCell('med_exam_hire_date', _medExamHireDate,
                  (d) => setState(() => _medExamHireDate = d))),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        Text(_th(loc, 'haccp_form_med_exam', 'Медицинский осмотр'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [
              _tableHeaderCell(_th(loc, 'haccp_tbl_exam_kind',
                  'Вид (предварительный/периодический)')),
              _tableHeaderCell(_th(loc, 'haccp_tbl_lpu', 'ЛПУ'))
            ]),
            TableRow(children: [
              _tableCell(_textField('med_exam_type',
                  _th(loc, 'haccp_cell_exam_kind_short', 'Вид'))),
              _tableCell(_textField(
                  'med_exam_institution',
                  _th(loc, 'haccp_cell_institution_long',
                      'Лечебное учреждение')))
            ]),
            TableRow(children: [
              _tableHeaderCell(
                  _th(loc, 'haccp_tbl_harmful_90', 'Вредный фактор №90')),
              _tableHeaderCell(
                  _th(loc, 'haccp_tbl_harmful_83', 'Вредный фактор №83'))
            ]),
            TableRow(children: [
              _tableCell(_textField('med_exam_harmful_1',
                  _th(loc, 'haccp_cell_order_ref_90', '№ по приказу 90'))),
              _tableCell(_textField('med_exam_harmful_2',
                  _th(loc, 'haccp_cell_order_ref_83', '№ по приказу 83')))
            ]),
            TableRow(children: [
              _tableHeaderCell(
                  _th(loc, 'haccp_tbl_exam_pass_date', 'Дата прохождения')),
              _tableHeaderCell(_th(loc, 'haccp_tbl_conclusion', 'Заключение'))
            ]),
            TableRow(children: [
              _tableCell(_datePickerCell('med_exam_date', _medExamDate,
                  (d) => setState(() => _medExamDate = d))),
              _tableCell(_textField('med_exam_conclusion',
                  _th(loc, 'haccp_tbl_conclusion', 'Заключение'))),
            ]),
            TableRow(children: [
              _tableHeaderCell(_th(
                  loc, 'haccp_tbl_employer_decision', 'Решение работодателя')),
              _tableHeaderCell(_th(
                  loc, 'haccp_tbl_next_exam_date', 'Дата следующего осмотра'))
            ]),
            TableRow(children: [
              _tableCell(_textField(
                  'med_exam_employer_decision',
                  _th(loc, 'haccp_cell_employer_decision_short',
                      'Допущен/отстранён/переведён/уволен'))),
              _tableCell(_datePickerCell('med_exam_next_date', _medExamNextDate,
                  (d) => setState(() => _medExamNextDate = d))),
            ]),
            TableRow(children: [
              _tableHeaderCell(_th(loc, 'haccp_tbl_exclusion_date',
                  'Дата исключения из списков')),
              _tableHeaderCell(_th(loc, 'haccp_tbl_note', 'Примечание'))
            ]),
            TableRow(children: [
              _tableCell(_datePickerCell(
                  'med_exam_exclusion_date',
                  _medExamExclusionDate,
                  (d) => setState(() => _medExamExclusionDate = d))),
              _tableCell(_textField(
                  'med_exam_note', _th(loc, 'haccp_tbl_note', 'Примечание'))),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _datePickerCell(
      String key, DateTime? value, void Function(DateTime) onDate) {
    final loc = context.read<LocalizationService>();
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 3650)));
        if (d != null) onDate(d);
      },
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Text(value != null
              ? _formatDate(value)
              : _th(loc, 'haccp_tap_to_select_date', 'Выбрать дату'))),
    );
  }

  Widget _buildDisinfectantAccountingForm(LocalizationService loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            _th(loc, 'haccp_form_disinfect_need_title',
                'Расчёт потребности в дезинфицирующих средствах'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        // Без фиксированной ширины Table внутри горизонтального scroll получает
        // неограниченный maxWidth — FlexColumnWidth схлопывает колонки (текст «в столбик»).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1280,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(0.6),
                1: FlexColumnWidth(0.8),
                2: FlexColumnWidth(0.5),
                3: FlexColumnWidth(0.5),
                4: FlexColumnWidth(0.4),
                5: FlexColumnWidth(0.5),
                6: FlexColumnWidth(0.6),
                7: FlexColumnWidth(0.5),
                8: FlexColumnWidth(0.5),
                9: FlexColumnWidth(0.5),
                10: FlexColumnWidth(0.5),
                11: FlexColumnWidth(0.5),
              },
              border: TableBorder.all(color: Theme.of(context).dividerColor),
              children: [
                TableRow(children: [
                  _tableHeaderCell(
                      _th(loc, 'haccp_tbl_object_short', 'Объект')),
                  _tableHeaderCell(_th(loc, 'haccp_tbl_qty_short', 'Кол-во')),
                  _tableHeaderCell(_th(loc, 'haccp_tbl_area_m2', 'Площадь м²')),
                  _tableHeaderCell(_th(loc, 'haccp_tbl_tg_type', 'Вид Т/Г')),
                  _tableHeaderCell(
                      _th(loc, 'haccp_tbl_frequency_month', 'Кратность/мес')),
                  _tableHeaderCell(
                      _th(loc, 'haccp_tbl_disinfectant_short', 'Дезсредство')),
                  _tableHeaderCell(_th(loc, 'haccp_tbl_conc_pct', 'Конц.%')),
                  _tableHeaderCell(
                      _th(loc, 'haccp_tbl_consumption_m2', 'Расход/м²')),
                  _tableHeaderCell(_th(loc, 'haccp_tbl_solution_per_round',
                      'Раствор на 1 обр.')),
                  _tableHeaderCell(
                      _th(loc, 'haccp_tbl_need_1_round', 'Потребность 1 обр.')),
                  _tableHeaderCell(_th(loc, 'haccp_tbl_per_month', 'В месяц')),
                  _tableHeaderCell(_th(loc, 'haccp_tbl_per_year', 'В год')),
                ]),
                TableRow(children: [
                  _tableCell(_savedOptionTextField(
                    key: 'disinf_object_name',
                    label: _th(loc, 'haccp_tbl_object_short', 'Объект'),
                    options: _presetOptions['disinf_object_name'] ?? const [],
                    presetFieldKey: 'disinf_object_name',
                  )),
                  _tableCell(_textField('disinf_object_count',
                      _th(loc, 'haccp_tbl_qty_short', 'Кол-во'),
                      keyboardType: TextInputType.number)),
                  _tableCell(_textField(
                      'disinf_area_sqm', _th(loc, 'haccp_tbl_area_m2', 'м²'),
                      keyboardType: TextInputType.number)),
                  _tableCell(_savedOptionTextField(
                    key: 'disinf_treatment_type',
                    label: _th(loc, 'haccp_tbl_tg_type', 'Т/Г'),
                    options:
                        _presetOptions['disinf_treatment_type'] ?? const [],
                    presetFieldKey: 'disinf_treatment_type',
                  )),
                  _tableCell(_textField('disinf_frequency',
                      _th(loc, 'haccp_tbl_frequency_month', 'Кратность'),
                      keyboardType: TextInputType.number)),
                  _tableCell(_savedOptionTextField(
                    key: 'disinf_agent_name',
                    label:
                        _th(loc, 'haccp_tbl_disinfectant_short', 'Дезсредство'),
                    options: _presetOptions['disinf_agent_name'] ?? const [],
                    presetFieldKey: 'disinf_agent_name',
                  )),
                  _tableCell(_textField('disinf_concentration_pct',
                      _th(loc, 'haccp_tbl_conc_pct', '%'))),
                  _tableCell(_textField('disinf_consumption_per_sqm',
                      _th(loc, 'haccp_tbl_consumption_m2', 'Расход'),
                      keyboardType: TextInputType.number)),
                  _tableCell(_textField('disinf_solution_per_treatment',
                      _th(loc, 'haccp_cell_unit_l_kg', 'л/кг'),
                      keyboardType: TextInputType.number)),
                  _tableCell(_textField('disinf_need_per_treatment',
                      _th(loc, 'haccp_cell_unit_l_kg', 'л/кг'),
                      keyboardType: TextInputType.number)),
                  _tableCell(_textField('disinf_need_per_month',
                      _th(loc, 'haccp_cell_unit_l_kg', 'л/кг'),
                      keyboardType: TextInputType.number)),
                  _tableCell(_textField('disinf_need_per_year',
                      _th(loc, 'haccp_cell_unit_l_kg', 'л/кг'),
                      keyboardType: TextInputType.number)),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
            _th(loc, 'haccp_form_disinfect_receipt_title',
                'Поступление дезинфицирующих средств'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(0.5),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(0.8),
            3: FlexColumnWidth(0.6),
            4: FlexColumnWidth(0.6),
            5: FlexColumnWidth(1)
          },
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [
              _tableHeaderCell(_th(loc, 'haccp_tbl_date', 'Дата')),
              _tableHeaderCell(_th(loc, 'haccp_tbl_name', 'Наименование')),
              _tableHeaderCell(
                  _th(loc, 'haccp_tbl_invoice_date', 'Счёт, дата')),
              _tableHeaderCell(_th(loc, 'haccp_tbl_qty_short', 'Кол-во')),
              _tableHeaderCell(_th(loc, 'haccp_tbl_expiry', 'Срок годности')),
              _tableHeaderCell(
                  _th(loc, 'haccp_tbl_responsible', 'Ответственный'))
            ]),
            TableRow(children: [
              _tableCell(_datePickerCell(
                  'disinf_receipt_date',
                  _disinfReceiptDate,
                  (d) => setState(() => _disinfReceiptDate = d))),
              _tableCell(_savedOptionTextField(
                key: 'disinf_agent_name_receipt',
                label: _th(loc, 'haccp_tbl_name', 'Наименование'),
                options:
                    _presetOptions['disinf_agent_name_receipt'] ?? const [],
                presetFieldKey: 'disinf_agent_name_receipt',
              )),
              _tableCell(_textField('disinf_invoice_number',
                  _th(loc, 'haccp_cell_invoice_no', '№ счёта'))),
              _tableCell(_textField(
                  'disinf_quantity', _th(loc, 'haccp_tbl_qty_short', 'Кол-во'),
                  keyboardType: TextInputType.number)),
              _tableCell(_datePickerCell(
                  'disinf_expiry_date',
                  _disinfExpiryDate,
                  (d) => setState(() => _disinfExpiryDate = d))),
              _tableCell(_signatureFromAccount()),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _buildEquipmentWashingForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.6),
        1: FlexColumnWidth(0.5),
        2: FlexColumnWidth(1.35),
        3: FlexColumnWidth(1.1),
        4: FlexColumnWidth(0.5),
        5: FlexColumnWidth(0.9),
        6: FlexColumnWidth(0.5),
        7: FlexColumnWidth(0.5),
        8: FlexColumnWidth(0.8),
        9: FlexColumnWidth(0.8),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [
          _tableHeaderCell(_th(loc, 'haccp_tbl_date', 'Дата')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_wash_time', 'Время мойки')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_equipment', 'Оборудование')),
          _tableHeaderCell(
              _th(loc, 'haccp_tbl_cleaning_solution', 'Моющий раствор')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_conc_pct', 'Конц.%')),
          _tableHeaderCell(
              _th(loc, 'haccp_tbl_disinfect_solution', 'Дез. раствор')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_conc_pct', 'Конц.%')),
          _tableHeaderCell(
              _th(loc, 'haccp_tbl_rinse_temp', 'Ополаскивание t°')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_washer_fio', 'Ф.И.О. мойщика')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_controller', 'Контроль')),
        ]),
        TableRow(children: [
          _tableCell(Text(_formatDate(DateTime.now()))),
          _tableCell(
              _textField('wash_time', _th(loc, 'haccp_tbl_time', 'Время'))),
          _tableCell(_savedOptionTextField(
            key: 'wash_equipment_name',
            label: _th(loc, 'haccp_tbl_equipment', 'Оборудование'),
            options: _presetOptions['wash_equipment_name'] ?? const [],
            presetFieldKey: 'wash_equipment_name',
          )),
          _tableCell(_savedOptionTextField(
            key: 'wash_solution_name',
            label: _th(loc, 'haccp_tbl_wash_solution', 'Моющее'),
            options: _presetOptions['wash_solution_name'] ?? const [],
            presetFieldKey: 'wash_solution_name',
          )),
          _tableCell(_textField('wash_solution_concentration_pct',
              _th(loc, 'haccp_tbl_conc_pct', '%'))),
          _tableCell(_savedOptionTextField(
            key: 'wash_disinfectant_name',
            label: _th(loc, 'haccp_tbl_disinfect_solution', 'Дез. раствор'),
            options: _presetOptions['wash_disinfectant_name'] ?? const [],
            presetFieldKey: 'wash_disinfectant_name',
          )),
          _tableCell(_textField('wash_disinfectant_concentration_pct',
              _th(loc, 'haccp_tbl_conc_pct', '%'))),
          _tableCell(_textField(
              'wash_rinsing_temp', _th(loc, 'haccp_tbl_rinse_temp', 't°'))),
          _tableCell(_signatureFromAccount()),
          _tableCell(_signatureFromAccount()),
        ]),
      ],
    );
  }

  Widget _buildGeneralCleaningForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.5),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1)
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [
          _tableHeaderCell(_th(loc, 'haccp_tbl_no_short', '№')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_room_zone', 'Помещение / зона')),
          _tableHeaderCell(
              _th(loc, 'haccp_tbl_gen_clean_date', 'Дата проведения')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_responsible', 'Ответственный'))
        ]),
        TableRow(children: [
          _tableCell(const Text('1')),
          _tableCell(_savedOptionTextField(
            key: 'gen_clean_premises',
            label: _th(loc, 'haccp_tbl_room', 'Помещение'),
            options: _presetOptions['gen_clean_premises'] ?? const [],
            presetFieldKey: 'gen_clean_premises',
          )),
          _tableCell(_datePickerCell('gen_clean_date', _genCleanDate,
              (d) => setState(() => _genCleanDate = d))),
          _tableCell(_signatureFromAccount()),
        ]),
      ],
    );
  }

  Widget _buildSieveFilterMagnetForm(LocalizationService loc) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.5),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(0.8),
        3: FlexColumnWidth(0.8),
        4: FlexColumnWidth(0.8),
        5: FlexColumnWidth(0.8)
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [
          _tableHeaderCell(
              _th(loc, 'haccp_tbl_sieve_magnet_no', '№ сита/магнита')),
          _tableHeaderCell(_th(
              loc, 'haccp_tbl_name_location', 'Наименование / Расположение')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_condition', 'Состояние')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_cleaning_date', 'Дата очистки')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_fio_signature', 'ФИО, Подпись')),
          _tableHeaderCell(_th(loc, 'haccp_tbl_comments', 'Комментарии'))
        ]),
        TableRow(children: [
          _tableCell(
              _textField('sieve_no', _th(loc, 'haccp_tbl_no_short', '№'))),
          _tableCell(_savedOptionTextField(
            key: 'sieve_name_location',
            label: _th(loc, 'haccp_tbl_name', 'Наименование'),
            options: _presetOptions['sieve_name_location'] ?? const [],
            presetFieldKey: 'sieve_name_location',
          )),
          _tableCell(_savedOptionTextField(
            key: 'sieve_condition',
            label: _th(loc, 'haccp_tbl_condition', 'Состояние'),
            options: _presetOptions['sieve_condition'] ?? const [],
            presetFieldKey: 'sieve_condition',
          )),
          _tableCell(_datePickerCell('sieve_cleaning_date', _sieveCleaningDate,
              (d) => setState(() => _sieveCleaningDate = d))),
          _tableCell(_signatureFromAccount()),
          _tableCell(_textField(
              'sieve_comments', _th(loc, 'haccp_tbl_comments', 'Комментарии'))),
        ]),
      ],
    );
  }

  Widget _buildFormByType(LocalizationService loc, bool showNameTranslit) {
    switch (_logType) {
      case HaccpLogType.healthHygiene:
        return _buildHealthHygieneForm(loc, showNameTranslit);
      case HaccpLogType.fridgeTemperature:
        return _buildFridgeTemperatureForm(loc);
      case HaccpLogType.warehouseTempHumidity:
        return _buildWarehouseTempHumidityForm(loc);
      case HaccpLogType.finishedProductBrakerage:
        return _buildFinishedProductBrakerageForm(loc);
      case HaccpLogType.incomingRawBrakerage:
        return _buildIncomingRawBrakerageForm(loc);
      case HaccpLogType.fryingOil:
        return _buildFryingOilForm(loc);
      case HaccpLogType.medBookRegistry:
        return _buildMedBookForm(loc, showNameTranslit);
      case HaccpLogType.medExaminations:
        return _buildMedExaminationsForm(loc, showNameTranslit);
      case HaccpLogType.disinfectantAccounting:
        return _buildDisinfectantAccountingForm(loc);
      case HaccpLogType.equipmentWashing:
        return _buildEquipmentWashingForm(loc);
      case HaccpLogType.generalCleaningSchedule:
        return _buildGeneralCleaningForm(loc);
      case HaccpLogType.sieveFilterMagnet:
        return _buildSieveFilterMagnetForm(loc);
      default:
        return const SizedBox.shrink();
    }
  }

  // ---- Mobile (1 column, no horizontal scroll) ----

  Widget _mobileBlock(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...children.expand((w) => [w, const SizedBox(height: 10)]).toList()
              ..removeLast(),
          ],
        ),
      ),
    );
  }

  Widget _mobileSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required void Function(double) onChanged,
    int fractionDigits = 1,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text('${value.toStringAsFixed(fractionDigits)} $unit',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      ],
    );
  }

  Widget _buildFormByTypeMobile(
      LocalizationService loc, bool showNameTranslit) {
    switch (_logType) {
      case HaccpLogType.healthHygiene:
        final dateStr = _formatDate(DateTime.now());
        final currentEmp =
            context.watch<AccountManagerSupabase>().currentEmployee;
        final creatorName = currentEmp != null
            ? displayStoredPersonName(
                employeeFullNameRaw(currentEmp),
                loc,
                showNameTranslit: showNameTranslit,
              )
            : '—';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...List.generate(_healthRows.length, (i) {
              final row = _healthRows[i];
              final emp = _healthEmployeeById(row.employeeId);
              final name = emp != null
                  ? displayStoredPersonName(
                      employeeFullNameRaw(emp),
                      loc,
                      showNameTranslit: showNameTranslit,
                    )
                  : '—';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('$name · $dateStr',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                setState(() => _healthRows.removeAt(i)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _healthPositionDropdownForRow(i, loc),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(loc.t('haccp_tbl_sign_family_infect')),
                        value: row.statusOk,
                        onChanged: (v) => setState(() => row.statusOk = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(loc.t('haccp_tbl_sign_skin_resp')),
                        value: row.status2Ok,
                        onChanged: (v) => setState(() => row.status2Ok = v),
                      ),
                      const Divider(),
                      Text(
                          '${loc.t('haccp_result_label_short')}: ${row.statusOk ? loc.t('haccp_status_admitted') : loc.t('haccp_status_suspended')}',
                          style: const TextStyle(fontSize: 12)),
                      Text('${loc.t('haccp_responsible_person')}: $creatorName',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () async {
                final usedIds = _healthRows.map((r) => r.employeeId).toSet();
                final available = _healthEmployees
                    .where((e) => !usedIds.contains(e.id))
                    .toList();
                if (available.isEmpty) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(loc.t('haccp_all_employees_added') ??
                              'Все сотрудники уже добавлены')),
                    );
                  return;
                }
                final picked = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(loc.t('haccp_add_employee_row') ??
                        'Добавить сотрудника'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: available.map((e) {
                          final name = displayStoredPersonName(
                              employeeFullNameRaw(e), loc,
                              showNameTranslit: showNameTranslit);
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(
                              e.roles.isNotEmpty
                                  ? loc.roleDisplayName(e.roles.first)
                                  : '',
                            ),
                            onTap: () => Navigator.of(ctx).pop(e.id),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
                if (picked != null && mounted)
                  setState(() {
                    _healthRows.add(_HealthHygieneRow(
                        employeeId: picked,
                        positionOverride: null,
                        positionIsCustom: false,
                        statusOk: true,
                        status2Ok: true));
                  });
              },
              icon: const Icon(Icons.add),
              label: Text(loc.t('haccp_add_row')),
            ),
            const SizedBox(height: 10),
            _textField('note', loc.t('haccp_note')),
          ],
        );
      case HaccpLogType.fridgeTemperature:
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.fridgeTemperature, loc),
          [
            Consumer<AccountManagerSupabase>(
              builder: (_, acc, __) => TextFormField(
                initialValue: acc.establishment?.name ?? '—',
                decoration: InputDecoration(
                  labelText: loc.t('haccp_production_premises_name'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                readOnly: true,
              ),
            ),
            _savedOptionTextField(
              key: 'equipment',
              label: loc.t('haccp_equipment'),
              options: _presetOptions['equipment'] ?? const [],
              presetFieldKey: 'equipment',
            ),
            _mobileSlider(
              label: loc.t('haccp_temperature_short'),
              value: _tempValue,
              min: -25,
              max: 15,
              divisions: 400,
              unit: '°C',
              onChanged: (v) => _tempValue = v,
              fractionDigits: 1,
            ),
          ],
        );
      case HaccpLogType.warehouseTempHumidity:
        _controllers['warehouse_premises'] ??= TextEditingController();
        return Column(
          children: [
            _mobileBlock(
              _logTypeTitle(HaccpLogType.warehouseTempHumidity, loc),
              [
                _savedOptionTextField(
                  key: 'warehouse_premises',
                  label: loc.t('haccp_warehouse_premises') ??
                      'Наименование складского помещения',
                  options: _presetOptions['warehouse_premises'] ?? const [],
                  presetFieldKey: 'warehouse_premises',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? loc.t('haccp_warehouse_premises_required')
                      : null,
                ),
                _mobileSlider(
                  label: loc.t('haccp_temperature_short'),
                  value: _tempValue,
                  min: -5,
                  max: 35,
                  divisions: 800,
                  unit: '°C',
                  onChanged: (v) => _tempValue = v,
                  fractionDigits: 1,
                ),
                _mobileSlider(
                  label: loc.t('haccp_relative_humidity_short'),
                  value: _humidityValue,
                  min: 0,
                  max: 100,
                  divisions: 200,
                  unit: '%',
                  onChanged: (v) => _humidityValue = v,
                  fractionDigits: 1,
                ),
                _signatureFromAccount(),
              ],
            ),
          ],
        );
      case HaccpLogType.finishedProductBrakerage:
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.finishedProductBrakerage, loc),
          [
            TextFormField(
              initialValue:
                  _formatDateTime(DateTime.now()),
              decoration: InputDecoration(
                  labelText: _th(loc, 'haccp_tbl_dish_made_at',
                      'Дата и час изготовления блюда'),
                  border: const OutlineInputBorder(),
                  isDense: true),
              readOnly: true,
            ),
            _textField(
                'time_brakerage',
                _th(loc, 'haccp_placeholder_time_sample',
                    'Время снятия бракеража (например 12:00)')),
            _finishedProductPickerCell(loc),
            _textField('result',
                loc.t('haccp_result'),
                multiline: true),
            _approvalSelector(),
            _signatureFromAccount(),
            _textField(
                'weighing_result',
                _th(loc, 'haccp_tbl_portion_weighing',
                    'Результаты взвешивания порционных блюд')),
            _textField('note', loc.t('haccp_note')),
          ],
        );
      case HaccpLogType.incomingRawBrakerage:
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.incomingRawBrakerage, loc),
          [
            TextFormField(
              initialValue:
                  _formatDateTime(DateTime.now()),
              decoration: InputDecoration(
                  labelText: _th(
                      loc, 'haccp_tbl_received_at', 'Дата и час поступления'),
                  border: const OutlineInputBorder(),
                  isDense: true),
              readOnly: true,
            ),
            _textField('product', loc.t('haccp_product')),
            _savedOptionTextField(
              key: 'packaging',
              label: _th(loc, 'haccp_tbl_packaging', 'Фасовка'),
              options: _presetOptions['packaging'] ?? const [],
              presetFieldKey: 'packaging',
            ),
            _savedOptionTextField(
              key: 'manufacturer_supplier',
              label:
                  _th(loc, 'haccp_tbl_manufacturer', 'Изготовитель/поставщик'),
              options: _presetOptions['manufacturer_supplier'] ?? const [],
              presetFieldKey: 'manufacturer_supplier',
            ),
            _textField('quantity_kg',
                _th(loc, 'haccp_cell_qty_paren_long', 'Кол-во (кг/л/шт)'),
                keyboardType: TextInputType.number),
            _textField(
                'document_number', _th(loc, 'haccp_tbl_doc_no', '№ документа')),
            _textField(
                'result', loc.t('haccp_result'),
                multiline: true),
            _savedOptionTextField(
              key: 'storage_conditions',
              label: _th(loc, 'haccp_tbl_storage_shelf',
                  'Условия хранения, срок реализации'),
              options: _presetOptions['storage_conditions'] ?? const [],
              presetFieldKey: 'storage_conditions',
            ),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dateSold ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _dateSold = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                    labelText:
                        _th(loc, 'haccp_tbl_sale_date', 'Дата реализации'),
                    border: const OutlineInputBorder(),
                    isDense: true),
                child: Text(_dateSold != null
                    ? _formatDate(_dateSold!)
                    : _th(loc, 'haccp_pick_date_short', 'Выбрать')),
              ),
            ),
            _signatureFromAccount(),
            _textField('note', loc.t('haccp_note')),
          ],
        );
      case HaccpLogType.fryingOil:
        // Те же поля, что и в табличной форме (СанПиН), чтобы сохранение в БД и пресеты совпадали с десктопом.
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.fryingOil, loc),
          [
            TextFormField(
              initialValue: _formatDate(DateTime.now()),
              decoration: InputDecoration(
                  labelText: _th(loc, 'haccp_tbl_date', 'Дата'),
                  border: const OutlineInputBorder(),
                  isDense: true),
              readOnly: true,
            ),
            TextFormField(
              initialValue: _formatTime(DateTime.now()),
              decoration: InputDecoration(
                labelText: _th(loc, 'haccp_tbl_oil_use_start',
                    'Время начала использования жира'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              readOnly: true,
            ),
            _savedOptionTextField(
              key: 'oil_name',
              label:
                  _th(loc, 'haccp_tbl_frying_fat_type', 'Вид фритюрного жира'),
              options: _presetOptions['oil_name'] ?? const [],
              presetFieldKey: 'oil_name',
            ),
            _textField(
                'organoleptic_start',
                _th(loc, 'haccp_tbl_organo_fry_start',
                    'Органолептика на начало жарки'),
                multiline: true),
            _savedOptionTextField(
              key: 'frying_equipment_type',
              label: _th(
                  loc, 'haccp_tbl_fryer_type', 'Тип жарочного оборудования'),
              options: _presetOptions['frying_equipment_type'] ?? const [],
              presetFieldKey: 'frying_equipment_type',
            ),
            _savedOptionTextField(
              key: 'frying_product_type',
              label: _th(loc, 'haccp_tbl_product_type', 'Вид продукции'),
              options: _presetOptions['frying_product_type'] ?? const [],
              presetFieldKey: 'frying_product_type',
            ),
            _textField(
                'frying_end_time',
                _th(loc, 'haccp_placeholder_time_sample_14',
                    'Время окончания жарки (например 14:00)')),
            _textField(
                'organoleptic_end',
                _th(loc, 'haccp_tbl_organo_fry_end',
                    'Органолептика по окончании жарки'),
                multiline: true),
            _textField(
                'carry_over_kg',
                _th(loc, 'haccp_tbl_carry_remainder_kg',
                    'Переходящий остаток, кг'),
                keyboardType: TextInputType.number),
            _textField(
                'utilized_kg',
                _th(loc, 'haccp_tbl_fat_disposed_kg',
                    'Утилизированный жир, кг'),
                keyboardType: TextInputType.number),
            _signatureFromAccount(),
            _textField('note', loc.t('haccp_note')),
          ],
        );
      case HaccpLogType.medBookRegistry:
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.medBookRegistry, loc),
          [
            _employeePickerField(
                'med_book_employee_id',
                _th(loc, 'haccp_form_pick_employee', 'Сотрудник'),
                _medBookEmployeeId,
                (id) => setState(() {
                      _medBookEmployeeId = id;
                      final emp =
                          _formEmployees.where((e) => e.id == id).firstOrNull;
                      if (emp != null) {
                        _setText(
                          'med_book_employee_name',
                          employeeFullNameRaw(emp),
                        );
                        _setText(
                          'med_book_position',
                          emp.roles.isNotEmpty
                              ? loc.roleDisplayName(emp.roles.first)
                              : '',
                        );
                      } else {
                        _setText('med_book_employee_name', '');
                        _setText('med_book_position', '');
                      }
                    }),
                loc,
                showNameTranslit),
            _textField('med_book_position',
                _th(loc, 'haccp_tbl_position', 'Должность')),
            _textField('med_book_number',
                _th(loc, 'haccp_tbl_med_book_no', 'Номер медицинской книжки')),
            _datePickerField(
                'med_book_expiry_date',
                _th(loc, 'haccp_med_mobile_valid', 'Срок действия'),
                _medBookExpiryDate,
                (d) => setState(() => _medBookExpiryDate = d)),
            _datePickerField(
                'med_book_received_date',
                _th(loc, 'haccp_med_mobile_receipt', 'Получение (дата)'),
                _medBookReceivedDate,
                (d) => setState(() => _medBookReceivedDate = d)),
            _datePickerField(
                'med_book_returned_date',
                _th(loc, 'haccp_med_mobile_return', 'Возврат (дата)'),
                _medBookReturnedDate,
                (d) => setState(() => _medBookReturnedDate = d)),
          ],
        );
      case HaccpLogType.medExaminations:
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.medExaminations, loc),
          [
            _employeePickerField(
                'med_exam_employee_id',
                _th(loc, 'haccp_form_pick_employee', 'Сотрудник'),
                _medExamEmployeeId,
                (id) => setState(() => _medExamEmployeeId = id),
                loc,
                showNameTranslit),
            _textField('med_exam_position',
                _th(loc, 'haccp_tbl_position', 'Должность')),
            _textField('med_exam_department',
                _th(loc, 'haccp_tbl_struct_unit', 'Подразделение')),
            _datePickerField(
                'med_exam_hire_date',
                _th(loc, 'haccp_tbl_hire_date', 'Дата приёма'),
                _medExamHireDate,
                (d) => setState(() => _medExamHireDate = d)),
            _textField(
                'med_exam_type',
                _th(loc, 'haccp_tbl_exam_kind',
                    'Вид (предварительный/периодический)')),
            _textField(
                'med_exam_institution', _th(loc, 'haccp_tbl_lpu', 'ЛПУ')),
            _textField('med_exam_harmful_1',
                _th(loc, 'haccp_tbl_harmful_90', 'Вредный фактор №90')),
            _textField('med_exam_harmful_2',
                _th(loc, 'haccp_tbl_harmful_83', 'Вредный фактор №83')),
            _datePickerField(
                'med_exam_date',
                _th(loc, 'haccp_tbl_exam_pass_date', 'Дата прохождения'),
                _medExamDate,
                (d) => setState(() => _medExamDate = d)),
            _textField('med_exam_conclusion',
                _th(loc, 'haccp_tbl_conclusion', 'Заключение')),
            _textField(
                'med_exam_employer_decision',
                _th(loc, 'haccp_tbl_employer_decision',
                    'Решение работодателя')),
            _datePickerField(
                'med_exam_next_date',
                _th(loc, 'haccp_tbl_next_exam_date', 'Дата следующего осмотра'),
                _medExamNextDate,
                (d) => setState(() => _medExamNextDate = d)),
            _datePickerField(
                'med_exam_exclusion_date',
                _th(loc, 'haccp_tbl_exclusion_date',
                    'Дата исключения из списков'),
                _medExamExclusionDate,
                (d) => setState(() => _medExamExclusionDate = d)),
            _textField(
                'med_exam_note', _th(loc, 'haccp_tbl_note', 'Примечание')),
          ],
        );
      case HaccpLogType.disinfectantAccounting:
        return Column(
          children: [
            _mobileBlock(
              _th(loc, 'haccp_form_disinfect_need_title',
                  'Расчёт потребности в дезинфицирующих средствах'),
              [
                _savedOptionTextField(
                  key: 'disinf_object_name',
                  label: _th(loc, 'haccp_tbl_object_short', 'Объект'),
                  options: _presetOptions['disinf_object_name'] ?? const [],
                  presetFieldKey: 'disinf_object_name',
                ),
                _textField('disinf_object_count',
                    _th(loc, 'haccp_tbl_qty_short', 'Кол-во'),
                    keyboardType: TextInputType.number),
                _textField('disinf_area_sqm',
                    _th(loc, 'haccp_tbl_area_m2', 'Площадь м²'),
                    keyboardType: TextInputType.number),
                _savedOptionTextField(
                  key: 'disinf_treatment_type',
                  label: _th(loc, 'haccp_tbl_tg_type', 'Вид Т/Г'),
                  options: _presetOptions['disinf_treatment_type'] ?? const [],
                  presetFieldKey: 'disinf_treatment_type',
                ),
                _textField('disinf_frequency',
                    _th(loc, 'haccp_tbl_frequency_month', 'Кратность/мес'),
                    keyboardType: TextInputType.number),
                _savedOptionTextField(
                  key: 'disinf_agent_name',
                  label:
                      _th(loc, 'haccp_tbl_disinfectant_short', 'Дезсредство'),
                  options: _presetOptions['disinf_agent_name'] ?? const [],
                  presetFieldKey: 'disinf_agent_name',
                ),
                _textField('disinf_concentration_pct',
                    _th(loc, 'haccp_tbl_conc_pct', 'Конц.%')),
                _textField('disinf_consumption_per_sqm',
                    _th(loc, 'haccp_tbl_consumption_m2', 'Расход/м²'),
                    keyboardType: TextInputType.number),
                _textField(
                    'disinf_solution_per_treatment',
                    _th(loc, 'haccp_disinf_solution_per_round_hint',
                        'Раствор на 1 обр. (л/кг)'),
                    keyboardType: TextInputType.number),
                _textField(
                    'disinf_need_per_treatment',
                    _th(loc, 'haccp_disinf_need_round_hint',
                        'Потребность 1 обр. (л/кг)'),
                    keyboardType: TextInputType.number),
                _textField('disinf_need_per_month',
                    _th(loc, 'haccp_disinf_need_month_hint', 'В месяц (л/кг)'),
                    keyboardType: TextInputType.number),
                _textField('disinf_need_per_year',
                    _th(loc, 'haccp_disinf_need_year_hint', 'В год (л/кг)'),
                    keyboardType: TextInputType.number),
              ],
            ),
            _mobileBlock(
              _th(loc, 'haccp_form_disinfect_receipt_title',
                  'Поступление дезинфицирующих средств'),
              [
                _datePickerField(
                    'disinf_receipt_date',
                    _th(loc, 'haccp_tbl_date', 'Дата'),
                    _disinfReceiptDate,
                    (d) => setState(() => _disinfReceiptDate = d)),
                _savedOptionTextField(
                  key: 'disinf_agent_name_receipt',
                  label: _th(loc, 'haccp_tbl_name', 'Наименование'),
                  options:
                      _presetOptions['disinf_agent_name_receipt'] ?? const [],
                  presetFieldKey: 'disinf_agent_name_receipt',
                ),
                _textField('disinf_invoice_number',
                    _th(loc, 'haccp_invoice_no_short', 'Счёт №')),
                _textField('disinf_quantity',
                    _th(loc, 'haccp_tbl_qty_short', 'Кол-во'),
                    keyboardType: TextInputType.number),
                _datePickerField(
                    'disinf_expiry_date',
                    _th(loc, 'haccp_tbl_expiry', 'Срок годности'),
                    _disinfExpiryDate,
                    (d) => setState(() => _disinfExpiryDate = d)),
                _signatureFromAccount(),
              ],
            ),
          ],
        );
      case HaccpLogType.equipmentWashing:
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.equipmentWashing, loc),
          [
            TextFormField(
              initialValue: _formatDate(DateTime.now()),
              decoration: InputDecoration(
                  labelText: _th(loc, 'haccp_tbl_date', 'Дата'),
                  border: const OutlineInputBorder(),
                  isDense: true),
              readOnly: true,
            ),
            _textField(
                'wash_time', _th(loc, 'haccp_tbl_wash_time', 'Время мойки')),
            _savedOptionTextField(
              key: 'wash_equipment_name',
              label: _th(loc, 'haccp_tbl_equipment', 'Оборудование'),
              options: _presetOptions['wash_equipment_name'] ?? const [],
              presetFieldKey: 'wash_equipment_name',
            ),
            _savedOptionTextField(
              key: 'wash_solution_name',
              label: _th(loc, 'haccp_tbl_cleaning_solution', 'Моющий раствор'),
              options: _presetOptions['wash_solution_name'] ?? const [],
              presetFieldKey: 'wash_solution_name',
            ),
            _textField('wash_solution_concentration_pct',
                _th(loc, 'haccp_tbl_conc_pct', 'Конц.%')),
            _savedOptionTextField(
              key: 'wash_disinfectant_name',
              label: _th(loc, 'haccp_tbl_disinfect_solution', 'Дез. раствор'),
              options: _presetOptions['wash_disinfectant_name'] ?? const [],
              presetFieldKey: 'wash_disinfectant_name',
            ),
            _textField('wash_disinfectant_concentration_pct',
                _th(loc, 'haccp_tbl_conc_pct', 'Конц.%')),
            _textField('wash_rinsing_temp',
                _th(loc, 'haccp_tbl_rinse_temp', 'Ополаскивание t°'),
                keyboardType: TextInputType.number),
            _signatureFromAccount(),
          ],
        );
      case HaccpLogType.generalCleaningSchedule:
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.generalCleaningSchedule, loc),
          [
            _savedOptionTextField(
              key: 'gen_clean_premises',
              label: _th(loc, 'haccp_tbl_room_zone', 'Помещение / зона'),
              options: _presetOptions['gen_clean_premises'] ?? const [],
              presetFieldKey: 'gen_clean_premises',
            ),
            _datePickerField(
                'gen_clean_date',
                _th(loc, 'haccp_tbl_gen_clean_date', 'Дата проведения'),
                _genCleanDate,
                (d) => setState(() => _genCleanDate = d)),
            _signatureFromAccount(),
            _textField('note', loc.t('haccp_note')),
          ],
        );
      case HaccpLogType.sieveFilterMagnet:
        return _mobileBlock(
          _logTypeTitle(HaccpLogType.sieveFilterMagnet, loc),
          [
            _textField('sieve_no',
                _th(loc, 'haccp_tbl_sieve_magnet_no', '№ сита/магнита')),
            _savedOptionTextField(
              key: 'sieve_name_location',
              label: _th(loc, 'haccp_tbl_name_location',
                  'Наименование / Расположение'),
              options: _presetOptions['sieve_name_location'] ?? const [],
              presetFieldKey: 'sieve_name_location',
            ),
            _savedOptionTextField(
              key: 'sieve_condition',
              label: _th(loc, 'haccp_tbl_condition', 'Состояние'),
              options: _presetOptions['sieve_condition'] ?? const [],
              presetFieldKey: 'sieve_condition',
            ),
            _datePickerField(
                'sieve_cleaning_date',
                _th(loc, 'haccp_tbl_cleaning_date', 'Дата очистки'),
                _sieveCleaningDate,
                (d) => setState(() => _sieveCleaningDate = d)),
            _signatureFromAccount(),
            _textField('sieve_comments',
                _th(loc, 'haccp_tbl_comments', 'Комментарии')),
          ],
        );
      default:
        // Для остальных журналов (пока) оставляем текущую форму; ключевая проблема — горизонтальный скролл контейнера.
        return _buildFormByType(loc, showNameTranslit);
    }
  }

  Future<void> _save() async {
    if (_logType == null) return;
    if (!_formKey.currentState!.validate()) return;

    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t('haccp_establishment_not_selected') ??
                  'Заведение не выбрано')),
        );
      return;
    }
    if (emp == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t('haccp_employee_required') ??
                  'Войдите под учётной записью сотрудника заведения')),
        );
      return;
    }

    final svc = context.read<HaccpLogServiceSupabase>();
    setState(() => _saving = true);
    try {
      switch (_logType!.targetTable) {
        case HaccpLogTable.numeric:
          await _saveNumeric(svc, est.id, emp.id);
          break;
        case HaccpLogTable.status:
          await _saveStatus(svc, est.id, emp.id);
          break;
        case HaccpLogTable.quality:
          await _saveQuality(svc, est.id, emp.id);
          break;
      }
      if (mounted) context.pop({'saved': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${context.read<LocalizationService>().t('error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveNumeric(
      HaccpLogServiceSupabase svc, String estId, String empId) async {
    switch (_logType!) {
      case HaccpLogType.fridgeTemperature:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType!,
          value1: _tempValue,
          equipment:
              _getText('equipment').isNotEmpty ? _getText('equipment') : null,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        await _saveCurrentOption(
          controllerKey: 'equipment',
          fieldKey: 'equipment',
        );
        break;
      case HaccpLogType.warehouseTempHumidity:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType!,
          value1: _tempValue,
          value2: _humidityValue,
          equipment: _getText('warehouse_premises').trim().isNotEmpty
              ? _getText('warehouse_premises').trim()
              : null,
          note: _getText('note').isNotEmpty ? _getText('note') : null,
        );
        await _saveCurrentOption(
          controllerKey: 'warehouse_premises',
          fieldKey: 'warehouse_premises',
        );
        break;
      default:
        throw StateError('Unexpected numeric type: $_logType');
    }
  }

  Future<void> _saveStatus(
      HaccpLogServiceSupabase svc, String estId, String empId) async {
    if (_logType == HaccpLogType.healthHygiene) {
      if (_healthRows.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context
                        .read<LocalizationService>()
                        .t('haccp_add_at_least_one') ??
                    'Добавьте хотя бы одного сотрудника')),
          );
        return;
      }
      final note = _getText('note').isNotEmpty ? _getText('note') : null;
      for (final row in _healthRows) {
        final emp =
            _healthEmployees.where((e) => e.id == row.employeeId).firstOrNull;
        final String? posOverride;
        if (row.positionIsCustom) {
          final t = (row.positionOverride ?? '').trim();
          posOverride = t.isEmpty ? null : t;
        } else {
          final o = (row.positionOverride ?? '').trim();
          if (o.isNotEmpty) {
            posOverride = o;
          } else {
            posOverride =
                (emp != null && emp.roles.isNotEmpty) ? emp.roles.first : null;
          }
        }
        final employeeNameSnapshot =
            emp != null ? employeeFullNameRaw(emp) : null;
        final description = HaccpLog.buildHealthHygieneDescription(
            employeeId: row.employeeId,
            positionOverride: posOverride,
            employeeName: employeeNameSnapshot);
        await svc.insertStatus(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType!,
          statusOk: row.statusOk,
          status2Ok: row.status2Ok,
          description: description,
          note: note,
        );
      }
    } else {
      throw StateError('Unexpected status type: $_logType');
    }
  }

  Future<void> _saveQuality(
      HaccpLogServiceSupabase svc, String estId, String empId) async {
    final loc = context.read<LocalizationService>();
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    final signatureName = emp != null ? employeeFullNameRaw(emp) : null;
    final approvalStr = _logType == HaccpLogType.finishedProductBrakerage &&
            _approvalToSell != null
        ? (_approvalToSell!
            ? loc.t('haccp_approval_allowed')
            : loc.t('haccp_approval_denied'))
        : null;
    final isFryingOil = _logType == HaccpLogType.fryingOil;
    final isFinishedBrakerage =
        _logType == HaccpLogType.finishedProductBrakerage;
    final isMedBook = _logType == HaccpLogType.medBookRegistry;
    final isMedExam = _logType == HaccpLogType.medExaminations;
    final isDisinf = _logType == HaccpLogType.disinfectantAccounting;
    final isWash = _logType == HaccpLogType.equipmentWashing;
    final isGenClean = _logType == HaccpLogType.generalCleaningSchedule;
    final isSieve = _logType == HaccpLogType.sieveFilterMagnet;
    await svc.insertQuality(
      establishmentId: estId,
      createdByEmployeeId: empId,
      logType: _logType!,
      techCardId:
          isFinishedBrakerage ? _selectedFinishedBrakerageTechCardId : null,
      productName: _getText('product').isNotEmpty ? _getText('product') : null,
      result: _getText('result').isNotEmpty ? _getText('result') : null,
      timeBrakerage: _getText('time_brakerage').isNotEmpty
          ? _getText('time_brakerage')
          : null,
      approvalToSell: approvalStr ??
          (_getText('approval_to_sell').isNotEmpty
              ? _getText('approval_to_sell')
              : null),
      commissionSignatures: signatureName,
      weighingResult: _getText('weighing_result').isNotEmpty
          ? _getText('weighing_result')
          : null,
      packaging:
          _getText('packaging').isNotEmpty ? _getText('packaging') : null,
      manufacturerSupplier: _getText('manufacturer_supplier').isNotEmpty
          ? _getText('manufacturer_supplier')
          : null,
      quantityKg: _getNum('quantity_kg'),
      documentNumber: _getText('document_number').isNotEmpty
          ? _getText('document_number')
          : null,
      storageConditions: _getText('storage_conditions').isNotEmpty
          ? _getText('storage_conditions')
          : null,
      dateSold: _dateSold,
      oilName: isFryingOil && _getText('oil_name').isNotEmpty
          ? _getText('oil_name')
          : null,
      organolepticStart:
          isFryingOil && _getText('organoleptic_start').isNotEmpty
              ? _getText('organoleptic_start')
              : null,
      fryingEquipmentType:
          isFryingOil && _getText('frying_equipment_type').isNotEmpty
              ? _getText('frying_equipment_type')
              : null,
      fryingProductType:
          isFryingOil && _getText('frying_product_type').isNotEmpty
              ? _getText('frying_product_type')
              : null,
      fryingEndTime: isFryingOil && _getText('frying_end_time').isNotEmpty
          ? _getText('frying_end_time')
          : null,
      organolepticEnd: isFryingOil && _getText('organoleptic_end').isNotEmpty
          ? _getText('organoleptic_end')
          : null,
      carryOverKg: isFryingOil ? _getNum('carry_over_kg') : null,
      utilizedKg: isFryingOil ? _getNum('utilized_kg') : null,
      medBookEmployeeName:
          isMedBook && _getText('med_book_employee_name').isNotEmpty
              ? _getText('med_book_employee_name')
              : null,
      medBookPosition: isMedBook && _getText('med_book_position').isNotEmpty
          ? _getText('med_book_position')
          : null,
      medBookNumber: isMedBook && _getText('med_book_number').isNotEmpty
          ? _getText('med_book_number')
          : null,
      medBookValidUntil: isMedBook ? _medBookValidUntil : null,
      medBookIssuedAt: isMedBook ? _medBookIssuedAt : null,
      medBookReturnedAt: isMedBook ? _medBookReturnedAt : null,
      medExamEmployeeName:
          isMedExam && _getText('med_exam_employee_name').isNotEmpty
              ? _getText('med_exam_employee_name')
              : null,
      medExamDob: isMedExam && _getText('med_exam_dob').isNotEmpty
          ? _getText('med_exam_dob')
          : null,
      medExamGender: isMedExam && _getText('med_exam_gender').isNotEmpty
          ? _getText('med_exam_gender')
          : null,
      medExamPosition: isMedExam && _getText('med_exam_position').isNotEmpty
          ? _getText('med_exam_position')
          : null,
      medExamDepartment: isMedExam && _getText('med_exam_department').isNotEmpty
          ? _getText('med_exam_department')
          : null,
      medExamHireDate: isMedExam ? _medExamHireDate : null,
      medExamType: isMedExam && _getText('med_exam_type').isNotEmpty
          ? _getText('med_exam_type')
          : null,
      medExamInstitution:
          isMedExam && _getText('med_exam_institution').isNotEmpty
              ? _getText('med_exam_institution')
              : null,
      medExamHarmful1: isMedExam && _getText('med_exam_harmful_1').isNotEmpty
          ? _getText('med_exam_harmful_1')
          : null,
      medExamHarmful2: isMedExam && _getText('med_exam_harmful_2').isNotEmpty
          ? _getText('med_exam_harmful_2')
          : null,
      medExamDate: isMedExam ? _medExamDate : null,
      medExamConclusion: isMedExam && _getText('med_exam_conclusion').isNotEmpty
          ? _getText('med_exam_conclusion')
          : null,
      medExamEmployerDecision:
          isMedExam && _getText('med_exam_employer_decision').isNotEmpty
              ? _getText('med_exam_employer_decision')
              : null,
      medExamNextDate: isMedExam ? _medExamNextDate : null,
      medExamExclusionDate: isMedExam ? _medExamExclusionDate : null,
      disinfObjectName: isDisinf && _getText('disinf_object_name').isNotEmpty
          ? _getText('disinf_object_name')
          : null,
      disinfObjectCount: isDisinf ? _getNum('disinf_object_count') : null,
      disinfAreaSqm: isDisinf ? _getNum('disinf_area_sqm') : null,
      disinfTreatmentType:
          isDisinf && _getText('disinf_treatment_type').isNotEmpty
              ? _getText('disinf_treatment_type')
              : null,
      disinfFrequencyPerMonth: isDisinf ? _getInt('disinf_frequency') : null,
      disinfAgentName: isDisinf &&
              (_getText('disinf_agent_name').isNotEmpty ||
                  _getText('disinf_agent_name_receipt').isNotEmpty)
          ? (_getText('disinf_agent_name').isNotEmpty
              ? _getText('disinf_agent_name')
              : _getText('disinf_agent_name_receipt'))
          : null,
      disinfConcentrationPct:
          isDisinf && _getText('disinf_concentration_pct').isNotEmpty
              ? _getText('disinf_concentration_pct')
              : null,
      disinfConsumptionPerSqm:
          isDisinf ? _getNum('disinf_consumption_per_sqm') : null,
      disinfSolutionPerTreatment:
          isDisinf ? _getNum('disinf_solution_per_treatment') : null,
      disinfNeedPerTreatment:
          isDisinf ? _getNum('disinf_need_per_treatment') : null,
      disinfNeedPerMonth: isDisinf ? _getNum('disinf_need_per_month') : null,
      disinfNeedPerYear: isDisinf ? _getNum('disinf_need_per_year') : null,
      disinfReceiptDate: isDisinf ? _disinfReceiptDate : null,
      disinfInvoiceNumber:
          isDisinf && _getText('disinf_invoice_number').isNotEmpty
              ? _getText('disinf_invoice_number')
              : null,
      disinfQuantity: isDisinf ? _getNum('disinf_quantity') : null,
      disinfExpiryDate: isDisinf ? _disinfExpiryDate : null,
      disinfResponsibleName: isDisinf ? signatureName : null,
      washTime: isWash && _getText('wash_time').isNotEmpty
          ? _getText('wash_time')
          : null,
      washEquipmentName: isWash && _getText('wash_equipment_name').isNotEmpty
          ? _getText('wash_equipment_name')
          : null,
      washSolutionName: isWash && _getText('wash_solution_name').isNotEmpty
          ? _getText('wash_solution_name')
          : null,
      washSolutionConcentrationPct:
          isWash && _getText('wash_solution_concentration_pct').isNotEmpty
              ? _getText('wash_solution_concentration_pct')
              : null,
      washDisinfectantName:
          isWash && _getText('wash_disinfectant_name').isNotEmpty
              ? _getText('wash_disinfectant_name')
              : null,
      washDisinfectantConcentrationPct:
          isWash && _getText('wash_disinfectant_concentration_pct').isNotEmpty
              ? _getText('wash_disinfectant_concentration_pct')
              : null,
      washRinsingTemp: isWash && _getText('wash_rinsing_temp').isNotEmpty
          ? _getText('wash_rinsing_temp')
          : null,
      washControllerSignature: isWash ? signatureName : null,
      genCleanPremises: isGenClean && _getText('gen_clean_premises').isNotEmpty
          ? _getText('gen_clean_premises')
          : null,
      genCleanDate: isGenClean ? _genCleanDate : null,
      genCleanResponsible: isGenClean ? signatureName : null,
      sieveNo: isSieve && _getText('sieve_no').isNotEmpty
          ? _getText('sieve_no')
          : null,
      sieveNameLocation: isSieve && _getText('sieve_name_location').isNotEmpty
          ? _getText('sieve_name_location')
          : null,
      sieveCondition: isSieve && _getText('sieve_condition').isNotEmpty
          ? _getText('sieve_condition')
          : null,
      sieveCleaningDate: isSieve ? _sieveCleaningDate : null,
      sieveSignature: isSieve ? signatureName : null,
      sieveComments: isSieve && _getText('sieve_comments').isNotEmpty
          ? _getText('sieve_comments')
          : null,
      note: _getText('note').isNotEmpty ? _getText('note') : null,
    );
    for (final f in _presetFieldsForCurrentLog()) {
      await _saveCurrentOption(
          controllerKey: f, fieldKey: f, showFeedback: false);
    }
  }

  int? _getInt(String key) {
    final s = _getText(key);
    if (s.isEmpty) return null;
    return int.tryParse(s.replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final showNameTranslit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
    final account = context.watch<AccountManagerSupabase>();
    final config = context.watch<HaccpConfigService>();
    final emp = account.currentEmployee;
    final est = account.establishment;
    final countryCode =
        est != null ? config.resolveCountryCodeForEstablishment(est) : 'RU';
    if (_logType == null) {
      return Scaffold(
        appBar: AppBar(
            leading: appBarBackButton(context),
            title: Text(loc.t('haccp_journals'))),
        body: Center(child: Text(loc.t('error'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(
            '${loc.t('haccp_add_entry')} — ${_logTypeTitle(_logType!, loc)}'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (emp != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(
                    displayStoredPersonName(
                      employeeFullNameRaw(emp),
                      loc,
                      showNameTranslit: showNameTranslit,
                    ),
                  ),
                  subtitle: Text(
                    employeePositionLine(emp, loc,
                        establishment: context
                            .watch<AccountManagerSupabase>()
                            .establishment),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              HaccpCountryProfiles.recommendedSampleLabelTr(
                  countryCode, loc.t),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              HaccpCountryProfiles.journalLegalLineTr(
                  countryCode, _logType!, loc.t),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              HaccpCountryProfiles.legalFrameworkLabel(
                countryCode,
                loc.currentLanguageCode,
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            if (MediaQuery.of(context).size.shortestSide >= 600) ...[
              Text(
                loc.t('haccp_scroll_right_hint') ??
                    'Широкая таблица журнала — при необходимости прокрутите вправо',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1400,
                  child: _buildFormByType(loc, showNameTranslit),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              _buildFormByTypeMobile(loc, showNameTranslit),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
