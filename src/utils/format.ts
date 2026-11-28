import type { CategoryOption, EntryCategory, LifeEntry, Transaction } from '../types/api'

export interface ParsedBeijingDate {
  valid: boolean
  year: string
  month: string
  day: string
  time: string
  dateKey: string
  dotDate: string
  dotDateTime: string
  timestamp: number
}

const LEGACY_PLACEHOLDER_TITLES = new Set(['无题随笔', '无题'])
const LEGACY_PLACEHOLDER_PREFIXES = ['现场快门 · ', '现场记录 · ']

export const GALLERY_CATEGORIES: {
  id: EntryCategory
  label: string
  colorVar: string
}[] = [
  { id: 'photography', label: '摄影', colorVar: 'var(--tag-photography)' },
  { id: 'travel', label: '旅途', colorVar: 'var(--tag-travel)' },
  { id: 'still_life', label: '静物', colorVar: 'var(--tag-still-life)' },
  { id: 'motion', label: '影像', colorVar: 'var(--tag-motion)' },
]

export const ALL_ENTRY_CATEGORIES: {
  id: EntryCategory
  label: string
  colorVar: string
}[] = [
  { id: 'daily', label: '日常', colorVar: 'var(--accent-moss)' },
  ...GALLERY_CATEGORIES,
]

export function normalizeCategory(raw?: string | null): EntryCategory {
  const val = (raw ?? '').trim().toLowerCase()
  switch (val) {
    case 'photography':
    case '摄影':
      return 'photography'
    case 'travel':
    case '旅途':
    case '旅行':
      return 'travel'
    case 'still life':
    case 'still_life':
    case 'still-life':
    case 'stilllife':
    case '静物':
    case '器物':
      return 'still_life'
    case 'motion':
    case 'video':
    case '影像':
      return 'motion'
    default:
      return 'daily'
  }
}

export function toBackendCategory(cat: EntryCategory): string {
  switch (cat) {
    case 'photography':
      return 'Photography'
    case 'travel':
      return 'Travel'
    case 'still_life':
      return 'Still Life'
    case 'motion':
      return 'Motion'
    default:
      return ''
  }
}

export function categoryMeta(cat?: string | null): { id: EntryCategory; label: string; colorVar: string } {
  const norm = normalizeCategory(cat)
  return ALL_ENTRY_CATEGORIES.find((c) => c.id === norm) ?? ALL_ENTRY_CATEGORIES[0]
}

export function entryAccentVar(entry: LifeEntry): string {
  if (entry.type === 'wish') return 'var(--spectrum-leisure)'
  if (entry.type === 'transaction') return 'var(--spectrum-dining)'
  return categoryMeta(entry.category).colorVar
}

export function entryBadgeLabel(entry: LifeEntry): string {
  if (entry.type === 'wish') {
    if (entry.wish?.status === 'relinquished' || entry.title.startsWith('理性拔草')) {
      return '理性拔草'
    }
    if (entry.wish?.status === 'fulfilled' || entry.title.startsWith('圆满达成')) {
      return '心愿达成'
    }
    return '心愿印记'
  }
  if (entry.type === 'transaction') return '账目流水'
  const meta = categoryMeta(entry.category)
  return meta.id === 'daily' ? '日常随笔' : meta.label
}

export function hasDistinctTitle(entry: Pick<LifeEntry, 'title' | 'content'>): boolean {
  const t = (entry.title ?? '').trim()
  if (!t) return false
  if (LEGACY_PLACEHOLDER_TITLES.has(t)) return false
  if (LEGACY_PLACEHOLDER_PREFIXES.some((p) => t.startsWith(p))) return false
  const firstLine =
    (entry.content ?? '')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .find((l) => l.length > 0) ?? ''
  if (firstLine && (t === firstLine || firstLine.startsWith(t))) return false
  return true
}

export function deriveDisplayTitle(entry: Pick<LifeEntry, 'title' | 'content' | 'attachments'>): string {
  const t = (entry.title ?? '').trim()
  if (t) return t
  const firstLine =
    (entry.content ?? '')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .find((l) => l.length > 0) ?? ''
  if (firstLine) return firstLine
  return entry.attachments.length > 0 ? '相纸留影' : '无题散页'
}

