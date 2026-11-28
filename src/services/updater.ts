import { reactive } from 'vue'
import { showToast } from '../stores/appStore'

export const MAC_REPO = 'Losse-Leaf/MacOS'
export const MAC_RELEASES_API = `https://api.github.com/repos/${MAC_REPO}/releases/latest`
export const MAC_RELEASES_PAGE = `https://github.com/${MAC_REPO}/releases/latest`
export const MAC_INSTALL_COMMAND =
  '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Losse-Leaf/MacOS/main/install.sh)"'

const LAST_CHECK_AT_KEY = 'looseleaf_mac_update_last_check_at'
const CHECK_THROTTLE_MS = 24 * 60 * 60 * 1000
const FALLBACK_VERSION = '4.2.0'

export interface GitHubReleaseAsset {
  name: string
  browser_download_url: string
  digest?: string | null
}

export interface GitHubReleasePayload {
  tag_name: string
  body?: string | null
  published_at?: string | null
  assets?: GitHubReleaseAsset[]
}

export interface AppUpdateInfo {
  tagName: string
  version: string
  body: string
  publishedAt: string
  downloadUrl: string
  assetName: string
  expectedSha256: string | null
  checksumUrl: string | null
}

export interface UpdateProgressPayload {
  stage: string
  progress: number
  message: string
}

export const updaterState = reactive({
  currentVersion: FALLBACK_VERSION,
  checking: false,
  checked: false,
  updating: false,
  progress: 0,
  progressMessage: '',
  availableUpdate: null as AppUpdateInfo | null,
  error: '',
  lastCheckedAt: 0,
})

let initialized = false
let unlistenProgress: (() => void) | null = null

function isTauriRuntime(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window
}

export function normalizeSemver(raw: string): number[] {
  const cleaned = raw.trim().replace(/^v/i, '').split('-')[0] || '0'
  return cleaned
    .split('.')
    .map((seg) => {
      const n = Number.parseInt(seg.replace(/[^\d]/g, ''), 10)
      return Number.isFinite(n) ? n : 0
    })
}

export function compareSemver(remote: string, local: string): number {
  const r = normalizeSemver(remote)
  const l = normalizeSemver(local)
  const len = Math.max(r.length, l.length)
  for (let i = 0; i < len; i++) {
    const rv = r[i] ?? 0
    const lv = l[i] ?? 0
    if (rv > lv) return 1
    if (rv < lv) return -1
  }
  return 0
}

export function normalizeSha256Digest(raw?: string | null): string | null {
  if (!raw) return null
  let cleaned = raw.trim()
  if (cleaned.toLowerCase().startsWith('sha256:')) {
    cleaned = cleaned.slice('sha256:'.length).trim()
  }
  return /^[0-9a-fA-F]{64}$/.test(cleaned) ? cleaned.toLowerCase() : null
}

export function parseChecksumText(text: string, assetName = ''): string | null {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)

  for (const line of lines) {
    if (line.startsWith('#')) continue
    const parts = line.split(/\s+/)
    if (parts.length === 1) {
      const only = normalizeSha256Digest(parts[0])
      if (only) return only
      continue
    }
    const hash = normalizeSha256Digest(parts[0])
    if (!hash) continue
    const fileCandidate = (parts[1] || '').replace(/^[*./]+/, '')
    if (!assetName || fileCandidate === assetName || fileCandidate.endsWith(`/${assetName}`)) {
      return hash
    }
  }
  return null
}

export function parseReleaseInfo(
  release: GitHubReleasePayload,
  localVersion: string,
): { update: AppUpdateInfo | null; missingAsset: boolean } {
  const tagName = (release.tag_name || '').trim()
  if (!tagName) return { update: null, missingAsset: false }
  const cleanVersion = tagName.replace(/^v/i, '')

  if (compareSemver(cleanVersion, localVersion) <= 0) {
    return { update: null, missingAsset: false }
  }

  const assets = Array.isArray(release.assets) ? release.assets : []
  const zipAsset = assets.find((a) => {
    const lower = a.name.toLowerCase()
    return lower.endsWith('.zip') && (lower.includes('arm64') || lower.includes('looseleaf'))
  })

  if (!zipAsset || !zipAsset.browser_download_url) {
    return { update: null, missingAsset: true }
  }

  const checksumAsset = assets.find((a) => {
    const lower = a.name.toLowerCase()
    return (
      lower === `${zipAsset.name.toLowerCase()}.sha256` ||
      lower === 'checksums.txt' ||
      lower === 'sha256sums.txt' ||
      lower === 'sha256sums'
    )
  })

  return {
    update: {
      tagName,
      version: cleanVersion,
      body: (release.body || '').trim(),
      publishedAt: release.published_at || '',
      downloadUrl: zipAsset.browser_download_url,
      assetName: zipAsset.name,
      expectedSha256: normalizeSha256Digest(zipAsset.digest),
      checksumUrl: checksumAsset?.browser_download_url || null,
    },
    missingAsset: false,
  }
}

