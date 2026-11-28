import { computed, reactive } from 'vue'
import { api, ApiError, normalizeHubUrl, parsePairLink, resolveMediaUrl } from '../services/api'
import {
  clearCredentials,
  DEFAULT_HUB_URL,
  getDeviceHostname,
  loadCredentials,
  saveCredentials,
  type StoredCredentials,
} from '../services/credentials'
import type {
  Attachment,
  CreditChannel,
  CuratorProfile,
  EntryCategory,
  GlobalSearchResponse,
  GlobalStats,
  InstallmentPlanSummary,
  LifeEntry,
  SiteConfig,
  ThemeMode,
  Transaction,
  TransactionSummary,
  TrustedDevice,
  Wish,
} from '../types/api'
import { beijingDateParts, normalizeCategory } from '../utils/format'

export type AppSpace = 'journal' | 'gallery' | 'ledger' | 'wishlist' | 'settings'
export type JournalFilter = 'all' | 'daily' | 'private' | 'on_this_day'
export type GalleryFilter = 'all' | EntryCategory
export type LedgerTab = 'transactions' | 'installments'
export type LedgerDisplayMode = 'grouped' | 'table'

const THEME_STORAGE_KEY = 'looseleaf_desktop_theme_v1'
const DEFAULT_EXPENSE_CATS = ['餐饮', '交通', '购物', '数码器材', '娱乐', '学习', '住房', '医疗', '旅行度假', '其他']
const DEFAULT_INCOME_CATS = ['工资收入', '二手回血', '稿酬设计', '投资理财', '礼金红包', '退款报销', '其他收入']
const DEFAULT_PAYMENTS = ['微信支付', '支付宝', '银行卡', '现金', '其他']

export interface ConfirmDialogRequest {
  title: string
  message: string
  confirmText: string
  cancelText?: string
  danger?: boolean
  onConfirm: () => Promise<void> | void
}

const initialYm = beijingDateParts()

export const appStore = reactive({
  booting: true,
  isPaired: false,
  isConfirmingCode: false,
  isLoading: false,
  hubUrl: DEFAULT_HUB_URL,
  deviceToken: '',
  deviceId: '',
  deviceName: '',
  accountSub: '',
  accountName: '',
  accountEmail: '',

  themeMode: 'system' as ThemeMode,
  activeSpace: 'journal' as AppSpace,
  sidebarCollapsed: false,
  journalFilter: 'all' as JournalFilter,
  galleryCategory: 'all' as GalleryFilter,
  ledgerTab: 'transactions' as LedgerTab,
  ledgerDisplayMode: 'grouped' as LedgerDisplayMode,

  selectedEntryId: null as number | null,
  hydratedRemoteEntry: null as LifeEntry | null,
  searchQuery: '',
  remoteSearchResult: null as GlobalSearchResponse | null,
  isSearchingRemote: false,
  editEntryToken: 0,

  entries: [] as LifeEntry[],
  onThisDayEntries: [] as LifeEntry[],
  transactions: [] as Transaction[],
  selectedLedgerYear: initialYm.year,
  selectedLedgerMonth: initialYm.month,
  transactionSummary: {
    year: initialYm.year,
    month: initialYm.month,
    total_expense: 0,
    total_income: 0,
    balance: 0,
    category_breakdown: {},
    count: 0,
  } as TransactionSummary,
  creditChannels: [] as CreditChannel[],
  installmentPlans: [] as InstallmentPlanSummary[],
  wishes: [] as Wish[],
  expenseCategories: [...DEFAULT_EXPENSE_CATS],
  incomeCategories: [...DEFAULT_INCOME_CATS],
  paymentMethods: [...DEFAULT_PAYMENTS],

  siteConfig: {
    site_name: '散页 · Loose-Leaf',
    site_subtitle: '',
    site_desc: '',
    curator_name: '',
    default_location: '',
    initialized: false,
  } as SiteConfig,
  profile: {
    name: '',
    title: '',
    bio: '',
    location: '',
    current_city: '',
    avatar_url: '',
    motto: '',
    manifesto: '',
  } as CuratorProfile,
  stats: {
    total_entries: 0,
    total_photos: 0,
    month_expense: 0,
    current_year: initialYm.year,
    current_month: initialYm.month,
  } as GlobalStats,
  trustedDevices: [] as TrustedDevice[],

  errorBanner: '' as string,
  toast: null as { message: string; isError: boolean } | null,

  showNewEntryModal: false,
  showGlobalSearch: false,
  lightboxState: null as { attachments: Attachment[]; index: number } | null,
  confirmRequest: null as ConfirmDialogRequest | null,
  transactionModal: { open: false, editing: null as Transaction | null },
  wishModal: { open: false, editing: null as Wish | null },
  resolveWishTarget: null as Wish | null,
})

