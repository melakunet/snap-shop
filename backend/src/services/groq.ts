import type { Env } from '../lib/schema'
import { IdentifyResult } from '../lib/schema'

const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'
const GROQ_MODEL = 'qwen/qwen3.6-27b'

// Groq free tier: 8 000 tokens/min for qwen/qwen3.6-27b. Under sustained load
// the TPM cap is hit quickly — retries handle brief windows; a paid tier removes the cap.
const GROQ_RETRIES = 2

// Minimum confidence below which we return null (→ honest 422) rather than surface a guess.
// Mirrors the iOS ConfidenceThreshold.bestGuess floor of 0.35.
const MIN_CONFIDENCE = 0.35

// Category keywords that indicate the model identified a digital/non-physical product.
// This fires when Groq reads overlay text or watermarks instead of the image subject
// (e.g. a plant stock photo labelled "27 TRANSPARENT PNGS" gets returned as "clipart").
const NON_PHYSICAL_KEYWORDS = [
  'clipart', 'clip art', 'digital download', 'digital art', 'digital print',
  'digital pattern', 'printable', 'svg file', 'svg art', 'svg design',
  'png file', 'png pack', 'transparent png', 'stock photo', 'stock image',
  'vector graphic', 'vector art', 'vector design', 'design template',
  'graphic template', 'ebook', 'e-book',
]

function isNonPhysicalCategory(category: string): boolean {
  const cat = category.toLowerCase()
  return NON_PHYSICAL_KEYWORDS.some(k => cat.includes(k))
}

const USER_PROMPT = `Identify the PHYSICAL, PURCHASABLE product in this image. Respond with exactly this JSON object and nothing else:
{"brand":"","model":"","category":"","distinguishing_features":[],"confidence":0.0,"search_query":""}

- brand: manufacturer name, or "" if unknown
- model: specific product model or line name, or "" if unknown
- category: physical product type only (e.g. "sneaker", "laptop", "smartwatch", "headphones", "houseplant")
- distinguishing_features: up to 5 visual identifiers as strings
- confidence: 0.0–1.0 — set to 0.0 if no clear physical product is visible
- search_query: Google Shopping query optimized to find this exact product

IMPORTANT: Focus on the physical product in the foreground. Ignore any text overlays, watermarks, labels, or captions on the image — they describe the image file, not the product to identify. If the image shows digital art, clipart, stock photos, or design files rather than a physical product, set confidence to 0.0.
Respond with the JSON object only. No other text.`

interface GroqMessage {
  role: string
  content: Array<
    | { type: 'text'; text: string }
    | { type: 'image_url'; image_url: { url: string } }
  >
}

interface GroqChoice {
  message?: { content?: string }
}

interface GroqResponse {
  choices?: GroqChoice[]
  error?: { message?: string }
}

// Retries on Groq 429 (transient TPM rate-limit) with exponential backoff.
// Other non-2xx statuses are returned immediately for the caller to handle.
async function fetchGroqWithRetry(init: RequestInit): Promise<Response> {
  let res!: Response
  for (let attempt = 0; attempt <= GROQ_RETRIES; attempt++) {
    if (attempt > 0) {
      await new Promise<void>(r => setTimeout(r, attempt * 1_000))
      console.warn(`[groq] 429 rate-limited — retry ${attempt}/${GROQ_RETRIES}`)
    }
    res = await fetch(GROQ_API_URL, init)
    if (res.status !== 429) return res
  }
  return res
}

export async function identifyWithGroq(
  imageBase64: string,
  mediaType: string,
  env: Env,
): Promise<IdentifyResult | null> {
  if (!env.GROQ_API_KEY) throw new Error('GROQ_API_KEY is not configured')

  const message: GroqMessage = {
    role: 'user',
    content: [
      {
        type: 'image_url',
        image_url: { url: `data:${mediaType};base64,${imageBase64}` },
      },
      { type: 'text', text: USER_PROMPT },
    ],
  }

  const init: RequestInit = {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: GROQ_MODEL,
      max_completion_tokens: 512,
      reasoning_effort: 'none',  // disable thinking mode — response must be plain JSON
      messages: [message],
    }),
  }

  const res = await fetchGroqWithRetry(init)

  if (!res.ok) {
    const body = await res.text()
    console.error(
      `[groq] upstream error — model:${GROQ_MODEL} status:${res.status} body:${body.slice(0, 500)}`,
    )
    throw new Error(
      res.status === 429
        ? 'Too many requests — try again in a moment'
        : 'Product identification temporarily unavailable',
    )
  }

  const data = await res.json() as GroqResponse
  if (data.error) {
    console.error(
      `[groq] api error — model:${GROQ_MODEL} message:${data.error.message}`,
    )
    throw new Error('Product identification temporarily unavailable')
  }

  const raw = data.choices?.[0]?.message?.content ?? ''
  try {
    const cleaned = raw.replace(/```json\s*|```\s*/g, '').trim()
    const parsed: unknown = JSON.parse(cleaned)
    const result = IdentifyResult.safeParse(parsed)
    if (!result.success) return null
    const out = { ...result.data }

    // Confidence floor — return null (→ honest 422) rather than surface a low-confidence guess.
    if (out.confidence < MIN_CONFIDENCE) {
      console.log(`[groq] confidence ${out.confidence} below floor ${MIN_CONFIDENCE} — rejecting`)
      return null
    }

    // Non-physical category gate — fires when the model reads overlay text or watermarks
    // instead of the image subject (e.g. a plant photo labelled as "clipart" or "digital download").
    if (isNonPhysicalCategory(out.category)) {
      console.log(`[groq] non-physical category "${out.category}" — rejecting`)
      return null
    }

    // Groq sometimes returns empty search_query; synthesise one from available fields.
    if (!out.search_query.trim()) {
      const parts = [out.brand, out.model, out.category].filter(s => s.trim())
      out.search_query = parts.join(' ')
    }
    return out.search_query.trim() ? out : null
  } catch {
    return null
  }
}
