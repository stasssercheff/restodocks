import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/account_manager_supabase.dart';
import '../../services/localization_service.dart';
import '../../services/sales_plan_storage_service.dart';
import '../../services/tech_card_service_supabase.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

/// Создание и правка плана продаж POS (Supabase `pos_sales_plans`).
class KitchenBarSalesPlanFormScreen extends StatefulWidget {
  const KitchenBarSalesPlanFormScreen({
    super.key,
    required this.department,
    this.planId,
  });

  final String department;
  final String? planId;

  @override
  State<KitchenBarSalesPlanFormScreen> createState() =>
      _KitchenBarSalesPlanFormScreenState();
}

class _KitchenBarSalesPlanFormScreenState
    extends State<KitchenBarSalesPlanFormScreen> {
  SalesPlanPeriodKind _kind = SalesPlanPeriodKind.month;
  DateTime _anchor = DateTime.now();
  final _cashCtrl = TextEditingController();
  final List<_LineDraft> _lines = [];
  List<TechCard> _techCards = [];
  bool _loading = true;
  DateTime? _createdAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final establishment = acc.establishment;
    if (establishment == null) return;
    final posId = establishment.id;
    final dataId = establishment.dataEstablishmentId;
    final tech = TechCardServiceSupabase();
    final all = await tech.getTechCardsForEstablishment(dataId);
    final bar = widget.department == 'bar';
    _techCards = all.where((tc) {
      final cat = tc.category;
      final sec = tc.sections;
      final isBar = posLineIsBarDish(cat, sec);
      if (bar) return isBar;
      return !isBar;
    }).toList();
    _techCards.sort((a, b) => a.dishName.compareTo(b.dishName));

    if (widget.planId != null) {
      final existing =
          await SalesPlanStorageService.instance.getById(posId, widget.planId!);
      if (existing != null) {
        _createdAt = existing.createdAt;
        _kind = existing.periodKind;
        _anchor = existing.periodStart;
        _cashCtrl.text = existing.targetCashAmount.toStringAsFixed(0);
        for (final l in existing.lines) {
          _lines.add(_LineDraft(l.techCardId, l.dishName, l.targetQuantity));
        }
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final acc = context.read<AccountManagerSupabase>();
    final establishment = acc.establishment;
    if (establishment == null) return;
    final posId = establishment.id;
    final cash = double.tryParse(_cashCtrl.text.replaceAll(',', '.')) ?? 0;
    final (start, end) = salesPlanResolvePeriodBounds(
      kind: _kind,
      anchorLocal: _anchor,
    );
    final id = widget.planId ?? SalesPlanStorageService.instance.newId();
    final now = DateTime.now();
    final plan = SalesPlan(
      id: id,
      establishmentId: posId,
      department: widget.department == 'bar' ? 'bar' : 'kitchen',
      periodKind: _kind,
      periodStart: start,
      periodEnd: end,
      targetCashAmount: cash,
      lines: _lines
          .map(
            (e) => SalesPlanLine(
              techCardId: e.techCardId,
              dishName: e.dishName,
              targetQuantity: e.qty,
            ),
          )
          .toList(),
      createdAt: _createdAt ?? now,
      updatedAt: now,
    );
    await SalesPlanStorageService.instance.upsert(
      posId,
      plan,
      createdByEmployeeId:
          widget.planId == null ? acc.currentEmployee?.id : null,
    );
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.t('sales_plan_saved') ?? '')),
    );
    context.pop();
  }

  void _addLine() {
    if (_techCards.isEmpty) return;
    final tc = _techCards.first;
    setState(() {
      _lines.add(_LineDraft(tc.id, tc.dishName, 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final dept = widget.department == 'bar' ? 'bar' : 'kitchen';
    final titleKey = posDepartmentLabelKeyForRoute(dept);
    final deptTitle = titleKey != null ? loc.t(titleKey) : dept;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text('${loc.t('sales_plan_create') ?? ''} — $deptTitle'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(
          widget.planId == null
              ? '${loc.t('sales_plan_create') ?? ''} — $deptTitle'
              : '${loc.t('sales_plan_edit') ?? ''} — $deptTitle',
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(loc.t('save') ?? 'Сохранить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<SalesPlanPeriodKind>(
            value: _kind,
            decoration: InputDecoration(
              labelText: loc.t('haccp_period'),
            ),
            items: [
              for (final k in SalesPlanPeriodKind.values)
                DropdownMenuItem(
                  value: k,
                  child: Text(_kindLabel(loc, k)),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _kind = v);
            },
          ),
          ListTile(
            title: Text(loc.t('schedule') ?? 'Дата отсчёта'),
            subtitle: Text(
              MaterialLocalizations.of(context).formatFullDate(_anchor),
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _anchor,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _anchor = d);
            },
          ),
          TextField(
            controller: _cashCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: loc.t('sales_plan_target_cash') ?? '',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                loc.t('sales_plan_lines') ?? '',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                onPressed: _addLine,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          for (var i = 0; i < _lines.length; i++)
            _PlanLineCard(
              key: ValueKey('${_lines[i].techCardId}_$i'),
              draft: _lines[i],
              techCards: _techCards,
              onDraftChanged: (d) => setState(() => _lines[i] = d),
              onDelete: () => setState(() => _lines.removeAt(i)),
            ),
        ],
      ),
    );
  }

  String _kindLabel(LocalizationService loc, SalesPlanPeriodKind k) {
    switch (k) {
      case SalesPlanPeriodKind.shiftDay:
        return loc.t('sales_period_shift') ?? '';
      case SalesPlanPeriodKind.week:
        return loc.t('sales_period_week') ?? '';
      case SalesPlanPeriodKind.month:
        return loc.t('sales_period_month') ?? '';
      case SalesPlanPeriodKind.quarter:
        return loc.t('sales_period_quarter') ?? '';
      case SalesPlanPeriodKind.halfYear:
        return loc.t('sales_period_half_year') ?? '';
      case SalesPlanPeriodKind.year:
        return loc.t('sales_period_year') ?? '';
    }
  }
}

class _LineDraft {
  _LineDraft(this.techCardId, this.dishName, this.qty);

  String techCardId;
  String dishName;
  double qty;
}

class _PlanLineCard extends StatefulWidget {
  const _PlanLineCard({
    super.key,
    required this.draft,
    required this.techCards,
    required this.onDraftChanged,
    required this.onDelete,
  });

  final _LineDraft draft;
  final List<TechCard> techCards;
  final void Function(_LineDraft) onDraftChanged;
  final VoidCallback onDelete;

  @override
  State<_PlanLineCard> createState() => _PlanLineCardState();
}

class _PlanLineCardState extends State<_PlanLineCard> {
  late TextEditingController _qtyCtrl;

  @override
  void initState() {
    super.initState();
    final q = widget.draft.qty;
    _qtyCtrl = TextEditingController(
      text: q == q.roundToDouble() ? q.toInt().toString() : q.toString(),
    );
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButton<String>(
              isExpanded: true,
              value: widget.draft.techCardId,
              items: [
                for (final tc in widget.techCards)
                  DropdownMenuItem(
                    value: tc.id,
                    child: Text(tc.dishName, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return;
                final tc = widget.techCards.firstWhere((e) => e.id == id);
                widget.onDraftChanged(
                  _LineDraft(tc.id, tc.dishName, widget.draft.qty),
                );
              },
            ),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: loc.t('quantity_short')),
              onChanged: (s) {
                final q = double.tryParse(s.replaceAll(',', '.')) ?? 0;
                widget.onDraftChanged(
                  _LineDraft(
                    widget.draft.techCardId,
                    widget.draft.dishName,
                    q,
                  ),
                );
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: widget.onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
