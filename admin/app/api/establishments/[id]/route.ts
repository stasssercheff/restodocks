import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import { getAdminPassword, getSupabaseConfig } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export const dynamic = 'force-dynamic'

/** Каскадное удаление заведения и всех связанных данных (админ, service_role) */
async function deleteEstablishmentCascade(supabase: ReturnType<typeof createClient>, establishmentId: string) {
  // 1. Удаляем филиалы рекурсивно
  const { data: branches } = await supabase
    .from('establishments')
    .select('id')
    .eq('parent_establishment_id', establishmentId)
  const branchList = (branches ?? []) as { id: string }[]
  if (branchList.length) {
    for (const b of branchList) {
      await deleteEstablishmentCascade(supabase, b.id)
    }
  }

  // 2. Данные заведения
  const empIds = (await supabase.from('employees').select('id').eq('establishment_id', establishmentId)).data?.map(e => e.id) ?? []
  if (empIds.length) {
    await supabase.from('password_reset_tokens').delete().in('employee_id', empIds)
    await supabase.from('employee_direct_messages').delete().or(`sender_employee_id.in.(${empIds.join(',')}),recipient_employee_id.in.(${empIds.join(',')})`)
  }
  await supabase.from('co_owner_invitations').delete().eq('establishment_id', establishmentId)
  await supabase.from('inventory_documents').delete().eq('establishment_id', establishmentId)
  await supabase.from('order_documents').delete().eq('establishment_id', establishmentId)
  await supabase.from('inventory_drafts').delete().eq('establishment_id', establishmentId)
  await supabase.from('establishment_schedule_data').delete().eq('establishment_id', establishmentId)
  await supabase.from('establishment_order_list_data').delete().eq('establishment_id', establishmentId)
  await supabase.from('product_price_history').delete().eq('establishment_id', establishmentId)
  await supabase.from('establishment_products').delete().eq('establishment_id', establishmentId)
  const { data: techCards } = await supabase.from('tech_cards').select('id').eq('establishment_id', establishmentId)
  const tcIds = techCards?.map(t => t.id) ?? []
  if (tcIds.length) {
    await supabase.from('tt_ingredients').delete().in('tech_card_id', tcIds)
  }
  await supabase.from('tech_cards').delete().eq('establishment_id', establishmentId)
  const { data: checklists } = await supabase.from('checklists').select('id').eq('establishment_id', establishmentId)
  const clIds = checklists?.map(c => c.id) ?? []
  if (clIds.length) {
    await supabase.from('checklist_items').delete().in('checklist_id', clIds)
    await supabase.from('checklist_submissions').delete().in('checklist_id', clIds)
  }
  await supabase.from('checklists').delete().eq('establishment_id', establishmentId)
  try {
    await supabase.from('iiko_blank_storage').delete().eq('establishment_id', establishmentId)
  } catch { /* table may not exist */ }
  try {
    await supabase.from('iiko_products').delete().eq('establishment_id', establishmentId)
  } catch { /* table may not exist */ }
  await supabase.from('establishments').update({ owner_id: null }).eq('id', establishmentId)
  await supabase.from('employees').delete().eq('establishment_id', establishmentId)
  await supabase.from('establishments').delete().eq('id', establishmentId)
}

export async function DELETE(
  _req: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const config = await getSupabaseConfig()
  if (!config) return NextResponse.json({ error: 'Supabase not configured' }, { status: 500 })
  const supabase = createClient(config.url, config.serviceRoleKey)

  const { id } = await params
  if (!id) return NextResponse.json({ error: 'Establishment ID required' }, { status: 400 })

  try {
    await deleteEstablishmentCascade(supabase, id)
    return NextResponse.json({ ok: true })
  } catch (e) {
    console.error('Admin delete establishment error:', e)
    return NextResponse.json(
      { error: e instanceof Error ? e.message : 'Delete failed' },
      { status: 500 }
    )
  }
}
