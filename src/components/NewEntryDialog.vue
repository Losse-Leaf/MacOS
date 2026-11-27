<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'
import { Check, ImagePlus, Lock, MapPin, X } from 'lucide-vue-next'
import { api } from '../services/api'
import { appStore, mediaUrl, refreshAll, selectSpace, showToast } from '../stores/appStore'
import type { Attachment, EntryCategory } from '../types/api'
import {
  ALL_ENTRY_CATEGORIES,
  attachDialogLightDismiss,
  closeDialogAnimated,
  datetimeLocalToBeijingISO,
  toDatetimeLocalValue,
} from '../utils/format'

const dialogRef = ref<HTMLDialogElement | null>(null)
const titleInput = ref('')
const contentInput = ref('')
const category = ref<EntryCategory>('daily')
const locationInput = ref('')
const occurredLocal = ref(toDatetimeLocalValue())
const isPrivate = ref(false)
const attachments = ref<Attachment[]>([])
const isUploading = ref(false)
const isSaving = ref(false)
const errorMsg = ref('')
const fileInputRef = ref<HTMLInputElement | null>(null)
const isDragOver = ref(false)

let cleanupLightDismiss: (() => void) | null = null

watch(
  () => appStore.showNewEntryModal,
  (open) => {
    const dlg = dialogRef.value
    if (!dlg) return
    if (open) {
      titleInput.value = ''
      contentInput.value = ''
      category.value =
        appStore.activeSpace === 'gallery' && appStore.galleryCategory !== 'all'
          ? appStore.galleryCategory
          : 'daily'
      locationInput.value = appStore.profile.current_city || appStore.profile.location || ''
      occurredLocal.value = toDatetimeLocalValue()
      isPrivate.value = appStore.activeSpace === 'journal' && appStore.journalFilter === 'private'
      attachments.value = []
      errorMsg.value = ''
      if (!dlg.open) dlg.showModal()
      cleanupLightDismiss?.()
      cleanupLightDismiss = attachDialogLightDismiss(dlg, closeModal)
    } else if (dlg.open) {
      void closeDialogAnimated(dlg)
    }
  },
)

onBeforeUnmount(() => {
  cleanupLightDismiss?.()
})

function closeModal() {
  const dlg = dialogRef.value
  if (dlg?.open) {
    void closeDialogAnimated(dlg).then(() => {
      appStore.showNewEntryModal = false
    })
  } else {
    appStore.showNewEntryModal = false
  }
}

function handleCancel(e: Event) {
  e.preventDefault()
  closeModal()
}

async function handleFiles(files: FileList | File[]) {
  const imgs = Array.from(files).filter((f) => f.type.startsWith('image/'))
  if (!imgs.length) return
  isUploading.value = true
  errorMsg.value = ''
  try {
    for (const file of imgs) {
      const uploaded = await api.uploadImageFile(file)
      attachments.value.push(uploaded)
    }
  } catch (err) {
    errorMsg.value = err instanceof Error ? err.message : '图片上传失败'
  } finally {
    isUploading.value = false
  }
}

function handlePaste(e: ClipboardEvent) {
  if (!e.clipboardData) return
  const imgs: File[] = []
  for (const item of Array.from(e.clipboardData.items)) {
    if (item.type.startsWith('image/')) {
      const f = item.getAsFile()
      if (f) imgs.push(f)
    }
  }
  if (imgs.length) {
    e.preventDefault()
    void handleFiles(imgs)
  }
}

async function submit() {
  if (isSaving.value || isUploading.value) return
  const cleanTitle = titleInput.value.trim()
  const cleanContent = contentInput.value.trim()
  if (!cleanTitle && !cleanContent && attachments.value.length === 0) {
    errorMsg.value = '写点内容或添加一张照片吧'
    return
  }

  isSaving.value = true
  errorMsg.value = ''
  try {
    const created = await api.createEntry({
      type: 'life',
      category: category.value === 'daily' ? '' : category.value,
      title: cleanTitle,
      content: cleanContent,
      occurred_at: datetimeLocalToBeijingISO(occurredLocal.value),
      location: locationInput.value.trim() || null,
      is_private: isPrivate.value,
      attachment_ids: attachments.value.map((a) => a.id),
      client_request_id: crypto.randomUUID(),
    })

    appStore.entries = [created, ...appStore.entries]
    selectSpace('journal', { journalFilter: 'all' })
    appStore.selectedEntryId = created.id
    closeModal()
    showToast('已归入散页时间流')
    void refreshAll(true)
  } catch (err) {
    errorMsg.value = err instanceof Error ? err.message : '保存散页失败'
  } finally {
    isSaving.value = false
  }
}
</script>

