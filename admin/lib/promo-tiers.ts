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

/** Безопасная нормализация тарифа из БД (иногда приходит не string — иначе падает .toLowerCase). */
export function safeTierString(raw: unknown): string {
  if (raw == null || raw === '') return 'free'
  if (typeof raw === 'string') return raw.toLowerCase().trim()
  return String(raw).toLowerCase().trim()
}

/** Совпадает с subscription_type_is_paid_tier — любое значение, которое БД считает платным тарифом. */
export function isPaidTierStoredInDb(raw: unknown): boolean {
  const t = safeTierString(raw)
  return (SUBSCRIPTION_PAID_TIERS_DB as readonly string[]).includes(t)
}

/** Создание промокода через админку: только pro | ultra. */
export function isSelectablePromoGrantTier(raw: string | null | undefined): raw is PromoGrantSubscriptionType {
  const t = safeTierString(raw)
  return t === 'pro' || t === 'ultra'
}

/** Имя сохранено для существующих импортов; то же, что isPaidTierStoredInDb. */
export function isAllowedPromoGrantType(raw: string | null | undefined): boolean {
  return isPaidTierStoredInDb(raw)
}

export function subscriptionTierLabelRu(tier: unknown): string {
  const t = safeTierString(tier)
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
  return map[t] ?? (typeof tier === 'string' ? tier.trim() : String(tier ?? '—'))
}
