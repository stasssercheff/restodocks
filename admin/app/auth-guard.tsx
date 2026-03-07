import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { getAdminPassword } from '@/lib/admin-env'
import { verifySessionToken } from '@/lib/session'

export async function requireAuth() {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = await getAdminPassword()
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    redirect('/login')
  }
}
