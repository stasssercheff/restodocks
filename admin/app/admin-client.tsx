'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import type { PromoCode, PromoRedemptionDetail } from '@/lib/supabase'
import type { Insight, SecuritySnapshotPayload } from '@/lib/security-snapshot'
import type { SystemHealthPayload } from '@/lib/system-health'
import {
  PROMO_GRANT_SUBSCRIPTION_TYPES,
  SUBSCRIPTION_PAID_TIERS_DB,
  isSelectablePromoGrantTier,
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

function formatUsd(amount: number | null | undefined) {
  const n = Number(amount ?? 0)
  if (!Number.isFinite(n)) return '$0.00'
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  }).format(n)
}

/** Значение для `input type="date"` (календарь в локальной дате). */
function isoToDateInputValue(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
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
function promoRowStatus(row: PromoCode): 'disabled' | 'used' | 'partial' | 'expired' | 'free' {
  if (row.is_disabled) return 'disabled'
  if (row.is_used) return 'used'
  const rc = row.redemption_count ?? 0
  if (rc > 0) return 'partial'
  if (!isValidNow(row.starts_at, row.expires_at)) return 'expired'
  return 'free'
}

// ─── Main ─────────────────────────────────────────────────────────────────────

const RD_ADMIN_SUPPORT_KEY = 'rd_admin_support_active'

export default function AdminClient() {
  const router = useRouter()
  const [tab, setTab] = useState<
    'establishments' | 'promo' | 'broadcast' | 'support' | 'security' | 'health' | 'ai_usage'
  >('establishments')
  const [supportShellHighlight, setSupportShellHighlight] = useState(false)

  useEffect(() => {
    try {
      if (typeof window !== 'undefined' && sessionStorage.getItem(RD_ADMIN_SUPPORT_KEY) === '1') {
        setSupportShellHighlight(true)
      }
    } catch {
      /* ignore */
    }
  }, [])

  async function logout() {
    await fetch('/api/auth', { method: 'DELETE' })
    router.push('/login')
  }

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <header
        className={`px-4 py-3 flex items-center justify-between sticky top-0 z-10 border-b transition-colors ${
          supportShellHighlight
            ? 'border-purple-500/70 bg-purple-950/95 shadow-[0_0_24px_rgba(147,51,234,0.25)]'
            : 'border-amber-900/40 bg-gray-950'
        }`}
      >
        <div className="flex items-center gap-2">
          <span className="font-bold text-base">Restodocks</span>
          <span className="text-gray-500 text-sm hidden sm:inline">/ Admin</span>
          {supportShellHighlight ? (
            <span className="text-xs font-medium text-purple-200/95 hidden sm:inline">
              — сеанс техподдержки открыт
            </span>
          ) : null}
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
            { key: 'ai_usage', label: 'AI Usage' },
            { key: 'broadcast', label: 'Рассылка' },
            { key: 'support', label: 'Техподдержка' },
            { key: 'security', label: 'Безопасность' },
            { key: 'health', label: 'Нагрузка' },
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

      <main className="max-w-[min(1600px,calc(100vw-1.5rem))] mx-auto px-3 py-4 sm:px-6 sm:py-8">
        {tab === 'establishments' && <EstablishmentsTab />}
        {tab === 'promo' && <PromoTab />}
        {tab === 'ai_usage' && <AiUsageTab />}
        {tab === 'broadcast' && <BroadcastTab />}
        {tab === 'support' && (
          <SupportAccessTab
            onSupportShellActiveChange={active => {
              setSupportShellHighlight(active)
              try {
                if (typeof window === 'undefined') return
                if (active) sessionStorage.setItem(RD_ADMIN_SUPPORT_KEY, '1')
                else sessionStorage.removeItem(RD_ADMIN_SUPPORT_KEY)
              } catch {
                /* ignore */
              }
            }}
          />
        )}
        {tab === 'security' && <SecurityTab />}
        {tab === 'health' && <SystemHealthTab />}
      </main>
    </div>
  )
}

