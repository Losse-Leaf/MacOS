import type { EntryCategory, LifeEntry, Transaction } from '../types/api'

export interface ParsedBeijingDate {
  valid: boolean
  year: string
  month: string
  day: string
  time: string
  dateKey: string
  dotDate: string
  dotDateTime: string
  timestamp: number
}

const LEGACY_PLACEHOLDER_TITLES = new Set(['无题随笔', '无题'])
const LEGACY_PLACEHOLDER_PREFIXES = ['现场快门 · ', '现场记录 · ']

export const GALLERY_CATEGORIES: {
  id: EntryCategory
  label: string
  colorVar: string
}[] = [
  { id: 'photography', label: '摄影', colorVar: 'var(--tag-photography)' },
  { id: 'travel', label: '旅途', colorVar: 'var(--tag-travel)' },
  { id: 'still_life', label: '静物', colorVar: 'var(--tag-still-life)' },
  { id: 'motion', label: '影像', colorVar: 'var(--tag-motion)' },
]

export const ALL_ENTRY_CATEGORIES: {
  id: EntryCategory
  label: string
  colorVar: string
}[] = [
  { id: 'daily', label: '日常', colorVar: 'var(--accent-moss)' },
  ...GALLERY_CATEGORIES,
]

export function normalizeCategory(raw?: string | null): EntryCategory {
  const val = (raw ?? '').trim().toLowerCase()
  if (val === 'photography' || val === 'travel' || val === 'still_life' || val === 'motion') {
    return val
  }
  return 'daily'
}

export function categoryMeta(cat?: string | null): { id: EntryCategory; label: string; colorVar: string } {
  const norm = normalizeCategory(cat)
  return ALL_ENTRY_CATEGORIES.find((c) => c.id === norm) ?? ALL_ENTRY_CATEGORIES[0]
}

export function entryAccentVar(entry: LifeEntry): string {
  if (entry.type === 'wish') return 'var(--spectrum-leisure)'
  if (entry.type === 'transaction') return 'var(--spectrum-dining)'
  return categoryMeta(entry.category).colorVar
}

export function entryBadgeLabel(entry: LifeEntry): string {
  if (entry.type === 'wish') return '心愿达成'
  if (entry.type === 'transaction') return '账目流水'
  const meta = categoryMeta(entry.category)
  return meta.id === 'daily' ? '日常随笔' : meta.label
}

export function hasDistinctTitle(entry: Pick<LifeEntry, 'title' | 'content'>): boolean {
  const t = (entry.title ?? '').trim()
  if (!t) return false
  if (LEGACY_PLACEHOLDER_TITLES.has(t)) return false
  if (LEGACY_PLACEHOLDER_PREFIXES.some((p) => t.startsWith(p))) return false
  const firstLine =
    (entry.content ?? '')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .find((l) => l.length > 0) ?? ''
  if (firstLine && (t === firstLine || firstLine.startsWith(t))) return false
  return true
}

export function deriveDisplayTitle(entry: Pick<LifeEntry, 'title' | 'content' | 'attachments'>): string {
  const t = (entry.title ?? '').trim()
  if (t) return t
  const firstLine =
    (entry.content ?? '')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .find((l) => l.length > 0) ?? ''
  if (firstLine) return firstLine
  return entry.attachments.length > 0 ? '相纸留影' : '无题散页'
}

export function deriveExcerpt(entry: Pick<LifeEntry, 'title' | 'content'>): string {
  const trimmed = (entry.content ?? '').trim()
  if (!trimmed) return ''
  if (hasDistinctTitle(entry)) return trimmed
  const lines = trimmed
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
  return lines.slice(1).join(' ').trim()
}

export function parseYuanToCents(raw: string): number | null {
  const cleaned = raw.replace(/[¥,\s]/g, '').trim()
  if (!cleaned || !/^-?\d+(\.\d+)?$/.test(cleaned)) return null
  const num = Number(cleaned)
  if (!Number.isFinite(num)) return null
  return Math.round(num * 100)
}

