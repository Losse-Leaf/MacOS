<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { Check, Laptop, LogOut, Monitor, Moon, RefreshCw, Sun, Trash2, User } from 'lucide-vue-next'
import { api, isValidHubUrl } from '../services/api'
import {
  appStore,
  logout,
  refreshAll,
  refreshTrustedDevices,
  setHubUrl,
  setThemeMode,
  showToast,
} from '../stores/appStore'
import type { ThemeMode } from '../types/api'
import { parseOccurredDate } from '../utils/format'

const draftHubUrl = ref(appStore.hubUrl)
const profileName = ref(appStore.profile.name)
const profileCity = ref(appStore.profile.current_city || appStore.profile.location)
const profileMotto = ref(appStore.profile.motto)
const profileBio = ref(appStore.profile.bio)
const profileDirty = ref(false)
const savingProfile = ref(false)

watch(
  () => appStore.hubUrl,
  (url) => {
    draftHubUrl.value = url
  },
)

watch(
  () => appStore.profile,
  (prof) => {
    if (profileDirty.value) return
    profileName.value = prof.name ?? ''
    profileCity.value = prof.current_city || prof.location || ''
    profileMotto.value = prof.motto ?? ''
    profileBio.value = prof.bio ?? ''
  },
  { deep: true },
)

onMounted(() => {
  void refreshTrustedDevices()
})

async function saveHub() {
  if (!isValidHubUrl(draftHubUrl.value)) {
    showToast('服务器地址必须以 http:// 或 https:// 开头', true)
    return
  }
  await setHubUrl(draftHubUrl.value)
}

async function saveProfile() {
  savingProfile.value = true
  try {
    appStore.profile = await api.updateCuratorProfile({
      name: profileName.value.trim(),
      current_city: profileCity.value.trim(),
      motto: profileMotto.value.trim(),
      bio: profileBio.value.trim(),
    })
    profileDirty.value = false
    showToast('主理人档案已更新')
  } catch (err) {
    showToast(err instanceof Error ? err.message : '保存档案失败', true)
  } finally {
    savingProfile.value = false
  }
}

function revokeDevice(id: string, name: string) {
  appStore.confirmRequest = {
    title: '吊销设备会话？',
    message: `吊销后「${name}」需要重新通过 Vesper Auth 登录才能访问中枢。`,
    confirmText: '确认吊销',
    danger: true,
    onConfirm: async () => {
      await api.revokeDevice(id)
      showToast('已吊销该设备访问权')
      await refreshTrustedDevices()
    },
  }
}

function confirmLogout() {
  appStore.confirmRequest = {
    title: '退出当前账号？',
    message: '退出后将清除本机访问令牌并返回登录门禁页。',
    confirmText: '退出登录',
    danger: true,
    onConfirm: async () => {
      await logout()
    },
  }
}
</script>

