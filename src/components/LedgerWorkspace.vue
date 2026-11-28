<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  ChevronLeft,
  ChevronRight,
  CreditCard,
  Edit3,
  LayoutList,
  Plus,
  RefreshCw,
  Search,
  Sparkles,
  Table as TableIcon,
  Trash2,
  X,
} from 'lucide-vue-next'
import { api } from '../services/api'
import {
  activeInstallmentsCount,
  appStore,
  refreshAll,
  refreshMonthlySummary,
  showToast,
} from '../stores/appStore'
import type { Transaction } from '../types/api'
import {
  beijingDateParts,
  categoryColorVar,
  compactListDate,
  formatBeijingISO,
  formatYuan,
  groupTransactionsByDay,
  parseOccurredDate,
  parseQuickLedgerInput,
} from '../utils/format'
import InstallmentsWorkspace from './InstallmentsWorkspace.vue'

type SortField = 'occurred_at' | 'category' | 'title' | 'amount'
type SortDir = 'ascending' | 'descending'

const quickInput = ref('')
const isSubmittingQuick = ref(false)
const scopeFilter = ref<'month' | 'all'>('month')
const selectedCategory = ref<string>('all')
const sortField = ref<SortField>('occurred_at')
const sortDir = ref<SortDir>('descending')
const filterInputRef = ref<HTMLInputElement | null>(null)
const collator = new Intl.Collator('zh-CN', { numeric: true, sensitivity: 'base' })

const spectrumBreakdown = computed(() => {
  const total = appStore.transactionSummary.total_expense
  const map = appStore.transactionSummary.category_breakdown ?? {}
  if (total <= 0) return []
  return Object.entries(map)
    .sort((a, b) => b[1] - a[1])
    .map(([category, cents]) => ({
      category,
      cents,
      ratio: Math.max(0.02, cents / total),
      percent: Math.round((cents / total) * 100),
    }))
})

const allCategoriesFilter = computed(() => {
  const set = new Set<string>([
    ...appStore.expenseCategories,
    ...appStore.incomeCategories,
    ...appStore.transactions.map((t) => t.category).filter(Boolean),
  ])
  return ['all', ...Array.from(set)]
})

const filteredTransactions = computed(() => {
  const q = appStore.searchQuery.trim().toLowerCase()
  const y = String(appStore.selectedLedgerYear)
  const m = String(appStore.selectedLedgerMonth).padStart(2, '0')

  return appStore.transactions.filter((tx) => {
    if (scopeFilter.value === 'month') {
      const p = parseOccurredDate(tx.occurred_at)
      if (!p.valid || p.year !== y || p.month !== m) return false
    }
    if (selectedCategory.value !== 'all' && tx.category !== selectedCategory.value) {
      return false
    }
    if (q) {
      const hay = `${tx.title} ${tx.category} ${tx.note ?? ''} ${tx.payment_method ?? ''}`.toLowerCase()
      if (!hay.includes(q)) return false
    }
    return true
  })
})

const dayGroups = computed(() => groupTransactionsByDay(filteredTransactions.value))

const sortedTransactions = computed(() => {
  const factor = sortDir.value === 'ascending' ? 1 : -1
  return [...filteredTransactions.value].sort((a, b) => {
    if (sortField.value === 'occurred_at') {
      return factor * (parseOccurredDate(a.occurred_at).timestamp - parseOccurredDate(b.occurred_at).timestamp)
    }
    if (sortField.value === 'amount') {
      const sa = a.type === 'income' ? a.amount : -a.amount
      const sb = b.type === 'income' ? b.amount : -b.amount
      return factor * (sa - sb)
    }
    if (sortField.value === 'category') {
      return factor * collator.compare(a.category, b.category)
    }
    return factor * collator.compare(a.title || a.category, b.title || b.category)
  })
})

function toggleSort(field: SortField) {
  if (sortField.value === field) {
    sortDir.value = sortDir.value === 'ascending' ? 'descending' : 'ascending'
  } else {
    sortField.value = field
    sortDir.value = field === 'occurred_at' || field === 'amount' ? 'descending' : 'ascending'
  }
}

async function shiftMonth(delta: number) {
  let y = appStore.selectedLedgerYear
  let m = appStore.selectedLedgerMonth + delta
  if (m < 1) {
    m = 12
    y -= 1
  } else if (m > 12) {
    m = 1
    y += 1
  }
  await refreshMonthlySummary(y, m)
}

