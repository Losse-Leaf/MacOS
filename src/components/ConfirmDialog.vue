<script setup lang="ts">
import { ref, watch } from 'vue'
import { appStore } from '../stores/appStore'

const dialogRef = ref<HTMLDialogElement | null>(null)
const isRunning = ref(false)

watch(
  () => appStore.confirmRequest,
  (req) => {
    const dlg = dialogRef.value
    if (!dlg) return
    if (req) {
      if (!dlg.open) dlg.showModal()
    } else if (dlg.open) {
      dlg.close()
    }
  },
)

function cancel() {
  if (isRunning.value) return
  appStore.confirmRequest = null
}

async function confirmAction() {
  const req = appStore.confirmRequest
  if (!req || isRunning.value) return
  isRunning.value = true
  try {
    await req.onConfirm()
    appStore.confirmRequest = null
  } finally {
    isRunning.value = false
  }
}
</script>

<template>
  <dialog
    ref="dialogRef"
    aria-labelledby="confirm-dialog-title"
    class="w-[380px] rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] shadow-2xl overflow-hidden"
    @close="cancel"
  >
    <form v-if="appStore.confirmRequest" method="dialog" class="p-5 flex flex-col gap-3" @submit.prevent="confirmAction">
      <h2 id="confirm-dialog-title" class="font-serif-editorial text-[16px] font-semibold text-[var(--ink-primary)]">
        {{ appStore.confirmRequest.title }}
      </h2>
      <p class="text-[13px] leading-relaxed text-[var(--ink-secondary)]">
        {{ appStore.confirmRequest.message }}
      </p>
      <div class="pt-2 flex items-center justify-end gap-2">
        <button
          type="button"
          autofocus
          class="px-3.5 py-1.5 rounded-lg border border-[var(--border-subtle)] text-[12.5px] text-[var(--ink-secondary)] hover:bg-[var(--paper-subtle)] cursor-pointer"
          @click="cancel"
        >
          {{ appStore.confirmRequest.cancelText || '取消' }}
        </button>
        <button
          type="submit"
          :disabled="isRunning"
          class="px-3.5 py-1.5 rounded-lg text-[12.5px] font-medium text-white cursor-pointer disabled:opacity-50"
          :class="appStore.confirmRequest.danger ? 'bg-[var(--accent-warm)]' : 'bg-[var(--accent-moss)]'"
        >
          {{ isRunning ? '处理中…' : appStore.confirmRequest.confirmText }}
        </button>
      </div>
    </form>
  </dialog>
</template>
