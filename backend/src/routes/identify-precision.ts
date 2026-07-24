import { Hono } from 'hono'
import type { Env, Variables } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { identifyWithGroq } from '../services/groq'
import { lookupBarcode } from '../services/barcode'
import { captureError } from '../lib/sentry'

const route = new Hono<{ Bindings: Env; Variables: Variables }>()

const ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp'])
const MAX_BYTES = 10 * 1024 * 1024

function toBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf)
  let binary = ''
  const CHUNK = 8192
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...Array.from(bytes.subarray(i, i + CHUNK)))
  }
  return btoa(binary)
}

// POST /identify/precision
// Provider chain: barcode (if provided) → Groq Llama 4 Scout
route.post('/', async (c) => {
  let formData: FormData
  try {
    formData = await c.req.formData()
  } catch {
    return c.json(errorBody('invalid_input', 'Expected multipart/form-data'), 400)
  }

  // Optional barcode field — fast-path if present
  const barcodeField = formData.get('barcode')
  const barcode = typeof barcodeField === 'string' ? barcodeField.trim() : null

  const field = formData.get('image')
  if (!field || typeof field === 'string') {
    return c.json(errorBody('invalid_input', 'Missing required field: image'), 400)
  }

  const file = field as File
  if (!ALLOWED_TYPES.has(file.type)) {
    return c.json(errorBody('invalid_input', 'image must be JPEG, PNG, GIF, or WebP'), 400)
  }

  if (file.size > MAX_BYTES) {
    return c.json(errorBody('invalid_input', 'image must be smaller than 10 MB'), 400)
  }

  try {
    // Step 1 — barcode fast-path (returns confidence 0.99 on hit)
    if (barcode) {
      const barcodeResult = await lookupBarcode(barcode, c.env)
      if (barcodeResult) {
        return c.json({
          brand: barcodeResult.brand,
          model: barcodeResult.name,
          category: 'product',
          distinguishing_features: [],
          confidence: barcodeResult.confidence,
          search_query: barcodeResult.search_query,
        })
      }
    }

    const imageBase64 = toBase64(await file.arrayBuffer())

    // Step 2 — Groq Llama 4 Scout
    const groqResult = await identifyWithGroq(imageBase64, file.type, c.env)
    if (groqResult) return c.json(groqResult)

    return c.json(
      errorBody('no_products_found', "Couldn't identify this product — try getting closer or cropping tighter"),
      422,
    )
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err))
    console.error(`[precision] caught error: ${error.message}`)
    await captureError(c.env.SENTRY_DSN, {
      error,
      route: 'POST /identify/precision',
      requestId: c.get('requestId'),
      latencyMs: Date.now() - (c.get('startMs') ?? Date.now()),
      status: 502,
    })
    return c.json(errorBody('upstream_error', 'Product identification failed'), 502)
  }
})

export default route