<template>
  <dialog
    ref="dialogRef"
    closedby="any"
    aria-labelledby="new-entry-dialog-title"
    class="w-[680px] rounded-2xl bg-[var(--paper-elevated)] border border-[var(--border-subtle)] shadow-xl overflow-hidden"
    @cancel="handleCancel"
    @close="appStore.showNewEntryModal = false"
  >
    <div
      class="flex flex-col max-h-[85vh]"
      :class="{ 'ring-2 ring-inset ring-[var(--accent-warm)]': isDragOver }"
      @paste="handlePaste"
      @dragover.prevent="isDragOver = true"
      @dragleave="isDragOver = false"
      @drop.prevent="
        (e) => {
          isDragOver = false;
          if (e.dataTransfer?.files) void handleFiles(e.dataTransfer.files);
        }
      "
    >
      <div class="px-6 py-4 border-b border-[var(--border-subtle)] flex items-center justify-between">
        <h2 id="new-entry-dialog-title" class="font-serif-editorial text-[17px] font-semibold">
          写散页
        </h2>
        <button
          type="button"
          class="p-1.5 rounded-lg text-[var(--ink-muted)] hover:bg-[var(--paper-subtle)] hover:text-[var(--ink-primary)] cursor-pointer"
          aria-label="关闭窗口"
          @click="closeModal"
        >
          <X class="w-4 h-4" />
        </button>
      </div>

      <div class="p-6 overflow-y-auto paper-scroll flex flex-col gap-4">
        <div class="flex flex-wrap items-center gap-1.5">
          <span class="text-[12px] text-[var(--ink-muted)] mr-1">分类：</span>
          <button
            v-for="cat in ALL_ENTRY_CATEGORIES"
            :key="cat.id"
            type="button"
            class="px-2.5 py-1 rounded-full text-[12px] border transition-colors cursor-pointer"
            :class="
              category === cat.id
                ? 'bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/40 text-[var(--accent-warm)] font-medium'
                : 'bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)] hover:text-[var(--ink-primary)]'
            "
            @click="category = cat.id"
          >
            {{ cat.label }}
          </button>
        </div>

        <input
          v-model="titleInput"
          type="text"
          placeholder="标题（可选，留空自动取正文首行）"
          aria-label="标题"
          class="w-full px-3 py-2 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] font-serif-editorial text-[16px] text-[var(--ink-primary)]"
        />

        <textarea
          v-model="contentInput"
          rows="7"
          autofocus
          placeholder="此刻在想什么… 可直接 ⌘V 粘贴或拖入照片"
          aria-label="散页正文"
          class="w-full p-3.5 rounded-xl bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[14px] leading-relaxed text-[var(--ink-primary)] resize-y min-h-[160px]"
          @keydown.meta.enter.prevent="submit"
        />

        <div class="flex flex-wrap items-center gap-3">
          <input
            v-model="occurredLocal"
            type="datetime-local"
            aria-label="发生时刻"
            class="px-2.5 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12px] font-mono-tabular"
          />
          <div class="flex-1 min-w-[180px] flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)]">
            <MapPin class="w-3.5 h-3.5 text-[var(--ink-muted)]" />
            <input
              v-model="locationInput"
              type="text"
              placeholder="地点（可选）"
              aria-label="地点"
              class="w-full bg-transparent text-[12px] text-[var(--ink-primary)]"
            />
          </div>
        </div>

        <div class="p-3 rounded-xl bg-[var(--paper-subtle)]/70 border border-[var(--border-subtle)] flex flex-col gap-2.5">
          <div class="flex items-center justify-between">
            <span class="text-[12px] text-[var(--ink-secondary)]">
              照片附件（{{ attachments.length }}）
            </span>
            <div>
              <input
                ref="fileInputRef"
                type="file"
                accept="image/*"
                multiple
                class="hidden"
                @change="
                  (e) => {
                    const files = (e.target as HTMLInputElement).files;
                    if (files) void handleFiles(files);
                  }
                "
              />
              <button
                type="button"
                :disabled="isUploading"
                class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[var(--paper-elevated)] border border-[var(--border-subtle)] text-[12px] cursor-pointer hover:border-[var(--border-divider)]"
                @click="fileInputRef?.click()"
              >
                <ImagePlus class="w-3.5 h-3.5 text-[var(--accent-warm)]" />
                <span>{{ isUploading ? '上传中…' : '选择照片' }}</span>
              </button>
            </div>
          </div>

          <div v-if="attachments.length > 0" class="grid grid-cols-5 gap-2">
            <div
              v-for="(att, idx) in attachments"
              :key="att.id"
              class="relative aspect-square rounded-lg overflow-hidden bg-[var(--paper)] border border-[var(--border-subtle)] group"
            >
              <img :src="mediaUrl(att.thumbnail_url || att.url)" :alt="att.original_filename" class="w-full h-full object-cover" />
              <button
                type="button"
                class="absolute top-1 right-1 w-5 h-5 rounded-full bg-black/65 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 cursor-pointer"
                aria-label="移除照片"
                @click="attachments.splice(idx, 1)"
              >
                <X class="w-3 h-3" />
              </button>
            </div>
          </div>
        </div>

        <p v-if="errorMsg" class="text-[12px] text-[var(--accent-warm)] bg-[var(--accent-warm-soft)] px-3 py-2 rounded-lg">
          {{ errorMsg }}
        </p>
      </div>

      <div class="px-6 py-3.5 border-t border-[var(--border-subtle)] flex items-center justify-between">
        <label class="inline-flex items-center gap-1.5 text-[12.5px] text-[var(--ink-secondary)] cursor-pointer">
          <input v-model="isPrivate" type="checkbox" />
          <Lock class="w-3.5 h-3.5" :class="isPrivate ? 'text-[var(--accent-warm)]' : 'text-[var(--ink-muted)]'" />
          <span>仅自己可见</span>
        </label>

        <div class="flex items-center gap-2">
          <button
            type="button"
            class="px-3.5 py-1.5 rounded-lg border border-[var(--border-subtle)] text-[12.5px] text-[var(--ink-secondary)] hover:bg-[var(--paper-subtle)] cursor-pointer"
            @click="closeModal"
          >
            取消
          </button>
          <button
            type="button"
            :disabled="isSaving || isUploading"
            class="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-[var(--accent-warm)] text-white text-[12.5px] font-medium hover:opacity-92 disabled:opacity-50 cursor-pointer"
            @click="submit"
          >
            <Check class="w-3.5 h-3.5" />
            <span>{{ isSaving ? '归档中…' : '定格散页 (⌘↵)' }}</span>
          </button>
        </div>
      </div>
    </div>
  </dialog>
</template>
