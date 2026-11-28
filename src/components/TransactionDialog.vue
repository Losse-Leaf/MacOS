<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { Check, X } from 'lucide-vue-next'
import { api } from '../services/api'
import { appStore, refreshAll, refreshMonthlySummary, showToast } from '../stores/appStore'
import {
  attachDialogLightDismiss,
  closeDialogAnimated,
  datetimeLocalToBeijingISO,
  parseYuanToCents,
  toDatetimeLocalValue,
} from '../utils/format'

const dialogRef = ref<HTMLDialogElement | null>(null)
const txType = ref<'expense' | 'income'>('expense')
const amountText = ref('')
const titleInput = ref('')
const category = ref('')
const paymentMethod = ref('')
const occurredLocal = ref('')
const noteInput = ref('')
const wantsInstallment = ref(false)
const installmentTouched = ref(false)
const channelCode = ref('')
const months = ref(12)
const repaymentDay = ref(10)
const isSaving = ref(false)
const errorMsg = ref('')

let cleanupLightDismiss: (() => void) | null = null

const isEditing = computed(() => Boolean(appStore.transactionModal.editing))
const isInstallmentRepay = computed(() => appStore.transactionModal.editing?.source === 'installment_repay')
const categoriesForType = computed(() =>
  txType.value === 'income' ? appStore.incomeCategories : appStore.expenseCategories,
)
const hasMissingSelectedCategory = computed(() => {
  const cat = category.value.trim()
  return Boolean(cat) && !categoriesForType.value.includes(cat)
})

function onChannelChange() {
  const matched = appStore.creditChannels.find((c) => c.code === channelCode.value)
  if (matched && matched.repayment_day > 0) {
    repaymentDay.value = matched.repayment_day
  }
}

watch(
  () => appStore.transactionModal.open,
  (open) => {
    const dlg = dialogRef.value
    if (!dlg) return
    if (open) {
      const target = appStore.transactionModal.editing
      if (target) {
        txType.value = target.type === 'income' ? 'income' : 'expense'
        amountText.value = (target.amount / 100).toFixed(2)
        titleInput.value = target.title
        category.value = target.category
        paymentMethod.value = target.payment_method ?? appStore.paymentMethods[0] ?? '微信支付'
        occurredLocal.value = toDatetimeLocalValue(target.occurred_at)
        noteInput.value = target.note ?? ''
        wantsInstallment.value = Boolean(target.is_installment)
        installmentTouched.value = false
        channelCode.value = target.installment_channel_code ?? appStore.creditChannels[0]?.code ?? ''
        months.value = target.installment_months ?? 12
        repaymentDay.value = target.repayment_day ?? appStore.creditChannels[0]?.repayment_day ?? 10
      } else {
        txType.value = 'expense'
        amountText.value = ''
        titleInput.value = ''
        category.value = appStore.expenseCategories[0] ?? '餐饮'
        paymentMethod.value = appStore.paymentMethods[0] ?? '微信支付'
        occurredLocal.value = toDatetimeLocalValue()
        noteInput.value = ''
        wantsInstallment.value = false
        installmentTouched.value = false
        channelCode.value = appStore.creditChannels[0]?.code ?? ''
        months.value = 12
        repaymentDay.value = appStore.creditChannels[0]?.repayment_day ?? 10
      }
      errorMsg.value = ''
      if (!dlg.open) dlg.showModal()
      cleanupLightDismiss?.()
      cleanupLightDismiss = attachDialogLightDismiss(dlg, closeModal)
    } else if (dlg.open) {
      void closeDialogAnimated(dlg)
    }
  },
)

onBeforeUnmount(() => cleanupLightDismiss?.())

function closeModal() {
  const dlg = dialogRef.value
  if (dlg?.open) {
    void closeDialogAnimated(dlg).then(() => {
      appStore.transactionModal = { open: false, editing: null }
    })
  } else {
    appStore.transactionModal = { open: false, editing: null }
  }
}

function handleCancel(e: Event) {
  e.preventDefault()
  closeModal()
}

