import type { Env, ProductReviews } from '../lib/schema'

const SERPAPI_URL = 'https://serpapi.com/search'

function mockReviews(): ProductReviews {
  return {
    rating: 4.7,
    review_count: 12543,
    breakdown: { five: 8210, four: 2508, three: 1003, two: 501, one: 321 },
    top_reviews: [
      {
        author: 'Sarah M.',
        rating: 5,
        text: 'Absolutely love this product! The quality exceeded my expectations and it arrived quickly. Would definitely buy again.',
        date: 'December 2024',
      },
      {
        author: 'James T.',
        rating: 4,
        text: 'Great value for the price. Works exactly as described. Only minor complaint is the packaging could be better, but the product itself is excellent.',
        date: 'November 2024',
      },
      {
        author: 'Maria L.',
        rating: 5,
        text: 'Perfect! Fits great and looks exactly like the photos. Shipping was fast and everything was well protected. Very happy with this purchase.',
        date: 'January 2025',
      },
    ],
  }
}

interface SerpProductResults {
  rating?: number
  reviews?: number
}

interface SerpRatingEntry {
  stars?: number
  amount?: number
}

interface SerpReview {
  author?: string
  rating?: number
  date?: string
  content?: string
  snippet?: string
}

interface SerpReviewsResults {
  ratings?: SerpRatingEntry[]
  reviews?: SerpReview[]
}

interface SerpProductResponse {
  product_results?: SerpProductResults
  reviews_results?: SerpReviewsResults
  error?: string
}

export async function fetchProductReviews(productId: string, env: Env): Promise<ProductReviews> {
  if (!env.SERPAPI_KEY) return mockReviews()

  const params = new URLSearchParams({
    engine: 'google_product',
    product_id: productId,
    api_key: env.SERPAPI_KEY,
  })

  const res = await fetch(`${SERPAPI_URL}?${params}`)
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`SerpAPI ${res.status}: ${body.slice(0, 300)}`)
  }

  const data = await res.json() as SerpProductResponse
  if (data.error) throw new Error(`SerpAPI error: ${data.error}`)

  const product = data.product_results ?? {}
  const reviewsData = data.reviews_results ?? {}

  // Build the rating breakdown — SerpAPI returns [{stars: 5, amount: 8210}, ...]
  let breakdown: ProductReviews['breakdown']
  const ratings = reviewsData.ratings ?? []
  if (ratings.length > 0) {
    const byStars: Record<number, number> = {}
    for (const r of ratings) {
      if (r.stars != null) byStars[r.stars] = r.amount ?? 0
    }
    breakdown = {
      five: byStars[5] ?? 0,
      four: byStars[4] ?? 0,
      three: byStars[3] ?? 0,
      two: byStars[2] ?? 0,
      one: byStars[1] ?? 0,
    }
  }

  const topReviews = (reviewsData.reviews ?? []).slice(0, 5).map((r) => ({
    author: r.author ?? undefined,
    rating: r.rating ?? undefined,
    text: r.content ?? r.snippet ?? '',
    date: r.date ?? undefined,
  })).filter((r) => r.text.length > 0)

  return {
    rating: product.rating ?? 0,
    review_count: product.reviews ?? 0,
    ...(breakdown ? { breakdown } : {}),
    top_reviews: topReviews,
  }
}
