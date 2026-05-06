import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_floor_room_label.dart';
import '../../utils/pos_order_live_duration.dart';
import '../../utils/pos_order_menu_due_format.dart';
import '../../utils/pos_orders_list_subtitle_style.dart';
/// KDS по секретной ссылке: без входа в учётку, только очередь + ТТК + «отдано».
class PosKitchenDisplayPublicScreen extends StatefulWidget {
  const PosKitchenDisplayPublicScreen({super.key, required this.department});

  final String department;

  @override
  State<PosKitchenDisplayPublicScreen> createState() =>
      _PosKitchenDisplayPublicScreenState();
}

class _PosKitchenDisplayPublicScreenState extends State<PosKitchenDisplayPublicScreen> {
  late String _department;
  String _token = '';
  bool _loading = true;
  String? _errorCode;
  KdsGuestSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _department = widget.department.trim().toLowerCase();
    if (_department != 'kitchen' && _department != 'bar') {
      _department = 'kitchen';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _readTokenAndLoad());
  }

  void _readTokenAndLoad() {
    final q = GoRouterState.of(context).queryParameters;
    final t = q['kds_token']?.trim() ?? '';
    _token = t;
    _load();
  }

  Future<void> _load() async {
    if (_token.isEmpty) {
      setState(() {
        _loading = false;
        _errorCode = null;
        _snapshot = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _errorCode = null;
    });
    final snap = await PosKdsGuestService.instance.fetchOrders(
      token: _token,
      department: _department,
    );
    if (!mounted) return;
    if (!snap.ok) {
      setState(() {
        _loading = false;
        _errorCode = snap.errorCode;
        _snapshot = null;
      });
      return;
    }
    setState(() {
      _loading = false;
      _snapshot = snap;
      if (snap.rows.isNotEmpty) {
        _department = snap.department;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final baseStyle = Theme.of(context).textTheme.titleLarge!;
    final bigStyle =
        baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 20) + 6);

    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.12)),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: context.canPop(),
          title: Text(loc.t('pos_kds_public_title')),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed:
                  (_loading || _token.isEmpty) ? null : () => _load(),
              tooltip: loc.t('refresh'),
            ),
          ],
        ),
        body: _body(context, loc, bigStyle),
      ),
    );
  }

  Widget _body(
      BuildContext context, LocalizationService loc, TextStyle bigStyle) {
    if (_token.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.t('pos_kds_public_need_token'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final code = _errorCode;
    if (code != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _messageForCode(loc, code),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final snap = _snapshot!;
    if (snap.shiftRequired && !snap.shiftOpen) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.t('pos_kds_public_shift_closed'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final rows = snap.sortedForList();
    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(child: Text(loc.t('pos_orders_empty_active'))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final r = rows[i];
          final o = r.order;
          final tn = o.tableNumber ?? 0;
          final due = r.grandDue;
          final partial = r.menuDuePartial;
          final elapsed = loc.t('pos_order_list_timer', args: {
            'time': formatPosOrderLiveDuration(o.createdAt),
          });
          final subParts = [
            '${loc.t('pos_orders_guests_short')}: ${o.guestCount}',
            if (r.bucket == 'served') loc.t('pos_kds_public_served_chip'),
          ];
          final subline = subParts.join(' · ');
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              title: Text(
                loc.t('pos_table_number', args: {'n': '$tn'}),
                style: bigStyle,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      posFloorRoomSummaryLine(loc,
                          floorName: o.floorName, roomName: o.roomName),
                      style:
                          bigStyle.copyWith(fontSize: bigStyle.fontSize! - 2),
                    ),
                    if (due > 0 || partial)
                      Text(
                        '${partial ? '≈ ' : ''}${formatPosOrderMenuDue(context, due)}',
                        style: bigStyle.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    Text(
                      elapsed,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      subline,
                      style: posOrderListSubtitleStyle(context),
                    ),
                  ],
                ),
              ),
              onTap: () => _openOrderSheet(context, loc, r),
            ),
          );
        },
      ),
    );
  }

  String _messageForCode(LocalizationService loc, String code) {
    switch (code) {
      case 'invalid_token':
      case 'invalid_department':
      case 'department_mismatch':
        return loc.t('pos_kds_public_invalid_token');
      default:
        return '${loc.t('error')}: $code';
    }
  }

  Future<void> _openOrderSheet(
    BuildContext context,
    LocalizationService loc,
    KdsGuestOrderRow row,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) {
            return _KdsGuestOrderSheet(
              loc: loc,
              token: _token,
              department: _department,
              row: row,
              scrollController: scrollController,
              onChanged: () {
                if (mounted) _load();
              },
              onShowTechCard: (tcId) =>
                  _showTechCardDialog(ctx, loc, tcId),
            );
          },
        );
      },
    );
  }

  Future<void> _showTechCardDialog(
    BuildContext context,
    LocalizationService loc,
    String techCardId,
  ) async {
    final data = await PosKdsGuestService.instance.techCardPreview(
      token: _token,
      department: _department,
      techCardId: techCardId,
    );
    if (!context.mounted) return;
    final name =
        data?['dish_name']?.toString() ?? loc.t('pos_kds_public_ttk_title');
    final comp = data?['composition_for_hall']?.toString() ?? '';
    final desc = data?['description_for_hall']?.toString() ?? '';
    final lang = loc.currentLanguageCode;
    dynamic techLocalized = data?['technology_localized'];
    String tech = '';
    if (techLocalized is Map<String, dynamic>) {
      tech = (techLocalized[lang]?.toString() ??
              techLocalized['ru']?.toString() ??
              techLocalized['en']?.toString() ??
              '')
          .trim();
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name — ${loc.t('pos_kds_public_ttk_title')}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (desc.isNotEmpty) Text(desc),
              if (comp.isNotEmpty) ...[
                if (desc.isNotEmpty) const SizedBox(height: 12),
                Text(comp),
              ],
              if (tech.isNotEmpty) ...[
                if (desc.isNotEmpty || comp.isNotEmpty)
                  const SizedBox(height: 12),
                Text(tech),
              ],
              if (desc.isEmpty && comp.isEmpty && tech.isEmpty)
                Text(loc.t('pos_kds_public_ttk_empty')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
        ],
      ),
    );
  }
}

