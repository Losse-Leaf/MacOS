import type {
  APIEnvelope,
  Attachment,
  AuthSessionResponse,
  CategoryOption,
  ConfirmPairingResponse,
  CreateEntryPayload,
  CreateTransactionPayload,
  CreateWishPayload,
  CreditChannel,
  CuratorProfile,
  EntriesListResponse,
  GlobalSearchResponse,
  GlobalStats,
  InstallmentItem,
  InstallmentPlanDetail,
  InstallmentPlanSummary,
  LifeEntry,
  PresignUploadResponse,
  ResolveWishPayload,
  SiteConfig,
  SystemStatus,
  Transaction,
  TransactionSummary,
  TrustedDevice,
  UnifiedUploadResponse,
  UpdateEntryPayload,
  Wish,
  WishesListResponse,
} from '../types/api'
import { DEFAULT_HUB_URL } from './credentials'

export class ApiError extends Error {
  readonly code: number
  readonly status: number
  readonly isUnauthorized: boolean

  constructor(message: string, status = 0, code = 0) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.isUnauthorized = status === 401 || code === 401
  }
}

export function normalizeHubUrl(raw: string): string {
  const cleaned = raw.trim().replace(/\/+$/, '')
  return cleaned || DEFAULT_HUB_URL
}

export function isValidHubUrl(raw: string): boolean {
  try {
    const u = new URL(raw.trim())
    return (u.protocol === 'http:' || u.protocol === 'https:') && Boolean(u.hostname)
  } catch {
    return false
  }
}

export function buildOIDCLoginUrl(hubUrl: string, deviceName: string, platform = 'macos'): string | null {
  if (!isValidHubUrl(hubUrl)) return null
  const base = normalizeHubUrl(hubUrl)
  const url = new URL(`${base}/api/v1/auth/oidc/login`)
  url.searchParams.set('platform', platform)
  const cleanName = deviceName.trim()
  if (cleanName) {
    url.searchParams.set('device_name', cleanName)
  }
  return url.toString()
}

export function parsePairLink(raw: string): { hub: string; code: string } | null {
  const trimmed = raw.trim()
  if (!trimmed) return null
  try {
    const parsed = new URL(trimmed)
    if (parsed.protocol !== 'looseleaf:') return null
    const host = (parsed.hostname || parsed.host || '').toLowerCase()
    const pathname = parsed.pathname.toLowerCase()
    const isOAuthCallback = host === 'auth' || pathname.startsWith('//auth') || pathname.startsWith('/auth')
    const isLegacyPair = host === 'pair' || pathname.startsWith('//pair') || pathname.startsWith('/pair')
    if (!isOAuthCallback && !isLegacyPair) return null
    const code = (parsed.searchParams.get('code') ?? parsed.searchParams.get('ticket') ?? '').trim()
    if (!code) return null
    const hub = (parsed.searchParams.get('hub') ?? '').trim()
    return { hub, code }
  } catch {
    return null
  }
}

export function resolveMediaUrl(rawUrl: string | null | undefined, hubUrl: string): string {
  const trimmed = (rawUrl ?? '').trim()
  if (!trimmed) return ''
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed
  }
  const base = normalizeHubUrl(hubUrl)
  const path = trimmed.startsWith('/') ? trimmed : `/${trimmed}`
  return `${base}${path}`
}

function buildApiUrl(base: string, path: string, query?: Record<string, string | number | boolean | undefined | null>): string {
  const normalizedBase = normalizeHubUrl(base)
  const normalizedPath = path.startsWith('/') ? path : `/${path}`
  if (!query) return `${normalizedBase}${normalizedPath}`
  const pairs: string[] = []
  for (const [k, v] of Object.entries(query)) {
    if (v === undefined || v === null || v === '') continue
    pairs.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
  }
  return pairs.length > 0 ? `${normalizedBase}${normalizedPath}?${pairs.join('&')}` : `${normalizedBase}${normalizedPath}`
}

export class ApiClient {
  private hubUrl = DEFAULT_HUB_URL
  private token = ''
  private onUnauthorized: (() => void) | null = null

  setConfig(hubUrl: string, token: string, onUnauthorized?: (() => void) | null) {
    this.hubUrl = normalizeHubUrl(hubUrl)
    this.token = token
    if (onUnauthorized !== undefined) {
      this.onUnauthorized = onUnauthorized
    }
  }

