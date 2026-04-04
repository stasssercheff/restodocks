/**
 * Сводка Pro для админки: статус, способ (IAP / промокод), дата окончания.
 * Логика согласована с клиентом: effective Pro = оплаченный Pro ИЛИ активное окно trial.
 */

export type PromoRedemptionRow = { code: string }

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

  const trialActive = trialUntil !== null && trialUntil > now
  const isProTier = sub === 'pro' || sub === 'premium'
  const paidProActive =
    isProTier && (paidUntil === null || paidUntil > now)
  const paidProExpired = isProTier && paidUntil !== null && paidUntil <= now

  const effectivePro = paidProActive || trialActive

  if (!effectivePro) {
    if (paidProExpired && !trialActive) {
      return {
        statusLabel: 'Pro истёк',
        paymentLabel: promo ? 'Промокод (истёк)' : 'App Store / другое',
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
    return {
      statusLabel: 'Pro (промокод)',
      paymentLabel: 'Промокод',
      promoCode: promo.code,
      proUntilIso,
      detail: paidUntil === null ? 'без срока (промо)' : untilStr,
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

/** Pro активен: trial или оплаченный/бессрочный Pro по tier и датам. */
export function hasEffectivePro(
  est: EstablishmentSubFields,
  nowMs: number = Date.now(),
): boolean {
  const now = new Date(nowMs)
  const sub = (est.subscription_type ?? 'free').toLowerCase().trim()
  const paidUntil = parseDate(est.pro_paid_until ?? null)
  const trialUntil = parseDate(est.pro_trial_ends_at ?? null)
  const trialActive = trialUntil !== null && trialUntil > now
  const isProTier = sub === 'pro' || sub === 'premium'
  const paidProActive =
    isProTier && (paidUntil === null || paidUntil > now)
  return paidProActive || trialActive
}

export function countEffectiveProEstablishments(
  rows: EstablishmentSubFields[],
  nowMs: number = Date.now(),
): number {
  return rows.filter((e) => hasEffectivePro(e, nowMs)).length
}
