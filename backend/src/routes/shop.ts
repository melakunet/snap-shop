import { Hono } from 'hono'
import type { Env, Variables, ShopItem } from '../lib/schema'
import { ShopRequest } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { fetchShoppingResults } from '../services/serpapi'
import { fetchBestBuyPrices } from '../services/bestbuy'
import { fetchEbayPrices } from '../services/ebay'
import { buildShopCacheKey, cacheGet, cacheSet } from '../services/cache'
import { captureError } from '../lib/sentry'

// Race an upstream call against a timeout; on timeout or error return the fallback,
// so one stalled price source can never freeze the whole /shop response.
function withTimeout<T>(p: Promise<T>, ms: number, fallback: T, label: string): Promise<T> {
  return Promise.race([
    p.catch((err) => {
      console.error(`[shop] ${label} failed: ${err instanceof Error ? err.message : String(err)}`)
      return fallback
    }),
    new Promise<T>((resolve) =>
      setTimeout(() => {
        console.warn(`[shop] ${label} timed out after ${ms}ms — skipping`)
        resolve(fallback)
      }, ms),
    ),
  ])
}

const route = new Hono<{ Bindings: Env; Variables: Variables }>()

// Bayesian weighted rating: prevents items with few reviews from dominating.
// score = (v / (v + m)) * R + (m / (v + m)) * C
// v = review count, R = item rating, m = min-votes threshold, C = global mean
function bayesianScore(rating: number | undefined, reviewCount: number | undefined, m: number, C: number): number {
  const v = reviewCount ?? 0
  const R = rating ?? C
  return (v / (v + m)) * R + (m / (v + m)) * C
}

function deduplicateByUrl(items: ShopItem[]): ShopItem[] {
  const seen = new Set<string>()
  return items.filter((item) => {
    if (!item.link) return true  // no link = no basis for dedup, always include
    if (seen.has(item.link)) return false
    seen.add(item.link)
    return true
  })
}

function applyWhitelist(items: ShopItem[], whitelist: string[]): ShopItem[] {
  if (whitelist.length === 0) return items
  const normalized = whitelist.map((w) => w.toLowerCase())
  return items.filter((item) => normalized.some((w) => item.source.toLowerCase().includes(w)))
}

function isGrocery(query: string, category?: string): boolean {
  const keywords = ['milk', 'bread', 'grocery', 'snack', 'beverage', 'produce', 'food', 'cereal', 'snack', 'candy', 'coffee', 'tea']
  const lowQuery = query.toLowerCase()
  const lowCategory = category?.toLowerCase() ?? ''
  return keywords.some(kw => lowQuery.includes(kw) || lowCategory.includes(kw))
}

function filterGroceryResults(items: ShopItem[]): ShopItem[] {
  const electronicsRetailers = ['best buy', 'newegg', 'b&h', 'b \u0026 h']
  return items.filter(item => {
    const lowSource = item.source.toLowerCase()
    return !electronicsRetailers.some(e => lowSource.includes(e))
  })
}

// POST /shop — Best Buy + eBay in parallel, SerpAPI as fallback/supplement, 1-hour cache
route.post('/', async (c) => {
  let body: unknown
  try {
    body = await c.req.json()
  } catch {
    return c.json(errorBody('invalid_input', 'Expected JSON body'), 400)
  }

  const parsed = ShopRequest.safeParse(body)
  if (!parsed.success) {
    const msg = parsed.error.issues[0]?.message ?? 'Invalid request body'
    return c.json(errorBody('invalid_input', msg), 400)
  }

  const { query, retailer_whitelist, sort, region, category } = parsed.data

  // Cache check — before any API calls
  let cacheKey = ''
  try {
    cacheKey = await buildShopCacheKey(`${query}:${region}:${category ?? ''}`, retailer_whitelist, sort)
    const cached = await cacheGet<ShopItem[]>(cacheKey, c.env)
    if (cached !== null) {
      console.log(JSON.stringify({ cache: 'hit', key: cacheKey }))
      return c.json(cached)
    }
    console.log(JSON.stringify({ cache: 'miss', key: cacheKey }))
  } catch (err) {
    // Fail open: treat as miss, log to Sentry
    await captureError(c.env.SENTRY_DSN, {
      error: err instanceof Error ? err : new Error(String(err)),
      route: 'POST /shop cache-get',
      requestId: c.get('requestId'),
    })
  }

  try {
    // Step 1 — Run Best Buy + eBay in parallel
    // Start SerpAPI in parallel with Best Buy/eBay; awaited later only if needed.
    const serpPromise = withTimeout(fetchShoppingResults(query, retailer_whitelist, c.env, region), 20000, [] as ShopItem[], 'serpapi')
    const [bestBuyResults, ebayResults] = await Promise.all([
      withTimeout(fetchBestBuyPrices(query, c.env), 4000, [] as ShopItem[], 'bestbuy'),
      withTimeout(fetchEbayPrices(query, c.env), 4000, [] as ShopItem[], 'ebay'),
    ])

    const merged: ShopItem[] = [...bestBuyResults, ...ebayResults]
    const coveredSources = new Set(merged.map((r) => r.source))

    // Step 2 — Use SerpAPI if we need more results or whitelist requires sources not yet covered
    const needsSerpApi =
      merged.length < 5 ||
      (retailer_whitelist.length > 0 &&
        !retailer_whitelist.every((w) =>
          [...coveredSources].some((s) => s.toLowerCase().includes(w.toLowerCase())),
        ))

    if (needsSerpApi) {
      const serpResults = await serpPromise
      merged.push(...serpResults)
    }

    // Step 3 — Apply grocery heuristic if applicable
    let finalResults = merged
    if (isGrocery(query, category)) {
      finalResults = filterGroceryResults(merged)
    }

    // Step 4 — Whitelist, deduplicate by URL, sort, take top 10
    const whitelisted = applyWhitelist(finalResults, retailer_whitelist)
    const deduped = deduplicateByUrl(whitelisted)

    let results: ShopItem[]
    if (sort === 'reviews') {
      const m = 50
      const ratedItems = deduped.filter((item) => item.rating != null && (item.review_count ?? 0) > 0)
      const C = ratedItems.length > 0
        ? ratedItems.reduce((sum, item) => sum + (item.rating ?? 0), 0) / ratedItems.length
        : 4.0
      results = deduped
        .sort((a, b) => bayesianScore(b.rating, b.review_count, m, C) - bayesianScore(a.rating, a.review_count, m, C))
        .slice(0, 10)
    } else {
      results = deduped
        .sort((a, b) => a.extracted_price - b.extracted_price)
        .slice(0, 10)
    }

    // Store in cache (fire-and-forget on failure)
    if (cacheKey && results.length > 0) {
      cacheSet(cacheKey, results, 86400, c.env).catch((err: unknown) => {
        void captureError(c.env.SENTRY_DSN, {
          error: err instanceof Error ? err : new Error(String(err)),
          route: 'POST /shop cache-set',
          requestId: c.get('requestId'),
        })
      })
    }

    return c.json(results)
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err))
    await captureError(c.env.SENTRY_DSN, {
      error,
      route: 'POST /shop',
      requestId: c.get('requestId'),
      latencyMs: Date.now() - (c.get('startMs') ?? Date.now()),
      status: 502,
    })
    return c.json(errorBody('upstream_error', 'Price lookup failed'), 502)
  }
})

export default route
