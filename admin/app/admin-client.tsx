'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import type { PromoCode } from '@/lib/supabase'
import type { Insight, SecuritySnapshotPayload } from '@/lib/security-snapshot'
import type { SystemHealthPayload } from '@/lib/system-health'
import {
  PROMO_GRANT_SUBSCRIPTION_TYPES,
  subscriptionTierLabelRu,
  type PromoGrantSubscriptionType,
} from '@/lib/promo-tiers'

type SubscriptionSummary = {
  statusLabel: string
  paymentLabel: string
  promoCode: string | null
  proUntilIso: string | null
  detail: string | null
}

type SubscriptionGroup =
  | 'no_pro'
  | 'trial'
  | 'promo'
  | 'paid_iap'
  | 'expired'
  | 'pro_other'

type Establishment = {
  id: string
  name: string
  address: string | null
  created_at: string
  default_currency: string
  employee_count: number
  owner_name: string
  owner_email: string
  registration_ip?: string | null
  registration_country?: string | null
  registration_city?: string | null
  /** Админ: лимит доп. заведений для владельца; null = общая настройка «Настройки» */
  max_additional_establishments_override?: number | null
  establishment_type?: 'main' | 'branch' | 'separate'
  subscription_summary?: SubscriptionSummary
  effective_pro?: boolean
  /** Сводная категория подписки для фильтра колонки */
  subscription_group?: SubscriptionGroup
}

