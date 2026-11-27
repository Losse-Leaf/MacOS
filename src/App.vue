<script setup lang="ts">
import { onBeforeUnmount, onMounted } from 'vue'
import { AlertTriangle, CheckCircle2, PanelLeftOpen, RefreshCw } from 'lucide-vue-next'
import ConfirmDialog from './components/ConfirmDialog.vue'
import GalleryWorkspace from './components/GalleryWorkspace.vue'
import GlobalSearchDialog from './components/GlobalSearchDialog.vue'
import LedgerWorkspace from './components/LedgerWorkspace.vue'
import LightboxDialog from './components/LightboxDialog.vue'
import NewEntryDialog from './components/NewEntryDialog.vue'
import PairingGate from './components/PairingGate.vue'
import ResolveWishDialog from './components/ResolveWishDialog.vue'
import SettingsView from './components/SettingsView.vue'
import SidebarNav from './components/SidebarNav.vue'
import StreamWorkspace from './components/StreamWorkspace.vue'
import TransactionDialog from './components/TransactionDialog.vue'
import WishDialog from './components/WishDialog.vue'
import WishlistWorkspace from './components/WishlistWorkspace.vue'
import {
  appStore,
  bootstrapApp,
  displayedStreamEntries,
  refreshAll,
  selectEntry,
  selectSpace,
  toggleSidebar,
  triggerPrimaryCreate,
} from './stores/appStore'

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false
  const tag = target.tagName.toLowerCase()
  return tag === 'input' || tag === 'textarea' || tag === 'select' || target.isContentEditable
}

function handleGlobalKeydown(e: KeyboardEvent) {
  if (!appStore.isPaired) return
  const meta = e.metaKey || e.ctrlKey
  const key = e.key.toLowerCase()

  if (meta && e.key === '\\') {
    e.preventDefault()
    toggleSidebar()
    return
  }
  if (meta && key === 'k') {
    e.preventDefault()
    appStore.showGlobalSearch = true
    return
  }
  if (meta && key === 'n') {
    e.preventDefault()
    triggerPrimaryCreate()
    return
  }
  if (meta && key === 'r') {
    e.preventDefault()
    void refreshAll(false)
    return
  }
  if (meta && key === 'f') {
    e.preventDefault()
    window.dispatchEvent(new CustomEvent('looseleaf-focus-filter'))
    return
  }
  if (meta && key === ',') {
    e.preventDefault()
    selectSpace('settings')
    return
  }
  if (meta && key === 'e' && appStore.activeSpace === 'journal' && appStore.selectedEntryId) {
    e.preventDefault()
    appStore.editEntryToken += 1
    return
  }
  if (meta && key === '1') {
    e.preventDefault()
    selectSpace('journal')
    return
  }
  if (meta && key === '2') {
    e.preventDefault()
    selectSpace('gallery')
    return
  }
  if (meta && key === '3') {
    e.preventDefault()
    selectSpace('ledger')
    return
  }
  if (meta && key === '4') {
    e.preventDefault()
    selectSpace('wishlist')
    return
  }

  if (!meta && !isTypingTarget(e.target) && appStore.activeSpace === 'journal') {
    const list = displayedStreamEntries.value
    if (!list.length) return
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      const idx = list.findIndex((x) => x.id === appStore.selectedEntryId)
      const nextIdx =
        idx < 0
          ? 0
          : e.key === 'ArrowDown'
            ? Math.min(list.length - 1, idx + 1)
            : Math.max(0, idx - 1)
      void selectEntry(list[nextIdx].id)
    }
  }
}

onMounted(() => {
  void bootstrapApp()
  window.addEventListener('keydown', handleGlobalKeydown)
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleGlobalKeydown)
})
</script>

<template>
  <div v-if="appStore.booting" class="h-full w-full flex items-center justify-center bg-[var(--canvas)]">
    <RefreshCw class="w-5 h-5 animate-spin text-[var(--accent-warm)]" />
  </div>

  <PairingGate v-else-if="!appStore.isPaired" />

  <div
    v-else
    class="h-full w-full flex bg-[var(--canvas)] text-[var(--ink-primary)] overflow-hidden p-2 transition-[padding] duration-200"
    :class="appStore.sidebarCollapsed ? 'pl-2' : 'pl-0'"
  >
    <SidebarNav />

    <!-- 浮动纸张主舞台 -->
    <main
      class="relative flex-1 min-w-0 h-full rounded-2xl bg-[var(--paper)] border border-[var(--border-subtle)] overflow-hidden flex flex-col"
      style="box-shadow: var(--shadow-stage);"
    >
      <!-- 侧栏折叠时的呼出按钮（避开交通灯区域） -->
      <button
        v-if="appStore.sidebarCollapsed"
        type="button"
        class="tauri-no-drag absolute top-3 left-20 z-30 p-1.5 rounded-lg bg-[var(--paper-subtle)]/90 border border-[var(--border-subtle)] text-[var(--ink-secondary)] hover:text-[var(--ink-primary)] shadow-xs cursor-pointer"
        title="展开侧栏 (⌘\)"
        aria-label="展开侧栏"
        @click="toggleSidebar"
      >
        <PanelLeftOpen class="w-4 h-4" />
      </button>

      <Transition name="stage-fade" mode="out-in">
        <StreamWorkspace v-if="appStore.activeSpace === 'journal'" key="journal" />
        <GalleryWorkspace v-else-if="appStore.activeSpace === 'gallery'" key="gallery" />
        <LedgerWorkspace v-else-if="appStore.activeSpace === 'ledger'" key="ledger" />
        <WishlistWorkspace v-else-if="appStore.activeSpace === 'wishlist'" key="wishlist" />
        <SettingsView v-else key="settings" />
      </Transition>
    </main>

    <!-- 全局弹窗（均接入原生 top-layer 入离场动效） -->
    <NewEntryDialog />
    <TransactionDialog />
    <WishDialog />
    <ResolveWishDialog />
    <GlobalSearchDialog />
    <LightboxDialog />
    <ConfirmDialog />

    <!-- Toast 浮层 -->
    <div
      v-if="appStore.toast"
      role="status"
      class="fixed bottom-5 right-5 z-50 px-4 py-2.5 rounded-xl bg-[var(--paper-elevated)] border border-[var(--border-divider)] shadow-lg flex items-center gap-2 text-[12.5px]"
    >
      <AlertTriangle v-if="appStore.toast.isError" class="w-4 h-4 text-[var(--accent-warm)] shrink-0" />
      <CheckCircle2 v-else class="w-4 h-4 text-[var(--accent-moss)] shrink-0" />
      <span>{{ appStore.toast.message }}</span>
    </div>
  </div>
</template>
