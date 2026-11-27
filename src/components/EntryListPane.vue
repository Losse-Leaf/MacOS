<script setup lang="ts">
import { computed, ref } from 'vue'
import { BookOpen, Lock, RefreshCw, Search } from 'lucide-vue-next'
import {
  appStore,
  displayedStreamEntries,
  mediaUrl,
  remoteOnlySearchEntries,
  selectEntry,
} from '../stores/appStore'
import {
  compactListDate,
  deriveDisplayTitle,
  deriveExcerpt,
  groupEntriesByMonth,
} from '../utils/format'

const visibleLimit = ref(200)

const limitedEntries = computed(() => displayedStreamEntries.value.slice(0, visibleLimit.value))
const monthGroups = computed(() => groupEntriesByMonth(limitedEntries.value))
const remoteHits = computed(() => remoteOnlySearchEntries.value)
const hasMore = computed(() => displayedStreamEntries.value.length > limitedEntries.value.length)
</script>

<template>
  <div class="h-full flex flex-col bg-[var(--paper-subtle)]/55 border-r border-[var(--border-subtle)]">
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
            ? '正在加载散页…'
            : appStore.searchQuery.trim()
              ? '没有匹配的散页'
              : '这里尚无散页记录'
        }}
      </div>
      <p class="text-[12px] text-[var(--ink-muted)] leading-relaxed">
        {{
          appStore.searchQuery.trim()
            ? '试试更换关键词，或按 ⌘K 检索全库档案'
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

    <div v-else class="flex-1 overflow-y-auto paper-scroll px-2.5 py-2 flex flex-col gap-3">
      <section v-for="group in monthGroups" :key="group.id" class="flex flex-col gap-1">
        <h3
          class="sticky top-0 z-10 px-2 py-1 text-[11px] font-mono-tabular font-semibold text-[var(--ink-muted)] bg-[var(--paper)]/90 backdrop-blur-xs rounded-md"
        >
          {{ group.title }}
        </h3>

        <button
          v-for="entry in group.entries"
          :key="entry.id"
          type="button"
          class="entry-card"
          :class="appStore.selectedEntryId === entry.id ? 'entry-card-selected' : 'entry-card-idle'"
          @click="selectEntry(entry.id)"
        >
          <div class="flex-1 min-w-0 flex flex-col gap-1 text-left">
            <div class="text-[13.5px] font-semibold text-[var(--ink-primary)] truncate leading-snug">
              {{ deriveDisplayTitle(entry) }}
            </div>

            <p
              v-if="deriveExcerpt(entry)"
              class="text-[12px] text-[var(--ink-secondary)] line-clamp-2 leading-relaxed"
            >
              {{ deriveExcerpt(entry) }}
            </p>

            <div class="flex items-center gap-1.5 text-[11px] text-[var(--ink-muted)] font-mono-tabular pt-0.5">
              <span>{{ compactListDate(entry.occurred_at) }}</span>
              <span v-if="entry.location?.trim()" class="truncate font-sans">
                · {{ entry.location.trim() }}
              </span>
              <Lock v-if="entry.is_private" class="w-3 h-3 text-[var(--accent-warm)] shrink-0" />
            </div>
          </div>

          <div
            v-if="entry.attachments.length > 0"
            class="relative w-14 h-14 shrink-0 rounded-lg overflow-hidden bg-[var(--paper-subtle)] border border-[var(--border-subtle)]"
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
        class="mx-auto my-2 px-3 py-1.5 rounded-lg text-[11.5px] font-mono-tabular text-[var(--ink-secondary)] bg-[var(--paper-elevated)] border border-[var(--border-subtle)] hover:border-[var(--border-divider)] cursor-pointer"
        @click="visibleLimit += 200"
      >
        加载更多（{{ limitedEntries.length }} / {{ displayedStreamEntries.length }}）
      </button>

      <section v-if="remoteHits.length > 0" class="flex flex-col gap-1 pt-2 border-t border-[var(--border-subtle)]">
        <h3 class="px-2 py-1 text-[11px] font-semibold text-[var(--ink-muted)]">
          远端历史归档（{{ remoteHits.length }}）
        </h3>

        <button
          v-for="entry in remoteHits"
          :key="`remote-${entry.id}`"
          type="button"
          class="entry-card"
          :class="appStore.selectedEntryId === entry.id ? 'entry-card-selected' : 'entry-card-idle'"
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

.entry-card {
  @apply relative w-full flex items-start gap-2.5 p-2.5 rounded-xl border transition-all duration-100 cursor-pointer;
}

.entry-card-idle {
  @apply border-transparent bg-transparent hover:bg-[var(--paper-elevated)]/65;
}

.entry-card-selected {
  @apply bg-[var(--paper-elevated)] border-[var(--border-divider)] shadow-xs;
}

.entry-card-selected::before {
  content: '';
  position: absolute;
  left: 0;
  top: 10px;
  bottom: 10px;
  width: 3px;
  border-radius: 0 3px 3px 0;
  background-color: var(--accent-warm);
}
</style>
