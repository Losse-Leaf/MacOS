<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { Check, X } from 'lucide-vue-next'
import { api } from '../services/api'
import { appStore, refreshAll, showToast } from '../stores/appStore'
import { attachDialogLightDismiss, closeDialogAnimated, parseYuanToCents } from '../utils/format'

const dialogRef = ref<HTMLDialogElement | null>(null)
const titleInput = ref('')
const kind = ref<'item' | 'travel' | 'milestone'>('item')
const specInput = ref('')
const noteInput = ref('')
const budgetText = ref('')
const targetDate = ref('')
const isPrivate = ref(false)
const isSaving = ref(false)
const errorMsg = ref('')

let cleanupLightDismiss: (() => void) | null = null
const isEditing = computed(() => Boolean(appStore.wishModal.editing))

watch(
  () => appStore.wishModal.open,
  (open) => {
    const dlg = dialogRef.value
    if (!dlg) return
    if (open) {
      const target = appStore.wishModal.editing
      if (target) {
        titleInput.value = target.title
        kind.value = target.kind === 'travel' ? 'travel' : target.kind === 'milestone' ? 'milestone' : 'item'
        specInput.value = target.spec ?? ''
        noteInput.value = target.note ?? ''
        budgetText.value = target.budget > 0 ? (target.budget / 100).toFixed(2) : ''
        targetDate.value = target.target_date ?? ''
        isPrivate.value = Boolean(target.is_private)
      } else {
        titleInput.value = ''
        kind.value = 'item'
        specInput.value = ''
        noteInput.value = ''
        budgetText.value = ''
        targetDate.value = ''
        isPrivate.value = false
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
      appStore.wishModal = { open: false, editing: null }
    })
  } else {
    appStore.wishModal = { open: false, editing: null }
  }
}

function handleCancel(e: Event) {
  e.preventDefault()
  closeModal()
}

async function submit() {
  if (isSaving.value) return
  if (!titleInput.value.trim()) {
    errorMsg.value = '心愿标题不能为空'
    return
  }
  const budget = budgetText.value.trim() ? (parseYuanToCents(budgetText.value) ?? 0) : 0
  isSaving.value = true
  errorMsg.value = ''
  try {
    const editing = appStore.wishModal.editing
    const payload = {
      title: titleInput.value.trim(),
      kind: kind.value,
      spec: specInput.value.trim() || null,
      note: noteInput.value.trim() || null,
      budget,
      target_date: targetDate.value.trim() || null,
      is_private: isPrivate.value,
    }
    if (editing) {
      await api.updateWish(editing.id, payload)
      showToast('已更新心愿')
    } else {
      await api.createWish(payload)
      showToast('已种下新心愿')
    }
    closeModal()
    await refreshAll(true)
  } catch (err) {
    errorMsg.value = err instanceof Error ? err.message : '保存心愿失败'
  } finally {
    isSaving.value = false
  }
}
</script>

<template>
  <dialog
    ref="dialogRef"
    closedby="any"
    aria-labelledby="wish-dialog-title"
    class="w-[500px] rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] shadow-xl overflow-hidden"
    @cancel="handleCancel"
    @close="appStore.wishModal = { open: false, editing: null }"
  >
    <form class="flex flex-col" @submit.prevent="submit">
      <div class="px-6 py-4 border-b border-[var(--border-subtle)] flex items-center justify-between">
        <h2 id="wish-dialog-title" class="font-serif-editorial text-[17px] font-semibold">
          {{ isEditing ? '编辑心愿' : '许下新心愿' }}
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
            v-for="item in [
              { id: 'item', label: '心愿好物' },
              { id: 'travel', label: '向往旅程' },
              { id: 'milestone', label: '人生里程碑' },
            ] as const"
            :key="item.id"
            type="button"
            class="flex-1 py-1.5 rounded-lg text-[12.5px] border cursor-pointer"
            :class="
              kind === item.id
                ? 'bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/40 text-[var(--accent-warm)] font-medium'
                : 'bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)]'
            "
            @click="kind = item.id"
          >
            {{ item.label }}
          </button>
        </div>

        <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>心愿名称</span>
          <input
            v-model="titleInput"
            type="text"
            autofocus
            placeholder="想要实现的目标或物品"
            class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[13.5px] text-[var(--ink-primary)]"
          />
        </label>

        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>预期预算（元，可选）</span>
            <input
              v-model="budgetText"
              type="text"
              inputmode="decimal"
              placeholder="0.00"
              class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[13px] text-[var(--ink-primary)]"
            />
          </label>
          <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
            <span>目标日期（可选）</span>
            <input
              v-model="targetDate"
              type="date"
              class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-mono-tabular text-[12.5px] text-[var(--ink-primary)]"
            />
          </label>
        </div>

        <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>规格 / 细节（可选）</span>
          <input
            v-model="specInput"
            type="text"
            placeholder="例如：银色 32G / 秋季去 Kyoto"
            class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12.5px] text-[var(--ink-primary)]"
          />
        </label>

        <label class="flex flex-col gap-1 text-[12px] text-[var(--ink-secondary)]">
          <span>缘由备注</span>
          <textarea
            v-model="noteInput"
            rows="3"
            placeholder="为什么想实现它…"
            class="px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12.5px] text-[var(--ink-primary)]"
          />
        </label>

        <label class="inline-flex items-center gap-2 text-[12.5px] text-[var(--ink-secondary)] cursor-pointer">
          <input v-model="isPrivate" type="checkbox" />
          <span>仅自己可见</span>
        </label>

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
          <span>{{ isSaving ? '保存中…' : '保存心愿' }}</span>
        </button>
      </div>
    </form>
  </dialog>
</template>
