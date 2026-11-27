<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { BookOpen, Check, KeyRound, RefreshCw, Server, Settings2, WifiOff } from 'lucide-vue-next'
import { api, buildOIDCLoginUrl, isValidHubUrl } from '../services/api'
import { getDeviceHostname, openExternalUrl } from '../services/credentials'
import { appStore, redeemAuthCode, setHubUrl } from '../stores/appStore'
import type { SystemStatus } from '../types/api'

const isProbing = ref(true)
const systemStatus = ref<SystemStatus | null>(null)
const probeError = ref('')
const hasOpenedBrowser = ref(false)
const authError = ref('')
const manualCode = ref('')
const showManualInput = ref(false)
const editingHub = ref(false)
const draftHubUrl = ref(appStore.hubUrl)
const hubError = ref('')

async function probeHub() {
  isProbing.value = true
  probeError.value = ''
  authError.value = ''
  try {
    api.setConfig(appStore.hubUrl, '')
    systemStatus.value = await api.fetchSystemStatus()
  } catch (err) {
    systemStatus.value = null
    probeError.value = err instanceof Error ? err.message : '无法连接服务器'
  } finally {
    isProbing.value = false
  }
}

async function startOidcLogin() {
  authError.value = ''
  const hostName = await getDeviceHostname()
  const loginUrl = buildOIDCLoginUrl(appStore.hubUrl, hostName, 'macos')
  if (!loginUrl) {
    authError.value = '同步服务器地址格式无效'
    return
  }
  try {
    await openExternalUrl(loginUrl)
    hasOpenedBrowser.value = true
  } catch (err) {
    authError.value = err instanceof Error ? err.message : '无法打开系统浏览器'
  }
}

async function submitManualCode() {
  authError.value = ''
  try {
    await redeemAuthCode(manualCode.value)
  } catch (err) {
    authError.value = err instanceof Error ? err.message : '验证授权码失败'
  }
}

async function saveHubConfig() {
  hubError.value = ''
  if (!isValidHubUrl(draftHubUrl.value)) {
    hubError.value = '请输入以 http:// 或 https:// 开头的有效地址'
    return
  }
  await setHubUrl(draftHubUrl.value)
  editingHub.value = false
  await probeHub()
}

onMounted(() => {
  void probeHub()
})
</script>

