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
  /** Срок ввести код (не длина Pro, если задано activation_duration_days). */
  expires_at: string | null
  /** Дней Pro с момента активации; при изменении у использованного кода пересчитывается окончание. */
  activation_duration_days?: number | null
  max_employees: number | null
  establishments?: { name: string } | null
}
