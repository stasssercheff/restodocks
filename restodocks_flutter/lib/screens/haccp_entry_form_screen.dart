import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import '../models/product.dart';
import '../models/tech_card.dart';
import '../services/services.dart';
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

  @override
  void initState() {
    super.initState();
    if (_logType == HaccpLogType.healthHygiene) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHealthEmployees());
    } else if (_logType == HaccpLogType.finishedProductBrakerage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFinishedBrakerageChoices());
    } else if (_logType == HaccpLogType.medBookRegistry || _logType == HaccpLogType.medExaminations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFormEmployees());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedFieldOptions());
  }

  String _presetStorageKey(String fieldKey) => '${_logType?.code ?? 'unknown'}:$fieldKey';

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
        return const ['oil_name', 'frying_equipment_type', 'frying_product_type'];
      case HaccpLogType.incomingRawBrakerage:
        return const ['manufacturer_supplier', 'storage_conditions', 'packaging'];
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

  static List<String> _mergeUniqueOptions(Iterable<String> a, Iterable<String> b) {
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
      if (mounted) setState(() => _formEmployees = list.where((e) => e.isActive).toList());
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
            _healthRows = _healthEmployees.map((e) => _HealthHygieneRow(
              employeeId: e.id,
              positionOverride: null,
              positionIsCustom: false,
              statusOk: true,
              status2Ok: true,
            )).toList();
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
        if (_logType == HaccpLogType.warehouseTempHumidity && f == 'warehouse_premises') {
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
          content: Text('Вариант сохранён — выберите его из списка (стрелка) при следующей записи'),
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
      final visible = emp == null ? all : all.where((tc) => emp.canSeeTechCard(tc.sections)).toList();
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
                child: Text(e.surname != null ? '${e.surname} ${e.fullName}' : e.fullName),
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
        child: Text(value != null ? DateFormat('dd.MM.yyyy').format(value) : 'Выбрать'),
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

  Widget _textField(String key, String label, {bool multiline = false, TextInputType? keyboardType}) {
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
    _controllers[key] ??= TextEditingController();
    return TextFormField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: showHelperUnderField ? 'Плюс — в список, стрелка — выбрать' : null,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIconConstraints: const BoxConstraints(minWidth: 96, minHeight: 40),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Сохранить в список (этот журнал)',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _saveCurrentOption(
                controllerKey: key,
                fieldKey: presetFieldKey,
                showFeedback: true,
              ),
            ),
            IconButton(
              tooltip: 'Выбрать из сохранённых',
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

  String _finishedBrakerageTypeLabel(LocalizationService loc, {required bool isProduct, required bool isSemiFinished}) {
    if (isProduct) return loc.t('products') ?? 'Продукты';
    if (isSemiFinished) return loc.t('ttk_pf') ?? 'ТТК ПФ';
    return loc.t('ttk_dish') ?? 'Блюдо';
  }

  List<_FinishedBrakerageChoice> _buildFinishedBrakerageChoices(LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    final choices = <_FinishedBrakerageChoice>[
      ..._finishedBrakerageProducts.map((product) {
        final label = product.getLocalizedName(lang);
        return _FinishedBrakerageChoice(
          displayName: label,
          searchTokens: '$label ${product.name} ${product.category}',
          typeLabel: _finishedBrakerageTypeLabel(loc, isProduct: true, isSemiFinished: false),
          productName: label,
        );
      }),
      ..._finishedBrakerageTechCards.map((tc) {
        final label = tc.getDisplayNameInLists(lang);
        return _FinishedBrakerageChoice(
          displayName: label,
          searchTokens: '$label ${tc.dishName} ${tc.category}',
          typeLabel: _finishedBrakerageTypeLabel(loc, isProduct: false, isSemiFinished: tc.isSemiFinished),
          techCardId: tc.id,
          productName: label,
        );
      }),
    ];
    choices.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return choices;
  }

  /// Селектор «Разрешение к реализации»: разрешено / запрещено.
  Widget _approvalSelector() {
    return DropdownButtonFormField<bool>(
      value: _approvalToSell,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      hint: const Text('Выберите'),
      items: const [
        DropdownMenuItem(value: true, child: Text('разрешено')),
        DropdownMenuItem(value: false, child: Text('запрещено')),
      ],
      onChanged: (v) => setState(() => _approvalToSell = v),
    );
  }

  /// Выпадающий список выбора сотрудника (подставляет ФИО/должность в форму).
  Widget _employeeSelectorDropdown({
    required List<Employee> employees,
    required String label,
    required void Function(Employee?) onSelected,
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
        const DropdownMenuItem<Employee?>(value: null, child: Text('— Выбрать из списка —')),
        ...employees.map((e) => DropdownMenuItem<Employee?>(
          value: e,
          child: Text('${e.surname != null ? '${e.surname} ' : ''}${e.fullName} (${e.roleDisplayName})'),
        )),
      ],
      onChanged: (e) => onSelected(e),
    );
  }

  /// Подпись — ФИО сотрудника из учётной записи (только отображение).
  Widget _signatureFromAccount() {
    return Consumer<AccountManagerSupabase>(
      builder: (_, acc, __) {
        final emp = acc.currentEmployee;
        final name = emp != null
            ? (emp.surname != null ? '${emp.surname} ${emp.fullName}' : emp.fullName)
            : '—';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(name, style: const TextStyle(fontSize: 13)),
        );
      },
    );
  }

  static const String _customPositionValue = '__custom_position__';

  /// Список должностей: все из EmployeeRole + уникальные из карточек сотрудников всех подразделений.
  List<String> get _healthPositionOptions {
    final fromRoles = EmployeeRole.values.map((r) => r.displayName).toSet();
    final fromEmployees = _healthEmployees.map((e) => e.roleDisplayName).where((s) => s.isNotEmpty).toSet();
    final combined = [...fromRoles, ...fromEmployees.where((s) => !fromRoles.contains(s))]..sort();
    return combined;
  }

  Employee? _healthEmployeeById(String id) => _healthEmployees.cast<Employee?>().firstWhere((e) => e?.id == id, orElse: () => null);

  String _healthPositionDisplayForRow(_HealthHygieneRow row) {
    final emp = _healthEmployeeById(row.employeeId);
    if (row.positionIsCustom && row.positionOverride != null && row.positionOverride!.isNotEmpty) return row.positionOverride!;
    return emp?.roleDisplayName ?? '';
  }

  Widget _healthPositionDropdownForRow(int index) {
    final row = _healthRows[index];
    final positionOptions = _healthPositionOptions;
    final currentDisplay = _healthPositionDisplayForRow(row);
    final effectiveValue = row.positionIsCustom
        ? _customPositionValue
        : (positionOptions.contains(currentDisplay) ? currentDisplay : (positionOptions.isNotEmpty ? positionOptions.first : _customPositionValue));
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: effectiveValue,
        isExpanded: true,
        isDense: true,
        items: [
          ...positionOptions.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))),
          DropdownMenuItem(
            value: _customPositionValue,
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(row.positionIsCustom && (row.positionOverride ?? '').isNotEmpty ? 'Свой вариант: ${row.positionOverride}' : 'Свой вариант', overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
        onChanged: (v) async {
          if (v == _customPositionValue) {
            final text = await _showCustomPositionDialog(initial: row.positionOverride);
            if (text != null && mounted) setState(() {
              row.positionOverride = text;
              row.positionIsCustom = true;
            });
            return;
          }
          if (v != null) setState(() {
            row.positionOverride = v;
            row.positionIsCustom = false;
          });
        },
      ),
    );
  }

  Future<String?> _showCustomPositionDialog({String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Должность (свой вариант)'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Введите название должности',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
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
    final title = controller.text.isNotEmpty ? controller.text : (loc.t('haccp_product') ?? 'Продукция / Сырьё');
    return InkWell(
      onTap: () async {
        if (_finishedBrakerageTechCards.isEmpty && _finishedBrakerageProducts.isEmpty) {
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
                      .where((item) => item.searchTokens.toLowerCase().contains(q))
                      .toList();
            }
            applyFilter();
            return StatefulBuilder(
              builder: (ctx, setStateDialog) {
                return AlertDialog(
                  title: Text(loc.t('haccp_product') ?? 'Наименование блюда'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: searchCtrl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: loc.t('search') ?? 'Поиск',
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
                              ? Text(loc.t('no_results') ?? 'Ничего не найдено')
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
                      child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
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
          labelText: loc.t('haccp_product') ?? 'Продукция / Сырьё',
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
  Widget _buildHealthHygieneForm(LocalizationService loc) {
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
    final currentEmp = context.watch<AccountManagerSupabase>().currentEmployee;
    final creatorName = currentEmp != null
        ? (currentEmp.surname != null ? '${currentEmp.surname} ${currentEmp.fullName}' : currentEmp.fullName)
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
                _tableHeaderCell('№ п/п'),
                _tableHeaderCell('Дата'),
                _tableHeaderCell('Ф. И. О. работника (последнее при наличии)'),
                _tableHeaderCell('Должность'),
                _tableHeaderCell('Подпись сотрудника об отсутствии признаков инфекционных заболеваний у сотрудника и членов семьи'),
                _tableHeaderCell('Подпись сотрудника об отсутствии заболеваний верхних дыхательных путей и гнойничковых заболеваний кожи рук и открытых поверхностей тела'),
                _tableHeaderCell('Результат осмотра медицинским работником (ответственным лицом) (допущен / отстранен)'),
                _tableHeaderCell('Подпись медицинского работника (ответственного лица)'),
                _tableHeaderCell(''),
              ],
            ),
            ...List.generate(_healthRows.length, (i) {
              final row = _healthRows[i];
              final emp = _healthEmployeeById(row.employeeId);
              final name = emp != null ? (emp.surname != null ? '${emp.surname} ${emp.fullName}' : emp.fullName) : '—';
              return TableRow(
                children: [
                  _tableCell(Text('${i + 1}')),
                  _tableCell(Text(dateStr)),
                  _tableCell(Text(name)),
                  _tableCell(_healthPositionDropdownForRow(i)),
                  _tableCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(value: row.statusOk, onChanged: (v) => setState(() => row.statusOk = v ?? true)),
                      Text(row.statusOk ? 'Да' : 'Нет', style: TextStyle(fontSize: 12, color: row.statusOk ? Colors.green : Colors.orange)),
                    ],
                  )),
                  _tableCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(value: row.status2Ok, onChanged: (v) => setState(() => row.status2Ok = v ?? true)),
                      Text(row.status2Ok ? 'Да' : 'Нет', style: TextStyle(fontSize: 12, color: row.status2Ok ? Colors.green : Colors.orange)),
                    ],
                  )),
                  _tableCell(Text(row.statusOk ? 'допущен' : 'отстранен', style: const TextStyle(fontSize: 12))),
                  _tableCell(Text(creatorName, style: const TextStyle(fontSize: 11))),
                  _tableCell(IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                    onPressed: () => setState(() => _healthRows.removeAt(i)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
            final available = _healthEmployees.where((e) => !usedIds.contains(e.id)).toList();
            if (available.isEmpty) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.t('haccp_all_employees_added') ?? 'Все сотрудники уже добавлены')),
              );
              return;
            }
            final picked = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(loc.t('haccp_add_employee_row') ?? 'Добавить сотрудника'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: available.map((e) {
                      final name = e.surname != null ? '${e.surname} ${e.fullName}' : e.fullName;
                      return ListTile(
                        title: Text(name),
                        subtitle: Text(e.roleDisplayName),
                        onTap: () => Navigator.of(ctx).pop(e.id),
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
            if (picked != null && mounted) setState(() {
              _healthRows.add(_HealthHygieneRow(employeeId: picked, positionOverride: null, positionIsCustom: false, statusOk: true, status2Ok: true));
            });
          },
          icon: const Icon(Icons.add),
          label: Text(loc.t('haccp_add_row') ?? 'Добавить строку'),
        ),
        const SizedBox(height: 8),
        _textField('note', loc.t('haccp_note') ?? 'Примечание'),
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
            _tableHeaderCell('Наименование производственного помещения'),
            _tableHeaderCell('Наименование холодильного оборудования'),
            _tableHeaderCell('Температура °C'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Consumer<AccountManagerSupabase>(
              builder: (_, acc, __) => Text(acc.establishment?.name ?? '—'),
            )),
            _tableCell(_savedOptionTextField(
              key: 'equipment',
              label: loc.t('haccp_equipment') ?? 'Оборудование',
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
            label: loc.t('haccp_warehouse_premises') ?? 'Наименование складского помещения',
            hintText: 'Например: Склад сухих продуктов, Овощной цех',
            options: _presetOptions['warehouse_premises'] ?? const [],
            presetFieldKey: 'warehouse_premises',
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Укажите помещение';
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
                _tableHeaderCell('№ п/п'),
                _tableHeaderCell('Дата'),
                _tableHeaderCell('Температура, °C'),
                _tableHeaderCell('Относительная влажность, %'),
                _tableHeaderCell('Подпись ответственного лица'),
              ],
            ),
            TableRow(
              children: [
                _tableCell(const Text('1')),
                _tableCell(Text(DateFormat('dd.MM.yyyy').format(DateTime.now()))),
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
            _tableHeaderCell('Дата и час изготовления блюда'),
            _tableHeaderCell('Время снятия бракеража'),
            _tableHeaderCell('Наименование готового блюда'),
            _tableHeaderCell('Результаты органолептической оценки'),
            _tableHeaderCell('Разрешение к реализации'),
            _tableHeaderCell('Подписи членов бракеражной комиссии'),
            _tableHeaderCell('Результаты взвешивания порционных блюд'),
            _tableHeaderCell('Примечание'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Text(DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()))),
            _tableCell(_textField('time_brakerage', 'Время (например 12:00)')),
            _tableCell(_finishedProductPickerCell(loc)),
            _tableCell(_textField('result', loc.t('haccp_result') ?? 'Результат оценки', multiline: true)),
            _tableCell(_approvalSelector()),
            _tableCell(_signatureFromAccount()),
            _tableCell(_textField('weighing_result', 'Взвешивание')),
            _tableCell(_textField('note', loc.t('haccp_note') ?? 'Примечание')),
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
            _tableHeaderCell('Дата и час поступления'),
            _tableHeaderCell('Наименование'),
            _tableHeaderCell('Фасовка'),
            _tableHeaderCell('Изготовитель/поставщик'),
            _tableHeaderCell('Кол-во'),
            _tableHeaderCell('№ документа'),
            _tableHeaderCell('Органолептическая оценка'),
            _tableHeaderCell('Условия хранения, срок реализации'),
            _tableHeaderCell('Дата реализации'),
            _tableHeaderCell('Подпись'),
            _tableHeaderCell('Прим.'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Text(DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()))),
            _tableCell(_textField('product', loc.t('haccp_product') ?? 'Наименование')),
            _tableCell(_savedOptionTextField(
              key: 'packaging',
              label: 'Фасовка',
              options: _presetOptions['packaging'] ?? const [],
              presetFieldKey: 'packaging',
            )),
            _tableCell(_savedOptionTextField(
              key: 'manufacturer_supplier',
              label: 'Изготовитель/поставщик',
              options: _presetOptions['manufacturer_supplier'] ?? const [],
              presetFieldKey: 'manufacturer_supplier',
            )),
            _tableCell(_textField('quantity_kg', 'кг/л/шт', keyboardType: TextInputType.number)),
            _tableCell(_textField('document_number', '№ док.')),
            _tableCell(_textField('result', loc.t('haccp_result') ?? 'Оценка', multiline: true)),
            _tableCell(_savedOptionTextField(
              key: 'storage_conditions',
              label: 'Условия, срок',
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
              child: Text(_dateSold != null ? DateFormat('dd.MM.yyyy').format(_dateSold!) : 'Выбрать'),
            )),
            _tableCell(_signatureFromAccount()),
            _tableCell(_textField('note', loc.t('haccp_note') ?? 'Прим.')),
          ],
        ),
      ],
    );
  }

  /// Форма по бланку: Журнал учёта личных медицинских книжек (1:1 с бумагой).
  Widget _buildMedBookForm(LocalizationService loc) {
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
            _tableHeaderCell('№ п/п'),
            _tableHeaderCell('Фамилия, имя, отчество'),
            _tableHeaderCell('Должность'),
            _tableHeaderCell('Номер медицинской книжки'),
            _tableHeaderCell('Срок действия медицинской книжки'),
            _tableHeaderCell('Расписка и дата получения медицинской книжки'),
            _tableHeaderCell('Расписка и дата возврата медицинской книжки'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(const Text('1')),
            _tableCell(Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _employeeSelectorDropdown(
                  employees: _formEmployees,
                  label: 'Сотрудник',
                  onSelected: (e) {
                    if (e != null) {
                      _setText('med_book_employee_name', e.surname != null ? '${e.surname} ${e.fullName}' : e.fullName);
                      _setText('med_book_position', e.roleDisplayName);
                      setState(() {});
                    }
                  },
                ),
                _textField('med_book_employee_name', 'Ф. И. О.'),
              ],
            )),
            _tableCell(_textField('med_book_position', 'Должность')),
            _tableCell(_textField('med_book_number', 'Номер медкнижки')),
            _tableCell(InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _medBookValidUntil ?? DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (d != null) setState(() => _medBookValidUntil = d);
              },
              child: Text(_medBookValidUntil != null ? DateFormat('dd.MM.yyyy').format(_medBookValidUntil!) : 'Выбрать дату'),
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
                  child: Text(_medBookIssuedAt != null ? DateFormat('dd.MM.yyyy').format(_medBookIssuedAt!) : 'Дата получения'),
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
                  child: Text(_medBookReturnedAt != null ? DateFormat('dd.MM.yyyy').format(_medBookReturnedAt!) : 'Дата возврата'),
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
            _tableHeaderCell('Дата'),
            _tableHeaderCell('Время начала использования жира'),
            _tableHeaderCell('Вид фритюрного жира'),
            _tableHeaderCell('Органолептическая оценка на начало жарки'),
            _tableHeaderCell('Тип жарочного оборудования'),
            _tableHeaderCell('Вид продукции'),
            _tableHeaderCell('Время окончания жарки'),
            _tableHeaderCell('Органолептическая оценка по окончании жарки'),
            _tableHeaderCell('Переходящий остаток, кг'),
            _tableHeaderCell('Утилизированный жир, кг'),
            _tableHeaderCell('Должность, Ф.И.О. контролера'),
          ],
        ),
        TableRow(
          children: [
            _tableCell(Text(DateFormat('dd.MM.yyyy').format(DateTime.now()))),
            _tableCell(Text(DateFormat('HH:mm').format(DateTime.now()))),
            _tableCell(_savedOptionTextField(
              key: 'oil_name',
              label: 'Вид жира',
              options: _presetOptions['oil_name'] ?? const [],
              presetFieldKey: 'oil_name',
            )),
            _tableCell(_textField('organoleptic_start', 'Оценка на начало', multiline: true)),
            _tableCell(_savedOptionTextField(
              key: 'frying_equipment_type',
              label: 'Тип оборудования',
              options: _presetOptions['frying_equipment_type'] ?? const [],
              presetFieldKey: 'frying_equipment_type',
            )),
            _tableCell(_savedOptionTextField(
              key: 'frying_product_type',
              label: 'Вид продукции',
              options: _presetOptions['frying_product_type'] ?? const [],
              presetFieldKey: 'frying_product_type',
            )),
            _tableCell(_textField('frying_end_time', 'Время (например 14:00)')),
            _tableCell(_textField('organoleptic_end', 'Оценка по окончании', multiline: true)),
            _tableCell(_textField('carry_over_kg', 'кг', keyboardType: TextInputType.number)),
            _tableCell(_textField('utilized_kg', 'кг', keyboardType: TextInputType.number)),
            _tableCell(_signatureFromAccount()),
          ],
        ),
      ],
    );
  }

  Widget _buildMedExaminationsForm(LocalizationService loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Данные работника', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _employeeSelectorDropdown(
            employees: _formEmployees,
            label: 'Сотрудник',
            onSelected: (e) {
              if (e != null) {
                _setText('med_exam_employee_name', e.surname != null ? '${e.surname} ${e.fullName}' : e.fullName);
                _setText('med_exam_dob', e.birthday != null ? DateFormat('dd.MM.yyyy').format(e.birthday!) : '');
                _setText('med_exam_position', e.roleDisplayName);
                _setText('med_exam_department', e.employeeDepartment?.displayName ?? e.department);
                setState(() {});
              }
            },
          ),
        ),
        Table(
          columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [_tableHeaderCell('Ф. И. О.'), _tableHeaderCell('Возраст (дата рождения)')]),
            TableRow(children: [_tableCell(_textField('med_exam_employee_name', 'Ф. И. О.')), _tableCell(_textField('med_exam_dob', 'Дата рождения'))]),
            TableRow(children: [_tableHeaderCell('Пол'), _tableHeaderCell('Должность')]),
            TableRow(children: [_tableCell(_textField('med_exam_gender', 'Пол')), _tableCell(_textField('med_exam_position', 'Должность'))]),
            TableRow(children: [_tableHeaderCell('Структурное подразделение'), _tableHeaderCell('Дата приёма на работу')]),
            TableRow(children: [
              _tableCell(_textField('med_exam_department', 'Подразделение')),
              _tableCell(_datePickerCell('med_exam_hire_date', _medExamHireDate, (d) => setState(() => _medExamHireDate = d))),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        Text('Медицинский осмотр', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [_tableHeaderCell('Вид (предварительный/периодический)'), _tableHeaderCell('ЛПУ')]),
            TableRow(children: [_tableCell(_textField('med_exam_type', 'Вид')), _tableCell(_textField('med_exam_institution', 'Лечебное учреждение'))]),
            TableRow(children: [_tableHeaderCell('Вредный фактор №90'), _tableHeaderCell('Вредный фактор №83')]),
            TableRow(children: [_tableCell(_textField('med_exam_harmful_1', '№ по приказу 90')), _tableCell(_textField('med_exam_harmful_2', '№ по приказу 83'))]),
            TableRow(children: [_tableHeaderCell('Дата прохождения'), _tableHeaderCell('Заключение')]),
            TableRow(children: [
              _tableCell(_datePickerCell('med_exam_date', _medExamDate, (d) => setState(() => _medExamDate = d))),
              _tableCell(_textField('med_exam_conclusion', 'Заключение')),
            ]),
            TableRow(children: [_tableHeaderCell('Решение работодателя'), _tableHeaderCell('Дата следующего осмотра')]),
            TableRow(children: [
              _tableCell(_textField('med_exam_employer_decision', 'Допущен/отстранён/переведён/уволен')),
              _tableCell(_datePickerCell('med_exam_next_date', _medExamNextDate, (d) => setState(() => _medExamNextDate = d))),
            ]),
            TableRow(children: [_tableHeaderCell('Дата исключения из списков'), _tableHeaderCell('Примечание')]),
            TableRow(children: [
              _tableCell(_datePickerCell('med_exam_exclusion_date', _medExamExclusionDate, (d) => setState(() => _medExamExclusionDate = d))),
              _tableCell(_textField('med_exam_note', 'Примечание')),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _datePickerCell(String key, DateTime? value, void Function(DateTime) onDate) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 3650)));
        if (d != null) onDate(d);
      },
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), child: Text(value != null ? DateFormat('dd.MM.yyyy').format(value) : 'Выбрать дату')),
    );
  }

  Widget _buildDisinfectantAccountingForm(LocalizationService loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Расчёт потребности в дезинфицирующих средствах', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(0.6), 1: FlexColumnWidth(0.8), 2: FlexColumnWidth(0.5), 3: FlexColumnWidth(0.5),
              4: FlexColumnWidth(0.4), 5: FlexColumnWidth(0.5), 6: FlexColumnWidth(0.6), 7: FlexColumnWidth(0.5),
              8: FlexColumnWidth(0.5), 9: FlexColumnWidth(0.5), 10: FlexColumnWidth(0.5), 11: FlexColumnWidth(0.5), 12: FlexColumnWidth(0.5),
            },
            border: TableBorder.all(color: Theme.of(context).dividerColor),
            children: [
              TableRow(children: [
                _tableHeaderCell('Объект'), _tableHeaderCell('Кол-во'), _tableHeaderCell('Площадь м²'), _tableHeaderCell('Вид Т/Г'),
                _tableHeaderCell('Кратность/мес'), _tableHeaderCell('Дезсредство'), _tableHeaderCell('Конц.%'), _tableHeaderCell('Расход/м²'),
                _tableHeaderCell('Раствор на 1 обр.'), _tableHeaderCell('Потребность 1 обр.'), _tableHeaderCell('В месяц'), _tableHeaderCell('В год'),
              ]),
              TableRow(children: [
                _tableCell(_savedOptionTextField(
                  key: 'disinf_object_name',
                  label: 'Объект',
                  options: _presetOptions['disinf_object_name'] ?? const [],
                  presetFieldKey: 'disinf_object_name',
                )),
                _tableCell(_textField('disinf_object_count', 'Кол-во', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_area_sqm', 'м²', keyboardType: TextInputType.number)),
                _tableCell(_savedOptionTextField(
                  key: 'disinf_treatment_type',
                  label: 'Т/Г',
                  options: _presetOptions['disinf_treatment_type'] ?? const [],
                  presetFieldKey: 'disinf_treatment_type',
                )),
                _tableCell(_textField('disinf_frequency', 'Кратность', keyboardType: TextInputType.number)),
                _tableCell(_savedOptionTextField(
                  key: 'disinf_agent_name',
                  label: 'Дезсредство',
                  options: _presetOptions['disinf_agent_name'] ?? const [],
                  presetFieldKey: 'disinf_agent_name',
                )),
                _tableCell(_textField('disinf_concentration_pct', '%')),
                _tableCell(_textField('disinf_consumption_per_sqm', 'Расход', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_solution_per_treatment', 'л/кг', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_need_per_treatment', 'л/кг', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_need_per_month', 'л/кг', keyboardType: TextInputType.number)),
                _tableCell(_textField('disinf_need_per_year', 'л/кг', keyboardType: TextInputType.number)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Поступление дезинфицирующих средств', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {0: FlexColumnWidth(0.5), 1: FlexColumnWidth(1), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(0.6), 4: FlexColumnWidth(0.6), 5: FlexColumnWidth(1)},
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(children: [_tableHeaderCell('Дата'), _tableHeaderCell('Наименование'), _tableHeaderCell('Счёт, дата'), _tableHeaderCell('Кол-во'), _tableHeaderCell('Срок годности'), _tableHeaderCell('Ответственный')]),
            TableRow(children: [
              _tableCell(_datePickerCell('disinf_receipt_date', _disinfReceiptDate, (d) => setState(() => _disinfReceiptDate = d))),
              _tableCell(_savedOptionTextField(
                key: 'disinf_agent_name_receipt',
                label: 'Наименование',
                options: _presetOptions['disinf_agent_name_receipt'] ?? const [],
                presetFieldKey: 'disinf_agent_name_receipt',
              )),
              _tableCell(_textField('disinf_invoice_number', '№ счёта')),
              _tableCell(_textField('disinf_quantity', 'Кол-во', keyboardType: TextInputType.number)),
              _tableCell(_datePickerCell('disinf_expiry_date', _disinfExpiryDate, (d) => setState(() => _disinfExpiryDate = d))),
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
        0: FlexColumnWidth(0.6), 1: FlexColumnWidth(0.5), 2: FlexColumnWidth(1.35), 3: FlexColumnWidth(1.1), 4: FlexColumnWidth(0.5),
        5: FlexColumnWidth(0.9), 6: FlexColumnWidth(0.5), 7: FlexColumnWidth(0.5), 8: FlexColumnWidth(0.8), 9: FlexColumnWidth(0.8),
      },
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [
          _tableHeaderCell('Дата'), _tableHeaderCell('Время мойки'), _tableHeaderCell('Оборудование'), _tableHeaderCell('Моющий раствор'),
          _tableHeaderCell('Конц.%'), _tableHeaderCell('Дез. раствор'), _tableHeaderCell('Конц.%'), _tableHeaderCell('Ополаскивание t°'),
          _tableHeaderCell('Ф.И.О. мойщика'), _tableHeaderCell('Контроль'),
        ]),
        TableRow(children: [
          _tableCell(Text(DateFormat('dd.MM.yyyy').format(DateTime.now()))),
          _tableCell(_textField('wash_time', 'Время')),
          _tableCell(_savedOptionTextField(
            key: 'wash_equipment_name',
            label: 'Оборудование',
            options: _presetOptions['wash_equipment_name'] ?? const [],
            presetFieldKey: 'wash_equipment_name',
          )),
          _tableCell(_savedOptionTextField(
            key: 'wash_solution_name',
            label: 'Моющее',
            options: _presetOptions['wash_solution_name'] ?? const [],
            presetFieldKey: 'wash_solution_name',
          )),
          _tableCell(_textField('wash_solution_concentration_pct', '%')),
          _tableCell(_savedOptionTextField(
            key: 'wash_disinfectant_name',
            label: 'Дез. раствор',
            options: _presetOptions['wash_disinfectant_name'] ?? const [],
            presetFieldKey: 'wash_disinfectant_name',
          )),
          _tableCell(_textField('wash_disinfectant_concentration_pct', '%')),
          _tableCell(_textField('wash_rinsing_temp', 't°')),
          _tableCell(_signatureFromAccount()),
          _tableCell(_signatureFromAccount()),
        ]),
      ],
    );
  }

  Widget _buildGeneralCleaningForm(LocalizationService loc) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(0.5), 1: FlexColumnWidth(1.5), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [_tableHeaderCell('№'), _tableHeaderCell('Помещение / зона'), _tableHeaderCell('Дата проведения'), _tableHeaderCell('Ответственный')]),
        TableRow(children: [
          _tableCell(const Text('1')),
          _tableCell(_savedOptionTextField(
            key: 'gen_clean_premises',
            label: 'Помещение',
            options: _presetOptions['gen_clean_premises'] ?? const [],
            presetFieldKey: 'gen_clean_premises',
          )),
          _tableCell(_datePickerCell('gen_clean_date', _genCleanDate, (d) => setState(() => _genCleanDate = d))),
          _tableCell(_signatureFromAccount()),
        ]),
      ],
    );
  }

  Widget _buildSieveFilterMagnetForm(LocalizationService loc) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(0.5), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(0.8), 4: FlexColumnWidth(0.8), 5: FlexColumnWidth(0.8)},
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        TableRow(children: [_tableHeaderCell('№ сита/магнита'), _tableHeaderCell('Наименование / Расположение'), _tableHeaderCell('Состояние'), _tableHeaderCell('Дата очистки'), _tableHeaderCell('ФИО, Подпись'), _tableHeaderCell('Комментарии')]),
        TableRow(children: [
          _tableCell(_textField('sieve_no', '№')),
          _tableCell(_savedOptionTextField(
            key: 'sieve_name_location',
            label: 'Наименование',
            options: _presetOptions['sieve_name_location'] ?? const [],
            presetFieldKey: 'sieve_name_location',
          )),
          _tableCell(_savedOptionTextField(
            key: 'sieve_condition',
            label: 'Состояние',
            options: _presetOptions['sieve_condition'] ?? const [],
            presetFieldKey: 'sieve_condition',
          )),
          _tableCell(_datePickerCell('sieve_cleaning_date', _sieveCleaningDate, (d) => setState(() => _sieveCleaningDate = d))),
          _tableCell(_signatureFromAccount()),
          _tableCell(_textField('sieve_comments', 'Комментарии')),
        ]),
      ],
    );
  }

  Widget _buildFormByType(LocalizationService loc) {
    switch (_logType) {
      case HaccpLogType.healthHygiene:
        return _buildHealthHygieneForm(loc);
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
        return _buildMedBookForm(loc);
      case HaccpLogType.medExaminations:
        return _buildMedExaminationsForm(loc);
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
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...children.expand((w) => [w, const SizedBox(height: 10)]).toList()..removeLast(),
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
            Text('${value.toStringAsFixed(fractionDigits)} $unit', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
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

  Widget _buildFormByTypeMobile(LocalizationService loc) {
    switch (_logType) {
      case HaccpLogType.healthHygiene:
        final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
        final currentEmp = context.watch<AccountManagerSupabase>().currentEmployee;
        final creatorName = currentEmp != null
            ? (currentEmp.surname != null ? '${currentEmp.surname} ${currentEmp.fullName}' : currentEmp.fullName)
            : '—';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...List.generate(_healthRows.length, (i) {
              final row = _healthRows[i];
              final emp = _healthEmployeeById(row.employeeId);
              final name = emp != null ? (emp.surname != null ? '${emp.surname} ${emp.fullName}' : emp.fullName) : '—';
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
                            child: Text('$name · $dateStr', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _healthRows.removeAt(i)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _healthPositionDropdownForRow(i),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Нет признаков инфекционных заболеваний (у сотрудника и семьи)'),
                        value: row.statusOk,
                        onChanged: (v) => setState(() => row.statusOk = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Нет заболеваний ВДП и гнойничковых заболеваний кожи'),
                        value: row.status2Ok,
                        onChanged: (v) => setState(() => row.status2Ok = v),
                      ),
                      const Divider(),
                      Text('Результат: ${row.statusOk ? 'допущен' : 'отстранён'}', style: const TextStyle(fontSize: 12)),
                      Text('Ответственный: $creatorName', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () async {
                final usedIds = _healthRows.map((r) => r.employeeId).toSet();
                final available = _healthEmployees.where((e) => !usedIds.contains(e.id)).toList();
                if (available.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(loc.t('haccp_all_employees_added') ?? 'Все сотрудники уже добавлены')),
                  );
                  return;
                }
                final picked = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(loc.t('haccp_add_employee_row') ?? 'Добавить сотрудника'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: available.map((e) {
                          final name = e.surname != null ? '${e.surname} ${e.fullName}' : e.fullName;
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(e.roleDisplayName),
                            onTap: () => Navigator.of(ctx).pop(e.id),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
                if (picked != null && mounted) setState(() {
                  _healthRows.add(_HealthHygieneRow(employeeId: picked, positionOverride: null, positionIsCustom: false, statusOk: true, status2Ok: true));
                });
              },
              icon: const Icon(Icons.add),
              label: Text(loc.t('haccp_add_row') ?? 'Добавить строку'),
            ),
            const SizedBox(height: 10),
            _textField('note', loc.t('haccp_note') ?? 'Примечание'),
          ],
        );
      case HaccpLogType.fridgeTemperature:
        return _mobileBlock(
          loc.t(HaccpLogType.fridgeTemperature.displayNameKey) ?? HaccpLogType.fridgeTemperature.displayNameRu,
          [
            Consumer<AccountManagerSupabase>(
              builder: (_, acc, __) => TextFormField(
                initialValue: acc.establishment?.name ?? '—',
                decoration: const InputDecoration(
                  labelText: 'Наименование производственного помещения',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                readOnly: true,
              ),
            ),
            _savedOptionTextField(
              key: 'equipment',
              label: loc.t('haccp_equipment') ?? 'Оборудование',
              options: _presetOptions['equipment'] ?? const [],
              presetFieldKey: 'equipment',
            ),
            _mobileSlider(
              label: 'Температура',
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
              loc.t(HaccpLogType.warehouseTempHumidity.displayNameKey) ?? HaccpLogType.warehouseTempHumidity.displayNameRu,
              [
                _savedOptionTextField(
                  key: 'warehouse_premises',
                  label: loc.t('haccp_warehouse_premises') ?? 'Наименование складского помещения',
                  options: _presetOptions['warehouse_premises'] ?? const [],
                  presetFieldKey: 'warehouse_premises',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажите помещение' : null,
                ),
                _mobileSlider(
                  label: 'Температура',
                  value: _tempValue,
                  min: -5,
                  max: 35,
                  divisions: 800,
                  unit: '°C',
                  onChanged: (v) => _tempValue = v,
                  fractionDigits: 1,
                ),
                _mobileSlider(
                  label: 'Относительная влажность',
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
          loc.t(HaccpLogType.finishedProductBrakerage.displayNameKey) ?? HaccpLogType.finishedProductBrakerage.displayNameRu,
          [
            TextFormField(
              initialValue: DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
              decoration: const InputDecoration(labelText: 'Дата и час изготовления блюда', border: OutlineInputBorder(), isDense: true),
              readOnly: true,
            ),
            _textField('time_brakerage', 'Время снятия бракеража (например 12:00)'),
            _finishedProductPickerCell(loc),
            _textField('result', loc.t('haccp_result') ?? 'Результаты органолептической оценки', multiline: true),
            _approvalSelector(),
            _signatureFromAccount(),
            _textField('weighing_result', 'Результаты взвешивания порционных блюд'),
            _textField('note', loc.t('haccp_note') ?? 'Примечание'),
          ],
        );
      case HaccpLogType.incomingRawBrakerage:
        return _mobileBlock(
          loc.t(HaccpLogType.incomingRawBrakerage.displayNameKey) ?? HaccpLogType.incomingRawBrakerage.displayNameRu,
          [
            TextFormField(
              initialValue: DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
              decoration: const InputDecoration(labelText: 'Дата и час поступления', border: OutlineInputBorder(), isDense: true),
              readOnly: true,
            ),
            _textField('product', loc.t('haccp_product') ?? 'Наименование'),
            _savedOptionTextField(
              key: 'packaging',
              label: 'Фасовка',
              options: _presetOptions['packaging'] ?? const [],
              presetFieldKey: 'packaging',
            ),
            _savedOptionTextField(
              key: 'manufacturer_supplier',
              label: 'Изготовитель/поставщик',
              options: _presetOptions['manufacturer_supplier'] ?? const [],
              presetFieldKey: 'manufacturer_supplier',
            ),
            _textField('quantity_kg', 'Кол-во (кг/л/шт)', keyboardType: TextInputType.number),
            _textField('document_number', '№ документа'),
            _textField('result', loc.t('haccp_result') ?? 'Органолептическая оценка', multiline: true),
            _savedOptionTextField(
              key: 'storage_conditions',
              label: 'Условия хранения, срок реализации',
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
                decoration: const InputDecoration(labelText: 'Дата реализации', border: OutlineInputBorder(), isDense: true),
                child: Text(_dateSold != null ? DateFormat('dd.MM.yyyy').format(_dateSold!) : 'Выбрать'),
              ),
            ),
            _signatureFromAccount(),
            _textField('note', loc.t('haccp_note') ?? 'Примечание'),
          ],
        );
      case HaccpLogType.fryingOil:
        // Те же поля, что и в табличной форме (СанПиН), чтобы сохранение в БД и пресеты совпадали с десктопом.
        return _mobileBlock(
          loc.t(HaccpLogType.fryingOil.displayNameKey) ?? HaccpLogType.fryingOil.displayNameRu,
          [
            TextFormField(
              initialValue: DateFormat('dd.MM.yyyy').format(DateTime.now()),
              decoration: const InputDecoration(labelText: 'Дата', border: OutlineInputBorder(), isDense: true),
              readOnly: true,
            ),
            TextFormField(
              initialValue: DateFormat('HH:mm').format(DateTime.now()),
              decoration: const InputDecoration(
                labelText: 'Время начала использования жира',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              readOnly: true,
            ),
            _savedOptionTextField(
              key: 'oil_name',
              label: 'Вид фритюрного жира',
              options: _presetOptions['oil_name'] ?? const [],
              presetFieldKey: 'oil_name',
            ),
            _textField('organoleptic_start', 'Органолептика на начало жарки', multiline: true),
            _savedOptionTextField(
              key: 'frying_equipment_type',
              label: 'Тип жарочного оборудования',
              options: _presetOptions['frying_equipment_type'] ?? const [],
              presetFieldKey: 'frying_equipment_type',
            ),
            _savedOptionTextField(
              key: 'frying_product_type',
              label: 'Вид продукции',
              options: _presetOptions['frying_product_type'] ?? const [],
              presetFieldKey: 'frying_product_type',
            ),
            _textField('frying_end_time', 'Время окончания жарки (например 14:00)'),
            _textField('organoleptic_end', 'Органолептика по окончании жарки', multiline: true),
            _textField('carry_over_kg', 'Переходящий остаток, кг', keyboardType: TextInputType.number),
            _textField('utilized_kg', 'Утилизированный жир, кг', keyboardType: TextInputType.number),
            _signatureFromAccount(),
            _textField('note', loc.t('haccp_note') ?? 'Примечание'),
          ],
        );
      case HaccpLogType.medBookRegistry:
        return _mobileBlock(
          loc.t(HaccpLogType.medBookRegistry.displayNameKey) ?? HaccpLogType.medBookRegistry.displayNameRu,
          [
            _employeePickerField('med_book_employee_id', 'Сотрудник', _medBookEmployeeId, (id) => setState(() => _medBookEmployeeId = id)),
            _textField('med_book_position', 'Должность'),
            _textField('med_book_number', 'Номер медицинской книжки'),
            _datePickerField('med_book_expiry_date', 'Срок действия', _medBookExpiryDate, (d) => setState(() => _medBookExpiryDate = d)),
            _datePickerField('med_book_received_date', 'Получение (дата)', _medBookReceivedDate, (d) => setState(() => _medBookReceivedDate = d)),
            _datePickerField('med_book_returned_date', 'Возврат (дата)', _medBookReturnedDate, (d) => setState(() => _medBookReturnedDate = d)),
          ],
        );
      case HaccpLogType.medExaminations:
        return _mobileBlock(
          loc.t(HaccpLogType.medExaminations.displayNameKey) ?? HaccpLogType.medExaminations.displayNameRu,
          [
            _employeePickerField('med_exam_employee_id', 'Сотрудник', _medExamEmployeeId, (id) => setState(() => _medExamEmployeeId = id)),
            _textField('med_exam_position', 'Должность'),
            _textField('med_exam_department', 'Подразделение'),
            _datePickerField('med_exam_hire_date', 'Дата приёма', _medExamHireDate, (d) => setState(() => _medExamHireDate = d)),
            _textField('med_exam_type', 'Вид (предварительный/периодический)'),
            _textField('med_exam_institution', 'ЛПУ'),
            _textField('med_exam_harmful_1', 'Вредный фактор №90'),
            _textField('med_exam_harmful_2', 'Вредный фактор №83'),
            _datePickerField('med_exam_date', 'Дата прохождения', _medExamDate, (d) => setState(() => _medExamDate = d)),
            _textField('med_exam_conclusion', 'Заключение'),
            _textField('med_exam_employer_decision', 'Решение работодателя'),
            _datePickerField('med_exam_next_date', 'Дата следующего осмотра', _medExamNextDate, (d) => setState(() => _medExamNextDate = d)),
            _datePickerField('med_exam_exclusion_date', 'Дата исключения из списков', _medExamExclusionDate, (d) => setState(() => _medExamExclusionDate = d)),
            _textField('med_exam_note', 'Примечание'),
          ],
        );
      case HaccpLogType.disinfectantAccounting:
        return Column(
          children: [
            _mobileBlock(
              'Расчёт потребности в дезинфицирующих средствах',
              [
                _savedOptionTextField(
                  key: 'disinf_object_name',
                  label: 'Объект',
                  options: _presetOptions['disinf_object_name'] ?? const [],
                  presetFieldKey: 'disinf_object_name',
                ),
                _textField('disinf_object_count', 'Кол-во', keyboardType: TextInputType.number),
                _textField('disinf_area_sqm', 'Площадь м²', keyboardType: TextInputType.number),
                _savedOptionTextField(
                  key: 'disinf_treatment_type',
                  label: 'Вид Т/Г',
                  options: _presetOptions['disinf_treatment_type'] ?? const [],
                  presetFieldKey: 'disinf_treatment_type',
                ),
                _textField('disinf_frequency', 'Кратность/мес', keyboardType: TextInputType.number),
                _savedOptionTextField(
                  key: 'disinf_agent_name',
                  label: 'Дезсредство',
                  options: _presetOptions['disinf_agent_name'] ?? const [],
                  presetFieldKey: 'disinf_agent_name',
                ),
                _textField('disinf_concentration_pct', 'Конц.%'),
                _textField('disinf_consumption_per_sqm', 'Расход/м²', keyboardType: TextInputType.number),
                _textField('disinf_solution_per_treatment', 'Раствор на 1 обр. (л/кг)', keyboardType: TextInputType.number),
                _textField('disinf_need_per_treatment', 'Потребность 1 обр. (л/кг)', keyboardType: TextInputType.number),
                _textField('disinf_need_per_month', 'В месяц (л/кг)', keyboardType: TextInputType.number),
                _textField('disinf_need_per_year', 'В год (л/кг)', keyboardType: TextInputType.number),
              ],
            ),
            _mobileBlock(
              'Поступление дезинфицирующих средств',
              [
                _datePickerField('disinf_receipt_date', 'Дата', _disinfReceiptDate, (d) => setState(() => _disinfReceiptDate = d)),
                _savedOptionTextField(
                  key: 'disinf_agent_name_receipt',
                  label: 'Наименование',
                  options: _presetOptions['disinf_agent_name_receipt'] ?? const [],
                  presetFieldKey: 'disinf_agent_name_receipt',
                ),
                _textField('disinf_invoice_number', 'Счёт №'),
                _textField('disinf_quantity', 'Кол-во', keyboardType: TextInputType.number),
                _datePickerField('disinf_expiry_date', 'Срок годности', _disinfExpiryDate, (d) => setState(() => _disinfExpiryDate = d)),
                _signatureFromAccount(),
              ],
            ),
          ],
        );
      case HaccpLogType.equipmentWashing:
        return _mobileBlock(
          loc.t(HaccpLogType.equipmentWashing.displayNameKey) ?? HaccpLogType.equipmentWashing.displayNameRu,
          [
            TextFormField(
              initialValue: DateFormat('dd.MM.yyyy').format(DateTime.now()),
              decoration: const InputDecoration(labelText: 'Дата', border: OutlineInputBorder(), isDense: true),
              readOnly: true,
            ),
            _textField('wash_time', 'Время мойки'),
            _savedOptionTextField(
              key: 'wash_equipment_name',
              label: 'Оборудование',
              options: _presetOptions['wash_equipment_name'] ?? const [],
              presetFieldKey: 'wash_equipment_name',
            ),
            _savedOptionTextField(
              key: 'wash_solution_name',
              label: 'Моющий раствор',
              options: _presetOptions['wash_solution_name'] ?? const [],
              presetFieldKey: 'wash_solution_name',
            ),
            _textField('wash_solution_concentration_pct', 'Конц.%'),
            _savedOptionTextField(
              key: 'wash_disinfectant_name',
              label: 'Дез. раствор',
              options: _presetOptions['wash_disinfectant_name'] ?? const [],
              presetFieldKey: 'wash_disinfectant_name',
            ),
            _textField('wash_disinfectant_concentration_pct', 'Конц.%'),
            _textField('wash_rinsing_temp', 'Ополаскивание t°', keyboardType: TextInputType.number),
            _signatureFromAccount(),
          ],
        );
      case HaccpLogType.generalCleaningSchedule:
        return _mobileBlock(
          loc.t(HaccpLogType.generalCleaningSchedule.displayNameKey) ?? HaccpLogType.generalCleaningSchedule.displayNameRu,
          [
            _savedOptionTextField(
              key: 'gen_clean_premises',
              label: 'Помещение / зона',
              options: _presetOptions['gen_clean_premises'] ?? const [],
              presetFieldKey: 'gen_clean_premises',
            ),
            _datePickerField('gen_clean_date', 'Дата проведения', _genCleanDate, (d) => setState(() => _genCleanDate = d)),
            _signatureFromAccount(),
            _textField('note', loc.t('haccp_note') ?? 'Примечание'),
          ],
        );
      case HaccpLogType.sieveFilterMagnet:
        return _mobileBlock(
          loc.t(HaccpLogType.sieveFilterMagnet.displayNameKey) ?? HaccpLogType.sieveFilterMagnet.displayNameRu,
          [
            _textField('sieve_no', '№ сита/магнита'),
            _savedOptionTextField(
              key: 'sieve_name_location',
              label: 'Наименование / Расположение',
              options: _presetOptions['sieve_name_location'] ?? const [],
              presetFieldKey: 'sieve_name_location',
            ),
            _savedOptionTextField(
              key: 'sieve_condition',
              label: 'Состояние',
              options: _presetOptions['sieve_condition'] ?? const [],
              presetFieldKey: 'sieve_condition',
            ),
            _datePickerField('sieve_cleaning_date', 'Дата очистки', _sieveCleaningDate, (d) => setState(() => _sieveCleaningDate = d)),
            _signatureFromAccount(),
            _textField('sieve_comments', 'Комментарии'),
          ],
        );
      default:
        // Для остальных журналов (пока) оставляем текущую форму; ключевая проблема — горизонтальный скролл контейнера.
        return _buildFormByType(loc);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_establishment_not_selected') ?? 'Заведение не выбрано')),
      );
      return;
    }
    if (emp == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_employee_required') ?? 'Войдите под учётной записью сотрудника заведения')),
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
          SnackBar(content: Text('${context.read<LocalizationService>().t('error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveNumeric(HaccpLogServiceSupabase svc, String estId, String empId) async {
    switch (_logType!) {
      case HaccpLogType.fridgeTemperature:
        await svc.insertNumeric(
          establishmentId: estId,
          createdByEmployeeId: empId,
          logType: _logType!,
          value1: _tempValue,
          equipment: _getText('equipment').isNotEmpty ? _getText('equipment') : null,
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
          equipment: _getText('warehouse_premises').trim().isNotEmpty ? _getText('warehouse_premises').trim() : null,
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

  Future<void> _saveStatus(HaccpLogServiceSupabase svc, String estId, String empId) async {
    if (_logType == HaccpLogType.healthHygiene) {
      if (_healthRows.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('haccp_add_at_least_one') ?? 'Добавьте хотя бы одного сотрудника')),
        );
        return;
      }
      final note = _getText('note').isNotEmpty ? _getText('note') : null;
      for (final row in _healthRows) {
        final posOverride = (row.positionOverride ?? '').trim().isEmpty ? null : (row.positionOverride ?? '').trim();
        final emp = _healthEmployees.where((e) => e.id == row.employeeId).firstOrNull;
        final employeeNameSnapshot = emp != null ? '${emp.fullName}${emp.surname != null ? ' ${emp.surname}' : ''}' : null;
        final description = HaccpLog.buildHealthHygieneDescription(employeeId: row.employeeId, positionOverride: posOverride, employeeName: employeeNameSnapshot);
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

  Future<void> _saveQuality(HaccpLogServiceSupabase svc, String estId, String empId) async {
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    final signatureName = emp != null
        ? (emp.surname != null ? '${emp.surname} ${emp.fullName}' : emp.fullName)
        : null;
    final approvalStr = _logType == HaccpLogType.finishedProductBrakerage && _approvalToSell != null
        ? (_approvalToSell! ? 'разрешено' : 'запрещено')
        : null;
    final isFryingOil = _logType == HaccpLogType.fryingOil;
    final isFinishedBrakerage = _logType == HaccpLogType.finishedProductBrakerage;
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
      techCardId: isFinishedBrakerage ? _selectedFinishedBrakerageTechCardId : null,
      productName: _getText('product').isNotEmpty ? _getText('product') : null,
      result: _getText('result').isNotEmpty ? _getText('result') : null,
      timeBrakerage: _getText('time_brakerage').isNotEmpty ? _getText('time_brakerage') : null,
      approvalToSell: approvalStr ?? (_getText('approval_to_sell').isNotEmpty ? _getText('approval_to_sell') : null),
      commissionSignatures: signatureName,
      weighingResult: _getText('weighing_result').isNotEmpty ? _getText('weighing_result') : null,
      packaging: _getText('packaging').isNotEmpty ? _getText('packaging') : null,
      manufacturerSupplier: _getText('manufacturer_supplier').isNotEmpty ? _getText('manufacturer_supplier') : null,
      quantityKg: _getNum('quantity_kg'),
      documentNumber: _getText('document_number').isNotEmpty ? _getText('document_number') : null,
      storageConditions: _getText('storage_conditions').isNotEmpty ? _getText('storage_conditions') : null,
      dateSold: _dateSold,
      oilName: isFryingOil && _getText('oil_name').isNotEmpty ? _getText('oil_name') : null,
      organolepticStart: isFryingOil && _getText('organoleptic_start').isNotEmpty ? _getText('organoleptic_start') : null,
      fryingEquipmentType: isFryingOil && _getText('frying_equipment_type').isNotEmpty ? _getText('frying_equipment_type') : null,
      fryingProductType: isFryingOil && _getText('frying_product_type').isNotEmpty ? _getText('frying_product_type') : null,
      fryingEndTime: isFryingOil && _getText('frying_end_time').isNotEmpty ? _getText('frying_end_time') : null,
      organolepticEnd: isFryingOil && _getText('organoleptic_end').isNotEmpty ? _getText('organoleptic_end') : null,
      carryOverKg: isFryingOil ? _getNum('carry_over_kg') : null,
      utilizedKg: isFryingOil ? _getNum('utilized_kg') : null,
      medBookEmployeeName: isMedBook && _getText('med_book_employee_name').isNotEmpty ? _getText('med_book_employee_name') : null,
      medBookPosition: isMedBook && _getText('med_book_position').isNotEmpty ? _getText('med_book_position') : null,
      medBookNumber: isMedBook && _getText('med_book_number').isNotEmpty ? _getText('med_book_number') : null,
      medBookValidUntil: isMedBook ? _medBookValidUntil : null,
      medBookIssuedAt: isMedBook ? _medBookIssuedAt : null,
      medBookReturnedAt: isMedBook ? _medBookReturnedAt : null,
      medExamEmployeeName: isMedExam && _getText('med_exam_employee_name').isNotEmpty ? _getText('med_exam_employee_name') : null,
      medExamDob: isMedExam && _getText('med_exam_dob').isNotEmpty ? _getText('med_exam_dob') : null,
      medExamGender: isMedExam && _getText('med_exam_gender').isNotEmpty ? _getText('med_exam_gender') : null,
      medExamPosition: isMedExam && _getText('med_exam_position').isNotEmpty ? _getText('med_exam_position') : null,
      medExamDepartment: isMedExam && _getText('med_exam_department').isNotEmpty ? _getText('med_exam_department') : null,
      medExamHireDate: isMedExam ? _medExamHireDate : null,
      medExamType: isMedExam && _getText('med_exam_type').isNotEmpty ? _getText('med_exam_type') : null,
      medExamInstitution: isMedExam && _getText('med_exam_institution').isNotEmpty ? _getText('med_exam_institution') : null,
      medExamHarmful1: isMedExam && _getText('med_exam_harmful_1').isNotEmpty ? _getText('med_exam_harmful_1') : null,
      medExamHarmful2: isMedExam && _getText('med_exam_harmful_2').isNotEmpty ? _getText('med_exam_harmful_2') : null,
      medExamDate: isMedExam ? _medExamDate : null,
      medExamConclusion: isMedExam && _getText('med_exam_conclusion').isNotEmpty ? _getText('med_exam_conclusion') : null,
      medExamEmployerDecision: isMedExam && _getText('med_exam_employer_decision').isNotEmpty ? _getText('med_exam_employer_decision') : null,
      medExamNextDate: isMedExam ? _medExamNextDate : null,
      medExamExclusionDate: isMedExam ? _medExamExclusionDate : null,
      disinfObjectName: isDisinf && _getText('disinf_object_name').isNotEmpty ? _getText('disinf_object_name') : null,
      disinfObjectCount: isDisinf ? _getNum('disinf_object_count') : null,
      disinfAreaSqm: isDisinf ? _getNum('disinf_area_sqm') : null,
      disinfTreatmentType: isDisinf && _getText('disinf_treatment_type').isNotEmpty ? _getText('disinf_treatment_type') : null,
      disinfFrequencyPerMonth: isDisinf ? _getInt('disinf_frequency') : null,
      disinfAgentName: isDisinf && (_getText('disinf_agent_name').isNotEmpty || _getText('disinf_agent_name_receipt').isNotEmpty) ? (_getText('disinf_agent_name').isNotEmpty ? _getText('disinf_agent_name') : _getText('disinf_agent_name_receipt')) : null,
      disinfConcentrationPct: isDisinf && _getText('disinf_concentration_pct').isNotEmpty ? _getText('disinf_concentration_pct') : null,
      disinfConsumptionPerSqm: isDisinf ? _getNum('disinf_consumption_per_sqm') : null,
      disinfSolutionPerTreatment: isDisinf ? _getNum('disinf_solution_per_treatment') : null,
      disinfNeedPerTreatment: isDisinf ? _getNum('disinf_need_per_treatment') : null,
      disinfNeedPerMonth: isDisinf ? _getNum('disinf_need_per_month') : null,
      disinfNeedPerYear: isDisinf ? _getNum('disinf_need_per_year') : null,
      disinfReceiptDate: isDisinf ? _disinfReceiptDate : null,
      disinfInvoiceNumber: isDisinf && _getText('disinf_invoice_number').isNotEmpty ? _getText('disinf_invoice_number') : null,
      disinfQuantity: isDisinf ? _getNum('disinf_quantity') : null,
      disinfExpiryDate: isDisinf ? _disinfExpiryDate : null,
      disinfResponsibleName: isDisinf ? signatureName : null,
      washTime: isWash && _getText('wash_time').isNotEmpty ? _getText('wash_time') : null,
      washEquipmentName: isWash && _getText('wash_equipment_name').isNotEmpty ? _getText('wash_equipment_name') : null,
      washSolutionName: isWash && _getText('wash_solution_name').isNotEmpty ? _getText('wash_solution_name') : null,
      washSolutionConcentrationPct: isWash && _getText('wash_solution_concentration_pct').isNotEmpty ? _getText('wash_solution_concentration_pct') : null,
      washDisinfectantName: isWash && _getText('wash_disinfectant_name').isNotEmpty ? _getText('wash_disinfectant_name') : null,
      washDisinfectantConcentrationPct: isWash && _getText('wash_disinfectant_concentration_pct').isNotEmpty ? _getText('wash_disinfectant_concentration_pct') : null,
      washRinsingTemp: isWash && _getText('wash_rinsing_temp').isNotEmpty ? _getText('wash_rinsing_temp') : null,
      washControllerSignature: isWash ? signatureName : null,
      genCleanPremises: isGenClean && _getText('gen_clean_premises').isNotEmpty ? _getText('gen_clean_premises') : null,
      genCleanDate: isGenClean ? _genCleanDate : null,
      genCleanResponsible: isGenClean ? signatureName : null,
      sieveNo: isSieve && _getText('sieve_no').isNotEmpty ? _getText('sieve_no') : null,
      sieveNameLocation: isSieve && _getText('sieve_name_location').isNotEmpty ? _getText('sieve_name_location') : null,
      sieveCondition: isSieve && _getText('sieve_condition').isNotEmpty ? _getText('sieve_condition') : null,
      sieveCleaningDate: isSieve ? _sieveCleaningDate : null,
      sieveSignature: isSieve ? signatureName : null,
      sieveComments: isSieve && _getText('sieve_comments').isNotEmpty ? _getText('sieve_comments') : null,
      note: _getText('note').isNotEmpty ? _getText('note') : null,
    );
    for (final f in _presetFieldsForCurrentLog()) {
      await _saveCurrentOption(controllerKey: f, fieldKey: f, showFeedback: false);
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
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    if (_logType == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('haccp_journals') ?? 'Журналы ХАССП')),
        body: Center(child: Text(loc.t('error') ?? 'Неизвестный тип журнала')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('haccp_add_entry') ?? 'Добавить'} — ${(loc.t(_logType!.displayNameKey) ?? _logType!.displayNameRu)}'),
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
                  title: Text(emp.fullName),
                  subtitle: Text(emp.roleDisplayName),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              loc.t('haccp_recommended_sample') ?? 'Рекомендуемый образец',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 4),
            if (MediaQuery.of(context).size.shortestSide >= 600) ...[
              Text(
                loc.t('haccp_scroll_right_hint') ?? 'Таблица по форме СанПиН — при необходимости прокрутите вправо',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1400,
                  child: _buildFormByType(loc),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              _buildFormByTypeMobile(loc),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
