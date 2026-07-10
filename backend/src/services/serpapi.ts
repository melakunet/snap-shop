import type { Env, ShopItem } from '../lib/schema'

const SERPAPI_URL = 'https://serpapi.com/search'

// Dev mock returned when SERPAPI_KEY is not configured
function mockResults(query: string, whitelist: string[]): ShopItem[] {
  const all: ShopItem[] = [
    { price: '$29.99', extracted_price: 29.99, delivery: 'Free delivery', source: 'Amazon.com', link: `https://amazon.com/s?k=${encodeURIComponent(query)}`, thumbnail: '', rating: 4.7, review_count: 12543, title: query, snippet: `Top-rated ${query} with fast Prime delivery. Highly rated by thousands of customers.`, product_id: 'mock_amz_1' },
    { price: '$34.95', extracted_price: 34.95, delivery: '2-day shipping', source: 'Walmart', link: `https://walmart.com/search?q=${encodeURIComponent(query)}`, thumbnail: '', rating: 4.5, review_count: 3871, title: query, snippet: `Save on ${query} at Walmart. Everyday low prices with free 2-day shipping on eligible orders.`, product_id: 'mock_wmt_2' },
    { price: '$42.00', extracted_price: 42.00, delivery: 'Free shipping', source: 'Target', link: `https://target.com/s?searchTerm=${encodeURIComponent(query)}`, thumbnail: '', rating: 4.3, review_count: 918, title: query, snippet: `Shop ${query} at Target. Free shipping on orders over $35 or free same-day pickup in store.`, product_id: 'mock_tgt_3' },
    { price: '$38.50', extracted_price: 38.50, delivery: 'Ships from Nike', source: 'Nike', link: `https://nike.com/search?q=${encodeURIComponent(query)}`, thumbnail: '', rating: 4.8, review_count: 204, title: query, snippet: `Official Nike ${query}. Authentic product direct from Nike with free returns.`, product_id: 'mock_nke_4' },
    { price: '$31.99', extracted_price: 31.99, delivery: 'Free shipping over $35', source: 'Best Buy', link: `https://bestbuy.com/site/searchpage.jsp?st=${encodeURIComponent(query)}`, thumbnail: '', rating: 4.6, review_count: 1102, title: query, snippet: `Find ${query} at Best Buy with expert advice and price match guarantee.`, product_id: 'mock_bbuy_5' },
    { price: '$27.50', extracted_price: 27.50, delivery: 'Varies', source: 'eBay', link: `https://ebay.com/sch/i.html?_nkw=${encodeURIComponent(query)}`, thumbnail: '', title: query },
    { price: '$44.00', extracted_price: 44.00, delivery: 'Free shipping', source: 'Adidas', link: `https://adidas.com/us/search?q=${encodeURIComponent(query)}`, thumbnail: '', rating: 4.4, review_count: 567, title: query, snippet: `Official Adidas ${query}. Performance and style with free shipping on all orders.`, product_id: 'mock_adi_7' },
  ]
  const norm = whitelist.map((w) => w.toLowerCase())
  const filtered = norm.length === 0 ? all : all.filter((r) => norm.some((w) => r.source.toLowerCase().includes(w)))
  return filtered.slice(0, 10)
}

interface SerpResult {
  title?: string
  price?: string
  extracted_price?: number
  delivery?: string
  source?: string
  link?: string
  product_link?: string
  thumbnail?: string
  rating?: number
  reviews?: number
  snippet?: string
  product_id?: string
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
    ...(r.rating != null ? { rating: r.rating } : {}),
    ...(r.reviews != null ? { review_count: r.reviews } : {}),
    ...(r.title ? { title: r.title } : {}),
    ...(r.snippet ? { snippet: r.snippet } : {}),
    ...(r.product_id ? { product_id: r.product_id } : {}),
  }))
}