export function deriveExcerpt(entry: Pick<LifeEntry, 'title' | 'content'>): string {
  const trimmed = (entry.content ?? '').trim()
  if (!trimmed) return ''
  if (hasDistinctTitle(entry)) return trimmed
  const lines = trimmed
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
  return lines.slice(1).join(' ').trim()
}

export function parseYuanToCents(raw: string): number | null {
  const cleaned = raw.replace(/[¥,\s]/g, '').trim()
  if (!cleaned || !/^-?\d+(\.\d+)?$/.test(cleaned)) return null
  const num = Number(cleaned)
  if (!Number.isFinite(num)) return null
  return Math.round(num * 100)
}

export function formatYuan(cents: number, includeSymbol = true): string {
  const absYuan = (Math.abs(cents) / 100).toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  const sign = cents < 0 ? '-' : ''
  return includeSymbol ? `${sign}¥ ${absYuan}` : `${sign}${absYuan}`
}

export function parseQuickLedgerInput(raw: string): {
  amountCents: number | null
  title: string
  type: 'expense' | 'income'
} {
  const trimmed = raw.trim()
  if (!trimmed) return { amountCents: null, title: '', type: 'expense' }

  let working = trimmed
  let type: 'expense' | 'income' = 'expense'
  if (working.startsWith('+')) {
    type = 'income'
    working = working.slice(1).trim()
  } else if (working.startsWith('-')) {
    type = 'expense'
    working = working.slice(1).trim()
  }

  const leadingMatch = working.match(/^(\d+(?:\.\d{1,2})?)\s*(.*)$/)
  if (leadingMatch) {
    const cents = parseYuanToCents(leadingMatch[1])
    return { amountCents: cents, title: leadingMatch[2].trim(), type }
  }

  const trailingMatch = working.match(/^(.*?)\s+(\d+(?:\.\d{1,2})?)$/)
  if (trailingMatch) {
    const cents = parseYuanToCents(trailingMatch[2])
    return { amountCents: cents, title: trailingMatch[1].trim(), type }
  }

  return { amountCents: null, title: trimmed, type }
}

const beijingPartsFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Shanghai',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  weekday: 'short',
  hourCycle: 'h23',
})

const MONTH_ABBR = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']
const WEEKDAY_CN: Record<string, string> = {
  Sun: '周日',
  Mon: '周一',
  Tue: '周二',
  Wed: '周三',
  Thu: '周四',
  Fri: '周五',
  Sat: '周六',
  '周日': '周日',
  '周一': '周一',
  '周二': '周二',
  '周三': '周三',
  '周四': '周四',
  '周五': '周五',
  '周六': '周六',
}

export function beijingDateParts(date: Date = new Date()): {
  year: number
  month: number
  day: number
  hour: number
  minute: number
  second: number
  yearStr: string
  monthStr: string
  dayStr: string
  weekday: string
} {
  const parts = beijingPartsFormatter.formatToParts(date)
  const map: Record<string, string> = {}
  for (const p of parts) {
    map[p.type] = p.value
  }
  const yearStr = map.year ?? '1970'
  const monthStr = map.month ?? '01'
  const dayStr = map.day ?? '01'
  const rawWd = map.weekday ?? ''
  return {
    year: Number(yearStr),
    month: Number(monthStr),
    day: Number(dayStr),
    hour: Number(map.hour ?? '0'),
    minute: Number(map.minute ?? '0'),
    second: Number(map.second ?? '0'),
    yearStr,
    monthStr,
    dayStr,
    weekday: WEEKDAY_CN[rawWd] ?? rawWd,
  }
}

export function formatBeijingISO(date: Date = new Date()): string {
  const p = beijingDateParts(date)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${p.yearStr}-${p.monthStr}-${p.dayStr}T${pad(p.hour)}:${pad(p.minute)}:${pad(p.second)}+08:00`
}

export function toDatetimeLocalValue(isoOrText?: string | null): string {
  const parsed = isoOrText ? new Date(isoOrText) : new Date()
  const valid = Number.isNaN(parsed.getTime()) ? new Date() : parsed
  const p = beijingDateParts(valid)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${p.yearStr}-${p.monthStr}-${p.dayStr}T${pad(p.hour)}:${pad(p.minute)}`
}

export function datetimeLocalToBeijingISO(localVal: string): string {
  const trimmed = localVal.trim()
  if (!trimmed) return formatBeijingISO()
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(trimmed)) {
    return `${trimmed}:00+08:00`
  }
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(trimmed)) {
    return `${trimmed}+08:00`
  }
  const d = new Date(trimmed)
  return Number.isNaN(d.getTime()) ? formatBeijingISO() : formatBeijingISO(d)
}

