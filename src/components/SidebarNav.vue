<script setup lang="ts">
import { computed } from 'vue'
import {
  BookOpen,
  Camera,
  Coffee,
  CreditCard,
  Film,
  Image as ImageIcon,
  Map as MapIcon,
  Monitor,
  Moon,
  PanelLeftClose,
  Plus,
  Search,
  Settings,
  Sparkles,
  Sun,
} from 'lucide-vue-next'
import {
  activeInstallmentsCount,
  appStore,
  categoryEntriesCount,
  selectSpace,
  setThemeMode,
  toggleSidebar,
  totalGalleryCount,
  triggerPrimaryCreate,
  wantingWishesCount,
} from '../stores/appStore'
import type { EntryCategory, ThemeMode } from '../types/api'
import { beijingDateParts, formatEditorialDateBadge } from '../utils/format'

const todayStamp = computed(() => {
  const parts = beijingDateParts()
  const badge = formatEditorialDateBadge(new Date().toISOString())
  return `${badge.monthShort} ${String(parts.day).padStart(2, '0')} · ${parts.year}`
})

const galleryMuseums: {
  id: EntryCategory
  label: string
  colorVar: string
  icon: typeof Camera
}[] = [
  { id: 'photography', label: '摄影', colorVar: 'var(--tag-photography)', icon: Camera },
  { id: 'travel', label: '旅途', colorVar: 'var(--tag-travel)', icon: MapIcon },
  { id: 'still_life', label: '静物', colorVar: 'var(--tag-still-life)', icon: Coffee },
  { id: 'motion', label: '影像', colorVar: 'var(--tag-motion)', icon: Film },
]

function cycleTheme() {
  const order: ThemeMode[] = ['system', 'light', 'dark']
  const next = order[(order.indexOf(appStore.themeMode) + 1) % order.length]
  setThemeMode(next)
}

function themeLabel(mode: ThemeMode): string {
  if (mode === 'light') return '暖色棉纸'
  if (mode === 'dark') return '暗房安全灯'
  return '跟随系统'
}
</script>

