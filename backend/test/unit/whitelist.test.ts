import { describe, it, expect } from 'vitest'

// Extracted whitelist filter logic (mirrors serpapi.ts implementation)
function applyWhitelist(
  items: Array<{ source: string }>,
  whitelist: string[],
): Array<{ source: string }> {
  const normalized = whitelist.map((r) => r.toLowerCase())
  if (normalized.length === 0) return items
  return items.filter((r) => normalized.some((w) => r.source.toLowerCase().includes(w)))
}

const SAMPLE_ITEMS = [
  { source: 'Amazon.com' },
  { source: 'Walmart' },
  { source: 'Best Buy' },
  { source: 'eBay' },
  { source: 'Nike' },
]

describe('whitelist filter', () => {
  it('returns all items when whitelist is empty', () => {
    const result = applyWhitelist(SAMPLE_ITEMS, [])
    expect(result).toHaveLength(SAMPLE_ITEMS.length)
  })

  it('filters case-insensitively', () => {
    const result = applyWhitelist(SAMPLE_ITEMS, ['amazon'])
    expect(result).toHaveLength(1)
    expect(result[0].source).toBe('Amazon.com')
  })

  it('matches partial source names', () => {
    const result = applyWhitelist(SAMPLE_ITEMS, ['best'])
    expect(result).toHaveLength(1)
    expect(result[0].source).toBe('Best Buy')
  })

  it('returns multiple matches', () => {
    const result = applyWhitelist(SAMPLE_ITEMS, ['amazon', 'walmart'])
    expect(result).toHaveLength(2)
  })

  it('returns empty array when no items match the whitelist', () => {
    const result = applyWhitelist(SAMPLE_ITEMS, ['target'])
    expect(result).toHaveLength(0)
  })

  it('handles uppercase whitelist entries', () => {
    const result = applyWhitelist(SAMPLE_ITEMS, ['EBAY'])
    expect(result).toHaveLength(1)
    expect(result[0].source).toBe('eBay')
  })

  it('handles mixed-case whitelist entries', () => {
    const result = applyWhitelist(SAMPLE_ITEMS, ['Best Buy'])
    expect(result).toHaveLength(1)
    expect(result[0].source).toBe('Best Buy')
  })
})