export function toDateInputValue(isoOrText?: string | null): string {
  const parsed = parseOccurredDate(isoOrText)
  return parsed.valid ? parsed.dateKey : ''
}

export function parseOccurredDate(raw?: string | null): ParsedBeijingDate {
  const text = (raw ?? '').trim()
  if (!text) {
    return {
      valid: false,
      year: '',
      month: '',
      day: '',
      time: '',
      dateKey: '',
      dotDate: '',
      dotDateTime: '',
      timestamp: 0,
    }
  }
  const normalized = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(text)
    ? text.replace(' ', 'T') + (text.includes('+') || text.endsWith('Z') ? '' : '+08:00')
    : /^\d{4}-\d{2}-\d{2}$/.test(text)
      ? `${text}T00:00:00+08:00`
      : text
  const d = new Date(normalized)
  if (Number.isNaN(d.getTime())) {
    return {
      valid: false,
      year: '',
      month: '',
      day: '',
      time: '',
      dateKey: '',
      dotDate: text,
      dotDateTime: text,
      timestamp: 0,
    }
  }
  const p = beijingDateParts(d)
  const pad = (n: number) => String(n).padStart(2, '0')
  const time = `${pad(p.hour)}:${pad(p.minute)}`
  const dateKey = `${p.yearStr}-${p.monthStr}-${p.dayStr}`
  const dotDate = `${p.yearStr}.${p.monthStr}.${p.dayStr}`
  return {
    valid: true,
    year: p.yearStr,
    month: p.monthStr,
    day: p.dayStr,
    time,
    dateKey,
    dotDate,
    dotDateTime: `${dotDate} ${time}`,
    timestamp: d.getTime(),
  }
}

export function formatEditorialDateBadge(occurredAt?: string | null): {
  day: string
  monthShort: string
  year: string
  weekday: string
} {
  const parsed = parseOccurredDate(occurredAt)
  if (!parsed.valid) {
    return { day: '--', monthShort: '---', year: '----', weekday: '' }
  }
  const d = new Date(parsed.timestamp)
  const p = beijingDateParts(d)
  const monthIdx = Math.max(0, Math.min(11, p.month - 1))
  return {
    day: p.dayStr,
    monthShort: MONTH_ABBR[monthIdx] ?? '---',
    year: p.yearStr,
    weekday: p.weekday,
  }
}

export function compactListDate(occurredAt?: string | null, now: Date = new Date()): string {
  const parsed = parseOccurredDate(occurredAt)
  if (!parsed.valid) return ''
  const curYear = beijingDateParts(now).yearStr
  const m = Number(parsed.month)
  const d = Number(parsed.day)
  if (parsed.year === curYear) {
    return `${m}月${d}日`
  }
  return `${parsed.year}/${m}/${d}`
}

export interface EntryMonthGroup {
  id: string
  title: string
  entries: LifeEntry[]
}

export function groupEntriesByMonth(list: LifeEntry[]): EntryMonthGroup[] {
  const order: string[] = []
  const titles = new Map<string, string>()
  const buckets = new Map<string, LifeEntry[]>()

  for (const entry of list) {
    const parsed = parseOccurredDate(entry.occurred_at)
    let key = 'unknown'
    let title = '未定日期'
    if (parsed.valid && parsed.year) {
      key = `${parsed.year}-${parsed.month}`
      title = `${parsed.year}年${Number(parsed.month)}月`
    }
    if (!buckets.has(key)) {
      order.push(key)
      titles.set(key, title)
      buckets.set(key, [])
    }
    buckets.get(key)!.push(entry)
  }

  return order.map((key) => ({
    id: key,
    title: titles.get(key) ?? key,
    entries: buckets.get(key) ?? [],
  }))
}

export interface TransactionDayGroup {
  id: string
  title: string
  expenseTotal: number
  incomeTotal: number
  transactions: Transaction[]
}

