'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import type { PromoCode } from '@/lib/supabase'

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
}

function formatDate(iso: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' })
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

// ─── Main ─────────────────────────────────────────────────────────────────────

export default function AdminClient() {
  const router = useRouter()
  const [tab, setTab] = useState<'establishments' | 'promo' | 'settings'>('establishments')

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

  const [data, setData] = useState<Establishment[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
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

  const filtered = data.filter(e =>
    e.name.toLowerCase().includes(search.toLowerCase()) ||
    e.owner_email.toLowerCase().includes(search.toLowerCase()) ||
    e.owner_name.toLowerCase().includes(search.toLowerCase()) ||
    (e.registration_ip ?? '').toLowerCase().includes(search.toLowerCase()) ||
    (e.registration_country ?? '').toLowerCase().includes(search.toLowerCase()) ||
    (e.registration_city ?? '').toLowerCase().includes(search.toLowerCase())
  )

  function regInfo(row: Establishment) {
    if (!row.registration_ip) return '—'
    const parts = [row.registration_ip]
    if (row.registration_city) parts.push(row.registration_city)
    if (row.registration_country && row.registration_country !== row.registration_city) parts.push(row.registration_country)
    return parts.join(', ')
  }

  const total = data.length
  const totalEmployees = data.reduce((s, e) => s + e.employee_count, 0)

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
      const json = await res.json()
      if (!res.ok) throw new Error(json?.error || 'Ошибка удаления')
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
            Нет колонки или схема старая — открой Supabase → SQL Editor и выполни миграцию из{' '}
            <code className="text-gray-400">supabase/migrations/20260430230000_establishments_max_additional_override.sql</code>
            . Ошибка входа/401 — тогда проверь Secrets (SUPABASE_URL, SERVICE_ROLE_KEY).
          </span>
        </div>
      )}
      <div className="grid grid-cols-3 gap-2 mb-4 sm:gap-3 sm:mb-8">
        <StatCard label="Заведений" value={total} />
        <StatCard label="Сотрудников" value={totalEmployees} />
        <StatCard label="Подписок" value="—" dimmed />
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
          <div className="hidden md:block bg-gray-900 rounded-xl border border-gray-800 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wide">
                  <th className="px-4 py-3 text-left">Заведение</th>
                  <th className="px-4 py-3 text-left">Тип</th>
                  <th className="px-4 py-3 text-left">Владелец</th>
                  <th className="px-4 py-3 text-left">Email</th>
                  <th className="px-4 py-3 text-center">Сотр.</th>
                  <th className="px-4 py-3 text-center" title="Переопределение лимита доп. заведений для владельца; при нескольких — минимум">
                    Лимит доп.
                  </th>
                  <th className="px-4 py-3 text-left">Дата</th>
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
                    <td className="px-4 py-3 text-gray-500 text-xs">{formatDate(row.created_at)}</td>
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
                <div className="text-gray-500 text-xs">{row.owner_email}</div>
                <div className="text-gray-600 text-xs mt-1">{formatDate(row.created_at)}</div>
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
  const [newMaxEmployees, setNewMaxEmployees] = useState('')
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<'all' | 'free' | 'used' | 'expired'>('all')

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
      }),
    })
    setNewCode(''); setNewNote(''); setNewStartDate(''); setNewEndDate(''); setNewMaxEmployees('')
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

  async function setEndDate(id: number) {
    const val = prompt('Действует до (YYYY-MM-DD), пусто — без срока:')
    if (val === null) return
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, expires_at: val || null }),
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

  const filtered = codes.filter(c => {
    const match = c.code.includes(search.toUpperCase()) || (c.note ?? '').toLowerCase().includes(search.toLowerCase())
    if (!match) return false
    if (filter === 'free') return !c.is_used && isValidNow(c.starts_at, c.expires_at)
    if (filter === 'used') return c.is_used
    if (filter === 'expired') return !c.is_used && !isValidNow(c.starts_at, c.expires_at)
    return true
  })

  const total = codes.length
  const usedCount = codes.filter(c => c.is_used).length
  const freeCount = codes.filter(c => !c.is_used && isValidNow(c.starts_at, c.expires_at)).length
  const expiredCount = codes.filter(c => !c.is_used && !isValidNow(c.starts_at, c.expires_at)).length

  return (
    <>
      {error && (
        <div className="mb-4 p-4 bg-red-900/30 border border-red-700 rounded-lg text-red-200 text-sm">
          {error}
        </div>
      )}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-4 sm:gap-3 sm:mb-6">
        <StatCard label="Всего" value={total} />
        <StatCard label="Свободно" value={freeCount} />
        <StatCard label="Использовано" value={usedCount} />
        <StatCard label="Истекло" value={expiredCount} />
      </div>

      {/* Add form */}
      <div className="bg-gray-900 rounded-xl p-4 border border-gray-800 mb-4">
        <h2 className="text-xs font-medium text-gray-500 mb-3 uppercase tracking-wide">Новый промокод</h2>
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
            <label className="text-xs text-gray-500">Действует с</label>
            <input
              type="date"
              value={newStartDate}
              onChange={e => setNewStartDate(e.target.value)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500 text-sm"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500">Действует до</label>
            <input
              type="date"
              value={newEndDate}
              onChange={e => setNewEndDate(e.target.value)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500 text-sm"
            />
          </div>
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
          {(['all', 'free', 'used', 'expired'] as const).map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-2.5 py-1.5 rounded-lg text-xs transition ${filter === f ? 'bg-indigo-600 text-white' : 'bg-gray-900 border border-gray-800 text-gray-400 hover:text-white'}`}
            >
              {{ all: 'Все', free: 'Своб.', used: 'Исп.', expired: 'Истёк' }[f]}
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
                  <th className="px-4 py-3 text-left">До</th>
                  <th className="px-4 py-3 text-center">Сотр.</th>
                  <th className="px-4 py-3 text-left">Создан</th>
                  <th className="px-4 py-3 text-right">Действия</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((row, i) => {
                  const status = row.is_used ? 'used' : !isValidNow(row.starts_at, row.expires_at) ? 'expired' : 'free'
                  const statusCfg = {
                    used: { label: 'Использован', cls: 'bg-blue-900/40 text-blue-300' },
                    expired: { label: 'Истёк', cls: 'bg-red-900/40 text-red-300' },
                    free: { label: 'Свободен', cls: 'bg-emerald-900/40 text-emerald-300' },
                  }[status]
                  return (
                    <tr key={row.id} className={`border-b border-gray-800/50 hover:bg-gray-800/30 transition ${i === filtered.length - 1 ? 'border-0' : ''}`}>
                      <td className="px-4 py-3">
                        <button onClick={() => navigator.clipboard.writeText(row.code)} className="font-mono font-bold text-white hover:text-indigo-400 transition">
                          {row.code}
                        </button>
                      </td>
                      <td className="px-4 py-3">
                        <span className={`px-2 py-0.5 rounded text-xs font-medium ${statusCfg.cls}`}>{statusCfg.label}</span>
                      </td>
                      <td className="px-4 py-3 text-gray-400">
                        {row.is_used && row.establishments?.name ? <span className="text-white">{row.establishments.name}</span> : row.note || '—'}
                      </td>
                      <td className="px-4 py-3 text-gray-400">
                        <button onClick={() => setEndDate(row.id)} className={`hover:text-white transition text-xs ${isExpired(row.expires_at) ? 'text-red-400' : ''}`}>
                          {formatDate(row.expires_at)}
                        </button>
                      </td>
                      <td className="px-4 py-3 text-center">
                        <button onClick={() => setMaxEmployees(row.id, row.max_employees)} className="text-xs font-mono hover:text-indigo-400 transition">
                          {row.max_employees != null
                            ? <span className="bg-indigo-900/40 text-indigo-300 px-2 py-0.5 rounded">≤{row.max_employees}</span>
                            : <span className="text-gray-600">∞</span>}
                        </button>
                      </td>
                      <td className="px-4 py-3 text-gray-500 text-xs">{formatDate(row.created_at)}</td>
                      <td className="px-4 py-3">
                        <div className="flex gap-2 justify-end">
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
              const status = row.is_used ? 'used' : !isValidNow(row.starts_at, row.expires_at) ? 'expired' : 'free'
              const statusCfg = {
                used: { label: 'Использован', cls: 'bg-blue-900/40 text-blue-300' },
                expired: { label: 'Истёк', cls: 'bg-red-900/40 text-red-300' },
                free: { label: 'Свободен', cls: 'bg-emerald-900/40 text-emerald-300' },
              }[status]
              return (
                <div key={row.id} className="bg-gray-900 rounded-xl border border-gray-800 p-4">
                  <div className="flex items-start justify-between gap-2 mb-2">
                    <button
                      onClick={() => navigator.clipboard.writeText(row.code)}
                      className="font-mono font-bold text-white text-base active:text-indigo-400"
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

                  <div className="flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-gray-500 mb-3">
                    {row.expires_at && (
                      <span className={isExpired(row.expires_at) ? 'text-red-400' : ''}>
                        до {formatDate(row.expires_at)}
                      </span>
                    )}
                    {row.max_employees != null && (
                      <span className="text-indigo-300">≤{row.max_employees} сотр.</span>
                    )}
                    <span>создан {formatDate(row.created_at)}</span>
                  </div>

                  <div className="flex gap-2">
                    <button
                      onClick={() => toggleUsed(row)}
                      className="flex-1 text-center text-gray-400 hover:text-white active:text-white transition text-sm py-2 rounded-lg border border-gray-700 active:border-gray-500"
                    >
                      {row.is_used ? '↩ Сбросить' : '✓ Отметить исп.'}
                    </button>
                    <button
                      onClick={() => setEndDate(row.id)}
                      className="px-3 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-white active:text-white text-sm"
                    >
                      📅
                    </button>
                    <button
                      onClick={() => setMaxEmployees(row.id, row.max_employees)}
                      className="px-3 py-2 rounded-lg border border-gray-700 text-gray-400 hover:text-white active:text-white text-sm"
                    >
                      👥
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
