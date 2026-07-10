import type { Env } from '../lib/schema'
import { cacheGet, cacheSet } from './cache'

export interface URLIdentifyResult {
  productName: string
  imageURL: string
  searchQuery: string
}

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

  let html: string
  try {
    const res = await fetch(pageURL, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; SnapShopBot/1.0)',
        Accept: 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      },
      signal: AbortSignal.timeout(15_000),
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    html = await res.text()
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    throw new Error(`Could not fetch the page: ${msg}`)
  }

  const productName = extractJsonLd(html) ?? extractOgTitle(html) ?? extractTitle(html)
  if (!productName) throw new Error('No product name found on the page')

  const imageURL = extractOgImage(html) ?? ''
  const asin = extractAsin(pageURL)
  const baseQuery = cleanForSearch(productName)
  const searchQuery = asin ? `${baseQuery} ${asin}`.trim() : baseQuery

  const result: URLIdentifyResult = { productName, imageURL, searchQuery }
  await cacheSet(cacheKey, result, 86_400, env).catch(() => { /* fail open */ })
  return result
}