export function formatYuan(cents: number, includeSymbol = true): string {
  const absYuan = (Math.abs(cents) / 100).toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  const sign = cents < 0 ? '-' : ''
  return includeSymbol ? `${sign}¥ ${absYuan}` : `${sign}${absYuan}`
}

export function parseQuickLedgerInput(raw: string): {
  amountCents: number | null
  title: string
  type: 'expense' | 'income'
} {
  const trimmed = raw.trim()
  if (!trimmed) return { amountCents: null, title: '', type: 'expense' }

  let working = trimmed
  let type: 'expense' | 'income' = 'expense'
  if (working.startsWith('+')) {
    type = 'income'
    working = working.slice(1).trim()
  } else if (working.startsWith('-')) {
    type = 'expense'
    working = working.slice(1).trim()
  }

  const leadingMatch = working.match(/^(\d+(?:\.\d{1,2})?)\s*(.*)$/)
  if (leadingMatch) {
    const cents = parseYuanToCents(leadingMatch[1])
    return { amountCents: cents, title: leadingMatch[2].trim(), type }
  }

  const trailingMatch = working.match(/^(.*?)\s+(\d+(?:\.\d{1,2})?)$/)
  if (trailingMatch) {
    const cents = parseYuanToCents(trailingMatch[2])
    return { amountCents: cents, title: trailingMatch[1].trim(), type }
  }

  return { amountCents: null, title: trimmed, type }
}

const beijingPartsFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Shanghai',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  weekday: 'short',
  hourCycle: 'h23',
})

const MONTH_ABBR = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']
const WEEKDAY_CN: Record<string, string> = {
  Sun: '周日',
  Mon: '周一',
  Tue: '周二',
  Wed: '周三',
  Thu: '周四',
  Fri: '周五',
  Sat: '周六',
  '周日': '周日',
  '周一': '周一',
  '周二': '周二',
  '周三': '周三',
  '周四': '周四',
  '周五': '周五',
  '周六': '周六',
}

export function beijingDateParts(date: Date = new Date()): {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
  yearStr: string
  monthStr: string
  dayStr: string
  weekday: string
} {
  const parts = beijingPartsFormatter.formatToParts(date)
  const map: Record<string, string> = {}
  for (const p of parts) {
    map[p.type] = p.value
  }
  const yearStr = map.year ?? '1970'
  const monthStr = map.month ?? '01'
  const dayStr = map.day ?? '01'
  const rawWd = map.weekday ?? ''
  return {
    year: Number(yearStr),
    month: Number(monthStr),
    day: Number(dayStr),
    hour: Number(map.hour ?? '0'),
    minute: Number(map.minute ?? '0'),
    second: Number(map.second ?? '0'),
    yearStr,
    monthStr,
    dayStr,
    weekday: WEEKDAY_CN[rawWd] ?? rawWd,
  }
}

export function formatBeijingISO(date: Date = new Date()): string {
  const p = beijingDateParts(date)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${p.yearStr}-${p.monthStr}-${p.dayStr}T${pad(p.hour)}:${pad(p.minute)}:${pad(p.second)}+08:00`
}

export function toDatetimeLocalValue(isoOrText?: string | null): string {
  const parsed = isoOrText ? new Date(isoOrText) : new Date()
  const valid = Number.isNaN(parsed.getTime()) ? new Date() : parsed
  const p = beijingDateParts(valid)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${p.yearStr}-${p.monthStr}-${p.dayStr}T${pad(p.hour)}:${pad(p.minute)}`
}

export function datetimeLocalToBeijingISO(localVal: string): string {
  const trimmed = localVal.trim()
  if (!trimmed) return formatBeijingISO()
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(trimmed)) {
    return `${trimmed}:00+08:00`
  }
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(trimmed)) {
    return `${trimmed}+08:00`
  }
  const d = new Date(trimmed)
  return Number.isNaN(d.getTime()) ? formatBeijingISO() : formatBeijingISO(d)
}