let toastTimer: ReturnType<typeof setTimeout> | null = null
let pendingRefresh = false
let pendingRefreshSilent = true
let lastSyncedAt = 0
const redeemedCodes = new Set<string>()

export function showToast(message: string, isError = false) {
  appStore.toast = { message, isError }
  if (toastTimer) clearTimeout(toastTimer)
  toastTimer = setTimeout(() => {
    if (appStore.toast?.message === message) {
      appStore.toast = null
    }
  }, 3200)
}

export function setThemeMode(mode: ThemeMode) {
  appStore.themeMode = mode
  localStorage.setItem(THEME_STORAGE_KEY, mode)
  applyDocumentTheme(mode)
}

export function applyDocumentTheme(mode: ThemeMode) {
  if (typeof document === 'undefined') return
  const root = document.documentElement
  if (mode === 'system') {
    root.removeAttribute('data-theme')
  } else {
    root.setAttribute('data-theme', mode)
  }
}

export function toggleSidebar() {
  appStore.sidebarCollapsed = !appStore.sidebarCollapsed
}

export const displayedStreamEntries = computed<LifeEntry[]>(() => {
  const filter = appStore.journalFilter
  const q = appStore.searchQuery.trim().toLowerCase()
  const base = filter === 'on_this_day' ? appStore.onThisDayEntries : appStore.entries

  return base.filter((entry) => {
    if (filter === 'daily') {
      if (entry.type !== 'life' || normalizeCategory(entry.category) !== 'daily') return false
    } else if (filter === 'private') {
      if (!entry.is_private) return false
    }

    if (!q) return true
    const haystack = `${entry.title}\n${entry.content}\n${entry.location ?? ''}`.toLowerCase()
    return haystack.includes(q)
  })
})

export const galleryEntries = computed<LifeEntry[]>(() => {
  const cat = appStore.galleryCategory
  const q = appStore.searchQuery.trim().toLowerCase()
  return appStore.entries.filter((entry) => {
    const normCat = normalizeCategory(entry.category)
    const hasPhotos = entry.attachments.length > 0
    if (cat === 'all') {
      if (!hasPhotos && normCat === 'daily') return false
    } else {
      if (entry.type !== 'life' || normCat !== cat) return false
    }
    if (!q) return true
    const haystack = `${entry.title}\n${entry.content}\n${entry.location ?? ''}`.toLowerCase()
    return haystack.includes(q)
  })
})

export const remoteOnlySearchEntries = computed<LifeEntry[]>(() => {
  const q = appStore.searchQuery.trim()
  if (!q || !appStore.remoteSearchResult?.entries?.length) return []
  const localIds = new Set(displayedStreamEntries.value.map((e) => e.id))
  return appStore.remoteSearchResult.entries.filter((e) => !localIds.has(e.id))
})

export const activeStreamEntry = computed<LifeEntry | null>(() => {
  const id = appStore.selectedEntryId
  if (!id) return null
  if (appStore.hydratedRemoteEntry?.id === id) {
    return appStore.hydratedRemoteEntry
  }
  return (
    appStore.entries.find((e) => e.id === id) ??
    appStore.onThisDayEntries.find((e) => e.id === id) ??
    appStore.remoteSearchResult?.entries.find((e) => e.id === id) ??
    null
  )
})

export const dailyEntriesCount = computed(
  () => appStore.entries.filter((e) => e.type === 'life' && normalizeCategory(e.category) === 'daily').length,
)

export const privateEntriesCount = computed(() => appStore.entries.filter((e) => e.is_private).length)

export const totalGalleryCount = computed(
  () =>
    appStore.entries.filter((e) => e.attachments.length > 0 || normalizeCategory(e.category) !== 'daily')
      .length,
)

export const wantingWishesCount = computed(
  () =>
    appStore.wishes.filter((w) => {
      const s = (w.status || '').toLowerCase()
      return !s || s === 'wanting' || s === 'pending' || s === 'shelved'
    }).length,
)

export const activeInstallmentsCount = computed(
  () => appStore.installmentPlans.filter((p) => p.status === 'active').length,
)

