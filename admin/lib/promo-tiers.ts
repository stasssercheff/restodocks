/**
 * Тариф по промокоду хранится в promo_codes.grants_subscription_type → establishments.subscription_type.
 *
 * В админке при создании кода выбираем только реальные продукты Restodocks: Pro и Ultra.
 * «Доп. заведение» и «+сотрудники» — это grants_branch_slot_packs / grants_employee_slot_packs, не отдельные значения subscription_type.
 *
 * Полный список ниже совпадает с public.subscription_type_is_paid_tier в SQL — для чтения старых строк и PATCH.
 */
export const PROMO_GRANT_SUBSCRIPTION_TYPES = ['pro', 'ultra'] as const
export type PromoGrantSubscriptionType = (typeof PROMO_GRANT_SUBSCRIPTION_TYPES)[number]

export const SUBSCRIPTION_PAID_TIERS_DB = [
  'pro',
  'premium',
  'ultra',
  'plus',
  'starter',
  'business',
] as const

/** Совпадает с subscription_type_is_paid_tier — любое значение, которое БД считает платным тарифом. */
export function isPaidTierStoredInDb(raw: string | null | undefined): boolean {
  const t = (raw ?? 'free').toLowerCase().trim()
  return (SUBSCRIPTION_PAID_TIERS_DB as readonly string[]).includes(t)
}

/** Создание промокода через админку: только pro | ultra. */
export function isSelectablePromoGrantTier(raw: string | null | undefined): raw is PromoGrantSubscriptionType {
  const t = (raw ?? 'ultra').toLowerCase().trim()
  return t === 'pro' || t === 'ultra'
}

/** Имя сохранено для существующих импортов; то же, что isPaidTierStoredInDb. */
export function isAllowedPromoGrantType(raw: string | null | undefined): boolean {
  return isPaidTierStoredInDb(raw)
}

export function subscriptionTierLabelRu(tier: string | null | undefined): string {
  const t = (tier ?? 'free').toLowerCase().trim()
  const map: Record<string, string> = {
    free: 'Free',
    lite: 'Lite',
    pro: 'Pro',
    premium: 'Premium',
    ultra: 'Ultra',
    plus: 'Plus',
    starter: 'Starter',
    business: 'Business',
  }
  return map[t] ?? tier?.trim() ?? '—'
}
