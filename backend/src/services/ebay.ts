import type { Env, ShopItem } from '../lib/schema'

interface EbayItemSummary {
  title?: string
  price?: { value?: string; currency?: string }
  itemWebUrl?: string
  image?: { imageUrl?: string }
  shippingOptions?: Array<{ shippingCost?: { value?: string } }>
}

interface EbayBrowseResponse {
  itemSummaries?: EbayItemSummary[]
}

export async function fetchEbayPrices(query: string, env: Env): Promise<ShopItem[]> {
  if (!env.EBAY_APP_ID) return []

  try {
    const params = new URLSearchParams({ q: query, limit: '5' })
    const url = `https://api.ebay.com/buy/browse/v1/item_summary/search?${params}`

    const res = await fetch(url, {
      headers: {
        Authorization: `Bearer ${env.EBAY_APP_ID}`,
        'Content-Type': 'application/json',
      },
    })
    if (!res.ok) return []

    const data = await res.json() as EbayBrowseResponse
    const items = data.itemSummaries ?? []

    return items.map((item): ShopItem => {
      const priceValue = parseFloat(item.price?.value ?? '0') || 0
      const currency = item.price?.currency === 'USD' ? '$' : ''
      const shippingCost = item.shippingOptions?.[0]?.shippingCost?.value
      const delivery = shippingCost === '0.0' ? 'Free shipping' : shippingCost ? `+$${shippingCost} shipping` : ''
      return {
        price: `${currency}${priceValue.toFixed(2)}`,
        extracted_price: priceValue,
        delivery,
        source: 'eBay',
        link: item.itemWebUrl ?? '',
        thumbnail: item.image?.imageUrl ?? '',
      }
    })
  } catch {
    return []
  }
}
