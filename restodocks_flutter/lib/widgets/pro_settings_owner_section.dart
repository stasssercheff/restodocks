import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import 'post_registration_trial_dialog.dart';

/// Блок настроек PRO для собственника: промокод, оплата (iOS IAP), условия.
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
  AppleIapService? _iap;
  int _lastIapSuccessToken = 0;
  bool _iapWasBusy = false;
  Timer? _promoReloadDebounce;

  @override
  void initState() {
    super.initState();
    _promoFuture = widget.accountManager.getEstablishmentPromoForOwner();
    widget.accountManager.addListener(_onAccountChanged);
  }

  void _onAccountChanged() {
    if (!mounted) return;
    _promoReloadDebounce?.cancel();
    _promoReloadDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _reloadPromo();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final iap = context.read<AppleIapService>();
    if (!identical(_iap, iap)) {
      _iap?.removeListener(_onIapChanged);
      _iap = iap;
      _iap?.addListener(_onIapChanged);
    }
  }

  @override
  void dispose() {
    _promoReloadDebounce?.cancel();
    widget.accountManager.removeListener(_onAccountChanged);
    _iap?.removeListener(_onIapChanged);
    super.dispose();
  }

  void _onIapChanged() {
    final iap = _iap;
    if (iap == null || !mounted) return;
    final loc = widget.localization;

    if (iap.successToken != _lastIapSuccessToken && iap.successToken > 0) {
      _lastIapSuccessToken = iap.successToken;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pro_iap_activated'))),
      );
    } else if (_iapWasBusy && !iap.busy && iap.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_iapFailureMessage(loc, iap.lastError!))),
      );
    }
    _iapWasBusy = iap.busy;
  }

  /// Сообщения после покупки/restore: сервер, чек, роль и т.д.
  String _iapFailureMessage(LocalizationService loc, String code) {
    final c = code.toLowerCase();
    if (c.contains('store_unavailable')) return loc.t('pro_iap_store_unavailable');
    if (c.contains('product_not') || c.contains('product_not_ready')) {
      return loc.t('pro_iap_product_unavailable');
    }
    if (c.contains('not_owner')) return loc.t('pro_iap_not_owner');
    if (c.contains('no_receipt')) return loc.t('pro_iap_no_receipt');
    if (c.contains('verify_failed_http_429') || c.contains('too many requests')) {
      return loc.t('pro_iap_rate_limited');
    }
    if (c.contains('verify_failed_http_500') ||
        c.contains('server configuration error')) {
      return loc.t('pro_iap_server_config');
    }
    if (c.contains('verify_failed_http_400') ||
        c.contains('apple receipt validation') ||
        c.contains('receipt validation failed')) {
      return loc.t('pro_iap_apple_validation_failed');
    }
    return loc.t('pro_iap_error');
  }

  /// StoreKit 2: [AppStoreProduct2Details.price] — это `Product.displayPrice` от Apple (как в листе оплаты).
  /// StoreKit 1: в плагине цена склеивается из символа и числа — пересчитываем из [rawPrice]/[currencyCode].
  /// Google Play: оставляем готовую строку [ProductDetails.price].
  String _formatIapProductPrice(BuildContext context, ProductDetails product) {
    if (product is AppStoreProduct2Details) {
      return product.price;
    }
    if (product is AppStoreProductDetails) {
      final code = product.currencyCode.trim();
      if (code.isEmpty) return product.price;
      try {
        final locale = Localizations.localeOf(context);
        return NumberFormat.currency(
          locale: locale.toString(),
          name: code,
        ).format(product.rawPrice);
      } catch (_) {
        try {
          return NumberFormat.simpleCurrency(name: code).format(product.rawPrice);
        } catch (_) {
          return product.price;
        }
      }
    }
    return product.price;
  }

  void _reloadPromo() {
    setState(() {
      _promoFuture = widget.accountManager.getEstablishmentPromoForOwner();
    });
  }

  String _formatDate(DateTime d) {
    final loc = widget.localization;
    final tag = loc.currentLanguageCode == 'ru' ? 'ru_RU' : loc.currentLanguageCode;
    return DateFormat.yMMMd(tag).format(d.toLocal());
  }

  String? _promoErrorFromException(Object e, LocalizationService loc) {
    final msg = e.toString();
    if (msg.contains('PROMO_INVALID')) return loc.t('promo_code_invalid');
    if (msg.contains('PROMO_USED')) return loc.t('promo_code_used');
    if (msg.contains('PROMO_NOT_STARTED')) return loc.t('promo_code_not_started');
    if (msg.contains('PROMO_EXPIRED')) return loc.t('promo_code_expired');
    if (msg.contains('PROMO_DISABLED')) return loc.t('promo_code_disabled');
    if (msg.contains('ESTABLISHMENT_HAS_PROMO')) {
      return loc.t('establishment_has_promo');
    }
    return null;
  }

  Future<void> _showApplyPromoDialog() async {
    final loc = widget.localization;
    final controller = TextEditingController();
    var busy = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(loc.t('pro_promo_enter_title')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: loc.t('promo_code'),
                    hintText: loc.t('enter_promo_code'),
                  ),
                  enabled: !busy,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final code = controller.text.trim();
                        if (code.isEmpty) {
                          setDialogState(() => dialogError = loc.t('promo_code_required'));
                          return;
                        }
                        setDialogState(() {
                          busy = true;
                          dialogError = null;
                        });
                        try {
                          await widget.accountManager.applyPromoToEstablishmentForOwner(code);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          _reloadPromo();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(loc.t('pro_promo_applied'))),
                          );
                        } catch (e) {
                          setDialogState(() {
                            busy = false;
                            dialogError =
                                _promoErrorFromException(e, loc) ?? e.toString();
                          });
                        }
                      },
                child: Text(loc.t('pro_promo_apply')),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
  }

  Future<void> _onPaymentTap(AppleIapService iap, LocalizationService loc) async {
    if (!AppleIapService.isIOSPlatform) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pro_iap_ios_only'))),
      );
      return;
    }
    if (widget.accountManager.hasPaidProSubscription) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pro_iap_paid_already'))),
      );
      return;
    }
    await iap.init();
    if (!mounted) return;
    if (!iap.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pro_iap_store_unavailable'))),
      );
      return;
    }
    if (iap.product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pro_iap_product_unavailable'))),
      );
      return;
    }
    final product = iap.product!;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final priceText = _formatIapProductPrice(ctx, product);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.apple, size: 40, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    loc.t('pro_payment_title'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    loc.t('pro_payment_body'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 12,
                      ),
                      child: Text(
                        priceText,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    loc.t('pro_payment_price_note'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(loc.t('pro_purchase')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx, false);
                      await iap.restorePurchases();
                    },
                    child: Text(loc.t('pro_iap_restore')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(loc.t('cancel')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (ok == true && mounted) {
      await iap.purchasePro();
    }
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
                  onPressed: _reloadPromo,
                ),
              );
            }
            final hasPromo = promo.hasPromo;
            String subtitle;
            if (!hasPromo) {
              subtitle = loc.t('pro_promo_subtitle_none');
            } else if (promo.isDisabled) {
              subtitle = loc.t('pro_promo_subtitle_disabled');
            } else if (promo.expiresAt != null) {
              subtitle = loc.t('pro_promo_subtitle_until',
                  args: {'date': _formatDate(promo.expiresAt!)});
            } else {
              subtitle = loc.t('pro_promo_subtitle_no_expiry');
            }
            final subtitleStyle = hasPromo && promo.isDisabled
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null;
            return ListTile(
              leading: Icon(
                hasPromo && promo.isDisabled
                    ? Icons.block_flipped
                    : Icons.local_offer_outlined,
              ),
              title: Text(loc.t('pro_promo_title')),
              subtitle: Text(subtitle, style: subtitleStyle),
              trailing: Icon(hasPromo ? Icons.info_outline : Icons.edit_outlined),
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
                              if (promo.isDisabled) ...[
                                Text(
                                  loc.t('promo_code_disabled'),
                                  style: TextStyle(
                                    color: Theme.of(ctx).colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
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
                  : _showApplyPromoDialog,
            );
          },
        ),
        Consumer<AppleIapService>(
          builder: (context, iap, _) {
            final busy = iap.busy;
            return ListTile(
              leading: const Icon(Icons.payment_outlined),
              title: Text(loc.t('pro_payment_title')),
              subtitle: Text(loc.t('pro_payment_subtitle')),
              trailing: busy
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.apple),
              onTap: busy ? null : () => _onPaymentTap(iap, loc),
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
