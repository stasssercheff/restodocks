/**
 * Сводка подписки для админки: тариф (не только pro), способ (IAP / промокод), даты.
 */
import { isAllowedPromoGrantType, subscriptionTierLabelRu } from '@/lib/promo-tiers'

function isPaidSubscriptionTier(sub: string | null | undefined): boolean {
  const t = (sub ?? 'free').toLowerCase().trim()
  if (t === 'free' || t === '') return false
  return isAllowedPromoGrantType(t)
}

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

const ruDateTime: Intl.DateTimeFormatOptions = {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
}

/** Подсказка для админки: момент создания записи заведения и ориентир окончания 72 ч Pro без промокода. */
export function registrationAndTrialHint(establishmentCreatedAt: string | null | undefined): string | null {
  const reg = parseDate(establishmentCreatedAt ?? null)
  if (!reg) return null
  const trialEnd = new Date(reg.getTime() + 72 * 3600000)
  return `Запись заведения: ${reg.toLocaleString('ru-RU', ruDateTime)}. Регистрация без промокода: полный Pro 72 ч с этого момента (ориентир окончания trial: ${trialEnd.toLocaleString('ru-RU', ruDateTime)}).`
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

  if (!isPaidSubscriptionTier(sub)) return false

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
  establishmentCreatedAt?: string | null,
): SubscriptionAdminSummary {
  const now = new Date(nowMs)
  const sub = (est.subscription_type ?? 'free').toLowerCase().trim()
  const paidUntil = parseDate(est.pro_paid_until ?? null)
  const trialUntil = parseDate(est.pro_trial_ends_at ?? null)
  const promoEnd = promoProEndDate(promo)

  const trialActive = trialUntil !== null && trialUntil > now
  const tierName = subscriptionTierLabelRu(est.subscription_type)
  const paidTierActive =
    isPaidSubscriptionTier(sub) && (paidUntil === null || paidUntil > now)
  const paidTierExpired =
    isPaidSubscriptionTier(sub) && paidUntil !== null && paidUntil <= now

  if (!hasEffectivePro(est, promo, nowMs)) {
    if (promo?.code && isPaidSubscriptionTier(sub) && !trialActive) {
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
        statusLabel: `${tierName} (истёк, промо)`,
        paymentLabel: 'Промокод (истёк)',
        promoCode: promo.code,
        proUntilIso: est.pro_paid_until ?? null,
        detail: pDetail,
      }
    }
    if (paidTierExpired && !trialActive) {
      return {
        statusLabel: `${tierName} (истёк)`,
        paymentLabel: 'App Store / другое',
        promoCode: promo?.code ?? null,
        proUntilIso: est.pro_paid_until ?? null,
        detail: paidUntil ? `до ${paidUntil.toLocaleDateString('ru-RU')}` : null,
      }
    }
    return {
      statusLabel: 'Без подписки',
      paymentLabel: '—',
      promoCode: null,
      proUntilIso: null,
      detail: registrationAndTrialHint(establishmentCreatedAt),
    }
  }

  // Пробный 72ч имеет приоритет в отображении, если оплаченного тарифа ещё нет
  if (trialActive && !paidTierActive) {
    return {
      statusLabel: 'Пробный период',
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
      statusLabel: `${tierName} (промокод)`,
      paymentLabel: 'Промокод',
      promoCode: promo.code,
      proUntilIso,
      detail,
    }
  }

  if (paidUntil !== null) {
    return {
      statusLabel: `${tierName} (оплата)`,
      paymentLabel: 'App Store (In-App Purchase)',
      promoCode: null,
      proUntilIso,
      detail: untilStr,
    }
  }

  return {
    statusLabel: tierName,
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
  establishmentCreatedAt?: string | null,
): 'no_pro' | 'trial' | 'promo' | 'paid_iap' | 'expired' | 'pro_other' {
  const s = summarizeSubscriptionForAdmin(est, promo, nowMs, establishmentCreatedAt)
  const label = s.statusLabel
  if (label === 'Без подписки' || label === 'Без Pro') return 'no_pro'
  if (label.includes('Пробный')) return 'trial'
  if (label.includes('(промокод)') && !label.includes('истёк')) return 'promo'
  if (label.includes('(оплата)') || label.includes('App Store')) return 'paid_iap'
  if (label.includes('истёк')) return 'expired'
  return 'pro_other'
}
