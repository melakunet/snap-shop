import { describe, it, expect } from 'vitest'
import { ShopItem, ShopRequest } from '../../src/lib/schema'

// Bayesian scoring logic mirrored from shop.ts
function bayesianScore(
  rating: number | undefined,
  reviewCount: number | undefined,
  m: number,
  C: number,
): number {
  const v = reviewCount ?? 0
  const R = rating ?? C
  return (v / (v + m)) * R + (m / (v + m)) * C
}

const M = 50 // threshold used in shop.ts

describe('bayesianScore', () => {
  it('returns C when item has no reviews', () => {
    expect(bayesianScore(undefined, undefined, M, 4.0)).toBeCloseTo(4.0)
  })

  it('returns C when reviewCount is 0', () => {
    expect(bayesianScore(5.0, 0, M, 4.0)).toBeCloseTo(4.0)
  })

  it('approaches R as reviewCount grows large', () => {
    const score = bayesianScore(4.9, 10000, M, 4.0)
    expect(score).toBeGreaterThan(4.89)
    expect(score).toBeLessThanOrEqual(4.9)
  })

  it('gives higher score to well-reviewed item over single 5-star item', () => {
    const singleFiveStar = bayesianScore(5.0, 1, M, 4.0)
    const wellReviewed = bayesianScore(4.7, 500, M, 4.0)
    expect(wellReviewed).toBeGreaterThan(singleFiveStar)
  })

  it('scores equal items equally', () => {
    const a = bayesianScore(4.5, 100, M, 4.0)
    const b = bayesianScore(4.5, 100, M, 4.0)
    expect(a).toBeCloseTo(b)
  })
})

describe('ShopItem schema with rating fields', () => {
  const base = {
    price: '$29.99',
    extracted_price: 29.99,
    delivery: 'Free shipping',
    source: 'Amazon.com',
    link: 'https://amazon.com',
    thumbnail: '',
  }

  it('parses without optional rating fields', () => {
    const result = ShopItem.safeParse(base)
    expect(result.success).toBe(true)
    if (result.success) {
      expect(result.data.rating).toBeUndefined()
      expect(result.data.review_count).toBeUndefined()
    }
  })

  it('parses with rating and review_count', () => {
    const result = ShopItem.safeParse({ ...base, rating: 4.7, review_count: 1234 })
    expect(result.success).toBe(true)
    if (result.success) {
      expect(result.data.rating).toBe(4.7)
      expect(result.data.review_count).toBe(1234)
    }
  })

  it('rejects a non-integer review_count', () => {
    const result = ShopItem.safeParse({ ...base, review_count: 1.5 })
    expect(result.success).toBe(false)
  })
})

describe('ShopRequest sort field', () => {
  const base = { query: 'Nike Air Force 1', retailer_whitelist: [] }

  it('defaults sort to "price" when omitted', () => {
    const result = ShopRequest.safeParse(base)
    expect(result.success).toBe(true)
    if (result.success) {
      expect(result.data.sort).toBe('price')
    }
  })

  it('accepts sort = "price"', () => {
    const result = ShopRequest.safeParse({ ...base, sort: 'price' })
    expect(result.success).toBe(true)
  })

  it('accepts sort = "reviews"', () => {
    const result = ShopRequest.safeParse({ ...base, sort: 'reviews' })
    expect(result.success).toBe(true)
  })

  it('rejects unknown sort values', () => {
    const result = ShopRequest.safeParse({ ...base, sort: 'popularity' })
    expect(result.success).toBe(false)
  })
})
