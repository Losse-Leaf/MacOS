<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { CheckCircle2, Edit3, Plus, RefreshCw, Search, Sparkles, Trash2, X } from 'lucide-vue-next'
import { api } from '../services/api'
import { appStore, mediaUrl, refreshAll, showToast, wantingWishesCount } from '../stores/appStore'
import type { Wish } from '../types/api'
import { formatYuan } from '../utils/format'

const kindFilter = ref<'all' | 'item' | 'travel' | 'milestone'>('all')
const statusFilter = ref<'all' | 'wanting' | 'fulfilled'>('all')
const filterInputRef = ref<HTMLInputElement | null>(null)

const totalBudgetCents = computed(() =>
  appStore.wishes
    .filter((w) => w.status === 'wanting' || !w.status || w.status === 'shelved')
    .reduce((sum, w) => sum + (w.budget || 0), 0),
)

const fulfilledCount = computed(
  () => appStore.wishes.filter((w) => w.status === 'fulfilled' || w.status === 'relinquished').length,
)

const filteredWishes = computed(() => {
  const q = appStore.searchQuery.trim().toLowerCase()
  return appStore.wishes.filter((w) => {
    if (kindFilter.value !== 'all' && w.kind !== kindFilter.value) return false
    const isArchived = w.status === 'fulfilled' || w.status === 'relinquished'
    if (statusFilter.value === 'wanting' && isArchived) return false
    if (statusFilter.value === 'fulfilled' && !isArchived) return false
    if (q) {
      const hay = `${w.title} ${w.note ?? ''} ${w.spec ?? ''}`.toLowerCase()
      if (!hay.includes(q)) return false
    }
    return true
  })
})

function kindLabel(kind: string): string {
  if (kind === 'travel') return '旅程'
  if (kind === 'milestone') return '里程碑'
  return '好物'
}

function statusLabel(status: string): string {
  if (status === 'fulfilled') return '已圆满'
  if (status === 'relinquished') return '已释怀'
  if (status === 'shelved') return '暂搁'
  return '心愿中'
}

function askDeleteWish(wish: Wish) {
  appStore.confirmRequest = {
    title: '移除这个心愿？',
    message: `确定移除「${wish.title}」吗？`,
    confirmText: '确认移除',
    danger: true,
    onConfirm: async () => {
      await api.deleteWish(wish.id)
      appStore.wishes = appStore.wishes.filter((x) => x.id !== wish.id)
      showToast('已移除心愿')
      void refreshAll(true)
    },
  }
}

function handleFocusEvent() {
  filterInputRef.value?.focus()
  filterInputRef.value?.select()
}

onMounted(() => window.addEventListener('looseleaf-focus-filter', handleFocusEvent))
onBeforeUnmount(() => window.removeEventListener('looseleaf-focus-filter', handleFocusEvent))
</script>