export function groupTransactionsByDay(
  list: Transaction[],
  now: Date = new Date(),
): TransactionDayGroup[] {
  const curYear = beijingDateParts(now).yearStr
  const order: string[] = []
  const meta = new Map<string, { title: string; expense: number; income: number; items: Transaction[] }>()

  for (const tx of list) {
    const parsed = parseOccurredDate(tx.occurred_at)
    const key = parsed.valid ? parsed.dateKey : 'unknown'
    if (!meta.has(key)) {
      order.push(key)
      let title = '未定日期'
      if (parsed.valid) {
        const badge = formatEditorialDateBadge(tx.occurred_at)
        const datePart =
          parsed.year === curYear
            ? `${Number(parsed.month)}月${Number(parsed.day)}日`
            : `${parsed.year}年${Number(parsed.month)}月${Number(parsed.day)}日`
        title = badge.weekday ? `${datePart} · ${badge.weekday}` : datePart
      }
      meta.set(key, { title, expense: 0, income: 0, items: [] })
    }
    const bucket = meta.get(key)!
    bucket.items.push(tx)
    if (tx.type === 'income') {
      bucket.income += tx.amount
    } else {
      const expensePart = tx.source === 'installment_repay' ? (tx.fee_amount ?? 0) : tx.amount
      bucket.expense += expensePart
    }
  }

  return order.map((key) => {
    const b = meta.get(key)!
    return {
      id: key,
      title: b.title,
      expenseTotal: b.expense,
      incomeTotal: b.income,
      transactions: b.items,
    }
  })
}

export function categoryColorVar(category: string): string {
  switch (category) {
    case '餐饮':
    case '咖啡饮品':
    case '买菜生鲜':
    case '零食水果':
      return 'var(--spectrum-dining)'
    case '交通':
      return 'var(--spectrum-transit)'
    case '购物':
    case '日用百货':
    case '服饰美妆':
    case '数码器材':
    case '好物购置':
      return 'var(--spectrum-shopping)'
    case '居家':
    case '住房':
    case '水电燃气':
    case '通讯网费':
      return 'var(--spectrum-housing)'
    case '订阅':
    case '订阅会员':
      return 'var(--spectrum-subscription)'
    case '娱乐':
    case '旅行度假':
    case '运动健康':
    case '宠物':
      return 'var(--spectrum-leisure)'
    case '医疗':
    case '利息手续费':
      return 'var(--spectrum-medical)'
    case '学习':
      return 'var(--spectrum-study)'
    default:
      return 'var(--spectrum-other)'
  }
}

const QUICK_EXPENSE_FALLBACK_CHAINS: Record<string, string[]> = {
  餐饮: ['餐饮', '美食', '日常饮食'],
  交通: ['交通', '出行'],
  购物: ['购物', '日用百货'],
  居家: ['居家', '住房'],
  订阅: ['订阅', '订阅会员', '娱乐', '学习'],
  娱乐: ['娱乐', '休闲'],
  医疗: ['医疗', '健康'],
  学习: ['学习', '办公', '教育'],
}

const QUICK_INCOME_FALLBACK_CHAINS: Record<string, string[]> = {
  工资: ['工资', '工资收入', '薪资', '月薪', '奖金'],
  副业: ['副业', '兼职副业', '稿酬设计', '工资'],
  理财: ['理财', '投资理财', '投资收益'],
  退款: ['退款', '退款报销', '二手回血'],
}

const QUICK_EXPENSE_TIER_A: [string, string[]][] = [
  ['医疗', ['美团买药', '饿了么买药', '京东大药房', '叮当快药', '阿里健康']],
  ['交通', ['美团打车', '高德打车', '滴滴出行', '曹操出行', 't3出行', '12306', '铁路12306']],
  ['娱乐', ['美团酒店', '美团民宿', '携程', '飞猪', '去哪儿', '同程', 'airbnb', '爱彼迎', '亚朵', '全季', '汉庭', '健身房', '乐刻', '超级猩猩', '迪卡侬', '羽毛球馆', '游泳馆', '瑜伽馆', '普拉提', '宠物医院', '猫粮', '狗粮', '猫砂']],
  ['餐饮', ['美团优选', '美团买菜', '小象超市', '叮咚买菜', '朴朴超市', '盒马鲜生', '多多买菜']],
  ['居家', ['国家电网', '南方电网', '电费', '水费', '燃气费', '煤气费', '天然气费', '暖气费', '供暖费', '中国移动', '中国联通', '中国电信', '话费', '宽带', '流量包', '通讯费']],
  ['订阅', ['icloud', 'app store', 'chatgpt', 'openai', 'claude', 'github', 'cursor', 'notion', 'spotify', 'netflix', 'youtube', '百度网盘', '夸克网盘', 'wps会员', '腾讯视频', '爱奇艺', '优酷', '网易云音乐', 'qq音乐', '连续包月', '自动续费']],
  ['购物', ['apple store', '苹果专卖', '华为商城', '小米之家', '大疆', 'dji', '索尼', '罗技', '机械键盘', '显卡', '固态硬盘', '顺丰', '菜鸟裹裹', '菜鸟驿站', '丰巢', '快递费', '寄件', '丝芙兰', '优衣库', 'uniqlo', 'zara', '耐克', 'nike', '阿迪达斯', '理发', '美发', '洗剪吹', '剪发']],
]

