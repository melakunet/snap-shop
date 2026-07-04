import { Hono } from 'hono'
import type { Env, Variables, ShopItem } from '../lib/schema'
import { ShopRequest } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { fetchShoppingResults } from '../services/serpapi'
import { fetchBestBuyPrices } from '../services/bestbuy'
import { fetchEbayPrices } from '../services/ebay'
import { buildShopCacheKey, cacheGet, cacheSet } from '../services/cache'
import { captureError } from '../lib/sentry'

const route = new Hono<{ Bindings: Env; Variables: Variables }>()

function deduplicateByUrl(items: ShopItem[]): ShopItem[] {
  const seen = new Set<string>()
  return items.filter((item) => {
    if (!item.link || seen.has(item.link)) return false
    seen.add(item.link)
    return true
  })
}

function applyWhitelist(items: ShopItem[], whitelist: string[]): ShopItem[] {
  if (whitelist.length === 0) return items
  const normalized = whitelist.map((w) => w.toLowerCase())
  return items.filter((item) => normalized.some((w) => item.source.toLowerCase().includes(w)))
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

  const { query, retailer_whitelist } = parsed.data

  // Cache check — before any API calls
  let cacheKey = ''
  try {
    cacheKey = await buildShopCacheKey(query, retailer_whitelist)
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
    // Step 1 — Run Best Buy + eBay in parallel (free tier, gracefully return [] when keys absent)
    const [bestBuyResults, ebayResults] = await Promise.all([
      fetchBestBuyPrices(query, c.env),
      fetchEbayPrices(query, c.env),
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
      const serpResults = await fetchShoppingResults(query, retailer_whitelist, c.env)
      merged.push(...serpResults)
    }

    // Step 3 — Whitelist, deduplicate by URL, sort by price, take top 10
    const whitelisted = applyWhitelist(merged, retailer_whitelist)
    const deduped = deduplicateByUrl(whitelisted)
    const results = deduped
      .sort((a, b) => a.extracted_price - b.extracted_price)
      .slice(0, 10)

    // Store in cache (fire-and-forget on failure)
    if (cacheKey) {
      cacheSet(cacheKey, results, 3600, c.env).catch((err: unknown) => {
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
