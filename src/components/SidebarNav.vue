<script setup lang="ts">
import {
  BookOpen,
  CalendarClock,
  Camera,
  Coffee,
  CreditCard,
  FileText,
  Film,
  History,
  Lock,
  Map as MapIcon,
  Monitor,
  Moon,
  Settings,
  Sparkles,
  Sun,
} from 'lucide-vue-next'
import {
  activeInstallmentsCount,
  appStore,
  categoryEntriesCount,
  dailyEntriesCount,
  destinationKey,
  privateEntriesCount,
  selectDestination,
  setThemeMode,
  wantingWishesCount,
} from '../stores/appStore'
import type { SidebarDestination, ThemeMode } from '../types/api'

const galleryItems: {
  id: 'photography' | 'travel' | 'still_life' | 'motion'
  label: string
  colorVar: string
  icon: typeof Camera
}[] = [
  { id: 'photography', label: '摄影', colorVar: 'var(--tag-photography)', icon: Camera },
  { id: 'travel', label: '旅途', colorVar: 'var(--tag-travel)', icon: MapIcon },
  { id: 'still_life', label: '静物', colorVar: 'var(--tag-still-life)', icon: Coffee },
  { id: 'motion', label: '影像', colorVar: 'var(--tag-motion)', icon: Film },
]

