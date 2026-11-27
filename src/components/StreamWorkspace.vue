<script setup lang="ts">
import { ref } from 'vue'
import EntryListPane from './EntryListPane.vue'
import EntryReaderPane from './EntryReaderPane.vue'

const listWidth = ref(316)

function startResize(startEvent: PointerEvent) {
  const startX = startEvent.clientX
  const startWidth = listWidth.value
  const onMove = (e: PointerEvent) => {
    const next = Math.min(440, Math.max(250, startWidth + (e.clientX - startX)))
    listWidth.value = next
  }
  const onUp = () => {
    window.removeEventListener('pointermove', onMove)
    window.removeEventListener('pointerup', onUp)
  }
  window.addEventListener('pointermove', onMove)
  window.addEventListener('pointerup', onUp)
}
</script>

<template>
  <div class="flex-1 min-h-0 flex w-full">
    <div :style="{ width: `${listWidth}px` }" class="shrink-0 h-full">
      <EntryListPane />
    </div>

    <div
      class="w-1 shrink-0 h-full cursor-col-resize hover:bg-[var(--accent-warm)]/35 transition-colors"
      title="拖动调整列表宽度"
      @pointerdown="startResize"
    />

    <div class="flex-1 min-w-0 h-full">
      <EntryReaderPane />
    </div>
  </div>
</template>
