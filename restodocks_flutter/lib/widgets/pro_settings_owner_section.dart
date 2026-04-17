import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/iap_constants.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../utils/iap_product_price_format.dart';
import 'subscription_plans_dialog.dart';

String _promoTierDisplayName(LocalizationService loc, String? raw) {
  final t = (raw ?? 'pro').toLowerCase().trim();
  switch (t) {
    case 'ultra':
    case 'premium':
      return loc.t('pro_promo_scope_tier_ultra');
    case 'pro':
    case 'plus':
    case 'starter':
    case 'business':
      return loc.t('pro_promo_scope_tier_pro');
    case 'lite':
    case 'free':
      return loc.t('pro_promo_scope_tier_lite');
    default:
      return loc.t('pro_promo_scope_tier_other', args: {'name': raw ?? t});
  }
}

/// Строки «на что промокод» для диалога (тариф, пакеты, лимит) — всегда с заголовком «Что даёт».
List<Widget> _promoScopeDetailWidgets(
  LocalizationService loc,
  EstablishmentPromoInfo p,
  TextTheme textTheme,
) {
  final bodyStyle = textTheme.bodyMedium;
  final headingStyle = textTheme.titleSmall?.copyWith(
    fontWeight: FontWeight.w600,
  );
  final tierRaw = (p.grantsSubscriptionType ?? '').trim();
  final tierLabel = tierRaw.isNotEmpty
      ? _promoTierDisplayName(loc, tierRaw)
      : loc.t('pro_promo_scope_tier_unspecified');
  final hasEmployeePacks = p.grantsEmployeeSlotPacks > 0;
  final hasBranchPacks = p.grantsBranchSlotPacks > 0;

  final out = <Widget>[
    const SizedBox(height: 16),
    Text(loc.t('pro_promo_scope_heading'), style: headingStyle),
    const SizedBox(height: 8),
  ];

  if (p.grantsAdditiveOnly) {
    out.add(Text(loc.t('pro_promo_scope_additive_only'), style: bodyStyle));
    out.add(const SizedBox(height: 8));
  }

  out.add(Text(
    loc.t('pro_promo_scope_tier_prefix', args: {'tier': tierLabel}),
    style: bodyStyle,
  ));
  out.add(const SizedBox(height: 8));

  out.add(Text(
    '${loc.t('employees')}: ${hasEmployeePacks ? loc.t('answer_yes') : loc.t('answer_no')}',
    style: bodyStyle,
  ));
  out.add(const SizedBox(height: 8));

  if (hasEmployeePacks) {
    final packs = p.grantsEmployeeSlotPacks;
    final slots = packs * 5;
    out.add(Text(
      loc.t(
        'pro_promo_scope_employee_packs',
        args: {'packs': '$packs', 'slots': '$slots'},
      ),
      style: bodyStyle,
    ));
    out.add(const SizedBox(height: 8));
  }
  out.add(Text(
    '${loc.t('establishments')}: ${hasBranchPacks ? loc.t('answer_yes') : loc.t('answer_no')}',
    style: bodyStyle,
  ));
  out.add(const SizedBox(height: 8));

  if (hasBranchPacks) {
    out.add(Text(
      loc.t(
        'pro_promo_scope_branch_packs',
        args: {'packs': '${p.grantsBranchSlotPacks}'},
      ),
      style: bodyStyle,
    ));
    out.add(const SizedBox(height: 8));
  }
  if (p.promoMaxEmployees != null) {
    out.add(Text(
      loc.t('pro_promo_scope_max_employees',
          args: {'n': '${p.promoMaxEmployees}'}),
      style: bodyStyle,
    ));
  }
  return out;
}

String _iapSubscriptionPurchaseLabel(LocalizationService loc, String productId) {
  if (productId == kRestodocksUltraMonthlyProductId) {
    return loc.t('subscription_iap_purchase_ultra');
  }
  return loc.t('subscription_iap_purchase_pro');
}

