<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { Image as ImageIcon, Maximize2, Plus, RefreshCw, Search, X } from 'lucide-vue-next'
import {
  appStore,
  galleryEntries,
  mediaUrl,
  refreshAll,
  selectEntry,
  selectSpace,
  type GalleryFilter,
} from '../stores/appStore'
import {
  compactListDate,
  deriveDisplayTitle,
  entryAccentVar,
  entryBadgeLabel,
  GALLERY_CATEGORIES,
} from '../utils/format'

const filterInputRef = ref<HTMLInputElement | null>(null)

const tabs: { id: GalleryFilter; label: string }[] = [
  { id: 'all', label: '全部影像' },
  ...GALLERY_CATEGORIES.map((c) => ({ id: c.id, label: c.label })),
]

function handleFocusEvent() {
  filterInputRef.value?.focus()
  filterInputRef.value?.select()
}

onMounted(() => window.addEventListener('looseleaf-focus-filter', handleFocusEvent))
onBeforeUnmount(() => window.removeEventListener('looseleaf-focus-filter', handleFocusEvent))
</script>

<template>
  <div class="flex-1 min-h-0 flex flex-col bg-[var(--paper)]">
    <!-- 策展画廊头部 -->
    <header
      data-tauri-drag-region
      class="tauri-drag shrink-0 px-8 pt-5 pb-4 border-b border-[var(--border-subtle)] flex flex-wrap items-center justify-between gap-4"
      :class="appStore.sidebarCollapsed ? 'pl-[124px]' : ''"
    >
      <div class="flex flex-col gap-2">
        <div class="flex items-baseline gap-3">
          <h1 class="font-serif-editorial text-[24px] font-semibold tracking-tight text-[var(--ink-primary)]">
            影像画廊
          </h1>
          <span class="font-mono-tabular text-[12px] text-[var(--ink-muted)]">
            {{ galleryEntries.length }} 组展品
          </span>
        </div>

        <div class="flex flex-wrap items-center gap-1.5">
          <button
            v-for="tab in tabs"
            :key="tab.id"
            type="button"
            class="px-3 py-1 rounded-full text-[12px] transition-colors cursor-pointer"
            :class="
              appStore.galleryCategory === tab.id
                ? 'bg-[var(--ink-primary)] text-[var(--paper)] font-medium'
                : 'bg-[var(--paper-subtle)] text-[var(--ink-secondary)] hover:text-[var(--ink-primary)]'
            "
            @click="selectSpace('gallery', { galleryCategory: tab.id })"
          >
            {{ tab.label }}
          </button>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <div class="relative flex items-center w-52">
          <Search class="w-3.5 h-3.5 text-[var(--ink-muted)] absolute left-2.5 pointer-events-none" />
          <input
            ref="filterInputRef"
            v-model="appStore.searchQuery"
            type="search"
            placeholder="筛选画廊展品… (⌘F)"
            aria-label="筛选画廊"
            class="w-full pl-8 pr-7 py-1.5 rounded-xl bg-[var(--paper-subtle)] border border-transparent focus:border-[var(--border-divider)] focus:bg-[var(--paper-elevated)] text-[12px]"
          />
          <button
            v-if="appStore.searchQuery"
            type="button"
            class="absolute right-2 text-[var(--ink-muted)] cursor-pointer"
            aria-label="清空"
            @click="appStore.searchQuery = ''"
          >
            <X class="w-3 h-3" />
          </button>
        </div>

        <button
          type="button"
          class="p-2 rounded-xl text-[var(--ink-secondary)] hover:bg-[var(--paper-subtle)] cursor-pointer"
          title="同步 (⌘R)"
          aria-label="同步"
          @click="refreshAll(false)"
        >
          <RefreshCw class="w-4 h-4" :class="{ 'animate-spin text-[var(--accent-warm)]': appStore.isLoading }" />
        </button>

        <button
          type="button"
          class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-[var(--accent-warm)] text-white text-[12.5px] font-medium hover:opacity-92 cursor-pointer"
          @click="appStore.showNewEntryModal = true"
        >
          <Plus class="w-3.5 h-3.5" />
          <span>定格新照</span>
        </button>
      </div>
    </header>

    <div class="flex-1 overflow-y-auto paper-scroll px-8 py-6">
      <div
        v-if="galleryEntries.length === 0"
        class="h-full flex flex-col items-center justify-center gap-2.5 text-[var(--ink-muted)]"
      >
        <ImageIcon class="w-9 h-9 opacity-50" />
        <div class="font-serif-editorial text-[17px] text-[var(--ink-primary)]">此展区暂无影像散页</div>
        <p class="text-[12.5px]">写散页时选择摄影 / 旅途 / 静物 / 影像，或附上照片即可在此陈列。</p>
      </div>

      <div
        v-else
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5 pb-8"
      >
        <article
          v-for="entry in galleryEntries"
          :key="entry.id"
          class="group rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] hover:border-[var(--border-divider)] overflow-hidden transition-all duration-150 flex flex-col cursor-pointer"
          style="box-shadow: var(--shadow-card);"
          @click="selectEntry(entry.id, true)"
        >
          <div class="relative aspect-[4/3] w-full overflow-hidden bg-[var(--paper-subtle)]">
            <img
              v-if="entry.attachments.length > 0"
              :src="mediaUrl(entry.attachments[0].thumbnail_url || entry.attachments[0].url)"
              :alt="deriveDisplayTitle(entry)"
              loading="lazy"
              class="w-full h-full object-cover group-hover:scale-[1.03] transition-transform duration-300"
            />
            <div v-else class="w-full h-full flex items-center justify-center text-[var(--ink-muted)]">
              <ImageIcon class="w-7 h-7 opacity-40" />
            </div>

            <div class="absolute top-2.5 left-2.5 flex items-center gap-1.5">
              <span
                class="px-2 py-0.5 rounded-full text-[10.5px] font-medium backdrop-blur-md bg-[var(--paper-elevated)]/88"
                :style="{ color: entryAccentVar(entry) }"
              >
                {{ entryBadgeLabel(entry) }}
              </span>
            </div>

            <div class="absolute top-2.5 right-2.5 flex items-center gap-1.5">
              <span
                v-if="entry.attachments.length > 1"
                class="px-2 py-0.5 rounded-full bg-black/60 text-white font-mono-tabular text-[10px] font-semibold backdrop-blur-xs"
              >
                {{ entry.attachments.length }} 张
              </span>
              <button
                v-if="entry.attachments.length > 0"
                type="button"
                class="w-7 h-7 rounded-full bg-black/55 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity hover:bg-black/80 cursor-zoom-in"
                title="灯箱查看原图"
                aria-label="灯箱查看原图"
                @click.stop="appStore.lightboxState = { attachments: entry.attachments, index: 0 }"
              >
                <Maximize2 class="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          <div class="p-3.5 flex flex-col gap-1">
            <h3 class="font-serif-editorial text-[15px] font-semibold text-[var(--ink-primary)] truncate">
              {{ deriveDisplayTitle(entry) }}
            </h3>
            <div class="flex items-center justify-between gap-2 text-[11px] text-[var(--ink-muted)] font-mono-tabular">
              <span>{{ compactListDate(entry.occurred_at) }}</span>
              <span v-if="entry.location?.trim()" class="font-sans truncate">{{ entry.location.trim() }}</span>
            </div>
          </div>
        </article>
      </div>
    </div>
  </div>
</template>
