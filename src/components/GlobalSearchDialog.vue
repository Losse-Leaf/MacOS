<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { BookOpen, Search, Sparkles, X } from 'lucide-vue-next'
import { api } from '../services/api'
import { appStore, selectEntry, selectSpace } from '../stores/appStore'
import type { LifeEntry, Wish } from '../types/api'
import { attachDialogLightDismiss, closeDialogAnimated, compactListDate, deriveDisplayTitle } from '../utils/format'

const dialogRef = ref<HTMLDialogElement | null>(null)
const query = ref('')
const remoteEntries = ref<LifeEntry[]>([])
const remoteWishes = ref<Wish[]>([])
const isSearching = ref(false)

let cleanupLightDismiss: (() => void) | null = null
let timer: ReturnType<typeof setTimeout> | null = null

watch(
  () => appStore.showGlobalSearch,
  (open) => {
    const dlg = dialogRef.value
    if (!dlg) return
    if (open) {
      query.value = ''
      remoteEntries.value = []
      remoteWishes.value = []
      if (!dlg.open) dlg.showModal()
      cleanupLightDismiss?.()
      cleanupLightDismiss = attachDialogLightDismiss(dlg, closeModal)
    } else if (dlg.open) {
      void closeDialogAnimated(dlg)
    }
  },
)

watch(query, (val) => {
  if (timer) clearTimeout(timer)
  const trimmed = val.trim()
  if (!trimmed) {
    remoteEntries.value = []
    remoteWishes.value = []
    return
  }
  timer = setTimeout(async () => {
    isSearching.value = true
    try {
      const res = await api.searchGlobalArchive(trimmed, 20)
      remoteEntries.value = res.entries ?? []
      remoteWishes.value = res.wishes ?? []
    } catch {
      remoteEntries.value = []
      remoteWishes.value = []
    } finally {
      isSearching.value = false
    }
  }, 150)
})

const mergedEntries = computed(() => {
  const q = query.value.trim().toLowerCase()
  if (!q) return appStore.entries.slice(0, 8)
  const local = appStore.entries.filter((e) =>
    `${e.title} ${e.content} ${e.location ?? ''}`.toLowerCase().includes(q),
  )
  const seen = new Set(local.map((e) => e.id))
  return [...local, ...remoteEntries.value.filter((e) => !seen.has(e.id))].slice(0, 15)
})

const mergedWishes = computed(() => {
  const q = query.value.trim().toLowerCase()
  if (!q) return appStore.wishes.slice(0, 5)
  const local = appStore.wishes.filter((w) =>
    `${w.title} ${w.spec ?? ''} ${w.note ?? ''}`.toLowerCase().includes(q),
  )
  const seen = new Set(local.map((w) => w.id))
  return [...local, ...remoteWishes.value.filter((w) => !seen.has(w.id))].slice(0, 10)
})

onBeforeUnmount(() => cleanupLightDismiss?.())

function closeModal() {
  const dlg = dialogRef.value
  if (dlg?.open) {
    void closeDialogAnimated(dlg).then(() => {
      appStore.showGlobalSearch = false
    })
  } else {
    appStore.showGlobalSearch = false
  }
}

function handleCancel(e: Event) {
  e.preventDefault()
  closeModal()
}

async function openEntry(entry: LifeEntry) {
  await selectEntry(entry.id, true)
  closeModal()
}

function openWishlist() {
  selectSpace('wishlist')
  closeModal()
}
</script>

<template>
  <dialog
    ref="dialogRef"
    closedby="any"
    aria-labelledby="global-search-title"
    class="w-[620px] rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] shadow-2xl overflow-hidden"
    @cancel="handleCancel"
    @close="appStore.showGlobalSearch = false"
  >
    <div class="flex flex-col max-h-[75vh]">
      <div class="px-4 py-3 border-b border-[var(--border-subtle)] flex items-center gap-3">
        <Search class="w-4 h-4 text-[var(--accent-warm)] shrink-0" />
        <input
          v-model="query"
          type="search"
          autofocus
          placeholder="全局检索散页手稿与心愿档案… (⌘K)"
          aria-labelledby="global-search-title"
          class="flex-1 bg-transparent text-[14px] text-[var(--ink-primary)] placeholder:text-[var(--ink-muted)]"
        />
        <span id="global-search-title" class="sr-only">全局档案搜索</span>
        <button
          type="button"
          class="p-1 rounded-md text-[var(--ink-muted)] hover:bg-[var(--paper-subtle)] cursor-pointer"
          aria-label="关闭全局搜索"
          @click="closeModal"
        >
          <X class="w-4 h-4" />
        </button>
      </div>

      <div class="flex-1 overflow-y-auto paper-scroll p-3 flex flex-col gap-4">
        <div v-if="mergedEntries.length > 0" class="flex flex-col gap-1">
          <div class="px-2 py-1 text-[11px] font-semibold text-[var(--ink-muted)]">
            散页档案（{{ mergedEntries.length }}）
          </div>
          <button
            v-for="entry in mergedEntries"
            :key="entry.id"
            type="button"
            class="w-full px-3 py-2 rounded-xl flex items-center justify-between gap-3 text-left hover:bg-[var(--paper-subtle)] transition-colors cursor-pointer"
            @click="openEntry(entry)"
          >
            <div class="flex items-center gap-2.5 min-w-0">
              <BookOpen class="w-4 h-4 text-[var(--accent-warm)] shrink-0" />
              <div class="min-w-0">
                <div class="text-[13px] font-medium text-[var(--ink-primary)] truncate">
                  {{ deriveDisplayTitle(entry) }}
                </div>
                <div class="text-[11.5px] text-[var(--ink-muted)] truncate">
                  {{ entry.content }}
                </div>
              </div>
            </div>
            <span class="font-mono-tabular text-[11px] text-[var(--ink-muted)] shrink-0">
              {{ compactListDate(entry.occurred_at) }}
            </span>
          </button>
        </div>

        <div v-if="mergedWishes.length > 0" class="flex flex-col gap-1">
          <div class="px-2 py-1 text-[11px] font-semibold text-[var(--ink-muted)]">
            心愿清单（{{ mergedWishes.length }}）
          </div>
          <button
            v-for="wish in mergedWishes"
            :key="wish.id"
            type="button"
            class="w-full px-3 py-2 rounded-xl flex items-center justify-between gap-3 text-left hover:bg-[var(--paper-subtle)] transition-colors cursor-pointer"
            @click="openWishlist"
          >
            <div class="flex items-center gap-2.5 min-w-0">
              <Sparkles class="w-4 h-4 text-[var(--spectrum-leisure)] shrink-0" />
              <span class="text-[13px] font-medium text-[var(--ink-primary)] truncate">
                {{ wish.title }}
              </span>
            </div>
            <span class="text-[11px] text-[var(--ink-muted)] shrink-0">前往心愿清单</span>
          </button>
        </div>

        <div
          v-if="!isSearching && mergedEntries.length === 0 && mergedWishes.length === 0"
          class="py-10 text-center text-[13px] text-[var(--ink-muted)]"
        >
          没有找到匹配的记录
        </div>
      </div>
    </div>
  </dialog>
</template>
