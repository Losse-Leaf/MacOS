<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import {
  BookOpen,
  Check,
  Copy,
  Edit3,
  ImagePlus,
  Lock,
  LockOpen,
  MapPin,
  Trash2,
  X,
} from 'lucide-vue-next'
import { api } from '../services/api'
import {
  activeStreamEntry,
  appStore,
  mediaUrl,
  refreshAll,
  showToast,
} from '../stores/appStore'
import type { Attachment, EntryCategory } from '../types/api'
import {
  ALL_ENTRY_CATEGORIES,
  datetimeLocalToBeijingISO,
  deriveDisplayTitle,
  entryAccentVar,
  entryBadgeLabel,
  hasDistinctTitle,
  normalizeCategory,
  parseOccurredDate,
  toDatetimeLocalValue,
} from '../utils/format'

const isEditing = ref(false)
const editTitle = ref('')
const editContent = ref('')
const editCategory = ref<EntryCategory>('daily')
const editLocation = ref('')
const editOccurredLocal = ref('')
const editIsPrivate = ref(false)
const editAttachments = ref<Attachment[]>([])
const isUploading = ref(false)
const isSaving = ref(false)
const editError = ref('')
const isDragOver = ref(false)
const textareaRef = ref<HTMLTextAreaElement | null>(null)
const fileInputRef = ref<HTMLInputElement | null>(null)

const entry = computed(() => activeStreamEntry.value)

const photoGridClass = computed(() => {
  const count = entry.value?.attachments.length ?? 0
  if (count === 1) return 'grid-cols-1'
  if (count === 2 || count === 4) return 'grid-cols-2'
  return 'grid-cols-3'
})

watch(
  () => entry.value?.id,
  () => {
    isEditing.value = false
    editError.value = ''
  },
)

watch(
  () => appStore.editEntryToken,
  () => {
    if (!entry.value) return
    if (isEditing.value) {
      isEditing.value = false
    } else {
      startEdit()
    }
  },
)

async function startEdit() {
  if (!entry.value) return
  const target = entry.value
  editTitle.value = target.title
  editContent.value = target.content
  editCategory.value = normalizeCategory(target.category)
  editLocation.value = target.location ?? ''
  editOccurredLocal.value = toDatetimeLocalValue(target.occurred_at)
  editIsPrivate.value = target.is_private
  editAttachments.value = [...target.attachments]
  editError.value = ''
  isEditing.value = true
  await nextTick()
  textareaRef.value?.focus()
}

async function handleFiles(files: FileList | File[]) {
  const list = Array.from(files).filter((f) => f.type.startsWith('image/'))
  if (!list.length) return
  isUploading.value = true
  editError.value = ''
  try {
    for (const file of list) {
      const uploaded = await api.uploadImageFile(file)
      editAttachments.value.push(uploaded)
    }
  } catch (err) {
    editError.value = err instanceof Error ? err.message : '图片上传失败'
  } finally {
    isUploading.value = false
  }
}

