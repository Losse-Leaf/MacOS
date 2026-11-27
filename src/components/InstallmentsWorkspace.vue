<script setup lang="ts">
import { computed, ref } from 'vue'
import { CalendarClock, CheckCircle2, ChevronDown, ChevronRight, Plus, RotateCcw, Trash2 } from 'lucide-vue-next'
import { api } from '../services/api'
import { appStore, refreshAll, showToast } from '../stores/appStore'
import type { InstallmentPlanDetail, InstallmentPlanSummary } from '../types/api'
import { formatYuan, parseYuanToCents } from '../utils/format'

const expandedPlanId = ref<number | null>(null)
const detailByPlanId = ref<Record<number, InstallmentPlanDetail>>({})
const loadingDetailId = ref<number | null>(null)
const showCreateForm = ref(false)
const newTitle = ref('')
const newPrincipal = ref('')
const newPeriods = ref(12)
const newFeeMode = ref<'none' | 'fixed_per_period' | 'total_fee'>('none')
const newFeeText = ref('0')
const newChannelCode = ref('')
const newRepayDay = ref(10)
const isCreating = ref(false)

const filteredPlans = computed(() => {
  const q = appStore.searchQuery.trim().toLowerCase()
  return appStore.installmentPlans.filter((p) => {
    if (!q) return true
    return `${p.title} ${p.channel_name ?? ''} ${p.category_name ?? ''}`.toLowerCase().includes(q)
  })
})

const totalRemainingCents = computed(() =>
  appStore.installmentPlans
    .filter((p) => p.status === 'active')
    .reduce((acc, p) => acc + p.remaining_total, 0),
)

async function toggleExpand(plan: InstallmentPlanSummary) {
  if (expandedPlanId.value === plan.id) {
    expandedPlanId.value = null
    return
  }
  expandedPlanId.value = plan.id
  await loadDetail(plan.id)
}

async function loadDetail(planId: number) {
  loadingDetailId.value = planId
  try {
    detailByPlanId.value[planId] = await api.fetchInstallmentPlanDetail(planId)
  } catch (err) {
    showToast(err instanceof Error ? err.message : '加载期次明细失败', true)
  } finally {
    loadingDetailId.value = null
  }
}

async function payItem(planId: number, itemId: number) {
  try {
    await api.payInstallmentItem(itemId, {
      pay_account: appStore.paymentMethods[0] || '银行卡',
    })
    showToast('已标记本期已还并自动生成还款流水')
    await Promise.all([loadDetail(planId), refreshAll(true)])
  } catch (err) {
    showToast(err instanceof Error ? err.message : '操作失败', true)
  }
}

async function unpayItem(planId: number, itemId: number) {
  try {
    await api.unpayInstallmentItem(itemId)
    showToast('已撤销本期还款状态')
    await Promise.all([loadDetail(planId), refreshAll(true)])
  } catch (err) {
    showToast(err instanceof Error ? err.message : '撤销失败', true)
  }
}

function settlePlan(plan: InstallmentPlanSummary) {
  appStore.confirmRequest = {
    title: '提前结清全部分期？',
    message: `将把「${plan.title}」剩余所有期次标记为已还并生成还款流水。`,
    confirmText: '确认结清',
    danger: false,
    onConfirm: async () => {
      await api.settleInstallmentPlan(plan.id)
      showToast('分期计划已全部结清')
      await Promise.all([loadDetail(plan.id), refreshAll(true)])
    },
  }
}

function deletePlan(plan: InstallmentPlanSummary) {
  appStore.confirmRequest = {
    title: '删除分期计划？',
    message: `确定删除分期计划「${plan.title}」吗？`,
    confirmText: '删除',
    danger: true,
    onConfirm: async () => {
      await api.deleteInstallmentPlan(plan.id)
      if (expandedPlanId.value === plan.id) expandedPlanId.value = null
      showToast('已删除分期计划')
      await refreshAll(true)
    },
  }
}

async function submitNewPlan() {
  if (isCreating.value) return
  const principal = parseYuanToCents(newPrincipal.value)
  if (!newTitle.value.trim() || !principal || principal <= 0) {
    showToast('请填写名称和有效本金', true)
    return
  }
  const feeValue = newFeeMode.value === 'none' ? 0 : (parseYuanToCents(newFeeText.value) ?? 0)
  isCreating.value = true
  try {
    await api.createInstallmentPlan({
      title: newTitle.value.trim(),
      channel_code: newChannelCode.value || appStore.creditChannels[0]?.code,
      kind: 'expense',
      principal,
      periods: newPeriods.value,
      fee_mode: newFeeMode.value,
      fee_value: feeValue,
      repay_day: newRepayDay.value,
      category_name: appStore.expenseCategories[0] || '购物',
    })
    newTitle.value = ''
    newPrincipal.value = ''
    showCreateForm.value = false
    showToast('已创建分期还款计划')
    await refreshAll(true)
  } catch (err) {
    showToast(err instanceof Error ? err.message : '创建分期失败', true)
  } finally {
    isCreating.value = false
  }
}
</script>

