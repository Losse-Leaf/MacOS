<script setup lang="ts">
import { ref } from 'vue'
import { appStore } from '../stores/appStore'
import EntryListPane from './EntryListPane.vue'
import EntryReaderPane from './EntryReaderPane.vue'

const LIST_WIDTH_KEY = 'looseleaf_desktop_list_width_v1'
const saved = Number(typeof localStorage !== 'undefined' ? localStorage.getItem(LIST_WIDTH_KEY) : 0)
const listWidth = ref(Number.isFinite(saved) && saved >= 270 && saved <= 460 ? saved : 340)

function startResize(startEvent: PointerEvent) {
  const target = startEvent.currentTarget instanceof HTMLElement ? startEvent.currentTarget : null
  target?.setPointerCapture?.(startEvent.pointerId)
  const startX = startEvent.clientX
  const startWidth = listWidth.value
  const prevCursor = document.body.style.cursor
  document.body.style.cursor = 'col-resize'

  const onMove = (e: PointerEvent) => {
    const stageWidth = window.innerWidth - (appStore.sidebarCollapsed ? 16 : 240)
    const maxAllowed = Math.max(270, Math.min(460, stageWidth - 420))
    const next = Math.min(maxAllowed, Math.max(270, startWidth + (e.clientX - startX)))
    listWidth.value = next
  }
  const onUp = () => {
    document.body.style.cursor = prevCursor
    localStorage.setItem(LIST_WIDTH_KEY, String(listWidth.value))
    window.removeEventListener('pointermove', onMove)
    window.removeEventListener('pointerup', onUp)
    window.removeEventListener('pointercancel', onUp)
  }
  window.addEventListener('pointermove', onMove)
  window.addEventListener('pointerup', onUp)
  window.addEventListener('pointercancel', onUp)
}
</script>

<template>
  <div class="flex-1 min-h-0 flex w-full">
    <div :style="{ width: `${listWidth}px` }" class="shrink-0 h-full">
      <EntryListPane />
    </div>

    <div
      class="w-1 shrink-0 h-full cursor-col-resize hover:bg-[var(--accent-warm)]/30 transition-colors"
      title="拖动调整列表宽度"
      @pointerdown="startResize"
    />

    <div class="flex-1 min-w-0 h-full">
      <EntryReaderPane />
    </div>
  </div>
</template>
