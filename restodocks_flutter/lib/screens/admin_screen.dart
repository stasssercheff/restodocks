import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Кабинет платформенного администратора бэты.
/// Вкладки: Дашборд, Промокоды, Заведения, Пользователи, Поддержка.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('admin_title')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.dashboard_outlined), text: loc.t('admin_tab_dashboard')),
            Tab(icon: const Icon(Icons.confirmation_number_outlined), text: loc.t('admin_tab_promo_codes')),
            Tab(icon: const Icon(Icons.store_outlined), text: loc.t('admin_tab_establishments')),
            Tab(icon: const Icon(Icons.people_outline), text: loc.t('admin_tab_users')),
            Tab(icon: const Icon(Icons.support_agent_outlined), text: loc.t('admin_tab_support')),
          ],
          labelStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DashboardTab(supabase: _supabase),
          _PromoCodesTab(supabase: _supabase),
          _EstablishmentsTab(supabase: _supabase),
          _UsersTab(supabase: _supabase),
          _SupportTab(supabase: _supabase),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ДАШБОРД
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({required this.supabase});
  final SupabaseClient supabase;

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.supabase.from('establishments').select('id, created_at').order('created_at'),
        widget.supabase.from('employees').select('id, roles, is_active, created_at').order('created_at'),
        widget.supabase.from('promo_codes').select('id, is_used, expires_at, created_at').order('created_at'),
      ]);

      final establishments = results[0] as List;
      final employees = results[1] as List;
      final promoCodes = results[2] as List;

      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final monthAgo = now.subtract(const Duration(days: 30));

      final owners = employees.where((e) {
        final roles = e['roles'];
        if (roles is List) return roles.contains('owner');
        return false;
      }).toList();

      final newEstThisWeek = establishments.where((e) {
        final d = DateTime.tryParse(e['created_at'] ?? '');
        return d != null && d.isAfter(weekAgo);
      }).length;

      final newEstThisMonth = establishments.where((e) {
        final d = DateTime.tryParse(e['created_at'] ?? '');
        return d != null && d.isAfter(monthAgo);
      }).length;

      final usedCodes = promoCodes.where((c) => c['is_used'] == true).length;
      final freeCodes = promoCodes.where((c) => c['is_used'] == false).length;
      final expiredCodes = promoCodes.where((c) {
        final exp = c['expires_at'] as String?;
        if (exp == null) return false;
        final d = DateTime.tryParse(exp);
        return d != null && d.isBefore(now);
      }).length;

      // Регистрации по дням (последние 14 дней)
      final Map<String, int> registrationsByDay = {};
      for (var i = 13; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final key = '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}';
        registrationsByDay[key] = 0;
      }
      for (final e in establishments) {
        final d = DateTime.tryParse(e['created_at'] ?? '');
        if (d != null && d.isAfter(now.subtract(const Duration(days: 14)))) {
          final key = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
          registrationsByDay[key] = (registrationsByDay[key] ?? 0) + 1;
        }
      }

      setState(() {
        _stats = {
          'total_establishments': establishments.length,
          'new_this_week': newEstThisWeek,
          'new_this_month': newEstThisMonth,
          'total_employees': employees.length,
          'total_owners': owners.length,
          'total_promo_codes': promoCodes.length,
          'used_promo_codes': usedCodes,
          'free_promo_codes': freeCodes,
          'expired_promo_codes': expiredCodes,
          'registrations_by_day': registrationsByDay,
        };
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.t('error_generic', args: {'error': _error!})),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(loc.t('retry'))),
          ],
        ),
      );
    }
    final s = _stats!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(loc.t('admin_section_establishments')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _KpiCard(
                icon: Icons.store,
                label: loc.t('admin_kpi_total'),
                value: '${s['total_establishments']}',
                color: Colors.blue,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.fiber_new,
                label: loc.t('admin_kpi_this_week'),
                value: '+${s['new_this_week']}',
                color: Colors.green,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.calendar_month,
                label: loc.t('admin_kpi_this_month'),
                value: '+${s['new_this_month']}',
                color: Colors.teal,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _SectionTitle(loc.t('admin_section_users')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _KpiCard(
                icon: Icons.people,
                label: loc.t('admin_kpi_employees'),
                value: '${s['total_employees']}',
                color: Colors.purple,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.manage_accounts,
                label: loc.t('admin_kpi_owners'),
                value: '${s['total_owners']}',
                color: Colors.indigo,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _SectionTitle(loc.t('admin_section_promo_codes')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _KpiCard(
                icon: Icons.confirmation_number,
                label: loc.t('admin_kpi_total'),
                value: '${s['total_promo_codes']}',
                color: Colors.orange,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.check_circle,
                label: loc.t('admin_kpi_used'),
                value: '${s['used_promo_codes']}',
                color: Colors.green,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.lock_open,
                label: loc.t('admin_kpi_free'),
                value: '${s['free_promo_codes']}',
                color: Colors.lightBlue,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _SectionTitle(loc.t('admin_section_registrations_14d')),
          const SizedBox(height: 8),
          _BarChart(data: Map<String, int>.from(s['registrations_by_day'])),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: theme.textTheme.headlineSmall?.copyWith(
                  color: color, fontWeight: FontWeight.bold)),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6))),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.data});
  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVal = data.values.isEmpty ? 1 : (data.values.reduce(max) == 0 ? 1 : data.values.reduce(max));
    final keys = data.keys.toList();

    return Container(
      height: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: keys.map((key) {
          final val = data[key] ?? 0;
          final height = (val / maxVal) * 70;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (val > 0)
                    Text('$val',
                        style: TextStyle(
                            fontSize: 8,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Container(
                    height: val == 0 ? 2 : height.clamp(2.0, 70.0),
                    decoration: BoxDecoration(
                      color: val == 0
                          ? theme.colorScheme.outlineVariant
                          : theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(key,
                      style: TextStyle(
                          fontSize: 7,
                          color: theme.colorScheme.onSurface.withOpacity(0.5))),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ПРОМОКОДЫ
// ─────────────────────────────────────────────────────────────────────────────

class _PromoCodesTab extends StatefulWidget {
  const _PromoCodesTab({required this.supabase});
  final SupabaseClient supabase;

  @override
  State<_PromoCodesTab> createState() => _PromoCodesTabState();
}

class _PromoCodesTabState extends State<_PromoCodesTab> {
  final _codeController = TextEditingController();
  final _noteController = TextEditingController();
  final _maxEmployeesController = TextEditingController();
  final _bulkCountController = TextEditingController(text: '5');
  late DateTime _expiresAt;

  List<Map<String, dynamic>> _codes = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String _filter = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _expiresAt = DateTime.now().add(const Duration(days: 30));
    _loadCodes();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _noteController.dispose();
    _maxEmployeesController.dispose();
    _bulkCountController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCodes() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await widget.supabase
          .from('promo_codes')
          .select(
            '*, '
            'establishments:used_by_establishment_id(name, email), '
            'promo_code_redemptions('
            'redeemed_at, '
            'establishments:establishment_id(name, email)'
            ')',
          )
          .order('created_at', ascending: false);
      setState(() => _codes = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredCodes {
    final now = DateTime.now();
    return _codes.where((c) {
      final code = (c['code'] as String? ?? '').toLowerCase();
      final note = (c['note'] as String? ?? '').toLowerCase();
      final q = _searchQuery.toLowerCase();
      if (q.isNotEmpty && !code.contains(q) && !note.contains(q)) return false;
      if (_filter == 'free') return c['is_used'] == false;
      if (_filter == 'used') return c['is_used'] == true;
      if (_filter == 'expired') {
        final exp = c['expires_at'] as String?;
        if (exp == null) return false;
        final d = DateTime.tryParse(exp);
        return d != null && d.isBefore(now);
      }
      return true;
    }).toList();
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return 'BETA' + List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _addCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final maxEmp = int.tryParse(_maxEmployeesController.text.trim());
      await widget.supabase.from('promo_codes').insert({
        'code': code,
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        'expires_at': _expiresAt.toIso8601String(),
        'max_employees': maxEmp,
      });
      _codeController.clear();
      _noteController.clear();
      _maxEmployeesController.clear();
      setState(() => _expiresAt = DateTime.now().add(const Duration(days: 30)));
      await _loadCodes();
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('error_generic', args: {'error': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _bulkCreateCodes() async {
    final loc = context.read<LocalizationService>();
    final count = int.tryParse(_bulkCountController.text.trim()) ?? 5;
    if (count < 1 || count > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('admin_promo_qty_range'))),
      );
      return;
    }

    final note = _noteController.text.trim();
    final maxEmp = int.tryParse(_maxEmployeesController.text.trim());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('admin_create_n_promos_title', args: {'count': '$count'})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.t('admin_create_n_promos_body', args: {'count': '$count'})),
            if (note.isNotEmpty) Text(loc.t('admin_note_line', args: {'note': note})),
            if (maxEmp != null) Text(loc.t('admin_limit_employees_line', args: {'max': '$maxEmp'})),
            Text(loc.t('admin_expires_line', args: {'date': _formatDate(_expiresAt.toIso8601String())})),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.t('admin_button_create'))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final existing = _codes.map((c) => c['code'] as String).toSet();
      final rows = <Map<String, dynamic>>[];
      final usedInBatch = <String>{};
      int attempts = 0;
      while (rows.length < count && attempts < count * 10) {
        final code = _generateCode();
        if (!existing.contains(code) && !usedInBatch.contains(code)) {
          usedInBatch.add(code);
          rows.add({
            'code': code,
            'note': note.isEmpty ? null : note,
            'expires_at': _expiresAt.toIso8601String(),
            'max_employees': maxEmp,
          });
        }
        attempts++;
      }
      await widget.supabase.from('promo_codes').insert(rows);
      if (mounted) {
        final locOk = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(locOk.t('admin_promos_created', args: {'count': '${rows.length}'})),
            backgroundColor: Colors.green,
          ),
        );
      }
      _noteController.clear();
      _maxEmployeesController.clear();
      setState(() => _expiresAt = DateTime.now().add(const Duration(days: 30)));
      await _loadCodes();
    } catch (e) {
      if (mounted) {
        final locErr = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(locErr.t('error_generic', args: {'error': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteCode(int id) async {
    final loc = context.read<LocalizationService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('admin_delete_promo_title')),
        content: Text(loc.t('admin_delete_promo_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.t('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(loc.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.supabase.from('promo_codes').delete().eq('id', id);
    await _loadCodes();
  }

  Future<void> _toggleUsed(int id, bool currentUsed) async {
    await widget.supabase.from('promo_codes').update({
      'is_used': !currentUsed,
      'used_at': !currentUsed ? DateTime.now().toIso8601String() : null,
      'used_by_establishment_id': currentUsed ? null : null,
    }).eq('id', id);
    await _loadCodes();
  }

  Future<void> _setExpires(int id) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    await widget.supabase.from('promo_codes').update({
      'expires_at': picked.toIso8601String(),
    }).eq('id', id);
    await _loadCodes();
  }

  Future<void> _setMaxEmployees(int id, int? current) async {
    final loc = context.read<LocalizationService>();
    final controller = TextEditingController(text: current?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('admin_employee_limit_title')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: loc.t('admin_max_employees_label'),
            hintText: loc.t('admin_hint_example_10'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc.t('cancel'))),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, v);
            },
            child: Text(loc.t('save')),
          ),
        ],
      ),
    );
    if (result == null) return;
    await widget.supabase.from('promo_codes').update({'max_employees': result}).eq('id', id);
    await _loadCodes();
  }

  Future<void> _clearMaxEmployees(int id) async {
    await widget.supabase.from('promo_codes').update({'max_employees': null}).eq('id', id);
    await _loadCodes();
  }

  Future<void> _pickNewCodeExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  bool _isExpired(String? iso) {
    if (iso == null) return false;
    final d = DateTime.tryParse(iso);
    if (d == null) return false;
    return d.isBefore(DateTime.now());
  }

  /// Погашения из [promo_code_redemptions] (название, email заведения, дата) или legacy по колонкам promo_codes.
  List<Widget> _promoUsageSubtitleWidgets(
    Map<String, dynamic> row,
    LocalizationService loc,
  ) {
    final raw = row['promo_code_redemptions'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          list.add(item);
        } else if (item is Map) {
          list.add(Map<String, dynamic>.from(item));
        }
      }
    }
    list.sort((a, b) {
      final da = DateTime.tryParse(a['redeemed_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b['redeemed_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return da.compareTo(db);
    });

    final out = <Widget>[];

    if (list.isNotEmpty) {
      out.add(const SizedBox(height: 2));
      out.add(Text(
        loc.t('admin_promo_who_used'),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ));
      for (final r in list) {
        final est = r['establishments'];
        var nameDisp = '—';
        var emailDisp = '—';
        if (est is Map) {
          final n = est['name']?.toString().trim();
          final e = est['email']?.toString().trim();
          if (n != null && n.isNotEmpty) nameDisp = n;
          if (e != null && e.isNotEmpty) emailDisp = e;
        }
        final redeemed = r['redeemed_at']?.toString();
        final dateDisp = redeemed != null ? _formatDate(redeemed) : '—';
        out.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            loc.t('admin_promo_usage_line', args: {
              'name': nameDisp,
              'email': emailDisp,
              'date': dateDisp,
            }),
            style: const TextStyle(fontSize: 10),
          ),
        ));
      }
      return out;
    }

    final isUsed = row['is_used'] == true;
    final usedAt = row['used_at'] as String?;
    final estRow = row['establishments'] as Map?;
    final establishmentName = estRow?['name'] as String?;
    final establishmentEmail = estRow?['email'] as String?;
    if (isUsed &&
        (establishmentName != null ||
            establishmentEmail != null ||
            usedAt != null)) {
      out.add(const SizedBox(height: 2));
      out.add(Text(
        loc.t('admin_promo_who_used'),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ));
      out.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          loc.t('admin_promo_usage_line', args: {
            'name': (establishmentName != null && establishmentName.isNotEmpty)
                ? establishmentName
                : '—',
            'email': (establishmentEmail != null && establishmentEmail.isNotEmpty)
                ? establishmentEmail
                : '—',
            'date': usedAt != null ? _formatDate(usedAt) : '—',
          }),
          style: const TextStyle(fontSize: 10),
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocalizationService>();
    final filtered = _filteredCodes;

    return Column(
      children: [
        // Форма создания
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(loc.t('admin_new_promo'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: loc.t('admin_field_code'),
                        hintText: loc.t('admin_code_hint'),
                        prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 18),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.auto_fix_high, size: 16),
                          onPressed: () => _codeController.text = _generateCode(),
                          tooltip: loc.t('admin_generate_tooltip'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _noteController,
                      decoration: InputDecoration(
                        labelText: loc.t('admin_field_note'),
                        hintText: loc.t('admin_hint_for_whom'),
                        prefixIcon: const Icon(Icons.notes, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _maxEmployeesController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: loc.t('admin_field_employees_short'),
                        hintText: '∞',
                        prefixIcon: const Icon(Icons.people_outline, size: 16),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickNewCodeExpiry,
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: Text(
                        loc.t('admin_until_prefix',
                            args: {'date': _formatDate(_expiresAt.toIso8601String())}),
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _addCode,
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add, size: 16),
                    label: Text(loc.t('admin_button_create')),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Массовое создание
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _bulkCreateCodes,
                    icon: const Icon(Icons.burst_mode, size: 16),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('×'),
                        SizedBox(
                          width: 32,
                          child: TextField(
                            controller: _bulkCountController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Поиск + фильтры
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: loc.t('admin_search_code_note'),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _FilterChip(label: loc.t('admin_filter_all', args: {'count': '${_codes.length}'}), value: 'all', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _FilterChip(label: loc.t('admin_filter_free'), value: 'free', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _FilterChip(label: loc.t('admin_filter_used'), value: 'used', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _FilterChip(label: loc.t('admin_filter_expired'), value: 'expired', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _loadCodes,
                    tooltip: loc.t('refresh'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Список
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(loc.t('error_generic', args: {'error': _error!})))
                  : filtered.isEmpty
                      ? Center(child: Text(loc.t('admin_nothing_found')))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) => _buildCodeTile(filtered[i]),
                        ),
        ),
      ],
    );
  }

  Widget _buildCodeTile(Map<String, dynamic> row) {
    final loc = context.watch<LocalizationService>();
    final id = row['id'] as int;
    final code = row['code'] as String;
    final isUsed = row['is_used'] == true;
    final note = row['note'] as String?;
    final expiresAt = row['expires_at'] as String?;
    final maxEmployees = row['max_employees'] as int?;
    final expired = _isExpired(expiresAt);

    Color statusColor = isUsed ? Colors.green : expired ? Colors.red : Colors.orange;
    final statusLabel = isUsed
        ? loc.t('admin_promo_status_used')
        : expired
            ? loc.t('admin_promo_status_expired')
            : loc.t('admin_promo_status_free');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isUsed ? Icons.check_circle : expired ? Icons.timer_off : Icons.confirmation_number,
          color: statusColor,
          size: 18,
        ),
      ),
      title: Row(
        children: [
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.t('admin_code_copied')), duration: const Duration(seconds: 1)),
              );
            },
            child: Text(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor)),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null && note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 11)),
          ..._promoUsageSubtitleWidgets(row, loc),
          if (expiresAt != null)
            Text(loc.t('admin_expires_line', args: {'date': _formatDate(expiresAt)}),
                style: TextStyle(fontSize: 10, color: expired ? Colors.red : Colors.grey)),
          Text(
            loc.t('admin_employees_line', args: {
              'value': maxEmployees != null ? '≤ $maxEmployees' : '∞',
            }),
            style: TextStyle(fontSize: 10, color: maxEmployees != null ? Colors.blueGrey : Colors.grey),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          switch (action) {
            case 'toggle': await _toggleUsed(id, isUsed); break;
            case 'set_expires': await _setExpires(id); break;
            case 'set_max_employees': await _setMaxEmployees(id, maxEmployees); break;
            case 'clear_max_employees': await _clearMaxEmployees(id); break;
            case 'delete': await _deleteCode(id); break;
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'toggle',
            child: Row(children: [
              Icon(isUsed ? Icons.refresh : Icons.check, size: 16),
              const SizedBox(width: 8),
              Text(isUsed ? loc.t('admin_action_free') : loc.t('admin_action_mark_used')),
            ]),
          ),
          PopupMenuItem(
            value: 'set_expires',
            child: Row(children: [
              const Icon(Icons.calendar_today, size: 16),
              const SizedBox(width: 8),
              Text(loc.t('admin_change_expiry')),
            ]),
          ),
          PopupMenuItem(
            value: 'set_max_employees',
            child: Row(children: [
              const Icon(Icons.people_outline, size: 16),
              const SizedBox(width: 8),
              Text(maxEmployees != null ? loc.t('admin_change_limit') : loc.t('admin_set_limit')),
            ]),
          ),
          if (maxEmployees != null)
            PopupMenuItem(
              value: 'clear_max_employees',
              child: Row(children: [
                const Icon(Icons.people_alt, size: 16),
                const SizedBox(width: 8),
                Text(loc.t('admin_remove_limit')),
              ]),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              const Icon(Icons.delete, size: 16, color: Colors.red),
              const SizedBox(width: 8),
              Text(loc.t('delete'), style: const TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  final String label;
  final String value;
  final String current;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = value == current;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ЗАВЕДЕНИЯ
// ─────────────────────────────────────────────────────────────────────────────

class _EstablishmentsTab extends StatefulWidget {
  const _EstablishmentsTab({required this.supabase});
  final SupabaseClient supabase;

  @override
  State<_EstablishmentsTab> createState() => _EstablishmentsTabState();
}

class _EstablishmentsTabState extends State<_EstablishmentsTab> {
  List<Map<String, dynamic>> _establishments = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.supabase
          .from('establishments')
          .select('id, name, address, phone, email, default_currency, owner_id, created_at')
          .order('created_at', ascending: false);

      // Загружаем кол-во сотрудников для каждого заведения
      final empCounts = await widget.supabase
          .from('employees')
          .select('establishment_id');

      final Map<String, int> countMap = {};
      for (final e in (empCounts as List)) {
        final id = e['establishment_id'] as String?;
        if (id != null) countMap[id] = (countMap[id] ?? 0) + 1;
      }

      // Загружаем промокоды для заведений
      final promoCodes = await widget.supabase
          .from('promo_codes')
          .select('used_by_establishment_id, code, expires_at')
          .eq('is_used', true);

      final Map<String, Map<String, dynamic>> promoMap = {};
      for (final p in (promoCodes as List)) {
        final id = p['used_by_establishment_id'] as String?;
        if (id != null) promoMap[id] = p;
      }

      setState(() {
        _establishments = (data as List).map((e) {
          final m = Map<String, dynamic>.from(e);
          m['employee_count'] = countMap[e['id']] ?? 0;
          m['promo'] = promoMap[e['id']];
          return m;
        }).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _establishments;
    return _establishments.where((e) {
      final name = (e['name'] as String? ?? '').toLowerCase();
      final address = (e['address'] as String? ?? '').toLowerCase();
      final email = (e['email'] as String? ?? '').toLowerCase();
      return name.contains(q) || address.contains(q) || email.contains(q);
    }).toList();
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  bool _isPromoExpired(Map<String, dynamic>? promo) {
    if (promo == null) return false;
    final exp = promo['expires_at'] as String?;
    if (exp == null) return false;
    final d = DateTime.tryParse(exp);
    return d != null && d.isBefore(DateTime.now());
  }

  void _showDetails(Map<String, dynamic> est) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => _EstablishmentDetails(
          est: est,
          scrollController: scrollController,
          formatDate: _formatDate,
          isPromoExpired: _isPromoExpired,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: loc.t('admin_search_establishment'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
                tooltip: loc.t('refresh'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                loc.t('admin_total_establishments', args: {'count': '${_establishments.length}'}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  loc.t('admin_found_establishments', args: {'count': '${_filtered.length}'}),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(loc.t('error_generic', args: {'error': _error!})),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: Text(loc.t('retry'))),
                        ],
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(child: Text(loc.t('admin_nothing_found')))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final est = _filtered[i];
                              final promo = est['promo'] as Map<String, dynamic>?;
                              final promoExpired = _isPromoExpired(promo);
                              final empCount = est['employee_count'] as int;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: promoExpired
                                      ? Colors.red.withOpacity(0.1)
                                      : Colors.blue.withOpacity(0.1),
                                  child: Text(
                                    (est['name'] as String? ?? '?').characters.first.toUpperCase(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: promoExpired ? Colors.red : Colors.blue,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  est['name'] as String? ?? '—',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      loc.t('admin_registered_line', args: {'date': _formatDate(est['created_at'] as String?)}),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Row(
                                      children: [
                                        Icon(Icons.people_outline, size: 12,
                                            color: Colors.grey.shade600),
                                        const SizedBox(width: 3),
                                        Text(loc.t('admin_emp_count_short', args: {'count': '$empCount'}),
                                            style: const TextStyle(fontSize: 11)),
                                        if (promo != null) ...[
                                          const SizedBox(width: 8),
                                          Icon(Icons.confirmation_number_outlined, size: 12,
                                              color: promoExpired ? Colors.red : Colors.green),
                                          const SizedBox(width: 3),
                                          Text(
                                            promo['code'] as String? ?? '—',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: promoExpired ? Colors.red : Colors.green,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          if (promoExpired)
                                            Text(loc.t('admin_expired_suffix'),
                                                style: const TextStyle(fontSize: 10, color: Colors.red)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                                onTap: () => _showDetails(est),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _EstablishmentDetails extends StatelessWidget {
  const _EstablishmentDetails({
    required this.est,
    required this.scrollController,
    required this.formatDate,
    required this.isPromoExpired,
  });

  final Map<String, dynamic> est;
  final ScrollController scrollController;
  final String Function(String?) formatDate;
  final bool Function(Map<String, dynamic>?) isPromoExpired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocalizationService>();
    final promo = est['promo'] as Map<String, dynamic>?;
    final promoExpired = isPromoExpired(promo);
    final empCount = est['employee_count'] as int;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.blue.withOpacity(0.1),
              child: Text(
                (est['name'] as String? ?? '?').characters.first.toUpperCase(),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(est['name'] as String? ?? '—',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(loc.t('admin_registered_line', args: {'date': formatDate(est['created_at'] as String?)}),
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _DetailRow(icon: Icons.people_outline, label: loc.t('admin_detail_employees'), value: '$empCount'),
        if (est['address'] != null && (est['address'] as String).isNotEmpty)
          _DetailRow(icon: Icons.location_on_outlined, label: loc.t('admin_detail_address'), value: est['address'] as String),
        if (est['phone'] != null && (est['phone'] as String).isNotEmpty)
          _DetailRow(icon: Icons.phone_outlined, label: loc.t('admin_detail_phone'), value: est['phone'] as String),
        if (est['email'] != null && (est['email'] as String).isNotEmpty)
          _DetailRow(icon: Icons.email_outlined, label: loc.t('email_label'), value: est['email'] as String),
        _DetailRow(
          icon: Icons.currency_exchange,
          label: loc.t('admin_detail_currency'),
          value: est['default_currency'] as String? ?? 'RUB',
        ),
        const Divider(height: 24),
        Text(loc.t('admin_promo_section'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (promo == null)
          Text(loc.t('admin_promo_not_linked'), style: const TextStyle(color: Colors.grey))
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: promoExpired
                  ? Colors.red.withOpacity(0.05)
                  : Colors.green.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: promoExpired
                    ? Colors.red.withOpacity(0.3)
                    : Colors.green.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.confirmation_number_outlined,
                        size: 16, color: promoExpired ? Colors.red : Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      promo['code'] as String? ?? '—',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: promoExpired ? Colors.red : Colors.green,
                      ),
                    ),
                    if (promoExpired) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(loc.t('admin_expired_badge'),
                            style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                if (promo['expires_at'] != null) ...[
                  const SizedBox(height: 4),
                  Text(loc.t('admin_expires_line', args: {'date': formatDate(promo['expires_at'] as String?)}),
                      style: TextStyle(
                          fontSize: 12,
                          color: promoExpired ? Colors.red : Colors.grey)),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(loc.t('admin_id_line', args: {'id': '${est['id']}'}),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ПОЛЬЗОВАТЕЛИ
// ─────────────────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.supabase});
  final SupabaseClient supabase;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  bool _ownersOnly = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.supabase
          .from('employees')
          .select('id, full_name, surname, email, roles, department, is_active, created_at, establishment_id, establishments:establishment_id(name)')
          .order('created_at', ascending: false);

      setState(() {
        _users = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _users.where((u) {
      if (_ownersOnly) {
        final roles = u['roles'];
        final isOwner = roles is List && roles.contains('owner');
        if (!isOwner) return false;
      }
      final q = _searchQuery.toLowerCase();
      if (q.isEmpty) return true;
      final name = (u['full_name'] as String? ?? '').toLowerCase();
      final surname = (u['surname'] as String? ?? '').toLowerCase();
      final email = (u['email'] as String? ?? '').toLowerCase();
      final estName = ((u['establishments'] as Map?)?['name'] as String? ?? '').toLowerCase();
      return name.contains(q) || surname.contains(q) || email.contains(q) || estName.contains(q);
    }).toList();
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _rolesLabel(LocalizationService loc, dynamic roles) {
    if (roles is! List || roles.isEmpty) return loc.t('admin_role_fallback');
    return roles.map((r) => loc.roleDisplayName(r.toString())).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final filtered = _filtered;
    final ownersCount = _users.where((u) {
      final roles = u['roles'];
      return roles is List && roles.contains('owner');
    }).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: loc.t('admin_users_search_hint'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
                tooltip: loc.t('refresh'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(loc.t('admin_users_total', args: {'total': '${_users.length}', 'owners': '$ownersCount'}),
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _ownersOnly = !_ownersOnly),
                child: Row(
                  children: [
                    Checkbox(
                      value: _ownersOnly,
                      onChanged: (v) => setState(() => _ownersOnly = v ?? false),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    Text(loc.t('admin_only_owners'), style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(loc.t('error_generic', args: {'error': _error!})),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: Text(loc.t('retry'))),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(child: Text(loc.t('admin_nothing_found')))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final u = filtered[i];
                              final roles = u['roles'];
                              final isOwner = roles is List && roles.contains('owner');
                              final isActive = u['is_active'] == true;
                              final estName = (u['establishments'] as Map?)?['name'] as String?;
                              final fullName = [
                                u['full_name'] as String? ?? '',
                                u['surname'] as String? ?? '',
                              ].where((s) => s.isNotEmpty).join(' ');

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 3),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isOwner
                                      ? Colors.indigo.withOpacity(0.1)
                                      : Colors.grey.withOpacity(0.1),
                                  child: Icon(
                                    isOwner ? Icons.manage_accounts : Icons.person_outline,
                                    size: 18,
                                    color: isOwner ? Colors.indigo : Colors.grey,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fullName.isEmpty ? '—' : fullName,
                                        style: const TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!isActive)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(loc.t('admin_inactive_short'),
                                            style: const TextStyle(
                                                fontSize: 9, color: Colors.grey)),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(u['email'] as String? ?? '—',
                                        style: const TextStyle(fontSize: 11)),
                                    Row(
                                      children: [
                                        Text(
                                          _rolesLabel(loc, roles),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isOwner ? Colors.indigo : Colors.grey,
                                            fontWeight: isOwner ? FontWeight.w600 : FontWeight.normal,
                                          ),
                                        ),
                                        if (estName != null) ...[
                                          const Text(' • ',
                                              style: TextStyle(fontSize: 11, color: Colors.grey)),
                                          Expanded(
                                            child: Text(
                                              estName,
                                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(loc.t('admin_list_line', args: {'date': _formatDate(u['created_at'] as String?)}),
                                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ПОДДЕРЖКА: по PIN заведения (при включённом доступе в настройках клиента)
// ─────────────────────────────────────────────────────────────────────────────

class _SupportTab extends StatefulWidget {
  const _SupportTab({required this.supabase});
  final SupabaseClient supabase;

  @override
  State<_SupportTab> createState() => _SupportTabState();
}

class _SupportTabState extends State<_SupportTab> {
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _payload;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final loc = context.read<LocalizationService>();
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _payload = null;
    });
    try {
      final raw = await widget.supabase
          .rpc('support_lookup_establishment_by_pin', params: {'p_pin': pin});
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _error = loc.t('admin_support_error_not_found');
          _loading = false;
        });
        return;
      }
      final map = Map<String, dynamic>.from(raw as Map);
      final ok = map['ok'] == true;
      if (!ok) {
        final reason = map['reason']?.toString() ?? '';
        String msg;
        switch (reason) {
          case 'forbidden':
            msg = loc.t('admin_support_error_forbidden');
            break;
          case 'support_disabled':
            msg = loc.t('admin_support_error_disabled');
            break;
          case 'not_found':
            msg = loc.t('admin_support_error_not_found');
            break;
          case 'invalid_pin':
            msg = loc.t('admin_support_error_invalid_pin');
            break;
          default:
            msg = loc.t('error_generic', args: {'error': reason});
        }
        setState(() {
          _error = msg;
          _loading = false;
        });
        return;
      }
      setState(() {
        _payload = map;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final est = _payload?['establishment'] as Map<String, dynamic>?;
    final employees = _payload?['employees'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(loc.t('admin_support_intro'),
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _pinController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: loc.t('admin_support_pin_label'),
            hintText: loc.t('admin_support_pin_hint'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (!_loading) _lookup();
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _lookup,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search, size: 20),
          label: Text(loc.t('admin_support_lookup')),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (est != null) ...[
          const SizedBox(height: 24),
          Text(loc.t('admin_support_result_title'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _kv(loc, 'ID', est['id']?.toString() ?? '—'),
          _kv(loc, loc.t('company_name'), est['name']?.toString() ?? '—'),
          _kv(loc, loc.t('company_pin'), est['pin_code']?.toString() ?? '—'),
          _kv(loc, loc.t('admin_support_field_address'),
              (est['address'] ?? '').toString().trim().isEmpty
                  ? '—'
                  : est['address'].toString()),
          _kv(loc, loc.t('admin_support_field_phone'),
              (est['phone'] ?? '').toString().trim().isEmpty
                  ? '—'
                  : est['phone'].toString()),
          _kv(loc, loc.t('admin_support_field_est_email'),
              (est['email'] ?? '').toString().trim().isEmpty
                  ? '—'
                  : est['email'].toString()),
          _kv(loc, loc.t('admin_support_field_currency'),
              (est['default_currency'] ?? '').toString().trim().isEmpty
                  ? '—'
                  : est['default_currency'].toString()),
          _kv(loc, loc.t('admin_support_field_subscription'),
              (est['subscription_type'] ?? '').toString().trim().isEmpty
                  ? '—'
                  : est['subscription_type'].toString()),
          _kv(loc, loc.t('admin_support_field_parent_id'),
              (est['parent_establishment_id'] ?? '').toString().trim().isEmpty
                  ? '—'
                  : est['parent_establishment_id'].toString()),
          const SizedBox(height: 16),
          Text(loc.t('admin_support_employees_title'),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (employees is List && employees.isNotEmpty)
            ...employees.map((e) {
              final row = Map<String, dynamic>.from(e as Map);
              final name = [
                row['full_name'] as String? ?? '',
                row['surname'] as String? ?? '',
              ].where((s) => s.isNotEmpty).join(' ');
              final em = row['email'] as String? ?? '';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(name.isEmpty ? '—' : name),
                subtitle: Text(em.isEmpty ? '—' : em),
              );
            })
          else
            Text(loc.t('admin_support_no_employees'), style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _kv(LocalizationService loc, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(k, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
