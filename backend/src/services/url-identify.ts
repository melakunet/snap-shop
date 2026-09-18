import type { Env } from '../lib/schema'
import { cacheGet, cacheSet } from './cache'

export interface URLIdentifyResult {
  productName: string
  imageURL: string
  searchQuery: string
  confidence: number
}

/**
 * Derive a search query from the URL itself when fetching or parsing fails.
 * e.g. ".../myrrh-tonka-room-spray-100ml-xl-42" → "myrrh tonka room spray"
 * Tokens from the first size/variant token onward are dropped (they describe a
 * variant, not the product), as are long pure-number tokens (internal IDs).
 * Short numbers are kept because they are usually part of the name ("air max 90").
 */
export function deriveQueryFromUrl(urlStr: string): string | null {
  try {
    const url = new URL(urlStr)
    // Get last meaningful path segment, strip trailing slash
    const path = url.pathname.replace(/\/$/, '')
    const segment = path.split('/').pop()
    if (!segment) return null

    // Strip extension and query string (URL object already handled query)
    const slug = segment.split('.')[0]

    // Split on hyphens and underscores
    const tokens = slug.split(/[-_]/)

    const isSizeToken = (low: string) =>
      /^\d+(ml|g|oz|kg|lb)$/i.test(low) || ['xs', 's', 'm', 'l', 'xl', 'xxl', 'xxxl'].includes(low)

    // Everything from the first size/variant token onward is variant info, not the name
    const sizeIdx = tokens.findIndex((t) => isSizeToken(t.toLowerCase()))
    const nameTokens = sizeIdx === -1 ? tokens : tokens.slice(0, sizeIdx)

    const productTokens = nameTokens.filter((t) => {
      const low = t.toLowerCase()
      // Long pure numbers are internal IDs; short ones ("90", "15") are usually model names
      if (/^\d{3,}$/.test(low)) return false
      return low.length > 0
    })

    if (productTokens.length === 0) return null
    return productTokens.join(' ').toLowerCase().trim()
  } catch {
    return null
  }
}

/** @deprecated use deriveQueryFromUrl */
export const deriveSlugFromUrl = deriveQueryFromUrl

// Extract schema.org Product name from JSON-LD script blocks
function extractJsonLd(html: string): string | null {
  const re = /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi
  let m: RegExpExecArray | null
  while ((m = re.exec(html)) !== null) {
    try {
      const data: unknown = JSON.parse(m[1])
      const items = Array.isArray(data) ? (data as unknown[]) : [data]
      for (const item of items) {
        const obj = item as Record<string, unknown>
        if (obj['@type'] === 'Product' && typeof obj.name === 'string') return obj.name
        if (Array.isArray(obj['@graph'])) {
          for (const node of obj['@graph'] as Record<string, unknown>[]) {
            if (node['@type'] === 'Product' && typeof node.name === 'string') return node.name
          }
        }
      }
    } catch { /* invalid JSON-LD — skip */ }
  }
  return null
}

// og:title — handles both attribute orderings
function extractOgTitle(html: string): string | null {
  const m =
    html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']{1,300})["']/i) ??
    html.match(/<meta[^>]+content=["']([^"']{1,300})["'][^>]+property=["']og:title["']/i)
  return m ? decodeEntities(m[1].trim()) : null
}

// <title> tag
function extractTitle(html: string): string | null {
  const m = html.match(/<title[^>]*>([^<]{1,300})<\/title>/i)
  return m ? decodeEntities(m[1].trim()) : null
}

// og:image — handles both attribute orderings
function extractOgImage(html: string): string | null {
  const m =
    html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ??
    html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i)
  return m ? m[1].trim() : null
}

// Amazon ASIN from /dp/XXXXXXXXXX or /gp/product/XXXXXXXXXX
function extractAsin(url: string): string | null {
  const m = url.match(/\/(?:dp|gp\/product)\/([A-Z0-9]{10})/i)
  return m ? m[1].toUpperCase() : null
}

// Minimal HTML entity decode covering common cases in product titles
function decodeEntities(s: string): string {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_, n: string) => String.fromCharCode(Number(n)))
}

// Strip common retailer name suffixes that pollute search queries
function cleanForSearch(name: string): string {
  return name
    .replace(/\s*[|\-–—]\s*(Amazon(\.[a-z]+)?|Walmart\.com|Best Buy|Target|eBay|Etsy).*/gi, '')
    .replace(/\s*:\s*Amazon\.[^|]*/gi, '')
    .trim()
}

export async function identifyFromURL(pageURL: string, env: Env): Promise<URLIdentifyResult> {
  const cacheKey = `url-identify:${pageURL}`
  const cached = await cacheGet<URLIdentifyResult>(cacheKey, env)
  if (cached) return cached

  let html = ''
  let fetchOk = false

  try {
    const origin = new URL(pageURL).origin
    const res = await fetch(pageURL, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'en-CA,en-US;q=0.9,en;q=0.8',
        'Referer': origin,
      },
      signal: AbortSignal.timeout(10_000),
    })

    if (res.ok) {
      html = await res.text()
      fetchOk = true
    } else {
      console.warn(`[identify-url] Fetch failed with status ${res.status} for ${pageURL}`)
    }
  } catch (err) {
    console.error(`[identify-url] Fetch error for ${pageURL}:`, err)
  }

  // Attempt metadata extraction if fetch succeeded
  let productName: string | null = null
  let imageURL = ''

  if (fetchOk) {
    productName = extractJsonLd(html) ?? extractOgTitle(html) ?? extractTitle(html)
    imageURL = extractOgImage(html) ?? ''
  }

  // Layer 2 Fallback — if fetch failed or returned no product name
  if (!productName) {
    const fallbackQuery = deriveQueryFromUrl(pageURL)
    if (!fallbackQuery) {
      throw new Error(fetchOk ? 'No product name found on the page' : 'Could not fetch the page')
    }
    const result: URLIdentifyResult = {
      productName: fallbackQuery,
      imageURL: '',
      searchQuery: fallbackQuery,
      confidence: 0.5
    }
    await cacheSet(cacheKey, result, 86_400, env).catch(() => {})
    return result
  }

  // Success path
  const asin = extractAsin(pageURL)
  const baseQuery = cleanForSearch(productName)
  const searchQuery = asin ? `${baseQuery} ${asin}`.trim() : baseQuery

  const result: URLIdentifyResult = {
    productName,
    imageURL,
    searchQuery,
    confidence: 0.9
  }
  await cacheSet(cacheKey, result, 86_400, env).catch(() => { /* fail open */ })
  return result
}
