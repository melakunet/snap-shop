import { Hono } from 'hono'
import type { Env, Variables } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { identifyWithGemini } from '../services/gemini'
import type { FrameInput } from '../services/gemini'
import { captureError } from '../lib/sentry'

const route = new Hono<{ Bindings: Env; Variables: Variables }>()

const ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp'])
const MAX_FRAMES = 8
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

// POST /identify/deep — Gemini Vision (2.5 Flash, escalates to 2.5 Pro on low confidence)
route.post('/', async (c) => {
  let formData: FormData
  try {
    formData = await c.req.formData()
  } catch {
    return c.json(errorBody('invalid_input', 'Expected multipart/form-data'), 400)
  }

  const rawFrames = formData.getAll('frames[]')

  if (rawFrames.length === 0) {
    return c.json(errorBody('invalid_input', 'At least one frame is required in frames[]'), 400)
  }

  if (rawFrames.length > MAX_FRAMES) {
    return c.json(errorBody('invalid_input', `Maximum ${MAX_FRAMES} frames allowed`), 400)
  }

  const frames: FrameInput[] = []
  for (let i = 0; i < rawFrames.length; i++) {
    const frame = rawFrames[i]
    if (typeof frame === 'string') {
      return c.json(errorBody('invalid_input', `frames[${i}] must be a file, not a string`), 400)
    }
    const file = frame as File
    if (!ALLOWED_TYPES.has(file.type)) {
      return c.json(errorBody('invalid_input', `frames[${i}] must be JPEG, PNG, GIF, or WebP`), 400)
    }
    if (file.size > MAX_BYTES) {
      return c.json(errorBody('invalid_input', `frames[${i}] must be smaller than 10 MB`), 400)
    }
    frames.push({ base64: toBase64(await file.arrayBuffer()), mediaType: file.type })
  }

  const hintField = formData.get('hint')
  const hint = typeof hintField === 'string' && hintField.length > 0 ? hintField : undefined

  try {
    const items = await identifyWithGemini(frames, hint, c.env)

    if (items.length === 0) {
      return c.json(
        errorBody('no_products_found', "Couldn't spot a product — try getting closer or use Scan this frame"),
        422,
      )
    }

    // Pick highest-confidence item and return as IdentifyResult (without frame_index)
    const best = items.reduce((a, b) => (a.confidence >= b.confidence ? a : b))
    return c.json({
      brand: best.brand,
      model: best.model,
      category: best.category,
      distinguishing_features: best.distinguishing_features,
      confidence: best.confidence,
      search_query: best.search_query,
    })
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err))
    await captureError(c.env.SENTRY_DSN, {
      error,
      route: 'POST /identify/deep',
      requestId: c.get('requestId'),
      latencyMs: Date.now() - (c.get('startMs') ?? Date.now()),
      status: 502,
      extras: { frameCount: frames.length },
    })
    return c.json(errorBody('upstream_error', 'Product identification failed'), 502)
  }
})

export default route
