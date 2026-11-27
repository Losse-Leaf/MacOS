<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { BookOpen, Lock, RefreshCw, Search, X } from 'lucide-vue-next'
import { api } from '../services/api'
import {
  appStore,
  displayedStreamEntries,
  mediaUrl,
  refreshAll,
  remoteOnlySearchEntries,
  selectEntry,
  selectSpace,
  type JournalFilter,
} from '../stores/appStore'
import {
  compactListDate,
  deriveDisplayTitle,
  deriveExcerpt,
  formatEditorialDateBadge,
  groupEntriesByMonth,
} from '../utils/format'

const visibleLimit = ref(200)
const filterInputRef = ref<HTMLInputElement | null>(null)
let searchDebounce: ReturnType<typeof setTimeout> | null = null

const limitedEntries = computed(() => displayedStreamEntries.value.slice(0, visibleLimit.value))
const monthGroups = computed(() => groupEntriesByMonth(limitedEntries.value))
const remoteHits = computed(() => remoteOnlySearchEntries.value)
const hasMore = computed(() => displayedStreamEntries.value.length > limitedEntries.value.length)

const filterTabs = computed<{ id: JournalFilter; label: string }[]>(() => {
  const base: { id: JournalFilter; label: string }[] = [
    { id: 'all', label: '全部' },
    { id: 'daily', label: '日常' },
    { id: 'private', label: '私密' },
  ]
  if (appStore.onThisDayEntries.length > 0) {
    base.push({ id: 'on_this_day', label: '那年今日' })
  }
  return base
})

function onSearchInput(val: string) {
  appStore.searchQuery = val
  if (searchDebounce) clearTimeout(searchDebounce)
  const trimmed = val.trim()
  if (!trimmed) {
    appStore.remoteSearchResult = null
    appStore.isSearchingRemote = false
    return
  }
  searchDebounce = setTimeout(async () => {
    appStore.isSearchingRemote = true
    try {
      appStore.remoteSearchResult = await api.searchGlobalArchive(trimmed, 25)
    } catch {
      appStore.remoteSearchResult = null
    } finally {
      appStore.isSearchingRemote = false
    }
  }, 180)
}

function handleFocusEvent() {
  filterInputRef.value?.focus()
  filterInputRef.value?.select()
}

onMounted(() => {
  window.addEventListener('looseleaf-focus-filter', handleFocusEvent)
})

onBeforeUnmount(() => {
  window.removeEventListener('looseleaf-focus-filter', handleFocusEvent)
  if (searchDebounce) clearTimeout(searchDebounce)
})
</script>