const QUICK_EXPENSE_MEALS = ['早餐', '早点', '早茶', '午餐', '午饭', '中餐', '晚餐', '晚饭', '夜宵', '宵夜', '正餐', '食堂', '工作餐']

const QUICK_EXPENSE_TIER_B: [string, string[]][] = [
  ['餐饮', [
    '星巴克', 'starbucks', '瑞幸', 'luckin', '库迪', 'manner', '喜茶', '奈雪', '霸王茶姬', '茶百道', '古茗', '蜜雪冰城', '一点点', 'coco', '茶颜悦色', '手冲咖啡', '拿铁', '美式', '咖啡', '奶茶', '果茶', '柠檬茶',
    '麦当劳', '肯德基', 'kfc', '汉堡王', '必胜客', '萨莉亚', '海底捞', '太二', '西贝', '老乡鸡', '沙县', '兰州拉面', '黄焖鸡', '螺蛳粉', '饿了么', '美团外卖', '外卖', '快餐', '火锅', '烧烤', '烤肉', '日料', '寿司', '拉面', '米线', '麻辣烫', '吃饭', '聚餐',
    '买菜', '菜市场', '农贸市场', '生鲜', '盒马', '叮咚', '朴朴', '钱大妈', '永辉', '菜场',
    '百果园', '鲜丰水果', '水果', '果切', '三只松鼠', '良品铺子', '好利来', '鲍师傅', '面包', '蛋糕', '甜品', '冰淇淋', '零食', '坚果', '巧克力',
  ]],
  ['交通', ['地铁', '公交', '打车', '网约车', '出租车', '顺风车', '滴滴', '高德', '火车', '高铁', '动车', '机票', '航空', '加油', '中石油', '中石化', '充电桩', '停车费', '高速费', 'etc', '单车', '骑行']],
  ['购物', [
    '罗森', '全家', '711', '7-eleven', '便利蜂', '沃尔玛', '山姆', 'costco', '名创优品', '屈臣氏', '超市', '便利店', '百货', '纸巾', '洗衣液', '牙膏', '洗发水', '日用品', '快递',
    '衣服', '裤子', '外套', '球鞋', '运动鞋', '包包', '口红', '面霜', '防晒', '护肤', '化妆品', '美甲', '烫发', '染发',
    '手机', 'iphone', 'ipad', 'macbook', 'airpods', '相机', '镜头', '电脑', '笔记本', '显示器', '耳机', '键盘', '鼠标', '路由器', '充电宝', '数据线', '数码', '鲜花', '花店', '礼物',
  ]],
  ['居家', ['房租', '租金', '月租', '房贷', '按揭', '物业费', '物业', '宜家', 'ikea', '家具', '家电', '装修', '保洁', '家政']],
  ['订阅', ['会员费', '会员续费', '月卡', '季卡', '年卡', '云盘', '网盘', '订阅']],
  ['医疗', ['医院', '门诊', '挂号', '诊所', '体检', '拔牙', '洗牙', '牙科', '口腔', '配镜', '药房', '药店', '买药', '药品']],
  ['学习', ['学费', '培训', '网课', '课程', '考研', '考公', '雅思', '托福', '驾校', '考试费', '书店', '买书', '购书', '图书', '书籍', '文具', '打印']],
  ['娱乐', [
    '电影', '万达影城', '淘票票', '猫眼', '剧本杀', '密室', '桌游', 'ktv', '酒吧', '演唱会', '话剧', '展览', '游戏', 'steam', 'switch', '盲盒',
    '酒店', '民宿', '客栈', '旅馆', '景点', '门票', '景区', '迪士尼', '环球影城', '旅游', '度假', '露营', '签证',
    '健身', '私教', '游泳', '瑜伽', '跑步', '羽毛球', '篮球', '网球', '滑雪', '按摩', '推拿', '足疗',
    '宠物', '猫咖', '狗咖', '驱虫', '疫苗',
  ]],
]

