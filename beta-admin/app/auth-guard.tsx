import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { verifySessionToken } from './api/auth/route'

export async function requireAuth() {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  const adminPassword = process.env.ADMIN_PASSWORD
  if (!session || !adminPassword || !(await verifySessionToken(session, adminPassword))) {
    redirect('/login')
  }
}