<template>
  <div class="h-full flex flex-col bg-[var(--paper)] border-r border-[var(--border-subtle)]">
    <!-- 一体化编辑室目录头部 -->
    <div
      data-tauri-drag-region
      class="tauri-drag shrink-0 px-4 pt-3.5 pb-3 border-b border-[var(--border-subtle)] flex flex-col gap-3"
      :class="appStore.sidebarCollapsed ? 'pl-[124px]' : ''"
    >
      <div class="flex items-center justify-between gap-2">
        <div class="flex items-baseline gap-2">
          <h1 class="font-serif-editorial text-[19px] font-semibold text-[var(--ink-primary)] tracking-tight">
            散页
          </h1>
          <span class="font-mono-tabular text-[11px] text-[var(--ink-muted)]">
            {{ displayedStreamEntries.length }} 篇
          </span>
        </div>

        <button
          type="button"
          class="p-1.5 rounded-lg text-[var(--ink-muted)] hover:text-[var(--ink-primary)] hover:bg-[var(--paper-subtle)] transition-colors cursor-pointer"
          :disabled="appStore.isLoading"
          title="同步中枢 (⌘R)"
          aria-label="同步中枢"
          @click="refreshAll(false)"
        >
          <RefreshCw class="w-3.5 h-3.5" :class="{ 'animate-spin text-[var(--accent-warm)]': appStore.isLoading }" />
        </button>
      </div>

      <!-- 胶囊切换栏 -->
      <div class="flex items-center gap-1 overflow-x-auto">
        <button
          v-for="tab in filterTabs"
          :key="tab.id"
          type="button"
          class="px-2.5 py-1 rounded-lg text-[12px] transition-colors cursor-pointer whitespace-nowrap"
          :class="
            appStore.journalFilter === tab.id
              ? 'bg-[var(--paper-subtle)] text-[var(--ink-primary)] font-semibold'
              : 'text-[var(--ink-muted)] hover:text-[var(--ink-primary)]'
          "
          @click="selectSpace('journal', { journalFilter: tab.id })"
        >
          {{ tab.label }}
        </button>
      </div>

      <!-- 内联筛选 -->
      <div class="relative flex items-center">
        <Search class="w-3.5 h-3.5 text-[var(--ink-muted)] absolute left-2.5 pointer-events-none" />
        <input
          ref="filterInputRef"
          :value="appStore.searchQuery"
          type="search"
          placeholder="筛选当前列表… (⌘F)"
          aria-label="筛选散页"
          class="w-full pl-8 pr-7 py-1.5 rounded-lg bg-[var(--paper-subtle)]/80 border border-transparent focus:border-[var(--border-divider)] focus:bg-[var(--paper-elevated)] text-[12px] text-[var(--ink-primary)] placeholder:text-[var(--ink-muted)] transition-colors"
          @input="onSearchInput(($event.target as HTMLInputElement).value)"
        />
        <button
          v-if="appStore.searchQuery"
          type="button"
          class="absolute right-2 p-0.5 rounded text-[var(--ink-muted)] hover:text-[var(--ink-primary)] cursor-pointer"
          aria-label="清空筛选"
          @click="onSearchInput('')"
        >
          <X class="w-3 h-3" />
        </button>
      </div>
    </div>

    <!-- 空态 -->
    <div
      v-if="displayedStreamEntries.length === 0 && remoteHits.length === 0"
      class="flex-1 flex flex-col items-center justify-center px-6 text-center gap-2.5"
    >
      <RefreshCw
        v-if="appStore.isLoading || appStore.isSearchingRemote"
        class="w-6 h-6 animate-spin text-[var(--ink-muted)]"
      />
      <Search v-else-if="appStore.searchQuery.trim()" class="w-7 h-7 text-[var(--ink-muted)]" />
      <BookOpen v-else class="w-7 h-7 text-[var(--ink-muted)]" />

      <div class="font-serif-editorial text-[16px] font-medium text-[var(--ink-primary)]">
        {{
          appStore.isLoading
            ? '正在翻阅档案…'
            : appStore.searchQuery.trim()
              ? '没有匹配的散页'
              : '这里尚无散页记录'
        }}
      </div>
      <p class="text-[12px] text-[var(--ink-muted)] leading-relaxed">
        {{
          appStore.searchQuery.trim()
            ? '试试更换关键词，或按 ⌘K 检索全库'
            : '写下日常想法、定格照片，或按 ⌘N 记一笔'
        }}
      </p>
      <button
        v-if="!appStore.searchQuery.trim() && !appStore.isLoading"
        type="button"
        class="mt-1 px-3.5 py-1.5 rounded-lg bg-[var(--accent-warm)] text-white text-[12.5px] font-medium cursor-pointer hover:opacity-92"
        @click="appStore.showNewEntryModal = true"
      >
        写一篇新散页
      </button>
    </div>

    <!-- 按月分组杂志目录流 -->
    <div v-else class="flex-1 overflow-y-auto paper-scroll px-2.5 py-2.5 flex flex-col gap-4">
      <section v-for="group in monthGroups" :key="group.id" class="flex flex-col gap-1.5">
        <h3
          class="sticky top-0 z-10 px-2 py-1 text-[10.5px] font-mono-tabular tracking-[0.08em] uppercase text-[var(--ink-muted)] bg-[var(--paper)]/92 backdrop-blur-xs"
        >
          {{ group.title }}
        </h3>

        <button
          v-for="entry in group.entries"
          :key="entry.id"
          type="button"
          class="journal-item"
          :class="appStore.selectedEntryId === entry.id ? 'journal-item-active' : 'journal-item-idle'"
          @click="selectEntry(entry.id)"
        >
          <!-- 左侧竖排日历日章 -->
          <div class="w-8 shrink-0 flex flex-col items-center pt-0.5 text-center">
            <span
              class="font-serif-editorial text-[17px] font-semibold leading-none"
              :class="appStore.selectedEntryId === entry.id ? 'text-[var(--accent-warm)]' : 'text-[var(--ink-primary)]'"
            >
              {{ formatEditorialDateBadge(entry.occurred_at).day }}
            </span>
            <span class="text-[10px] text-[var(--ink-muted)] mt-1">
              {{ formatEditorialDateBadge(entry.occurred_at).weekday }}
            </span>
          </div>

          <div class="flex-1 min-w-0 flex flex-col gap-1 text-left">
            <div class="flex items-center gap-1.5">
              <span class="text-[13.5px] font-semibold text-[var(--ink-primary)] truncate leading-snug">
                {{ deriveDisplayTitle(entry) }}
              </span>
              <Lock v-if="entry.is_private" class="w-3 h-3 text-[var(--accent-warm)] shrink-0" />
            </div>

            <p
              v-if="deriveExcerpt(entry)"
              class="text-[12px] text-[var(--ink-secondary)] line-clamp-2 leading-relaxed"
            >
              {{ deriveExcerpt(entry) }}
            </p>

            <div class="flex items-center gap-1.5 text-[11px] text-[var(--ink-muted)] pt-0.5">
              <span class="font-mono-tabular">{{ compactListDate(entry.occurred_at) }}</span>
              <span v-if="entry.location?.trim()" class="truncate">· {{ entry.location.trim() }}</span>
            </div>
          </div>

          <div
            v-if="entry.attachments.length > 0"
            class="relative w-[68px] h-[52px] shrink-0 rounded-lg overflow-hidden bg-[var(--paper-subtle)] border border-[var(--border-subtle)]"
          >
            <img
              :src="mediaUrl(entry.attachments[0].thumbnail_url || entry.attachments[0].url)"
              :alt="entry.attachments[0].original_filename || '散页配图'"
              loading="lazy"
              class="w-full h-full object-cover"
            />
            <span
              v-if="entry.attachments.length > 1"
              class="absolute bottom-1 right-1 px-1.5 py-0.5 rounded-full bg-black/65 text-white font-mono-tabular text-[9.5px] font-semibold leading-none"
            >
              +{{ entry.attachments.length - 1 }}
            </span>
          </div>
        </button>
      </section>

      <button
        v-if="hasMore"
        type="button"
        class="mx-auto my-2 px-3 py-1.5 rounded-lg text-[11.5px] font-mono-tabular text-[var(--ink-secondary)] bg-[var(--paper-subtle)] hover:bg-[var(--paper-elevated)] cursor-pointer"
        @click="visibleLimit += 200"
      >
        展开更多（{{ limitedEntries.length }} / {{ displayedStreamEntries.length }}）
      </button>

      <section v-if="remoteHits.length > 0" class="flex flex-col gap-1.5 pt-2 border-t border-[var(--border-subtle)]">
        <h3 class="px-2 py-1 text-[10.5px] font-semibold text-[var(--ink-muted)]">
          远端历史归档（{{ remoteHits.length }}）
        </h3>

        <button
          v-for="entry in remoteHits"
          :key="`remote-${entry.id}`"
          type="button"
          class="journal-item"
          :class="appStore.selectedEntryId === entry.id ? 'journal-item-active' : 'journal-item-idle'"
          @click="selectEntry(entry.id)"
        >
          <div class="flex-1 min-w-0 flex flex-col gap-1 text-left">
            <div class="text-[13.5px] font-semibold text-[var(--ink-primary)] truncate">
              {{ deriveDisplayTitle(entry) }}
            </div>
            <p v-if="deriveExcerpt(entry)" class="text-[12px] text-[var(--ink-secondary)] line-clamp-2">
              {{ deriveExcerpt(entry) }}
            </p>
            <div class="text-[11px] text-[var(--ink-muted)] font-mono-tabular">
              {{ compactListDate(entry.occurred_at) }}
            </div>
          </div>
        </button>
      </section>
    </div>
  </div>
</template>

<style scoped>
@reference "../styles/main.css";

.journal-item {
  @apply relative w-full flex items-start gap-2.5 p-2.5 rounded-xl border transition-all duration-100 cursor-pointer;
}
.journal-item-idle {
  @apply border-transparent bg-transparent hover:bg-[var(--paper-subtle)]/75;
}
.journal-item-active {
  @apply bg-[var(--paper-elevated)] border-[var(--border-divider)];
  box-shadow: var(--shadow-card);
}
</style>
