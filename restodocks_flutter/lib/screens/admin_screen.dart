import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_bar_home_button.dart';

/// Кабинет платформенного администратора бэты.
/// Вкладки: Дашборд, Промокоды, Заведения, Пользователи.
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
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: const Text('Бета-Админка'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Дашборд'),
            Tab(icon: Icon(Icons.confirmation_number_outlined), text: 'Промокоды'),
            Tab(icon: Icon(Icons.store_outlined), text: 'Заведения'),
            Tab(icon: Icon(Icons.people_outline), text: 'Пользователи'),
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ошибка: $_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Повторить')),
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
          _SectionTitle('Заведения'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _KpiCard(
                icon: Icons.store,
                label: 'Всего',
                value: '${s['total_establishments']}',
                color: Colors.blue,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.fiber_new,
                label: 'За неделю',
                value: '+${s['new_this_week']}',
                color: Colors.green,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.calendar_month,
                label: 'За месяц',
                value: '+${s['new_this_month']}',
                color: Colors.teal,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _SectionTitle('Пользователи'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _KpiCard(
                icon: Icons.people,
                label: 'Сотрудников',
                value: '${s['total_employees']}',
                color: Colors.purple,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.manage_accounts,
                label: 'Владельцев',
                value: '${s['total_owners']}',
                color: Colors.indigo,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _SectionTitle('Промокоды'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _KpiCard(
                icon: Icons.confirmation_number,
                label: 'Всего',
                value: '${s['total_promo_codes']}',
                color: Colors.orange,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.check_circle,
                label: 'Использовано',
                value: '${s['used_promo_codes']}',
                color: Colors.green,
              )),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(
                icon: Icons.lock_open,
                label: 'Свободно',
                value: '${s['free_promo_codes']}',
                color: Colors.lightBlue,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _SectionTitle('Регистрации за последние 14 дней'),
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
  DateTime? _expiresAt;

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
          .select('*, establishments:used_by_establishment_id(name)')
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
        'expires_at': _expiresAt?.toIso8601String(),
        'max_employees': maxEmp,
      });
      _codeController.clear();
      _noteController.clear();
      _maxEmployeesController.clear();
      setState(() => _expiresAt = null);
      await _loadCodes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _bulkCreateCodes() async {
    final count = int.tryParse(_bulkCountController.text.trim()) ?? 5;
    if (count < 1 || count > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Количество от 1 до 100')),
      );
      return;
    }

    final note = _noteController.text.trim();
    final maxEmp = int.tryParse(_maxEmployeesController.text.trim());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Создать $count промокодов?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Будет сгенерировано $count уникальных кодов'),
            if (note.isNotEmpty) Text('Заметка: $note'),
            if (maxEmp != null) Text('Лимит: $maxEmp сотрудников'),
            if (_expiresAt != null) Text('Срок до: ${_formatDate(_expiresAt!.toIso8601String())}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
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
            'expires_at': _expiresAt?.toIso8601String(),
            'max_employees': maxEmp,
          });
        }
        attempts++;
      }
      await widget.supabase.from('promo_codes').insert(rows);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Создано ${rows.length} промокодов'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _noteController.clear();
      _maxEmployeesController.clear();
      setState(() => _expiresAt = null);
      await _loadCodes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteCode(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить промокод?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
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

  Future<void> _clearExpires(int id) async {
    await widget.supabase.from('promo_codes').update({'expires_at': null}).eq('id', id);
    await _loadCodes();
  }

  Future<void> _setMaxEmployees(int id, int? current) async {
    final controller = TextEditingController(text: current?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Лимит сотрудников'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Макс. количество сотрудников',
            hintText: 'Например: 10',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, v);
            },
            child: const Text('Сохранить'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Text('Новый промокод', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Код',
                        hintText: 'BETA001',
                        prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 18),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.auto_fix_high, size: 16),
                          onPressed: () => _codeController.text = _generateCode(),
                          tooltip: 'Сгенерировать',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Заметка',
                        hintText: 'Для кого',
                        prefixIcon: Icon(Icons.notes, size: 18),
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
                      decoration: const InputDecoration(
                        labelText: 'Сотр.',
                        hintText: '∞',
                        prefixIcon: Icon(Icons.people_outline, size: 16),
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
                        _expiresAt == null
                            ? 'Без срока'
                            : 'До ${_formatDate(_expiresAt!.toIso8601String())}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ),
                  if (_expiresAt != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _expiresAt = null),
                      tooltip: 'Убрать срок',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _addCode,
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add, size: 16),
                    label: const Text('Создать'),
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
                  hintText: 'Поиск по коду или заметке...',
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
                  _FilterChip(label: 'Все (${_codes.length})', value: 'all', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _FilterChip(label: 'Свободные', value: 'free', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _FilterChip(label: 'Использованные', value: 'used', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _FilterChip(label: 'Истёкшие', value: 'expired', current: _filter,
                      onTap: (v) => setState(() => _filter = v)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _loadCodes,
                    tooltip: 'Обновить',
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
                  ? Center(child: Text('Ошибка: $_error'))
                  : filtered.isEmpty
                      ? const Center(child: Text('Ничего не найдено'))
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
    final id = row['id'] as int;
    final code = row['code'] as String;
    final isUsed = row['is_used'] == true;
    final note = row['note'] as String?;
    final expiresAt = row['expires_at'] as String?;
    final usedAt = row['used_at'] as String?;
    final establishmentName = (row['establishments'] as Map?)?['name'] as String?;
    final maxEmployees = row['max_employees'] as int?;
    final expired = _isExpired(expiresAt);

    Color statusColor = isUsed ? Colors.green : expired ? Colors.red : Colors.orange;
    String statusLabel = isUsed ? 'Использован' : expired ? 'Истёк' : 'Свободен';

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
                const SnackBar(content: Text('Код скопирован'), duration: Duration(seconds: 1)),
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
          if (isUsed && establishmentName != null)
            Text('Заведение: $establishmentName', style: const TextStyle(fontSize: 11)),
          if (isUsed && usedAt != null)
            Text('Использован: ${_formatDate(usedAt)}',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          if (expiresAt != null)
            Text('Срок до: ${_formatDate(expiresAt)}',
                style: TextStyle(fontSize: 10, color: expired ? Colors.red : Colors.grey)),
          Text(
            'Сотрудники: ${maxEmployees != null ? '≤ $maxEmployees' : '∞'}',
            style: TextStyle(fontSize: 10, color: maxEmployees != null ? Colors.blueGrey : Colors.grey),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          switch (action) {
            case 'toggle': await _toggleUsed(id, isUsed); break;
            case 'set_expires': await _setExpires(id); break;
            case 'clear_expires': await _clearExpires(id); break;
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
              Text(isUsed ? 'Освободить' : 'Отметить использованным'),
            ]),
          ),
          PopupMenuItem(
            value: 'set_expires',
            child: const Row(children: [
              Icon(Icons.calendar_today, size: 16),
              SizedBox(width: 8),
              Text('Изменить срок'),
            ]),
          ),
          if (expiresAt != null)
            const PopupMenuItem(
              value: 'clear_expires',
              child: Row(children: [
                Icon(Icons.timer_off, size: 16),
                SizedBox(width: 8),
                Text('Убрать срок'),
              ]),
            ),
          PopupMenuItem(
            value: 'set_max_employees',
            child: Row(children: [
              const Icon(Icons.people_outline, size: 16),
              const SizedBox(width: 8),
              Text(maxEmployees != null ? 'Изменить лимит' : 'Задать лимит'),
            ]),
          ),
          if (maxEmployees != null)
            const PopupMenuItem(
              value: 'clear_max_employees',
              child: Row(children: [
                Icon(Icons.people_alt, size: 16),
                SizedBox(width: 8),
                Text('Убрать лимит'),
              ]),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Удалить', style: TextStyle(color: Colors.red)),
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
            color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
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
                    hintText: 'Поиск заведения...',
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
                tooltip: 'Обновить',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Всего: ${_establishments.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  'Найдено: ${_filtered.length}',
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
                          Text('Ошибка: $_error'),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Повторить')),
                        ],
                      ),
                    )
                  : _filtered.isEmpty
                      ? const Center(child: Text('Ничего не найдено'))
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
                                      'Зарегистрировано: ${_formatDate(est['created_at'] as String?)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Row(
                                      children: [
                                        Icon(Icons.people_outline, size: 12,
                                            color: Colors.grey.shade600),
                                        const SizedBox(width: 3),
                                        Text('$empCount сотр.',
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
                                            const Text(' (истёк)',
                                                style: TextStyle(fontSize: 10, color: Colors.red)),
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
                  Text('Зарегистрировано: ${formatDate(est['created_at'] as String?)}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _DetailRow(icon: Icons.people_outline, label: 'Сотрудников', value: '$empCount'),
        if (est['address'] != null && (est['address'] as String).isNotEmpty)
          _DetailRow(icon: Icons.location_on_outlined, label: 'Адрес', value: est['address'] as String),
        if (est['phone'] != null && (est['phone'] as String).isNotEmpty)
          _DetailRow(icon: Icons.phone_outlined, label: 'Телефон', value: est['phone'] as String),
        if (est['email'] != null && (est['email'] as String).isNotEmpty)
          _DetailRow(icon: Icons.email_outlined, label: 'Email', value: est['email'] as String),
        _DetailRow(
          icon: Icons.currency_exchange,
          label: 'Валюта',
          value: est['default_currency'] as String? ?? 'RUB',
        ),
        const Divider(height: 24),
        Text('Промокод', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (promo == null)
          const Text('Промокод не привязан', style: TextStyle(color: Colors.grey))
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
                        child: const Text('ИСТЁК',
                            style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                if (promo['expires_at'] != null) ...[
                  const SizedBox(height: 4),
                  Text('Срок до: ${formatDate(promo['expires_at'] as String?)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: promoExpired ? Colors.red : Colors.grey)),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text('ID: ${est['id']}',
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

  String _rolesLabel(dynamic roles) {
    if (roles is! List || roles.isEmpty) return 'Сотрудник';
    const map = {
      'owner': 'Владелец',
      'executive_chef': 'Шеф-повар',
      'sous_chef': 'Су-шеф',
      'cook': 'Повар',
      'brigadier': 'Бригадир',
      'bartender': 'Бармен',
      'waiter': 'Официант',
    };
    return roles.map((r) => map[r] ?? r).join(', ');
  }

  @override
  Widget build(BuildContext context) {
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
                    hintText: 'Поиск по имени, email, заведению...',
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
                tooltip: 'Обновить',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('Всего: ${_users.length}  •  Владельцев: $ownersCount',
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
                    const Text('Только владельцы', style: TextStyle(fontSize: 12)),
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
                          Text('Ошибка: $_error'),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Повторить')),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? const Center(child: Text('Ничего не найдено'))
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
                                        child: const Text('неакт.',
                                            style: TextStyle(
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
                                          _rolesLabel(roles),
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
                                    Text('Рег.: ${_formatDate(u['created_at'] as String?)}',
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
