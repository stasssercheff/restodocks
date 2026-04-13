import '../models/establishment.dart';

/// Продуктовые тарифы Lite / Pro / Ultra (после триала — «бесплатный» = Lite).
enum AppSubscriptionTier {
  lite,
  pro,
  ultra,
}

/// Доступ к функциям по тарифу и триалу 72 ч (триал = полный доступ к платным разделам,
/// отдельные лимиты — trial_increment_usage и т.д.).
///
/// Базовые лимиты активных «слотов» сотрудников (без пакетов +5): Lite 3, Pro 8, Ultra 15
/// — на стороне БД (`establishment_active_employee_cap`); собственник без должности
/// (в `roles` только owner) в счёт не идёт (`employee_row_counts_toward_cap`).
///
/// **Lite (бесплатный после триала), целевой продукт:**
/// 1) График · 2) Номенклатура · 3) ТТК без фото, создание вручную, для зала без описания
/// · 4) Меню, фудкост недоступен · 5) одно заведение · 6) Сообщения только текст (чаты: без фото/голоса/ссылок)
/// · 7) до 3 сотрудников в лимите (см. БД), апгрейд Pro для большего
/// · 8) без сохранения файлов на устройство · 9) сотрудники — только постоянные (где применимо)
/// · 10) Расходы — только расчёт ФЗП по часам/смене без выгрузки
/// · 11) центральная кнопка навигации — всегда график (владелец Lite)
/// · 12) все языки · 13) только кухня (без зала и бара), в т.ч. график — только блок кухни
/// (маршруты all/bar/hall отображаются как кухня; средняя кнопка → `/schedule/kitchen`).
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

  /// Сохранение расчёта ФЗП в файл на устройство (Excel и т.д.) — не в чистом Lite после триала.
  bool get canExportSalaryPayrollToDevice => _hasEst && !isLiteTier;
}
