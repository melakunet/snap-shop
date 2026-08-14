import { Hono } from 'hono'
import type { Env, Variables } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { identifyWithGroq } from '../services/groq'
import { lookupBarcode, isISBN } from '../services/barcode'
import { captureError } from '../lib/sentry'
import {
  isPlantLike,
  identifyPlantSpecies,
  shapePlantResponse,
  isSpecificPlantQuery,
  SAFETY_NOTE,
  shouldAddSafetyNote,
} from '../services/plant-id'

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
// Provider chain: barcode (if provided) → Groq vision → plant specialist (plant-like only)
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
        const category = isISBN(barcode) ? 'book' : 'product'
        return c.json({
          brand: barcodeResult.brand,
          model: barcodeResult.name,
          category,
          distinguishing_features: [],
          confidence: barcodeResult.confidence,
          search_query: barcodeResult.search_query,
        })
      }
      // Barcode provided but lookup returned nothing.
      // ISBN barcodes point at a book label image — Groq cannot identify books from barcode art.
      // Return a clear error so the user can search by title instead of getting hallucinated results.
      if (isISBN(barcode)) {
        return c.json(
          errorBody('barcode_not_found', "Couldn't find this book — try searching by title or author."),
          422,
        )
      }
      // Non-ISBN: image may contain the actual product visually — fall through to Groq.
    }

    const imageBase64 = toBase64(await file.arrayBuffer())

    // Step 2 — Groq general vision
    const groqResult = await identifyWithGroq(imageBase64, file.type, c.env)
    if (!groqResult) {
      return c.json(
        errorBody('no_products_found', "Couldn't identify this product — try getting closer or cropping tighter"),
        422,
      )
    }

    // Step 3 — Plant specialist pass (fires only for plant-like results)
    if (isPlantLike(groqResult)) {
      const specialist = await identifyPlantSpecies(imageBase64, file.type, c.env)

      if (!specialist) {
        // GROQ_API_KEY absent or parse failed both attempts — return plain result
        return c.json(groqResult)
      }

      // Unknown species — honest 422, never fall through to shopping
      if (specialist.common_name.toLowerCase() === 'unknown') {
        return c.json(
          errorBody(
            'plant_unidentified',
            "Couldn't determine the species — try a Deep scan or frame the plant closer. Never eat or touch unfamiliar plants based on a guess.",
          ),
          422,
        )
      }

      const plantPayload = shapePlantResponse(specialist)
      const isDangerous = !!plantPayload.warning
      const needsNote = shouldAddSafetyNote(specialist.hazard_signals)

      // Dangerous plants: suppress shopping (clear search_query)
      // Safe plants: allow shopping only when the query is species-specific
      let finalQuery = isDangerous
        ? ''
        : isSpecificPlantQuery(groqResult.search_query)
          ? groqResult.search_query
          : `${specialist.common_name.toLowerCase()} plant`

      // Extra safety note for berry/mushroom hazard signals even on non-danger-listed plants
      if (needsNote && !isDangerous) {
        plantPayload.safety_note = SAFETY_NOTE
      }

      return c.json({
        brand: groqResult.brand,
        model: groqResult.model,
        category: groqResult.category,
        distinguishing_features: groqResult.distinguishing_features,
        confidence: specialist.confidence,
        search_query: finalQuery,
        plant: plantPayload,
      })
    }

    // Non-plant: return Groq result unchanged
    return c.json(groqResult)
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
    return c.json(errorBody('upstream_error', `Product identification failed: ${error.message}`), 502)
  }
})

export default route
