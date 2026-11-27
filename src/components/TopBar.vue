<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Plus, RefreshCw, Search, X } from 'lucide-vue-next'
import { api } from '../services/api'
import {
  activeInstallmentsCount,
  appStore,
  destinationTitle,
  displayedStreamEntries,
  isStreamDestination,
  refreshAll,
  triggerPrimaryCreate,
  wantingWishesCount,
} from '../stores/appStore'

const searchInputRef = ref<HTMLInputElement | null>(null)
let debounceTimer: ReturnType<typeof setTimeout> | null = null

const title = computed(() => destinationTitle(appStore.destination))

const subtitle = computed(() => {
  const dest = appStore.destination
  if (isStreamDestination(dest)) {
    return `${displayedStreamEntries.value.length} 篇`
  }
  if (dest.kind === 'ledger') {
    return `${appStore.selectedLedgerYear}年${appStore.selectedLedgerMonth}月`
  }
  if (dest.kind === 'installments') {
    return `${activeInstallmentsCount.value} 个进行中`
  }
  if (dest.kind === 'wishlist') {
    return `${wantingWishesCount.value} 个待实现`
  }
  return appStore.accountName || appStore.accountEmail || appStore.hubUrl
})

const searchPlaceholder = computed(() => {
  switch (appStore.destination.kind) {
    case 'ledger':
      return '筛选流水账目…'
    case 'installments':
      return '筛选分期计划…'
    case 'wishlist':
      return '筛选心愿清单…'
    default:
      return '搜索散页或远端归档… (⌘F)'
  }
})

const createLabel = computed(() => {
  switch (appStore.destination.kind) {
    case 'ledger':
      return '记一笔'
    case 'wishlist':
      return '许下心愿'
    default:
      return '写散页'
  }
})

watch(
  () => appStore.searchQuery,
  (val) => {
    if (debounceTimer) clearTimeout(debounceTimer)
    const trimmed = val.trim()
    if (!trimmed) {
      appStore.remoteSearchResult = null
      appStore.isSearchingRemote = false
      return
    }
    if (!isStreamDestination(appStore.destination)) return
    debounceTimer = setTimeout(async () => {
      appStore.isSearchingRemote = true
      try {
        appStore.remoteSearchResult = await api.searchGlobalArchive(trimmed, 25)
      } catch {
        appStore.remoteSearchResult = null
      } finally {
        appStore.isSearchingRemote = false
      }
    }, 180)
  },
)

function focusSearch() {
  searchInputRef.value?.focus()
  searchInputRef.value?.select()
}

defineExpose({ focusSearch })
</script>

<template>
  <header
    data-tauri-drag-region
    class="tauri-drag h-12 shrink-0 px-5 border-b border-[var(--border-subtle)] bg-[var(--paper)] flex items-center justify-between gap-4"
  >
    <div class="flex items-baseline gap-2.5 min-w-0">
      <h1 class="font-serif-editorial text-[16px] font-semibold text-[var(--ink-primary)] truncate">
        {{ title }}
      </h1>
      <span class="text-[12px] text-[var(--ink-muted)] font-mono-tabular truncate">
        {{ subtitle }}
      </span>
    </div>

    <div class="flex items-center gap-2 shrink-0">
      <!-- 紧凑工具栏检索框 -->
      <div
        v-if="appStore.destination.kind !== 'settings'"
        class="relative flex items-center w-56 focus-within:w-68 transition-all duration-150"
      >
        <Search class="w-3.5 h-3.5 text-[var(--ink-muted)] absolute left-2.5 pointer-events-none" />
        <input
          ref="searchInputRef"
          v-model="appStore.searchQuery"
          type="search"
          :placeholder="searchPlaceholder"
          aria-label="筛选当前视图"
          class="w-full pl-8 pr-7 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-transparent focus:border-[var(--border-divider)] focus:bg-[var(--paper-elevated)] text-[12.5px] text-[var(--ink-primary)] placeholder:text-[var(--ink-muted)] transition-colors"
        />
        <button
          v-if="appStore.searchQuery"
          type="button"
          class="absolute right-2 p-0.5 rounded text-[var(--ink-muted)] hover:text-[var(--ink-primary)] cursor-pointer"
          aria-label="清空搜索"
          @click="appStore.searchQuery = ''"
        >
          <X class="w-3 h-3" />
        </button>
      </div>

      <button
        type="button"
        class="p-1.5 rounded-lg text-[var(--ink-secondary)] hover:bg-[var(--paper-subtle)] hover:text-[var(--ink-primary)] transition-colors disabled:opacity-50 cursor-pointer"
        :disabled="appStore.isLoading"
        title="全量同步中枢 (⌘R)"
        aria-label="全量同步中枢"
        @click="refreshAll(false)"
      >
        <RefreshCw class="w-4 h-4" :class="{ 'animate-spin text-[var(--accent-warm)]': appStore.isLoading }" />
      </button>

      <button
        v-if="appStore.destination.kind !== 'installments' && appStore.destination.kind !== 'settings'"
        type="button"
        class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--accent-warm)] text-white text-[12.5px] font-medium hover:opacity-92 active:scale-[0.98] transition-all cursor-pointer"
        :title="`${createLabel} (⌘N)`"
        @click="triggerPrimaryCreate"
      >
        <Plus class="w-3.5 h-3.5" />
        <span>{{ createLabel }}</span>
      </button>
    </div>
  </header>
</template>
