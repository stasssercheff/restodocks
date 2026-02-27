import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_bar_home_button.dart';

/// Кабинет платформенного администратора — управление промокодами.
/// Доступен только авторизованному владельцу платформы.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _supabase = Supabase.instance.client;
  final _codeController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _expiresAt;

  List<Map<String, dynamic>> _codes = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCodes() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await _supabase
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

  Future<void> _addCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await _supabase.from('promo_codes').insert({
        'code': code,
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        'expires_at': _expiresAt?.toIso8601String(),
      });
      _codeController.clear();
      _noteController.clear();
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

    await _supabase.from('promo_codes').delete().eq('id', id);
    await _loadCodes();
  }

  Future<void> _toggleUsed(int id, bool currentUsed) async {
    await _supabase.from('promo_codes').update({
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

    await _supabase.from('promo_codes').update({
      'expires_at': picked.toIso8601String(),
    }).eq('id', id);
    await _loadCodes();
  }

  Future<void> _clearExpires(int id) async {
    await _supabase.from('promo_codes').update({'expires_at': null}).eq('id', id);
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

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: const Text('Admin — промокоды'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCodes,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          // Форма создания нового промокода
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Новый промокод', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Код',
                          hintText: 'BETA001',
                          prefixIcon: Icon(Icons.confirmation_number_outlined),
                          isDense: true,
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
                          prefixIcon: Icon(Icons.notes),
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
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _expiresAt == null
                              ? 'Без срока'
                              : 'До ${_formatDate(_expiresAt!.toIso8601String())}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    if (_expiresAt != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _expiresAt = null),
                        tooltip: 'Убрать срок',
                      ),
                    ],
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _addCode,
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add, size: 18),
                      label: const Text('Создать'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Статистика
          if (!_isLoading && _codes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _statChip(
                    label: 'Всего',
                    count: _codes.length,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    label: 'Использовано',
                    count: _codes.where((c) => c['is_used'] == true).length,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    label: 'Свободно',
                    count: _codes.where((c) => c['is_used'] == false).length,
                    color: Colors.orange,
                  ),
                ],
              ),
            ),

          // Список
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Ошибка: $_error', style: TextStyle(color: theme.colorScheme.error)))
                    : _codes.isEmpty
                        ? const Center(child: Text('Промокодов пока нет'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _codes.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) => _buildCodeTile(_codes[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _statChip({required String label, required int count, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
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
    final expired = _isExpired(expiresAt);

    Color statusColor = isUsed
        ? Colors.green
        : expired
            ? Colors.red
            : Colors.orange;

    String statusLabel = isUsed ? 'Использован' : expired ? 'Истёк' : 'Свободен';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isUsed ? Icons.check_circle : expired ? Icons.timer_off : Icons.confirmation_number,
          color: statusColor,
          size: 20,
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
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(statusLabel, style: TextStyle(fontSize: 11, color: statusColor)),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null && note.isNotEmpty)
            Text(note, style: const TextStyle(fontSize: 12)),
          if (isUsed && establishmentName != null)
            Text('Заведение: $establishmentName', style: const TextStyle(fontSize: 12)),
          if (isUsed && usedAt != null)
            Text('Использован: ${_formatDate(usedAt)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (expiresAt != null)
            Text(
              'Срок до: ${_formatDate(expiresAt)}',
              style: TextStyle(fontSize: 11, color: expired ? Colors.red : Colors.grey),
            ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          switch (action) {
            case 'toggle':
              await _toggleUsed(id, isUsed);
              break;
            case 'set_expires':
              await _setExpires(id);
              break;
            case 'clear_expires':
              await _clearExpires(id);
              break;
            case 'delete':
              await _deleteCode(id);
              break;
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'toggle',
            child: Row(children: [
              Icon(isUsed ? Icons.refresh : Icons.check, size: 18),
              const SizedBox(width: 8),
              Text(isUsed ? 'Сбросить (освободить)' : 'Отметить использованным'),
            ]),
          ),
          PopupMenuItem(
            value: 'set_expires',
            child: const Row(children: [
              Icon(Icons.calendar_today, size: 18),
              SizedBox(width: 8),
              Text('Изменить срок'),
            ]),
          ),
          if (expiresAt != null)
            const PopupMenuItem(
              value: 'clear_expires',
              child: Row(children: [
                Icon(Icons.timer_off, size: 18),
                SizedBox(width: 8),
                Text('Убрать срок'),
              ]),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Удалить', style: TextStyle(color: Colors.red)),
            ]),
          ),
        ],
      ),
    );
  }
}