class _KdsGuestOrderSheet extends StatefulWidget {
  const _KdsGuestOrderSheet({
    required this.loc,
    required this.token,
    required this.department,
    required this.row,
    required this.scrollController,
    required this.onChanged,
    required this.onShowTechCard,
  });

  final LocalizationService loc;
  final String token;
  final String department;
  final KdsGuestOrderRow row;
  final ScrollController scrollController;
  final VoidCallback onChanged;
  final void Function(String techCardId) onShowTechCard;

  @override
  State<_KdsGuestOrderSheet> createState() => _KdsGuestOrderSheetState();
}

class _KdsGuestOrderSheetState extends State<_KdsGuestOrderSheet> {
  bool _busy = false;

  Future<void> _mark(PosOrderLine line) async {
    if (line.servedAt != null) return;
    if (widget.row.order.status != PosOrderStatus.sent) {
      AppToastService.show(widget.loc.t('pos_order_line_mark_served_forbidden'));
      return;
    }
    setState(() => _busy = true);
    final ok = await PosKdsGuestService.instance.markLineServed(
      token: widget.token,
      department: widget.department,
      orderId: widget.row.order.id,
      lineId: line.id,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      AppToastService.show(widget.loc.t('pos_kds_public_marked_ok'));
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } else {
      AppToastService.show(widget.loc.t('pos_kds_public_mark_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final o = widget.row.order;
    final lines = widget.row.lines;
    final name =
        loc.t('pos_table_number', args: {'n': '${o.tableNumber ?? 0}'});
    final timeFmt =
        DateFormat.Hm(Localizations.localeOf(context).toString());

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          posFloorRoomSummaryLine(loc, floorName: o.floorName, roomName: o.roomName),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        for (final line in lines) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(line.dishTitleForLang(loc.currentLanguageCode)),
            subtitle: Text(
              [
                '${loc.t('pos_order_line_qty_short')}: ${line.quantity}',
                if (line.guestNumber != null)
                  loc.t('pos_order_line_guest_short',
                      args: {'n': '${line.guestNumber}'}),
                if (line.servedAt != null)
                  loc.t('pos_order_line_served_at', args: {
                    'time': timeFmt.format(line.servedAt!.toLocal()),
                  }),
              ].join(' · '),
            ),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => widget.onShowTechCard(line.techCardId),
                  child: Text(loc.t('pos_kds_public_ttk_title')),
                ),
                if (line.servedAt == null &&
                    o.status == PosOrderStatus.sent)
                  FilledButton(
                    onPressed: _busy ? null : () => _mark(line),
                    child: Text(loc.t('pos_order_line_mark_served')),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
