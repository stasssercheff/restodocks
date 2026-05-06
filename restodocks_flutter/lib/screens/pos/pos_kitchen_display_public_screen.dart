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
  DateTime? _highlightUntil;
  bool _soundEnabled = true;
  bool _autoRefreshEnabled = true;
  Timer? _autoRefreshTimer;

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
      _restartAutoRefresh();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('kds_public_sound_enabled', _soundEnabled);
      await prefs.setBool('kds_public_auto_refresh', _autoRefreshEnabled);
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
    final addedNow = <String>{};
    for (final row in snap.rows) {
      final orderId = row.order.id;
      final prev = _knownLineIdsByOrder[orderId] ?? <String>{};
      final current = row.lines.map((e) => e.id).toSet();
      for (final id in current) {
        if (!prev.contains(id) && _knownLineIdsByOrder.isNotEmpty) {
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
        SystemSound.play(SystemSoundType.alert);
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

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
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
          title: Text(loc.t('pos_kds_public_title')),
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
      ..sort((a, b) => b.order.updatedAt.compareTo(a.order.updatedAt));
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
                    Text(
                      elapsed,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      subline,
                      style: posOrderListSubtitleStyle(context),
                    ),
                    const SizedBox(height: 8),
                    for (final line in r.lines)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _lineColor(context, line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                line.dishTitleForLang(loc.currentLanguageCode),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text('x${line.quantity}'),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _showTechCardDialog(
                                  context, loc, line, r),
                              child: Text(loc.t('pos_kds_public_ttk_title')),
                            ),
                            if (line.servedAt == null &&
                                o.status == PosOrderStatus.sent)
                              FilledButton.tonal(
                                onPressed: () => _markLine(r, line),
                                child: Text(loc.t('pos_order_line_mark_served')),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
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
    var localSound = _soundEnabled;
    var localAuto = _autoRefreshEnabled;
    final selectedLang = ValueNotifier<String>(loc.currentLanguageCode);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: localAuto,
                  onChanged: (v) => setLocal(() => localAuto = v),
                  title: const Text('Auto refresh'),
                ),
                SwitchListTile(
                  value: localSound,
                  onChanged: (v) => setLocal(() => localSound = v),
                  title: const Text('Sound on new items'),
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
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Language',
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    _soundEnabled = localSound;
    _autoRefreshEnabled = localAuto;
    if (initialSound != _soundEnabled || initialAuto != _autoRefreshEnabled) {
      await _savePrefs();
      _restartAutoRefresh();
    }
    if (selectedLang.value != loc.currentLanguageCode) {
      await loc.setLocale(Locale(selectedLang.value), userChoice: true);
    }
    if (mounted) setState(() {});
  }
}
