import { describe, it, expect, vi, afterEach } from 'vitest'
import { ProductReviews, ReviewItem, RatingBreakdown } from '../../src/lib/schema'
import type { Env } from '../../src/lib/schema'
import { fetchProductReviews } from '../../src/services/product-reviews'

const validBreakdown = { five: 8210, four: 2508, three: 1003, two: 501, one: 321 }
const validReview = { text: 'Great product!' }
const validReviews = {
  rating: 4.7,
  review_count: 12543,
  breakdown: validBreakdown,
  top_reviews: [validReview],
}

describe('ReviewItem schema', () => {
  it('parses with only required text field', () => {
    const result = ReviewItem.safeParse({ text: 'Good product' })
    expect(result.success).toBe(true)
  })

  it('parses with all optional fields', () => {
    const result = ReviewItem.safeParse({
      author: 'Jane D.',
      rating: 5,
      text: 'Excellent!',
      date: 'January 2025',
    })
    expect(result.success).toBe(true)
  })

  it('fails when text is missing', () => {
    const result = ReviewItem.safeParse({ author: 'Jane' })
    expect(result.success).toBe(false)
  })

  it('allows fractional rating', () => {
    const result = ReviewItem.safeParse({ text: 'ok', rating: 4.5 })
    expect(result.success).toBe(true)
  })
})

describe('RatingBreakdown schema', () => {
  it('parses valid breakdown', () => {
    const result = RatingBreakdown.safeParse(validBreakdown)
    expect(result.success).toBe(true)
  })

  it('fails when a star count is missing', () => {
    const { five: _five, ...withoutFive } = validBreakdown
    const result = RatingBreakdown.safeParse(withoutFive)
    expect(result.success).toBe(false)
  })

  it('fails when count is not an integer', () => {
    const result = RatingBreakdown.safeParse({ ...validBreakdown, five: 1.5 })
    expect(result.success).toBe(false)
  })
})

describe('ProductReviews schema', () => {
  it('parses a full valid response', () => {
    const result = ProductReviews.safeParse(validReviews)
    expect(result.success).toBe(true)
  })

  it('accepts mock field', () => {
    const result = ProductReviews.safeParse({ ...validReviews, mock: true })
    expect(result.success).toBe(true)
    if (result.success) expect(result.data.mock).toBe(true)
  })

  it('parses without optional breakdown', () => {
    const { breakdown: _bd, ...withoutBreakdown } = validReviews
    const result = ProductReviews.safeParse(withoutBreakdown)
    expect(result.success).toBe(true)
    if (result.success) expect(result.data.breakdown).toBeUndefined()
  })

  it('parses with empty top_reviews array', () => {
    const result = ProductReviews.safeParse({ ...validReviews, top_reviews: [] })
    expect(result.success).toBe(true)
  })

  it('fails when rating is missing', () => {
    const { rating: _r, ...withoutRating } = validReviews
    const result = ProductReviews.safeParse(withoutRating)
    expect(result.success).toBe(false)
  })

  it('fails when review_count is not an integer', () => {
    const result = ProductReviews.safeParse({ ...validReviews, review_count: 12543.5 })
    expect(result.success).toBe(false)
  })
})

// ── fetchProductReviews live-vs-mock gating ──────────────────────────────────

const devEnv = {} as Env
const liveEnv = { SERPAPI_KEY: 'test-key' } as Env

const serpApiReply = (overrides: Record<string, unknown> = {}) => ({
  ok: true,
  json: async () => overrides,
  text: async () => '',
})

describe('fetchProductReviews — live vs dev mode gating', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('returns mock data when SERPAPI_KEY is absent (dev mode only)', async () => {
    // fetch must NOT be called — mock is generated entirely in-process
    const spy = vi.fn()
    vi.stubGlobal('fetch', spy)
    const result = await fetchProductReviews('prod-123', devEnv)
    expect(spy).not.toHaveBeenCalled()
    expect(result).not.toBeNull()
    expect(result!.mock).toBe(true)
    expect(result!.rating).toBe(4.7)
    expect(result!.review_count).toBe(12543)
    expect(result!.top_reviews.length).toBeGreaterThan(0)
    // Ensure well-known fabricated reviewers are present
    const authors = result!.top_reviews.map((r) => r.author)
    expect(authors).toContain('Sarah M.')
  })

  it('returns empty honest response in live mode when SerpAPI has no data', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      serpApiReply({ product_results: {}, reviews_results: {} })
    ))
    const result = await fetchProductReviews('prod-456', liveEnv)
    expect(result).not.toBeNull()
    expect(result!.mock).toBeUndefined()   // no mock flag — this is real (empty) data
    expect(result!.rating).toBe(0)
    expect(result!.review_count).toBe(0)
    expect(result!.top_reviews).toHaveLength(0)
    expect(result!.breakdown).toBeUndefined()
  })

  it('passes through real data in live mode when SerpAPI returns reviews', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      serpApiReply({
        product_results: { rating: 4.3, reviews: 871 },
        reviews_results: {
          ratings: [
            { stars: 5, amount: 500 },
            { stars: 4, amount: 200 },
            { stars: 3, amount: 100 },
            { stars: 2, amount: 50 },
            { stars: 1, amount: 21 },
          ],
          reviews: [{ author: 'Alice', rating: 5, content: 'Works great.', date: 'Feb 2025' }],
        },
      })
    ))
    const result = await fetchProductReviews('prod-789', liveEnv)
    expect(result).not.toBeNull()
    expect(result!.mock).toBeUndefined()
    expect(result!.rating).toBe(4.3)
    expect(result!.review_count).toBe(871)
    expect(result!.top_reviews).toHaveLength(1)
    expect(result!.top_reviews[0].author).toBe('Alice')
    expect(result!.breakdown?.five).toBe(500)
    expect(result!.breakdown?.one).toBe(21)
  })

  it('returns null (not mock) in live mode when SerpAPI returns an HTTP error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 429,
      text: async () => 'Too Many Requests',
    }))
    const result = await fetchProductReviews('prod-err', liveEnv)
    expect(result).toBeNull()
  })
})
