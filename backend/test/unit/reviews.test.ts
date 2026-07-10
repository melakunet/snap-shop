import { describe, it, expect } from 'vitest'
import { ProductReviews, ReviewItem, RatingBreakdown } from '../../src/lib/schema'

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
