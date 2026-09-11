// Barcode lookup chain:
//   ISBN (978/979 prefix) → Google Books → UPCitemdb
//   Other              → Open Food Facts → UPCitemdb
// Returns null on miss so caller can decide how to handle it.
import type { Env } from '../lib/schema'

export interface BarcodeResult {
  name: string
  brand: string
  image?: string
  confidence: 0.99
  search_query: string
}

// ── Helpers ──────────────────────────────────────────────────────────────────

export function isISBN(barcode: string): boolean {
  return barcode.startsWith('978') || barcode.startsWith('979')
}

// ── Google Books (ISBN only, no key required) ─────────────────────────────

interface GoogleBooksVolume {
  volumeInfo?: {
    title?: string
    authors?: string[]
    imageLinks?: { thumbnail?: string; smallThumbnail?: string }
  }
}
interface GoogleBooksResponse {
  totalItems?: number
  items?: GoogleBooksVolume[]
}

async function lookupGoogleBooks(isbn: string): Promise<BarcodeResult | null> {
  try {
    const url = `https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}&maxResults=1`
    const res = await fetch(url)
    if (!res.ok) return null
    const data = await res.json() as GoogleBooksResponse
    if (!data.totalItems || !data.items?.length) return null
    const vol = data.items[0].volumeInfo
    if (!vol?.title) return null

    const title = vol.title
    const authors = vol.authors?.join(', ') ?? ''
    const image =
      vol.imageLinks?.thumbnail?.replace('http://', 'https://') ??
      vol.imageLinks?.smallThumbnail?.replace('http://', 'https://')

    return {
      name: title,
      brand: authors,
      image,
      confidence: 0.99,
      search_query: authors ? `${title} ${authors} book` : `${title} book`,
    }
  } catch {
    return null
  }
}

// ── Open Library (ISBN only, no key required) ────────────────────────────

interface OpenLibraryBook {
  title?: string
  authors?: Array<{ name: string }>
  cover?: { small?: string; medium?: string; large?: string }
}

async function lookupOpenLibrary(isbn: string): Promise<BarcodeResult | null> {
  try {
    const url = `https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`
    const res = await fetch(url)
    if (!res.ok) return null
    const data = await res.json() as Record<string, OpenLibraryBook>
    const book = data[`ISBN:${isbn}`]
    if (!book?.title) return null
    const title = book.title
    const authors = book.authors?.map((a) => a.name).join(', ') ?? ''
    const image =
      book.cover?.medium?.replace('http://', 'https://') ??
      book.cover?.large?.replace('http://', 'https://')
    return {
      name: title,
      brand: authors,
      image,
      confidence: 0.99,
      search_query: authors ? `${title} ${authors} book` : `${title} book`,
    }
  } catch {
    return null
  }
}

// ── Open Food Facts (food/grocery, no key required) ──────────────────────

interface OpenFoodFactsProduct {
  product_name?: string
  brands?: string
  image_front_url?: string
}
interface OpenFoodFactsResponse {
  status?: number
  product?: OpenFoodFactsProduct
}

async function lookupOpenFoodFacts(barcode: string): Promise<BarcodeResult | null> {
  try {
    const res = await fetch(`https://world.openfoodfacts.org/api/v2/product/${barcode}.json`)
    if (!res.ok) return null
    const data = await res.json() as OpenFoodFactsResponse
    if (data.status !== 1 || !data.product) return null
    const p = data.product
    const name = p.product_name ?? ''
    const brand = p.brands ?? ''
    if (!name) return null
    return {
      name,
      brand,
      image: p.image_front_url,
      confidence: 0.99,
      search_query: brand ? `${brand} ${name}` : name,
    }
  } catch {
    return null
  }
}

// ── UPCitemdb (retail, requires key) ─────────────────────────────────────

interface UpcItemDbItem {
  title?: string
  brand?: string
  images?: string[]
}
interface UpcItemDbResponse {
  items?: UpcItemDbItem[]
}

async function lookupUPCItemDb(barcode: string, key: string): Promise<BarcodeResult | null> {
  try {
    const res = await fetch(
      `https://api.upcitemdb.com/prod/trial/lookup?upc=${barcode}`,
      { headers: { Authorization: `BEARER ${key}` } },
    )
    if (!res.ok) return null
    const data = await res.json() as UpcItemDbResponse
    const item = data.items?.[0]
    if (!item?.title) return null
    const name = item.title
    const brand = item.brand ?? ''
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

// ── Public entry point ────────────────────────────────────────────────────

export async function lookupBarcode(barcode: string, env: Env): Promise<BarcodeResult | null> {
  if (isISBN(barcode)) {
    // Run Google Books + Open Library in parallel — take the first hit.
    // Running in parallel means a miss on one source costs no extra wall-clock time.
    const [googleResult, olResult] = await Promise.all([
      lookupGoogleBooks(barcode),
      lookupOpenLibrary(barcode),
    ])
    if (googleResult) return googleResult
    if (olResult) return olResult
    // UPCitemdb as last resort if key is available
    if (env.UPCITEMDB_KEY) return lookupUPCItemDb(barcode, env.UPCITEMDB_KEY)
    return null
  }

  // General retail: Open Food Facts → UPCitemdb
  const food = await lookupOpenFoodFacts(barcode)
  if (food) return food

  if (env.UPCITEMDB_KEY) return lookupUPCItemDb(barcode, env.UPCITEMDB_KEY)
  return null
}
