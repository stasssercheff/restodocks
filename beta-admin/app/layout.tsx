import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Restodocks Admin',
  description: 'Platform administration',
  robots: 'noindex, nofollow',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ru">
      <body className="antialiased">{children}</body>
    </html>
  )
}