<template>
  <div class="flex-1 min-h-0 flex flex-col bg-[var(--paper)]">
    <!-- 一体化心愿图鉴头部 -->
    <header
      data-tauri-drag-region
      class="tauri-drag shrink-0 px-8 pt-5 pb-4 border-b border-[var(--border-subtle)] flex flex-wrap items-center justify-between gap-4"
    >
      <div class="flex flex-col gap-1.5">
        <div
          class="flex items-baseline gap-3 transition-[padding] duration-200"
          :class="appStore.sidebarCollapsed ? 'pl-[84px]' : ''"
        >
          <h1 class="font-serif-editorial text-[24px] font-semibold tracking-tight text-[var(--ink-primary)]">
            心愿图鉴
          </h1>
          <span class="font-mono-tabular text-[12px] text-[var(--ink-muted)]">
            {{ wantingWishesCount }} 待实现 · {{ fulfilledCount }} 已归档 · 预算 {{ formatYuan(totalBudgetCents) }}
          </span>
        </div>

        <div class="flex flex-wrap items-center gap-1.5 pt-0.5">
          <button
            v-for="k in (['all', 'item', 'travel', 'milestone'] as const)"
            :key="k"
            type="button"
            class="chip-btn"
            :class="kindFilter === k ? 'chip-active' : 'chip-idle'"
            @click="kindFilter = k"
          >
            {{ k === 'all' ? '全部维度' : kindLabel(k) }}
          </button>

          <span class="w-px h-3.5 bg-[var(--border-subtle)] mx-1" />

          <button
            v-for="s in (['all', 'wanting', 'fulfilled'] as const)"
            :key="s"
            type="button"
            class="chip-btn"
            :class="statusFilter === s ? 'chip-active' : 'chip-idle'"
            @click="statusFilter = s"
          >
            {{ s === 'all' ? '全部状态' : s === 'wanting' ? '心愿中' : '已归档' }}
          </button>
        </div>
      </div>

      <div class="flex items-center gap-2">
        <div class="relative flex items-center w-48">
          <Search class="w-3.5 h-3.5 text-[var(--ink-muted)] absolute left-2.5 pointer-events-none" />
          <input
            ref="filterInputRef"
            v-model="appStore.searchQuery"
            type="search"
            placeholder="筛选心愿… (⌘F)"
            aria-label="筛选心愿"
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
          @click="appStore.wishModal = { open: true, editing: null }"
        >
          <Plus class="w-3.5 h-3.5" />
          <span>许下心愿</span>
        </button>
      </div>
    </header>

    <div class="flex-1 overflow-y-auto paper-scroll px-8 py-6">
      <div
        v-if="filteredWishes.length === 0"
        class="h-full flex flex-col items-center justify-center gap-2.5 text-[var(--ink-muted)]"
      >
        <Sparkles class="w-8 h-8 opacity-45" />
        <div class="font-serif-editorial text-[16px] text-[var(--ink-primary)]">心愿图鉴暂时为空</div>
        <p class="text-[12.5px]">种下一个想买的好物、想去的旅途或人生里程碑吧。</p>
      </div>

      <div v-else class="max-w-[1120px] mx-auto grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 pb-10">
        <article
          v-for="wish in filteredWishes"
          :key="wish.id"
          class="group rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] hover:border-[var(--border-divider)] overflow-hidden flex flex-col transition-all duration-150"
          style="box-shadow: var(--shadow-card);"
        >
          <div
            v-if="wish.attachments?.length"
            class="h-44 w-full overflow-hidden bg-[var(--paper-subtle)] cursor-zoom-in"
            @click="appStore.lightboxState = { attachments: wish.attachments, index: 0 }"
          >
            <img
              :src="mediaUrl(wish.attachments[0].thumbnail_url || wish.attachments[0].url)"
              :alt="wish.title"
              loading="lazy"
              class="w-full h-full object-cover group-hover:scale-[1.02] transition-transform duration-300"
            />
          </div>

          <div class="p-4.5 flex-1 flex flex-col gap-2.5">
            <div class="flex items-start justify-between gap-2">
              <div class="flex items-center gap-1.5">
                <span class="px-2 py-0.5 rounded-full bg-[var(--paper-subtle)] text-[11px] text-[var(--ink-secondary)]">
                  {{ kindLabel(wish.kind) }}
                </span>
                <span
                  class="px-2 py-0.5 rounded-full text-[11px] font-medium"
                  :class="
                    wish.status === 'fulfilled'
                      ? 'bg-[var(--accent-moss-soft)] text-[var(--accent-moss)]'
                      : wish.status === 'relinquished'
                        ? 'bg-[var(--paper-subtle)] text-[var(--ink-muted)]'
                        : 'bg-[var(--accent-warm-soft)] text-[var(--accent-warm)]'
                  "
                >
                  {{ statusLabel(wish.status) }}
                </span>
              </div>

              <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity">
                <button
                  type="button"
                  class="p-1 rounded-md hover:bg-[var(--paper-subtle)] text-[var(--ink-secondary)] cursor-pointer"
                  aria-label="编辑心愿"
                  @click="appStore.wishModal = { open: true, editing: wish }"
                >
                  <Edit3 class="w-3.5 h-3.5" />
                </button>
                <button
                  type="button"
                  class="p-1 rounded-md hover:bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] cursor-pointer"
                  aria-label="删除心愿"
                  @click="askDeleteWish(wish)"
                >
                  <Trash2 class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>

            <h3 class="font-serif-editorial text-[18px] font-semibold text-[var(--ink-primary)] leading-snug">
              {{ wish.actual_title || wish.title }}
            </h3>

            <p v-if="wish.spec || wish.note" class="text-[12.5px] text-[var(--ink-secondary)] line-clamp-3 leading-relaxed">
              {{ wish.spec || wish.note }}
            </p>

            <div class="mt-auto pt-3 border-t border-[var(--border-subtle)] flex items-center justify-between gap-2">
              <div class="text-[12.5px] font-mono-tabular text-[var(--ink-secondary)]">
                <span v-if="wish.status === 'fulfilled' && wish.actual_cost > 0">
                  实付 {{ formatYuan(wish.actual_cost) }}
                </span>
                <span v-else-if="wish.budget > 0">
                  预算 {{ formatYuan(wish.budget) }}
                </span>
                <span v-else class="font-sans text-[var(--ink-muted)]">无预算约束</span>
              </div>

              <button
                v-if="wish.status !== 'fulfilled' && wish.status !== 'relinquished'"
                type="button"
                class="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] text-[11.5px] font-medium hover:opacity-90 cursor-pointer"
                @click="appStore.resolveWishTarget = wish"
              >
                <CheckCircle2 class="w-3.5 h-3.5" />
                <span>圆满实现</span>
              </button>
            </div>
          </div>
        </article>
      </div>
    </div>
  </div>
</template>

<style scoped>
@reference "../styles/main.css";
.chip-btn {
  @apply px-2.5 py-1 rounded-full text-[12px] border transition-colors cursor-pointer;
}
.chip-idle {
  @apply bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)] hover:text-[var(--ink-primary)];
}
.chip-active {
  @apply bg-[var(--ink-primary)] border-transparent text-[var(--paper)] font-medium;
}
</style>