<template>
  <div class="flex-1 min-h-0 flex flex-col bg-[var(--paper)]">
    <header
      data-tauri-drag-region
      class="tauri-drag shrink-0 px-8 pt-5 pb-4 border-b border-[var(--border-subtle)] flex items-baseline gap-3"
      :class="appStore.sidebarCollapsed ? 'pl-[112px]' : ''"
    >
      <h1 class="font-serif-editorial text-[24px] font-semibold tracking-tight text-[var(--ink-primary)]">
        偏好与连接
      </h1>
      <span class="text-[12px] text-[var(--ink-muted)] font-mono-tabular">
        {{ appStore.accountName || appStore.accountEmail || appStore.hubUrl }}
      </span>
    </header>

    <div class="flex-1 overflow-y-auto paper-scroll px-8 py-7">
      <div class="max-w-[740px] mx-auto flex flex-col gap-6 pb-10">
        <!-- 外观主题 -->
        <section class="settings-card">
          <h2 class="settings-title">外观与材质</h2>
          <div class="grid grid-cols-3 gap-2.5">
            <button
              v-for="item in [
                { id: 'system', label: '跟随系统', icon: Monitor },
                { id: 'light', label: '暖色棉纸', icon: Sun },
                { id: 'dark', label: '暗房安全灯', icon: Moon },
              ] as { id: ThemeMode; label: string; icon: typeof Monitor }[]"
              :key="item.id"
              type="button"
              class="flex items-center justify-center gap-2 py-2.5 rounded-xl border text-[13px] transition-colors cursor-pointer"
              :class="
                appStore.themeMode === item.id
                  ? 'bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/45 text-[var(--accent-warm)] font-medium'
                  : 'bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)] hover:text-[var(--ink-primary)]'
              "
              @click="setThemeMode(item.id)"
            >
              <component :is="item.icon" class="w-4 h-4" />
              <span>{{ item.label }}</span>
            </button>
          </div>
        </section>

        <!-- 主理人档案 -->
        <section class="settings-card">
          <div class="flex items-center justify-between">
            <h2 class="settings-title flex items-center gap-2">
              <User class="w-4 h-4 text-[var(--accent-warm)]" />
              <span>主理人档案</span>
            </h2>
            <span class="text-[11.5px] text-[var(--ink-muted)]">全端同步展示</span>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
              <span>称呼</span>
              <input v-model="profileName" type="text" class="settings-input" @input="profileDirty = true" />
            </label>
            <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
              <span>当前常驻城市</span>
              <input v-model="profileCity" type="text" class="settings-input" @input="profileDirty = true" />
            </label>
          </div>

          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>一句话座右铭</span>
            <input v-model="profileMotto" type="text" class="settings-input" @input="profileDirty = true" />
          </label>

          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>个人简介</span>
            <textarea v-model="profileBio" rows="3" class="settings-input" @input="profileDirty = true" />
          </label>

          <div class="flex justify-end">
            <button
              type="button"
              :disabled="savingProfile"
              class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-[var(--accent-warm)] text-white text-[12.5px] font-medium cursor-pointer disabled:opacity-50"
              @click="saveProfile"
            >
              <Check class="w-3.5 h-3.5" />
              <span>{{ savingProfile ? '保存中…' : '保存档案' }}</span>
            </button>
          </div>
        </section>

        <!-- 中枢与设备 -->
        <section class="settings-card">
          <div class="flex items-center justify-between">
            <h2 class="settings-title flex items-center gap-2">
              <Laptop class="w-4 h-4 text-[var(--accent-moss)]" />
              <span>同步中枢与授信设备</span>
            </h2>
            <button
              type="button"
              class="inline-flex items-center gap-1 text-[12px] text-[var(--ink-secondary)] hover:text-[var(--ink-primary)] cursor-pointer"
              @click="refreshTrustedDevices"
            >
              <RefreshCw class="w-3.5 h-3.5" />
              <span>刷新列表</span>
            </button>
          </div>

          <form class="flex items-center gap-2" @submit.prevent="saveHub">
            <input
              v-model="draftHubUrl"
              type="url"
              class="settings-input flex-1 font-mono-tabular"
              aria-label="中枢地址"
            />
            <button
              type="submit"
              class="px-3 py-2 rounded-xl border border-[var(--border-subtle)] bg-[var(--paper-subtle)] text-[12.5px] hover:border-[var(--border-divider)] cursor-pointer"
            >
              切换地址
            </button>
            <button
              type="button"
              class="px-3 py-2 rounded-xl border border-[var(--border-subtle)] bg-[var(--paper-subtle)] text-[12.5px] hover:border-[var(--border-divider)] cursor-pointer"
              @click="refreshAll(false)"
            >
              立即同步
            </button>
          </form>

          <div class="divide-y divide-[var(--border-subtle)] rounded-xl border border-[var(--border-subtle)] overflow-hidden">
            <div
              v-for="dev in appStore.trustedDevices"
              :key="dev.device_id"
              class="px-3.5 py-2.5 bg-[var(--paper)]/60 flex items-center justify-between gap-3"
            >
              <div class="min-w-0">
                <div class="flex items-center gap-2 text-[13px] font-medium">
                  <span class="truncate">{{ dev.name }}</span>
                  <span
                    v-if="dev.is_current || dev.device_id === appStore.deviceId"
                    class="px-1.5 py-0.5 rounded bg-[var(--accent-moss-soft)] text-[var(--accent-moss)] text-[10.5px]"
                  >
                    当前设备
                  </span>
                </div>
                <div class="text-[11.5px] font-mono-tabular text-[var(--ink-muted)]">
                  {{ dev.platform }} · 最近活跃 {{ parseOccurredDate(dev.last_active_at).dotDateTime || dev.last_active_at }}
                </div>
              </div>

              <button
                v-if="!dev.is_current && dev.device_id !== appStore.deviceId"
                type="button"
                class="p-1.5 rounded-lg text-[var(--ink-muted)] hover:text-[var(--accent-warm)] hover:bg-[var(--accent-warm-soft)] cursor-pointer"
                aria-label="吊销设备"
                @click="revokeDevice(dev.device_id, dev.name)"
              >
                <Trash2 class="w-4 h-4" />
              </button>
            </div>
            <div v-if="appStore.trustedDevices.length === 0" class="px-3.5 py-4 text-[12px] text-[var(--ink-muted)]">
              暂无设备信息
            </div>
          </div>

          <div class="pt-2 flex items-center justify-between border-t border-[var(--border-subtle)]">
            <div class="text-[12px] text-[var(--ink-muted)]">
              当前账号：{{ appStore.accountName || appStore.accountEmail || '已配对主理人' }}
            </div>
            <button
              type="button"
              class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] text-[12.5px] font-medium hover:opacity-90 cursor-pointer"
              @click="confirmLogout"
            >
              <LogOut class="w-3.5 h-3.5" />
              <span>退出账号登录</span>
            </button>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<style scoped>
@reference "../styles/main.css";
.settings-card {
  @apply p-5 rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] flex flex-col gap-3.5;
  box-shadow: var(--shadow-card);
}
.settings-title {
  @apply font-serif-editorial text-[16px] font-semibold text-[var(--ink-primary)];
}
.settings-input {
  @apply px-3 py-2 rounded-xl bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[13px] text-[var(--ink-primary)];
}
</style>