<template>
  <aside
    class="shrink-0 h-full flex flex-col select-none transition-[width,opacity] duration-200 overflow-hidden"
    :class="appStore.sidebarCollapsed ? 'w-0 opacity-0 pointer-events-none' : 'w-[224px] opacity-100 px-3 pb-3'"
    aria-label="主导航"
  >
    <!-- macOS 交通灯避让拖拽区 + 收起侧栏 -->
    <div data-tauri-drag-region class="tauri-drag h-11 shrink-0 flex items-center justify-end">
      <button
        type="button"
        class="p-1.5 rounded-lg text-[var(--ink-muted)] hover:text-[var(--ink-primary)] hover:bg-[var(--paper-subtle)] transition-colors cursor-pointer"
        title="收起侧栏 (⌘\)"
        aria-label="收起侧栏"
        @click="toggleSidebar"
      >
        <PanelLeftClose class="w-4 h-4" />
      </button>
    </div>

    <!-- 刊头与主操作 -->
    <div class="px-1.5 pb-4 flex flex-col gap-3">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0">
          <div class="font-serif-editorial text-[20px] font-semibold tracking-tight text-[var(--ink-primary)] leading-tight truncate">
            {{ appStore.siteConfig.site_name || '散页' }}
          </div>
          <div class="font-mono-tabular text-[10px] tracking-[0.14em] text-[var(--ink-muted)] mt-0.5">
            {{ todayStamp }}
          </div>
        </div>

        <button
          type="button"
          class="w-8 h-8 shrink-0 rounded-xl bg-[var(--accent-warm)] text-white flex items-center justify-center shadow-xs hover:opacity-92 active:scale-[0.96] transition-all cursor-pointer"
          title="快速新建 (⌘N)"
          aria-label="快速新建"
          @click="triggerPrimaryCreate"
        >
          <Plus class="w-4 h-4" />
        </button>
      </div>

      <!-- 全库聚光灯搜索胶囊 -->
      <button
        type="button"
        class="w-full px-3 py-1.5 rounded-xl bg-[var(--paper-subtle)]/90 border border-[var(--border-subtle)] hover:border-[var(--border-divider)] flex items-center justify-between gap-2 text-[12px] text-[var(--ink-muted)] transition-colors cursor-pointer"
        @click="appStore.showGlobalSearch = true"
      >
        <span class="inline-flex items-center gap-2">
          <Search class="w-3.5 h-3.5" />
          <span>搜索全库…</span>
        </span>
        <kbd class="font-mono-tabular text-[10px] px-1.5 py-0.5 rounded bg-[var(--paper-elevated)]/80 text-[var(--ink-muted)]">
          ⌘K
        </kbd>
      </button>
    </div>

    <nav class="flex-1 overflow-y-auto paper-scroll flex flex-col gap-5 px-0.5">
      <!-- 四大核心空间 -->
      <section class="flex flex-col gap-1">
        <button
          type="button"
          class="space-item"
          :class="appStore.activeSpace === 'journal' ? 'space-item-active' : 'space-item-idle'"
          @click="selectSpace('journal')"
        >
          <BookOpen class="w-4 h-4 shrink-0" :class="appStore.activeSpace === 'journal' ? 'text-[var(--accent-warm)]' : 'text-[var(--ink-secondary)]'" />
          <span class="flex-1 text-left">散页手记</span>
          <span class="space-count">{{ appStore.entries.length }}</span>
        </button>

        <button
          type="button"
          class="space-item"
          :class="appStore.activeSpace === 'gallery' ? 'space-item-active' : 'space-item-idle'"
          @click="selectSpace('gallery', { galleryCategory: 'all' })"
        >
          <ImageIcon class="w-4 h-4 shrink-0" :class="appStore.activeSpace === 'gallery' ? 'text-[var(--accent-warm)]' : 'text-[var(--ink-secondary)]'" />
          <span class="flex-1 text-left">影像画廊</span>
          <span class="space-count">{{ totalGalleryCount }}</span>
        </button>

        <button
          type="button"
          class="space-item"
          :class="appStore.activeSpace === 'ledger' ? 'space-item-active' : 'space-item-idle'"
          @click="selectSpace('ledger')"
        >
          <CreditCard class="w-4 h-4 shrink-0" :class="appStore.activeSpace === 'ledger' ? 'text-[var(--accent-warm)]' : 'text-[var(--ink-secondary)]'" />
          <span class="flex-1 text-left">收支账本</span>
          <span v-if="activeInstallmentsCount > 0" class="space-count text-[var(--accent-warm)]">
            {{ activeInstallmentsCount }} 分期
          </span>
          <span v-else class="space-count">{{ appStore.transactions.length }}</span>
        </button>

        <button
          type="button"
          class="space-item"
          :class="appStore.activeSpace === 'wishlist' ? 'space-item-active' : 'space-item-idle'"
          @click="selectSpace('wishlist')"
        >
          <Sparkles class="w-4 h-4 shrink-0" :class="appStore.activeSpace === 'wishlist' ? 'text-[var(--accent-warm)]' : 'text-[var(--ink-secondary)]'" />
          <span class="flex-1 text-left">心愿图鉴</span>
          <span v-if="wantingWishesCount > 0" class="space-count">{{ wantingWishesCount }}</span>
        </button>
      </section>

      <!-- 画廊展区直达 -->
      <section class="flex flex-col gap-1 pt-2 border-t border-[var(--border-subtle)]">
        <div class="px-2.5 pb-1 text-[10.5px] font-semibold tracking-[0.12em] text-[var(--ink-muted)]">
          画廊分馆
        </div>

        <button
          v-for="item in galleryMuseums"
          :key="item.id"
          type="button"
          class="space-subitem"
          :class="
            appStore.activeSpace === 'gallery' && appStore.galleryCategory === item.id
              ? 'bg-[var(--paper-elevated)] text-[var(--ink-primary)] font-medium shadow-xs'
              : 'text-[var(--ink-secondary)] hover:bg-[var(--paper)]/60 hover:text-[var(--ink-primary)]'
          "
          @click="selectSpace('gallery', { galleryCategory: item.id })"
        >
          <component :is="item.icon" class="w-3.5 h-3.5 shrink-0" :style="{ color: item.colorVar }" />
          <span class="flex-1 text-left">{{ item.label }}</span>
          <span v-if="categoryEntriesCount(item.id) > 0" class="font-mono-tabular text-[11px] text-[var(--ink-muted)]">
            {{ categoryEntriesCount(item.id) }}
          </span>
        </button>
      </section>
    </nav>

    <!-- 底栏主理人 + 主题 + 设置 -->
    <div class="shrink-0 pt-2.5 mt-2 border-t border-[var(--border-subtle)] flex items-center gap-1.5 px-1">
      <div class="flex-1 min-w-0 flex items-center gap-2">
        <span
          class="w-2 h-2 rounded-full shrink-0"
          :class="appStore.isLoading ? 'bg-[var(--accent-warm)] animate-pulse' : 'bg-[var(--accent-moss)]'"
        />
        <span class="text-[12px] text-[var(--ink-secondary)] truncate">
          {{ appStore.profile.name || appStore.accountName || (appStore.isLoading ? '同步中…' : '已连接中枢') }}
        </span>
      </div>

      <button
        type="button"
        class="p-1.5 rounded-lg text-[var(--ink-secondary)] hover:bg-[var(--paper-elevated)] hover:text-[var(--ink-primary)] transition-colors cursor-pointer"
        :title="`切换主题（当前：${themeLabel(appStore.themeMode)}）`"
        :aria-label="`切换主题，当前为${themeLabel(appStore.themeMode)}`"
        @click="cycleTheme"
      >
        <Sun v-if="appStore.themeMode === 'light'" class="w-3.5 h-3.5" />
        <Moon v-else-if="appStore.themeMode === 'dark'" class="w-3.5 h-3.5" />
        <Monitor v-else class="w-3.5 h-3.5" />
      </button>

      <button
        type="button"
        class="p-1.5 rounded-lg transition-colors cursor-pointer"
        :class="
          appStore.activeSpace === 'settings'
            ? 'bg-[var(--paper-elevated)] text-[var(--accent-warm)] shadow-xs'
            : 'text-[var(--ink-secondary)] hover:bg-[var(--paper-elevated)] hover:text-[var(--ink-primary)]'
        "
        title="偏好与设备设置 (⌘,)"
        aria-label="打开偏好与设备设置"
        @click="selectSpace('settings')"
      >
        <Settings class="w-3.5 h-3.5" />
      </button>
    </div>
  </aside>
</template>

<style scoped>
@reference "../styles/main.css";

.space-item {
  @apply w-full flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-[13.5px] transition-all duration-100 cursor-pointer;
}
.space-item-idle {
  @apply text-[var(--ink-primary)] hover:bg-[var(--paper)]/65;
}
.space-item-active {
  @apply bg-[var(--paper-elevated)] text-[var(--ink-primary)] font-semibold;
  box-shadow: var(--shadow-card);
}
.space-count {
  @apply font-mono-tabular text-[11px] text-[var(--ink-muted)];
}
.space-subitem {
  @apply w-full flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg text-[12.5px] transition-all duration-100 cursor-pointer;
}
</style>
