<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { ChevronLeft, ChevronRight, ExternalLink, X } from 'lucide-vue-next'
import { openExternalUrl } from '../services/credentials'
import { appStore, mediaUrl } from '../stores/appStore'
import { attachDialogLightDismiss } from '../utils/format'

const dialogRef = ref<HTMLDialogElement | null>(null)
const currentIndex = ref(0)
let cleanupLightDismiss: (() => void) | null = null

const currentAttachment = computed(() => {
  const list = appStore.lightboxState?.attachments ?? []
  return list[currentIndex.value] ?? null
})

watch(
  () => appStore.lightboxState,
  (state) => {
    const dlg = dialogRef.value
    if (!dlg) return
    if (state) {
      currentIndex.value = state.index
      if (!dlg.open) dlg.showModal()
      cleanupLightDismiss?.()
      cleanupLightDismiss = attachDialogLightDismiss(dlg, closeModal)
    } else if (dlg.open) {
      dlg.close()
    }
  },
)

onBeforeUnmount(() => cleanupLightDismiss?.())

function closeModal() {
  appStore.lightboxState = null
}

function prev() {
  const len = appStore.lightboxState?.attachments.length ?? 0
  if (len <= 1) return
  currentIndex.value = (currentIndex.value - 1 + len) % len
}

function next() {
  const len = appStore.lightboxState?.attachments.length ?? 0
  if (len <= 1) return
  currentIndex.value = (currentIndex.value + 1) % len
}
</script>

<template>
  <dialog
    ref="dialogRef"
    closedby="any"
    aria-labelledby="lightbox-filename"
    class="w-[90vw] max-w-[1100px] h-[86vh] rounded-2xl bg-[#141312] text-[#EDE8E1] border border-white/10 shadow-2xl overflow-hidden"
    @close="closeModal"
    @keydown.left.prevent="prev"
    @keydown.right.prevent="next"
  >
    <div class="h-full flex flex-col">
      <div class="h-12 px-4 border-b border-white/10 flex items-center justify-between gap-3">
        <span id="lightbox-filename" class="text-[12.5px] font-mono-tabular text-white/80 truncate">
          {{ currentAttachment?.original_filename || '原图预览' }}
          <span v-if="(appStore.lightboxState?.attachments.length ?? 0) > 1" class="text-white/45 ml-2">
            {{ currentIndex + 1 }} / {{ appStore.lightboxState?.attachments.length }}
          </span>
        </span>

        <div class="flex items-center gap-2">
          <button
            v-if="currentAttachment"
            type="button"
            class="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-white/10 hover:bg-white/15 text-[12px] cursor-pointer"
            @click="openExternalUrl(mediaUrl(currentAttachment.url))"
          >
            <ExternalLink class="w-3.5 h-3.5" />
            <span>浏览器打开原图</span>
          </button>
          <button
            type="button"
            class="p-1.5 rounded-lg hover:bg-white/10 cursor-pointer"
            aria-label="关闭大图预览"
            @click="closeModal"
          >
            <X class="w-4 h-4" />
          </button>
        </div>
      </div>

      <div class="relative flex-1 min-h-0 flex items-center justify-center p-6">
        <button
          v-if="(appStore.lightboxState?.attachments.length ?? 0) > 1"
          type="button"
          class="absolute left-4 p-2.5 rounded-full bg-black/50 hover:bg-black/75 text-white cursor-pointer"
          aria-label="上一张"
          @click="prev"
        >
          <ChevronLeft class="w-5 h-5" />
        </button>

        <img
          v-if="currentAttachment"
          :src="mediaUrl(currentAttachment.url)"
          :alt="currentAttachment.original_filename"
          class="max-w-full max-h-full object-contain rounded-lg select-none"
        />

        <button
          v-if="(appStore.lightboxState?.attachments.length ?? 0) > 1"
          type="button"
          class="absolute right-4 p-2.5 rounded-full bg-black/50 hover:bg-black/75 text-white cursor-pointer"
          aria-label="下一张"
          @click="next"
        >
          <ChevronRight class="w-5 h-5" />
        </button>
      </div>
    </div>
  </dialog>
</template>
