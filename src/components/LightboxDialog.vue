<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { ChevronLeft, ChevronRight, ExternalLink, X, ZoomIn, ZoomOut } from 'lucide-vue-next'
import { openExternalUrl } from '../services/credentials'
import { appStore, mediaUrl } from '../stores/appStore'
import { attachDialogLightDismiss, closeDialogAnimated } from '../utils/format'

const dialogRef = ref<HTMLDialogElement | null>(null)
const currentIndex = ref(0)
const zoomed = ref(false)
let cleanupLightDismiss: (() => void) | null = null

const attachments = computed(() => appStore.lightboxState?.attachments ?? [])
const currentAttachment = computed(() => attachments.value[currentIndex.value] ?? null)

watch(
  () => appStore.lightboxState,
  (state) => {
    const dlg = dialogRef.value
    if (!dlg) return
    if (state) {
      currentIndex.value = state.index
      zoomed.value = false
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
      appStore.lightboxState = null
    })
  } else {
    appStore.lightboxState = null
  }
}

function handleCancel(e: Event) {
  e.preventDefault()
  closeModal()
}

function prev() {
  const len = attachments.value.length
  if (len <= 1) return
  zoomed.value = false
  currentIndex.value = (currentIndex.value - 1 + len) % len
}

function next() {
  const len = attachments.value.length
  if (len <= 1) return
  zoomed.value = false
  currentIndex.value = (currentIndex.value + 1) % len
}
</script>

<template>
  <dialog
    ref="dialogRef"
    closedby="any"
    aria-labelledby="lightbox-filename"
    class="w-[92vw] max-w-[1160px] h-[88vh] rounded-2xl bg-[#11100F] text-[#EDE8E1] border border-white/10 shadow-2xl overflow-hidden"
    @cancel="handleCancel"
    @close="appStore.lightboxState = null"
    @keydown.left.prevent="prev"
    @keydown.right.prevent="next"
  >
    <div class="h-full flex flex-col">
      <div class="h-12 shrink-0 px-4 border-b border-white/10 flex items-center justify-between gap-3">
        <span id="lightbox-filename" class="text-[12.5px] font-mono-tabular text-white/80 truncate">
          {{ currentAttachment?.original_filename || '暗房原图' }}
          <span v-if="attachments.length > 1" class="text-white/45 ml-2">
            {{ currentIndex + 1 }} / {{ attachments.length }}
          </span>
        </span>

        <div class="flex items-center gap-1.5">
          <button
            type="button"
            class="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-white/10 hover:bg-white/15 text-[12px] cursor-pointer"
            @click="zoomed = !zoomed"
          >
            <ZoomOut v-if="zoomed" class="w-3.5 h-3.5" />
            <ZoomIn v-else class="w-3.5 h-3.5" />
            <span>{{ zoomed ? '1×' : '1.8×' }}</span>
          </button>

          <button
            v-if="currentAttachment"
            type="button"
            class="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-white/10 hover:bg-white/15 text-[12px] cursor-pointer"
            @click="openExternalUrl(mediaUrl(currentAttachment.url))"
          >
            <ExternalLink class="w-3.5 h-3.5" />
            <span>原图链接</span>
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

      <div class="relative flex-1 min-h-0 flex items-center justify-center p-6 overflow-auto">
        <button
          v-if="attachments.length > 1"
          type="button"
          class="fixed left-8 z-10 p-2.5 rounded-full bg-black/55 hover:bg-black/80 text-white cursor-pointer"
          aria-label="上一张"
          @click="prev"
        >
          <ChevronLeft class="w-5 h-5" />
        </button>

        <img
          v-if="currentAttachment"
          :src="mediaUrl(currentAttachment.url)"
          :alt="currentAttachment.original_filename"
          class="rounded-lg select-none transition-transform duration-200 cursor-zoom-in"
          :class="zoomed ? 'scale-[1.75] cursor-zoom-out' : 'max-w-full max-h-full object-contain'"
          @click="zoomed = !zoomed"
        />

        <button
          v-if="attachments.length > 1"
          type="button"
          class="fixed right-8 z-10 p-2.5 rounded-full bg-black/55 hover:bg-black/80 text-white cursor-pointer"
          aria-label="下一张"
          @click="next"
        >
          <ChevronRight class="w-5 h-5" />
        </button>
      </div>

      <!-- 胶片缩略图选片条 -->
      <div
        v-if="attachments.length > 1"
        class="h-18 shrink-0 px-4 border-t border-white/10 flex items-center justify-center gap-2 overflow-x-auto"
      >
        <button
          v-for="(att, idx) in attachments"
          :key="att.id"
          type="button"
          class="w-12 h-12 shrink-0 rounded-lg overflow-hidden border-2 transition-all cursor-pointer"
          :class="idx === currentIndex ? 'border-[var(--accent-warm-dark)] opacity-100 scale-105' : 'border-transparent opacity-50 hover:opacity-85'"
          @click="
            zoomed = false;
            currentIndex = idx
          "
        >
          <img
            :src="mediaUrl(att.thumbnail_url || att.url)"
            :alt="att.original_filename"
            class="w-full h-full object-cover"
          />
        </button>
      </div>
    </div>
  </dialog>
</template>