const QUICK_EXPENSE_SUFFIX_RULES: [string, RegExp][] = [
  ['购物', /(?:理发|美发|造型|美容|美甲|美睫|服饰|服装)(?:店|室|馆|工作室)?$/],
  ['餐饮', /(?:咖啡|茶饮|奶茶|茶室|茶馆|面馆|饭店|餐馆|餐厅|烧烤|火锅|烤肉|小吃|快餐|食堂|水果|果业|烘焙|面包|蛋糕|甜品|生鲜|菜场|菜市|农贸)$/],
  ['购物', /(?:超市|便利店|百货|驿站)$/],
  ['医疗', /(?:药房|药店|医院|诊所|口腔|牙科)$/],
  ['娱乐', /(?:酒店|宾馆|民宿|客栈)$/],
]

const QUICK_INCOME_RULES: [string, string[], number][] = [
  ['工资', ['代发工资', '工资', '薪资', '发薪', '薪水', '底薪', '月薪', '年终奖', '奖金', '绩效', '提成', '津贴', '补贴', '房补', '餐补', '加班费'], 100],
  ['副业', ['兼职', '副业', '外包', '劳务费', '咨询费', '讲课费', '稿费', '稿酬', '设计费', '约稿', '版权', '版税', '创作激励', '打赏'], 95],
  ['理财', ['理财', '基金', '股票', '股息', '分红', '利息', '结息', '收益', '余额宝', '国债'], 95],
  ['退款', ['退款', '退货', '退费', '报销', '返现', '退税', '理赔', '二手', '闲鱼', '转转', '爱回收', '回血', '出售', '出闲置'], 95],
  ['其他', ['红包', '礼金', '压岁钱', '份子钱', '转账收款', '收到转账', '亲友转账'], 55],
]

/**
 * 为 macOS 快速记账条提供零 AI、多级确定性分类推荐。
 */
export function inferQuickLedgerCategory(
  title: string,
  type: 'expense' | 'income',
  knownCategories: string[],
  categoryItems: CategoryOption[] = [],
): string {
  const validKnown = Array.from(new Set(knownCategories.map((c) => c.trim()).filter(Boolean)))
  const cleaned = title.trim()
  const lower = cleaned.toLowerCase()

  const resolveFallback = (): string => {
    if (validKnown.length === 0) return '其他'
    const order = type === 'income' ? ['其他', '其他收入', '工资', '工资收入'] : ['其他', '餐饮', '购物']
    const hit = order.find((c) => validKnown.includes(c))
    return hit || validKnown[0]
  }

  const resolveBucket = (bucket: string): string | null => {
    if (validKnown.length === 0 || validKnown.includes(bucket)) return bucket
    const chain = (type === 'income' ? QUICK_INCOME_FALLBACK_CHAINS : QUICK_EXPENSE_FALLBACK_CHAINS)[bucket]
    return chain?.find((c) => validKnown.includes(c)) || null
  }

  if (!cleaned) return resolveFallback()

  // Stage 1: 用户在云端配置的分类关键词
  let bestCustomCat: string | null = null
  let bestCustomScore = 0
  for (const item of categoryItems) {
    if (item.scope !== type || !item.keywords) continue
    if (validKnown.length > 0 && !validKnown.includes(item.name)) continue
    const kws = item.keywords
      .split(/[,，、;\n]+/)
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean)
    for (const kw of kws) {
      if (lower.includes(kw)) {
        const sc = 100 + Math.min(kw.length, 20)
        if (sc > bestCustomScore) {
          bestCustomScore = sc
          bestCustomCat = item.name
        }
      }
    }
  }
  if (bestCustomCat) return bestCustomCat

  // Stage 2: 动态分类名直接命中（不含「其他」）
  if (validKnown.length > 0) {
    const exactMatch = validKnown
      .filter((c) => c !== '其他' && c !== '其他收入')
      .sort((a, b) => b.length - a.length)
      .find((c) => lower.includes(c.toLowerCase()))
    if (exactMatch) return exactMatch
  }

  // Stage 3: 四档加权内置知识库
  const scores = new Map<string, number>()
  const addScore = (bucket: string, val: number) => {
    const resolved = resolveBucket(bucket)
    if (!resolved) return
    scores.set(resolved, (scores.get(resolved) || 0) + val)
  }

  if (type === 'income') {
    for (const [bucket, kws, sc] of QUICK_INCOME_RULES) {
      if (kws.some((kw) => lower.includes(kw))) {
        addScore(bucket, sc)
      }
    }
  } else {
    for (const [bucket, kws] of QUICK_EXPENSE_TIER_A) {
      if (kws.some((kw) => lower.includes(kw))) addScore(bucket, 120)
    }
    if (QUICK_EXPENSE_MEALS.some((kw) => lower.includes(kw))) {
      addScore('餐饮', 96)
    }
    for (const [bucket, kws] of QUICK_EXPENSE_TIER_B) {
      if (kws.some((kw) => lower.includes(kw))) addScore(bucket, 90)
    }
    if (scores.size === 0 && cleaned.length >= 2 && cleaned.length <= 20) {
      for (const [bucket, regex] of QUICK_EXPENSE_SUFFIX_RULES) {
        if (regex.test(cleaned)) addScore(bucket, 75)
      }
    }
    if (lower.includes('美团')) addScore('餐饮', 30)
    if (['淘宝', '天猫', '京东', '拼多多', '闲鱼'].some((kw) => lower.includes(kw))) {
      addScore('购物', 30)
    }
  }

  let topCat: string | null = null
  let topScore = 0
  for (const [cat, sc] of scores.entries()) {
    if (sc > topScore) {
      topScore = sc
      topCat = cat
    }
  }
  return topCat || resolveFallback()
}

