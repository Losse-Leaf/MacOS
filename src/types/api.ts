export type EntryType = 'life' | 'wish' | 'transaction'

export type EntryCategory = 'daily' | 'photography' | 'travel' | 'still_life' | 'motion'

export type ThemeMode = 'system' | 'light' | 'dark'

export interface APIEnvelope<T> {
  code: number
  message: string
  data: T | null
}

export interface AccountProfile {
  sub?: string | null
  name?: string | null
  email?: string | null
}

export interface SystemStatus {
  initialized: boolean
  site_name: string
  curator_name: string
  oidc_enabled: boolean
  oidc_provider_name?: string | null
}

export interface ConfirmPairingResponse {
  access_token?: string | null
  session_id?: string | null
  device_id: string
  device_name: string
  platform: string
  paired_at: string
  device_token: string
  initialized: boolean
  hub_url?: string | null
  account?: AccountProfile | null
}

export interface AuthSessionResponse {
  is_admin: boolean
  role: string
  session_id?: string | null
  device_id?: string | null
  platform?: string | null
  account?: AccountProfile | null
}

export interface TrustedDevice {
  id: number
  device_id: string
  name: string
  platform: string
  device_model?: string | null
  status: string
  paired_at: string
  last_active_at: string
  is_current?: boolean | null
}

export interface SiteConfig {
  site_name: string
  site_subtitle?: string | null
  site_desc?: string | null
  curator_name: string
  default_location: string
  initialized: boolean
}

export interface CuratorProfile {
  name: string
  title: string
  bio: string
  location: string
  current_city: string
  avatar_url: string
  avatar_key?: string | null
  motto: string
  manifesto: string
  email?: string | null
  github?: string | null
  social_links?: Record<string, string> | null
  updated_at?: string | null
}

export interface GlobalStats {
  total_entries: number
  total_photos: number
  month_expense: number
  current_year: number
  current_month: number
}

export interface Attachment {
  id: number
  object_key: string
  url: string
  thumbnail_url?: string | null
  original_filename: string
  mime_type: string
  size: number
  width?: number | null
  height?: number | null
}

export interface Wish {
  id: number
  title: string
  kind: 'item' | 'travel' | 'milestone' | string
  note?: string | null
  spec?: string | null
  budget: number
  actual_cost: number
  resolution_type?: string | null
  actual_title?: string | null
  target_date?: string | null
  planted_at?: string | null
  status: 'wanting' | 'fulfilled' | 'relinquished' | 'shelved' | string
  fulfilled_at?: string | null
  transaction_id?: number | null
  life_entry_id?: number | null
  is_private?: boolean | null
  attachments: Attachment[]
  created_at?: string | null
  updated_at?: string | null
}

export interface LifeEntry {
  id: number
  type: EntryType | string
  category?: string | null
  title: string
  content: string
  occurred_at: string
  location?: string | null
  wish_id?: number | null
  wish?: Wish | null
  is_private: boolean
  attachments: Attachment[]
  deleted_at?: string | null
  created_at?: string | null
  updated_at?: string | null
}

export interface EntriesListResponse {
  total: number
  page: number
  page_size: number
  entries: LifeEntry[]
}

export interface CreateEntryPayload {
  type: string
  category: string
  title: string
  content: string
  occurred_at: string
  location?: string | null
  wish_id?: number | null
  is_private?: boolean
  attachment_ids: number[]
  client_request_id?: string
}

export interface UpdateEntryPayload {
  type?: string
  category?: string
  title?: string
  content?: string
  occurred_at?: string
  location?: string | null
  wish_id?: number | null
  is_private?: boolean
  attachment_ids?: number[]
  clear_attachments?: boolean
}

export interface Transaction {
  id: number
  amount: number
  type: 'expense' | 'income' | string
  category: string
  title: string
  note?: string | null
  payment_method?: string | null
  wish_id?: number | null
  occurred_at: string
  is_installment?: boolean | null
  installment_channel_code?: string | null
  installment_total_amount?: number | null
  installment_months?: number | null
  installment_monthly_pay?: number | null
  installment_remain_months?: number | null
  repayment_day?: number | null
  source?: string | null
  installment_plan_id?: number | null
  installment_item_id?: number | null
  principal_amount?: number | null
  fee_amount?: number | null
  deleted_at?: string | null
  created_at?: string | null
  updated_at?: string | null
}