async function submit() {
  if (isSaving.value) return
  const cents = parseYuanToCents(amountText.value)
  if (!cents || cents <= 0) {
    errorMsg.value = '请输入大于 0 的有效金额'
    return
  }

  isSaving.value = true
  errorMsg.value = ''
  try {
    const editing = appStore.transactionModal.editing
    const effCat = category.value || categoriesForType.value[0] || '其他'
    const effTitle = titleInput.value.trim() || effCat
    const occurredAt = datetimeLocalToBeijingISO(occurredLocal.value)

    if (!editing) {
      const payload = {
        amount: cents,
        type: txType.value,
        category: effCat,
        title: effTitle,
        note: noteInput.value.trim(),
        payment_method: paymentMethod.value,
        occurred_at: occurredAt,
        is_installment: txType.value === 'expense' && wantsInstallment.value ? true : undefined,
        installment_channel_code:
          txType.value === 'expense' && wantsInstallment.value ? channelCode.value || null : null,
        installment_total_amount: txType.value === 'expense' && wantsInstallment.value ? cents : null,
        installment_months: txType.value === 'expense' && wantsInstallment.value ? months.value : null,
        installment_monthly_pay:
          txType.value === 'expense' && wantsInstallment.value
            ? Math.floor(cents / Math.max(1, months.value))
            : null,
        installment_remain_months:
          txType.value === 'expense' && wantsInstallment.value ? months.value : null,
        repayment_day: txType.value === 'expense' && wantsInstallment.value ? repaymentDay.value : null,
        client_request_id: crypto.randomUUID(),
      }
      const created = await api.createTransaction(payload)
      appStore.transactions = [created, ...appStore.transactions]
      showToast(`已记入账本：¥ ${(cents / 100).toFixed(2)}`)
    } else {
      const wasInstallment = Boolean(editing.is_installment)
      const isExpense = txType.value === 'expense'
      const applyInstallment =
        isExpense && ((installmentTouched.value && wantsInstallment.value) || (!installmentTouched.value && wasInstallment))
      const cancelInstallment =
        (!isExpense && wasInstallment) || (isExpense && installmentTouched.value && !wantsInstallment.value && wasInstallment)

      const updated = await api.updateTransaction(editing.id, {
        amount: isInstallmentRepay.value ? editing.amount : cents,
        type: isInstallmentRepay.value ? 'expense' : txType.value,
        category: effCat,
        title: effTitle,
        note: noteInput.value.trim(),
        payment_method: paymentMethod.value,
        occurred_at: occurredAt,
        is_installment: applyInstallment ? true : cancelInstallment ? false : undefined,
        clear_installment: cancelInstallment || undefined,
        installment_channel_code: applyInstallment ? channelCode.value || editing.installment_channel_code : null,
        installment_total_amount: applyInstallment
          ? cents !== editing.amount
            ? cents
            : (editing.installment_total_amount ?? cents)
          : null,
        installment_months: applyInstallment ? months.value : null,
        installment_monthly_pay: applyInstallment
          ? Math.floor(
              (cents !== editing.amount ? cents : (editing.installment_total_amount ?? cents)) /
                Math.max(1, months.value),
            )
          : null,
        installment_remain_months: applyInstallment
          ? (editing.installment_remain_months ?? months.value)
          : null,
        repayment_day: applyInstallment ? repaymentDay.value : null,
      })

      const idx = appStore.transactions.findIndex((t) => t.id === updated.id)
      if (idx >= 0) appStore.transactions[idx] = updated
      showToast('已更新账目')
    }

    closeModal()
    await refreshMonthlySummary(appStore.selectedLedgerYear, appStore.selectedLedgerMonth)
    void refreshAll(true)
  } catch (err) {
    errorMsg.value = err instanceof Error ? err.message : '保存账目失败'
  } finally {
    isSaving.value = false
  }
}
</script>