export function categoryEntriesCount(cat: EntryCategory): number {
  return appStore.entries.filter((e) => e.type === 'life' && normalizeCategory(e.category) === cat).length
}

export function mediaUrl(raw?: string | null): string {
  return resolveMediaUrl(raw, appStore.hubUrl)
}

export function selectSpace(
  space: AppSpace,
  options?: { journalFilter?: JournalFilter; galleryCategory?: GalleryFilter; ledgerTab?: LedgerTab },
) {
  if (space !== appStore.activeSpace) {
    appStore.searchQuery = ''
    appStore.remoteSearchResult = null
  }
  appStore.activeSpace = space
  if (options?.journalFilter) {
    appStore.journalFilter = options.journalFilter
  }
  if (options?.galleryCategory) {
    appStore.galleryCategory = options.galleryCategory
  }
  if (options?.ledgerTab) {
    appStore.ledgerTab = options.ledgerTab
  }
  if (space === 'journal') {
    ensureJournalSelection()
  }
}

export function ensureJournalSelection() {
  const list = displayedStreamEntries.value
  if (!appStore.selectedEntryId || !list.some((e) => e.id === appStore.selectedEntryId)) {
    appStore.selectedEntryId = list[0]?.id ?? null
  }
}

export async function selectEntry(id: number, switchToJournal = false) {
  if (switchToJournal) {
    appStore.activeSpace = 'journal'
    appStore.journalFilter = 'all'
  }
  appStore.selectedEntryId = id
  appStore.hydratedRemoteEntry = null
  if (!appStore.entries.some((e) => e.id === id)) {
    try {
      const full = await api.fetchEntry(id)
      if (appStore.selectedEntryId === id) {
        appStore.hydratedRemoteEntry = full
      }
    } catch {
      // ignore hydration failure for remote hit
    }
  }
}

export async function setHubUrl(nextUrl: string) {
  const cleaned = normalizeHubUrl(nextUrl)
  const changed = cleaned !== appStore.hubUrl
  appStore.hubUrl = cleaned
  api.setConfig(cleaned, appStore.deviceToken, handleUnauthorized)
  await saveCredentials({
    device_token: appStore.deviceToken || undefined,
    device_id: appStore.deviceId || undefined,
    device_name: appStore.deviceName || undefined,
    account_sub: appStore.accountSub || undefined,
    account_name: appStore.accountName || undefined,
    account_email: appStore.accountEmail || undefined,
    hub_url: cleaned,
  })
  if (changed && appStore.isPaired) {
    await logoutLocalOnly('切换同步服务器已重置当前会话，请重新登录')
  }
}

function handleUnauthorized() {
  if (!appStore.isPaired) return
  void logoutLocalOnly('登录凭据已失效或在其他设备被吊销，请重新登录')
}

async function logoutLocalOnly(banner?: string) {
  appStore.deviceToken = ''
  appStore.deviceId = ''
  appStore.accountSub = ''
  appStore.accountName = ''
  appStore.accountEmail = ''
  appStore.isPaired = false
  appStore.entries = []
  appStore.transactions = []
  appStore.wishes = []
  appStore.installmentPlans = []
  appStore.trustedDevices = []
  appStore.selectedEntryId = null
  appStore.errorBanner = banner ?? ''
  api.setConfig(appStore.hubUrl, '', handleUnauthorized)
  await clearCredentials()
}

export async function logout() {
  try {
    await api.logout()
  } catch (err) {
    if (!(err instanceof ApiError && err.status >= 400 && err.status < 500)) {
      // allow local logout
    }
  }
  await logoutLocalOnly()
  showToast('已退出登录并清除本机凭据')
}

export async function bootstrapApp() {
  const savedTheme = localStorage.getItem(THEME_STORAGE_KEY) as ThemeMode | null
  if (savedTheme === 'light' || savedTheme === 'dark' || savedTheme === 'system') {
    appStore.themeMode = savedTheme
  }
  applyDocumentTheme(appStore.themeMode)

  const creds = await loadCredentials()
  appStore.hubUrl = normalizeHubUrl(creds.hub_url || DEFAULT_HUB_URL)
  appStore.deviceToken = creds.device_token?.trim() ?? ''
  appStore.deviceId = creds.device_id ?? ''
  appStore.deviceName = creds.device_name ?? ''
  appStore.accountSub = creds.account_sub ?? ''
  appStore.accountName = creds.account_name ?? ''
  appStore.accountEmail = creds.account_email ?? ''

  api.setConfig(appStore.hubUrl, appStore.deviceToken, handleUnauthorized)

  if (appStore.deviceToken) {
    appStore.isPaired = true
  }

  await setupDeepLinkBridge()
  appStore.booting = false

  if (appStore.isPaired) {
    await Promise.all([refreshSessionSilent(), refreshAll()])
  }
}

