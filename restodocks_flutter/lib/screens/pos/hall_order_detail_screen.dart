import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

bool _isBarDish(TechCard tc) => posLineIsBarDish(tc.category, tc.sections);

/// Карточка заказа зала: позиции из меню (ТТК).
class HallOrderDetailScreen extends StatefulWidget {
  const HallOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<HallOrderDetailScreen> createState() => _HallOrderDetailScreenState();
}

class _HallOrderDetailScreenState extends State<HallOrderDetailScreen> {
  PosOrder? _order;
  bool _orderLoading = true;

  List<PosOrderLine> _lines = [];
  bool _linesLoading = true;
  Object? _linesError;

  List<TechCard> _menuDishes = [];
  bool _menuLoading = false;

  bool _sending = false;

  bool get _busy => _orderLoading || _linesLoading || _sending;

  String _statusLabel(LocalizationService loc, PosOrderStatus s) {
    switch (s) {
      case PosOrderStatus.draft:
        return loc.t('pos_order_status_draft');
      case PosOrderStatus.sent:
        return loc.t('pos_order_status_sent');
      case PosOrderStatus.closed:
        return loc.t('pos_order_status_closed');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadAll();
      _loadMenu();
    });
  }

  Future<void> _loadOrder() async {
    setState(() => _orderLoading = true);
    try {
      final o = await PosOrderService.instance.fetchById(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = o;
        _orderLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _order = null;
        _orderLoading = false;
      });
    }
  }

  Future<void> _reloadAll() async {
    await _loadOrder();
    await _refreshLines();
  }

  Future<void> _submit(LocalizationService loc) async {
    if (_lines.isEmpty) {
      AppToastService.show(loc.t('pos_order_send_empty'));
      return;
    }
    setState(() => _sending = true);
    try {
      await PosOrderService.instance.submitOrder(widget.orderId);
      if (!mounted) return;
      AppToastService.show(loc.t('pos_order_sent_toast'));
      await _loadOrder();
      await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } on PosOrderSubmitEmptyException {
      if (mounted) AppToastService.show(loc.t('pos_order_send_empty'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadMenu() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;
    setState(() => _menuLoading = true);
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final all = await svc.getTechCardsForEstablishment(est.dataEstablishmentId);
      final dishes = all.where((tc) => !tc.isSemiFinished).toList();
      dishes.sort((a, b) => a.dishName.toLowerCase().compareTo(b.dishName.toLowerCase()));
      if (mounted) {
        setState(() {
          _menuDishes = dishes;
          _menuLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _menuLoading = false);
    }
  }

  Future<void> _refreshLines() async {
    setState(() {
      _linesLoading = true;
      _linesError = null;
    });
    try {
      final list = await PosOrderService.instance.fetchLines(widget.orderId);
      if (!mounted) return;
      setState(() {
        _lines = list;
        _linesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _linesError = e;
        _linesLoading = false;
      });
    }
  }

  Future<void> _addDish(TechCard tc, LocalizationService loc) async {
    try {
      await PosOrderService.instance.addLine(
        orderId: widget.orderId,
        techCardId: tc.id,
        quantity: 1,
      );
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) {
        AppToastService.show(loc.t('pos_order_edit_forbidden'));
      }
    } catch (e) {
      if (mounted) {
        AppToastService.show('${loc.t('error')}: $e');
      }
    }
  }

  Future<void> _setQty(PosOrderLine line, double q, LocalizationService loc) async {
    try {
      await PosOrderService.instance.updateLineQuantity(line.id, widget.orderId, q);
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _removeLine(PosOrderLine line, LocalizationService loc) async {
    try {
      await PosOrderService.instance.deleteLine(line.id, widget.orderId);
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _editLineComment(PosOrderLine line, LocalizationService loc) async {
    final ctrl = TextEditingController(text: line.comment ?? '');
    bool? ok;
    var snap = '';
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.t('pos_order_line_comment')),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: loc.t('pos_order_line_comment_hint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.t('save')),
            ),
          ],
        ),
      );
    } finally {
      snap = ctrl.text;
      ctrl.dispose();
    }
    if (ok != true || !mounted) return;
    try {
      await PosOrderService.instance
          .updateLineComment(line.id, widget.orderId, snap.trim().isEmpty ? null : snap.trim());
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  void _openAddDishSheet(LocalizationService loc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _AddDishSheet(
          loc: loc,
          dishes: _menuDishes,
          loading: _menuLoading,
          onPick: (tc) async {
            Navigator.pop(ctx);
            await _addDish(tc, loc);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final lc = Localizations.localeOf(context).toString();
    final dateFmt = DateFormat.yMMMd(lc);
    final timeFmt = DateFormat.Hm(lc);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_order_detail_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _reloadAll,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      floatingActionButton: () {
        final o = _order;
        final draft = o?.status == PosOrderStatus.draft;
        if (!draft || o == null) return const SizedBox.shrink();
        return FloatingActionButton(
          onPressed: (_menuLoading && _menuDishes.isEmpty) || _sending
              ? null
              : () => _openAddDishSheet(loc),
          tooltip: loc.t('pos_order_line_add'),
          child: const Icon(Icons.add),
        );
      }(),
      body: () {
        if (_orderLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final o = _order;
        if (o == null) {
          return Center(child: Text(loc.t('document_not_found')));
        }
        final tn = o.tableNumber ?? 0;
        final editable = o.status == PosOrderStatus.draft;

        return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                loc.t('pos_table_number', args: {'n': '$tn'}),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${loc.t('pos_orders_guests_short')}: ${o.guestCount}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${loc.t('pos_tables_field_status')}: ${_statusLabel(loc, o.status)}',
              ),
              const SizedBox(height: 8),
              Text(
                '${dateFmt.format(o.createdAt.toLocal())} ${timeFmt.format(o.createdAt.toLocal())}',
              ),
              const SizedBox(height: 24),
              Text(
                loc.t('pos_order_lines_heading'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (_linesLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_linesError != null)
                Text(
                  loc.t('pos_tables_load_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (_lines.isEmpty)
                Text(
                  loc.t('pos_order_line_empty'),
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              else
                ..._lines.map((line) => _LineTile(
                      line: line,
                      lang: lang,
                      editable: editable,
                      loc: loc,
                      onQty: (q) => _setQty(line, q, loc),
                      onDelete: () => _removeLine(line, loc),
                      onComment: () => _editLineComment(line, loc),
                    )),
              if (editable) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: (_menuLoading && _menuDishes.isEmpty) || _sending
                      ? null
                      : () => _openAddDishSheet(loc),
                  icon: const Icon(Icons.restaurant_menu),
                  label: Text(loc.t('pos_order_line_add')),
                ),
                if (!_linesLoading && _lines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _sending ? null : () => _submit(loc),
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(loc.t('pos_order_send')),
                  ),
                ],
              ],
              if (!editable) ...[
                const SizedBox(height: 16),
                Text(
                  o.status == PosOrderStatus.sent
                      ? loc.t('pos_order_sent_readonly_hint')
                      : loc.t('pos_order_edit_forbidden_hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          );
      }(),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.lang,
    required this.editable,
    required this.loc,
    required this.onQty,
    required this.onDelete,
    required this.onComment,
  });

  final PosOrderLine line;
  final String lang;
  final bool editable;
  final LocalizationService loc;
  final void Function(double) onQty;
  final VoidCallback onDelete;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    final title = line.dishTitleForLang(lang);
    final sub = <String>[
      '${loc.t('pos_order_line_qty_short')}: ${_formatPosQty(line.quantity)}',
      if (line.courseNumber > 1)
        '${loc.t('pos_order_course_short')}: ${line.courseNumber}',
      if (line.comment != null && line.comment!.trim().isNotEmpty)
        line.comment!.trim(),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (editable) ...[
                  IconButton(
                    onPressed: onComment,
                    icon: Icon(
                      line.comment != null && line.comment!.trim().isNotEmpty
                          ? Icons.chat
                          : Icons.chat_outlined,
                    ),
                    tooltip: loc.t('pos_order_line_comment'),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: loc.t('pos_order_line_delete'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (editable) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: line.quantity <= 1
                        ? null
                        : () => onQty(line.quantity - 1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(_formatPosQty(line.quantity),
                      style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    onPressed: () => onQty(line.quantity + 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _editQtyDialog(context, line, onQty, loc),
                    child: Text(loc.t('pos_order_line_qty_edit')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

}

String _formatPosQty(double q) {
  final t = q.toStringAsFixed(2);
  return t.replaceFirst(RegExp(r'\.?0+$'), '');
}

Future<void> _editQtyDialog(
  BuildContext context,
  PosOrderLine line,
  void Function(double) onQty,
  LocalizationService loc,
) async {
  final ctrl = TextEditingController(text: _formatPosQty(line.quantity));
  bool? ok;
  String textSnapshot = '';
  try {
    ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('pos_order_line_qty_edit')),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(labelText: loc.t('pos_order_line_qty')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.t('save')),
          ),
        ],
      ),
    );
    textSnapshot = ctrl.text;
  } finally {
    ctrl.dispose();
  }
  if (ok != true || !context.mounted) return;
  final raw = textSnapshot.replaceAll(',', '.').trim();
  final v = double.tryParse(raw);
  if (v == null || v <= 0) {
    AppToastService.show(loc.t('pos_order_line_qty_invalid'));
    return;
  }
  onQty(v);
}

class _AddDishSheet extends StatefulWidget {
  const _AddDishSheet({
    required this.loc,
    required this.dishes,
    required this.loading,
    required this.onPick,
  });

  final LocalizationService loc;
  final List<TechCard> dishes;
  final bool loading;
  final Future<void> Function(TechCard) onPick;

  @override
  State<_AddDishSheet> createState() => _AddDishSheetState();
}

class _AddDishSheetState extends State<_AddDishSheet> {
  final _search = TextEditingController();
  String _tab = 'kitchen';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TechCard> get _filtered {
    var list = widget.dishes.where((tc) {
      if (_tab == 'bar') return _isBarDish(tc);
      return !_isBarDish(tc);
    }).toList();
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((tc) {
      if (tc.dishName.toLowerCase().contains(q)) return true;
      final loc = tc.dishNameLocalized?.values.any((v) => v.toLowerCase().contains(q));
      return loc == true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final lang = loc.currentLanguageCode;
    final h = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                loc.t('pos_order_line_add'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: loc.t('pos_order_line_search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'kitchen',
                  label: Text(loc.t('kitchen')),
                ),
                ButtonSegment(
                  value: 'bar',
                  label: Text(loc.t('bar')),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.loading && widget.dishes.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final tc = _filtered[i];
                        final name = tc.dishNameLocalized?[lang]?.trim().isNotEmpty == true
                            ? tc.dishNameLocalized![lang]!
                            : tc.dishName;
                        return ListTile(
                          title: Text(name),
                          subtitle: tc.sellingPrice != null
                              ? Text(tc.sellingPrice!.toStringAsFixed(0))
                              : null,
                          onTap: () => widget.onPick(tc),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
