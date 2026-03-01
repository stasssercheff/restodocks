import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import LoginClient from './login-client'

export default async function LoginPage() {
  const cookieStore = await cookies()
  const session = cookieStore.get('admin_session')?.value
  if (session) redirect('/')
  return <LoginClient />
}