function SupportAccessTab({
  onSupportShellActiveChange,
}: {
  onSupportShellActiveChange?: (active: boolean) => void
}) {
  const [supportOperatorLogin, setSupportOperatorLogin] = useState('')
  const [accountLogin, setAccountLogin] = useState('')
  const [appOrigin, setAppOrigin] = useState('https://restodocks-beta.pages.dev')
  const [activeEstablishmentId, setActiveEstablishmentId] = useState<string | null>(null)
  const [activeEstablishmentName, setActiveEstablishmentName] = useState<string | null>(null)
  const [logs, setLogs] = useState<Array<{ id: number; event_type: string; support_operator_login: string | null; account_login: string | null; created_at: string }>>([])
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function loadLogs(establishmentId: string) {
    const res = await fetch(`/api/support?establishment_id=${encodeURIComponent(establishmentId)}`)
    const data = await res.json()
    if (!res.ok) {
      setError(typeof data?.error === 'string' ? data.error : 'Ошибка журнала')
      return
    }
    setLogs(Array.isArray(data) ? data : [])
  }

  useEffect(() => {
    try {
      if (typeof window === 'undefined') return
      if (sessionStorage.getItem(RD_ADMIN_SUPPORT_KEY) !== '1') return
      const raw = sessionStorage.getItem('rd_admin_support_meta')
      if (!raw) return
      const meta = JSON.parse(raw) as { id?: string; name?: string }
      if (meta?.id) {
        setActiveEstablishmentId(meta.id)
        setActiveEstablishmentName(meta.name ?? null)
        void loadLogs(meta.id)
      }
    } catch {
      /* ignore */
    }
  }, [])

  async function startSupportSession() {
    setBusy(true)
    setError(null)
    try {
      const res = await fetch('/api/support', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          support_operator_login: supportOperatorLogin.trim() || 'admin',
          account_login: accountLogin.trim().toLowerCase(),
          app_origin: appOrigin.trim(),
        }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(typeof data?.error === 'string' ? data.error : `Ошибка (${res.status})`)
        return
      }
      const est = data?.establishment
      setActiveEstablishmentId(est?.id ?? null)
      setActiveEstablishmentName(est?.name ?? null)
      if (est?.id) {
        try {
          sessionStorage.setItem(
            'rd_admin_support_meta',
            JSON.stringify({ id: est.id, name: est.name }),
          )
        } catch {
          /* ignore */
        }
        await loadLogs(est.id)
      }
      onSupportShellActiveChange?.(true)
      if (typeof data?.warning === 'string' && data.warning.length > 0) {
        alert(data.warning)
      }
      if (typeof data?.action_link === 'string' && data.action_link.length > 0) {
        window.open(data.action_link, '_blank', 'noopener,noreferrer')
      }
      alert(
        'Сеанс техподдержки открыт: верхняя панель админки подсвечена фиолетовым — так видно, что вы в режиме входа в аккаунт пользователя. Ссылка для входа открыта в новой вкладке.',
      )
    } finally {
      setBusy(false)
    }
  }

  async function endSupportSession() {
    if (!activeEstablishmentId) return
    setBusy(true)
    setError(null)
    try {
      const res = await fetch('/api/support', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ establishment_id: activeEstablishmentId }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(typeof data?.error === 'string' ? data.error : `Ошибка (${res.status})`)
        return
      }
      try {
        sessionStorage.removeItem('rd_admin_support_meta')
      } catch {
        /* ignore */
      }
      onSupportShellActiveChange?.(false)
      await loadLogs(activeEstablishmentId)
      alert('Сеанс техподдержки завершён.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-4 max-w-3xl">
      {error && <div className="p-3 rounded-lg border border-red-800 bg-red-950/40 text-red-200 text-sm">{error}</div>}
      <div className="bg-gray-900 rounded-xl border border-gray-800 p-4 space-y-3">
        <h2 className="text-sm font-semibold text-white">Доступ техподдержки</h2>
        <p className="text-xs text-gray-500">
          Введите логин учётной записи (email). PIN вводит владелец на своей стороне вместе с тумблером доступа.
        </p>
        <div className="grid sm:grid-cols-2 gap-2">
          <input value={supportOperatorLogin} onChange={e => setSupportOperatorLogin(e.target.value)} placeholder="Логин оператора" className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm" />
          <input value={accountLogin} onChange={e => setAccountLogin(e.target.value)} placeholder="Логин учётной записи (email)" className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm" />
        </div>
        <input value={appOrigin} onChange={e => setAppOrigin(e.target.value)} placeholder="Origin веб-приложения, куда входить (например https://restodocks-beta.pages.dev)" className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-xs" />
        <div className="flex gap-2">
          <button onClick={startSupportSession} disabled={busy || !accountLogin.trim()} className="bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 px-4 py-2 rounded-lg text-sm">
            Открыть доступ
          </button>
          <button onClick={endSupportSession} disabled={busy || !activeEstablishmentId} className="bg-gray-800 border border-gray-700 hover:bg-gray-700 disabled:opacity-50 px-4 py-2 rounded-lg text-sm">
            Закрыть доступ
          </button>
        </div>
      </div>

      {activeEstablishmentId && (
        <div className="bg-gray-900 rounded-xl border border-gray-800 p-4">
          <div className="text-sm text-gray-300 mb-2">Активное заведение: <span className="text-white">{activeEstablishmentName ?? activeEstablishmentId}</span></div>
          <div className="space-y-1 text-xs text-gray-400">
            {logs.map(row => (
              <div key={row.id} className="flex flex-wrap gap-2 border-b border-gray-800 pb-1">
                <span>{row.event_type}</span>
                <span>Оператор: {row.support_operator_login ?? '—'}</span>
                <span>Логин: {row.account_login ?? '—'}</span>
                <span>{formatDateTime(row.created_at)}</span>
              </div>
            ))}
            {logs.length === 0 && <div className="text-gray-600">Записей пока нет</div>}
          </div>
        </div>
      )}
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
      <div className="space-y-0.5 max-w-[11rem] min-w-0">
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
      alert(`Заведение «${row.name}» удалено из базы (строка establishments).`)
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Ошибка удаления'
      setError(msg)
      alert(`Не удалось удалить заведение «${row.name}».\n\n${msg}\n\nЕсли здесь про миграцию или функцию admin_delete_establishment — выполните её в Supabase (см. репозиторий, папка supabase/migrations).`)
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
            {' '}(колонка <code className="text-gray-500">pro_paid_until</code>). Ошибка входа/401 — проверь Secrets в Cloudflare (<code className="text-gray-500">SUPABASE_URL</code>,{' '}
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
        <p className="mt-3 text-xs text-gray-500 leading-relaxed border-t border-gray-800 pt-3">
          <span className="text-gray-400">Заведения и филиалы</span> создаются только в приложении (регистрация, экран «Мои заведения» / добавление филиала). В этой админке нет кнопки «создать заведение» — здесь только список из БД, удаление и гео. Если
          строка «видна в админке, но не в приложении», это всё равно записи в Supabase; после успешного удаления появится подтверждение; при ошибке — текст в алерте и в красном блоке выше.
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
            <table className="w-full text-xs sm:text-sm min-w-full">
              <thead>
                <tr className="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wide">
                  <th className="px-2 py-2.5 sm:px-3 text-left">Заведение</th>
                  <th className="px-2 py-2.5 sm:px-3 text-left align-top">
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
                    className="px-2 py-2.5 sm:px-3 text-left min-w-[9rem] align-top"
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
                  <th className="px-2 py-2.5 sm:px-3 text-left">Владелец</th>
                  <th className="px-2 py-2.5 sm:px-3 text-left">Email</th>
                  <th className="px-2 py-2.5 sm:px-3 text-center align-top">
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
                  <th
                    className="px-2 py-2.5 sm:px-3 text-left min-w-[8rem]"
                    title="Дата и время создания записи заведения в БД. Без промокода: 72 ч Pro с этого момента (см. pro_trial_ends_at)."
                  >
                    Регистрация
                  </th>
                  <th className="px-2 py-2.5 sm:px-3 text-left">IP регистрации</th>
                  <th
                    className="px-3 py-3 text-right w-[5.5rem] sticky right-0 z-20 bg-gray-900 border-l border-gray-800 shadow-[-6px_0_12px_-4px_rgba(0,0,0,0.45)]"
                    title="Действия — при узком окне колонка закреплена справа"
                  >
                    <span className="sr-only">Действия</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((row, i) => (
                  <tr
                    key={row.id}
                    className={`group border-b border-gray-800/50 hover:bg-gray-800/30 transition ${i === filtered.length - 1 ? 'border-0' : ''}`}
                  >
                    <td className="px-2 py-2.5 sm:px-3 font-medium text-white max-w-[11rem] sm:max-w-[14rem] min-w-0">
                      <div className="flex items-center gap-2 flex-wrap min-w-0">
                        <span className="min-w-0 truncate" title={row.name}>
                          {row.name}
                        </span>
                        <button
                          type="button"
                          onClick={() => handleDelete(row)}
                          disabled={deleting === row.id}
                          className="hidden max-xl:inline-flex shrink-0 text-red-400/90 hover:text-red-300 text-[11px] font-medium underline underline-offset-2 disabled:opacity-50"
                          title="Удалить без прокрутки таблицы вправо"
                        >
                          {deleting === row.id ? '…' : 'Удалить'}
                        </button>
                      </div>
                    </td>
                    <td className="px-2 py-2.5 sm:px-3 text-xs whitespace-nowrap">
                      <span className={establishmentTypeBadgeClass(row)}>
                        {establishmentTypeLabel(row)}
                      </span>
                    </td>
                    <td className="px-2 py-2.5 sm:px-3 align-top text-gray-300 min-w-0 w-[11rem]">
                      <SubscriptionBlock row={row} />
                    </td>
                    <td className="px-2 py-2.5 sm:px-3 text-gray-300 max-w-[10rem] sm:max-w-[12rem] truncate min-w-0" title={row.owner_name}>
                      {row.owner_name}
                    </td>
                    <td className="px-2 py-2.5 sm:px-3 text-gray-400 text-xs max-w-[12rem] sm:max-w-[14rem] truncate min-w-0" title={row.owner_email}>
                      {row.owner_email}
                    </td>
                    <td className="px-2 py-2.5 sm:px-3 text-center">
                      <span className="bg-gray-800 px-2 py-0.5 rounded text-xs font-mono">{row.employee_count}</span>
                    </td>
                    <td className="px-2 py-2.5 sm:px-3 text-gray-500 text-xs whitespace-nowrap" title={row.created_at}>
                      {formatDateTime(row.created_at)}
                    </td>
                    <td className="px-2 py-2.5 sm:px-3 text-gray-400 text-xs font-mono max-w-[min(14rem,22vw)] truncate min-w-0" title={regInfo(row)}>
                      {regInfo(row)}
                    </td>
                    <td className="px-2 py-2.5 sm:px-3 text-right sticky right-0 z-10 bg-gray-900 group-hover:bg-gray-800/30 border-l border-gray-800 shadow-[-6px_0_12px_-4px_rgba(0,0,0,0.45)]">
                      <button
                        type="button"
                        onClick={() => handleDelete(row)}
                        disabled={deleting === row.id}
                        className="text-red-400 hover:text-red-300 text-xs disabled:opacity-50 min-w-[2rem]"
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
              </div>
            ))}
          </div>
        </>
      )}
    </>
  )
}