function isSelected(dest: SidebarDestination): boolean {
  return destinationKey(appStore.destination) === destinationKey(dest)
}

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
    class="w-[224px] shrink-0 h-full flex flex-col bg-[var(--paper-subtle)] border-r border-[var(--border-subtle)] select-none"
    aria-label="工作台导航栏"
  >
    <!-- macOS 交通灯占位拖拽区 -->
    <div data-tauri-drag-region class="tauri-drag h-11 shrink-0 flex items-center justify-end px-3">
      <span
        v-if="appStore.siteConfig.site_name"
        class="text-[11px] font-medium tracking-wide text-[var(--ink-muted)] truncate max-w-[116px]"
      >
        {{ appStore.siteConfig.site_name }}
      </span>
    </div>

    <nav class="flex-1 overflow-y-auto paper-scroll px-2.5 pb-4 flex flex-col gap-5">
      <!-- 1. 散页 -->
      <section class="flex flex-col gap-0.5">
        <h2 class="px-2.5 pb-1 text-[11px] font-semibold tracking-wider text-[var(--ink-muted)]">
          散页
        </h2>

        <button
          type="button"
          class="nav-item"
          :class="isSelected({ kind: 'all' }) ? 'nav-item-active' : 'nav-item-idle'"
          @click="selectDestination({ kind: 'all' })"
        >
          <BookOpen class="w-4 h-4 shrink-0 text-[var(--accent-warm)]" />
          <span class="flex-1 text-left truncate">全部印记</span>
          <span class="nav-badge">{{ appStore.entries.length }}</span>
        </button>

        <button
          type="button"
          class="nav-item"
          :class="isSelected({ kind: 'daily' }) ? 'nav-item-active' : 'nav-item-idle'"
          @click="selectDestination({ kind: 'daily' })"
        >
          <FileText class="w-4 h-4 shrink-0 text-[var(--accent-moss)]" />
          <span class="flex-1 text-left truncate">日常</span>
          <span v-if="dailyEntriesCount > 0" class="nav-badge">{{ dailyEntriesCount }}</span>
        </button>

        <button
          type="button"
          class="nav-item"
          :class="isSelected({ kind: 'private' }) ? 'nav-item-active' : 'nav-item-idle'"
          @click="selectDestination({ kind: 'private' })"
        >
          <Lock class="w-4 h-4 shrink-0 text-[var(--accent-warm)]" />
          <span class="flex-1 text-left truncate">私密</span>
          <span v-if="privateEntriesCount > 0" class="nav-badge">{{ privateEntriesCount }}</span>
        </button>

        <button
          v-if="appStore.onThisDayEntries.length > 0"
          type="button"
          class="nav-item"
          :class="isSelected({ kind: 'on_this_day' }) ? 'nav-item-active' : 'nav-item-idle'"
          @click="selectDestination({ kind: 'on_this_day' })"
        >
          <History class="w-4 h-4 shrink-0 text-[var(--accent-warm)]" />
          <span class="flex-1 text-left truncate">那年今日</span>
          <span class="nav-badge">{{ appStore.onThisDayEntries.length }}</span>
        </button>
      </section>

      <!-- 2. 画廊 -->
      <section class="flex flex-col gap-0.5">
        <h2 class="px-2.5 pb-1 text-[11px] font-semibold tracking-wider text-[var(--ink-muted)]">
          画廊
        </h2>

        <button
          v-for="item in galleryItems"
          :key="item.id"
          type="button"
          class="nav-item"
          :class="
            isSelected({ kind: 'category', category: item.id }) ? 'nav-item-active' : 'nav-item-idle'
          "
          @click="selectDestination({ kind: 'category', category: item.id })"
        >
          <component :is="item.icon" class="w-4 h-4 shrink-0" :style="{ color: item.colorVar }" />
          <span class="flex-1 text-left truncate">{{ item.label }}</span>
          <span v-if="categoryEntriesCount(item.id) > 0" class="nav-badge">{{
            categoryEntriesCount(item.id)
          }}</span>
        </button>
      </section>

      <!-- 3. 财务与心愿 -->
      <section class="flex flex-col gap-0.5">
        <h2 class="px-2.5 pb-1 text-[11px] font-semibold tracking-wider text-[var(--ink-muted)]">
          财务与心愿
        </h2>

        <button
          type="button"
          class="nav-item"
          :class="isSelected({ kind: 'ledger' }) ? 'nav-item-active' : 'nav-item-idle'"
          @click="selectDestination({ kind: 'ledger' })"
        >
          <CreditCard class="w-4 h-4 shrink-0 text-[var(--spectrum-dining)]" />
          <span class="flex-1 text-left truncate">收支流水</span>
          <span v-if="appStore.transactions.length > 0" class="nav-badge">{{
            appStore.transactions.length
          }}</span>
        </button>

        <button
          type="button"
          class="nav-item"
          :class="isSelected({ kind: 'installments' }) ? 'nav-item-active' : 'nav-item-idle'"
          @click="selectDestination({ kind: 'installments' })"
        >
          <CalendarClock class="w-4 h-4 shrink-0 text-[var(--spectrum-transit)]" />
          <span class="flex-1 text-left truncate">分期计划</span>
          <span v-if="activeInstallmentsCount > 0" class="nav-badge">{{
            activeInstallmentsCount
          }}</span>
        </button>

        <button
          type="button"
          class="nav-item"
          :class="isSelected({ kind: 'wishlist' }) ? 'nav-item-active' : 'nav-item-idle'"
          @click="selectDestination({ kind: 'wishlist' })"
        >
          <Sparkles class="w-4 h-4 shrink-0 text-[var(--spectrum-leisure)]" />
          <span class="flex-1 text-left truncate">心愿清单</span>
          <span v-if="wantingWishesCount > 0" class="nav-badge">{{ wantingWishesCount }}</span>
        </button>
      </section>
    </nav>

    <!-- 底栏状态与外观/设置入口 -->
    <div class="shrink-0 border-t border-[var(--border-subtle)] px-3 py-2.5 flex items-center gap-2">
      <span
        class="w-2 h-2 rounded-full shrink-0"
        :class="appStore.isLoading ? 'bg-[var(--spectrum-study)] animate-pulse' : 'bg-[var(--accent-moss)]'"
      />
      <span class="text-[11.5px] text-[var(--ink-muted)] truncate flex-1">
        {{ appStore.isLoading ? '同步中…' : '中枢就绪' }}
      </span>

      <button
        type="button"
        class="p-1.5 rounded-md text-[var(--ink-secondary)] hover:bg-[var(--paper-elevated)] hover:text-[var(--ink-primary)] transition-colors cursor-pointer"
        :title="`外观主题：${themeLabel(appStore.themeMode)}（点击切换）`"
        :aria-label="`切换外观主题，当前为${themeLabel(appStore.themeMode)}`"
        @click="cycleTheme"
      >
        <Sun v-if="appStore.themeMode === 'light'" class="w-3.5 h-3.5" />
        <Moon v-else-if="appStore.themeMode === 'dark'" class="w-3.5 h-3.5" />
        <Monitor v-else class="w-3.5 h-3.5" />
      </button>

      <button
        type="button"
        class="p-1.5 rounded-md transition-colors cursor-pointer"
        :class="
          isSelected({ kind: 'settings' })
            ? 'bg-[var(--paper-elevated)] text-[var(--accent-warm)] shadow-xs'
            : 'text-[var(--ink-secondary)] hover:bg-[var(--paper-elevated)] hover:text-[var(--ink-primary)]'
        "
        title="偏好与账号设置 (⌘,)"
        aria-label="打开偏好与账号设置"
        @click="selectDestination({ kind: 'settings' })"
      >
        <Settings class="w-3.5 h-3.5" />
      </button>
    </div>
  </aside>
</template>

<style scoped>
@reference "../styles/main.css";

.nav-item {
  @apply relative w-full flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg text-[13px] transition-all duration-100 cursor-pointer;
}

.nav-item-idle {
  @apply text-[var(--ink-primary)] hover:bg-[var(--paper)]/65;
}

.nav-item-active {
  @apply bg-[var(--paper-elevated)] text-[var(--ink-primary)] font-medium shadow-xs;
}

.nav-item-active::before {
  content: '';
  position: absolute;
  left: 3px;
  top: 7px;
  bottom: 7px;
  width: 2.5px;
  border-radius: 9999px;
  background-color: var(--accent-warm);
}

.nav-badge {
  @apply font-mono-tabular text-[11px] text-[var(--ink-muted)] px-1.5 py-0.5 rounded-md;
}
</style>
