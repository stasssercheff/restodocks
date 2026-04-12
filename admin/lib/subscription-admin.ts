/**
 * Сводка Pro для админки: статус, способ (IAP / промокод), дата окончания.
 * Логика согласована с клиентом: effective Pro = оплаченный Pro ИЛИ активное окно trial.
 */

/** Данные погашения из promo_code_redemptions + promo_codes (для админки). */
export type PromoRedemptionRow = {
  code: string
  redeemed_at?: string | null
  activation_duration_days?: number | null
  expires_at?: string | null
}

export type EstablishmentSubFields = {
  subscription_type?: string | null
  pro_paid_until?: string | null
  pro_trial_ends_at?: string | null
}

export type SubscriptionAdminSummary = {
  /** Короткий статус для таблицы */
  statusLabel: string
  /** Способ / источник: IAP, промокод, пробный, — */
  paymentLabel: string
  /** Код промокода, если было погашение */
  promoCode: string | null
  /** ISO дата окончания оплаченного Pro (или null) */
  proUntilIso: string | null
  /** Доп. строка: дата trial или пояснение */
  detail: string | null
}

function parseDate(iso: string | null | undefined): Date | null {
  if (!iso) return null
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? null : d
}

/** Конец Pro по промо: фиксированный expires_at в строке промо или N дней с redeemed_at. */
export function promoProEndDate(promo: PromoRedemptionRow | null | undefined): Date | null {
  if (!promo?.code) return null
  const days = promo.activation_duration_days
  if (days != null && days > 0) {
    const start = parseDate(promo.redeemed_at ?? null)
    if (!start) return null
    return new Date(start.getTime() + days * 86400000)
  }
  return parseDate(promo.expires_at ?? null)
}

/**
 * Pro «активен» для строки заведения: trial, IAP с датой, или промо (в т.ч. activation_duration_days).
 * @param promo — данные погашения; без кода не учитывается окно промо (как раньше — только tier/IAP/trial).
 */
export function hasEffectivePro(
  est: EstablishmentSubFields,
  promo: PromoRedemptionRow | null | undefined,
  nowMs: number = Date.now(),
): boolean {
  const now = new Date(nowMs)
  const sub = (est.subscription_type ?? 'free').toLowerCase().trim()
  const paidUntil = parseDate(est.pro_paid_until ?? null)
  const trialUntil = parseDate(est.pro_trial_ends_at ?? null)
  const trialActive = trialUntil !== null && trialUntil > now
  if (trialActive) return true

  const isProTier = sub === 'pro' || sub === 'premium'
  if (!isProTier) return false

  if (paidUntil !== null && paidUntil > now) return true
  if (paidUntil !== null && paidUntil <= now) return false

  if (!promo?.code) return true

  const end = promoProEndDate(promo)
  if (promo.activation_duration_days != null && promo.activation_duration_days > 0) {
    return end !== null && end > now
  }
  const exp = parseDate(promo.expires_at ?? null)
  if (exp === null) return true
  return exp > now
}

/**
 * @param promo — первая строка погашения промокода для заведения (код), если есть
 */