export interface CreateTransactionPayload {
  amount: number
  type: string
  category: string
  title: string
  note?: string | null
  payment_method?: string | null
  wish_id?: number | null
  occurred_at: string
  is_installment?: boolean
  clear_installment?: boolean
  installment_channel_code?: string | null
  installment_total_amount?: number | null
  installment_months?: number | null
  installment_monthly_pay?: number | null
  installment_remain_months?: number | null
  repayment_day?: number | null
  client_request_id?: string
}

export interface TransactionSummary {
  year: number
  month: number
  total_expense: number
  total_income: number
  balance: number
  category_breakdown: Record<string, number>
  count: number
}

export interface CreditChannel {
  id: number
  code: string
  name: string
  repayment_day: number
  note?: string | null
}

export interface InstallmentPlanSummary {
  id: number
  channel_id: number
  channel_code: string
  channel_name?: string | null
  title: string
  kind: string
  principal: number
  periods: number
  fee_mode: string
  fee_value: number
  total_fee: number
  first_due_date: string
  repay_day: number
  category_name?: string | null
  status: 'active' | 'settled' | string
  note?: string | null
  remaining_principal: number
  remaining_fee: number
  remaining_total: number
  paid_principal: number
  paid_fee: number
  paid_total: number
  paid_periods: number
  next_due_date?: string
  next_principal: number
  next_fee: number
  next_total: number
  is_overdue: boolean
  overdue_days: number
  created_at?: string
}

export interface InstallmentItem {
  id: number
  plan_id: number
  seq: number
  due_date: string
  principal_part: number
  fee_part: number
  status: 'scheduled' | 'paid' | string
  paid_at?: string | null
  paid_amount: number
  pay_account?: string | null
  transaction_id?: number | null
}

export interface InstallmentPlanDetail {
  plan: InstallmentPlanSummary
  items: InstallmentItem[]
  remaining_principal: number
  remaining_fee: number
  remaining_total: number
  paid_principal: number
  paid_fee: number
  paid_total: number
  paid_periods: number
  next_due_date?: string
  next_principal: number
  next_fee: number
  next_total: number
  is_overdue: boolean
  overdue_days: number
}

export interface CategoryOption {
  id: number
  scope: 'expense' | 'income' | 'payment' | string
  name: string
  group_name?: string
  keywords?: string
  sort_order: number
  is_builtin: boolean
  usage_count?: number
}

export interface WishesListResponse {
  total: number
  page: number
  page_size: number
  wishes: Wish[]
}

export interface CreateWishPayload {
  title: string
  kind: string
  note?: string | null
  spec?: string | null
  budget: number
  target_date?: string | null
  planted_at?: string | null
  attachment_ids?: number[] | null
  clear_attachments?: boolean | null
  is_private?: boolean | null
  client_request_id?: string
}

export interface BatchSignItem {
  object_key: string
  url: string
  thumbnail_url: string
  expires_in: number
}

export interface ResolveWishPayload {
  fulfilled_at: string
  actual_cost: number
  resolution_type: 'exact' | 'altered' | 'relinquished'
  actual_title?: string | null
  create_transaction: boolean
  create_life_entry: boolean
  entry_content?: string | null
  attachment_ids?: number[] | null
  is_installment?: boolean
  installment_channel_code?: string | null
  installment_total_amount?: number | null
  installment_months?: number | null
  repayment_day?: number | null
}

export interface GlobalSearchResponse {
  query: string
  entries: LifeEntry[]
  wishes: Wish[]
}

export interface PresignUploadResponse {
  upload_id: string
  object_key: string
  upload_url: string
  expires_in: number
}

export interface UnifiedUploadResponse {
  object_key: string
  url: string
  thumbnail_url?: string | null
  expires_in: number
  filename: string
  mime_type: string
  size: number
  width?: number | null
  height?: number | null
  attachment_id: number
}
