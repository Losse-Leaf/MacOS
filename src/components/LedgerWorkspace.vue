<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  CalendarClock,
  ChevronLeft,
  ChevronRight,
  CreditCard,
  Edit3,
  Plus,
  Sparkles,
  Trash2,
} from 'lucide-vue-next'
import { api } from '../services/api'
import {
  appStore,
  refreshAll,
  refreshMonthlySummary,
  selectDestination,
  showToast,
} from '../stores/appStore'
import type { Transaction } from '../types/api'
import {
  beijingDateParts,
  categoryColorVar,
  compactListDate,
  formatBeijingISO,
  formatYuan,
  parseOccurredDate,
  parseQuickLedgerInput,
} from '../utils/format'

type SortField = 'occurred_at' | 'category' | 'title' | 'amount'
type SortDir = 'ascending' | 'descending'

const quickInput = ref('')
const isSubmittingQuick = ref(false)
const scopeFilter = ref<'month' | 'all'>('month')
const selectedCategory = ref<string>('all')
const sortField = ref<SortField>('occurred_at')
const sortDir = ref<SortDir>('descending')
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

const sortedTransactions = computed(() => {
  const factor = sortDir.value === 'ascending' ? 1 : -1
  return [...filteredTransactions.value].sort((a, b) => {
    if (sortField.value === 'occurred_at') {
      const ta = parseOccurredDate(a.occurred_at).timestamp
      const tb = parseOccurredDate(b.occurred_at).timestamp
      return factor * (ta - tb)
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
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto paper-scroll px-7 py-6 bg-[var(--paper)]">
    <div class="max-w-[1060px] mx-auto flex flex-col gap-5">
      <!-- 月度概览与类目光谱 -->
      <section class="p-4 rounded-2xl bg-[var(--paper-subtle)]/70 border border-[var(--border-subtle)] flex flex-col gap-3">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div class="flex items-center gap-2">
            <button
              type="button"
              class="p-1.5 rounded-lg hover:bg-[var(--paper-elevated)] text-[var(--ink-secondary)] cursor-pointer"
              aria-label="上一个月"
              @click="shiftMonth(-1)"
            >
              <ChevronLeft class="w-4 h-4" />
            </button>
            <span class="font-serif-editorial text-[16px] font-semibold text-[var(--ink-primary)] min-w-[96px] text-center">
              {{ appStore.selectedLedgerYear }}年{{ appStore.selectedLedgerMonth }}月
            </span>
            <button
              type="button"
              class="p-1.5 rounded-lg hover:bg-[var(--paper-elevated)] text-[var(--ink-secondary)] cursor-pointer"
              aria-label="下一个月"
              @click="shiftMonth(1)"
            >
              <ChevronRight class="w-4 h-4" />
            </button>
          </div>

          <div class="flex flex-wrap items-center gap-5 text-[13px] font-mono-tabular">
            <div class="flex items-baseline gap-1.5">
              <span class="text-[11.5px] font-sans text-[var(--ink-muted)]">支出</span>
              <span class="font-semibold text-[var(--accent-warm)]">
                {{ formatYuan(appStore.transactionSummary.total_expense) }}
              </span>
            </div>
            <div class="flex items-baseline gap-1.5">
              <span class="text-[11.5px] font-sans text-[var(--ink-muted)]">收入</span>
              <span class="font-semibold text-[var(--accent-moss)]">
                {{ formatYuan(appStore.transactionSummary.total_income) }}
              </span>
            </div>
            <div class="flex items-baseline gap-1.5">
              <span class="text-[11.5px] font-sans text-[var(--ink-muted)]">结余</span>
              <span class="font-semibold text-[var(--ink-primary)]">
                {{ formatYuan(appStore.transactionSummary.balance) }}
              </span>
            </div>
          </div>
        </div>

        <!-- 光谱条 -->
        <div
          v-if="spectrumBreakdown.length > 0"
          class="flex flex-col gap-2 pt-1"
        >
          <div class="h-2 w-full rounded-full overflow-hidden flex bg-[var(--paper)]">
            <div
              v-for="seg in spectrumBreakdown"
              :key="seg.category"
              :style="{
                width: `${seg.ratio * 100}%`,
                backgroundColor: categoryColorVar(seg.category),
              }"
              :title="`${seg.category}：${formatYuan(seg.cents)} (${seg.percent}%)`"
              class="h-full first:rounded-l-full last:rounded-r-full"
            />
          </div>
          <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-[11.5px] text-[var(--ink-secondary)]">
            <span v-for="seg in spectrumBreakdown.slice(0, 6)" :key="seg.category" class="inline-flex items-center gap-1.5">
              <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: categoryColorVar(seg.category) }" />
              <span>{{ seg.category }}</span>
              <span class="font-mono-tabular text-[var(--ink-muted)]">{{ formatYuan(seg.cents, false) }}</span>
            </span>
          </div>
        </div>
      </section>

      <!-- 快速记账条 -->
      <form
        class="p-2.5 pl-4 rounded-xl bg-[var(--paper-subtle)] border border-[var(--border-subtle)] flex flex-wrap items-center gap-2.5"
        @submit.prevent="submitQuick"
      >
        <Sparkles class="w-4 h-4 text-[var(--accent-warm)] shrink-0" />
        <input
          v-model="quickInput"
          type="text"
          placeholder="快速记账（如：42.5 咖啡，或 +3500 稿费）…"
          aria-label="快速记账输入"
          class="flex-1 min-w-[200px] bg-transparent text-[13px] text-[var(--ink-primary)] placeholder:text-[var(--ink-muted)]"
        />
        <span
          v-if="parsedQuick.amountCents"
          class="text-[11.5px] font-mono-tabular px-2 py-0.5 rounded-md bg-[var(--paper-elevated)] text-[var(--ink-secondary)]"
        >
          {{ parsedQuick.type === 'income' ? '收入' : '支出' }} {{ formatYuan(parsedQuick.amountCents) }}
        </span>
        <button
          type="submit"
          :disabled="!parsedQuick.amountCents || isSubmittingQuick"
          class="px-3.5 py-1.5 rounded-lg bg-[var(--accent-warm)] text-white text-[12px] font-medium disabled:opacity-40 cursor-pointer"
        >
          {{ isSubmittingQuick ? '记入中…' : '记入账本' }}
        </button>
        <button
          type="button"
          class="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg bg-[var(--paper-elevated)] border border-[var(--border-subtle)] text-[12px] text-[var(--ink-secondary)] hover:text-[var(--ink-primary)] cursor-pointer"
          @click="appStore.transactionModal = { open: true, editing: null }"
        >
          <Plus class="w-3.5 h-3.5" />
          <span>详细表单</span>
        </button>
      </form>

      <!-- 筛选栏 -->
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-1.5 overflow-x-auto pb-1">
          <button
            type="button"
            class="chip-btn"
            :class="scopeFilter === 'month' ? 'chip-active' : 'chip-idle'"
            @click="scopeFilter = 'month'"
          >
            {{ appStore.selectedLedgerMonth }}月流水
          </button>
          <button
            type="button"
            class="chip-btn"
            :class="scopeFilter === 'all' ? 'chip-active' : 'chip-idle'"
            @click="scopeFilter = 'all'"
          >
            全部历史
          </button>

          <span class="w-px h-4 bg-[var(--border-subtle)] mx-1" />

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

        <button
          type="button"
          class="inline-flex items-center gap-1.5 text-[12px] text-[var(--ink-secondary)] hover:text-[var(--accent-warm)] cursor-pointer"
          @click="selectDestination({ kind: 'installments' })"
        >
          <CalendarClock class="w-3.5 h-3.5" />
          <span>查看分期计划</span>
        </button>
      </div>

      <!-- 语义化可排序流水表格 (per sortable-table guide) -->
      <div class="rounded-2xl border border-[var(--border-subtle)] bg-[var(--paper-elevated)] overflow-hidden">
        <div v-if="sortedTransactions.length === 0" class="py-16 flex flex-col items-center justify-center gap-2.5 text-[var(--ink-muted)]">
          <CreditCard class="w-8 h-8 opacity-60" />
          <div class="font-serif-editorial text-[16px] text-[var(--ink-primary)]">尚无符合条件的账目流水</div>
          <p class="text-[12px]">可在上方快速记账，或点击右上角「记一笔」录入收支与分期。</p>
        </div>

        <div v-else class="overflow-x-auto" role="region" aria-label="收支流水表" tabindex="0">
          <table class="w-full border-collapse text-left">
            <caption class="sr-only">收支流水明细表</caption>
            <thead>
              <tr class="border-b border-[var(--border-subtle)] bg-[var(--paper-subtle)]/55 text-[12px] text-[var(--ink-secondary)]">
                <th
                  scope="col"
                  class="w-[140px]"
                  :aria-sort="sortField === 'occurred_at' ? sortDir : undefined"
                >
                  <button type="button" class="sort-th-btn" @click="toggleSort('occurred_at')">
                    <span>日期</span>
                    <ArrowUp v-if="sortField === 'occurred_at' && sortDir === 'ascending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowDown v-else-if="sortField === 'occurred_at' && sortDir === 'descending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowUpDown v-else class="w-3 h-3 opacity-35" aria-hidden="true" />
                  </button>
                </th>
                <th
                  scope="col"
                  class="w-[140px]"
                  :aria-sort="sortField === 'category' ? sortDir : undefined"
                >
                  <button type="button" class="sort-th-btn" @click="toggleSort('category')">
                    <span>分类</span>
                    <ArrowUp v-if="sortField === 'category' && sortDir === 'ascending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowDown v-else-if="sortField === 'category' && sortDir === 'descending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowUpDown v-else class="w-3 h-3 opacity-35" aria-hidden="true" />
                  </button>
                </th>
                <th
                  scope="col"
                  :aria-sort="sortField === 'title' ? sortDir : undefined"
                >
                  <button type="button" class="sort-th-btn" @click="toggleSort('title')">
                    <span>摘要与支付方式</span>
                    <ArrowUp v-if="sortField === 'title' && sortDir === 'ascending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowDown v-else-if="sortField === 'title' && sortDir === 'descending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowUpDown v-else class="w-3 h-3 opacity-35" aria-hidden="true" />
                  </button>
                </th>
                <th
                  scope="col"
                  class="w-[160px]"
                  :aria-sort="sortField === 'amount' ? sortDir : undefined"
                >
                  <button type="button" class="sort-th-btn justify-end" @click="toggleSort('amount')">
                    <span>金额</span>
                    <ArrowUp v-if="sortField === 'amount' && sortDir === 'ascending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowDown v-else-if="sortField === 'amount' && sortDir === 'descending'" class="w-3 h-3" aria-hidden="true" />
                    <ArrowUpDown v-else class="w-3 h-3 opacity-35" aria-hidden="true" />
                  </button>
                </th>
                <th scope="col" class="w-[88px] px-3 py-2.5 text-right font-medium">操作</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-[var(--border-subtle)] text-[13px]">
              <tr
                v-for="tx in sortedTransactions"
                :key="tx.id"
                class="group hover:bg-[var(--paper-subtle)]/50 transition-colors"
              >
                <td class="px-4 py-2.5 font-mono-tabular text-[12px] text-[var(--ink-secondary)] whitespace-nowrap">
                  {{ compactListDate(tx.occurred_at) }}
                </td>
                <td class="px-4 py-2.5 whitespace-nowrap">
                  <span class="inline-flex items-center gap-1.5 text-[12.5px]">
                    <span
                      class="w-2 h-2 rounded-full shrink-0"
                      :style="{ backgroundColor: categoryColorVar(tx.category) }"
                    />
                    <span>{{ tx.category }}</span>
                  </span>
                </td>
                <td class="px-4 py-2.5">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="font-medium text-[var(--ink-primary)]">{{ tx.title || tx.category }}</span>
                    <span
                      v-if="tx.is_installment && tx.installment_months"
                      class="px-1.5 py-0.5 rounded bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] font-mono-tabular text-[10.5px]"
                    >
                      分期 {{ tx.installment_remain_months ?? tx.installment_months }}/{{ tx.installment_months }} 期
                    </span>
                    <span v-if="tx.payment_method" class="text-[11.5px] text-[var(--ink-muted)]">
                      · {{ tx.payment_method }}
                    </span>
                  </div>
                  <p v-if="tx.note" class="text-[11.5px] text-[var(--ink-muted)] mt-0.5 truncate max-w-[380px]">
                    {{ tx.note }}
                  </p>
                </td>
                <td
                  class="px-4 py-2.5 text-right font-mono-tabular font-semibold whitespace-nowrap"
                  :class="tx.type === 'income' ? 'text-[var(--accent-moss)]' : 'text-[var(--ink-primary)]'"
                >
                  {{ tx.type === 'income' ? '+' : '-' }}{{ formatYuan(tx.amount) }}
                </td>
                <td class="px-3 py-2.5 text-right whitespace-nowrap">
                  <div class="inline-flex items-center gap-1 opacity-0 group-hover:opacity-100 focus-within:opacity-100 transition-opacity">
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