export function parseOccurredDate(raw?: string | null): ParsedBeijingDate {
  const text = (raw ?? '').trim()
  if (!text) {
    return {
      valid: false,
      year: '',
      month: '',
      day: '',
      time: '',
      dateKey: '',
      dotDate: '',
      dotDateTime: '',
      timestamp: 0,
    }
  }
  const normalized = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(text)
    ? text.replace(' ', 'T') + (text.includes('+') || text.endsWith('Z') ? '' : '+08:00')
    : /^\d{4}-\d{2}-\d{2}$/.test(text)
      ? `${text}T00:00:00+08:00`
      : text
  const d = new Date(normalized)
  if (Number.isNaN(d.getTime())) {
    return {
      valid: false,
      year: '',
      month: '',
      day: '',
      time: '',
      dateKey: '',
      dotDate: text,
      dotDateTime: text,
      timestamp: 0,
    }
  }
  const p = beijingDateParts(d)
  const pad = (n: number) => String(n).padStart(2, '0')
  const time = `${pad(p.hour)}:${pad(p.minute)}`
  const dateKey = `${p.yearStr}-${p.monthStr}-${p.dayStr}`
  const dotDate = `${p.yearStr}.${p.monthStr}.${p.dayStr}`
  return {
    valid: true,
    year: p.yearStr,
    month: p.monthStr,
    day: p.dayStr,
    time,
    dateKey,
    dotDate,
    dotDateTime: `${dotDate} ${time}`,
    timestamp: d.getTime(),
  }
}

export function formatEditorialDateBadge(occurredAt?: string | null): {
  day: string
  monthShort: string
  year: string
  weekday: string
} {
  const parsed = parseOccurredDate(occurredAt)
  if (!parsed.valid) {
    return { day: '--', monthShort: '---', year: '----', weekday: '' }
  }
  const d = new Date(parsed.timestamp)
  const p = beijingDateParts(d)
  const monthIdx = Math.max(0, Math.min(11, p.month - 1))
  return {
    day: p.dayStr,
    monthShort: MONTH_ABBR[monthIdx] ?? '---',
    year: p.yearStr,
    weekday: p.weekday,
  }
}

export function compactListDate(occurredAt?: string | null, now: Date = new Date()): string {
  const parsed = parseOccurredDate(occurredAt)
  if (!parsed.valid) return ''
  const curYear = beijingDateParts(now).yearStr
  const m = Number(parsed.month)
  const d = Number(parsed.day)
  if (parsed.year === curYear) {
    return `${m}月${d}日`
  }
  return `${parsed.year}/${m}/${d}`
}

export interface EntryMonthGroup {
  id: string
  title: string
  entries: LifeEntry[]
}

export function groupEntriesByMonth(list: LifeEntry[]): EntryMonthGroup[] {
  const order: string[] = []
  const titles = new Map<string, string>()
  const buckets = new Map<string, LifeEntry[]>()

  for (const entry of list) {
    const parsed = parseOccurredDate(entry.occurred_at)
    let key = 'unknown'
    let title = '未定日期'
    if (parsed.valid && parsed.year) {
      key = `${parsed.year}-${parsed.month}`
      title = `${parsed.year}年${Number(parsed.month)}月`
    }
    if (!buckets.has(key)) {
      order.push(key)
      titles.set(key, title)
      buckets.set(key, [])
    }
    buckets.get(key)!.push(entry)
  }

  return order.map((key) => ({
    id: key,
    title: titles.get(key) ?? key,
    entries: buckets.get(key) ?? [],
  }))
}

export interface TransactionDayGroup {
  id: string
  title: string
  expenseTotal: number
  incomeTotal: number
  transactions: Transaction[]
}

export function groupTransactionsByDay(
  list: Transaction[],
  now: Date = new Date(),
): TransactionDayGroup[] {
  const curYear = beijingDateParts(now).yearStr
  const order: string[] = []
  const meta = new Map<string, { title: string; expense: number; income: number; items: Transaction[] }>()

  for (const tx of list) {
    const parsed = parseOccurredDate(tx.occurred_at)
    const key = parsed.valid ? parsed.dateKey : 'unknown'
    if (!meta.has(key)) {
      order.push(key)
      let title = '未定日期'
      if (parsed.valid) {
        const badge = formatEditorialDateBadge(tx.occurred_at)
        const datePart =
          parsed.year === curYear
            ? `${Number(parsed.month)}月${Number(parsed.day)}日`
            : `${parsed.year}年${Number(parsed.month)}月${Number(parsed.day)}日`
        title = badge.weekday ? `${datePart} · ${badge.weekday}` : datePart
      }
      meta.set(key, { title, expense: 0, income: 0, items: [] })
    }
    const bucket = meta.get(key)!
    bucket.items.push(tx)
    if (tx.type === 'income') {
      bucket.income += tx.amount
    } else {
      bucket.expense += tx.amount
    }
  }

  return order.map((key) => {
    const b = meta.get(key)!
    return {
      id: key,
      title: b.title,
      expenseTotal: b.expense,
      incomeTotal: b.income,
      transactions: b.items,
    }
  })
}

