<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'
import { Check, X } from 'lucide-vue-next'
import { api } from '../services/api'
import { appStore, refreshAll, showToast } from '../stores/appStore'
import {
  attachDialogLightDismiss,
  closeDialogAnimated,
  datetimeLocalToBeijingISO,
  parseYuanToCents,
  toDatetimeLocalValue,
} from '../utils/format'

const dialogRef = ref<HTMLDialogElement | null>(null)
const resolutionType = ref<'exact' | 'altered' | 'relinquished'>('exact')
const actualTitle = ref('')
const actualCostText = ref('')
const fulfilledLocal = ref('')
const createTransaction = ref(true)
const createLifeEntry = ref(true)
const entryContent = ref('')
const isSaving = ref(false)
const errorMsg = ref('')

let cleanupLightDismiss: (() => void) | null = null

watch(
  () => appStore.resolveWishTarget,
  (target) => {
    const dlg = dialogRef.value
    if (!dlg) return
    if (target) {
      resolutionType.value = 'exact'
      actualTitle.value = target.title
      actualCostText.value = target.budget > 0 ? (target.budget / 100).toFixed(2) : '0'
      fulfilledLocal.value = toDatetimeLocalValue()
      createTransaction.value = target.budget > 0
      createLifeEntry.value = true
      entryContent.value = `心愿「${target.title}」终于如愿以偿。`
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
      appStore.resolveWishTarget = null
    })
  } else {
    appStore.resolveWishTarget = null
  }
}

function handleCancel(e: Event) {
  e.preventDefault()
  closeModal()
}

async function submit() {
  const target = appStore.resolveWishTarget
  if (!target || isSaving.value) return
  const cost = actualCostText.value.trim() ? (parseYuanToCents(actualCostText.value) ?? 0) : 0
  isSaving.value = true
  errorMsg.value = ''
  try {
    await api.resolveWish(target.id, {
      fulfilled_at: datetimeLocalToBeijingISO(fulfilledLocal.value),
      actual_cost: cost,
      resolution_type: resolutionType.value,
      actual_title: actualTitle.value.trim() || null,
      create_transaction: resolutionType.value !== 'relinquished' && createTransaction.value && cost > 0,
      create_life_entry: createLifeEntry.value,
      entry_content: createLifeEntry.value ? entryContent.value.trim() : null,
    })
    closeModal()
    showToast(`心愿「${target.title}」已圆满归档`)
    await refreshAll(true)
  } catch (err) {
    errorMsg.value = err instanceof Error ? err.message : '操作失败'
  } finally {
    isSaving.value = false
  }
}
</script>

<template>
  <dialog
    ref="dialogRef"
    closedby="any"
    aria-labelledby="resolve-wish-title"
    class="w-[500px] rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] shadow-xl overflow-hidden"
    @cancel="handleCancel"
    @close="appStore.resolveWishTarget = null"
  >
    <form class="flex flex-col" @submit.prevent="submit">
      <div class="px-6 py-4 border-b border-[var(--border-subtle)] flex items-center justify-between">
        <h2 id="resolve-wish-title" class="font-serif-editorial text-[17px] font-semibold">
          圆满实现心愿
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

      <div class="p-6 flex flex-col gap-4">
        <div class="flex items-center gap-2">
          <button
            v-for="opt in [
              { id: 'exact', label: '如愿达成' },
              { id: 'altered', label: '平替/改期' },
              { id: 'relinquished', label: '主动释怀' },
            ] as const"
            :key="opt.id"
            type="button"
            class="flex-1 py-1.5 rounded-lg text-[12.5px] border cursor-pointer"
            :class="
              resolutionType === opt.id
                ? 'bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/40 text-[var(--accent-warm)] font-medium'
                : 'bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)]'
            "
            @click="resolutionType = opt.id"
          >
            {{ opt.label }}
          </button>
        </div>

        <label v-if="resolutionType === 'altered'" class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>实际实现内容</span>
          <input
            v-model="actualTitle"
            type="text"
            class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[13px]"
          />
        </label>

        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>实际花费（元）</span>
            <input
              v-model="actualCostText"
              type="text"
              inputmode="decimal"
              autofocus
              class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[13px]"
            />
          </label>
          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>达成时间</span>
            <input
              v-model="fulfilledLocal"
              type="datetime-local"
              class="px-2.5 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[12px]"
            />
          </label>
        </div>

        <div class="flex flex-col gap-2 text-[12.5px] text-[var(--ink-secondary)]">
          <label v-if="resolutionType !== 'relinquished'" class="inline-flex items-center gap-2 cursor-pointer">
            <input v-model="createTransaction" type="checkbox" />
            <span>同步记入收支流水</span>
          </label>
          <label class="inline-flex items-center gap-2 cursor-pointer">
            <input v-model="createLifeEntry" type="checkbox" />
            <span>同步生成一篇散页纪念</span>
          </label>
        </div>

        <textarea
          v-if="createLifeEntry"
          v-model="entryContent"
          rows="3"
          placeholder="记录这一刻的心境…"
          class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[13px]"
        />

        <p v-if="errorMsg" class="text-[12px] text-[var(--accent-warm)] bg-[var(--accent-warm-soft)] px-3 py-2 rounded-lg">
          {{ errorMsg }}
        </p>
      </div>

      <div class="px-6 py-3.5 border-t border-[var(--border-subtle)] flex justify-end gap-2">
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
          <span>{{ isSaving ? '归档中…' : '确认圆满' }}</span>
        </button>
      </div>
    </form>
  </dialog>
</template>