  getHubUrl(): string {
    return this.hubUrl
  }

  private async request<T>(
    path: string,
    options: {
      method?: string
      query?: Record<string, string | number | boolean | undefined | null>
      body?: unknown
      skipAuthHeader?: boolean
    } = {},
  ): Promise<T> {
    const url = buildApiUrl(this.hubUrl, path, options.query)
    const headers: Record<string, string> = {}
    if (options.body !== undefined) {
      headers['Content-Type'] = 'application/json'
    }
    if (!options.skipAuthHeader && this.token) {
      headers['Authorization'] = `Bearer ${this.token}`
      headers['X-Device-Token'] = this.token
    }

    let response: Response
    try {
      response = await fetch(url, {
        method: options.method ?? 'GET',
        headers,
        body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
      })
    } catch (err) {
      throw new ApiError(err instanceof Error ? err.message : '网络连接异常')
    }

    if (response.status === 401) {
      let msg = '设备凭据未授权或已失效，请重新登录'
      try {
        const env = (await response.json()) as APIEnvelope<unknown>
        if (env?.message) msg = env.message
      } catch {
        // ignore parse failure
      }
      if (!options.skipAuthHeader) {
        this.onUnauthorized?.()
      }
      throw new ApiError(msg, 401, 401)
    }

    let envelope: APIEnvelope<T>
    try {
      envelope = (await response.json()) as APIEnvelope<T>
    } catch {
      if (!response.ok) {
        throw new ApiError(`请求失败 (HTTP ${response.status})`, response.status, response.status)
      }
      throw new ApiError('响应数据解析失败', response.status, 0)
    }

    if (!response.ok || envelope.code >= 400 || envelope.data === null || envelope.data === undefined) {
      throw new ApiError(
        envelope.message || `请求失败 (HTTP ${response.status})`,
        response.status,
        envelope.code ?? response.status,
      )
    }

    return envelope.data
  }

  fetchSystemStatus(): Promise<SystemStatus> {
    return this.request<SystemStatus>('/api/v1/system/status', { skipAuthHeader: true })
  }

  async exchangeOIDCCode(code: string, deviceName: string): Promise<ConfirmPairingResponse> {
    const payload = {
      code,
      ticket: code,
      device_name: deviceName,
      platform: 'macos',
      device_model: 'Mac',
    }
    try {
      return await this.request<ConfirmPairingResponse>('/api/v1/auth/oidc/exchange', {
        method: 'POST',
        body: payload,
        skipAuthHeader: true,
      })
    } catch (err) {
      if (err instanceof ApiError && err.status === 404) {
        return await this.request<ConfirmPairingResponse>('/api/v1/auth/pair/confirm', {
          method: 'POST',
          body: payload,
          skipAuthHeader: true,
        })
      }
      throw err
    }
  }

  fetchSession(): Promise<AuthSessionResponse> {
    return this.request('/api/v1/auth/session')
  }

  async logout(): Promise<void> {
    await this.request('/api/v1/auth/logout', { method: 'POST', body: {} })
  }

  fetchTrustedDevices(): Promise<TrustedDevice[]> {
    return this.request('/api/v1/auth/devices')
  }

  async updateDeviceName(id: string, name: string): Promise<TrustedDevice> {
    return this.request(`/api/v1/auth/devices/${encodeURIComponent(id)}`, {
      method: 'PUT',
      body: { name },
    })
  }

  async revokeDevice(id: string): Promise<void> {
    await this.request(`/api/v1/auth/devices/${encodeURIComponent(id)}`, { method: 'DELETE' })
  }

  fetchSiteConfig(): Promise<SiteConfig> {
    return this.request('/api/v1/config')
  }

  fetchCuratorProfile(): Promise<CuratorProfile> {
    return this.request('/api/v1/profile')
  }

  updateCuratorProfile(payload: Partial<CuratorProfile>): Promise<CuratorProfile> {
    return this.request('/api/v1/profile', { method: 'PUT', body: payload })
  }

  fetchGlobalStats(): Promise<GlobalStats> {
    return this.request('/api/v1/stats')
  }