/** Выбор тарифа промокода (pro/ultra); для старых строк в БД — доп. опция с текущим значением. */
function PromoGrantTierSelect({
  row,
  saving,
  onPick,
  className,
}: {
  row: PromoCode
  saving: boolean
  onPick: (row: PromoCode, next: string) => void
  className?: string
}) {
  const grantRaw = (row.grants_subscription_type ?? 'ultra').toLowerCase().trim()
  const isLegacy = !isSelectablePromoGrantTier(grantRaw)
  return (
    <select
      value={grantRaw}
      onChange={e => onPick(row, e.target.value)}
      disabled={saving}
      title="Тариф при погашении кода (subscription_type в заведении на момент активации)"
      className={
        className ??
        'mt-0.5 bg-gray-900 border border-gray-700 rounded px-2 py-1 text-[10px] text-gray-200 max-w-[11rem]'
      }
    >
      {isLegacy && (
        <option value={grantRaw}>
          Текущий (legacy): {subscriptionTierLabelRu(grantRaw)} ({grantRaw})
        </option>
      )}
      {PROMO_GRANT_SUBSCRIPTION_TYPES.map(t => (
        <option key={t} value={t}>
          {subscriptionTierLabelRu(t)} ({t})
        </option>
      ))}
    </select>
  )
}

function PromoRecipientsCell({ row }: { row: PromoCode }) {
  const details = row.redemption_details
  if (details && details.length > 0) {
    return (
      <div className="space-y-1.5 max-w-[18rem]">
        {details.map((d: PromoRedemptionDetail, idx: number) => (
          <div key={`${d.establishment_id}-${idx}`} className="leading-snug">
            <div className="text-white text-[13px]">
              {d.establishment_name?.trim() || '—'}
              {d.owner_email ? <span className="text-indigo-300/95"> · {d.owner_email}</span> : null}
            </div>
            {d.owner_name && !d.owner_email ? (
              <div className="text-gray-500 text-[10px]">{d.owner_name}</div>
            ) : null}
            {d.redeemed_at ? (
              <div className="text-gray-600 text-[10px]">{formatDateTime(d.redeemed_at)}</div>
            ) : null}
          </div>
        ))}
        {row.note ? (
          <div className="text-gray-600 text-[10px] pt-1 border-t border-gray-800/80 mt-1">Заметка: {row.note}</div>
        ) : null}
      </div>
    )
  }
  if (row.is_used && row.establishments?.name) {
    return <span className="text-white">{row.establishments.name}</span>
  }
  return <span className="text-gray-500">{row.note || '—'}</span>
}

// ─── Promo Tab ────────────────────────────────────────────────────────────────