<template>
  <div class="relative min-h-dvh w-full flex flex-col items-center justify-center bg-[var(--paper)] px-6 py-12">
    <div class="tauri-drag fixed inset-x-0 top-0 h-10" />

    <div class="w-full max-w-[440px] flex flex-col items-center gap-6">
      <div class="flex flex-col items-center text-center gap-2">
        <div
          class="w-14 h-14 rounded-2xl bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] flex items-center justify-center mb-1"
        >
          <BookOpen class="w-7 h-7" />
        </div>
        <h1 class="font-serif-editorial text-[28px] font-semibold tracking-tight text-[var(--ink-primary)]">
          散页 · Loose-Leaf
        </h1>
        <p class="text-[13px] text-[var(--ink-secondary)]">
          暖棉纸质感个人生活档案馆 · 散页、账本与心愿
        </p>
      </div>

      <!-- Hub 地址胶囊 -->
      <div class="w-full flex flex-col items-center gap-2">
        <button
          v-if="!editingHub"
          type="button"
          class="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12px] text-[var(--ink-secondary)] hover:border-[var(--border-divider)] transition-colors cursor-pointer"
          @click="
            draftHubUrl = appStore.hubUrl;
            hubError = '';
            editingHub = true
          "
        >
          <span
            class="w-2 h-2 rounded-full"
            :class="
              isProbing
                ? 'bg-[var(--ink-muted)]'
                : probeError
                  ? 'bg-[var(--accent-warm)]'
                  : 'bg-[var(--accent-moss)]'
            "
          />
          <span class="font-mono-tabular truncate max-w-[280px]">{{ appStore.hubUrl }}</span>
          <Settings2 class="w-3.5 h-3.5 text-[var(--ink-muted)]" />
        </button>

        <form
          v-else
          class="w-full flex flex-col gap-2 p-3 rounded-xl bg-[var(--paper-subtle)] border border-[var(--border-subtle)]"
          @submit.prevent="saveHubConfig"
        >
          <div class="flex items-center gap-2">
            <Server class="w-4 h-4 text-[var(--ink-muted)] shrink-0" />
            <input
              v-model="draftHubUrl"
              type="url"
              placeholder="https://leaf.starryheavens.uk"
              class="flex-1 bg-[var(--paper-elevated)] border border-[var(--border-subtle)] rounded-lg px-2.5 py-1.5 text-[12px] font-mono-tabular text-[var(--ink-primary)]"
              autofocus
            />
            <button
              type="submit"
              class="px-3 py-1.5 rounded-lg bg-[var(--accent-warm)] text-white text-[12px] font-medium cursor-pointer hover:opacity-90"
            >
              确定
            </button>
            <button
              type="button"
              class="px-2.5 py-1.5 rounded-lg text-[12px] text-[var(--ink-secondary)] hover:bg-[var(--paper)] cursor-pointer"
              @click="editingHub = false"
            >
              取消
            </button>
          </div>
          <p v-if="hubError" class="text-[11px] text-[var(--accent-warm)] px-1">{{ hubError }}</p>
        </form>
      </div>

      <!-- 主登录卡片 -->
      <div
        class="w-full rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] p-7 shadow-sm flex flex-col gap-4"
      >
        <div v-if="isProbing" class="py-8 flex flex-col items-center gap-3 text-[var(--ink-secondary)]">
          <RefreshCw class="w-5 h-5 animate-spin text-[var(--accent-warm)]" />
          <span class="text-[13px]">正在探测中枢节点状态…</span>
        </div>

        <div v-else-if="probeError" class="py-4 flex flex-col items-center text-center gap-3">
          <WifiOff class="w-7 h-7 text-[var(--accent-warm)]" />
          <div class="text-[15px] font-semibold text-[var(--ink-primary)]">无法连接同步服务器</div>
          <p class="text-[12px] font-mono-tabular text-[var(--ink-muted)] bg-[var(--paper-subtle)] px-3 py-2 rounded-lg w-full break-all">
            {{ probeError }}
          </p>
          <button
            type="button"
            class="mt-1 px-4 py-2 rounded-lg bg-[var(--accent-warm)] text-white text-[13px] font-medium hover:opacity-90 cursor-pointer"
            @click="probeHub"
          >
            重新连接
          </button>
        </div>

        <template v-else>
          <div class="text-center flex flex-col gap-1.5">
            <h2 class="font-serif-editorial text-[19px] font-semibold text-[var(--ink-primary)]">
              账号登录
            </h2>
            <p class="text-[12.5px] leading-relaxed text-[var(--ink-secondary)]">
              将在系统浏览器跳转至
              <span class="font-medium text-[var(--ink-primary)]">{{
                systemStatus?.oidc_provider_name?.trim() || 'Vesper Auth'
              }}</span>
              完成授权，验证后自动回到《散页》。
            </p>
          </div>

          <button
            type="button"
            :disabled="appStore.isConfirmingCode || systemStatus?.oidc_enabled === false"
            class="w-full py-2.5 px-4 rounded-xl bg-[var(--accent-warm)] text-white text-[13.5px] font-medium flex items-center justify-center gap-2 hover:opacity-92 active:scale-[0.99] transition-all disabled:opacity-50 cursor-pointer"
            @click="startOidcLogin"
          >
            <RefreshCw v-if="appStore.isConfirmingCode" class="w-4 h-4 animate-spin" />
            <KeyRound v-else class="w-4 h-4" />
            <span>
              {{
                appStore.isConfirmingCode
                  ? '正在建立登录会话…'
                  : systemStatus?.oidc_enabled === false
                    ? '服务器未启用 OAuth 2.0'
                    : `使用 ${systemStatus?.oidc_provider_name?.trim() || 'Vesper Auth'} 登录`
              }}
            </span>
          </button>

          <p
            v-if="hasOpenedBrowser && !appStore.isConfirmingCode"
            class="text-[12px] text-[var(--ink-muted)] bg-[var(--paper-subtle)] px-3 py-2.5 rounded-lg text-center leading-relaxed"
          >
            已在默认浏览器打开登录页。若浏览器未自动唤起应用，可复制回调链接或一次性授权码粘贴到下方：
          </p>

          <div class="pt-1 flex flex-col gap-2">
            <button
              type="button"
              class="text-[12px] text-[var(--ink-muted)] hover:text-[var(--ink-primary)] self-center cursor-pointer"
              @click="showManualInput = !showManualInput"
            >
              {{ showManualInput ? '收起手动授权码输入' : '改为粘贴回调链接 / 授权码登录' }}
            </button>

            <form
              v-if="showManualInput || hasOpenedBrowser"
              class="flex items-center gap-2 mt-1"
              @submit.prevent="submitManualCode"
            >
              <input
                v-model="manualCode"
                type="text"
                placeholder="looseleaf://auth/callback?... 或授权码"
                class="flex-1 bg-[var(--paper-subtle)] border border-[var(--border-subtle)] rounded-lg px-3 py-1.5 text-[12px] font-mono-tabular text-[var(--ink-primary)]"
              />
              <button
                type="submit"
                :disabled="!manualCode.trim() || appStore.isConfirmingCode"
                class="px-3 py-1.5 rounded-lg bg-[var(--ink-primary)] text-[var(--paper)] text-[12px] font-medium flex items-center gap-1 disabled:opacity-40 cursor-pointer"
              >
                <Check class="w-3.5 h-3.5" />
                <span>确认</span>
              </button>
            </form>
          </div>

          <p
            v-if="authError || appStore.errorBanner"
            class="text-[12px] text-[var(--accent-warm)] bg-[var(--accent-warm-soft)] px-3 py-2 rounded-lg text-center"
          >
            {{ authError || appStore.errorBanner }}
          </p>
        </template>
      </div>
    </div>
  </div>
</template>