  async fetchCategories(scope?: string): Promise<CategoryOption[]> {
    const raw = await this.request<{ items?: CategoryOption[] } | CategoryOption[]>('/api/v1/categories', {
      query: scope ? { scope } : undefined,
    })
    return Array.isArray(raw) ? raw : (raw.items ?? [])
  }

  fetchOnThisDayEntries(): Promise<{ month: number; day: number; entries: LifeEntry[] }> {
    return this.request('/api/v1/entries/on-this-day')
  }

  searchGlobalArchive(query: string, limit = 25): Promise<GlobalSearchResponse> {
    return this.request('/api/v1/search', { query: { q: query, limit } })
  }

  fetchEntriesPage(page = 1, pageSize = 50): Promise<EntriesListResponse> {
    return this.request('/api/v1/entries', { query: { page, page_size: pageSize } })
  }

  async fetchAllEntries(): Promise<LifeEntry[]> {
    const collected: LifeEntry[] = []
    let page = 1
    const pageSize = 50
    while (page <= 40) {
      const resp = await this.fetchEntriesPage(page, pageSize)
      const list = resp.entries ?? []
      collected.push(...list)
      if (collected.length >= resp.total || list.length < pageSize) break
      page++
    }
    return collected
  }

  fetchEntry(id: number): Promise<LifeEntry> {
    return this.request(`/api/v1/entries/${id}`)
  }

  createEntry(payload: CreateEntryPayload): Promise<LifeEntry> {
    return this.request('/api/v1/entries', { method: 'POST', body: payload })
  }

  updateEntry(id: number, payload: UpdateEntryPayload): Promise<LifeEntry> {
    return this.request(`/api/v1/entries/${id}`, { method: 'PUT', body: payload })
  }

  async deleteEntry(id: number): Promise<void> {
    await this.request(`/api/v1/entries/${id}`, { method: 'DELETE' })
  }

  async fetchAllTransactions(): Promise<Transaction[]> {
    const collected: Transaction[] = []
    let offset = 0
    const limit = 200
    while (offset <= 10_000) {
      const batch = await this.request<Transaction[]>('/api/v1/transactions', {
        query: { limit, offset },
      })
      collected.push(...batch)
      if (batch.length < limit) break
      offset += limit
    }
    return collected
  }

  fetchTransactionSummary(year: number, month: number): Promise<TransactionSummary> {
    return this.request('/api/v1/transactions/summary', { query: { year, month } })
  }

  createTransaction(payload: CreateTransactionPayload): Promise<Transaction> {
    return this.request('/api/v1/transactions', { method: 'POST', body: payload })
  }

  updateTransaction(id: number, payload: CreateTransactionPayload): Promise<Transaction> {
    return this.request(`/api/v1/transactions/${id}`, { method: 'PUT', body: payload })
  }

  async deleteTransaction(id: number): Promise<void> {
    await this.request(`/api/v1/transactions/${id}`, { method: 'DELETE' })
  }

  fetchCreditChannels(): Promise<CreditChannel[]> {
    return this.request('/api/v1/credit-channels')
  }

  fetchInstallmentPlans(status?: string): Promise<InstallmentPlanSummary[]> {
    return this.request('/api/v1/installment-plans', {
      query: status ? { status } : undefined,
    })
  }

  fetchInstallmentPlanDetail(id: number): Promise<InstallmentPlanDetail> {
    return this.request(`/api/v1/installment-plans/${id}`)
  }

  createInstallmentPlan(payload: {
    channel_code?: string
    title: string
    kind: 'expense'
    principal: number
    periods: number
    fee_mode: string
    fee_value: number
    first_due_date?: string
    repay_day?: number
    category_name?: string
    note?: string
  }): Promise<{ plan: InstallmentPlanSummary; items: InstallmentItem[] }> {
    return this.request('/api/v1/installment-plans', { method: 'POST', body: payload })
  }

  payInstallmentItem(
    itemId: number,
    payload: { paid_amount?: number; pay_account?: string; paid_at?: string } = {},
  ): Promise<{ item: InstallmentItem; plan_status: string }> {
    return this.request(`/api/v1/installment-items/${itemId}/pay`, { method: 'POST', body: payload })
  }

  unpayInstallmentItem(itemId: number): Promise<{ item: InstallmentItem; plan_status: string }> {
    return this.request(`/api/v1/installment-items/${itemId}/unpay`, { method: 'POST', body: {} })
  }

