/** Допустимые тарифы для промокода (совпадает с subscription_type_is_paid_tier в SQL). */
export const PROMO_GRANT_SUBSCRIPTION_TYPES = [
  'pro',
  'premium',
  'ultra',
  'plus',
  'starter',
  'business',
] as const

export type PromoGrantSubscriptionType = (typeof PROMO_GRANT_SUBSCRIPTION_TYPES)[number]

export function isAllowedPromoGrantType(raw: string | null | undefined): raw is PromoGrantSubscriptionType {
  const t = (raw ?? 'pro').toLowerCase().trim()
  return (PROMO_GRANT_SUBSCRIPTION_TYPES as readonly string[]).includes(t)
}

export function subscriptionTierLabelRu(tier: string | null | undefined): string {
  const t = (tier ?? 'free').toLowerCase().trim()
  const map: Record<string, string> = {
    free: 'Free',
    pro: 'Pro',
    premium: 'Premium',
    ultra: 'Ultra',
    plus: 'Plus',
    starter: 'Starter',
    business: 'Business',
  }
  return map[t] ?? tier?.trim() ?? '—'
}
