import { createClient, SupabaseClient } from '@supabase/supabase-js'

let _supabase: SupabaseClient | null = null

export function getSupabase(): SupabaseClient {
  if (!_supabase) {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.SUPABASE_URL ?? ''
    const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY ?? ''
    _supabase = createClient(url, key)
  }
  return _supabase
}

export const supabase = new Proxy({} as SupabaseClient, {
  get(_target, prop) {
    return (getSupabase() as unknown as Record<string | symbol, unknown>)[prop]
  },
})

export type PromoCode = {
  id: number
  code: string
  is_used: boolean
  /** Вручную отключён в админке: нельзя применить; у погасивших — блок доступа. */
  is_disabled?: boolean
  used_by_establishment_id: string | null
  used_at: string | null
  created_at: string
  note: string | null
  starts_at: string | null
  /** Классика: срок действия по календарю. Новый тип: при activation_duration_days — окно «ввести код до». */
  expires_at: string | null
  /** Если задано — второй тип промокода (дни Pro с применения). Если null — классическая логика как раньше. */
  activation_duration_days?: number | null
  /** Тариф заведения при погашении: в админке создаём только pro | ultra; в БД могут быть legacy-значения. */
  grants_subscription_type?: string | null
  /** Пакеты +5 сотрудников на заведение при погашении */
  grants_employee_slot_packs?: number | null
  /** Пакеты +1 филиал на владельца при погашении */
  grants_branch_slot_packs?: number | null
  /** Только аддоны, без смены тарифа заведения */
  grants_additive_only?: boolean | null
  max_employees: number | null
  establishments?: { name: string } | null
}
