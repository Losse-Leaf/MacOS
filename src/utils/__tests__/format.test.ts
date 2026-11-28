import { describe, expect, it } from 'vitest'
import {
  compactListDate,
  deriveDisplayTitle,
  deriveExcerpt,
  formatEditorialDateBadge,
  formatYuan,
  groupEntriesByMonth,
  groupTransactionsByDay,
  hasDistinctTitle,
  normalizeCategory,
  parseQuickLedgerInput,
  parseYuanToCents,
  toBackendCategory,
  toDateInputValue,
} from '../format'

describe('format utilities', () => {
  it('parses yuan strings into exact integer cents', () => {
    expect(parseYuanToCents('42.5')).toBe(4250)
    expect(parseYuanToCents('42.50')).toBe(4250)
    expect(parseYuanToCents('¥ 1,299.99')).toBe(129999)
    expect(parseYuanToCents('0.01')).toBe(1)
    expect(parseYuanToCents('abc')).toBeNull()
    expect(parseYuanToCents('')).toBeNull()
  })

  it('formats integer cents consistently', () => {
    expect(formatYuan(4250)).toBe('¥ 42.50')
    expect(formatYuan(-2867)).toBe('-¥ 28.67')
    expect(formatYuan(10000, false)).toBe('100.00')
  })

  it('parses quick ledger input strings cleanly', () => {
    expect(parseQuickLedgerInput('42.5 咖啡')).toEqual({
      amountCents: 4250,
      title: '咖啡',
      type: 'expense',
    })
    expect(parseQuickLedgerInput('+3500 稿费')).toEqual({
      amountCents: 350000,
      title: '稿费',
      type: 'income',
    })
    expect(parseQuickLedgerInput('打车 18.8')).toEqual({
      amountCents: 1880,
      title: '打车',
      type: 'expense',
    })
  })

  it('matches cross-platform hasDistinctTitle & deriveExcerpt rules', () => {
    expect(hasDistinctTitle({ title: '', content: '第一行\n第二行' })).toBe(false)
    expect(hasDistinctTitle({ title: '第一行', content: '第一行\n第二行' })).toBe(false)
    expect(hasDistinctTitle({ title: '独立标题', content: '正文内容' })).toBe(true)

    expect(
      deriveDisplayTitle({ title: '', content: '雨停了\n出门走走', attachments: [] }),
    ).toBe('雨停了')
    expect(
      deriveExcerpt({ title: '雨停了', content: '雨停了\n出门走走' }),
    ).toBe('出门走走')
    expect(
      deriveExcerpt({ title: '独立标题', content: '第一段正文\n第二段正文' }),
    ).toBe('第一段正文\n第二段正文')
  })

  it('groups entries by Beijing calendar month in order', () => {
    const groups = groupEntriesByMonth([
      {
        id: 1,
        type: 'life',
        title: '十一月A',
        content: '',
        occurred_at: '2026-11-26T10:00:00+08:00',
        is_private: false,
        attachments: [],
      },
      {
        id: 2,
        type: 'life',
        title: '十一月B',
        content: '',
        occurred_at: '2026-11-02T10:00:00+08:00',
        is_private: false,
        attachments: [],
      },
      {
        id: 3,
        type: 'life',
        title: '六月',
        content: '',
        occurred_at: '2025-06-08T10:00:00+08:00',
        is_private: false,
        attachments: [],
      },
    ])
    expect(groups.map((g) => g.title)).toEqual(['2026年11月', '2025年6月'])
    expect(groups[0].entries.map((e) => e.id)).toEqual([1, 2])
    expect(compactListDate('2026-11-26T10:00:00+08:00', new Date('2026-11-27T12:00:00+08:00'))).toBe('11月26日')
    expect(compactListDate('2025-06-08T10:00:00+08:00', new Date('2026-11-27T12:00:00+08:00'))).toBe('2025/6/8')
  })

  it('formats editorial calendar stamp and groups ledger transactions by Beijing day', () => {
    expect(formatEditorialDateBadge('2026-11-26T22:15:00+08:00')).toEqual({
      day: '26',
      monthShort: 'NOV',
      year: '2026',
      weekday: '周四',
    })
    expect(formatEditorialDateBadge('')).toEqual({
      day: '--',
      monthShort: '---',
      year: '----',
      weekday: '',
    })

    const groups = groupTransactionsByDay(
      [
        {
          id: 101,
          amount: 4200,
          type: 'expense',
          category: '餐饮',
          title: '手冲咖啡',
          occurred_at: '2026-11-26T09:00:00+08:00',
        },
        {
          id: 102,
          amount: 120000,
          type: 'income',
          category: '兼职',
          title: '设计稿费',
          occurred_at: '2026-11-26T18:30:00+08:00',
        },
        {
          id: 103,
          amount: 8800,
          type: 'expense',
          category: '书籍',
          title: '纸质画册',
          occurred_at: '2025-06-08T11:00:00+08:00',
        },
      ],
      new Date('2026-11-27T12:00:00+08:00'),
    )

    expect(groups).toHaveLength(2)
    expect(groups[0]).toMatchObject({
      id: '2026-11-26',
      title: '11月26日 · 周四',
      expenseTotal: 4200,
      incomeTotal: 120000,
    })
    expect(groups[0].transactions.map((t) => t.id)).toEqual([101, 102])
    expect(groups[1]).toMatchObject({
      id: '2025-06-08',
      title: '2025年6月8日 · 周日',
      expenseTotal: 8800,
      incomeTotal: 0,
    })
  })

  it('normalizes backend entry categories and counts installment_repay fees only', () => {
    expect(normalizeCategory('Still Life')).toBe('still_life')
    expect(normalizeCategory('still-life')).toBe('still_life')
    expect(normalizeCategory('Photography')).toBe('photography')
    expect(normalizeCategory('静物')).toBe('still_life')
    expect(toBackendCategory('still_life')).toBe('Still Life')
    expect(toBackendCategory('daily')).toBe('')

    expect(toDateInputValue('2026-12-31T00:00:00+08:00')).toBe('2026-12-31')
    expect(toDateInputValue('')).toBe('')

    const groups = groupTransactionsByDay([
      {
        id: 201,
        amount: 50500,
        type: 'expense',
        category: '利息手续费',
        title: 'MacBook 分期 · 第 1/12 期',
        source: 'installment_repay',
        fee_amount: 500,
        occurred_at: '2026-11-28T10:00:00+08:00',
      },
    ])
    expect(groups).toHaveLength(1)
    expect(groups[0].expenseTotal).toBe(500)
  })
})
