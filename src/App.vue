<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { AlertTriangle, CheckCircle2, RefreshCw } from 'lucide-vue-next'
import ConfirmDialog from './components/ConfirmDialog.vue'
import GlobalSearchDialog from './components/GlobalSearchDialog.vue'
import InstallmentsWorkspace from './components/InstallmentsWorkspace.vue'
import LedgerWorkspace from './components/LedgerWorkspace.vue'
import LightboxDialog from './components/LightboxDialog.vue'
import NewEntryDialog from './components/NewEntryDialog.vue'
import PairingGate from './components/PairingGate.vue'
import ResolveWishDialog from './components/ResolveWishDialog.vue'
import SettingsView from './components/SettingsView.vue'
import SidebarNav from './components/SidebarNav.vue'
import StreamWorkspace from './components/StreamWorkspace.vue'
import TopBar from './components/TopBar.vue'
import TransactionDialog from './components/TransactionDialog.vue'
import WishDialog from './components/WishDialog.vue'
import WishlistWorkspace from './components/WishlistWorkspace.vue'
import {
  appStore,
  bootstrapApp,
  displayedStreamEntries,
  isStreamDestination,
  refreshAll,
  selectDestination,
  selectEntry,
  triggerPrimaryCreate,
} from './stores/appStore'

const topBarRef = ref<InstanceType<typeof TopBar> | null>(null)

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false
  const tag = target.tagName.toLowerCase()
  return tag === 'input' || tag === 'textarea' || tag === 'select' || target.isContentEditable
}

function handleGlobalKeydown(e: KeyboardEvent) {
  if (!appStore.isPaired) return
  const meta = e.metaKey || e.ctrlKey
  const key = e.key.toLowerCase()

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
    topBarRef.value?.focusSearch()
    return
  }
  if (meta && key === ',') {
    e.preventDefault()
    selectDestination({ kind: 'settings' })
    return
  }
  if (meta && key === 'e' && isStreamDestination(appStore.destination) && appStore.selectedEntryId) {
    e.preventDefault()
    appStore.editEntryToken += 1
    return
  }
  if (meta && key === '1') {
    e.preventDefault()
    selectDestination({ kind: 'all' })
    return
  }
  if (meta && key === '2') {
    e.preventDefault()
    selectDestination({ kind: 'ledger' })
    return
  }
  if (meta && key === '3') {
    e.preventDefault()
    selectDestination({ kind: 'installments' })
    return
  }
  if (meta && key === '4') {
    e.preventDefault()
    selectDestination({ kind: 'wishlist' })
    return
  }

  if (!meta && !isTypingTarget(e.target) && isStreamDestination(appStore.destination)) {
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
  <div v-if="appStore.booting" class="h-full w-full flex items-center justify-center bg-[var(--paper)]">
    <RefreshCw class="w-5 h-5 animate-spin text-[var(--accent-warm)]" />
  </div>

  <PairingGate v-else-if="!appStore.isPaired" />

  <div v-else class="h-full w-full flex bg-[var(--paper)] text-[var(--ink-primary)] overflow-hidden">
    <SidebarNav />

    <main class="flex-1 min-w-0 h-full flex flex-col">
      <TopBar ref="topBarRef" />

      <StreamWorkspace v-if="isStreamDestination(appStore.destination)" />
      <LedgerWorkspace v-else-if="appStore.destination.kind === 'ledger'" />
      <InstallmentsWorkspace v-else-if="appStore.destination.kind === 'installments'" />
      <WishlistWorkspace v-else-if="appStore.destination.kind === 'wishlist'" />
      <SettingsView v-else />
    </main>

    <!-- 全局弹窗 -->
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
