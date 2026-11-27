export interface StoredCredentials {
  device_token?: string | null
  device_id?: string | null
  device_name?: string | null
  account_sub?: string | null
  account_name?: string | null
  account_email?: string | null
  hub_url?: string | null
}

export const DEFAULT_HUB_URL = 'https://leaf.starryheavens.uk'
const BROWSER_FALLBACK_KEY = 'looseleaf_desktop_credentials_v1'

function isTauriRuntime(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window
}

export async function loadCredentials(): Promise<StoredCredentials> {
  if (isTauriRuntime()) {
    const { invoke } = await import('@tauri-apps/api/core')
    const creds = await invoke<StoredCredentials>('load_credentials')
    return {
      ...creds,
      hub_url: creds.hub_url || DEFAULT_HUB_URL,
    }
  }
  try {
    const raw = localStorage.getItem(BROWSER_FALLBACK_KEY)
    if (!raw) return { hub_url: DEFAULT_HUB_URL }
    const parsed = JSON.parse(raw) as StoredCredentials
    return { ...parsed, hub_url: parsed.hub_url || DEFAULT_HUB_URL }
  } catch {
    return { hub_url: DEFAULT_HUB_URL }
  }
}

export async function saveCredentials(creds: StoredCredentials): Promise<void> {
  if (isTauriRuntime()) {
    const { invoke } = await import('@tauri-apps/api/core')
    await invoke('save_credentials', { creds })
    return
  }
  localStorage.setItem(BROWSER_FALLBACK_KEY, JSON.stringify(creds))
}

export async function clearCredentials(): Promise<void> {
  if (isTauriRuntime()) {
    const { invoke } = await import('@tauri-apps/api/core')
    await invoke('clear_credentials')
    return
  }
  const prev = await loadCredentials()
  localStorage.setItem(
    BROWSER_FALLBACK_KEY,
    JSON.stringify({ hub_url: prev.hub_url || DEFAULT_HUB_URL }),
  )
}

export async function getDeviceHostname(): Promise<string> {
  if (isTauriRuntime()) {
    const { invoke } = await import('@tauri-apps/api/core')
    return await invoke<string>('get_device_hostname')
  }
  return 'Mac Desktop'
}

export async function openExternalUrl(url: string): Promise<void> {
  if (isTauriRuntime()) {
    const { openUrl } = await import('@tauri-apps/plugin-opener')
    await openUrl(url)
    return
  }
  window.open(url, '_blank', 'noopener,noreferrer')
}