async function setupDeepLinkBridge() {
  if (typeof window === 'undefined' || !('__TAURI_INTERNALS__' in window)) return
  try {
    const { listen } = await import('@tauri-apps/api/event')
    const { invoke } = await import('@tauri-apps/api/core')
    await listen<string[]>('deep-link-url', (event) => {
      for (const raw of event.payload ?? []) {
        void handleIncomingDeepLink(raw)
      }
    })
    const pending = await invoke<string[]>('get_pending_deep_links')
    for (const raw of pending) {
      void handleIncomingDeepLink(raw)
    }
  } catch {
    // browser preview
  }
}

export async function handleIncomingDeepLink(rawUrl: string) {
  const pair = parsePairLink(rawUrl)
  if (pair) {
    if (redeemedCodes.has(pair.code) || appStore.isConfirmingCode) return
    await redeemAuthCode(pair.code, pair.hub || undefined)
    return
  }
  try {
    const u = new URL(rawUrl)
    if (u.protocol === 'looseleaf:' && u.hostname === 'entry') {
      const id = Number(u.pathname.replace(/\//g, ''))
      if (Number.isInteger(id) && id > 0) {
        await selectEntry(id, true)
      }
    }
  } catch {
    // ignore malformed url
  }
}

export async function redeemAuthCode(rawCodeOrLink: string, hubOverride?: string) {
  const parsed = parsePairLink(rawCodeOrLink)
  const code = (parsed?.code ?? rawCodeOrLink).trim()
  const hub = parsed?.hub || hubOverride || appStore.hubUrl
  if (!code) {
    throw new Error('请输入有效的授权码或回调链接')
  }

  appStore.isConfirmingCode = true
  appStore.errorBanner = ''
  try {
    if (hub && normalizeHubUrl(hub) !== appStore.hubUrl) {
      appStore.hubUrl = normalizeHubUrl(hub)
    }
    api.setConfig(appStore.hubUrl, '', handleUnauthorized)
    const hostName = await getDeviceHostname()
    const resp = await api.exchangeOIDCCode(code, `${hostName} · macOS`)
    redeemedCodes.add(code)

    const resolvedHub = normalizeHubUrl(resp.hub_url || appStore.hubUrl)
    const token = (resp.access_token || resp.device_token || '').trim()
    const sessionId = (resp.session_id || resp.device_id || '').trim()

    appStore.hubUrl = resolvedHub
    appStore.deviceToken = token
    appStore.deviceId = sessionId
    appStore.deviceName = resp.device_name
    appStore.accountSub = resp.account?.sub ?? ''
    appStore.accountName = resp.account?.name ?? ''
    appStore.accountEmail = resp.account?.email ?? ''
    appStore.isPaired = Boolean(token)

    const payload: StoredCredentials = {
      device_token: token,
      device_id: sessionId,
      device_name: resp.device_name,
      account_sub: resp.account?.sub ?? undefined,
      account_name: resp.account?.name ?? undefined,
      account_email: resp.account?.email ?? undefined,
      hub_url: resolvedHub,
    }
    await saveCredentials(payload)
    api.setConfig(resolvedHub, token, handleUnauthorized)

    const label = appStore.accountName || appStore.accountEmail || '主理人'
    showToast(`欢迎回来，${label}`)
    await refreshAll()
  } finally {
    appStore.isConfirmingCode = false
  }
}

async function refreshSessionSilent() {
  try {
    const sess = await api.fetchSession()
    if (sess.account) {
      appStore.accountSub = sess.account.sub ?? appStore.accountSub
      appStore.accountName = sess.account.name ?? appStore.accountName
      appStore.accountEmail = sess.account.email ?? appStore.accountEmail
    }
    if (sess.session_id || sess.device_id) {
      appStore.deviceId = sess.session_id || sess.device_id || appStore.deviceId
    }
  } catch {
    // keep prior profile
  }
}

export async function refreshAll(silent = false) {
  if (!appStore.isPaired) return
  if (appStore.isLoading) {
    pendingRefresh = true
    pendingRefreshSilent = pendingRefreshSilent && silent
    return
  }
  appStore.isLoading = true
  try {
    const [
      cfgRes,
      profRes,
      statsRes,
      catsRes,
      entriesRes,
      otdRes,
      txRes,
      summaryRes,
      channelsRes,
      plansRes,
      wishesRes,
    ] = await Promise.allSettled([
      api.fetchSiteConfig(),
      api.fetchCuratorProfile(),
      api.fetchGlobalStats(),
      api.fetchCategoryDictionaries(),
      api.fetchAllEntries(),
      api.fetchOnThisDayEntries(),
      api.fetchAllTransactions(),
      api.fetchTransactionSummary(appStore.selectedLedgerYear, appStore.selectedLedgerMonth),
      api.fetchCreditChannels(),
      api.fetchInstallmentPlans(),
      api.fetchAllWishes(),
    ])

    if (cfgRes.status === 'fulfilled') appStore.siteConfig = cfgRes.value
    if (profRes.status === 'fulfilled') appStore.profile = profRes.value
    if (statsRes.status === 'fulfilled') appStore.stats = statsRes.value
    if (catsRes.status === 'fulfilled') {
      const { byScope } = catsRes.value
      if (byScope.expense.length) appStore.expenseCategories = byScope.expense
      if (byScope.income.length) appStore.incomeCategories = byScope.income
      if (byScope.payment.length) appStore.paymentMethods = byScope.payment
    }
    if (entriesRes.status === 'fulfilled') {
      appStore.entries = entriesRes.value
    }
    if (otdRes.status === 'fulfilled') {
      appStore.onThisDayEntries = otdRes.value.entries ?? []
    }
    if (txRes.status === 'fulfilled') {
      appStore.transactions = txRes.value
    }
    if (summaryRes.status === 'fulfilled') {
      appStore.transactionSummary = summaryRes.value
    }
    if (channelsRes.status === 'fulfilled') {
      appStore.creditChannels = channelsRes.value
    }
    if (plansRes.status === 'fulfilled') {
      appStore.installmentPlans = plansRes.value
    }
    if (wishesRes.status === 'fulfilled') {
      appStore.wishes = wishesRes.value
    }

    if (appStore.activeSpace === 'journal') {
      ensureJournalSelection()
    }

    const coreResults = [entriesRes, txRes, wishesRes]
    const firstFailure = coreResults.find(
      (r): r is PromiseRejectedResult =>
        r.status === 'rejected' && !(r.reason instanceof ApiError && r.reason.isUnauthorized),
    )

    if (firstFailure) {
      const reason = firstFailure.reason
      const msg = reason instanceof Error ? reason.message : '部分数据同步失败，请检查网络连接'
      appStore.errorBanner = msg
      if (!silent) {
        showToast(msg, true)
      }
    } else {
      appStore.errorBanner = ''
      lastSyncedAt = Date.now()
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : '同步失败'
    appStore.errorBanner = msg
    if (!silent) {
      showToast(msg, true)
    }
  } finally {
    appStore.isLoading = false
    if (pendingRefresh) {
      const nextSilent = pendingRefreshSilent
      pendingRefresh = false
      pendingRefreshSilent = true
      if (appStore.isPaired) {
        void refreshAll(nextSilent)
      }
    }
  }
}

export function refreshIfStale(maxAgeMs = 20 * 60 * 1000) {
  if (!appStore.isPaired || appStore.isLoading) return
  if (Date.now() - lastSyncedAt > maxAgeMs) {
    void refreshAll(true)
  }
}

export async function refreshMonthlySummary(year: number, month: number) {
  appStore.selectedLedgerYear = year
  appStore.selectedLedgerMonth = month
  try {
    appStore.transactionSummary = await api.fetchTransactionSummary(year, month)
  } catch {
    // keep prior summary
  }
}

export async function refreshTrustedDevices() {
  try {
    appStore.trustedDevices = await api.fetchTrustedDevices()
  } catch (err) {
    showToast(err instanceof Error ? err.message : '加载设备列表失败', true)
  }
}

export function triggerPrimaryCreate() {
  if (appStore.activeSpace === 'ledger') {
    appStore.transactionModal = { open: true, editing: null }
  } else if (appStore.activeSpace === 'wishlist') {
    appStore.wishModal = { open: true, editing: null }
  } else {
    appStore.showNewEntryModal = true
  }
}
