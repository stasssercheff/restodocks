import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../legal/legal_texts.dart';
import '../services/services.dart';

class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key, this.nextPath});

  final String? nextPath;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _accept() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loc = context.read<LocalizationService>();
      await context.read<PrivacyPolicyConsentService>().acceptCurrentVersion(
            locale: loc.currentLanguageCode,
          );
      if (!mounted) return;
      final target = (widget.nextPath != null && widget.nextPath!.isNotEmpty)
          ? widget.nextPath!
          : '/home';
      context.go(target.startsWith('/') ? target : '/$target');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await context.read<AccountManagerSupabase>().logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(loc.t('privacy_policy')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('privacy_consent_required'),
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const SingleChildScrollView(
                    child: SelectableText(privacyPolicyFullTextRu),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : _accept,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(loc.t('accept_and_continue')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _loading ? null : _logout,
                child: Text(loc.t('logout')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