export function summarizeSubscriptionForAdmin(
  est: EstablishmentSubFields,
  promo: PromoRedemptionRow | null | undefined,
  nowMs: number = Date.now(),
): SubscriptionAdminSummary {
  const now = new Date(nowMs)
  const sub = (est.subscription_type ?? 'free').toLowerCase().trim()
  const paidUntil = parseDate(est.pro_paid_until ?? null)
  const trialUntil = parseDate(est.pro_trial_ends_at ?? null)
  const promoEnd = promoProEndDate(promo)

  const trialActive = trialUntil !== null && trialUntil > now
  const isProTier = sub === 'pro' || sub === 'premium'
  const paidProActive =
    isProTier && (paidUntil === null || paidUntil > now)
  const paidProExpired = isProTier && paidUntil !== null && paidUntil <= now

  if (!hasEffectivePro(est, promo, nowMs)) {
    if (promo?.code && isProTier && !trialActive) {
      const pDetail =
        promo.activation_duration_days != null &&
        promo.activation_duration_days > 0 &&
        promoEnd
          ? `истёк ${promoEnd.toLocaleDateString('ru-RU')} (${promo.activation_duration_days} дн. с активации)`
          : (() => {
              const exp = parseDate(promo.expires_at ?? null)
              return exp ? `истёк ${exp.toLocaleDateString('ru-RU')}` : null
            })()
      return {
        statusLabel: 'Pro истёк',
        paymentLabel: 'Промокод (истёк)',
        promoCode: promo.code,
        proUntilIso: est.pro_paid_until ?? null,
        detail: pDetail,
      }
    }
    if (paidProExpired && !trialActive) {
      return {
        statusLabel: 'Pro истёк',
        paymentLabel: 'App Store / другое',
        promoCode: promo?.code ?? null,
        proUntilIso: est.pro_paid_until ?? null,
        detail: paidUntil ? `до ${paidUntil.toLocaleDateString('ru-RU')}` : null,
      }
    }
    return {
      statusLabel: 'Без Pro',
      paymentLabel: '—',
      promoCode: null,
      proUntilIso: null,
      detail: null,
    }
  }

  // Пробный 72ч имеет приоритет в отображении, если оплаченного Pro ещё нет
  if (trialActive && !paidProActive) {
    return {
      statusLabel: 'Пробный Pro',
      paymentLabel: '—',
      promoCode: null,
      proUntilIso: null,
      detail: trialUntil
        ? `trial до ${trialUntil.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })}`
        : null,
    }
  }

  const proUntilIso = est.pro_paid_until ?? null
  const untilStr =
    paidUntil && paidUntil > now
      ? `до ${paidUntil.toLocaleDateString('ru-RU')}`
      : null

  if (promo?.code) {
    let detail: string | null = null
    if (promo.activation_duration_days != null && promo.activation_duration_days > 0 && promoEnd) {
      detail = `до ${promoEnd.toLocaleDateString('ru-RU')} (${promo.activation_duration_days} дн. с активации)`
    } else if (untilStr) {
      detail = untilStr
    } else {
      const legExp = parseDate(promo.expires_at ?? null)
      if (legExp) detail = `до ${legExp.toLocaleDateString('ru-RU')}`
      else detail = 'без срока (промо)'
    }
    return {
      statusLabel: 'Pro (промокод)',
      paymentLabel: 'Промокод',
      promoCode: promo.code,
      proUntilIso,
      detail,
    }
  }

  if (paidUntil !== null) {
    return {
      statusLabel: 'Pro оплачен',
      paymentLabel: 'App Store (In-App Purchase)',
      promoCode: null,
      proUntilIso,
      detail: untilStr,
    }
  }

  return {
    statusLabel: 'Pro',
    paymentLabel: 'Неизвестно / вручную',
    promoCode: null,
    proUntilIso: null,
    detail: 'без даты окончания в БД',
  }
}

export function countEffectiveProEstablishments(
  rows: EstablishmentSubFields[],
  nowMs: number = Date.now(),
): number {
  return rows.filter((e) => hasEffectivePro(e, null, nowMs)).length
}

/** Категория для фильтра колонки «Подписка» в админке (не email/имя). */
export function subscriptionGroupKey(
  est: EstablishmentSubFields,
  promo: PromoRedemptionRow | null | undefined,
  nowMs: number = Date.now(),
): 'no_pro' | 'trial' | 'promo' | 'paid_iap' | 'expired' | 'pro_other' {
  const s = summarizeSubscriptionForAdmin(est, promo, nowMs)
  const label = s.statusLabel
  if (label === 'Без Pro') return 'no_pro'
  if (label === 'Пробный Pro') return 'trial'
  if (label === 'Pro (промокод)') return 'promo'
  if (label === 'Pro оплачен') return 'paid_iap'
  if (label === 'Pro истёк') return 'expired'
  return 'pro_other'
}
