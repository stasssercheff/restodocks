import { NextResponse } from 'next/server'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

async function requireAdmin(): Promise<
  | { ok: true; supabase: SupabaseClient }
  | { ok: false; response: NextResponse }
> {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    return { ok: false, response: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) }
  }
  const config = await getSupabaseConfig()
  if (!config) {
    return { ok: false, response: NextResponse.json({ error: 'Supabase not configured' }, { status: 500 }) }
  }
  const supabase = createClient(config.url, config.serviceRoleKey)
  return { ok: true, supabase }
}

export async function DELETE(
  _req: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const auth = await requireAdmin()
  if (!auth.ok) return auth.response
  const supabase = auth.supabase

  const { id } = await params
  if (!id) return NextResponse.json({ error: 'Establishment ID required' }, { status: 400 })

  try {
    const { data: rpcData, error } = await supabase.rpc('admin_delete_establishment', {
      p_establishment_id: id,
    })
    if (error) {
      const err = error as {
        message?: string
        details?: string
        hint?: string
        code?: string
      }
      const msg = [err.message, err.details, err.hint].filter(Boolean).join(' — ') || String(error)
      console.error('Admin delete establishment error:', error)
      const missingRpcHint =
        /function public\.admin_delete_establishment|does not exist|42883/i.test(msg)
          ? ' Выполните миграции Supabase: 20260623190000_establishment_delete_purge_auth_users.sql и зависимости _delete_establishment_cascade.'
          : ''
      const appleIapColumnHint =
        /apple_iap_subscription_claims|column "establishment_id" does not exist|42703/i.test(msg)
          ? ' Для новой схемы Apple IAP примените миграцию 20260623153000_fix_delete_establishment_cascade_apple_iap_column.sql (supabase/migrations и restodocks_flutter/supabase/migrations).'
          : ''
      const hint = `${missingRpcHint}${appleIapColumnHint}`
      return NextResponse.json({ error: msg + hint, code: err.code }, { status: 500 })
    }

    type RpcPayload = { ok?: boolean; purge_auth_user_ids?: unknown }
    const payload = (rpcData ?? null) as RpcPayload | null
    const purgeAuthUserIds: string[] = Array.isArray(payload?.purge_auth_user_ids)
      ? (payload!.purge_auth_user_ids as unknown[]).filter(
          (x): x is string => typeof x === 'string' && x.length > 0
        )
      : []

    for (const uid of purgeAuthUserIds) {
      const { error: delErr } = await supabase.auth.admin.deleteUser(uid)
      if (delErr) {
        console.error('Admin delete establishment: auth.admin.deleteUser failed', uid, delErr)
        return NextResponse.json(
          {
            error: `Заведение удалено из БД, но не удалось удалить пользователя Auth (${uid}): ${delErr.message}`,
            uid,
          },
          { status: 500 }
        )
      }
    }

    return NextResponse.json({
      ok: true,
      result: rpcData ?? null,
      auth_users_purged: purgeAuthUserIds.length,
    })
  } catch (e) {
    console.error('Admin delete establishment error:', e)
    const msg =
      e instanceof Error
        ? e.message
        : typeof e === 'object' &&
            e !== null &&
            'message' in e &&
            typeof (e as { message: unknown }).message === 'string'
          ? (e as { message: string }).message
          : 'Delete failed'
    return NextResponse.json({ error: msg }, { status: 500 })
  }
}
