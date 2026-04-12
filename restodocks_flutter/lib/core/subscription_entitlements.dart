import '../models/establishment.dart';

/// Продуктовые тарифы Lite / Pro / Ultra (после триала — «бесплатный» = Lite).
enum AppSubscriptionTier {
  lite,
  pro,
  ultra,
}

/// Доступ к функциям по тарифу и триалу 72 ч (триал = полный доступ к платным разделам,
/// отдельные лимиты — trial_increment_usage и т.д.).
class SubscriptionEntitlements {
  SubscriptionEntitlements._(this.establishment);

  final Establishment? establishment;

  factory SubscriptionEntitlements.from(Establishment? e) =>
      SubscriptionEntitlements._(e);

  bool get _hasEst => establishment != null;

  /// Бесплатный Lite: после окончания триала, без оплаченного тарифа.
  bool get isLiteTier =>
      _hasEst &&
      !establishment!.hasPaidProAccess &&
      !establishment!.isProTrialWindowActive;

  /// Триал 72 ч — как Ultra по навигации и гейтам «нужен Pro».
  bool get isTrialFullFeature =>
      establishment?.isProTrialWindowActive ?? false;

  AppSubscriptionTier get paidTier {
    final t = establishment?.subscriptionType?.toLowerCase().trim() ?? 'free';
    switch (t) {
      case 'ultra':
      case 'premium':
        return AppSubscriptionTier.ultra;
      case 'pro':
      case 'plus':
      case 'starter':
      case 'business':
        return AppSubscriptionTier.pro;
      default:
        return AppSubscriptionTier.lite;
    }
  }

  /// Эффективный уровень для UX: триал → ultra; иначе оплаченный тариф или Lite.
  AppSubscriptionTier get effectiveTier {
    if (!_hasEst) return AppSubscriptionTier.lite;
    if (isTrialFullFeature) return AppSubscriptionTier.ultra;
    if (!establishment!.hasPaidProAccess) return AppSubscriptionTier.lite;
    return paidTier;
  }

  /// Только кухня (без зала и бара): Lite вне триала.
  bool get kitchenOnlyDepartments => isLiteTier;

  /// Pro или Ultra (оплата), без триала.
  bool get hasPaidProOrUltra =>
      _hasEst &&
      establishment!.hasPaidProAccess &&
      (paidTier == AppSubscriptionTier.pro ||
          paidTier == AppSubscriptionTier.ultra);

  /// Ultra-уровень возможностей (включая триал).
  bool get hasUltraLevelFeatures =>
      effectiveTier == AppSubscriptionTier.ultra;

  /// Pro или выше по возможностям (включая триал как «всё открыто»).
  bool get hasProLevelOrTrial =>
      _hasEst && establishment!.hasEffectiveProAccess;

  /// Разделы только для Pro/Ultra/триал (не Lite).
  bool get showProHomeSections => hasProLevelOrTrial;
}
