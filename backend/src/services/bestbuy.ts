import type { Env, ShopItem } from '../lib/schema'

interface BestBuyProduct {
  name?: string
  salePrice?: number
  regularPrice?: number
  url?: string
  thumbnailImage?: string
  customerReviewAverage?: number
  customerReviewCount?: number
}

interface BestBuyResponse {
  products?: BestBuyProduct[]
}

export async function fetchBestBuyPrices(query: string, env: Env): Promise<ShopItem[]> {
  if (!env.BESTBUY_API_KEY) return []

  try {
    const params = new URLSearchParams({
      apiKey: env.BESTBUY_API_KEY,
      show: 'name,salePrice,regularPrice,url,thumbnailImage,customerReviewAverage,customerReviewCount',
      format: 'json',
      pageSize: '5',
    })
    const searchStr = encodeURIComponent(query)
    const url = `https://api.bestbuy.com/v1/products((search=${searchStr}))?${params}`

    const res = await fetch(url)
    if (!res.ok) return []

    const data = await res.json() as BestBuyResponse
    const products = data.products ?? []

    return products.map((p): ShopItem => {
      const price = p.salePrice ?? p.regularPrice ?? 0
      return {
        price: `$${price.toFixed(2)}`,
        extracted_price: price,
        delivery: '',
        source: 'Best Buy',
        link: p.url ?? '',
        thumbnail: p.thumbnailImage ?? '',
        ...(p.customerReviewAverage != null ? { rating: p.customerReviewAverage } : {}),
        ...(p.customerReviewCount != null ? { review_count: p.customerReviewCount } : {}),
        ...(p.name ? { title: p.name } : {}),
      }
    })
  } catch {
    return []
  }
}