<template>
  <div class="flex-1 min-h-0 overflow-y-auto paper-scroll px-8 py-6 bg-[var(--paper)]">
    <div class="max-w-[980px] mx-auto flex flex-col gap-5 pb-10">
      <div class="flex flex-wrap items-end justify-between gap-4 pb-5 border-b border-[var(--border-subtle)]">
        <div class="flex items-end gap-8">
          <div>
            <div class="text-[11.5px] text-[var(--ink-muted)]">剩余待还总额（含手续费）</div>
            <div class="font-mono-tabular text-[30px] font-semibold text-[var(--accent-warm)] leading-none mt-1">
              {{ formatYuan(totalRemainingCents) }}
            </div>
          </div>
          <div>
            <div class="text-[11.5px] text-[var(--ink-muted)]">进行中计划</div>
            <div class="font-mono-tabular text-[18px] font-semibold text-[var(--ink-primary)] mt-0.5">
              {{ appStore.installmentPlans.filter((p) => p.status === 'active').length }} 笔
            </div>
          </div>
        </div>

        <button
          type="button"
          class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-[var(--accent-warm)] text-white text-[12.5px] font-medium cursor-pointer hover:opacity-92"
          @click="showCreateForm = !showCreateForm"
        >
          <Plus class="w-3.5 h-3.5" />
          <span>{{ showCreateForm ? '收起表单' : '新建分期' }}</span>
        </button>
      </div>

      <form
        v-if="showCreateForm"
        class="p-4 rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-divider)] grid grid-cols-6 gap-3 items-end"
        @submit.prevent="submitNewPlan"
      >
        <label class="col-span-2 flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>计划名称</span>
          <input
            v-model="newTitle"
            type="text"
            placeholder="例如：MacBook Pro"
            class="px-3 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12.5px]"
          />
        </label>
        <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>本金（元）</span>
          <input
            v-model="newPrincipal"
            type="text"
            placeholder="6000"
            class="px-3 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[12.5px]"
          />
        </label>
        <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>期数</span>
          <input
            v-model.number="newPeriods"
            type="number"
            min="1"
            max="120"
            class="px-3 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[12.5px]"
          />
        </label>
        <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>手续费</span>
          <select
            v-model="newFeeMode"
            class="px-2 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12px]"
          >
            <option value="none">免息分期</option>
            <option value="fixed_per_period">每期固定(元)</option>
            <option value="total_fee">总手续费(元)</option>
          </select>
        </label>
        <div class="flex items-center gap-2">
          <input
            v-if="newFeeMode !== 'none'"
            v-model="newFeeText"
            type="text"
            placeholder="手续费"
            class="w-20 px-2 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[12px]"
          />
          <button
            type="submit"
            :disabled="isCreating"
            class="flex-1 py-1.5 px-3 rounded-lg bg-[var(--ink-primary)] text-[var(--paper)] text-[12.5px] font-medium cursor-pointer"
          >
            {{ isCreating ? '创建中…' : '创建' }}
          </button>
        </div>
      </form>

      <div
        v-if="filteredPlans.length === 0"
        class="py-16 flex flex-col items-center justify-center gap-2 text-[var(--ink-muted)]"
      >
        <CalendarClock class="w-8 h-8 opacity-45" />
        <div class="font-serif-editorial text-[16px] text-[var(--ink-primary)]">暂无分期计划</div>
        <p class="text-[12px]">在记账时勾选分期或在此新建分期计划后，各期还款进度将在此展示。</p>
      </div>

      <div v-else class="flex flex-col gap-3">
        <div
          v-for="plan in filteredPlans"
          :key="plan.id"
          class="rounded-2xl border border-[var(--border-subtle)] bg-[var(--paper-elevated)] overflow-hidden"
        >
          <div class="p-4 flex flex-wrap items-center justify-between gap-4">
            <button
              type="button"
              class="flex items-center gap-3 text-left flex-1 min-w-[240px] cursor-pointer"
              @click="toggleExpand(plan)"
            >
              <ChevronDown v-if="expandedPlanId === plan.id" class="w-4 h-4 text-[var(--ink-muted)]" />
              <ChevronRight v-else class="w-4 h-4 text-[var(--ink-muted)]" />
              <div class="flex flex-col gap-0.5">
                <div class="flex items-center gap-2">
                  <span class="font-semibold text-[14.5px] text-[var(--ink-primary)]">{{ plan.title }}</span>
                  <span
                    class="px-2 py-0.5 rounded-full text-[11px] font-medium"
                    :class="
                      plan.status === 'settled'
                        ? 'bg-[var(--accent-moss-soft)] text-[var(--accent-moss)]'
                        : plan.is_overdue
                          ? 'bg-[var(--accent-warm-soft)] text-[var(--accent-warm)]'
                          : 'bg-[var(--paper-subtle)] text-[var(--ink-secondary)]'
                    "
                  >
                    {{ plan.status === 'settled' ? '已结清' : plan.is_overdue ? `逾期 ${plan.overdue_days} 天` : `已还 ${plan.paid_periods}/${plan.periods} 期` }}
                  </span>
                </div>
                <div class="text-[12px] text-[var(--ink-muted)] font-mono-tabular">
                  本金 {{ formatYuan(plan.principal) }} · {{ plan.channel_name || plan.channel_code }} · 每月 {{ plan.repay_day }} 日
                </div>
              </div>
            </button>

            <div class="flex items-center gap-4">
              <div class="text-right">
                <div class="text-[11px] text-[var(--ink-muted)]">待还总额</div>
                <div class="font-mono-tabular text-[15px] font-semibold text-[var(--ink-primary)]">
                  {{ formatYuan(plan.remaining_total) }}
                </div>
              </div>

              <button
                v-if="plan.status === 'active'"
                type="button"
                class="px-2.5 py-1 rounded-lg bg-[var(--paper-subtle)] text-[12px] text-[var(--ink-secondary)] hover:text-[var(--ink-primary)] cursor-pointer"
                @click="settlePlan(plan)"
              >
                提前结清
              </button>
              <button
                type="button"
                class="p-1.5 rounded-lg text-[var(--ink-muted)] hover:text-[var(--accent-warm)] hover:bg-[var(--accent-warm-soft)] cursor-pointer"
                aria-label="删除分期计划"
                @click="deletePlan(plan)"
              >
                <Trash2 class="w-4 h-4" />
              </button>
            </div>
          </div>

          <div
            v-if="expandedPlanId === plan.id"
            class="border-t border-[var(--border-subtle)] bg-[var(--paper-subtle)]/40 px-5 py-3"
          >
            <div v-if="loadingDetailId === plan.id" class="py-4 text-center text-[12px] text-[var(--ink-muted)]">
              加载期次明细…
            </div>
            <table
              v-else-if="detailByPlanId[plan.id]?.items?.length"
              class="w-full text-[12.5px] border-collapse"
            >
              <thead>
                <tr class="text-[11.5px] text-[var(--ink-muted)] border-b border-[var(--border-subtle)]">
                  <th class="py-1.5 text-left font-medium">期次</th>
                  <th class="py-1.5 text-left font-medium">到期日</th>
                  <th class="py-1.5 text-right font-medium">应还本金</th>
                  <th class="py-1.5 text-right font-medium">手续费</th>
                  <th class="py-1.5 text-right font-medium">状态</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-[var(--border-subtle)]">
                <tr v-for="item in detailByPlanId[plan.id].items" :key="item.id">
                  <td class="py-2 font-mono-tabular">第 {{ item.seq }} 期</td>
                  <td class="py-2 font-mono-tabular text-[var(--ink-secondary)]">{{ item.due_date }}</td>
                  <td class="py-2 text-right font-mono-tabular">{{ formatYuan(item.principal_part) }}</td>
                  <td class="py-2 text-right font-mono-tabular text-[var(--ink-muted)]">{{ formatYuan(item.fee_part) }}</td>
                  <td class="py-2 text-right">
                    <button
                      v-if="item.status !== 'paid'"
                      type="button"
                      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-md bg-[var(--accent-warm-soft)] text-[var(--accent-warm)] text-[11.5px] font-medium hover:opacity-90 cursor-pointer"
                      @click="payItem(plan.id, item.id)"
                    >
                      <CheckCircle2 class="w-3 h-3" />
                      <span>标记已还</span>
                    </button>
                    <button
                      v-else
                      type="button"
                      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-md text-[11.5px] text-[var(--accent-moss)] hover:bg-[var(--paper)] cursor-pointer"
                      @click="unpayItem(plan.id, item.id)"
                    >
                      <RotateCcw class="w-3 h-3" />
                      <span>已还（撤销）</span>
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