/// Блок настроек подписки для собственника: промокод, тарифы, оплата (iOS IAP).
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
  /// Открывается окно «Подписка и доступ» — повторные нажатия игнорируем (иначе несколько диалогов).
  bool _proPaymentHubOpening = false;

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
      if (mounted) {
        setState(() {
          _promoFuture = widget.accountManager.getEstablishmentPromoForOwner();
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pro_iap_activated'))),
      );
    } else if (_iapWasBusy && !iap.busy && iap.lastError != null) {
      iap.clearErrorIfProActive();
      // Pro уже на сервере — не показываем ложное «ошибка» после успешной оплаты (дубли StoreKit).
      if (iap.lastError == null ||
          widget.accountManager.hasPaidProSubscription) {
        _iapWasBusy = iap.busy;
        return;
      }
      final err = iap.lastError!;
      final msg = _iapFailureMessage(loc, err);
      final restore = _iapOfferRestoreSnackAction(err);
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return AlertDialog(
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                    ),
                    if (restore) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          unawaited(iap.restorePurchases());
                        },
                        child: Text(loc.t('pro_iap_restore')),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(loc.t('close')),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    _iapWasBusy = iap.busy;
  }

  /// Apple мог уже списать деньги, а Pro на нашем сервере не активировался — не вводить в заблуждение.
  bool _shouldAppendAppleChargedHint(String code) {
    final c = code.toLowerCase();
    // Подписка уже есть у Apple ID / конфликт привязки — не дублировать про списание.
    if (c.contains('apple_subscription_already_linked')) return false;
    // Preflight: экран оплаты Apple не открывался — не добавлять текст про «уже списали».
    if (c.contains('409_preflight')) return false;
    if (c.contains('iap_session_unavailable_pre_store')) return false;
    if (c.contains('missing_user_jwt')) return false;
    if (c.contains('not_owner')) return false;
    if (c.contains('store_unavailable')) return false;
    if (c.contains('product_not')) return false;
    if (c.contains('no_receipt')) return false;
    if (c.contains('apple receipt validation') ||
        c.contains('receipt validation failed')) {
      return true;
    }
    return c.contains('verify_failed_http_') || c.contains('iap_client_exception');
  }

  /// Кнопка в SnackBar: то же, что «Восстановить покупки» в блоке PRO.
  bool _iapOfferRestoreSnackAction(String code) {
    final c = code.toLowerCase();
    if (c.contains('no_receipt')) return true;
    // Подписка уже оформлена у Apple ID — нужен «Восстановить покупки».
    if (c.contains('apple_subscription_already_linked')) return true;
    // Preflight: конфликт до листа оплаты — «Восстановить» всё равно уместно.
    if (c.contains('409_preflight')) return true;
    return _shouldAppendAppleChargedHint(code);
  }

  /// Сообщения после покупки/restore: сервер Edge `billing-verify-apple`, Apple verifyReceipt, StoreKit.
  String _iapFailureMessage(LocalizationService loc, String code) {
    final base = _iapFailureBaseMessage(loc, code);
    if (_shouldAppendAppleChargedHint(code)) {
      return '$base\n\n${loc.t('pro_iap_apple_charged_hint')}';
    }
    return base;
  }

  String _iapFailureBaseMessage(LocalizationService loc, String code) {
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
    // Нет JWT после нескольких refresh (до окна StoreKit или после чека).
    if (c.contains('iap_session_unavailable_pre_store') ||
        c.contains('iap_session_unavailable')) {
      return loc.t('pro_iap_session_missing');
    }
    // Клиент не смог получить JWT — раньше уходил anon → ложный 401 на Edge.
    if (c.contains('missing_user_jwt')) {
      return loc.t('pro_iap_session_missing');
    }
    // Сессия: JWT не принят Edge (истёк / не передан).
    if (c.contains('verify_failed_http_401') || c.contains('|unauthorized')) {
      return loc.t('pro_iap_unauthorized');
    }
    // Чек Apple привязан к другому владельцу / заведению (applicationUsername в чеке ≠ этот owner).
    if (c.contains('receipt_bound_to_other_establishment') ||
        c.contains('receipt_bound_to_other_owner')) {
      return loc.t('pro_iap_receipt_other_establishment');
    }
    // Не owner или чужое заведение.
    if (c.contains('verify_failed_http_403') ||
        c.contains('forbidden') ||
        c.contains('only owner can verify')) {
      return loc.t('pro_iap_forbidden');
    }
    // 409: сервер подтвердил активную подписку Apple ID, но привязка OTID к другому заведению.
    if (c.contains('apple_subscription_already_linked')) {
      return loc.t('pro_iap_409_subscription_restore_guidance');
    }
    if (c.contains('verify_failed_http_409')) {
      return loc.t('pro_iap_subscription_linked_other_account');
    }
    // Конфиг сервера: нет APPLE_IAP_SHARED_SECRET и т.п.
    if (c.contains('server configuration error')) {
      return loc.t('pro_iap_server_config');
    }
    // Apple verifyReceipt status !== 0
    if (c.contains('verify_failed_http_400')) {
      if (c.contains('receipt_missing_app_account_binding')) {
        return loc.t('pro_iap_binding_unverified');
      }
      final appleM = RegExp(r'apple_status_(\d+)').firstMatch(c);
      if (appleM != null) {
        return loc.t('pro_iap_apple_status_detail',
            args: {'code': appleM.group(1)!});
      }
      if (c.contains('establishment_id and receipt_data')) {
        return loc.t('pro_iap_bad_request');
      }
      return loc.t('pro_iap_apple_validation_failed');
    }
    // Любой 5xx на Edge или ошибка обновления БД
    if (RegExp(r'verify_failed_http_5\d\d').hasMatch(c)) {
      final m = RegExp(r'verify_failed_http_(\d+)').firstMatch(c);
      final st = m?.group(1) ?? '5xx';
      if (c.contains('verify_failed_http_500') && c.contains('server configuration')) {
        return loc.t('pro_iap_server_config');
      }
      return loc.t('pro_iap_server_http', args: {'status': st});
    }
    // Остальные коды ответа Edge (404 и т.д.)
    if (c.contains('verify_failed_http_')) {
      final m = RegExp(r'verify_failed_http_(\d+)').firstMatch(c);
      final st = m?.group(1) ?? '?';
      return loc.t('pro_iap_server_http', args: {'status': st});
    }
    if (c.contains('iap_client_exception')) {
      return loc.t('pro_iap_client_error');
    }
    // Старые строки без префикса HTTP (совместимость)
    if (c.contains('apple receipt validation') ||
        c.contains('receipt validation failed')) {
      return loc.t('pro_iap_apple_validation_failed');
    }
    if (c.contains('forbidden')) return loc.t('pro_iap_forbidden');
    return loc.t('pro_iap_error_with_detail', args: {'detail': _shortIapTechnical(code)});
  }

  /// Короткая строка для пользователя / поддержки (полный код в логах devLog).
  String _shortIapTechnical(String code) {
    final s = code.trim();
    if (s.length <= 200) return s;
    return '${s.substring(0, 197)}...';
  }

  /// Сумма из StoreKit ([rawPrice] + [currencyCode]), формат числа под витрину валюты — не язык приложения.
  String _formatIapProductPrice(ProductDetails product) =>
      formatIapPriceForAppleStorefront(product);

  Future<void> _openAppleSubscriptionsSettings() async {
    final uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _reloadPromo() {
    setState(() {
      _promoFuture = widget.accountManager.getEstablishmentPromoForOwner();
    });
  }

  Future<void> _syncProSectionFromServer() async {
    await widget.accountManager.syncEstablishmentAccessFromServer();
    if (!mounted) return;
    setState(() {
      _promoFuture = widget.accountManager.getEstablishmentPromoForOwner();
    });
  }

  /// Даты в блоке PRO — коротко, в формате дд.мм.гггг (без «сервера» в тексте).
  String _formatProDate(DateTime d) {
    final loc = widget.localization;
    final tag =
        loc.currentLanguageCode == 'ru' ? 'ru_RU' : loc.currentLanguageCode;
    return DateFormat('dd.MM.yyyy', tag).format(d.toLocal());
  }

  /// Дата+время окончания триала в локальной зоне устройства.
  String _formatProDateTime(DateTime d) {
    final loc = widget.localization;
    final tag =
        loc.currentLanguageCode == 'ru' ? 'ru_RU' : loc.currentLanguageCode;
    return DateFormat('dd.MM.yyyy HH:mm', tag).format(d.toLocal());
  }

  String _formatDate(DateTime d) {
    final loc = widget.localization;
    final tag = loc.currentLanguageCode == 'ru' ? 'ru_RU' : loc.currentLanguageCode;
    return DateFormat.yMMMd(tag).format(d.toLocal());
  }

  /// Строки статуса для диалога «Подписка и доступ» — по одной смысловой строке, без длинных абзацев.
  List<String> _proHubStatusLines(
    LocalizationService loc,
    EstablishmentPromoInfo promo,
    Establishment? est,
  ) {
    final lines = <String>[];
    final estSafe = est;
    final paidAccess = estSafe?.hasPaidProAccess ?? false;
    final until = estSafe?.proPaidUntil;

    if (promo.hasPromo && promo.isDisabled) {
      lines.add(loc.t('pro_payment_hub_line_promo_disabled_admin'));
    }

    if (until != null) {
      lines.add(loc.t('pro_payment_hub_line_subscription_until',
          args: {'date': _formatProDate(until)}));
    } else if (paidAccess &&
        !promo.isPromoGrantActive &&
        !(promo.hasPromo && promo.isDisabled)) {
      lines.add(loc.t('pro_payment_hub_line_subscription_active'));
    }

    if (promo.isPromoGrantActive && promo.expiresAt != null) {
      lines.add(loc.t('pro_payment_hub_line_promo_until',
          args: {'date': _formatProDate(promo.expiresAt!)}));
    }

    if (lines.isEmpty && paidAccess) {
      lines.add(loc.t('pro_payment_hub_status_fallback'));
    }
    return lines;
  }

  /// Подзаголовок пункта «Оплата подписки» в списке настроек.
  String _paidProPaymentSubtitle(
    LocalizationService loc,
    EstablishmentPromoInfo? promo,
    Establishment? est,
  ) {
    if (promo != null && promo.isPromoGrantActive) {
      return loc.t('pro_iap_already_active_promo');
    }
    if (promo != null && promo.hasPromo && promo.isDisabled) {
      return loc.t('pro_payment_subtitle_promo_disabled');
    }
    final until = est?.proPaidUntil;
    if (until != null) {
      return loc.t('pro_payment_subtitle_short_until',
          args: {'date': _formatProDate(until)});
    }
    return loc.t('pro_payment_subtitle_active_no_date');
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
                const SizedBox(height: 8),
                Text(
                  loc.t('pro_promo_code_single_use_hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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

  /// Окно «подписка и доступ»: статус (промокод / оплаченный Pro), покупка, восстановление.
  Future<void> _showProPaymentHub(AppleIapService iap, LocalizationService loc) async {
    if (_proPaymentHubOpening) return;

    if (!AppleIapService.isIOSPlatform) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.t('pro_payment_hub_title')),
          content: Text(loc.t('pro_iap_ios_only')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.t('close')),
            ),
          ],
        ),
      );
      return;
    }

    _proPaymentHubOpening = true;
    setState(() {});

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        useRootNavigator: true,
        builder: (ctx) => _ProPaymentHubFutureDialog(
          iap: iap,
          accountManager: widget.accountManager,
          loc: loc,
          statusLines: _proHubStatusLines,
          formatIapPrice: _formatIapProductPrice,
          onOpenAppleSubs: _openAppleSubscriptionsSettings,
        ),
      );
    } finally {
      _proPaymentHubOpening = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.localization;
    return ExpansionTile(
      leading: const Icon(Icons.workspace_premium_outlined),
      title: Text(loc.t('subscription_settings')),
      subtitle: Text(loc.t('subscription_settings_desc')),
      onExpansionChanged: (expanded) {
        if (expanded) unawaited(_syncProSectionFromServer());
      },
      children: [
        ListenableBuilder(
          listenable: widget.accountManager,
          builder: (context, _) {
            final est = widget.accountManager.establishment;
            final trialEndsAt = est?.proTrialEndsAt;
            if (trialEndsAt == null) return const SizedBox.shrink();
            return ListTile(
              leading: const Icon(Icons.hourglass_top_outlined),
              title: Text(loc.t('owner_trial_welcome_title')),
              subtitle: Text(_formatProDateTime(trialEndsAt)),
            );
          },
        ),
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
            final showPromoDetails = promo.isPromoGrantActive;
            String subtitle;
            if (!showPromoDetails) {
              subtitle = loc.t('pro_promo_subtitle_none');
            } else {
              subtitle = loc.t('pro_promo_subtitle_until',
                  args: {'date': _formatDate(promo.expiresAt!)});
            }
            return ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: Text(loc.t('pro_promo_title')),
              subtitle: Text(subtitle),
              trailing:
                  Icon(showPromoDetails ? Icons.info_outline : Icons.edit_outlined),
              onTap: showPromoDetails
                  ? () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) {
                          final theme = Theme.of(ctx);
                          final estName =
                              widget.accountManager.establishment?.name.trim();
                          final mutedStyle =
                              theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          );
                          return AlertDialog(
                            title: Text(loc.t('pro_promo_title')),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (estName != null && estName.isNotEmpty) ...[
                                    Text(
                                      '${loc.t('pro_promo_establishment_label')}: $estName',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  Text(
                                    '${loc.t('pro_promo_code_label')}: ${promo.code}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 16,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          loc.t('pro_promo_code_single_use_hint'),
                                          style: mutedStyle,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '${loc.t('pro_promo_valid_until_label')}: ${_formatDate(promo.expiresAt!)}',
                                  ),
                                  ..._promoScopeDetailWidgets(
                                    loc,
                                    promo,
                                    theme.textTheme,
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(
                                  MaterialLocalizations.of(ctx).okButtonLabel,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    }
                  : _showApplyPromoDialog,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.list_alt_outlined),
          title: Text(loc.t('subscription_plans_list_tile_title')),
          subtitle: Text(loc.t('subscription_plans_list_tile_subtitle')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showSubscriptionPlansDialog(context),
        ),
        FutureBuilder<EstablishmentPromoInfo>(
          future: _promoFuture,
          builder: (context, promoSnap) {
            final promo = promoSnap.data;
            return ListenableBuilder(
              listenable: widget.accountManager,
              builder: (context, _) {
                final paidPro = widget.accountManager.hasPaidProSubscription;
                return Consumer<AppleIapService>(
                  builder: (context, iap, _) {
                    final busy = iap.busy;
                    final subtitle = !paidPro
                        ? loc.t('subscription_payment_list_tile_subtitle')
                        : _paidProPaymentSubtitle(
                            loc,
                            promo,
                            widget.accountManager.establishment,
                          );
                    return ListTile(
                      leading: const Icon(Icons.payment_outlined),
                      title: Text(loc.t('subscription_payment_list_tile_title')),
                      subtitle: Text(subtitle),
                      trailing: busy
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              paidPro
                                  ? Icons.check_circle_outline
                                  : Icons.apple,
                            ),
                      onTap: (busy || _proPaymentHubOpening)
                          ? null
                          : () => _showProPaymentHub(iap, loc),
                    );
                  },
                );
              },
            );
          },
        ),
        FutureBuilder<EstablishmentPromoInfo>(
          future: _promoFuture,
          builder: (context, promoSnap) {
            return ListenableBuilder(
              listenable: widget.accountManager,
              builder: (context, _) {
                if (!AppleIapService.isIOSPlatform) {
                  return const SizedBox.shrink();
                }
                return ListTile(
                  leading: const Icon(Icons.cancel_outlined),
                  title: Text(loc.t('pro_payment_open_apple_subscriptions')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(_openAppleSubscriptionsSettings()),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

/// Один маршрут: загрузка StoreKit + данные сервера внутри диалога (без второго полноэкранного спиннера).
class _ProPaymentHubFutureDialog extends StatefulWidget {
  const _ProPaymentHubFutureDialog({
    required this.iap,
    required this.accountManager,
    required this.loc,
    required this.statusLines,
    required this.formatIapPrice,
    required this.onOpenAppleSubs,
  });

  final AppleIapService iap;
  final AccountManagerSupabase accountManager;
  final LocalizationService loc;
  final List<String> Function(
    LocalizationService loc,
    EstablishmentPromoInfo promo,
    Establishment? est,
  ) statusLines;
  final String Function(ProductDetails product) formatIapPrice;
  final Future<void> Function() onOpenAppleSubs;

  @override
  State<_ProPaymentHubFutureDialog> createState() =>
      _ProPaymentHubFutureDialogState();
}

class _ProPaymentHubFutureDialogState extends State<_ProPaymentHubFutureDialog> {
  late final Future<_ProHubPreload> _preload;
  bool _establishmentsExpanded = true;
  bool _employeesExpanded = true;

  ({int? count, bool establishments}) _parseAddonId(String productId) {
    final m = RegExp(r'^(\d+)_extra_(establishment|employee)_monthly$')
        .firstMatch(productId.trim());
    if (m == null) return (count: null, establishments: true);
    return (
      count: int.tryParse(m.group(1) ?? ''),
      establishments: m.group(2) == 'establishment',
    );
  }

  String _fallbackAddonTitle(LocalizationService loc, String productId) {
    final parsed = _parseAddonId(productId);
    final count = parsed.count;
    if (count != null) {
      final lang = loc.currentLanguageCode.toLowerCase();
      if (lang == 'ru') {
        final noun = parsed.establishments ? 'Заведение' : 'Сотрудник';
        return '$noun +$count';
      }
      final noun = parsed.establishments ? 'Establishment' : 'Employee';
      return '$noun +$count';
    }
    final cleaned = productId.trim();
    if (cleaned.isEmpty) return productId;
    final noSuffix = cleaned.replaceAll(RegExp(r'_monthly$', caseSensitive: false), '');
    return noSuffix.replaceAll('_', ' ');
  }

  String _addonDisplayTitle(LocalizationService loc, String productId, ProductDetails? product) {
    final title = product?.title.trim() ?? '';
    if (title.isNotEmpty) {
      // Store title can stay as fallback, but prefer clear localized label by product id.
      final parsed = _parseAddonId(productId);
      if (parsed.count == null) return title;
    }
    return _fallbackAddonTitle(loc, productId);
  }

  String _iapPriceMonthlyLabel(ProductDetails p) {
    return widget.loc.t(
      'iap_price_monthly',
      args: {'price': widget.formatIapPrice(p)},
    );
  }

  ButtonStyle _subscriptionButtonStyle(ColorScheme cs) {
    return FilledButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
    );
  }

  Widget _addonGroupSection({
    required ThemeData theme,
    required ColorScheme cs,
    required String title,
    required bool initiallyExpanded,
    required ValueChanged<bool> onExpansionChanged,
    required List<String> addonIds,
    required Map<String, ProductDetails> addonsById,
  }) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 6),
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        iconColor: cs.onSurfaceVariant,
        collapsedIconColor: cs.onSurfaceVariant,
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        onExpansionChanged: onExpansionChanged,
        children: [
          for (final addonId in addonIds) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: addonsById[addonId] != null
                  ? FilledButton(
                      style: _subscriptionButtonStyle(cs),
                      onPressed: () {
                        Navigator.pop(context);
                        unawaited(widget.iap.purchaseAddon(addonsById[addonId]!.id));
                      },
                      child: Text(
                        '${_addonDisplayTitle(widget.loc, addonId, addonsById[addonId])} - ${_iapPriceMonthlyLabel(addonsById[addonId]!)}',
                      ),
                    )
                  : OutlinedButton(
                      onPressed: null,
                      child: Text(
                        '${_addonDisplayTitle(widget.loc, addonId, null)} - ${widget.loc.t('pro_iap_product_unavailable')}',
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _preload = _runPreload();
  }

  Future<_ProHubPreload> _runPreload() async {
    await Future.wait<void>([
      widget.iap.init(),
      widget.accountManager.syncEstablishmentAccessFromServer(),
    ]);
    final promo = await widget.accountManager.getEstablishmentPromoForOwner();
    return _ProHubPreload(promo: promo);
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    return FutureBuilder<_ProHubPreload>(
      future: _preload,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(loc.t('pro_payment_hub_loading'))),
              ],
            ),
          );
        }
        if (snap.hasError) {
          debugPrint('_ProPaymentHubFutureDialog: ${snap.error}');
          return AlertDialog(
            title: Text(loc.t('pro_payment_hub_title')),
            content: Text(loc.t('pro_payment_hub_load_error')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(loc.t('close')),
              ),
            ],
          );
        }
        final promo = snap.data!.promo;
        return ListenableBuilder(
          listenable: widget.accountManager,
          builder: (context, _) {
            final paid = widget.accountManager.hasPaidProSubscription;
            final est = widget.accountManager.establishment;
            final subs = widget.iap.subscriptionProducts;
            final addons = widget.iap.addonProducts;
            final addonsById = <String, ProductDetails>{
              for (final addon in addons) addon.id: addon,
            };
            final addonIdsInOrder = kRestodocksAddonProductIdOrder;
            final establishmentAddonIds = addonIdsInOrder
                .where((id) => _parseAddonId(id).establishments)
                .toList();
            final employeeAddonIds = addonIdsInOrder
                .where((id) => !_parseAddonId(id).establishments)
                .toList();
            final ready = widget.iap.ready;
            final theme = Theme.of(context);
            final cs = theme.colorScheme;
            final maxH = MediaQuery.sizeOf(context).height * 0.88;
            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              paid
                                  ? Icons.verified_outlined
                                  : Icons.apple,
                              size: 28,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                loc.t('pro_payment_hub_title'),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (paid) ...[
                          ...widget
                              .statusLines(loc, promo, est)
                              .map(
                                (line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    line,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(height: 1.4),
                                  ),
                                ),
                              ),
                        ] else ...[
                          Text(
                            loc.t('pro_payment_body_short'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                          if (ready && subs.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            for (final d in subs) ...[
                              FilledButton(
                                style: _subscriptionButtonStyle(cs),
                                onPressed: () {
                                  Navigator.pop(context);
                                  unawaited(widget.iap.purchaseSubscription(d.id));
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_iapSubscriptionPurchaseLabel(loc, d.id)),
                                    Text(
                                      _iapPriceMonthlyLabel(d),
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: cs.onPrimary.withValues(alpha: 0.88),
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (addons.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _addonGroupSection(
                                theme: theme,
                                cs: cs,
                                title: loc.t('establishments'),
                                initiallyExpanded: _establishmentsExpanded,
                                onExpansionChanged: (v) {
                                  setState(() => _establishmentsExpanded = v);
                                },
                                addonIds: establishmentAddonIds,
                                addonsById: addonsById,
                              ),
                              _addonGroupSection(
                                theme: theme,
                                cs: cs,
                                title: loc.t('employees'),
                                initiallyExpanded: _employeesExpanded,
                                onExpansionChanged: (v) {
                                  setState(() => _employeesExpanded = v);
                                },
                                addonIds: employeeAddonIds,
                                addonsById: addonsById,
                              ),
                              Text(
                                loc.t('subscription_iap_addons_hint'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              loc.t('pro_cancel_anytime_notice'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 12),
                            Text(
                              !ready
                                  ? loc.t('pro_iap_store_unavailable')
                                  : loc.t('pro_iap_product_unavailable'),
                              style: TextStyle(
                                color: cs.error,
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                        if (!paid) ...[
                          const SizedBox(height: 12),
                          Text(
                            loc.t('pro_payment_hub_restore_hint'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (paid) ...[
                          OutlinedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await widget.onOpenAppleSubs();
                            },
                            child: Text(loc.t('pro_cancel_subscription_title')),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            loc.t('pro_cancel_subscription_subtitle'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        OutlinedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await widget.iap.restorePurchases();
                          },
                          child: Text(loc.t('pro_iap_restore')),
                        ),
                        if (!paid)
                          TextButton(
                            onPressed: () async {
                              await widget.onOpenAppleSubs();
                            },
                            child: Text(
                              loc.t('pro_payment_open_apple_subscriptions'),
                            ),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(loc.t('close')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProHubPreload {
  _ProHubPreload({required this.promo});
  final EstablishmentPromoInfo promo;
}
