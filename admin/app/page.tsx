import { requireAuth } from './auth-guard'
import AdminClient from './admin-client'

export default async function Page() {
  await requireAuth()
  return <AdminClient />
}
