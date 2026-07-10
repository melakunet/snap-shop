import { Hono } from 'hono'
import type { Env, Variables, ProductReviews } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { fetchProductReviews } from '../services/product-reviews'
import { cacheGet, cacheSet } from '../services/cache'
import { captureError } from '../lib/sentry'

const route = new Hono<{ Bindings: Env; Variables: Variables }>()

const REVIEWS_TTL = 6 * 3600 // 6 hours — product reviews change slowly

route.get('/', async (c) => {
  const productId = c.req.query('product_id')?.trim()
  if (!productId) {
    return c.json(errorBody('invalid_input', 'Missing required query param: product_id'), 400)
  }

  // Cache check
  const cacheKey = `reviews:${productId}`
  try {
    const cached = await cacheGet<ProductReviews>(cacheKey, c.env)
    if (cached !== null) {
      console.log(JSON.stringify({ cache: 'hit', key: cacheKey }))
      return c.json(cached)
    }
    console.log(JSON.stringify({ cache: 'miss', key: cacheKey }))
  } catch (err) {
    await captureError(c.env.SENTRY_DSN, {
      error: err instanceof Error ? err : new Error(String(err)),
      route: 'GET /product/reviews cache-get',
      requestId: c.get('requestId'),
    })
  }

  try {
    const reviews = await fetchProductReviews(productId, c.env)

    cacheSet(cacheKey, reviews, REVIEWS_TTL, c.env).catch((err: unknown) => {
      void captureError(c.env.SENTRY_DSN, {
        error: err instanceof Error ? err : new Error(String(err)),
        route: 'GET /product/reviews cache-set',
        requestId: c.get('requestId'),
      })
    })

    return c.json(reviews)
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err))
    await captureError(c.env.SENTRY_DSN, {
      error,
      route: 'GET /product/reviews',
      requestId: c.get('requestId'),
      latencyMs: Date.now() - (c.get('startMs') ?? Date.now()),
      status: 502,
    })
    return c.json(errorBody('upstream_error', 'Failed to fetch product reviews'), 502)
  }
})

export default route