function handlePaste(e: ClipboardEvent) {
  if (!isEditing.value || !e.clipboardData) return
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

function handleDrop(e: DragEvent) {
  isDragOver.value = false
  if (!isEditing.value || !e.dataTransfer?.files?.length) return
  void handleFiles(e.dataTransfer.files)
}

async function saveEdit() {
  if (!entry.value || isSaving.value || isUploading.value) return
  const cleanTitle = editTitle.value.trim()
  const cleanContent = editContent.value.trim()
  if (!cleanTitle && !cleanContent && editAttachments.value.length === 0) {
    editError.value = '标题、正文与配图不能同时为空'
    return
  }

  isSaving.value = true
  editError.value = ''
  try {
    const ids = editAttachments.value.map((a) => a.id)
    const updated = await api.updateEntry(entry.value.id, {
      type: entry.value.type === 'wish' || entry.value.type === 'transaction' ? entry.value.type : 'life',
      category: editCategory.value === 'daily' ? '' : editCategory.value,
      title: cleanTitle,
      content: cleanContent,
      occurred_at: datetimeLocalToBeijingISO(editOccurredLocal.value),
      location: editLocation.value.trim() || null,
      is_private: editIsPrivate.value,
      attachment_ids: ids,
      clear_attachments: ids.length === 0,
    })

    const idx = appStore.entries.findIndex((x) => x.id === updated.id)
    if (idx >= 0) {
      appStore.entries[idx] = updated
    } else {
      appStore.hydratedRemoteEntry = updated
    }
    isEditing.value = false
    showToast('已更新散页手稿')
    void refreshAll(true)
  } catch (err) {
    editError.value = err instanceof Error ? err.message : '保存失败'
  } finally {
    isSaving.value = false
  }
}

async function togglePrivacy() {
  if (!entry.value) return
  const target = entry.value
  try {
    const updated = await api.updateEntry(target.id, { is_private: !target.is_private })
    const idx = appStore.entries.findIndex((x) => x.id === updated.id)
    if (idx >= 0) appStore.entries[idx] = updated
    if (appStore.hydratedRemoteEntry?.id === updated.id) appStore.hydratedRemoteEntry = updated
    showToast(updated.is_private ? '已设为仅自己可见（私密）' : '已设为公开可见')
  } catch (err) {
    showToast(err instanceof Error ? err.message : '切换隐私失败', true)
  }
}

async function copyMarkdown() {
  if (!entry.value) return
  const e = entry.value
  const lines: string[] = []
  const t = deriveDisplayTitle(e)
  if (t) lines.push(`# ${t}`, '')
  if (e.content.trim()) lines.push(e.content.trim(), '')
  lines.push(`> ${parseOccurredDate(e.occurred_at).dotDateTime}${e.location ? ` · ${e.location}` : ''}`)
  await navigator.clipboard.writeText(lines.join('\n'))
  showToast('已拷贝 Markdown 至剪贴板')
}

function askDelete() {
  if (!entry.value) return
  const target = entry.value
  appStore.confirmRequest = {
    title: '删除这篇散页？',
    message: `删除后「${deriveDisplayTitle(target)}」将从时间流中移除（关联账目不会被删除）。`,
    confirmText: '确认删除',
    danger: true,
    onConfirm: async () => {
      await api.deleteEntry(target.id)
      appStore.entries = appStore.entries.filter((x) => x.id !== target.id)
      if (appStore.selectedEntryId === target.id) {
        appStore.selectedEntryId = appStore.entries[0]?.id ?? null
      }
      showToast('已删除散页手稿')
      void refreshAll(true)
    },
  }
}
</script>

<template>
  <div
    class="h-full flex flex-col bg-[var(--paper)] min-w-0"
    @dragover.prevent="isDragOver = isEditing"
    @dragleave="isDragOver = false"
    @drop.prevent="handleDrop"
  >
    <div
      v-if="!entry"
      class="flex-1 flex flex-col items-center justify-center text-center px-8 gap-3 text-[var(--ink-muted)]"
    >
      <BookOpen class="w-9 h-9 opacity-60" />
      <div class="font-serif-editorial text-[17px] text-[var(--ink-secondary)]">
        从左侧列表选择一篇散页开始阅读
      </div>
      <p class="text-[12px]">支持 ↑ / ↓ 快速切换，⌘E 原地编辑，⌘N 写下新想法</p>
    </div>

    <!-- 原地编辑态 -->
    <template v-else-if="isEditing">
      <div
        class="h-11 shrink-0 px-7 border-b border-[var(--border-subtle)] flex items-center justify-between gap-3"
      >
        <span class="text-[12.5px] font-medium text-[var(--ink-secondary)]">正在原地编辑散页</span>

        <div class="flex items-center gap-2">
          <button
            type="button"
            class="px-3 py-1 rounded-lg border border-[var(--border-subtle)] text-[12px] text-[var(--ink-secondary)] hover:bg-[var(--paper-subtle)] cursor-pointer"
            @click="isEditing = false"
          >
            取消
          </button>
          <button
            type="button"
            :disabled="isSaving || isUploading"
            class="inline-flex items-center gap-1.5 px-3.5 py-1 rounded-lg bg-[var(--accent-warm)] text-white text-[12px] font-medium hover:opacity-92 disabled:opacity-50 cursor-pointer"
            @click="saveEdit"
          >
            <Check class="w-3.5 h-3.5" />
            <span>{{ isSaving ? '保存中…' : '保存修改' }}</span>
          </button>
        </div>
      </div>

      <div
        class="flex-1 overflow-y-auto paper-scroll px-8 py-6"
        :class="{ 'ring-2 ring-inset ring-[var(--accent-warm)]/60 bg-[var(--accent-warm-soft)]/25': isDragOver }"
        @paste="handlePaste"
      >
        <div class="max-w-[740px] mx-auto flex flex-col gap-5">
          <!-- 分类 + 私密 -->
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex flex-wrap items-center gap-1.5">
              <button
                v-for="cat in ALL_ENTRY_CATEGORIES"
                :key="cat.id"
                type="button"
                class="px-2.5 py-1 rounded-full text-[12px] border transition-colors cursor-pointer"
                :class="
                  editCategory === cat.id
                    ? 'bg-[var(--accent-warm-soft)] border-[var(--accent-warm)]/40 text-[var(--accent-warm)] font-medium'
                    : 'bg-[var(--paper-subtle)] border-transparent text-[var(--ink-secondary)] hover:text-[var(--ink-primary)]'
                "
                @click="editCategory = cat.id"
              >
                {{ cat.label }}
              </button>
            </div>

            <label class="inline-flex items-center gap-1.5 text-[12px] text-[var(--ink-secondary)] cursor-pointer">
              <input v-model="editIsPrivate" type="checkbox" class="rounded" />
              <Lock v-if="editIsPrivate" class="w-3.5 h-3.5 text-[var(--accent-warm)]" />
              <span>仅自己可见</span>
            </label>
          </div>

          <!-- 时间 + 地点 -->
          <div class="flex flex-wrap items-center gap-3">
            <input
              v-model="editOccurredLocal"
              type="datetime-local"
              aria-label="发生时刻"
              class="px-2.5 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)] text-[12px] font-mono-tabular text-[var(--ink-primary)]"
            />
            <div class="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-[var(--paper-subtle)] border border-[var(--border-subtle)]">
              <MapPin class="w-3.5 h-3.5 text-[var(--ink-muted)]" />
              <input
                v-model="editLocation"
                type="text"
                placeholder="地点（可选）"
                aria-label="地点"
                class="bg-transparent text-[12px] text-[var(--ink-primary)] placeholder:text-[var(--ink-muted)] w-44"
              />
            </div>
          </div>

          <input
            v-model="editTitle"
            type="text"
            placeholder="标题（可留空，自动取正文首行）"
            aria-label="标题"
            class="w-full bg-transparent font-serif-editorial text-[24px] font-semibold text-[var(--ink-primary)] placeholder:text-[var(--ink-muted)]/60 border-b border-[var(--border-subtle)] pb-2"
          />

          <textarea
            ref="textareaRef"
            v-model="editContent"
            rows="10"
            placeholder="写下此刻的想法… 支持直接 ⌘V 粘贴或拖拽图片"
            aria-label="正文"
            class="w-full bg-transparent text-[15px] leading-[1.85] text-[var(--ink-primary)] placeholder:text-[var(--ink-muted)]/60 resize-y min-h-[220px]"
          />

          <!-- 图片管理区 -->
          <div class="p-3.5 rounded-xl bg-[var(--paper-subtle)]/70 border border-[var(--border-subtle)] flex flex-col gap-3">
            <div class="flex items-center justify-between">
              <span class="text-[12px] font-medium text-[var(--ink-secondary)]">
                相纸与配图（{{ editAttachments.length }}）
              </span>
              <div class="flex items-center gap-2">
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
                  class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[var(--paper-elevated)] border border-[var(--border-subtle)] text-[12px] text-[var(--ink-primary)] hover:border-[var(--border-divider)] cursor-pointer"
                  @click="fileInputRef?.click()"
                >
                  <ImagePlus class="w-3.5 h-3.5 text-[var(--accent-warm)]" />
                  <span>{{ isUploading ? '上传中…' : '添加照片' }}</span>
                </button>
              </div>
            </div>

            <div v-if="editAttachments.length > 0" class="grid grid-cols-4 gap-2.5">
              <div
                v-for="(att, idx) in editAttachments"
                :key="att.id"
                class="relative aspect-square rounded-lg overflow-hidden bg-[var(--paper)] border border-[var(--border-subtle)] group"
              >
                <img
                  :src="mediaUrl(att.thumbnail_url || att.url)"
                  :alt="att.original_filename"
                  class="w-full h-full object-cover"
                />
                <button
                  type="button"
                  class="absolute top-1.5 right-1.5 w-6 h-6 rounded-full bg-black/65 text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer"
                  aria-label="移除照片"
                  @click="editAttachments.splice(idx, 1)"
                >
                  <X class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          </div>

          <p v-if="editError" class="text-[12px] text-[var(--accent-warm)] bg-[var(--accent-warm-soft)] px-3 py-2 rounded-lg">
            {{ editError }}
          </p>
        </div>
      </div>
    </template>

    <!-- 纯净阅读态 -->
    <template v-else>
      <div
        class="h-11 shrink-0 px-7 border-b border-[var(--border-subtle)] flex items-center justify-between gap-3"
      >
        <div class="flex items-center gap-2">
          <span
            class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11.5px] font-medium"
            :style="{
              color: entryAccentVar(entry),
              backgroundColor: 'color-mix(in srgb, ' + entryAccentVar(entry) + ' 12%, transparent)',
            }"
          >
            <span class="w-1.5 h-1.5 rounded-full" :style="{ backgroundColor: entryAccentVar(entry) }" />
            <span>{{ entryBadgeLabel(entry) }}</span>
          </span>

          <span
            v-if="entry.is_private"
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11.5px] font-medium text-[var(--accent-warm)] bg-[var(--accent-warm-soft)]"
          >
            <Lock class="w-3 h-3" />
            <span>私密</span>
          </span>
        </div>

        <div class="flex items-center gap-1">
          <button
            type="button"
            class="reader-icon-btn"
            title="原地编辑散页 (⌘E)"
            aria-label="原地编辑散页"
            @click="startEdit"
          >
            <Edit3 class="w-4 h-4" />
          </button>

          <button
            type="button"
            class="reader-icon-btn"
            :class="entry.is_private ? 'text-[var(--accent-warm)]' : ''"
            :title="entry.is_private ? '设为公开可见' : '设为仅自己可见'"
            :aria-label="entry.is_private ? '设为公开可见' : '设为仅自己可见'"
            @click="togglePrivacy"
          >
            <LockOpen v-if="entry.is_private" class="w-4 h-4" />
            <Lock v-else class="w-4 h-4" />
          </button>

          <button
            type="button"
            class="reader-icon-btn"
            title="拷贝 Markdown"
            aria-label="拷贝 Markdown"
            @click="copyMarkdown"
          >
            <Copy class="w-4 h-4" />
          </button>

          <button
            type="button"
            class="reader-icon-btn text-[var(--accent-warm)] hover:bg-[var(--accent-warm-soft)]"
            title="删除散页"
            aria-label="删除散页"
            @click="askDelete"
          >
            <Trash2 class="w-4 h-4" />
          </button>
        </div>
      </div>

      <article class="flex-1 overflow-y-auto paper-scroll px-9 py-7">
        <div class="max-w-[740px] mx-auto flex flex-col gap-5">
          <div class="flex items-center gap-2 text-[12px] font-mono-tabular text-[var(--ink-muted)]">
            <time :datetime="entry.occurred_at">{{ parseOccurredDate(entry.occurred_at).dotDateTime }}</time>
            <span v-if="entry.location?.trim()" class="font-sans">· {{ entry.location.trim() }}</span>
          </div>

          <h2
            v-if="hasDistinctTitle(entry)"
            class="selectable-text font-serif-editorial text-[26px] font-semibold tracking-tight text-[var(--ink-primary)] leading-snug"
          >
            {{ entry.title }}
          </h2>

          <div
            v-if="entry.content.trim()"
            class="selectable-text text-[15px] leading-[1.85] text-[var(--ink-primary)] whitespace-pre-wrap break-words"
          >
            {{ entry.content }}
          </div>

          <!-- 无边框自适应相册网格 -->
          <div
            v-if="entry.attachments.length > 0"
            class="grid gap-2.5 pt-2"
            :class="photoGridClass"
          >
            <button
              v-for="(att, idx) in entry.attachments"
              :key="att.id"
              type="button"
              class="group relative overflow-hidden rounded-xl bg-[var(--paper-subtle)] border border-[var(--border-subtle)] hover:border-[var(--accent-warm)]/45 transition-all cursor-zoom-in"
              :class="
                entry.attachments.length === 1
                  ? 'max-h-[480px] flex justify-start bg-transparent border-0'
                  : entry.attachments.length === 3 && idx === 0
                    ? 'col-span-3 aspect-[16/9]'
                    : entry.attachments.length <= 4
                      ? 'aspect-[4/3]'
                      : 'aspect-square'
              "
              @click="appStore.lightboxState = { attachments: entry.attachments, index: idx }"
            >
              <img
                :src="mediaUrl(att.thumbnail_url || att.url)"
                :alt="att.original_filename || deriveDisplayTitle(entry)"
                loading="lazy"
                :class="
                  entry.attachments.length === 1
                    ? 'max-h-[460px] w-auto max-w-full rounded-xl border border-[var(--border-subtle)] object-contain'
                    : 'w-full h-full object-cover group-hover:scale-[1.015] transition-transform duration-200'
                "
              />
            </button>
          </div>
        </div>
      </article>
    </template>
  </div>
</template>

<style scoped>
@reference "../styles/main.css";

.reader-icon-btn {
  @apply p-1.5 rounded-lg text-[var(--ink-secondary)] hover:bg-[var(--paper-subtle)] hover:text-[var(--ink-primary)] transition-colors cursor-pointer;
}
</style>