const parsedQuick = computed(() => parseQuickLedgerInput(quickInput.value))

async function submitQuick() {
  if (isSubmittingQuick.value) return
  const { amountCents, title, type } = parsedQuick.value
  if (!amountCents || amountCents <= 0) {
    showToast('请先输入有效金额（例如：42.5 咖啡）', true)
    return
  }
  isSubmittingQuick.value = true
  try {
    const defaultCat =
      type === 'income'
        ? appStore.incomeCategories[0] || '工资收入'
        : appStore.expenseCategories[0] || '餐饮'
    const created = await api.createTransaction({
      amount: amountCents,
      type,
      category: defaultCat,
      title: title || defaultCat,
      payment_method: appStore.paymentMethods[0] || '微信支付',
      occurred_at: formatBeijingISO(),
      client_request_id: crypto.randomUUID(),
    })
    appStore.transactions = [created, ...appStore.transactions]
    quickInput.value = ''
    showToast(`已记入账本：${formatYuan(amountCents)}`)
    const now = beijingDateParts()
    await refreshMonthlySummary(now.year, now.month)
    void refreshAll(true)
  } catch (err) {
    showToast(err instanceof Error ? err.message : '记账失败', true)
  } finally {
    isSubmittingQuick.value = false
  }
}

function askDeleteTx(tx: Transaction) {
  appStore.confirmRequest = {
    title: '删除这笔流水？',
    message: `将移除「${tx.title || tx.category}」（${formatYuan(tx.amount)}）。`,
    confirmText: '确认删除',
    danger: true,
    onConfirm: async () => {
      await api.deleteTransaction(tx.id)
      appStore.transactions = appStore.transactions.filter((x) => x.id !== tx.id)
      showToast('已删除流水记录')
      await refreshMonthlySummary(appStore.selectedLedgerYear, appStore.selectedLedgerMonth)
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
    <!-- 一体化顶部头部 -->
    <header
      data-tauri-drag-region
      class="tauri-drag shrink-0 px-8 pt-5 pb-4 border-b border-[var(--border-subtle)] flex flex-wrap items-center justify-between gap-4"
      :class="appStore.sidebarCollapsed ? 'pl-[112px]' : ''"
    >
      <div class="flex items-center gap-5">
        <h1 class="font-serif-editorial text-[24px] font-semibold tracking-tight text-[var(--ink-primary)]">
          账本
        </h1>

        <div class="inline-flex items-center p-1 rounded-xl bg-[var(--paper-subtle)] border border-[var(--border-subtle)]">
          <button
            type="button"
            class="px-3 py-1 rounded-lg text-[12.5px] transition-colors cursor-pointer"
            :class="
              appStore.ledgerTab === 'transactions'
                ? 'bg-[var(--paper-elevated)] text-[var(--ink-primary)] font-semibold shadow-xs'
                : 'text-[var(--ink-secondary)] hover:text-[var(--ink-primary)]'
            "
            @click="appStore.ledgerTab = 'transactions'"
          >
            收支流水
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-1 rounded-lg text-[12.5px] transition-colors cursor-pointer"
            :class="
              appStore.ledgerTab === 'installments'
                ? 'bg-[var(--paper-elevated)] text-[var(--ink-primary)] font-semibold shadow-xs'
                : 'text-[var(--ink-secondary)] hover:text-[var(--ink-primary)]'
            "
            @click="appStore.ledgerTab = 'installments'"
          >
            <span>分期计划</span>
            <span
              v-if="activeInstallmentsCount > 0"
              class="font-mono-tabular text-[10.5px] px-1.5 py-0.5 rounded-full bg-[var(--accent-warm-soft)] text-[var(--accent-warm)]"
            >
              {{ activeInstallmentsCount }}
            </span>
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
            placeholder="筛选账目… (⌘F)"
            aria-label="筛选账目"
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
          v-if="appStore.ledgerTab === 'transactions'"
          type="button"
          class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-[var(--accent-warm)] text-white text-[12.5px] font-medium hover:opacity-92 cursor-pointer"
          @click="appStore.transactionModal = { open: true, editing: null }"
        >
          <Plus class="w-3.5 h-3.5" />
          <span>记一笔</span>
        </button>
      </div>
    </header>

    <InstallmentsWorkspace v-if="appStore.ledgerTab === 'installments'" />

    <div v-else class="flex-1 min-h-0 overflow-y-auto paper-scroll px-8 py-6">
      <div class="max-w-[980px] mx-auto flex flex-col gap-6 pb-10">
        <!-- 资产负债排版大盘（去框线、纯排版+交互式类目光谱） -->
        <section class="flex flex-col gap-4 pb-5 border-b border-[var(--border-subtle)]">
          <div class="flex flex-wrap items-end justify-between gap-6">
            <div class="flex flex-col gap-1.5">
              <div class="flex items-center gap-2 text-[12px] text-[var(--ink-muted)]">
                <button
                  type="button"
                  class="p-1 rounded-md hover:bg-[var(--paper-subtle)] cursor-pointer"
                  aria-label="上一个月"
                  @click="shiftMonth(-1)"
                >
                  <ChevronLeft class="w-3.5 h-3.5" />
                </button>
                <span class="font-mono-tabular font-medium text-[var(--ink-secondary)]">
                  {{ appStore.selectedLedgerYear }}年{{ appStore.selectedLedgerMonth }}月 本月支出
                </span>
                <button
                  type="button"
                  class="p-1 rounded-md hover:bg-[var(--paper-subtle)] cursor-pointer"
                  aria-label="下一个月"
                  @click="shiftMonth(1)"
                >
                  <ChevronRight class="w-3.5 h-3.5" />
                </button>
              </div>
              <div class="font-mono-tabular text-[34px] font-semibold tracking-tight text-[var(--ink-primary)] leading-none">
                {{ formatYuan(appStore.transactionSummary.total_expense) }}
              </div>
            </div>

            <div class="flex items-center gap-8">
              <div>
                <div class="text-[11px] text-[var(--ink-muted)]">收入</div>
                <div class="font-mono-tabular text-[18px] font-semibold text-[var(--accent-moss)] mt-0.5">
                  {{ formatYuan(appStore.transactionSummary.total_income) }}
                </div>
              </div>
              <div>
                <div class="text-[11px] text-[var(--ink-muted)]">本月结余</div>
                <div class="font-mono-tabular text-[18px] font-semibold text-[var(--ink-primary)] mt-0.5">
                  {{ formatYuan(appStore.transactionSummary.balance) }}
                </div>
              </div>
            </div>
          </div>

          <div v-if="spectrumBreakdown.length > 0" class="flex flex-col gap-2">
            <div class="h-2.5 w-full rounded-full overflow-hidden flex gap-0.5 bg-[var(--paper-subtle)]">
              <button
                v-for="seg in spectrumBreakdown"
                :key="seg.category"
                type="button"
                :style="{
                  width: `${seg.ratio * 100}%`,
                  backgroundColor: categoryColorVar(seg.category),
                }"
                :title="`点击筛选 ${seg.category}：${formatYuan(seg.cents)} (${seg.percent}%)`"
                class="h-full first:rounded-l-full last:rounded-r-full hover:opacity-80 transition-opacity cursor-pointer"
                @click="selectedCategory = selectedCategory === seg.category ? 'all' : seg.category"
              />
            </div>

            <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-[11.5px] text-[var(--ink-secondary)]">
              <button
                v-for="seg in spectrumBreakdown.slice(0, 7)"
                :key="seg.category"
                type="button"
                class="inline-flex items-center gap-1.5 hover:text-[var(--ink-primary)] cursor-pointer"
                :class="selectedCategory === seg.category ? 'font-semibold text-[var(--ink-primary)]' : ''"
                @click="selectedCategory = selectedCategory === seg.category ? 'all' : seg.category"
              >
                <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: categoryColorVar(seg.category) }" />
                <span>{{ seg.category }}</span>
                <span class="font-mono-tabular text-[var(--ink-muted)]">{{ formatYuan(seg.cents, false) }}</span>
              </button>
            </div>
          </div>
        </section>

        <!-- 浮动快捷记账条 -->
        <form
          class="p-2 pl-4 rounded-2xl bg-[var(--paper-subtle)]/80 border border-[var(--border-subtle)] flex flex-wrap items-center gap-2.5"
          @submit.prevent="submitQuick"
        >
          <Sparkles class="w-4 h-4 text-[var(--accent-warm)] shrink-0" />
          <input
            v-model="quickInput"
            type="text"
            placeholder="快速记账：输入「42.5 咖啡」或「+3500 稿费」，回车直记…"
            aria-label="快速记账输入"
            class="flex-1 min-w-[220px] bg-transparent text-[13px] text-[var(--ink-primary)] placeholder:text-[var(--ink-muted)]"
          />
          <span
            v-if="parsedQuick.amountCents"
            class="text-[11.5px] font-mono-tabular px-2.5 py-0.5 rounded-lg bg-[var(--paper-elevated)] text-[var(--ink-secondary)]"
          >
            {{ parsedQuick.type === 'income' ? '收入' : '支出' }} {{ formatYuan(parsedQuick.amountCents) }}
          </span>
          <button
            type="submit"
            :disabled="!parsedQuick.amountCents || isSubmittingQuick"
            class="px-3.5 py-1.5 rounded-xl bg-[var(--ink-primary)] text-[var(--paper)] text-[12px] font-medium disabled:opacity-35 cursor-pointer"
          >
            {{ isSubmittingQuick ? '记入中…' : '记入' }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1 px-3 py-1.5 rounded-xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] text-[12px] text-[var(--ink-secondary)] hover:text-[var(--ink-primary)] cursor-pointer"
            @click="appStore.transactionModal = { open: true, editing: null }"
          >
            <Plus class="w-3.5 h-3.5" />
            <span>完整表单</span>
          </button>
        </form>

        <!-- 筛选与视图切换（分组流水 vs 排序表格） -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex items-center gap-1.5 overflow-x-auto pb-1">
            <button
              type="button"
              class="chip-btn"
              :class="scopeFilter === 'month' ? 'chip-active' : 'chip-idle'"
              @click="scopeFilter = 'month'"
            >
              {{ appStore.selectedLedgerMonth }}月
            </button>
            <button
              type="button"
              class="chip-btn"
              :class="scopeFilter === 'all' ? 'chip-active' : 'chip-idle'"
              @click="scopeFilter = 'all'"
            >
              全部历史
            </button>

            <span class="w-px h-3.5 bg-[var(--border-subtle)] mx-1" />

            <button
              v-for="cat in allCategoriesFilter"
              :key="cat"
              type="button"
              class="chip-btn shrink-0"
              :class="selectedCategory === cat ? 'chip-active' : 'chip-idle'"
              @click="selectedCategory = cat"
            >
              {{ cat === 'all' ? '全部类目' : cat }}
            </button>
          </div>

          <div class="inline-flex items-center p-0.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)]">
            <button
              type="button"
              class="inline-flex items-center gap-1 px-2.5 py-1 rounded-md text-[11.5px] cursor-pointer"
              :class="appStore.ledgerDisplayMode === 'grouped' ? 'bg-[var(--paper-elevated)] font-medium shadow-xs' : 'text-[var(--ink-muted)]'"
              @click="appStore.ledgerDisplayMode = 'grouped'"
            >
              <LayoutList class="w-3.5 h-3.5" />
              <span>日结</span>
            </button>
            <button
              type="button"
              class="inline-flex items-center gap-1 px-2.5 py-1 rounded-md text-[11.5px] cursor-pointer"
              :class="appStore.ledgerDisplayMode === 'table' ? 'bg-[var(--paper-elevated)] font-medium shadow-xs' : 'text-[var(--ink-muted)]'"
              @click="appStore.ledgerDisplayMode = 'table'"
            >
              <TableIcon class="w-3.5 h-3.5" />
              <span>明细表</span>
            </button>
          </div>
        </div>

        <div
          v-if="filteredTransactions.length === 0"
          class="py-16 flex flex-col items-center justify-center gap-2 text-[var(--ink-muted)]"
        >
          <CreditCard class="w-8 h-8 opacity-45" />
          <div class="font-serif-editorial text-[16px] text-[var(--ink-primary)]">暂无匹配账目</div>
          <p class="text-[12px]">可在上方快速记账，或切换月份/类目查看历史流水。</p>
        </div>

        <!-- 视图 1：按日分组编辑流 -->
        <div v-else-if="appStore.ledgerDisplayMode === 'grouped'" class="flex flex-col gap-5">
          <section v-for="group in dayGroups" :key="group.id" class="flex flex-col gap-1">
            <div class="flex items-center justify-between px-2 py-1.5 text-[11.5px] text-[var(--ink-muted)]">
              <span class="font-medium">{{ group.title }}</span>
              <span class="font-mono-tabular flex items-center gap-3">
                <span v-if="group.incomeTotal > 0" class="text-[var(--accent-moss)]">
                  +{{ formatYuan(group.incomeTotal, false) }}
                </span>
                <span v-if="group.expenseTotal > 0">
                  -{{ formatYuan(group.expenseTotal, false) }}
                </span>
              </span>
            </div>

            <div class="rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] divide-y divide-[var(--border-subtle)] overflow-hidden">
              <div
                v-for="tx in group.transactions"
                :key="tx.id"
                class="group px-4 py-3 flex items-center justify-between gap-4 hover:bg-[var(--paper-subtle)]/45 transition-colors"
              >
                <div class="flex items-center gap-3 min-w-0">
                  <span
                    class="w-2.5 h-2.5 rounded-full shrink-0"
                    :style="{ backgroundColor: categoryColorVar(tx.category) }"
                  />
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="text-[13.5px] font-medium text-[var(--ink-primary)]">
                        {{ tx.title || tx.category }}
                      </span>
                      <span class="text-[11.5px] text-[var(--ink-muted)]">{{ tx.category }}</span>
                      <span v-if="tx.payment_method" class="text-[11px] text-[var(--ink-muted)]">
                        · {{ tx.payment_method }}
                      </span>
                      <span
                        v-if="tx.is_installment && tx.installment_months"
                        class="px-1.5 py-0.5 rounded bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] font-mono-tabular text-[10px]"
                      >
                        {{ tx.installment_remain_months ?? tx.installment_months }}/{{ tx.installment_months }} 期
                      </span>
                      <span
                        v-if="tx.source === 'installment_repay'"
                        class="px-1.5 py-0.5 rounded bg-[var(--paper-subtle)] text-[var(--ink-secondary)] text-[10px]"
                      >
                        分期还款<template v-if="tx.fee_amount && tx.fee_amount > 0"> · 含息费 {{ formatYuan(tx.fee_amount, false) }}</template>
                      </span>
                    </div>
                    <p v-if="tx.note" class="text-[11.5px] text-[var(--ink-muted)] truncate max-w-[440px] mt-0.5">
                      {{ tx.note }}
                    </p>
                  </div>
                </div>

                <div class="flex items-center gap-3 shrink-0">
                  <div class="opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity flex items-center gap-1">
                    <button
                      type="button"
                      class="p-1.5 rounded-lg hover:bg-[var(--paper-subtle)] text-[var(--ink-secondary)] cursor-pointer"
                      aria-label="编辑账目"
                      @click="appStore.transactionModal = { open: true, editing: tx }"
                    >
                      <Edit3 class="w-3.5 h-3.5" />
                    </button>
                    <button
                      type="button"
                      class="p-1.5 rounded-lg hover:bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] cursor-pointer"
                      aria-label="删除账目"
                      @click="askDeleteTx(tx)"
                    >
                      <Trash2 class="w-3.5 h-3.5" />
                    </button>
                  </div>

                  <span
                    class="font-mono-tabular text-[14.5px] font-semibold min-w-[92px] text-right"
                    :class="tx.type === 'income' ? 'text-[var(--accent-moss)]' : 'text-[var(--ink-primary)]'"
                  >
                    {{ tx.type === 'income' ? '+' : '-' }}{{ formatYuan(tx.amount) }}
                  </span>
                </div>
              </div>
            </div>
          </section>
        </div>

        <!-- 视图 2：可排序明细表 (per sortable-table guide) -->
        <div
          v-else
          class="rounded-2xl border border-[var(--border-subtle)] bg-[var(--paper-elevated)] overflow-x-auto"
          role="region"
          aria-label="收支明细表"
          tabindex="0"
        >
          <table class="w-full border-collapse text-left">
            <caption class="sr-only">收支流水明细表</caption>
            <thead>
              <tr class="border-b border-[var(--border-subtle)] bg-[var(--paper-subtle)]/55 text-[12px] text-[var(--ink-secondary)]">
                <th scope="col" class="w-[130px]" :aria-sort="sortField === 'occurred_at' ? sortDir : undefined">
                  <button type="button" class="sort-th-btn" @click="toggleSort('occurred_at')">
                    <span>日期</span>
                    <ArrowUp v-if="sortField === 'occurred_at' && sortDir === 'ascending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowDown v-else-if="sortField === 'occurred_at' && sortDir === 'descending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowUpDown v-else class="w-3 h-3 opacity-35" aria-hidden="true" />
                  </button>
                </th>
                <th scope="col" class="w-[130px]" :aria-sort="sortField === 'category' ? sortDir : undefined">
                  <button type="button" class="sort-th-btn" @click="toggleSort('category')">
                    <span>分类</span>
                    <ArrowUp v-if="sortField === 'category' && sortDir === 'ascending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowDown v-else-if="sortField === 'category' && sortDir === 'descending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowUpDown v-else class="w-3 h-3 opacity-35" aria-hidden="true" />
                  </button>
                </th>
                <th scope="col" :aria-sort="sortField === 'title' ? sortDir : undefined">
                  <button type="button" class="sort-th-btn" @click="toggleSort('title')">
                    <span>摘要</span>
                    <ArrowUp v-if="sortField === 'title' && sortDir === 'ascending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowDown v-else-if="sortField === 'title' && sortDir === 'descending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowUpDown v-else class="w-3 h-3 opacity-35" aria-hidden="true" />
                  </button>
                </th>
                <th scope="col" class="w-[150px]" :aria-sort="sortField === 'amount' ? sortDir : undefined">
                  <button type="button" class="sort-th-btn justify-end" @click="toggleSort('amount')">
                    <span>金额</span>
                    <ArrowUp v-if="sortField === 'amount' && sortDir === 'ascending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowDown v-else-if="sortField === 'amount' && sortDir === 'descending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowUpDown v-else class="w-3 h-3 opacity-35" aria-hidden="true" />
                  </button>
                </th>
                <th scope="col" class="w-[84px] px-3 py-2.5 text-right font-medium">操作</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-[var(--border-subtle)] text-[13px]">
              <tr v-for="tx in sortedTransactions" :key="tx.id" class="group hover:bg-[var(--paper-subtle)]/45">
                <td class="px-4 py-2.5 font-mono-tabular text-[12px] text-[var(--ink-secondary)] whitespace-nowrap">
                  {{ compactListDate(tx.occurred_at) }}
                </td>
                <td class="px-4 py-2.5 whitespace-nowrap">
                  <span class="inline-flex items-center gap-1.5 text-[12.5px]">
                    <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: categoryColorVar(tx.category) }" />
                    <span>{{ tx.category }}</span>
                  </span>
                </td>
                <td class="px-4 py-2.5">
                  <span class="font-medium">{{ tx.title || tx.category }}</span>
                  <span v-if="tx.payment_method" class="text-[11.5px] text-[var(--ink-muted)] ml-2">
                    {{ tx.payment_method }}
                  </span>
                </td>
                <td
                  class="px-4 py-2.5 text-right font-mono-tabular font-semibold whitespace-nowrap"
                  :class="tx.type === 'income' ? 'text-[var(--accent-moss)]' : 'text-[var(--ink-primary)]'"
                >
                  {{ tx.type === 'income' ? '+' : '-' }}{{ formatYuan(tx.amount) }}
                </td>
                <td class="px-3 py-2.5 text-right whitespace-nowrap">
                  <div class="inline-flex items-center gap-1 opacity-0 group-hover:opacity-100 focus-within:opacity-100">
                    <button
                      type="button"
                      class="p-1 rounded hover:bg-[var(--paper)] text-[var(--ink-secondary)] cursor-pointer"
                      aria-label="编辑账目"
                      @click="appStore.transactionModal = { open: true, editing: tx }"
                    >
                      <Edit3 class="w-3.5 h-3.5" />
                    </button>
                    <button
                      type="button"
                      class="p-1 rounded hover:bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] cursor-pointer"
                      aria-label="删除账目"
                      @click="askDeleteTx(tx)"
                    >
                      <Trash2 class="w-3.5 h-3.5" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
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
  @apply bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/40 text-[var(--accent-warm)] font-medium;
}
.sort-th-btn {
  @apply w-full px-4 py-2.5 flex items-center gap-1.5 font-medium text-left hover:text-[var(--ink-primary)] cursor-pointer;
}
</style>
