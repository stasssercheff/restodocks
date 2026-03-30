import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/services.dart';
import 'post_registration_trial_dialog.dart';

/// Блок настроек PRO для собственника: промокод, оплата (заглушка), условия.
class ProSettingsOwnerSection extends StatefulWidget {
  const ProSettingsOwnerSection({
    super.key,
    required this.localization,
    required this.accountManager,
  });

  final LocalizationService localization;
  final AccountManagerSupabase accountManager;

  @override
  State<ProSettingsOwnerSection> createState() => _ProSettingsOwnerSectionState();
}

class _ProSettingsOwnerSectionState extends State<ProSettingsOwnerSection> {
  late Future<EstablishmentPromoInfo> _promoFuture;

  @override
  void initState() {
    super.initState();
    _promoFuture = widget.accountManager.getEstablishmentPromoForOwner();
  }

  String _formatDate(DateTime d) {
    final loc = widget.localization;
    final tag = loc.currentLanguageCode == 'ru' ? 'ru_RU' : loc.currentLanguageCode;
    return DateFormat.yMMMd(tag).format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.localization;
    return ExpansionTile(
      leading: const Icon(Icons.workspace_premium_outlined),
      title: Text(loc.t('pro_settings')),
      subtitle: Text(loc.t('pro_settings_desc')),
      children: [
        FutureBuilder<EstablishmentPromoInfo>(
          future: _promoFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: Text(loc.t('pro_promo_title')),
                subtitle: Text(loc.t('loading')),
              );
            }
            final promo = snap.data ?? const EstablishmentPromoInfo();
            if (promo.loadFailed) {
              return ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: Text(loc.t('pro_promo_title')),
                subtitle: Text(loc.t('pro_promo_load_error')),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() {
                    _promoFuture = widget.accountManager.getEstablishmentPromoForOwner();
                  }),
                ),
              );
            }
            final hasPromo = promo.hasPromo;
            String subtitle;
            if (!hasPromo) {
              subtitle = loc.t('pro_promo_subtitle_none');
            } else if (promo.expiresAt != null) {
              subtitle = loc.t('pro_promo_subtitle_until',
                  args: {'date': _formatDate(promo.expiresAt!)});
            } else {
              subtitle = loc.t('pro_promo_subtitle_no_expiry');
            }
            return ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: Text(loc.t('pro_promo_title')),
              subtitle: Text(subtitle),
              trailing: hasPromo ? const Icon(Icons.info_outline) : null,
              onTap: hasPromo
                  ? () {
                      final expText = promo.expiresAt != null
                          ? _formatDate(promo.expiresAt!)
                          : loc.t('pro_promo_subtitle_no_expiry');
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(loc.t('pro_promo_title')),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${loc.t('pro_promo_code_label')}: ${promo.code}'),
                              const SizedBox(height: 12),
                              Text(
                                  '${loc.t('pro_promo_valid_until_label')}: $expText'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                  MaterialLocalizations.of(ctx).okButtonLabel),
                            ),
                          ],
                        ),
                      );
                    }
                  : null,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.payment_outlined),
          title: Text(loc.t('pro_payment_title')),
          subtitle: Text(loc.t('pro_payment_subtitle')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(loc.t('pro_payment_title')),
                content: SingleChildScrollView(
                  child: Text(loc.t('pro_payment_body')),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child:
                        Text(MaterialLocalizations.of(ctx).okButtonLabel),
                  ),
                ],
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(loc.t('pro_conditions_title')),
          subtitle: Text(loc.t('pro_conditions_subtitle')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showPostRegistrationTrialDialog(context),
        ),
      ],
    );
  }
}
