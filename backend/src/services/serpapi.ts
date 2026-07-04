import type { Env, ShopItem } from '../lib/schema'

const SERPAPI_URL = 'https://serpapi.com/search'

// Dev mock returned when SERPAPI_KEY is not configured
function mockResults(query: string, whitelist: string[]): ShopItem[] {
  const all: ShopItem[] = [
    { price: '$29.99', extracted_price: 29.99, delivery: 'Free delivery', source: 'Amazon.com', link: `https://amazon.com/s?k=${encodeURIComponent(query)}`, thumbnail: '' },
    { price: '$34.95', extracted_price: 34.95, delivery: '2-day shipping', source: 'Walmart', link: `https://walmart.com/search?q=${encodeURIComponent(query)}`, thumbnail: '' },
    { price: '$42.00', extracted_price: 42.00, delivery: 'Free shipping', source: 'Target', link: `https://target.com/s?searchTerm=${encodeURIComponent(query)}`, thumbnail: '' },
    { price: '$38.50', extracted_price: 38.50, delivery: 'Ships from Nike', source: 'Nike', link: `https://nike.com/search?q=${encodeURIComponent(query)}`, thumbnail: '' },
    { price: '$31.99', extracted_price: 31.99, delivery: 'Free shipping over $35', source: 'Best Buy', link: `https://bestbuy.com/site/searchpage.jsp?st=${encodeURIComponent(query)}`, thumbnail: '' },
    { price: '$27.50', extracted_price: 27.50, delivery: 'Varies', source: 'eBay', link: `https://ebay.com/sch/i.html?_nkw=${encodeURIComponent(query)}`, thumbnail: '' },
    { price: '$44.00', extracted_price: 44.00, delivery: 'Free shipping', source: 'Adidas', link: `https://adidas.com/us/search?q=${encodeURIComponent(query)}`, thumbnail: '' },
  ]
  const norm = whitelist.map((w) => w.toLowerCase())
  const filtered = norm.length === 0 ? all : all.filter((r) => norm.some((w) => r.source.toLowerCase().includes(w)))
  return filtered.slice(0, 10)
}

interface SerpResult {
  price?: string
  extracted_price?: number
  delivery?: string
  source?: string
  link?: string
  product_link?: string
  thumbnail?: string
}

interface SerpAPIResponse {
  shopping_results?: SerpResult[]
  error?: string
}

export async function fetchShoppingResults(
  query: string,
  retailerWhitelist: string[],
  env: Env,
): Promise<ShopItem[]> {
  if (!env.SERPAPI_KEY) return mockResults(query, retailerWhitelist)

  const params = new URLSearchParams({
    engine: 'google_shopping',
    q: query,
    api_key: env.SERPAPI_KEY,
    num: '40', // fetch extra before whitelist filtering
  })

  const res = await fetch(`${SERPAPI_URL}?${params}`)

  if (!res.ok) {
    const body = await res.text()
    throw new Error(`SerpAPI ${res.status}: ${body.slice(0, 300)}`)
  }

  const data = await res.json() as SerpAPIResponse

  if (data.error) throw new Error(`SerpAPI error: ${data.error}`)

  const results = data.shopping_results ?? []

  // Case-insensitive whitelist filter (empty whitelist = return all)
  const normalized = retailerWhitelist.map((r) => r.toLowerCase())
  const filtered = normalized.length === 0
    ? results
    : results.filter((r) =>
      r.source && normalized.some((w) => r.source!.toLowerCase().includes(w))
    )

  return filtered.slice(0, 10).map((r) => ({
    price: r.price ?? '',
    extracted_price: r.extracted_price ?? 0,
    delivery: r.delivery ?? '',
    source: r.source ?? '',
    link: r.link ?? r.product_link ?? '',
    thumbnail: r.thumbnail ?? '',
  }))
}