function formatDate(iso: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

/** Дата и время создания записи заведения в БД (для админки). */
function formatDateTime(iso: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function isExpired(iso: string | null) {
  if (!iso) return false
  return new Date(iso) < new Date()
}


function isValidNow(startsAt: string | null, expiresAt: string | null) {
  if (startsAt && new Date(startsAt) > new Date()) return false
  if (expiresAt && new Date(expiresAt) < new Date()) return false
  return true
}

/** Статус строки: отключение вручную важнее остального. */
function promoRowStatus(row: PromoCode): 'disabled' | 'used' | 'expired' | 'free' {
  if (row.is_disabled) return 'disabled'
  if (row.is_used) return 'used'
  if (!isValidNow(row.starts_at, row.expires_at)) return 'expired'
  return 'free'
}

// ─── Main ─────────────────────────────────────────────────────────────────────

export default function AdminClient() {
  const router = useRouter()
  const [tab, setTab] = useState<'establishments' | 'promo' | 'security' | 'health' | 'settings'>('establishments')

  async function logout() {
    await fetch('/api/auth', { method: 'DELETE' })
    router.push('/login')
  }

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <header className="border-b border-amber-900/40 bg-gray-950 px-4 py-3 flex items-center justify-between sticky top-0 z-10">
        <div className="flex items-center gap-2">
          <span className="font-bold text-base">Restodocks</span>
          <span className="text-gray-500 text-sm hidden sm:inline">/ Admin</span>
        </div>
        <button onClick={logout} className="text-sm text-gray-500 hover:text-white transition">
          Выйти
        </button>
      </header>

      <div className="border-b border-gray-800 px-4">
        <div className="flex gap-1">
          {([
            { key: 'establishments', label: 'Заведения' },
            { key: 'promo', label: 'Промокоды' },
            { key: 'security', label: 'Безопасность' },
            { key: 'health', label: 'Нагрузка' },
            { key: 'settings', label: 'Настройки' },
          ] as const).map(t => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`px-4 py-3 text-sm font-medium border-b-2 transition ${
                tab === t.key
                  ? 'border-indigo-500 text-white'
                  : 'border-transparent text-gray-500 hover:text-gray-300'
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      <main className="max-w-6xl mx-auto px-3 py-4 sm:px-6 sm:py-8">
        {tab === 'establishments' && <EstablishmentsTab />}
        {tab === 'promo' && <PromoTab />}
        {tab === 'security' && <SecurityTab />}
        {tab === 'health' && <SystemHealthTab />}
        {tab === 'settings' && <PlatformSettingsTab />}
      </main>
    </div>
  )
}

// ─── Establishments Tab ───────────────────────────────────────────────────────

const CONFIRM_DELETE_TEXT = 'УДАЛИТЬ'

function EstablishmentsTab() {
  function establishmentTypeLabel(row: Establishment) {
    switch (row.establishment_type) {
      case 'branch':
        return 'Филиал'
      case 'separate':
        return 'Отдельное заведение'
      default:
        return 'Основное'
    }
  }

  /** Плашка «Тип» на тёмном фоне админки: филиал / отдельное / основное */
  function establishmentTypeBadgeClass(row: Establishment): string {
    const base = 'inline-flex items-center px-2 py-0.5 rounded text-xs font-medium border'
    switch (row.establishment_type) {
      case 'branch':
        return `${base} bg-amber-950/70 text-amber-100 border-amber-600/45`
      case 'separate':
        return `${base} bg-violet-950/70 text-violet-100 border-violet-600/45`
      default:
        return `${base} bg-emerald-950/70 text-emerald-100 border-emerald-600/45`
    }
  }

  function subscriptionStatusTextClass(status: string): string {
    if (status === 'Без подписки' || status === 'Без Pro') return 'text-gray-500'
    if (status.startsWith('Пробный')) return 'text-sky-300'
    if (status.includes('истёк')) return 'text-red-300/90'
    if (status.includes('промокод') && !status.includes('истёк')) return 'text-amber-200'
    if (status.includes('(оплата)') || status.includes('оплачен')) return 'text-emerald-300'
    if (!status.includes('Без')) return 'text-emerald-200'
    return 'text-gray-200'
  }

  function SubscriptionBlock({ row }: { row: Establishment }) {
    const s = row.subscription_summary
    if (!s) {
      return <span className="text-gray-600 text-xs">—</span>
    }
    const payTitle =
      s.paymentLabel === 'App Store (In-App Purchase)'
        ? 'Подписка через App Store (In-App Purchase). Дата окончания в БД обычно уже учитывает отсрочку оплаты (grace period), если она пришла в чеке из App Store Connect.'
        : undefined
    return (
      <div className="space-y-0.5 max-w-[15rem]">
        <div className={`text-xs font-medium ${subscriptionStatusTextClass(s.statusLabel)}`}>
          {s.statusLabel}
        </div>
        <div className="text-[11px] text-gray-500" title={payTitle}>
          {s.paymentLabel}
          {s.promoCode ? (
            <span className="block font-mono text-amber-200/90 mt-0.5">{s.promoCode}</span>
          ) : null}
        </div>
        {s.detail ? (
          <div className="text-[10px] text-gray-600 leading-snug">{s.detail}</div>
        ) : null}
      </div>
    )
  }

  const [data, setData] = useState<Establishment[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [filterType, setFilterType] = useState<'all' | 'main' | 'branch' | 'separate'>('all')
  const [filterSubscription, setFilterSubscription] = useState<'all' | SubscriptionGroup>('all')
  const [filterEmployees, setFilterEmployees] = useState<'all' | '0' | '1' | '2-5' | '6+'>('all')
  const [error, setError] = useState<string | null>(null)
  const [deleting, setDeleting] = useState<string | null>(null)
  const [refreshingGeo, setRefreshingGeo] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    const res = await fetch('/api/establishments')
    const json = await res.json()
    if (!res.ok) {
      setError(typeof json?.error === 'string' ? json.error : 'Ошибка загрузки')
      setData([])
    } else {
      setData(Array.isArray(json) ? json : [])
    }
    setLoading(false)
  }, [])

  useEffect(() => { load() }, [load])

  function matchesEmployeeFilter(n: number): boolean {
    if (filterEmployees === 'all') return true
    if (filterEmployees === '0') return n === 0
    if (filterEmployees === '1') return n === 1
    if (filterEmployees === '2-5') return n >= 2 && n <= 5
    return n >= 6
  }

  const filtered = data.filter(e => {
    const q = search.toLowerCase()
    const sub = e.subscription_summary
    const subText = sub
      ? [sub.statusLabel, sub.paymentLabel, sub.promoCode, sub.detail].filter(Boolean).join(' ').toLowerCase()
      : ''
    const textMatch =
      e.name.toLowerCase().includes(q) ||
      e.owner_email.toLowerCase().includes(q) ||
      e.owner_name.toLowerCase().includes(q) ||
      (e.registration_ip ?? '').toLowerCase().includes(q) ||
      (e.registration_country ?? '').toLowerCase().includes(q) ||
      (e.registration_city ?? '').toLowerCase().includes(q) ||
      (e.created_at ?? '').toLowerCase().includes(q) ||
      formatDateTime(e.created_at).toLowerCase().includes(q) ||
      subText.includes(q)
    if (!textMatch) return false
    if (filterType !== 'all' && e.establishment_type !== filterType) return false
    if (filterSubscription !== 'all' && (e.subscription_group ?? 'no_pro') !== filterSubscription) return false
    if (!matchesEmployeeFilter(e.employee_count)) return false
    return true
  })

  function regInfo(row: Establishment) {
    if (!row.registration_ip) return '—'
    const parts = [row.registration_ip]
    if (row.registration_city) parts.push(row.registration_city)
    if (row.registration_country && row.registration_country !== row.registration_city) parts.push(row.registration_country)
    return parts.join(', ')
  }

  const total = data.length
  const totalEmployees = data.reduce((s, e) => s + e.employee_count, 0)
  const totalProActive = data.filter(e => e.effective_pro).length

  async function handleRefreshGeo() {
    setRefreshingGeo(true)
    setError(null)
    try {
      const res = await fetch('/api/establishments/refresh-geo', { method: 'POST' })
      const json = await res.json()
      if (!res.ok) throw new Error(json?.error || 'Ошибка')
      await load()
      alert(`Обновлено: ${json.updated ?? 0} из ${json.total ?? 0}${json.errors?.length ? `\nОшибки: ${json.errors.length}` : ''}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка обновления гео')
    } finally {
      setRefreshingGeo(false)
    }
  }

  async function setMaxAdditionalOverride(row: Establishment) {
    const current = row.max_additional_establishments_override
    const val = prompt(
      'Макс. дополнительных заведений для аккаунта этого владельца (как общая настройка). Пусто — брать лимит из вкладки «Настройки»:',
      current != null ? String(current) : '',
    )
    if (val === null) return
    const trimmed = val.trim()
    const parsed = trimmed === '' ? null : parseInt(trimmed, 10)
    if (trimmed !== '' && (Number.isNaN(parsed!) || parsed! < 0 || parsed! > 999)) {
      alert('Введи целое от 0 до 999 или оставь пустым')
      return
    }
    const res = await fetch(`/api/establishments/${row.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ max_additional_establishments_override: parsed }),
    })
    const json = await res.json()
    if (!res.ok) {
      setError(typeof json?.error === 'string' ? json.error : 'Ошибка сохранения')
      return
    }
    await load()
  }

  async function handleDelete(row: Establishment) {
    if (!confirm(`Удалить заведение «${row.name}»?\n\nБудут удалены все данные: номенклатура, ТТК, чеклисты, сотрудники и т.д. Действие необратимо.`)) return
    const typed = prompt(`Для подтверждения введите "${CONFIRM_DELETE_TEXT}":`)
    if (typed?.trim() !== CONFIRM_DELETE_TEXT) {
      if (typed !== null) alert('Отменено: текст не совпадает.')
      return
    }
    setDeleting(row.id)
    try {
      const res = await fetch(`/api/establishments/${row.id}`, { method: 'DELETE' })
      const json = (await res.json().catch(() => ({}))) as { error?: string; code?: string }
      if (!res.ok) {
        const parts = [json?.error, json?.code ? `(${json.code})` : ''].filter(Boolean)
        throw new Error(parts.join(' ') || 'Ошибка удаления')
      }
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка удаления')
      await load()
    } finally {
      setDeleting(null)
    }
  }

  return (
    <>
      {error && (
        <div className="mb-4 p-4 bg-red-900/30 border border-red-700 rounded-lg text-red-200 text-sm">
          {error}
          <span className="block mt-2 text-gray-500 text-xs">
            Нет колонки или схема старая — открой Supabase → SQL Editor и выполни миграции:{' '}
            <code className="text-gray-400">supabase/migrations/20260502120000_pro_paid_until_and_status_rpc.sql</code>
            {' '}(колонка <code className="text-gray-500">pro_paid_until</code>), при необходимости{' '}
            <code className="text-gray-400">supabase/migrations/20260430230000_establishments_max_additional_override.sql</code>
            . Ошибка входа/401 — проверь Secrets в Cloudflare (<code className="text-gray-500">SUPABASE_URL</code>,{' '}
            <code className="text-gray-500">SERVICE_ROLE_KEY</code>) и перелогинься в админке.
          </span>
        </div>
      )}
      <div className="grid grid-cols-3 gap-2 mb-4 sm:gap-3 sm:mb-8">
        <StatCard label="Заведений" value={total} />
        <StatCard label="Сотрудников" value={totalEmployees} />
        <StatCard label="С платным тарифом" value={totalProActive} />
      </div>

      <div className="mb-4 p-4 bg-gray-900/80 border border-gray-800 rounded-xl text-gray-400 text-sm leading-relaxed">
        <p className="font-medium text-gray-300 mb-1">Регистрация и пробный Pro</p>
        <p>
          Колонка «Регистрация» — дата и время создания <span className="text-gray-500">записи заведения</span> в базе (
          <code className="text-gray-500 text-xs">establishments.created_at</code>). Для входа{' '}
          <span className="text-gray-300">без промокода</span> в продукте действует{' '}
          <span className="text-gray-300">72 часа полного Pro</span> с этого момента (в БД — поле{' '}
          <code className="text-gray-500 text-xs">pro_trial_ends_at</code>
          ). С промокодом триал обычно не заполняется — тариф даёт промо.
        </p>
        <p className="mt-2 text-xs text-gray-600">
          Если у старых аккаунтов без промо пропала дата окончания триала, выполни в Supabase миграцию{' '}
          <code className="text-gray-500">20260621120000_backfill_pro_trial_ends_at_no_promo_main.sql</code>.
        </p>
      </div>

      <div className="flex flex-wrap gap-2 mb-3 md:hidden">
        <select
          value={filterType}
          onChange={e => setFilterType(e.target.value as typeof filterType)}
          className="bg-gray-900 border border-gray-800 rounded-lg px-2 py-2 text-white text-xs flex-1 min-w-[6rem]"
        >
          <option value="all">Тип: все</option>
          <option value="main">Основное</option>
          <option value="branch">Филиал</option>
          <option value="separate">Отдельное</option>
        </select>
        <select
          value={filterSubscription}
          onChange={e => setFilterSubscription(e.target.value as typeof filterSubscription)}
          className="bg-gray-900 border border-gray-800 rounded-lg px-2 py-2 text-white text-xs flex-1 min-w-[8rem]"
        >
          <option value="all">Подписка: все</option>
          <option value="no_pro">Без подписки</option>
          <option value="trial">Пробный</option>
          <option value="promo">Pro (промокод)</option>
          <option value="paid_iap">Pro (оплата)</option>
          <option value="expired">Истёк</option>
          <option value="pro_other">Прочее</option>
        </select>
        <select
          value={filterEmployees}
          onChange={e => setFilterEmployees(e.target.value as typeof filterEmployees)}
          className="bg-gray-900 border border-gray-800 rounded-lg px-2 py-2 text-white text-xs flex-1 min-w-[6rem]"
        >
          <option value="all">Сотр.: все</option>
          <option value="0">0</option>
          <option value="1">1</option>
          <option value="2-5">2–5</option>
          <option value="6+">6+</option>
        </select>
      </div>

      <div className="flex gap-2 mb-4 flex-wrap">
        <input
          type="text"
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Поиск..."
          className="bg-gray-900 border border-gray-800 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 flex-1 min-w-0 text-sm"
        />
        <button
          onClick={handleRefreshGeo}
          disabled={refreshingGeo}
          className="text-gray-500 hover:text-white transition px-3 py-2 rounded-lg border border-gray-800 text-sm shrink-0 disabled:opacity-50"
          title="Обновить страну и город по IP для заведений с registration_ip"
        >
          {refreshingGeo ? '…' : '🌐 Обновить гео по IP'}
        </button>
        <button onClick={load} className="text-gray-500 hover:text-white transition px-3 py-2 rounded-lg border border-gray-800 text-sm shrink-0">
          ↻
        </button>
      </div>

      {loading ? (
        <div className="p-12 text-center text-gray-500">Загрузка...</div>
      ) : filtered.length === 0 ? (
        <div className="p-12 text-center text-gray-500">Заведений нет</div>
      ) : (
        <>
          {/* Desktop table */}
          <div className="hidden md:block bg-gray-900 rounded-xl border border-gray-800 overflow-x-auto">
            <table className="w-full text-sm min-w-[960px]">
              <thead>
                <tr className="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wide">
                  <th className="px-4 py-3 text-left">Заведение</th>
                  <th className="px-4 py-3 text-left align-top">
                    <div className="mb-1.5">Тип</div>
                    <select
                      value={filterType}
                      onChange={e => setFilterType(e.target.value as typeof filterType)}
                      title="Фильтр по типу заведения"
                      className="w-full max-w-[9rem] bg-gray-950 border border-gray-700 rounded-md px-1.5 py-1 text-[11px] text-gray-200 font-normal normal-case tracking-normal"
                    >
                      <option value="all">Все</option>
                      <option value="main">Основное</option>
                      <option value="branch">Филиал</option>
                      <option value="separate">Отдельное</option>
                    </select>
                  </th>
                  <th
                    className="px-4 py-3 text-left min-w-[11rem] align-top"
                    title="Статус Pro, способ оплаты (сейчас App Store IAP или промокод), код промо при погашении"
                  >
                    <div className="mb-1.5">Подписка</div>
                    <select
                      value={filterSubscription}
                      onChange={e => setFilterSubscription(e.target.value as typeof filterSubscription)}
                      title="Фильтр по подписке"
                      className="w-full max-w-[12rem] bg-gray-950 border border-gray-700 rounded-md px-1.5 py-1 text-[11px] text-gray-200 font-normal normal-case tracking-normal"
                    >
                      <option value="all">Все</option>
                      <option value="no_pro">Без подписки</option>
                      <option value="trial">Пробный</option>
                      <option value="promo">Pro (промокод)</option>
                      <option value="paid_iap">Pro (оплата)</option>
                      <option value="expired">Истёк</option>
                      <option value="pro_other">Прочее</option>
                    </select>
                  </th>
                  <th className="px-4 py-3 text-left">Владелец</th>
                  <th className="px-4 py-3 text-left">Email</th>
                  <th className="px-4 py-3 text-center align-top">
                    <div className="mb-1.5">Сотр.</div>
                    <select
                      value={filterEmployees}
                      onChange={e => setFilterEmployees(e.target.value as typeof filterEmployees)}
                      title="Фильтр по числу сотрудников"
                      className="w-full max-w-[6rem] mx-auto bg-gray-950 border border-gray-700 rounded-md px-1.5 py-1 text-[11px] text-gray-200 font-normal normal-case tracking-normal"
                    >
                      <option value="all">Все</option>
                      <option value="0">0</option>
                      <option value="1">1</option>
                      <option value="2-5">2–5</option>
                      <option value="6+">6+</option>
                    </select>
                  </th>
                  <th className="px-4 py-3 text-center" title="Переопределение лимита доп. заведений для владельца; при нескольких — минимум">
                    Лимит доп.
                  </th>
                  <th
                    className="px-4 py-3 text-left min-w-[9.5rem]"
                    title="Дата и время создания записи заведения в БД. Без промокода: 72 ч Pro с этого момента (см. pro_trial_ends_at)."
                  >
                    Регистрация
                  </th>
                  <th className="px-4 py-3 text-left">IP регистрации</th>
                  <th className="px-4 py-3 text-right w-20"></th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((row, i) => (
                  <tr key={row.id} className={`border-b border-gray-800/50 hover:bg-gray-800/30 transition ${i === filtered.length - 1 ? 'border-0' : ''}`}>
                    <td className="px-4 py-3 font-medium text-white">{row.name}</td>
                    <td className="px-4 py-3 text-xs">
                      <span className={establishmentTypeBadgeClass(row)}>
                        {establishmentTypeLabel(row)}
                      </span>
                    </td>
                    <td className="px-4 py-3 align-top text-gray-300">
                      <SubscriptionBlock row={row} />
                    </td>
                    <td className="px-4 py-3 text-gray-300">{row.owner_name}</td>
                    <td className="px-4 py-3 text-gray-400 text-xs">{row.owner_email}</td>
                    <td className="px-4 py-3 text-center">
                      <span className="bg-gray-800 px-2 py-0.5 rounded text-xs font-mono">{row.employee_count}</span>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <button
                        type="button"
                        onClick={() => setMaxAdditionalOverride(row)}
                        className="text-xs font-mono hover:text-indigo-400 transition"
                        title="Переопределить лимит доп. заведений для этого владельца"
                      >
                        {row.max_additional_establishments_override != null ? (
                          <span className="bg-indigo-900/40 text-indigo-300 px-2 py-0.5 rounded">
                            {row.max_additional_establishments_override}
                          </span>
                        ) : (
                          <span className="text-gray-600">платформа</span>
                        )}
                      </button>
                    </td>
                    <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap" title={row.created_at}>
                      {formatDateTime(row.created_at)}
                    </td>
                    <td className="px-4 py-3 text-gray-400 text-xs font-mono">{regInfo(row)}</td>
                    <td className="px-4 py-3 text-right">
                      <button
                        onClick={() => handleDelete(row)}
                        disabled={deleting === row.id}
                        className="text-red-400 hover:text-red-300 text-xs disabled:opacity-50"
                        title="Удалить заведение"
                      >
                        {deleting === row.id ? '...' : '🗑'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Mobile cards */}
          <div className="md:hidden space-y-2">
            {filtered.map(row => (
              <div key={row.id} className="bg-gray-900 rounded-xl border border-gray-800 p-4">
                <div className="flex items-start justify-between gap-2 mb-2">
                  <span className="font-medium text-white text-sm">{row.name}</span>
                  <span className="flex items-center gap-2 shrink-0">
                    <span className="bg-gray-800 px-2 py-0.5 rounded text-xs font-mono text-gray-400">
                      {row.employee_count} сотр.
                    </span>
                    <button
                      onClick={() => handleDelete(row)}
                      disabled={deleting === row.id}
                      className="text-red-400 hover:text-red-300 text-sm disabled:opacity-50"
                      title="Удалить заведение"
                    >
                      {deleting === row.id ? '...' : '🗑'}
                    </button>
                  </span>
                </div>
                <div className="text-gray-400 text-xs">{row.owner_name}</div>
                <div className="mt-1">
                  <span className={establishmentTypeBadgeClass(row)}>{establishmentTypeLabel(row)}</span>
                </div>
                <div className="mt-2">
                  <SubscriptionBlock row={row} />
                </div>
                <div className="text-gray-500 text-xs">{row.owner_email}</div>
                <div className="text-gray-600 text-xs mt-1" title={row.created_at}>
                  Регистрация: {formatDateTime(row.created_at)}
                </div>
                {row.registration_ip && (
                  <div className="text-gray-500 text-xs mt-1 font-mono">{regInfo(row)}</div>
                )}
                <div className="flex items-center gap-2 mt-2">
                  <span className="text-gray-600 text-xs">Лимит доп.:</span>
                  <button
                    type="button"
                    onClick={() => setMaxAdditionalOverride(row)}
                    className="text-xs font-mono hover:text-indigo-400"
                  >
                    {row.max_additional_establishments_override != null ? (
                      <span className="bg-indigo-900/40 text-indigo-300 px-2 py-0.5 rounded">
                        {row.max_additional_establishments_override}
                      </span>
                    ) : (
                      <span className="text-gray-600">платформа</span>
                    )}
                  </button>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </>
  )
}

// ─── Promo Tab ────────────────────────────────────────────────────────────────

function PromoTab() {
  const [codes, setCodes] = useState<PromoCode[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [newCode, setNewCode] = useState('')
  const [newNote, setNewNote] = useState('')
  const [newStartDate, setNewStartDate] = useState('')
  const [newEndDate, setNewEndDate] = useState('')
  const [newActivationDays, setNewActivationDays] = useState('')
  /** «Классика» = как у уже существующих кодов (поле activation_duration_days пустое). «С активации» — второй, дополнительный тип. */
  const [newPromoLogic, setNewPromoLogic] = useState<'legacy' | 'activation'>('legacy')
  const [newGrantTier, setNewGrantTier] = useState<PromoGrantSubscriptionType>('ultra')
  const [newMaxEmployees, setNewMaxEmployees] = useState('')
  /** Пакеты +5 сотрудников на одно заведение при погашении */
  const [newEmpSlotPacks, setNewEmpSlotPacks] = useState('')
  /** Пакеты +1 филиал на владельца */
  const [newBranchSlotPacks, setNewBranchSlotPacks] = useState('')
  const [newAdditiveOnly, setNewAdditiveOnly] = useState(false)
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<'all' | 'free' | 'used' | 'expired' | 'disabled'>('all')

  const loadCodes = useCallback(async () => {
    setLoading(true)
    setError(null)
    const res = await fetch('/api/promo')
    const data = await res.json()
    if (!res.ok) {
      setError(typeof data?.error === 'string' ? data.error : 'Ошибка загрузки')
      setCodes([])
    } else {
      setCodes(Array.isArray(data) ? data : [])
    }
    setLoading(false)
  }, [])

  useEffect(() => { loadCodes() }, [loadCodes])

  async function addCode() {
    if (!newCode.trim()) return
    const empN = newEmpSlotPacks.trim() ? parseInt(newEmpSlotPacks.trim(), 10) : 0
    const brN = newBranchSlotPacks.trim() ? parseInt(newBranchSlotPacks.trim(), 10) : 0
    if (Number.isNaN(empN) || empN < 0 || empN > 500 || Number.isNaN(brN) || brN < 0 || brN > 500) {
      alert('Пакеты: целые числа от 0 до 500.')
      return
    }
    if (newPromoLogic === 'activation') {
      const d = newActivationDays.trim()
      const n = d ? parseInt(d, 10) : NaN
      if (!d || Number.isNaN(n) || n < 1) {
        alert('Для нового типа укажи целое число дней Pro с активации (или переключись на «как раньше»).')
        return
      }
    }
    setSaving(true)
    await fetch('/api/promo', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        code: newCode.trim().toUpperCase(),
        note: newNote.trim() || null,
        starts_at: newStartDate || null,
        expires_at: newEndDate || null,
        max_employees: newMaxEmployees ? parseInt(newMaxEmployees) : null,
        activation_duration_days:
          newPromoLogic === 'activation' && newActivationDays.trim()
            ? parseInt(newActivationDays.trim(), 10)
            : null,
        grants_subscription_type: newGrantTier,
        grants_employee_slot_packs: empN,
        grants_branch_slot_packs: brN,
        grants_additive_only: newAdditiveOnly,
      }),
    })
    setNewCode('')
    setNewNote('')
    setNewStartDate('')
    setNewEndDate('')
    setNewActivationDays('')
    setNewPromoLogic('legacy')
    setNewGrantTier('ultra')
    setNewMaxEmployees('')
    setNewEmpSlotPacks('')
    setNewBranchSlotPacks('')
    setNewAdditiveOnly(false)
    await loadCodes()
    setSaving(false)
  }

  async function deleteCode(id: number) {
    if (!confirm('Удалить промокод?')) return
    await fetch('/api/promo', {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id }),
    })
    await loadCodes()
  }

  async function toggleUsed(row: PromoCode) {
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id: row.id,
        is_used: !row.is_used,
        used_at: !row.is_used ? new Date().toISOString() : null,
        used_by_establishment_id: row.is_used ? null : row.used_by_establishment_id,
      }),
    })
    await loadCodes()
  }

  async function setEndDate(id: number, row: PromoCode) {
    const isActivation = (row.activation_duration_days ?? 0) > 0
    const val = prompt(
      isActivation
        ? 'Последний день, когда код ещё можно ввести (YYYY-MM-DD). Пусто — без ограничения по дате ввода.'
        : 'Действует до (YYYY-MM-DD), как у существующих промокодов без режима «дней с активации». Пусто — без даты.',
    )
    if (val === null) return
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, expires_at: val || null }),
    })
    await loadCodes()
  }

  async function setGrantTier(row: PromoCode) {
    const cur = (row.grants_subscription_type ?? 'ultra').toLowerCase()
    const val = prompt('Выдаваемый тариф (subscription_type): pro или ultra', cur)
    if (val === null) return
    const g = val.trim().toLowerCase()
    if (!(PROMO_GRANT_SUBSCRIPTION_TYPES as readonly string[]).includes(g)) {
      alert('Недопустимое значение')
      return
    }
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: row.id, grants_subscription_type: g }),
    })
    await loadCodes()
  }

  async function setActivationDays(id: number, current: number | null) {
    const val = prompt(
      'Дней Pro с момента активации (1–36500). Пусто — вернуть промокод к классической логике (как раньше в базе), только дата «действует до»:',
      current != null ? String(current) : '',
    )
    if (val === null) return
    const t = val.trim()
    const parsed = t === '' ? null : parseInt(t, 10)
    if (t !== '' && (Number.isNaN(parsed!) || parsed! < 1 || parsed! > 36500)) {
      alert('Введи целое от 1 до 36500 или оставь пустым')
      return
    }
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, activation_duration_days: parsed }),
    })
    await loadCodes()
  }

  async function setMaxEmployees(id: number, current: number | null) {
    const val = prompt('Макс. сотрудников (пусто — без ограничений):', current?.toString() ?? '')
    if (val === null) return
    const parsed = val.trim() ? parseInt(val.trim()) : null
    if (val.trim() && (isNaN(parsed!) || parsed! < 1)) { alert('Введи целое число больше 0'); return }
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, max_employees: parsed }),
    })
    await loadCodes()
  }

  async function setEmpSlotPacks(id: number, current: number | null | undefined) {
    const val = prompt(
      'Пакеты +5 сотрудников на одно заведение при погашении (0–500):',
      String(current ?? 0),
    )
    if (val === null) return
    const n = parseInt(val.trim(), 10)
    if (val.trim() === '' || Number.isNaN(n) || n < 0 || n > 500) {
      alert('Целое число от 0 до 500')
      return
    }
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, grants_employee_slot_packs: n }),
    })
    await loadCodes()
  }

  async function setBranchSlotPacks(id: number, current: number | null | undefined) {
    const val = prompt('Пакеты +1 филиал на владельца при погашении (0–500):', String(current ?? 0))
    if (val === null) return
    const n = parseInt(val.trim(), 10)
    if (val.trim() === '' || Number.isNaN(n) || n < 0 || n > 500) {
      alert('Целое число от 0 до 500')
      return
    }
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, grants_branch_slot_packs: n }),
    })
    await loadCodes()
  }

  async function toggleAdditiveOnly(row: PromoCode) {
    const next = !row.grants_additive_only
    const ok = next
      ? confirm(
          'Включить «только аддон»? Код не будет менять тариф заведения — только начислит пакеты (после основного промо).',
        )
      : confirm('Выключить «только аддон»?')
    if (!ok) return
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: row.id, grants_additive_only: next }),
    })
    await loadCodes()
  }

  async function toggleDisabled(row: PromoCode) {
    const next = !row.is_disabled
    if (next && row.is_used) {
      const ok = confirm(
        'Отключить промокод? У заведений, которые уже его применили, доступ будет заблокирован (как при истечении срока).',
      )
      if (!ok) return
    }
    setSaving(true)
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: row.id, is_disabled: next }),
    })
    await loadCodes()
    setSaving(false)
  }

  const filtered = codes.filter(c => {
    const match = c.code.includes(search.toUpperCase()) || (c.note ?? '').toLowerCase().includes(search.toLowerCase())
    if (!match) return false
    const st = promoRowStatus(c)
    if (filter === 'free') return st === 'free'
    if (filter === 'used') return c.is_used
    if (filter === 'expired') return st === 'expired'
    if (filter === 'disabled') return c.is_disabled === true
    return true
  })

  const total = codes.length
  const usedCount = codes.filter(c => c.is_used).length
  const freeCount = codes.filter(c => promoRowStatus(c) === 'free').length
  const expiredCount = codes.filter(c => promoRowStatus(c) === 'expired').length
  const disabledCount = codes.filter(c => c.is_disabled === true).length

  return (
    <>
      {error && (
        <div className="mb-4 p-4 bg-red-900/30 border border-red-700 rounded-lg text-red-200 text-sm">
          {error}
        </div>
      )}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2 mb-4 sm:gap-3 sm:mb-6">
        <StatCard label="Всего" value={total} />
        <StatCard label="Свободно" value={freeCount} />
        <StatCard label="Использовано" value={usedCount} />
        <StatCard label="Истекло" value={expiredCount} />
        <StatCard label="Отключено" value={disabledCount} />
      </div>

      <p className="text-gray-500 text-sm mb-4 leading-relaxed">
        Регистрация <span className="text-gray-400">без промокода</span> в приложении даёт владельцу{' '}
        <span className="text-gray-400">72 часа полного Pro</span> (см. вкладку «Заведения»: колонка «Регистрация» и
        поле <code className="text-gray-600 text-xs">pro_trial_ends_at</code>). Промокоды ниже — отдельный способ выдать
        тариф и срок.
      </p>

      {/* Add form */}
      <div className="bg-gray-900 rounded-xl p-4 border border-gray-800 mb-4">
        <h2 className="text-xs font-medium text-gray-500 mb-3 uppercase tracking-wide">Новый промокод</h2>
        <p className="text-[11px] text-gray-600 mb-3 leading-snug">
          Уже созданные промокоды <span className="text-gray-500">не меняются</span>: у них по-прежнему пустое поле «дней с активации» и работает прежняя логика.
          Ниже можно завести <span className="text-gray-500">дополнительно второй тип</span> — с длительностью Pro в днях от момента применения кода (число дней потом можно править).
          Пакеты +5 сотрудников начисляются на <span className="text-gray-500">то заведение, где погасили код</span>; пакеты филиалов — на владельца.
        </p>
        <div className="flex flex-col gap-2 mb-3">
          <span className="text-[11px] text-gray-500 uppercase tracking-wide">Логика</span>
          <div className="flex flex-col sm:flex-row sm:flex-wrap gap-2 sm:gap-4">
            <label className="flex items-center gap-2 text-sm text-gray-300 cursor-pointer">
              <input
                type="radio"
                name="promoLogic"
                className="accent-indigo-500"
                checked={newPromoLogic === 'legacy'}
                onChange={() => {
                  setNewPromoLogic('legacy')
                  setNewActivationDays('')
                }}
              />
              Как раньше (классика)
            </label>
            <label className="flex items-center gap-2 text-sm text-gray-300 cursor-pointer">
              <input
                type="radio"
                name="promoLogic"
                className="accent-indigo-500"
                checked={newPromoLogic === 'activation'}
                onChange={() => setNewPromoLogic('activation')}
              />
              Новый тип: дни Pro с активации
            </label>
          </div>
          <p className="text-[11px] text-gray-600 mb-2">
            Тариф по промокоду — отдельно от «классика / с активации»: это значение попадёт в{' '}
            <span className="text-gray-500">subscription_type</span> заведения (в продукте — Pro или Ultra).
            Доп. филиалы и слоты сотрудников — поля «+филиал» и «+5 сотр.», не отдельные «типы» тарифа.
          </p>
          <div className="flex flex-col gap-1 mb-3 max-w-xs">
            <label className="text-xs text-gray-500">Выдаваемый тариф</label>
            <select
              value={newGrantTier}
              onChange={e => setNewGrantTier(e.target.value as PromoGrantSubscriptionType)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:border-indigo-500"
            >
              {PROMO_GRANT_SUBSCRIPTION_TYPES.map(t => (
                <option key={t} value={t}>
                  {subscriptionTierLabelRu(t)} ({t})
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap sm:gap-3 sm:items-end">
          <input
            type="text"
            value={newCode}
            onChange={e => setNewCode(e.target.value.toUpperCase())}
            placeholder="BETA001"
            className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white font-mono placeholder-gray-600 focus:outline-none focus:border-indigo-500 text-sm"
          />
          <input
            type="text"
            value={newNote}
            onChange={e => setNewNote(e.target.value)}
            placeholder="Заметка"
            className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 text-sm"
          />
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500">{newPromoLogic === 'legacy' ? 'Действует с' : 'Ввод кода с'}</label>
            <input
              type="date"
              value={newStartDate}
              onChange={e => setNewStartDate(e.target.value)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500 text-sm"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500">{newPromoLogic === 'legacy' ? 'Действует до' : 'Ввод кода до'}</label>
            <input
              type="date"
              value={newEndDate}
              onChange={e => setNewEndDate(e.target.value)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500 text-sm"
            />
          </div>
          {newPromoLogic === 'activation' && (
            <div className="flex flex-col gap-1">
              <label className="text-xs text-gray-500" title="Только для нового типа: длина Pro от момента применения кода">
                Дней Pro с активации
              </label>
              <input
                type="number"
                min="1"
                max="36500"
                value={newActivationDays}
                onChange={e => setNewActivationDays(e.target.value)}
                placeholder="напр. 30"
                className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 text-sm w-full sm:w-28"
              />
            </div>
          )}
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500">Макс. сотр.</label>
            <input
              type="number"
              min="1"
              value={newMaxEmployees}
              onChange={e => setNewMaxEmployees(e.target.value)}
              placeholder="∞"
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 text-sm w-full sm:w-24"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500" title="Начисляется на заведение, где погасили код">
              +5 сотр. (пак.)
            </label>
            <input
              type="number"
              min={0}
              max={500}
              value={newEmpSlotPacks}
              onChange={e => setNewEmpSlotPacks(e.target.value)}
              placeholder="0"
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 text-sm w-full sm:w-20"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500" title="Слоты на доп. заведения для владельца">
              +филиал (пак.)
            </label>
            <input
              type="number"
              min={0}
              max={500}
              value={newBranchSlotPacks}
              onChange={e => setNewBranchSlotPacks(e.target.value)}
              placeholder="0"
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 text-sm w-full sm:w-20"
            />
          </div>
          <label className="flex items-center gap-2 text-xs text-gray-400 cursor-pointer sm:mb-6">
            <input
              type="checkbox"
              className="accent-indigo-500 rounded"
              checked={newAdditiveOnly}
              onChange={e => setNewAdditiveOnly(e.target.checked)}
            />
            Только аддон
          </label>
          <button
            onClick={addCode}
            disabled={saving || !newCode.trim()}
            className="col-span-2 sm:col-auto bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed px-5 py-2 rounded-lg font-medium transition text-sm"
          >
            {saving ? '...' : '+ Создать'}
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-2 mb-3 flex-wrap">
        <input
          type="text"
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Поиск..."
          className="bg-gray-900 border border-gray-800 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 flex-1 min-w-32 text-sm"
        />
        <div className="flex gap-1 flex-wrap">
          {(['all', 'free', 'used', 'expired', 'disabled'] as const).map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-2.5 py-1.5 rounded-lg text-xs transition ${filter === f ? 'bg-indigo-600 text-white' : 'bg-gray-900 border border-gray-800 text-gray-400 hover:text-white'}`}
            >
              {{ all: 'Все', free: 'Своб.', used: 'Исп.', expired: 'Истёк', disabled: 'Выкл.' }[f]}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="p-12 text-center text-gray-500">Загрузка...</div>
      ) : filtered.length === 0 ? (
        <div className="p-12 text-center text-gray-500">Промокодов нет</div>
      ) : (
        <>
          {/* Desktop table */}
          <div className="hidden md:block bg-gray-900 rounded-xl border border-gray-800 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wide">
                  <th className="px-4 py-3 text-left">Код</th>
                  <th className="px-4 py-3 text-left">Статус</th>
                  <th className="px-4 py-3 text-left">Заметка / Заведение</th>
                  <th
                    className="px-4 py-3 text-left"
                    title="Классика: дата «действует до». Новый тип: дни с активации и при необходимости срок ввода кода."
                  >
                    Логика / срок
                  </th>
                  <th className="px-4 py-3 text-center">Сотр.</th>
                  <th
                    className="px-4 py-3 text-center text-[10px] uppercase"
                    title="Пакеты при погашении: сотрудники на заведение / филиалы владельцу"
                  >
                    Пакеты
                  </th>
                  <th className="px-4 py-3 text-center text-[10px] uppercase" title="Только начисление пакетов без смены тарифа">
                    Аддон
                  </th>
                  <th className="px-4 py-3 text-left">Создан</th>
                  <th className="px-4 py-3 text-right">Действия</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((row, i) => {
                  const status = promoRowStatus(row)
                  const statusCfg = {
                    disabled: { label: 'Отключён', cls: 'bg-amber-900/40 text-amber-200' },
                    used: { label: 'Использован', cls: 'bg-blue-900/40 text-blue-300' },
                    expired: { label: 'Истёк', cls: 'bg-red-900/40 text-red-300' },
                    free: { label: 'Свободен', cls: 'bg-emerald-900/40 text-emerald-300' },
                  }[status]
                  const codeBtnClass = row.is_disabled
                    ? 'font-mono font-bold text-red-400 hover:text-red-300 transition'
                    : 'font-mono font-bold text-white hover:text-indigo-400 transition'
                  const isNewType = (row.activation_duration_days ?? 0) > 0
                  return (
                    <tr key={row.id} className={`border-b border-gray-800/50 hover:bg-gray-800/30 transition ${i === filtered.length - 1 ? 'border-0' : ''}`}>
                      <td className="px-4 py-3">
                        <div className="flex flex-col gap-0.5 items-start">
                          <button type="button" onClick={() => navigator.clipboard.writeText(row.code)} className={codeBtnClass}>
                            {row.code}
                          </button>
                          <span className="text-[10px] text-gray-600 font-normal tracking-normal">
                            {isNewType ? 'тип: с активации' : 'тип: классика'}
                          </span>
                          <button
                            type="button"
                            onClick={() => setGrantTier(row)}
                            className="text-[10px] text-left text-gray-500 hover:text-indigo-400"
                          >
                            тариф: {subscriptionTierLabelRu(row.grants_subscription_type ?? 'ultra')} — изм.
                          </button>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span className={`px-2 py-0.5 rounded text-xs font-medium ${statusCfg.cls}`}>{statusCfg.label}</span>
                      </td>
                      <td className="px-4 py-3 text-gray-400">
                        {row.is_used && row.establishments?.name ? <span className="text-white">{row.establishments.name}</span> : row.note || '—'}
                      </td>
                      <td className="px-4 py-3 text-gray-400 align-top">
                        {row.activation_duration_days != null && row.activation_duration_days > 0 ? (
                          <div className="space-y-1">
                            <button
                              type="button"
                              onClick={() => setActivationDays(row.id, row.activation_duration_days ?? null)}
                              className="block text-left text-emerald-300/95 hover:text-emerald-200 text-xs"
                            >
                              {row.activation_duration_days} дн. с активации
                            </button>
                            {row.expires_at ? (
                              <button
                                type="button"
                                onClick={() => setEndDate(row.id, row)}
                                className={`block text-[10px] text-gray-500 hover:text-gray-300 ${isExpired(row.expires_at) ? 'text-red-400' : ''}`}
                              >
                                ввести до {formatDate(row.expires_at)}
                              </button>
                            ) : (
                              <span className="text-[10px] text-gray-600">ввод кода без крайней даты</span>
                            )}
                          </div>
                        ) : (
                          <button
                            type="button"
                            onClick={() => setEndDate(row.id, row)}
                            className={`hover:text-white transition text-xs ${isExpired(row.expires_at) ? 'text-red-400' : ''}`}
                          >
                            {formatDate(row.expires_at)}
                          </button>
                        )}
                      </td>
                      <td className="px-4 py-3 text-center">
                        <button onClick={() => setMaxEmployees(row.id, row.max_employees)} className="text-xs font-mono hover:text-indigo-400 transition">
                          {row.max_employees != null
                            ? <span className="bg-indigo-900/40 text-indigo-300 px-2 py-0.5 rounded">≤{row.max_employees}</span>
                            : <span className="text-gray-600">∞</span>}
                        </button>
                      </td>
                      <td className="px-4 py-3 text-center align-top">
                        <div className="flex flex-col gap-1 items-center">
                          <button
                            type="button"
                            title="Пакеты +5 сотрудников на заведение"
                            onClick={() => setEmpSlotPacks(row.id, row.grants_employee_slot_packs)}
                            className="text-[10px] font-mono hover:text-indigo-400"
                          >
                            E:{row.grants_employee_slot_packs ?? 0}
                          </button>
                          <button
                            type="button"
                            title="Пакеты +1 филиал"
                            onClick={() => setBranchSlotPacks(row.id, row.grants_branch_slot_packs)}
                            className="text-[10px] font-mono hover:text-indigo-400"
                          >
                            B:{row.grants_branch_slot_packs ?? 0}
                          </button>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-center">
                        <button
                          type="button"
                          onClick={() => toggleAdditiveOnly(row)}
                          className={`text-[10px] px-2 py-0.5 rounded border transition ${
                            row.grants_additive_only
                              ? 'border-amber-600/60 text-amber-200 bg-amber-950/40'
                              : 'border-gray-700 text-gray-600 hover:border-gray-500'
                          }`}
                        >
                          {row.grants_additive_only ? 'да' : 'нет'}
                        </button>
                      </td>
                      <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap" title={row.created_at}>
                        {formatDateTime(row.created_at)}
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex gap-2 justify-end flex-wrap">
                          <button
                            type="button"
                            title={row.is_disabled ? 'Включить промокод' : 'Отключить промокод'}
                            onClick={() => toggleDisabled(row)}
                            disabled={saving}
                            className={`text-xs px-2 py-1 rounded border transition ${row.is_disabled ? 'border-amber-700 text-amber-300 hover:bg-amber-900/30' : 'border-gray-700 text-gray-500 hover:text-amber-200 hover:border-amber-800'}`}
                          >
                            ⏻
                          </button>
                          <button onClick={() => toggleUsed(row)} className="text-gray-500 hover:text-white transition text-xs px-2 py-1 rounded border border-gray-700 hover:border-gray-500">
                            {row.is_used ? '↩' : '✓'}
                          </button>
                          <button onClick={() => deleteCode(row.id)} className="text-gray-500 hover:text-red-400 transition text-xs px-2 py-1 rounded border border-gray-700 hover:border-red-800">
                            ✕
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          {/* Mobile cards */}
          <div className="md:hidden space-y-2">
            {filtered.map(row => {
              const status = promoRowStatus(row)
              const statusCfg = {
                disabled: { label: 'Отключён', cls: 'bg-amber-900/40 text-amber-200' },
                used: { label: 'Использован', cls: 'bg-blue-900/40 text-blue-300' },
                expired: { label: 'Истёк', cls: 'bg-red-900/40 text-red-300' },
                free: { label: 'Свободен', cls: 'bg-emerald-900/40 text-emerald-300' },
              }[status]
              const codeBtnClassMobile = row.is_disabled
                ? 'font-mono font-bold text-red-400 text-base active:text-red-300'
                : 'font-mono font-bold text-white text-base active:text-indigo-400'
              return (
                <div key={row.id} className="bg-gray-900 rounded-xl border border-gray-800 p-4">
                  <div className="flex items-start justify-between gap-2 mb-2">
                    <button
                      type="button"
                      onClick={() => navigator.clipboard.writeText(row.code)}
                      className={codeBtnClassMobile}
                    >
                      {row.code}
                    </button>
                    <span className={`px-2 py-0.5 rounded text-xs font-medium shrink-0 ${statusCfg.cls}`}>
                      {statusCfg.label}
                    </span>
                  </div>

                  {(row.note || (row.is_used && row.establishments?.name)) && (
                    <div className="text-gray-400 text-xs mb-1">
                      {row.is_used && row.establishments?.name ? row.establishments.name : row.note}
                    </div>
                  )}
                  <div className="text-[10px] text-gray-600 mb-1 space-y-0.5">
                    <div>{(row.activation_duration_days ?? 0) > 0 ? 'тип: с активации' : 'тип: классика'}</div>
                    <button
                      type="button"
                      onClick={() => setGrantTier(row)}
                      className="text-indigo-400/90 active:text-indigo-300"
                    >
                      тариф: {subscriptionTierLabelRu(row.grants_subscription_type ?? 'ultra')} — изм.
                    </button>
                  </div>

                  <div className="flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-gray-500 mb-3">
                    {row.activation_duration_days != null && row.activation_duration_days > 0 && (
                      <button
                        type="button"
                        onClick={() => setActivationDays(row.id, row.activation_duration_days ?? null)}
                        className="text-emerald-300"
                      >
                        {row.activation_duration_days} дн. с активации
                      </button>
                    )}
                    {row.expires_at && (
                      <span className={isExpired(row.expires_at) ? 'text-red-400' : ''}>
                        {(row.activation_duration_days ?? 0) > 0 ? 'ввести до ' : 'до '}
                        {formatDate(row.expires_at)}
                      </span>
                    )}
                    {row.max_employees != null && (
                      <span className="text-indigo-300">≤{row.max_employees} сотр.</span>
                    )}
                    <span className="text-gray-600">
                      E:{row.grants_employee_slot_packs ?? 0} B:{row.grants_branch_slot_packs ?? 0}
                      {row.grants_additive_only ? ' · аддон' : ''}
                    </span>
                    <span>создан {formatDate(row.created_at)}</span>
                  </div>

                  <div className="flex gap-2 flex-wrap">
                    <button
                      type="button"
                      onClick={() => toggleDisabled(row)}
                      disabled={saving}
                      className={`px-3 py-2 rounded-lg border text-sm ${row.is_disabled ? 'border-amber-700 text-amber-300' : 'border-gray-700 text-gray-400 hover:text-amber-200'}`}
                      title={row.is_disabled ? 'Включить' : 'Отключить'}
                    >
                      ⏻
                    </button>
                    <button
                      onClick={() => toggleUsed(row)}
                      className="flex-1 min-w-[8rem] text-center text-gray-400 hover:text-white active:text-white transition text-sm py-2 rounded-lg border border-gray-700 active:border-gray-500"
                    >
                      {row.is_used ? '↩ Сбросить' : '✓ Отметить исп.'}
                    </button>
                    <button
                      onClick={() => setEndDate(row.id, row)}
                      className="px-3 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-white active:text-white text-sm"
                      title="Дата окончания / ввода"
                    >
                      📅
                    </button>
                    <button
                      onClick={() => setMaxEmployees(row.id, row.max_employees)}
                      className="px-3 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-white active:text-white text-sm"
                      title="Макс. сотрудников (промо)"
                    >
                      👥
                    </button>
                    <button
                      type="button"
                      onClick={() => setEmpSlotPacks(row.id, row.grants_employee_slot_packs)}
                      className="px-3 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-white text-sm font-mono text-[11px]"
                      title="Пакеты +5 сотрудников на заведение"
                    >
                      E
                    </button>
                    <button
                      type="button"
                      onClick={() => setBranchSlotPacks(row.id, row.grants_branch_slot_packs)}
                      className="px-3 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-white text-sm font-mono text-[11px]"
                      title="Пакеты +1 филиал"
                    >
                      B
                    </button>
                    <button
                      type="button"
                      onClick={() => toggleAdditiveOnly(row)}
                      className="px-3 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-amber-200 text-sm"
                      title="Только аддон"
                    >
                      +
                    </button>
                    <button
                      onClick={() => deleteCode(row.id)}
                      className="px-3 py-2 rounded-lg border border-red-900/50 text-red-500 hover:text-red-400 active:text-red-400 text-sm"
                    >
                      ✕
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
        </>
      )}
    </>
  )
}

// ─── Security Tab ─────────────────────────────────────────────────────────────

function insightTextRu(i: Insight): string {
  const nf = (n: number) => n.toLocaleString('ru-RU')
  switch (i.kind) {
    case 'traffic_volume':
      return `За ~24 ч около ${nf(i.requests24h)} HTTP-запросов к зоне. Сравните с обычным днём: резкий рост часто совпадает с ботами или парсингом.`
    case 'waf_activity':
      return `Срабатывания WAF: блокировок ${i.blocks}, challenge ${i.challenges}. Возможны сканирование, перебор или нетипичный клиент — смотрите Security в Cloudflare.`
    case 'ip_noisy':
      return `IP ${i.ip} даёт ${i.events} событий в выборке — проверьте rate limit / правило для IP (возможен парсинг или скрипт).`
    case 'probe_path':
      return `В выборке есть запрос к подозрительному пути (${i.pathSample}) — похоже на сканирование уязвимостей.`
    case 'db_attack_note':
      return 'Прямой доступ к БД из интернета здесь обычно не виден: Postgres за закрытым API. Риски — через ключи и эндпоинты; полные логи Auth/Edge — в Supabase.'
    default:
      return ''
  }
}

function SecurityTab() {
  const [data, setData] = useState<SecuritySnapshotPayload | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    const res = await fetch('/api/security-snapshot')
    const json = (await res.json()) as SecuritySnapshotPayload & { error?: string }
    if (!res.ok) {
      setError(typeof json?.error === 'string' ? json.error : 'Ошибка загрузки')
      setData(null)
    } else {
      setData(json as SecuritySnapshotPayload)
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    load()
  }, [load])

  if (loading) {
    return <div className="p-12 text-center text-gray-500">Загрузка...</div>
  }
  if (error) {
    return (
      <div className="space-y-4">
        <p className="text-red-300 text-sm">{error}</p>
        <button
          type="button"
          onClick={() => load()}
          className="bg-indigo-600 hover:bg-indigo-500 px-4 py-2 rounded-lg text-sm font-medium"
        >
          Обновить
        </button>
      </div>
    )
  }
  if (!data) return null

  const cf = data.cloudflare
  const reqStr =
    typeof cf.requests24hApprox === 'number'
      ? cf.requests24hApprox.toLocaleString('ru-RU')
      : '—'

  return (
    <div className="space-y-6 max-w-4xl">
      <p className="text-gray-400 text-sm leading-relaxed">
        Сводка периметра: трафик и WAF (Cloudflare, если заданы CLOUDFLARE_API_TOKEN и CLOUDFLARE_ZONE_ID в
        секретах Worker), эвристики и ссылки в консоли. Полные сырые логи — в Cloudflare и Supabase.
      </p>
      <p className="text-gray-500 text-xs">Снимок: {data.generatedAt}</p>

      <section>
        <h2 className="text-base font-semibold text-white mb-2">Cloudflare</h2>
        {!cf.configured ? (
          <p className="text-gray-400 text-sm">
            API Cloudflare не настроен. В Secrets/переменных Worker задайте CLOUDFLARE_API_TOKEN и
            CLOUDFLARE_ZONE_ID (Analytics + Firewall Read) — появятся счётчик и события WAF. Опционально
            CLOUDFLARE_ACCOUNT_ID — для прямых ссылок в дашборд.
          </p>
        ) : (
          <div className="space-y-2">
            <p className="text-gray-200 text-sm">
              Запросы (~24 ч): <span className="font-mono text-indigo-300">{reqStr}</span>
            </p>
            {cf.graphqlErrors && cf.graphqlErrors.length > 0 && (
              <p className="text-amber-300/90 text-xs">{cf.graphqlErrors.join('; ')}</p>
            )}
          </div>
        )}
      </section>

      {data.hint ? (
        <p className="text-amber-200/90 text-sm border border-amber-800/50 rounded-lg p-3 bg-amber-950/20">
          {data.hint}
        </p>
      ) : null}

      <section>
        <h2 className="text-base font-semibold text-white mb-3">Интерпретация</h2>
        <ul className="space-y-3">
          {data.insights.map((row, idx) => (
            <li key={idx} className="flex gap-2 text-sm text-gray-300">
              <span className="shrink-0" title={row.severity}>
                {row.severity === 'warning' ? '⚠️' : 'ℹ️'}
              </span>
              <span>{insightTextRu(row)}</span>
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="text-base font-semibold text-white mb-2">События WAF (последние)</h2>
        {!cf.configured || cf.firewallEvents.length === 0 ? (
          <p className="text-gray-500 text-sm">
            {cf.configured ? 'Нет событий в выборке или недоступно на тарифе/API.' : '—'}
          </p>
        ) : (
          <div className="overflow-x-auto bg-gray-900 rounded-xl border border-gray-800">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-gray-800 text-gray-500 text-left">
                  <th className="px-3 py-2">Действие</th>
                  <th className="px-3 py-2">IP</th>
                  <th className="px-3 py-2">Путь</th>
                  <th className="px-3 py-2">Время</th>
                </tr>
              </thead>
              <tbody>
                {cf.firewallEvents.slice(0, 25).map((e, i) => {
                  const path = (e.clientRequestPath ?? '').toString()
                  const short = path.length > 56 ? `${path.slice(0, 56)}…` : path
                  return (
                    <tr key={i} className="border-b border-gray-800/60">
                      <td className="px-3 py-2 text-gray-300">{e.action ?? '—'}</td>
                      <td className="px-3 py-2 font-mono text-gray-400">{e.clientIP ?? '—'}</td>
                      <td className="px-3 py-2 text-gray-400 max-w-[14rem] truncate" title={path}>
                        {short || '—'}
                      </td>
                      <td className="px-3 py-2 text-gray-500 whitespace-nowrap">{e.datetime ?? '—'}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section>
        <h2 className="text-base font-semibold text-white mb-2">Полные логи</h2>
        <ul className="space-y-2 text-sm">
          <li>
            <a
              href={data.links.cloudflareSecurity}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline"
            >
              Cloudflare — Security / Analytics
            </a>
          </li>
          <li>
            <a
              href={data.links.cloudflareWaf}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline"
            >
              Cloudflare — WAF
            </a>
          </li>
          <li>
            <a
              href={data.links.supabaseLogs}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline"
            >
              Supabase — Logs
            </a>
          </li>
          <li>
            <a
              href={data.links.supabaseAuth}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline"
            >
              Supabase — Auth
            </a>
          </li>
        </ul>
      </section>

      <button
        type="button"
        onClick={() => load()}
        className="bg-gray-800 hover:bg-gray-700 border border-gray-700 px-4 py-2 rounded-lg text-sm"
      >
        Обновить данные
      </button>
    </div>
  )
}

// ─── System health / load Tab ─────────────────────────────────────────────────

function SystemHealthTab() {
  const [data, setData] = useState<SystemHealthPayload | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    const res = await fetch('/api/system-health')
    const json = (await res.json()) as SystemHealthPayload & { error?: string }
    if (!res.ok) {
      setError(typeof json?.error === 'string' ? json.error : 'Ошибка загрузки')
      setData(null)
    } else {
      setData(json as SystemHealthPayload)
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    load()
  }, [load])

  if (loading) {
    return <div className="p-12 text-center text-gray-500">Загрузка...</div>
  }
  if (error) {
    return (
      <div className="space-y-4">
        <p className="text-red-300 text-sm">{error}</p>
        <button
          type="button"
          onClick={() => load()}
          className="bg-indigo-600 hover:bg-indigo-500 px-4 py-2 rounded-lg text-sm font-medium"
        >
          Повторить
        </button>
      </div>
    )
  }
  if (!data) return null

  const reqStr =
    typeof data.cloudflare.requests24hApprox === 'number'
      ? data.cloudflare.requests24hApprox.toLocaleString('ru-RU')
      : '—'

  function latencyClass(ms: number, ok: boolean): string {
    if (!ok) return 'text-red-400'
    if (ms >= 1200) return 'text-amber-300'
    return 'text-emerald-300'
  }

  return (
    <div className="space-y-6 max-w-4xl">
      <p className="text-gray-400 text-sm leading-relaxed">
        Быстрые проверки из админки: доступность Supabase (Auth и API к БД) и объём HTTP-запросов к зоне сайта в
        Cloudflare за ~24 ч. Это не замена мониторингу в Supabase (CPU, квоты, логи Edge), но помогает заметить
        отказ или аномальный трафик до того, как «ляжет» приложение у пользователей.
      </p>
      <div className="flex flex-wrap items-center gap-3">
        <span
          className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${
            data.ok ? 'bg-emerald-950/60 text-emerald-200 border border-emerald-800/50' : 'bg-red-950/60 text-red-200 border border-red-800/50'
          }`}
        >
          {data.ok ? 'Критичные проверки пройдены' : 'Есть проблемы доступности'}
        </span>
        <span className="text-gray-500 text-xs">Снимок: {data.generatedAt}</span>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 sm:gap-3">
        <StatCard
          label="Auth (GoTrue)"
          value={data.authHealth ? `${data.authHealth.latencyMs} мс` : '—'}
          dimmed={!data.authHealth?.ok}
        />
        <StatCard
          label="API БД (PostgREST)"
          value={data.restSmoke ? `${data.restSmoke.latencyMs} мс` : '—'}
          dimmed={!data.restSmoke?.ok}
        />
        <StatCard
          label="Заведений (оценка)"
          value={data.restRowEstimate != null ? data.restRowEstimate : '—'}
        />
        <StatCard label="HTTP к зоне (~24 ч)" value={reqStr} />
      </div>

      {(data.authHealth || data.restSmoke) && (
        <div className="text-xs text-gray-500 space-y-1 font-mono">
          {data.authHealth ? (
            <p className={latencyClass(data.authHealth.latencyMs, data.authHealth.ok)}>
              Auth: {data.authHealth.ok ? 'OK' : 'FAIL'}
              {data.authHealth.status != null ? ` ${data.authHealth.status}` : ''}
              {data.authHealth.detail ? ` — ${data.authHealth.detail}` : ''}
            </p>
          ) : null}
          {data.restSmoke ? (
            <p className={latencyClass(data.restSmoke.latencyMs, data.restSmoke.ok)}>
              REST HEAD establishments: {data.restSmoke.ok ? 'OK' : 'FAIL'}
              {data.restSmoke.status != null ? ` ${data.restSmoke.status}` : ''}
              {data.restSmoke.detail ? ` — ${data.restSmoke.detail}` : ''}
            </p>
          ) : null}
          {data.supabaseUrlHost ? (
            <p className="text-gray-600 truncate" title={data.supabaseUrlHost}>
              Хост: {data.supabaseUrlHost}
            </p>
          ) : null}
        </div>
      )}

      {!data.cloudflare.configured && (
        <p className="text-amber-200/90 text-sm border border-amber-800/50 rounded-lg p-3 bg-amber-950/20">
          Трафик Cloudflare не подключён: добавьте CLOUDFLARE_API_TOKEN и CLOUDFLARE_ZONE_ID в секреты Worker — как для
          вкладки «Безопасность».
        </p>
      )}
      {data.cloudflare.configured && data.cloudflare.graphqlError && (
        <p className="text-amber-300/90 text-xs">{data.cloudflare.graphqlError}</p>
      )}

      {data.hints.length > 0 && (
        <section>
          <h2 className="text-base font-semibold text-white mb-2">Подсказки</h2>
          <ul className="space-y-2">
            {data.hints.map((h, i) => (
              <li key={i} className="text-sm text-gray-400 border-l-2 border-gray-700 pl-3">
                {h}
              </li>
            ))}
          </ul>
        </section>
      )}

      <section>
        <h2 className="text-base font-semibold text-white mb-2">Где смотреть полные метрики</h2>
        <ul className="space-y-2 text-sm">
          <li>
            <a
              href={data.links.supabaseProject}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline"
            >
              Supabase — проект (отчёты, логи, биллинг)
            </a>
          </li>
          <li>
            <a
              href={data.links.supabaseAdvisor}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline"
            >
              Supabase — Advisors (медленные запросы, индексы)
            </a>
          </li>
          <li>
            <a
              href={data.links.cloudflareAnalytics}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline"
            >
              Cloudflare — аналитика трафика зоны
            </a>
          </li>
          <li>
            <a
              href={data.links.cloudflareWorkersOverview}
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-400 hover:text-indigo-300 underline"
            >
              Cloudflare — Workers &amp; Pages (в т.ч. эта админка)
            </a>
          </li>
        </ul>
      </section>

      <button
        type="button"
        onClick={() => load()}
        className="bg-gray-800 hover:bg-gray-700 border border-gray-700 px-4 py-2 rounded-lg text-sm"
      >
        Обновить проверки
      </button>
    </div>
  )
}

// ─── Platform Settings Tab ────────────────────────────────────────────────────

function PlatformSettingsTab() {
  const [maxEstablishments, setMaxEstablishments] = useState<number>(5)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    const res = await fetch('/api/platform-config')
    const data = await res.json()
    if (!res.ok) {
      setError(data?.error || 'Ошибка загрузки')
    } else {
      setMaxEstablishments(data.max_establishments_per_owner ?? 5)
    }
    setLoading(false)
  }, [])

  useEffect(() => { load() }, [load])

  async function save() {
    setSaving(true)
    setError(null)
    const res = await fetch('/api/platform-config', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ max_establishments_per_owner: maxEstablishments }),
    })
    const data = await res.json()
    if (!res.ok) {
      setError(data?.error || 'Ошибка сохранения')
    }
    setSaving(false)
  }

  if (loading) return <div className="p-12 text-center text-gray-500">Загрузка...</div>

  return (
    <>
      {error && (
        <div className="mb-4 p-4 bg-red-900/30 border border-red-700 rounded-lg text-red-200 text-sm">
          {error}
        </div>
      )}
      <div className="bg-gray-900 rounded-xl p-6 border border-gray-800 max-w-md">
        <h2 className="text-base font-medium text-white mb-4">Лимит заведений на одного владельца</h2>
        <p className="text-gray-400 text-sm mb-4">
          Максимум дополнительных заведений (первое не в счёт). Владелец может добавить до этого числа дополнительных заведений.
          Для отдельных аккаунтов лимит можно переопределить на вкладке «Заведения» (колонка «Лимит доп.»); если задано на нескольких заведениях одного владельца, действует минимальное значение.
        </p>
        <div className="flex items-center gap-3">
          <input
            type="number"
            min={0}
            max={999}
            value={maxEstablishments}
            onChange={e => setMaxEstablishments(Math.max(0, Math.min(999, parseInt(e.target.value, 10) || 0)))}
            className="bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 text-white w-24 focus:outline-none focus:border-indigo-500"
          />
          <span className="text-gray-400 text-sm">дополнительных заведений</span>
        </div>
        <button
          onClick={save}
          disabled={saving}
          className="mt-4 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 px-4 py-2 rounded-lg font-medium text-sm"
        >
          {saving ? 'Сохранение...' : 'Сохранить'}
        </button>
      </div>
    </>
  )
}

// ─── Shared Components ────────────────────────────────────────────────────────

function StatCard({ label, value, dimmed }: { label: string; value: number | string; dimmed?: boolean }) {
  return (
    <div className="bg-gray-900 rounded-xl p-3 sm:p-4 border border-gray-800">
      <div className={`text-xl sm:text-2xl font-bold ${dimmed ? 'text-gray-600' : 'text-white'}`}>{value}</div>
      <div className="text-gray-500 text-xs sm:text-sm mt-1">{label}</div>
    </div>
  )
}
