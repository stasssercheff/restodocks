import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_floor_room_label.dart';
import '../../utils/pos_order_live_duration.dart';
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
  final Map<String, Set<String>> _knownLineIdsByOrder = <String, Set<String>>{};
  final Set<String> _justAddedLineIds = <String>{};
  final Set<String> _expandedOrderIds = <String>{};
  DateTime? _highlightUntil;
  bool _soundEnabled = true;
  bool _autoRefreshEnabled = true;
  bool _clock24h = true;
  Timer? _autoRefreshTimer;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

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
    _restorePrefs();
    _load();
  }

  Future<void> _restorePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundEnabled = prefs.getBool('kds_public_sound_enabled') ?? true;
      _autoRefreshEnabled = prefs.getBool('kds_public_auto_refresh') ?? true;
      _clock24h = prefs.getBool('kds_public_clock_24h') ?? true;
      _restartAutoRefresh();
      _restartClock();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('kds_public_sound_enabled', _soundEnabled);
      await prefs.setBool('kds_public_auto_refresh', _autoRefreshEnabled);
      await prefs.setBool('kds_public_clock_24h', _clock24h);
    } catch (_) {}
  }

  void _restartAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (!_autoRefreshEnabled || _token.isEmpty) return;
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _loading) return;
      _load(silent: true);
    });
  }

  void _restartClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (_token.isEmpty) {
      setState(() {
        _loading = false;
        _errorCode = null;
        _snapshot = null;
      });
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _errorCode = null;
      });
    }
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
    final hadPreviousSnapshot = _snapshot != null;
    final addedNow = <String>{};
    for (final row in snap.rows) {
      final orderId = row.order.id;
      final prev = _knownLineIdsByOrder[orderId] ?? <String>{};
      final current = row.lines.map((e) => e.id).toSet();
      for (final id in current) {
        if (!prev.contains(id) && hadPreviousSnapshot) {
          addedNow.add(id);
        }
      }
      _knownLineIdsByOrder[orderId] = current;
    }
    if (addedNow.isNotEmpty) {
      _justAddedLineIds
        ..clear()
        ..addAll(addedNow);
      _highlightUntil = DateTime.now().add(const Duration(seconds: 75));
      if (_soundEnabled) {
        _playNewOrderSignal();
      }
    }
    setState(() {
      _loading = false;
      _snapshot = snap;
      if (snap.rows.isNotEmpty) {
        _department = snap.department;
      }
    });
    _restartAutoRefresh();
  }

  void _playNewOrderSignal() {
    // On web `alert` can be ignored by browser/device profile, so also send `click`.
    SystemSound.play(SystemSoundType.alert);
    Future<void>.delayed(
      const Duration(milliseconds: 120),
      () => SystemSound.play(SystemSoundType.click),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
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
          title: _kdsTitle(context, loc),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'KDS settings',
              onPressed: _openSettingsSheet,
            ),
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

  Widget _kdsTitle(BuildContext context, LocalizationService loc) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final time = _formatClock(_now, use24h: _clock24h);
        return Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(loc.t('pos_kds_public_title')),
            ),
            Text(
              time,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        );
      },
    );
  }

  String _formatClock(DateTime dt, {required bool use24h}) {
    final hh = dt.hour;
    final mm = dt.minute.toString().padLeft(2, '0');
    if (use24h) {
      return '${hh.toString().padLeft(2, '0')}:$mm';
    }
    final h12raw = hh % 12;
    final h12 = (h12raw == 0 ? 12 : h12raw).toString();
    final suffix = hh >= 12 ? 'PM' : 'AM';
    return '$h12:$mm $suffix';
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

    final rows = snap.sortedForList()
      ..sort((a, b) {
        final upd = b.order.updatedAt.compareTo(a.order.updatedAt);
        if (upd != 0) return upd;
        final tableCmp = (a.order.tableNumber ?? 0).compareTo(b.order.tableNumber ?? 0);
        if (tableCmp != 0) return tableCmp;
        return b.order.id.compareTo(a.order.id);
      });
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth - 32;
          final cols = totalWidth >= 1400
              ? 4
              : totalWidth >= 980
                  ? 3
                  : totalWidth >= 640
                      ? 2
                      : 1;
          final cardWidth = (totalWidth - ((cols - 1) * 10)) / cols;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final r in rows)
                    SizedBox(
                      width: cardWidth,
                      child: _buildOrderCard(context, loc, bigStyle, r),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    LocalizationService loc,
    TextStyle bigStyle,
    KdsGuestOrderRow r,
  ) {
    const collapsedLinesLimit = 4;
    final o = r.order;
    final tn = o.tableNumber ?? 0;
    final orderNo = o.id.length > 8 ? o.id.substring(0, 8) : o.id;
    final elapsed = loc.t('pos_order_list_timer', args: {
      'time': formatPosOrderLiveDuration(o.createdAt),
    });
    final subParts = [
      '${loc.t('pos_orders_guests_short')}: ${o.guestCount}',
      if (r.bucket == 'served') loc.t('pos_kds_public_served_chip'),
    ];
    final subline = subParts.join(' · ');
    final expanded = _expandedOrderIds.contains(o.id);
    final allLines = r.lines;
    final visibleLines =
        expanded ? allLines : allLines.take(collapsedLinesLimit).toList();
    final hasOverflow = allLines.length > collapsedLinesLimit;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.t('pos_table_number', args: {'n': '$tn'}),
              style: bigStyle.copyWith(fontSize: (bigStyle.fontSize ?? 22) - 8),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Заказ #$orderNo',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              posFloorRoomSummaryLine(
                loc,
                floorName: o.floorName,
                roomName: o.roomName,
              ),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(elapsed, style: Theme.of(context).textTheme.bodySmall),
            Text(
              subline,
              style: posOrderListSubtitleStyle(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            for (final line in visibleLines) _buildOrderLineTile(context, loc, r, line),
            if (hasOverflow)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      if (expanded) {
                        _expandedOrderIds.remove(o.id);
                      } else {
                        _expandedOrderIds.add(o.id);
                      }
                    });
                  },
                  icon: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: Text(
                    expanded
                        ? loc.t('ui_collapse')
                        : '${loc.t('ui_expand')} (+${allLines.length - visibleLines.length})',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderLineTile(
    BuildContext context,
    LocalizationService loc,
    KdsGuestOrderRow row,
    PosOrderLine line,
  ) {
    final o = row.order;
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _lineColor(context, line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.dishTitleForLang(loc.currentLanguageCode),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(width: 6),
              Text('x${line.quantity}', style: const TextStyle(fontSize: 12)),
            ],
          ),
          if ((line.comment ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              (line.comment ?? '').trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showTechCardDialog(context, loc, line, row),
                child: Text(loc.t('pos_kds_public_ttk_title')),
              ),
              if (line.servedAt == null && o.status == PosOrderStatus.sent)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  ),
                  onPressed: () => _markLine(row, line),
                  child: Text(loc.t('pos_order_line_mark_served')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _lineColor(BuildContext context, PosOrderLine line) {
    final cs = Theme.of(context).colorScheme;
    if (line.servedAt != null) return Colors.green.withValues(alpha: 0.16);
    final activeHighlight = _highlightUntil != null &&
        DateTime.now().isBefore(_highlightUntil!) &&
        _justAddedLineIds.contains(line.id);
    if (activeHighlight) return cs.tertiaryContainer.withValues(alpha: 0.75);
    return cs.surfaceContainerHighest.withValues(alpha: 0.45);
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

  Future<void> _showTechCardDialog(
    BuildContext context,
    LocalizationService loc,
    PosOrderLine line,
    KdsGuestOrderRow row,
  ) async {
    final data = row.techCardPreviewByLineId[line.id];
    final name =
        data?['dish_name']?.toString() ?? line.dishTitleForLang(loc.currentLanguageCode);
    final portion = (data?['portion_weight'] as num?)?.toDouble();
    final yieldG = (data?['yield'] as num?)?.toDouble();
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

    final ingredients = <TTIngredient>[];
    final rawIngredients = data?['ingredients'];
    if (rawIngredients is List) {
      for (final e in rawIngredients) {
        if (e is! Map) continue;
        try {
          ingredients.add(TTIngredient.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
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
              if (portion != null && portion > 0)
                Text('${loc.t('portion_weight')}: ${portion.toStringAsFixed(0)}'),
              if (yieldG != null && yieldG > 0)
                Text('${loc.t('yield_g')}: ${yieldG.toStringAsFixed(0)}'),
              if ((portion != null && portion > 0) || (yieldG != null && yieldG > 0))
                const SizedBox(height: 12),
              if (ingredients.isNotEmpty) ...[
                Text(
                  loc.t('tech_cards_ingredients_count')
                      .replaceAll('%s', '${ingredients.length}'),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                for (final ing in ingredients)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            ing.sourceTechCardName?.trim().isNotEmpty == true
                                ? '${ing.productName} (${ing.sourceTechCardName})'
                                : ing.productName,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${loc.t('ttk_gross')}: ${ing.grossWeight.toStringAsFixed(0)}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${loc.t('ttk_net')}: ${ing.netWeight.toStringAsFixed(0)}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        if (ing.outputWeight > 0) ...[
                          const SizedBox(width: 10),
                          Text(
                            '${loc.t('ttk_output')}: ${ing.outputWeight.toStringAsFixed(0)}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
              if (tech.isNotEmpty) ...[
                if (ingredients.isNotEmpty) const SizedBox(height: 12),
                Text(tech),
              ],
              if ((portion == null || portion == 0) &&
                  (yieldG == null || yieldG == 0) &&
                  ingredients.isEmpty &&
                  tech.isEmpty)
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

  Future<void> _markLine(KdsGuestOrderRow row, PosOrderLine line) async {
    final ok = await PosKdsGuestService.instance.markLineServed(
      token: _token,
      department: _department,
      orderId: row.order.id,
      lineId: line.id,
    );
    if (!mounted) return;
    if (!ok) {
      AppToastService.show(context.read<LocalizationService>().t('pos_kds_public_mark_failed'));
      return;
    }
    await _load(silent: true);
  }

  Future<void> _openSettingsSheet() async {
    final loc = context.read<LocalizationService>();
    final initialSound = _soundEnabled;
    final initialAuto = _autoRefreshEnabled;
    final initialClock = _clock24h;
    var localSound = _soundEnabled;
    var localAuto = _autoRefreshEnabled;
    var localClock = _clock24h;
    final selectedLang = ValueNotifier<String>(loc.currentLanguageCode);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: localAuto,
                    onChanged: (v) => setLocal(() => localAuto = v),
                    title: Text(loc.t('pos_kds_public_settings_auto_refresh')),
                  ),
                  SwitchListTile(
                    value: localSound,
                    onChanged: (v) => setLocal(() => localSound = v),
                    title: Text(loc.t('pos_kds_public_settings_sound')),
                  ),
                  SwitchListTile(
                    value: localClock,
                    onChanged: (v) => setLocal(() => localClock = v),
                    title: Text(loc.t('pos_kds_public_settings_clock_24h')),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: selectedLang,
                    builder: (_, value, __) {
                      return DropdownButtonFormField<String>(
                        initialValue: value,
                        items: const [
                          DropdownMenuItem(value: 'ru', child: Text('Русский')),
                          DropdownMenuItem(value: 'en', child: Text('English')),
                          DropdownMenuItem(value: 'es', child: Text('Español')),
                          DropdownMenuItem(value: 'kk', child: Text('Қазақша')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          selectedLang.value = v;
                        },
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: loc.t('language'),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.t('done')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _soundEnabled = localSound;
    _autoRefreshEnabled = localAuto;
    _clock24h = localClock;
    if (initialSound != _soundEnabled ||
        initialAuto != _autoRefreshEnabled ||
        initialClock != _clock24h) {
      await _savePrefs();
      _restartAutoRefresh();
    }
    if (selectedLang.value != loc.currentLanguageCode) {
      await loc.setLocale(Locale(selectedLang.value), userChoice: true);
    }
    if (mounted) setState(() {});
  }
}