function PromoTab() {
  const EMPLOYEE_PACK_OPTIONS = [0, 5, 8, 12, 15] as const
  const BRANCH_PACK_OPTIONS = [0, 1, 3, 5, 10] as const
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
  /** Подписка расширения сотрудников: значение из фиксированного набора пакетов. */
  const [newEmpSlotPacks, setNewEmpSlotPacks] = useState('0')
  /** Подписка расширения заведений: значение из фиксированного набора пакетов. */
  const [newBranchSlotPacks, setNewBranchSlotPacks] = useState('0')
  const [newAdditiveOnly, setNewAdditiveOnly] = useState(false)
  /** Сколько раз один код можно применить (разные учётные записи / заведения). */
  const [newMaxRedemptions, setNewMaxRedemptions] = useState('1')
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<'all' | 'free' | 'used' | 'expired' | 'disabled'>('all')
  /** Редактирование даты окончания / «ввести до» у существующего промокода (вместо prompt). */
  const [expiryEditRow, setExpiryEditRow] = useState<PromoCode | null>(null)
  const [expiryEditDraft, setExpiryEditDraft] = useState('')

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
    if (
      Number.isNaN(empN) ||
      Number.isNaN(brN) ||
      !EMPLOYEE_PACK_OPTIONS.includes(empN as typeof EMPLOYEE_PACK_OPTIONS[number]) ||
      !BRANCH_PACK_OPTIONS.includes(brN as typeof BRANCH_PACK_OPTIONS[number])
    ) {
      alert('Выберите пакет из списка для сотрудников и заведений.')
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
    const maxR = newMaxRedemptions.trim() ? parseInt(newMaxRedemptions.trim(), 10) : NaN
    if (Number.isNaN(maxR) || maxR < 1 || maxR > 100000) {
      alert('«Сколько учётных записей»: целое число от 1 до 100000 (по умолчанию 1).')
      return
    }
    setSaving(true)
    setError(null)
    try {
      const res = await fetch('/api/promo', {
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
          max_redemptions: maxR,
        }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(typeof data?.error === 'string' ? data.error : `Не удалось создать промокод (${res.status})`)
        return
      }
      setNewCode('')
      setNewNote('')
      setNewStartDate('')
      setNewEndDate('')
      setNewActivationDays('')
      setNewPromoLogic('legacy')
      setNewGrantTier('ultra')
      setNewMaxEmployees('')
      setNewEmpSlotPacks('0')
      setNewBranchSlotPacks('0')
      setNewAdditiveOnly(false)
      setNewMaxRedemptions('1')
      await loadCodes()
    } finally {
      setSaving(false)
    }
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

  function openPromoExpiryEdit(row: PromoCode) {
    setExpiryEditRow(row)
    setExpiryEditDraft(isoToDateInputValue(row.expires_at))
  }

  function closePromoExpiryEdit() {
    setExpiryEditRow(null)
    setExpiryEditDraft('')
  }

  async function savePromoExpiryEdit(forceValue?: string | null) {
    if (!expiryEditRow) return
    const id = expiryEditRow.id
    const val = forceValue !== undefined ? forceValue : expiryEditDraft.trim() || null
    setSaving(true)
    setError(null)
    try {
      const res = await fetch('/api/promo', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id, expires_at: val }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(typeof data?.error === 'string' ? data.error : `Не удалось сохранить дату (${res.status})`)
        return
      }
      closePromoExpiryEdit()
      await loadCodes()
    } finally {
      setSaving(false)
    }
  }

  async function patchPromoGrantTier(row: PromoCode, next: string) {
    const cur = (row.grants_subscription_type ?? 'ultra').toLowerCase().trim()
    const g = next.trim().toLowerCase()
    if (cur === g) return
    setSaving(true)
    setError(null)
    try {
      const res = await fetch('/api/promo', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: row.id, grants_subscription_type: g }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(typeof data?.error === 'string' ? data.error : `Не удалось сохранить тариф (${res.status})`)
        return
      }
      await loadCodes()
    } finally {
      setSaving(false)
    }
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

  async function setMaxRedemptionsRow(id: number, current: number | null) {
    const val = prompt(
      'Сколько раз можно применить этот код (разные учётные записи). Уже погашенные не снимаются.',
      current != null ? String(current) : '1',
    )
    if (val === null) return
    const t = val.trim()
    const parsed = t === '' ? 1 : parseInt(t, 10)
    if (Number.isNaN(parsed) || parsed < 1 || parsed > 100000) {
      alert('Введи целое от 1 до 100000')
      return
    }
    setSaving(true)
    setError(null)
    try {
      const res = await fetch('/api/promo', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id, max_redemptions: parsed }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(typeof data?.error === 'string' ? data.error : `Не удалось сохранить лимит (${res.status})`)
        return
      }
      await loadCodes()
    } finally {
      setSaving(false)
    }
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

  async function setEmpSlotPacks(id: number, nextValue: number) {
    if (!EMPLOYEE_PACK_OPTIONS.includes(nextValue as typeof EMPLOYEE_PACK_OPTIONS[number])) return
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, grants_employee_slot_packs: nextValue }),
    })
    await loadCodes()
  }

  async function setBranchSlotPacks(id: number, nextValue: number) {
    if (!BRANCH_PACK_OPTIONS.includes(nextValue as typeof BRANCH_PACK_OPTIONS[number])) return
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, grants_branch_slot_packs: nextValue }),
    })
    await loadCodes()
  }

  async function toggleAdditiveOnly(row: PromoCode) {
    const next = !row.grants_additive_only
    const ok = next
      ? confirm(
          'Включить «только расширения»? Код не меняет тариф Pro/Ultra — только начисляет подписки расширения (+5 сотр. / +1 филиал), если они заданы.',
        )
      : confirm('Выключить «только расширения»?')
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
    if (next && (row.is_used || (row.redemption_count ?? 0) > 0)) {
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
    if (filter === 'free') return st === 'free' || st === 'partial'
    if (filter === 'used') return c.is_used
    if (filter === 'expired') return st === 'expired'
    if (filter === 'disabled') return c.is_disabled === true
    return true
  })

  const total = codes.length
  const usedCount = codes.filter(c => c.is_used).length
  const freeCount = codes.filter(c => {
    const st = promoRowStatus(c)
    return st === 'free' || st === 'partial'
  }).length
  const expiredCount = codes.filter(c => promoRowStatus(c) === 'expired').length
  const disabledCount = codes.filter(c => c.is_disabled === true).length

  return (
    <>
      {error && (
        <div className="mb-4 p-4 bg-red-900/30 border border-red-700 rounded-lg text-red-200 text-sm">
          {error}
        </div>
      )}
      {expiryEditRow && (
        <div
          className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          role="dialog"
          aria-modal="true"
          aria-labelledby="promo-expiry-title"
          onClick={() => {
            if (!saving) closePromoExpiryEdit()
          }}
        >
          <div
            className="bg-gray-900 border border-gray-700 rounded-xl p-5 max-w-md w-full shadow-xl"
            onClick={e => e.stopPropagation()}
          >
            <h3 id="promo-expiry-title" className="text-white font-medium mb-2">
              Дата окончания / срок ввода
            </h3>
            <p className="text-gray-400 text-sm mb-3 leading-relaxed">
              {(expiryEditRow.activation_duration_days ?? 0) > 0
                ? 'Последний день, когда код ещё можно ввести. Без даты — нет ограничения по календарю.'
                : 'Действует до (классический промокод без режима «дней с активации»). Без даты — без ограничения.'}
            </p>
            <p className="text-gray-500 text-xs font-mono mb-3">{expiryEditRow.code}</p>
            <input
              type="date"
              value={expiryEditDraft}
              onChange={e => setExpiryEditDraft(e.target.value)}
              disabled={saving}
              className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:border-indigo-500 mb-4 [color-scheme:dark]"
            />
            <div className="flex flex-wrap gap-2 justify-end">
              <button
                type="button"
                onClick={() => {
                  if (!saving) closePromoExpiryEdit()
                }}
                disabled={saving}
                className="px-4 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-white text-sm disabled:opacity-50"
              >
                Отмена
              </button>
              <button
                type="button"
                onClick={() => void savePromoExpiryEdit(null)}
                disabled={saving}
                className="px-4 py-2 rounded-lg border border-amber-800/80 text-amber-200/90 hover:bg-amber-950/40 text-sm disabled:opacity-50"
              >
                Без даты
              </button>
              <button
                type="button"
                onClick={() => void savePromoExpiryEdit()}
                disabled={saving}
                className="px-4 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-sm disabled:opacity-50"
              >
                {saving ? '…' : 'Сохранить'}
              </button>
            </div>
          </div>
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
      <p className="text-gray-600 text-xs mb-4 leading-relaxed border-l-2 border-gray-800 pl-3">
        Тариф в строке промокода задаёт, что запишется в{' '}
        <code className="text-gray-500 text-[10px]">establishments.subscription_type</code> в момент{' '}
        <span className="text-gray-500">первого погашения</span> кода. Уже активированный код не переписывает заведение —
        смена тарифа здесь влияет на новые активации и на отображение в админке.
      </p>

      {/* Add form */}
      <div className="bg-gray-900 rounded-xl p-4 border border-gray-800 mb-4">
        <h2 className="text-xs font-medium text-gray-500 mb-3 uppercase tracking-wide">Новый промокод</h2>
        <p className="text-[11px] text-gray-600 mb-3 leading-snug">
          <span className="text-gray-500 font-medium">Промокод</span> — код выдачи тарифа (Pro/Ultra), сроков и при необходимости лимита сотрудников; это не то же самое, что платные подписки расширения в приложении.
          Уже созданные коды <span className="text-gray-500">не меняются</span> автоматически: у старых пустое «дней с активации».
          Ниже можно завести <span className="text-gray-500">второй тип срока</span> — дни Pro с момента активации кода.
        </p>
        <p className="text-[11px] text-gray-600 mb-3 leading-snug border-l-2 border-indigo-700/50 pl-3">
          <span className="text-gray-500 font-medium">Подписки расширения Lite</span>: выбор только из фиксированных пакетов.
          Для сотрудников: <span className="text-gray-400">+5 / +8 / +12 / +15</span>.
          Для заведений: <span className="text-gray-400">+1 / +3 / +5 / +10</span>.
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
            Тариф промокода — отдельно от «классика / с активации»: попадёт в{' '}
            <span className="text-gray-500">subscription_type</span> (Pro или Ultra), если не включён только режим расширений.
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
        <div className="text-[10px] text-gray-500 uppercase tracking-wide mb-1">Промокод — код, заметка, даты</div>
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
            <label
              className="text-xs text-gray-500"
              title="Один и тот же строковый код можно применить к указанному числу разных заведений (регистраций)."
            >
              Учётных записей
            </label>
            <input
              type="number"
              min="1"
              max="100000"
              value={newMaxRedemptions}
              onChange={e => setNewMaxRedemptions(e.target.value)}
              placeholder="1"
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 text-sm w-full sm:w-28"
            />
          </div>
        </div>
        <div className="text-[10px] text-gray-500 uppercase tracking-wide mt-3 mb-1">
          Подписки расширения (отдельно от промокода тарифа)
        </div>
        <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap sm:gap-3 sm:items-end rounded-lg border border-gray-800 bg-gray-950/40 p-3">
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-400">Увеличение сотрудников (пакет)</label>
            <select
              value={newEmpSlotPacks}
              onChange={e => setNewEmpSlotPacks(e.target.value)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500 text-sm w-full sm:w-28"
            >
              {EMPLOYEE_PACK_OPTIONS.map(v => (
                <option key={v} value={v}>
                  {v === 0 ? 'нет' : `+${v}`}
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-400">Доп. заведения/филиалы (пакет)</label>
            <select
              value={newBranchSlotPacks}
              onChange={e => setNewBranchSlotPacks(e.target.value)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500 text-sm w-full sm:w-28"
            >
              {BRANCH_PACK_OPTIONS.map(v => (
                <option key={v} value={v}>
                  {v === 0 ? 'нет' : `+${v}`}
                </option>
              ))}
            </select>
          </div>
          <label className="flex items-center gap-2 text-xs text-gray-400 cursor-pointer sm:mb-0 col-span-2 sm:col-auto">
            <input
              type="checkbox"
              className="accent-indigo-500 rounded"
              checked={newAdditiveOnly}
              onChange={e => setNewAdditiveOnly(e.target.checked)}
            />
            Только расширения (без смены тарифа промокодом)
          </label>
          <button
            onClick={addCode}
            disabled={saving || !newCode.trim()}
            className="col-span-2 sm:col-auto bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed px-5 py-2 rounded-lg font-medium transition text-sm"
          >
            {saving ? '...' : '+ Создать'}
          </button>
        </div>
        <div className="text-[11px] text-gray-600 mt-3 border-t border-gray-800 pt-3 leading-snug space-y-1.5">
          <div>
            <span className="text-gray-500">Промокод при погашении: </span>
            <span className="text-gray-400">
              {newAdditiveOnly
                ? 'только расширения (тариф по коду не меняется)'
                : `тариф ${subscriptionTierLabelRu(newGrantTier)}; даты и макс. сотр. — как в полях выше`}
            </span>
          </div>
          {(() => {
            const de = newEmpSlotPacks.trim() === '' ? 0 : parseInt(newEmpSlotPacks.trim(), 10)
            const db = newBranchSlotPacks.trim() === '' ? 0 : parseInt(newBranchSlotPacks.trim(), 10)
            if (
              Number.isNaN(de) ||
              Number.isNaN(db) ||
              !EMPLOYEE_PACK_OPTIONS.includes(de as typeof EMPLOYEE_PACK_OPTIONS[number]) ||
              !BRANCH_PACK_OPTIONS.includes(db as typeof BRANCH_PACK_OPTIONS[number])
            ) {
              return (
                <div className="text-amber-600/90">
                  Выберите пакеты только из фиксированного списка.
                </div>
              )
            }
            return (
              <>
                <div>
                  <span className="text-gray-500">Пакет сотрудников: </span>
                  <span className="text-gray-400">
                    {de === 0 ? 'не включен' : `+${de}`}
                  </span>
                </div>
                <div>
                  <span className="text-gray-500">Пакет заведений: </span>
                  <span className="text-gray-400">
                    {db === 0 ? 'не включен' : `+${db}`}
                  </span>
                </div>
              </>
            )
          })()}
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
                  <th
                    className="px-4 py-3 text-center text-[10px] uppercase max-w-[6rem]"
                    title="Сколько раз код уже применён / максимум разных учётных записей"
                  >
                    Активации
                  </th>
                  <th className="px-4 py-3 text-left">Кому применён</th>
                  <th
                    className="px-4 py-3 text-left"
                    title="Классика: дата «действует до». Новый тип: дни с активации и при необходимости срок ввода кода."
                  >
                    Логика / срок
                  </th>
                  <th className="px-4 py-3 text-center">Сотр.</th>
                  <th
                    className="px-4 py-3 text-center text-[10px] uppercase max-w-[5.5rem]"
                    title="Отдельная подписка расширения Lite: число активаций в коде, каждая даёт +5 к лимиту сотрудников на заведение погашения"
                  >
                    +5 сотр.
                  </th>
                  <th
                    className="px-4 py-3 text-center text-[10px] uppercase max-w-[5.5rem]"
                    title="Отдельная подписка расширения: число активаций в коде, каждая даёт +1 филиал на владельца"
                  >
                    +1 фил.
                  </th>
                  <th
                    className="px-4 py-3 text-center text-[10px] uppercase"
                    title="Только подписки расширения в коде, без выдачи тарифа Pro/Ultra"
                  >
                    Только расш.
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
                    used: { label: 'Закончился', cls: 'bg-blue-900/40 text-blue-300' },
                    partial: { label: 'Есть активации', cls: 'bg-cyan-900/40 text-cyan-200' },
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
                          <span className="text-[10px] text-gray-500">тариф</span>
                          <PromoGrantTierSelect row={row} saving={saving} onPick={patchPromoGrantTier} />
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span className={`px-2 py-0.5 rounded text-xs font-medium ${statusCfg.cls}`}>{statusCfg.label}</span>
                      </td>
                      <td className="px-4 py-3 text-center align-top">
                        <button
                          type="button"
                          title="Изменить лимит активаций"
                          onClick={() =>
                            setMaxRedemptionsRow(row.id, row.max_redemptions ?? 1)
                          }
                          className="text-xs font-mono tabular-nums hover:text-indigo-400 transition"
                        >
                          <span className="text-gray-300">{row.redemption_count ?? 0}</span>
                          <span className="text-gray-600">/</span>
                          <span className="text-gray-400">{row.max_redemptions ?? 1}</span>
                        </button>
                      </td>
                      <td className="px-4 py-3 text-gray-400 align-top">
                        <PromoRecipientsCell row={row} />
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
                                onClick={() => openPromoExpiryEdit(row)}
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
                            onClick={() => openPromoExpiryEdit(row)}
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
                        <select
                          title="Пакет сотрудников"
                          value={String(row.grants_employee_slot_packs ?? 0)}
                          onChange={e => setEmpSlotPacks(row.id, parseInt(e.target.value, 10))}
                          className="bg-gray-900 border border-gray-700 rounded px-2 py-1 text-xs text-gray-200"
                        >
                          {EMPLOYEE_PACK_OPTIONS.map(v => (
                            <option key={v} value={v}>
                              {v === 0 ? 'нет' : `+${v}`}
                            </option>
                          ))}
                        </select>
                      </td>
                      <td className="px-4 py-3 text-center align-top">
                        <select
                          title="Пакет заведений"
                          value={String(row.grants_branch_slot_packs ?? 0)}
                          onChange={e => setBranchSlotPacks(row.id, parseInt(e.target.value, 10))}
                          className="bg-gray-900 border border-gray-700 rounded px-2 py-1 text-xs text-gray-200"
                        >
                          {BRANCH_PACK_OPTIONS.map(v => (
                            <option key={v} value={v}>
                              {v === 0 ? 'нет' : `+${v}`}
                            </option>
                          ))}
                        </select>
                      </td>
                      <td className="px-4 py-3 text-center">
                        <button
                          type="button"
                          title="Только подписки расширения, без смены тарифа"
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
                used: { label: 'Закончился', cls: 'bg-blue-900/40 text-blue-300' },
                partial: { label: 'Есть активации', cls: 'bg-cyan-900/40 text-cyan-200' },
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

                  <div className="text-[11px] text-gray-500 mb-2">
                    Активации:{' '}
                    <button
                      type="button"
                      className="font-mono text-gray-300 hover:text-indigo-400"
                      onClick={() => setMaxRedemptionsRow(row.id, row.max_redemptions ?? 1)}
                    >
                      {row.redemption_count ?? 0}/{row.max_redemptions ?? 1}
                    </button>
                  </div>

                  <div className="text-gray-400 text-xs mb-2">
                    <PromoRecipientsCell row={row} />
                  </div>
                  <div className="text-[10px] text-gray-600 mb-1 space-y-1">
                    <div>{(row.activation_duration_days ?? 0) > 0 ? 'тип: с активации' : 'тип: классика'}</div>
                    <div className="flex flex-col gap-0.5">
                      <span className="text-gray-500">Тариф</span>
                      <PromoGrantTierSelect
                        row={row}
                        saving={saving}
                        onPick={patchPromoGrantTier}
                        className="bg-gray-950 border border-gray-700 rounded-lg px-2 py-2 text-xs text-gray-200 w-full max-w-[16rem]"
                      />
                    </div>
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
                    <span className="text-gray-600 block">
                      Пакет сотрудников: {((row.grants_employee_slot_packs ?? 0) > 0) ? `+${row.grants_employee_slot_packs}` : 'нет'}
                    </span>
                    <span className="text-gray-600 block">
                      Пакет заведений: {((row.grants_branch_slot_packs ?? 0) > 0) ? `+${row.grants_branch_slot_packs}` : 'нет'}
                      {row.grants_additive_only ? ' · только расширения' : ''}
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
                      onClick={() => openPromoExpiryEdit(row)}
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
                    <select
                      value={String(row.grants_employee_slot_packs ?? 0)}
                      onChange={e => setEmpSlotPacks(row.id, parseInt(e.target.value, 10))}
                      className="px-3 py-2 rounded-lg border border-gray-700 bg-gray-900 text-gray-200 text-sm"
                      title="Пакет сотрудников"
                    >
                      {EMPLOYEE_PACK_OPTIONS.map(v => (
                        <option key={v} value={v}>
                          {v === 0 ? 'Сотр.: нет' : `Сотр.: +${v}`}
                        </option>
                      ))}
                    </select>
                    <select
                      value={String(row.grants_branch_slot_packs ?? 0)}
                      onChange={e => setBranchSlotPacks(row.id, parseInt(e.target.value, 10))}
                      className="px-3 py-2 rounded-lg border border-gray-700 bg-gray-900 text-gray-200 text-sm"
                      title="Пакет заведений"
                    >
                      {BRANCH_PACK_OPTIONS.map(v => (
                        <option key={v} value={v}>
                          {v === 0 ? 'Филиалы: нет' : `Филиалы: +${v}`}
                        </option>
                      ))}
                    </select>
                    <button
                      type="button"
                      onClick={() => toggleAdditiveOnly(row)}
                      className="px-3 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-amber-200 text-sm"
                      title="Только подписки расширения"
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

// ─── AI Usage Tab ──────────────────────────────────────────────────────────────

type AiUsageResponse = {
  meta: {
    days: number
    provider: string | null
    fromIso: string
    sampleSize: number
    limit: number
  }
  summary: {
    requests: number
    successRequests: number
    failedRequests: number
    inputTokens: number
    outputTokens: number
    totalTokens: number
    estimatedCostUsd: number
  }
  byProvider: Array<{ provider: string; requests: number; totalTokens: number; estimatedCostUsd: number }>
  byContext: Array<{ context: string; requests: number; totalTokens: number; estimatedCostUsd: number }>
  byDay: Array<{ date: string; requests: number; totalTokens: number; estimatedCostUsd: number }>
  recent: Array<{
    created_at: string
    provider: string
    model: string | null
    context: string | null
    total_tokens: number | null
    estimated_cost_usd: number | null
    status: string | null
  }>
}

function AiUsageTab() {
  const [provider, setProvider] = useState('deepseek')
  const [days, setDays] = useState(30)
  const [data, setData] = useState<AiUsageResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const p = new URLSearchParams()
      p.set('days', String(days))
      if (provider.trim()) p.set('provider', provider.trim().toLowerCase())
      p.set('limit', '3000')
      const res = await fetch(`/api/ai-usage?${p.toString()}`)
      const json = (await res.json()) as AiUsageResponse & { error?: string }
      if (!res.ok) {
        setError(typeof json?.error === 'string' ? json.error : `Ошибка (${res.status})`)
        setData(null)
      } else {
        setData(json as AiUsageResponse)
      }
    } finally {
      setLoading(false)
    }
  }, [days, provider])

  useEffect(() => {
    void load()
  }, [load])

  const successRate = data?.summary.requests
    ? Math.round((data.summary.successRequests / data.summary.requests) * 1000) / 10
    : 0

  return (
    <div className="space-y-6">
      <div className="bg-gray-900 rounded-xl p-4 border border-gray-800 flex flex-wrap items-end gap-3">
        <div className="flex flex-col gap-1">
          <label className="text-xs text-gray-500">Провайдер</label>
          <select
            value={provider}
            onChange={e => setProvider(e.target.value)}
            className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm"
          >
            <option value="deepseek">deepseek</option>
            <option value="">all</option>
            <option value="openai">openai</option>
            <option value="gemini">gemini</option>
            <option value="groq">groq</option>
            <option value="claude">claude</option>
          </select>
        </div>
        <div className="flex flex-col gap-1">
          <label className="text-xs text-gray-500">Период (дней)</label>
          <select
            value={days}
            onChange={e => setDays(Number(e.target.value))}
            className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm"
          >
            <option value={7}>7</option>
            <option value={14}>14</option>
            <option value={30}>30</option>
            <option value={90}>90</option>
            <option value={180}>180</option>
          </select>
        </div>
        <button
          type="button"
          onClick={() => void load()}
          className="bg-indigo-600 hover:bg-indigo-500 px-4 py-2 rounded-lg text-sm font-medium"
          disabled={loading}
        >
          {loading ? 'Обновление…' : 'Обновить'}
        </button>
        {data?.meta ? (
          <div className="text-xs text-gray-500 ml-auto">
            Выборка: {data.meta.sampleSize} записей, с {formatDate(data.meta.fromIso)}
          </div>
        ) : null}
      </div>

      {error ? (
        <div className="p-4 bg-red-900/30 border border-red-700 rounded-lg text-red-200 text-sm">{error}</div>
      ) : null}

      <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-2 sm:gap-3">
        <StatCard label="Запросов" value={data?.summary.requests ?? '—'} />
        <StatCard label="Успешных" value={data?.summary.successRequests ?? '—'} />
        <StatCard label="Ошибок" value={data?.summary.failedRequests ?? '—'} dimmed={(data?.summary.failedRequests ?? 0) === 0} />
        <StatCard label="Токены (всего)" value={data?.summary.totalTokens?.toLocaleString('ru-RU') ?? '—'} />
        <StatCard label="Успешность" value={`${successRate}%`} />
        <StatCard label="Оценка расходов" value={formatUsd(data?.summary.estimatedCostUsd)} />
      </div>

      <div className="grid lg:grid-cols-2 gap-4">
        <section className="bg-gray-900 rounded-xl border border-gray-800 overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-800 text-sm text-gray-300">По контекстам</div>
          <div className="max-h-72 overflow-auto">
            <table className="w-full text-xs sm:text-sm">
              <thead className="bg-gray-950 text-gray-500">
                <tr>
                  <th className="text-left px-3 py-2 font-medium">Контекст</th>
                  <th className="text-right px-3 py-2 font-medium">Запросы</th>
                  <th className="text-right px-3 py-2 font-medium">Токены</th>
                  <th className="text-right px-3 py-2 font-medium">$</th>
                </tr>
              </thead>
              <tbody>
                {(data?.byContext ?? []).map(row => (
                  <tr key={row.context} className="border-t border-gray-800/70">
                    <td className="px-3 py-2 text-gray-300">{row.context}</td>
                    <td className="px-3 py-2 text-right">{row.requests.toLocaleString('ru-RU')}</td>
                    <td className="px-3 py-2 text-right">{row.totalTokens.toLocaleString('ru-RU')}</td>
                    <td className="px-3 py-2 text-right text-emerald-300">{formatUsd(row.estimatedCostUsd)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section className="bg-gray-900 rounded-xl border border-gray-800 overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-800 text-sm text-gray-300">По дням</div>
          <div className="max-h-72 overflow-auto">
            <table className="w-full text-xs sm:text-sm">
              <thead className="bg-gray-950 text-gray-500">
                <tr>
                  <th className="text-left px-3 py-2 font-medium">Дата</th>
                  <th className="text-right px-3 py-2 font-medium">Запросы</th>
                  <th className="text-right px-3 py-2 font-medium">Токены</th>
                  <th className="text-right px-3 py-2 font-medium">$</th>
                </tr>
              </thead>
              <tbody>
                {(data?.byDay ?? []).map(row => (
                  <tr key={row.date} className="border-t border-gray-800/70">
                    <td className="px-3 py-2 text-gray-300">{formatDate(row.date)}</td>
                    <td className="px-3 py-2 text-right">{row.requests.toLocaleString('ru-RU')}</td>
                    <td className="px-3 py-2 text-right">{row.totalTokens.toLocaleString('ru-RU')}</td>
                    <td className="px-3 py-2 text-right text-emerald-300">{formatUsd(row.estimatedCostUsd)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <section className="bg-gray-900 rounded-xl border border-gray-800 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-800 text-sm text-gray-300">
          Последние вызовы (до 200)
        </div>
        <div className="max-h-[420px] overflow-auto">
          <table className="w-full text-xs sm:text-sm">
            <thead className="bg-gray-950 text-gray-500 sticky top-0">
              <tr>
                <th className="text-left px-3 py-2 font-medium">Время</th>
                <th className="text-left px-3 py-2 font-medium">Provider</th>
                <th className="text-left px-3 py-2 font-medium">Model</th>
                <th className="text-left px-3 py-2 font-medium">Context</th>
                <th className="text-right px-3 py-2 font-medium">Токены</th>
                <th className="text-right px-3 py-2 font-medium">$</th>
                <th className="text-left px-3 py-2 font-medium">Статус</th>
              </tr>
            </thead>
            <tbody>
              {(data?.recent ?? []).map((row, idx) => (
                <tr key={`${row.created_at}-${idx}`} className="border-t border-gray-800/70">
                  <td className="px-3 py-2 text-gray-400 whitespace-nowrap">{new Date(row.created_at).toLocaleString('ru-RU')}</td>
                  <td className="px-3 py-2">{row.provider}</td>
                  <td className="px-3 py-2 text-gray-400">{row.model ?? '—'}</td>
                  <td className="px-3 py-2 text-gray-400">{row.context ?? '—'}</td>
                  <td className="px-3 py-2 text-right">{Number(row.total_tokens ?? 0).toLocaleString('ru-RU')}</td>
                  <td className="px-3 py-2 text-right text-emerald-300">{formatUsd(row.estimated_cost_usd ?? 0)}</td>
                  <td className={`px-3 py-2 ${String(row.status ?? 'ok').toLowerCase() === 'ok' ? 'text-emerald-300' : 'text-amber-300'}`}>
                    {row.status ?? 'ok'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}

// ─── Broadcast Tab ─────────────────────────────────────────────────────────────

function BroadcastTab() {
  const [userKind, setUserKind] = useState<'owners' | 'line' | 'all'>('all')
  const [subscriptionMode, setSubscriptionMode] = useState<
    'all' | 'with_any_subscription' | 'with_specific_subscriptions' | 'without_subscription'
  >('all')
  const [selectedSubscriptionTypes, setSelectedSubscriptionTypes] = useState<string[]>([])
  const [registeredFrom, setRegisteredFrom] = useState('')
  const [registeredTo, setRegisteredTo] = useState('')
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')
  const [count, setCount] = useState<number | null>(null)
  const [countLoading, setCountLoading] = useState(false)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [lastResult, setLastResult] = useState<string | null>(null)

  function buildFiltersQuery(): URLSearchParams {
    const p = new URLSearchParams()
    p.set('userKind', userKind)
    p.set('subscriptionMode', subscriptionMode)
    if (selectedSubscriptionTypes.length > 0) {
      p.set('subscriptionTypes', selectedSubscriptionTypes.join(','))
    }
    if (registeredFrom.trim()) p.set('registeredFrom', registeredFrom.trim())
    if (registeredTo.trim()) p.set('registeredTo', registeredTo.trim())
    return p
  }

  async function refreshCount() {
    setCountLoading(true)
    setError(null)
    setLastResult(null)
    try {
      const res = await fetch(`/api/broadcast?${buildFiltersQuery().toString()}`)
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(typeof data?.error === 'string' ? data.error : `Ошибка (${res.status})`)
        setCount(null)
        return
      }
      setCount(typeof data?.count === 'number' ? data.count : null)
    } finally {
      setCountLoading(false)
    }
  }

  async function send() {
    const subj = subject.trim()
    const text = body.trim()
    if (subj.length === 0 || text.length === 0) {
      setError('Укажите тему и текст письма')
      return
    }
    if (subscriptionMode === 'with_specific_subscriptions' && selectedSubscriptionTypes.length === 0) {
      setError('Выберите хотя бы один тип подписки')
      return
    }
    const userKindLabel =
      userKind === 'owners'
        ? 'только собственники'
        : userKind === 'line'
          ? 'только линейный персонал'
          : 'все пользователи'
    const subscriptionLabel =
      subscriptionMode === 'all'
        ? 'все'
        : subscriptionMode === 'without_subscription'
          ? 'без подписки'
          : subscriptionMode === 'with_any_subscription'
            ? 'с любой подпиской'
            : `с выбранными: ${selectedSubscriptionTypes.map((x) => subscriptionTierLabelRu(x)).join(', ')}`
    const ok = window.confirm(
      `Отправить рассылку?\n\nПользователи: ${userKindLabel}\nПодписка: ${subscriptionLabel}\nРегистрация: ${registeredFrom || 'любая'} — ${registeredTo || 'любая'}\nПолучателей (по последнему подсчёту): ${count ?? '—'}\nОт: info@restodocks.com (через Resend)`,
    )
    if (!ok) return

    setSending(true)
    setError(null)
    setLastResult(null)
    try {
      const res = await fetch('/api/broadcast', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          userKind,
          subscriptionMode,
          subscriptionTypes: selectedSubscriptionTypes,
          registeredFrom: registeredFrom.trim() || null,
          registeredTo: registeredTo.trim() || null,
          subject: subj,
          body: text,
        }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(typeof data?.error === 'string' ? data.error : `Ошибка (${res.status})`)
        return
      }
      const sent = typeof data?.sent === 'number' ? data.sent : 0
      const failed = typeof data?.failed === 'number' ? data.failed : 0
      const msg = typeof data?.message === 'string' ? data.message : null
      const errLines =
        Array.isArray(data?.errors) && data.errors.length
          ? `\nДетали: ${data.errors.map((x: unknown) => String(x)).join('; ')}`
          : ''
      setLastResult(
        (msg ??
          `Отправлено: ${sent}${failed > 0 ? `, не доставлено (ошибки API): ${failed}` : ''}. В списке было: ${data?.recipientCount ?? sent}.`) + errLines,
      )
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="space-y-4 max-w-2xl">
      {error && (
        <div className="p-3 rounded-lg border border-red-800 bg-red-950/40 text-red-200 text-sm">{error}</div>
      )}
      {lastResult && !error && (
        <div className="p-3 rounded-lg border border-emerald-800/60 bg-emerald-950/30 text-emerald-100 text-sm">
          {lastResult}
        </div>
      )}

      <div className="bg-gray-900 rounded-xl border border-gray-800 p-4 space-y-4">
        <h2 className="text-sm font-semibold text-white">Рассылка по email</h2>
        <p className="text-xs text-gray-500 leading-relaxed">
          Уходят через Resend с адреса по умолчанию{' '}
          <span className="text-gray-400">Restodocks &lt;info@restodocks.com&gt;</span> (или{' '}
          <code className="text-gray-500">RESEND_FROM_EMAIL</code> в окружении). Попадают только учётки с
          подтверждённым email в Auth и активной записью сотрудника. Очень большие списки могут упираться в
          таймаут Cloudflare Worker — при необходимости разбивайте рассылку по времени.
        </p>

        <div className="space-y-2">
          <div className="text-xs text-gray-400">Пользователи</div>
          <div className="flex flex-wrap gap-4 text-sm">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="broadcast_audience"
                checked={userKind === 'all'}
                onChange={() => {
                  setUserKind('all')
                  setCount(null)
                }}
              />
              Все пользователи
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="broadcast_audience"
                checked={userKind === 'owners'}
                onChange={() => {
                  setUserKind('owners')
                  setCount(null)
                }}
              />
              Только собственники (роль owner)
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="broadcast_audience"
                checked={userKind === 'line'}
                onChange={() => {
                  setUserKind('line')
                  setCount(null)
                }}
              />
              Только линейный персонал
            </label>
          </div>
        </div>

        <div className="space-y-2">
          <div className="text-xs text-gray-400">Подписка</div>
          <div className="flex flex-wrap gap-4 text-sm">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="broadcast_subscription_mode"
                checked={subscriptionMode === 'all'}
                onChange={() => {
                  setSubscriptionMode('all')
                  setCount(null)
                }}
              />
              Все
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="broadcast_subscription_mode"
                checked={subscriptionMode === 'with_any_subscription'}
                onChange={() => {
                  setSubscriptionMode('with_any_subscription')
                  setCount(null)
                }}
              />
              С подпиской (любая)
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="broadcast_subscription_mode"
                checked={subscriptionMode === 'without_subscription'}
                onChange={() => {
                  setSubscriptionMode('without_subscription')
                  setCount(null)
                }}
              />
              Без подписки
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="broadcast_subscription_mode"
                checked={subscriptionMode === 'with_specific_subscriptions'}
                onChange={() => {
                  setSubscriptionMode('with_specific_subscriptions')
                  setCount(null)
                }}
              />
              С конкретной подпиской
            </label>
          </div>
          {subscriptionMode === 'with_specific_subscriptions' && (
            <div className="grid sm:grid-cols-3 gap-2 text-sm">
              {SUBSCRIPTION_PAID_TIERS_DB.map((tier) => {
                const checked = selectedSubscriptionTypes.includes(tier)
                return (
                  <label key={tier} className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() => {
                        setCount(null)
                        setSelectedSubscriptionTypes((prev) =>
                          checked ? prev.filter((x) => x !== tier) : [...prev, tier],
                        )
                      }}
                    />
                    {subscriptionTierLabelRu(tier)}
                  </label>
                )
              })}
            </div>
          )}
        </div>

        <div className="space-y-2">
          <div className="text-xs text-gray-400">Диапазон регистрации (дата создания аккаунта)</div>
          <div className="grid sm:grid-cols-2 gap-2">
            <input
              type="date"
              value={registeredFrom}
              onChange={(e) => {
                setRegisteredFrom(e.target.value)
                setCount(null)
              }}
              className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm"
            />
            <input
              type="date"
              value={registeredTo}
              onChange={(e) => {
                setRegisteredTo(e.target.value)
                setCount(null)
              }}
              className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm"
            />
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => void refreshCount()}
            disabled={countLoading}
            className="bg-gray-800 border border-gray-700 hover:bg-gray-700 disabled:opacity-50 px-4 py-2 rounded-lg text-sm"
          >
            {countLoading ? 'Подсчёт…' : 'Подсчитать получателей'}
          </button>
          {count !== null && (
            <span className="text-sm text-gray-400">
              В списке: <span className="text-white font-medium">{count}</span>
            </span>
          )}
        </div>

        <div className="space-y-1">
          <label className="text-xs text-gray-400">Тема</label>
          <input
            value={subject}
            onChange={e => setSubject(e.target.value)}
            placeholder="Тема письма"
            maxLength={200}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm"
          />
        </div>

        <div className="space-y-1">
          <label className="text-xs text-gray-400">Текст (простой текст, переносы строк сохраняются)</label>
          <textarea
            value={body}
            onChange={e => setBody(e.target.value)}
            placeholder="Текст рассылки…"
            rows={12}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm font-mono leading-relaxed"
          />
        </div>

        <button
          type="button"
          onClick={() => void send()}
          disabled={sending || subject.trim().length === 0 || body.trim().length === 0}
          className="bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 px-4 py-2 rounded-lg text-sm"
        >
          {sending ? 'Отправка…' : 'Отправить рассылку'}
        </button>
      </div>
    </div>
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