  async settleInstallmentPlan(planId: number): Promise<void> {
    await this.request(`/api/v1/installment-plans/${planId}/settle`, { method: 'POST', body: {} })
  }

  async deleteInstallmentPlan(planId: number): Promise<void> {
    await this.request(`/api/v1/installment-plans/${planId}`, { method: 'DELETE' })
  }

  async fetchAllWishes(): Promise<Wish[]> {
    const collected: Wish[] = []
    let page = 1
    const pageSize = 100
    while (page <= 20) {
      const resp = await this.request<WishesListResponse>('/api/v1/wishes', {
        query: { page, page_size: pageSize },
      })
      const list = resp.wishes ?? []
      collected.push(...list)
      if (collected.length >= resp.total || list.length < pageSize) break
      page++
    }
    return collected
  }

  createWish(payload: CreateWishPayload): Promise<Wish> {
    return this.request('/api/v1/wishes', { method: 'POST', body: payload })
  }

  updateWish(id: number, payload: CreateWishPayload): Promise<Wish> {
    return this.request(`/api/v1/wishes/${id}`, { method: 'PUT', body: payload })
  }

  resolveWish(id: number, payload: ResolveWishPayload): Promise<Wish> {
    return this.request(`/api/v1/wishes/${id}/resolve`, { method: 'POST', body: payload })
  }

  async deleteWish(id: number): Promise<void> {
    await this.request(`/api/v1/wishes/${id}`, { method: 'DELETE' })
  }

  /**
   * 统一图片上传：优先走 R2 预签名直传（presign -> PUT -> complete），未开启 R2 时自动回退 multipart /files/upload
   */
  async uploadImageFile(file: File): Promise<Attachment> {
    const dims = await readImageDimensions(file)
    try {
      const presigned = await this.request<PresignUploadResponse>('/api/v1/uploads/presign', {
        method: 'POST',
        body: {
          filename: file.name || 'image.png',
          content_type: file.type || 'image/jpeg',
          size: file.size,
        },
      })

      const putResp = await fetch(presigned.upload_url, {
        method: 'PUT',
        headers: { 'Content-Type': file.type || 'application/octet-stream' },
        body: file,
      })
      if (!putResp.ok) {
        throw new ApiError(`对象存储直传失败 (${putResp.status})`, putResp.status)
      }

      return await this.request<Attachment>('/api/v1/uploads/complete', {
        method: 'POST',
        body: {
          upload_id: presigned.upload_id,
          object_key: presigned.object_key,
          original_filename: file.name || 'image.png',
          mime_type: file.type || 'image/jpeg',
          size: file.size,
          width: dims.width,
          height: dims.height,
        },
      })
    } catch {
      const form = new FormData()
      form.append('folder', 'entries')
      form.append('file', file, file.name || 'image.png')

      const headers: Record<string, string> = {}
      if (this.token) {
        headers['Authorization'] = `Bearer ${this.token}`
        headers['X-Device-Token'] = this.token
      }

      const resp = await fetch(buildApiUrl(this.hubUrl, '/api/v1/files/upload'), {
        method: 'POST',
        headers,
        body: form,
      })
      const env = (await resp.json()) as APIEnvelope<UnifiedUploadResponse>
      if (!resp.ok || env.code >= 400 || !env.data) {
        throw new ApiError(env?.message || `上传失败 (${resp.status})`, resp.status, env?.code ?? resp.status)
      }
      return {
        id: env.data.attachment_id,
        object_key: env.data.object_key,
        url: env.data.url,
        thumbnail_url: env.data.thumbnail_url,
        original_filename: env.data.filename,
        mime_type: env.data.mime_type,
        size: env.data.size,
        width: env.data.width ?? dims.width,
        height: env.data.height ?? dims.height,
      }
    }
  }
}

function readImageDimensions(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve) => {
    if (typeof Image === 'undefined' || typeof URL === 'undefined' || !file.type.startsWith('image/')) {
      resolve({ width: 0, height: 0 })
      return
    }
    const objUrl = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(objUrl)
      resolve({ width: img.naturalWidth || 0, height: img.naturalHeight || 0 })
    }
    img.onerror = () => {
      URL.revokeObjectURL(objUrl)
      resolve({ width: 0, height: 0 })
    }
    img.src = objUrl
  })
}

export const api = new ApiClient()
