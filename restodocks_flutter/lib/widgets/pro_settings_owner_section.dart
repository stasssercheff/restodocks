import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 14),
          behavior: SnackBarBehavior.floating,
          content: Text(msg),
          action: restore
              ? SnackBarAction(
                  label: loc.t('pro_iap_restore'),
                  onPressed: () => iap.restorePurchases(),
                )
              : null,
        ),
      );
    }
    _iapWasBusy = iap.busy;
  }

  /// Apple мог уже списать деньги, а Pro на нашем сервере не активировался — не вводить в заблуждение.
  bool _shouldAppendAppleChargedHint(String code) {
    final c = code.toLowerCase();
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
    // Не owner или чужое заведение.
    if (c.contains('verify_failed_http_403') ||
        c.contains('forbidden') ||
        c.contains('only owner can verify')) {
      return loc.t('pro_iap_forbidden');
    }
    // Подписка Apple уже привязана к другому заведению в Restodocks.
    if (c.contains('verify_failed_http_409') ||
        c.contains('apple_subscription_already_linked')) {
      return loc.t('pro_iap_subscription_linked_other_account');
    }
    // Конфиг сервера: нет APPLE_IAP_SHARED_SECRET и т.п.
    if (c.contains('server configuration error')) {
      return loc.t('pro_iap_server_config');
    }
    // Apple verifyReceipt status !== 0
    if (c.contains('verify_failed_http_400')) {
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

  /// Цена из StoreKit + ISO-код валюты (USD/VND и т.д. — задаёт Apple для Apple ID, не приложение).
  String _formatIapProductPrice(ProductDetails product) {
    final cc = product.currencyCode.trim();
    if (cc.isEmpty) return product.price;
    return '${product.price} · $cc';
  }

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
    if (AppleIapService.isIOSPlatform &&
        !widget.accountManager.hasPaidProSubscription) {
      final iap = context.read<AppleIapService>();
      await iap.init();
      await iap.trySyncProFromStoreReceipt();
      await widget.accountManager.syncEstablishmentAccessFromServer();
    }
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
      title: Text(loc.t('pro_settings')),
      subtitle: Text(loc.t('pro_settings_desc')),
      onExpansionChanged: (expanded) {
        if (expanded) unawaited(_syncProSectionFromServer());
      },
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
                                  '${loc.t('pro_promo_valid_until_label')}: ${_formatDate(promo.expiresAt!)}'),
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
                        ? loc.t('pro_payment_subtitle')
                        : _paidProPaymentSubtitle(
                            loc,
                            promo,
                            widget.accountManager.establishment,
                          );
                    return ListTile(
                      leading: const Icon(Icons.payment_outlined),
                      title: Text(loc.t('pro_payment_title')),
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
            final product = widget.iap.product;
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
                          if (est != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              '${loc.t('currency')}: ${est.defaultCurrency} (${est.currencySymbol})',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ],
                          if (ready && product != null) ...[
                            const SizedBox(height: 16),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 12,
                                ),
                                child: Text(
                                  widget.formatIapPrice(product),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              loc.t('pro_payment_price_note'),
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
                        const SizedBox(height: 14),
                        Text(
                          loc.t('pro_payment_hub_restore_hint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          loc.t('pro_iap_apple_account_hint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!paid && ready && product != null) ...[
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(context);
                              unawaited(widget.iap.purchasePro());
                            },
                            child: Text(loc.t('pro_purchase')),
                          ),
                          const SizedBox(height: 10),
                        ],
                        OutlinedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await widget.iap.restorePurchases();
                          },
                          child: Text(loc.t('pro_iap_restore')),
                        ),
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
