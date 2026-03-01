'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import type { PromoCode } from '@/lib/supabase'

// ─── Types ───────────────────────────────────────────────────────────────────

type Establishment = {
  id: string
  name: string
  address: string | null
  created_at: string
  default_currency: string
  employee_count: number
  owner_name: string
  owner_email: string
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatDate(iso: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

function isExpired(iso: string | null) {
  if (!iso) return false
  return new Date(iso) < new Date()
}

function isNotStarted(iso: string | null) {
  if (!iso) return false
  return new Date(iso) > new Date()
}

function isValidNow(startsAt: string | null, expiresAt: string | null) {
  if (startsAt && new Date(startsAt) > new Date()) return false
  if (expiresAt && new Date(expiresAt) < new Date()) return false
  return true
}

// ─── Main ─────────────────────────────────────────────────────────────────────

export default function AdminClient() {
  const router = useRouter()
  const [tab, setTab] = useState<'establishments' | 'promo'>('establishments')

  async function logout() {
    await fetch('/api/auth', { method: 'DELETE' })
    router.push('/login')
  }

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <header className="border-b border-gray-800 px-6 py-4 flex items-center justify-between">
        <div>
          <span className="font-bold text-lg">Restodocks</span>
          <span className="text-gray-500 ml-2 text-sm">/ Admin</span>
        </div>
        <button onClick={logout} className="text-sm text-gray-500 hover:text-white transition">
          Выйти
        </button>
      </header>

      {/* Tabs */}
      <div className="border-b border-gray-800 px-6">
        <div className="flex gap-1">
          {([
            { key: 'establishments', label: 'Заведения' },
            { key: 'promo', label: 'Промокоды' },
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

      <main className="max-w-6xl mx-auto px-4 py-8">
        {tab === 'establishments' ? <EstablishmentsTab /> : <PromoTab />}
      </main>
    </div>
  )
}

// ─── Establishments Tab ───────────────────────────────────────────────────────

function EstablishmentsTab() {
  const [data, setData] = useState<Establishment[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    const res = await fetch('/api/establishments')
    const json = await res.json()
    setData(json)
    setLoading(false)
  }, [])

  useEffect(() => { load() }, [load])

  const filtered = data.filter(e =>
    e.name.toLowerCase().includes(search.toLowerCase()) ||
    e.owner_email.toLowerCase().includes(search.toLowerCase()) ||
    e.owner_name.toLowerCase().includes(search.toLowerCase())
  )

  const total = data.length
  const totalEmployees = data.reduce((s, e) => s + e.employee_count, 0)

  return (
    <>
      {/* Stats */}
      <div className="grid grid-cols-3 gap-3 mb-8">
        <StatCard label="Заведений" value={total} />
        <StatCard label="Сотрудников" value={totalEmployees} />
        <StatCard label="Подписок" value="—" dimmed />
      </div>

      {/* Search */}
      <div className="flex gap-3 mb-4 items-center">
        <input
          type="text"
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Поиск по названию, владельцу, email..."
          className="bg-gray-900 border border-gray-800 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 flex-1"
        />
        <button onClick={load} className="text-gray-500 hover:text-white transition px-3 py-2 rounded-lg border border-gray-800 text-sm">
          ↻ Обновить
        </button>
      </div>

      {/* Table */}
      <div className="bg-gray-900 rounded-xl border border-gray-800 overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-gray-500">Загрузка...</div>
        ) : filtered.length === 0 ? (
          <div className="p-12 text-center text-gray-500">Заведений нет</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wide">
                <th className="px-4 py-3 text-left">Заведение</th>
                <th className="px-4 py-3 text-left">Владелец</th>
                <th className="px-4 py-3 text-left">Email</th>
                <th className="px-4 py-3 text-center">Сотрудников</th>
                <th className="px-4 py-3 text-left">Страна</th>
                <th className="px-4 py-3 text-left">Дата регистрации</th>
                <th className="px-4 py-3 text-left">Подписка</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((row, i) => (
                <tr
                  key={row.id}
                  className={`border-b border-gray-800/50 hover:bg-gray-800/30 transition ${i === filtered.length - 1 ? 'border-0' : ''}`}
                >
                  <td className="px-4 py-3 font-medium text-white">{row.name}</td>
                  <td className="px-4 py-3 text-gray-300">{row.owner_name}</td>
                  <td className="px-4 py-3 text-gray-400 text-xs">{row.owner_email}</td>
                  <td className="px-4 py-3 text-center">
                    <span className="bg-gray-800 px-2 py-0.5 rounded text-xs font-mono">
                      {row.employee_count}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-400 text-xs">{row.address || '—'}</td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{formatDate(row.created_at)}</td>
                  <td className="px-4 py-3">
                    <span className="px-2 py-0.5 rounded text-xs bg-gray-800 text-gray-500">
                      — (скоро)
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  )
}

// ─── Promo Tab ────────────────────────────────────────────────────────────────

function PromoTab() {
  const [codes, setCodes] = useState<PromoCode[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [newCode, setNewCode] = useState('')
  const [newNote, setNewNote] = useState('')
  const [newStartDate, setNewStartDate] = useState('')
  const [newEndDate, setNewEndDate] = useState('')
  const [newMaxEmployees, setNewMaxEmployees] = useState('')
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<'all' | 'free' | 'used' | 'expired'>('all')

  const loadCodes = useCallback(async () => {
    setLoading(true)
    const res = await fetch('/api/promo')
    const data = await res.json()
    setCodes(Array.isArray(data) ? data : [])
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

  async function setStartDate(id: number) {
    const val = prompt('Действует с (YYYY-MM-DD), пусто — без ограничения:')
    if (val === null) return
    await fetch('/api/promo', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, starts_at: val || null }),
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
    const val = prompt(`Макс. сотрудников (пусто — без ограничений):`, current?.toString() ?? '')
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
      {/* Stats */}
      <div className="grid grid-cols-4 gap-3 mb-8">
        <StatCard label="Всего" value={total} />
        <StatCard label="Свободно" value={freeCount} />
        <StatCard label="Использовано" value={usedCount} />
        <StatCard label="Истекло" value={expiredCount} />
      </div>

      {/* Add form */}
      <div className="bg-gray-900 rounded-xl p-5 border border-gray-800 mb-6">
        <h2 className="text-xs font-medium text-gray-500 mb-4 uppercase tracking-wide">Новый промокод</h2>
        <div className="flex gap-3 flex-wrap items-end">
          <input
            type="text"
            value={newCode}
            onChange={e => setNewCode(e.target.value.toUpperCase())}
            placeholder="BETA001"
            className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white font-mono placeholder-gray-600 focus:outline-none focus:border-indigo-500 w-36"
          />
          <input
            type="text"
            value={newNote}
            onChange={e => setNewNote(e.target.value)}
            placeholder="Заметка"
            className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 flex-1 min-w-48"
          />
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500">Действует с</label>
            <input
              type="date"
              value={newStartDate}
              onChange={e => setNewStartDate(e.target.value)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500">Действует до</label>
            <input
              type="date"
              value={newEndDate}
              onChange={e => setNewEndDate(e.target.value)}
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-gray-500">Макс. сотрудников</label>
            <input
              type="number"
              min="1"
              value={newMaxEmployees}
              onChange={e => setNewMaxEmployees(e.target.value)}
              placeholder="∞"
              className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 w-32"
            />
          </div>
          <button
            onClick={addCode}
            disabled={saving || !newCode.trim()}
            className="bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed px-5 py-2 rounded-lg font-medium transition"
          >
            {saving ? '...' : '+ Создать'}
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-3 mb-4 flex-wrap items-center">
        <input
          type="text"
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Поиск..."
          className="bg-gray-900 border border-gray-800 rounded-lg px-3 py-2 text-white placeholder-gray-600 focus:outline-none focus:border-indigo-500 flex-1 min-w-48"
        />
        <div className="flex gap-2">
          {(['all', 'free', 'used', 'expired'] as const).map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3 py-1.5 rounded-lg text-sm transition ${filter === f ? 'bg-indigo-600 text-white' : 'bg-gray-900 border border-gray-800 text-gray-400 hover:text-white'}`}
            >
              {{ all: 'Все', free: 'Свободные', used: 'Исп.', expired: 'Истекшие' }[f]}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="bg-gray-900 rounded-xl border border-gray-800 overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-gray-500">Загрузка...</div>
        ) : filtered.length === 0 ? (
          <div className="p-12 text-center text-gray-500">Промокодов нет</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wide">
                <th className="px-4 py-3 text-left">Код</th>
                <th className="px-4 py-3 text-left">Статус</th>
                <th className="px-4 py-3 text-left">Заметка / Заведение</th>
                <th className="px-4 py-3 text-left">Действует с</th>
                <th className="px-4 py-3 text-left">Действует до</th>
                <th className="px-4 py-3 text-center">Сотрудники</th>
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
                      <button
                        onClick={() => navigator.clipboard.writeText(row.code)}
                        title="Копировать"
                        className="font-mono font-bold text-white hover:text-indigo-400 transition"
                      >
                        {row.code}
                      </button>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-0.5 rounded text-xs font-medium ${statusCfg.cls}`}>
                        {statusCfg.label}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-gray-400">
                      {row.is_used && row.establishments?.name
                        ? <span className="text-white">{row.establishments.name}</span>
                        : row.note || '—'}
                    </td>
                    <td className="px-4 py-3 text-gray-400">
                      <button onClick={() => setStartDate(row.id)} className={`hover:text-white transition ${isNotStarted(row.starts_at) ? 'text-amber-400' : ''}`} title="Изменить дату начала">
                        {formatDate(row.starts_at)}
                      </button>
                    </td>
                    <td className="px-4 py-3 text-gray-400">
                      <button onClick={() => setEndDate(row.id)} className={`hover:text-white transition ${isExpired(row.expires_at) ? 'text-red-400' : ''}`} title="Изменить дату окончания">
                        {formatDate(row.expires_at)}
                      </button>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <button
                        onClick={() => setMaxEmployees(row.id, row.max_employees)}
                        title="Изменить лимит сотрудников"
                        className="text-xs font-mono hover:text-indigo-400 transition"
                      >
                        {row.max_employees != null
                          ? <span className="bg-indigo-900/40 text-indigo-300 px-2 py-0.5 rounded">≤ {row.max_employees}</span>
                          : <span className="text-gray-600">∞</span>}
                      </button>
                    </td>
                    <td className="px-4 py-3 text-gray-500 text-xs">{formatDate(row.created_at)}</td>
                    <td className="px-4 py-3">
                      <div className="flex gap-2 justify-end">
                        <button
                          onClick={() => toggleUsed(row)}
                          className="text-gray-500 hover:text-white transition text-xs px-2 py-1 rounded border border-gray-700 hover:border-gray-500"
                        >
                          {row.is_used ? '↩ Сбросить' : '✓ Исп.'}
                        </button>
                        <button
                          onClick={() => deleteCode(row.id)}
                          className="text-gray-500 hover:text-red-400 transition text-xs px-2 py-1 rounded border border-gray-700 hover:border-red-800"
                        >
                          ✕
                        </button>
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>
    </>
  )
}

// ─── Shared Components ────────────────────────────────────────────────────────

function StatCard({ label, value, dimmed }: { label: string; value: number | string; dimmed?: boolean }) {
  return (
    <div className="bg-gray-900 rounded-xl p-4 border border-gray-800">
      <div className={`text-2xl font-bold ${dimmed ? 'text-gray-600' : 'text-white'}`}>{value}</div>
      <div className="text-gray-500 text-sm mt-1">{label}</div>
    </div>
  )
}