let cachedSupportsDisplayTransition: boolean | undefined

function canTransitionDisplay(): boolean {
  if (cachedSupportsDisplayTransition !== undefined) return cachedSupportsDisplayTransition
  if (
    typeof window === 'undefined' ||
    !window.CSS?.supports?.('transition-behavior', 'allow-discrete') ||
    !document.body
  ) {
    cachedSupportsDisplayTransition = false
    return false
  }
  const probe = document.createElement('div')
  probe.style.cssText = 'transition: display 1s allow-discrete !important; display: block;'
  document.body.appendChild(probe)
  getComputedStyle(probe).display
  probe.style.display = 'none'
  cachedSupportsDisplayTransition = getComputedStyle(probe).display === 'block'
  probe.remove()
  return cachedSupportsDisplayTransition
}

function supportsTopLayerExit(): boolean {
  if (typeof window === 'undefined') return false
  return Boolean(window.CSS?.supports?.('overlay', 'auto')) && canTransitionDisplay()
}

/**
 * Animated top-layer dialog close with Safari/WebKit fallback (per `animate-to-from-top-layer`).
 */
export async function closeDialogAnimated(dialog: HTMLDialogElement): Promise<void> {
  if (!dialog.open) return
  if (!supportsTopLayerExit() && typeof dialog.getAnimations === 'function') {
    dialog.setAttribute('data-closing', '')
    const animations = dialog.getAnimations({ subtree: true })
    if (animations.length > 0) {
      await Promise.race([
        Promise.allSettled(animations.map((a) => a.finished)),
        new Promise<void>((r) => setTimeout(r, 350)),
      ])
    }
    if (!dialog.hasAttribute('data-closing')) return
    dialog.removeAttribute('data-closing')
  }
  if (dialog.open) {
    dialog.close()
  }
}

/**
 * Light-dismiss fallback for WebKit/Safari where <dialog closedby="any"> is not supported.
 */
export function attachDialogLightDismiss(
  dialog: HTMLDialogElement,
  onDismiss: () => void,
): () => void {
  if ('closedBy' in HTMLDialogElement.prototype) {
    return () => {}
  }
  let pressedOutside = false
  const isOutside = (e: PointerEvent) => {
    const r = dialog.getBoundingClientRect()
    return e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom
  }
  const onPointerDown = (e: PointerEvent) => {
    pressedOutside = isOutside(e)
  }
  const onPointerUp = (e: PointerEvent) => {
    if (pressedOutside && isOutside(e)) {
      onDismiss()
    }
    pressedOutside = false
  }
  dialog.addEventListener('pointerdown', onPointerDown)
  dialog.addEventListener('pointerup', onPointerUp)
  return () => {
    dialog.removeEventListener('pointerdown', onPointerDown)
    dialog.removeEventListener('pointerup', onPointerUp)
  }
}