export async function initUpdater(): Promise<void> {
  if (initialized) return
  initialized = true

  try {
    const savedAt = Number(localStorage.getItem(LAST_CHECK_AT_KEY) || '0')
    if (Number.isFinite(savedAt) && savedAt > 0) {
      updaterState.lastCheckedAt = savedAt
    }
  } catch {
    // ignore storage errors
  }

  if (!isTauriRuntime()) return

  try {
    const { invoke } = await import('@tauri-apps/api/core')
    const ver = await invoke<string>('get_app_version')
    if (ver && ver.trim()) {
      updaterState.currentVersion = ver.trim()
    }
  } catch {
    // keep fallback version
  }

  try {
    const { listen } = await import('@tauri-apps/api/event')
    if (!unlistenProgress) {
      unlistenProgress = await listen<UpdateProgressPayload>('app-update-progress', (event) => {
        const payload = event.payload
        if (!payload) return
        if (typeof payload.progress === 'number') {
          updaterState.progress = Math.max(0, Math.min(1, payload.progress))
        }
        if (payload.message) {
          updaterState.progressMessage = payload.message
        }
      })
    }
  } catch {
    // ignore event listener setup failures
  }
}

async function resolveUpdateSha256(info: AppUpdateInfo): Promise<string | null> {
  if (info.expectedSha256) return info.expectedSha256
  if (!info.checksumUrl) return null
  try {
    const res = await fetch(info.checksumUrl)
    if (!res.ok) return null
    const text = await res.text()
    const digest = parseChecksumText(text, info.assetName)
    if (digest) {
      info.expectedSha256 = digest
    }
    return digest
  } catch {
    return null
  }
}

export async function checkForAppUpdate(manual = false): Promise<void> {
  if (updaterState.checking) {
    if (manual) showToast('正在检查新版本，请稍候…')
    return
  }

  if (!manual && updaterState.lastCheckedAt > 0) {
    if (Date.now() - updaterState.lastCheckedAt < CHECK_THROTTLE_MS) {
      updaterState.checked = true
      return
    }
  }

  updaterState.checking = true
  updaterState.error = ''

  try {
    const res = await fetch(MAC_RELEASES_API, {
      headers: { Accept: 'application/vnd.github.v3+json' },
    })

    if (res.status === 403 && res.headers.get('X-RateLimit-Remaining') === '0') {
      const resetSec = Number(res.headers.get('X-RateLimit-Reset') || '0')
      const hint = resetSec > 0
        ? new Date(resetSec * 1000).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
        : '稍后'
      const msg = `GitHub 版本查询频率受限，请于 ${hint} 后重试`
      updaterState.error = msg
      if (manual) showToast(msg, true)
      return
    }

    if (!res.ok) {
      const msg = `检查更新失败 (HTTP ${res.status})`
      updaterState.error = msg
      if (manual) showToast(msg, true)
      return
    }

    const release = (await res.json()) as GitHubReleasePayload
    const { update, missingAsset } = parseReleaseInfo(release, updaterState.currentVersion)

    const now = Date.now()
    updaterState.lastCheckedAt = now
    try {
      localStorage.setItem(LAST_CHECK_AT_KEY, String(now))
    } catch {
      // ignore storage errors
    }

    if (missingAsset) {
      updaterState.availableUpdate = null
      updaterState.error = '发现新版本，但未找到 macOS 安装包资产'
      if (manual) showToast(updaterState.error, true)
      return
    }

    if (update) {
      await resolveUpdateSha256(update)
      updaterState.availableUpdate = update
      if (manual) {
        showToast(`发现新版本 ${update.tagName}`)
      }
    } else {
      updaterState.availableUpdate = null
      if (manual) {
        showToast(`当前已是最新版本 (v${updaterState.currentVersion})`)
      }
    }
    updaterState.checked = true
  } catch (err) {
    const msg = err instanceof Error ? `检查更新失败：${err.message}` : '检查更新失败，请检查网络'
    updaterState.error = msg
    if (manual) showToast(msg, true)
  } finally {
    updaterState.checking = false
  }
}

export async function startInAppUpdate(): Promise<void> {
  const info = updaterState.availableUpdate
  if (!info || updaterState.updating) return

  if (!isTauriRuntime()) {
    await openReleasePage()
    return
  }

  updaterState.updating = true
  updaterState.error = ''
  updaterState.progress = 0.05
  updaterState.progressMessage = '正在准备应用内更新…'

  try {
    const sha256 = await resolveUpdateSha256(info)
    if (!sha256) {
      throw new Error('更新包缺少 SHA256 完整性摘要，请改用终端一键安装或前往 GitHub 下载')
    }
    const { invoke } = await import('@tauri-apps/api/core')
    await invoke('perform_app_update', {
      downloadUrl: info.downloadUrl,
      expectedSha256: sha256,
      assetName: info.assetName,
    })
  } catch (err) {
    const msg = typeof err === 'string'
      ? err
      : err instanceof Error
        ? err.message
        : '应用内更新失败'
    updaterState.error = msg
    updaterState.progress = 0
    updaterState.progressMessage = ''
    showToast(msg, true)
  } finally {
    updaterState.updating = false
  }
}

export async function copyInstallCommand(): Promise<void> {
  try {
    await navigator.clipboard.writeText(MAC_INSTALL_COMMAND)
    showToast('已复制终端升级命令，打开「终端」粘贴回车即可一键升级')
  } catch {
    showToast('复制失败，请手动从页面复制更新命令', true)
  }
}

export async function openReleasePage(): Promise<void> {
  const url = updaterState.availableUpdate?.downloadUrl || MAC_RELEASES_PAGE
  try {
    if (isTauriRuntime()) {
      const { openUrl } = await import('@tauri-apps/plugin-opener')
      await openUrl(url)
      return
    }
  } catch {
    // fall through
  }
  window.open(url, '_blank', 'noopener,noreferrer')
}