export function categoryColorVar(category: string): string {
  switch (category) {
    case '餐饮':
      return 'var(--spectrum-dining)'
    case '交通':
      return 'var(--spectrum-transit)'
    case '购物':
    case '数码器材':
      return 'var(--spectrum-shopping)'
    case '娱乐':
      return 'var(--spectrum-leisure)'
    case '住房':
      return 'var(--spectrum-housing)'
    case '学习':
      return 'var(--spectrum-study)'
    case '医疗':
      return 'var(--spectrum-medical)'
    default:
      return 'var(--spectrum-other)'
  }
}

let cachedSupportsDisplayTransition: boolean | undefined

function canTransitionDisplay(): boolean {
  if (cachedSupportsDisplayTransition !== undefined) return cachedSupportsDisplayTransition
  if (
    typeof window === 'undefined' ||
    !window.CSS?.supports?.('transition-behavior', 'allow-discrete') ||
    !document.body
  ) {
    cachedSupportsDisplayTransition = false
    return false
  }
  const probe = document.createElement('div')
  probe.style.cssText = 'transition: display 1s allow-discrete !important; display: block;'
  document.body.appendChild(probe)
  getComputedStyle(probe).display
  probe.style.display = 'none'
  cachedSupportsDisplayTransition = getComputedStyle(probe).display === 'block'
  probe.remove()
  return cachedSupportsDisplayTransition
}

function supportsTopLayerExit(): boolean {
  if (typeof window === 'undefined') return false
  return Boolean(window.CSS?.supports?.('overlay', 'auto')) && canTransitionDisplay()
}

/**
 * Animated top-layer dialog close with Safari/WebKit fallback (per `animate-to-from-top-layer`).
 */
export async function closeDialogAnimated(dialog: HTMLDialogElement): Promise<void> {
  if (!dialog.open) return
  if (!supportsTopLayerExit() && typeof dialog.getAnimations === 'function') {
    dialog.setAttribute('data-closing', '')
    const animations = dialog.getAnimations({ subtree: true })
    if (animations.length > 0) {
      await Promise.race([
        Promise.allSettled(animations.map((a) => a.finished)),
        new Promise<void>((r) => setTimeout(r, 350)),
      ])
    }
    if (!dialog.hasAttribute('data-closing')) return
    dialog.removeAttribute('data-closing')
  }
  if (dialog.open) {
    dialog.close()
  }
}

/**
 * Light-dismiss fallback for WebKit/Safari where <dialog closedby="any"> is not supported.
 */
export function attachDialogLightDismiss(
  dialog: HTMLDialogElement,
  onDismiss: () => void,
): () => void {
  if ('closedBy' in HTMLDialogElement.prototype) {
    return () => {}
  }
  let pressedOutside = false
  const isOutside = (e: PointerEvent) => {
    const r = dialog.getBoundingClientRect()
    return e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom
  }
  const onPointerDown = (e: PointerEvent) => {
    pressedOutside = isOutside(e)
  }
  const onPointerUp = (e: PointerEvent) => {
    if (pressedOutside && isOutside(e)) {
      onDismiss()
    }
    pressedOutside = false
  }
  dialog.addEventListener('pointerdown', onPointerDown)
  dialog.addEventListener('pointerup', onPointerUp)
  return () => {
    dialog.removeEventListener('pointerdown', onPointerDown)
    dialog.removeEventListener('pointerup', onPointerUp)
  }
}
