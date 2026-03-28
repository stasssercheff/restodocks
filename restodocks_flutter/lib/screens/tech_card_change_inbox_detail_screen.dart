import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Согласование заявки на изменение ТТК (владелец).
class TechCardChangeInboxDetailScreen extends StatefulWidget {
  const TechCardChangeInboxDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<TechCardChangeInboxDetailScreen> createState() =>
      _TechCardChangeInboxDetailScreenState();
}

class _TechCardChangeInboxDetailScreenState
    extends State<TechCardChangeInboxDetailScreen> {
  bool _loading = true;
  Object? _error;
  Map<String, dynamic>? _row;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await TechCardChangeRequestService.instance
          .getById(widget.requestId);
      if (!mounted) return;
      setState(() {
        _row = r;
        _loading = false;
        if (r == null) _error = 'missing';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _approve() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (emp == null) return;
    final loc = context.read<LocalizationService>();
    setState(() => _loading = true);
    try {
      await TechCardChangeRequestService.instance.approve(
        requestId: widget.requestId,
        resolverEmployeeId: emp.id,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('tech_card_change_approved'))),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _reject() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (emp == null) return;
    final loc = context.read<LocalizationService>();
    setState(() => _loading = true);
    try {
      await TechCardChangeRequestService.instance.reject(
        requestId: widget.requestId,
        resolverEmployeeId: emp.id,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('tech_card_change_rejected'))),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('ttk_change_inbox_title')),
      ),
      body: _loading && _row == null
          ? const Center(child: CircularProgressIndicator())
          : _error == 'missing' || _row == null
              ? Center(child: Text(loc.t('error')))
              : _buildBody(loc),
    );
  }

  Widget _buildBody(LocalizationService loc) {
    final payload = _row!['proposed_payload'];
    String dish = '—';
    if (payload is Map<String, dynamic>) {
      final c = payload['card'];
      if (c is Map<String, dynamic>) {
        dish = c['dish_name']?.toString() ?? dish;
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            dish,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            loc.t('ttk_change_inbox_hint'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: loc.t('pos_cash_shift_notes_optional'),
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _loading ? null : _reject,
                  child: Text(loc.t('tech_card_change_reject')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : _approve,
                  child: Text(loc.t('tech_card_change_approve')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