<template>
  <dialog
    ref="dialogRef"
    closedby="any"
    aria-labelledby="tx-dialog-title"
    class="w-[520px] rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] shadow-xl overflow-hidden"
    @cancel="handleCancel"
    @close="appStore.transactionModal = { open: false, editing: null }"
  >
    <form class="flex flex-col" @submit.prevent="submit">
      <div class="px-6 py-4 border-b border-[var(--border-subtle)] flex items-center justify-between">
        <h2 id="tx-dialog-title" class="font-serif-editorial text-[17px] font-semibold">
          {{ isEditing ? '编辑收支账目' : '记一笔' }}
        </h2>
        <button
          type="button"
          class="p-1.5 rounded-lg text-[var(--ink-muted)] hover:bg-[var(--paper-subtle)] cursor-pointer"
          aria-label="关闭窗口"
          @click="closeModal"
        >
          <X class="w-4 h-4" />
        </button>
      </div>

      <div class="p-6 flex flex-col gap-4 max-h-[75vh] overflow-y-auto paper-scroll">
        <div class="flex items-center gap-2">
          <button
            type="button"
            :disabled="isInstallmentRepay"
            class="flex-1 py-1.5 rounded-lg text-[13px] font-medium border transition-colors cursor-pointer disabled:opacity-55 disabled:cursor-not-allowed"
            :class="
              txType === 'expense'
                ? 'bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/40 text-[var(--accent-warm)]'
                : 'bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)]'
            "
            @click="
              txType = 'expense';
              if (!categoriesForType.includes(category)) category = categoriesForType[0] || '其他';
            "
          >
            支出
          </button>
          <button
            type="button"
            :disabled="isInstallmentRepay"
            class="flex-1 py-1.5 rounded-lg text-[13px] font-medium border transition-colors cursor-pointer disabled:opacity-55 disabled:cursor-not-allowed"
            :class="
              txType === 'income'
                ? 'bg-[var(--accent-moss)]/12 border-[var(--accent-moss)]/40 text-[var(--accent-moss)]'
                : 'bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)]'
            "
            @click="
              txType = 'income';
              if (!categoriesForType.includes(category)) category = categoriesForType[0] || '工资';
            "
          >
            收入
          </button>
        </div>

        <p
          v-if="isInstallmentRepay"
          class="text-[11.5px] text-[var(--ink-muted)] bg-[var(--paper-subtle)] px-3 py-2 rounded-lg"
        >
          分期还款流水的金额与类型由分期计划管理，如需修改请在分期计划中撤销还款。
        </p>

        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>金额（元）</span>
            <input
              v-model="amountText"
              type="text"
              inputmode="decimal"
              :disabled="isInstallmentRepay"
              autofocus
              placeholder="0.00"
              class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[15px] text-[var(--ink-primary)] disabled:opacity-60"
            />
          </label>
          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>摘要</span>
            <input
              v-model="titleInput"
              type="text"
              placeholder="消费或入账摘要"
              class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[13px] text-[var(--ink-primary)]"
            />
          </label>
        </div>

        <div class="flex flex-col gap-1.5">
          <span class="text-[12px] text-[var(--ink-secondary)]">分类</span>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="cat in categoriesForType"
              :key="cat"
              type="button"
              class="px-2.5 py-1 rounded-full text-[12px] border cursor-pointer"
              :class="
                category === cat
                  ? 'bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/40 text-[var(--accent-warm)] font-medium'
                  : 'bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)]'
              "
              @click="category = cat"
            >
              {{ cat }}
            </button>
            <button
              v-if="hasMissingSelectedCategory"
              type="button"
              class="px-2.5 py-1 rounded-full text-[12px] border bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/40 text-[var(--accent-warm)] font-medium cursor-pointer"
            >
              {{ category }}
            </button>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>支付方式</span>
            <select
              v-model="paymentMethod"
              class="px-2.5 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12.5px] text-[var(--ink-primary)]"
            >
              <option v-for="pm in appStore.paymentMethods" :key="pm" :value="pm">{{ pm }}</option>
            </select>
          </label>
          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>发生时间</span>
            <input
              v-model="occurredLocal"
              type="datetime-local"
              class="px-2.5 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[12px] text-[var(--ink-primary)]"
            />
          </label>
        </div>

        <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>备注（可选）</span>
          <input
            v-model="noteInput"
            type="text"
            placeholder="补充说明"
            class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12.5px] text-[var(--ink-primary)]"
          />
        </label>

        <div
          v-if="txType === 'expense' && !isInstallmentRepay"
          class="p-3 rounded-xl bg-[var(--paper-subtle)]/70 border border-[var(--border-subtle)] flex flex-col gap-3"
        >
          <label class="inline-flex items-center justify-between cursor-pointer text-[12.5px]">
            <span>作为分期付款记录</span>
            <input
              v-model="wantsInstallment"
              type="checkbox"
              @change="installmentTouched = true"
            />
          </label>

          <div v-if="wantsInstallment" class="grid grid-cols-3 gap-2.5 pt-1">
            <label class="flex flex-col gap-1 text-[11.5px] text-[var(--ink-secondary)]">
              <span>信贷渠道</span>
              <select
                v-model="channelCode"
                class="px-2 py-1.5 rounded-lg bg-[var(--paper-elevated)] border border-[var(--border-subtle)] text-[12px]"
                @change="onChannelChange"
              >
                <option value="">默认渠道</option>
                <option v-for="ch in appStore.creditChannels" :key="ch.code" :value="ch.code">
                  {{ ch.name }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-[11.5px] text-[var(--ink-secondary)]">
              <span>分期期数</span>
              <input
                v-model.number="months"
                type="number"
                min="2"
                max="60"
                class="px-2 py-1.5 rounded-lg bg-[var(--paper-elevated)] border border-[var(--border-subtle)] font-mono-tabular text-[12px]"
              />
            </label>
            <label class="flex flex-col gap-1 text-[11.5px] text-[var(--ink-secondary)]">
              <span>每月还款日</span>
              <input
                v-model.number="repaymentDay"
                type="number"
                min="1"
                max="31"
                class="px-2 py-1.5 rounded-lg bg-[var(--paper-elevated)] border border-[var(--border-subtle)] font-mono-tabular text-[12px]"
              />
            </label>
          </div>
        </div>

        <p v-if="errorMsg" class="text-[12px] text-[var(--accent-warm)] bg-[var(--accent-warm-soft)] px-3 py-2 rounded-lg">
          {{ errorMsg }}
        </p>
      </div>

      <div class="px-6 py-3.5 border-t border-[var(--border-subtle)] flex items-center justify-end gap-2">
        <button
          type="button"
          class="px-3.5 py-1.5 rounded-lg border border-[var(--border-subtle)] text-[12.5px] text-[var(--ink-secondary)] cursor-pointer"
          @click="closeModal"
        >
          取消
        </button>
        <button
          type="submit"
          :disabled="isSaving"
          class="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-[var(--accent-warm)] text-white text-[12.5px] font-medium cursor-pointer disabled:opacity-50"
        >
          <Check class="w-3.5 h-3.5" />
          <span>{{ isSaving ? '保存中…' : '保存账目' }}</span>
        </button>
      </div>
    </form>
  </dialog>
</template>
