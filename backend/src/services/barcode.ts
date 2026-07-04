// Tries Open Food Facts then UPCitemdb. Returns null on miss so caller falls through to vision.
import type { Env } from '../lib/schema'

export interface BarcodeResult {
  name: string
  brand: string
  image?: string
  confidence: 0.99
  search_query: string
}

interface OpenFoodFactsProduct {
  product_name?: string
  brands?: string
  image_front_url?: string
}

interface OpenFoodFactsResponse {
  status?: number
  product?: OpenFoodFactsProduct
}

interface UpcItemDbItem {
  title?: string
  brand?: string
  images?: string[]
}

interface UpcItemDbResponse {
  items?: UpcItemDbItem[]
}

export async function lookupBarcode(barcode: string, env: Env): Promise<BarcodeResult | null> {
  // 1. Try Open Food Facts (no API key required)
  try {
    const res = await fetch(`https://world.openfoodfacts.org/api/v2/product/${barcode}.json`)
    if (res.ok) {
      const data = await res.json() as OpenFoodFactsResponse
      if (data.status === 1 && data.product) {
        const p = data.product
        const name = p.product_name ?? ''
        const brand = p.brands ?? ''
        if (name) {
          return {
            name,
            brand,
            image: p.image_front_url,
            confidence: 0.99,
            search_query: brand ? `${brand} ${name}` : name,
          }
        }
      }
    }
  } catch {
    // fall through to UPCitemdb
  }

  // 2. Try UPCitemdb if key is set
  if (!env.UPCITEMDB_KEY) return null

  try {
    const res = await fetch(
      `https://api.upcitemdb.com/prod/trial/lookup?upc=${barcode}`,
      { headers: { Authorization: `BEARER ${env.UPCITEMDB_KEY}` } },
    )
    if (!res.ok) return null

    const data = await res.json() as UpcItemDbResponse
    const item = data.items?.[0]
    if (!item) return null

    const name = item.title ?? ''
    const brand = item.brand ?? ''
    if (!name) return null

    return {
      name,
      brand,
      image: item.images?.[0],
      confidence: 0.99,
      search_query: brand ? `${brand} ${name}` : name,
    }
  } catch {
    return null
  }
}
