import type { Env } from '../lib/schema'
import { DeepIdentifyResult } from '../lib/schema'
import type { DeepIdentifyItem } from '../lib/schema'

const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com/v1beta/models'
export const FLASH = 'gemini-2.5-flash'
export const PRO = 'gemini-2.5-pro'

const SYSTEM_PROMPT =
  'You are a product identification API. Output ONLY a valid JSON array. No markdown, no prose, no code fences.'

function buildPrompt(frameCount: number, hint?: string): string {
  const hintLine = hint ? `\nUser hint: "${hint}"` : ''
  return `The ${frameCount} image(s) above are labeled [Frame 0] through [Frame ${frameCount - 1}].${hintLine}

Identify all distinct products visible across these frames. For each product, record the frame it appears in (frame_index, 0-based).
Return a JSON array where each element is exactly:
{"brand":"","model":"","category":"","distinguishing_features":[],"confidence":0.0,"search_query":"","frame_index":0}

- brand: manufacturer name, or "" if unknown
- model: specific product model or line, or "" if unknown
- category: product type (e.g. "kitchen gadget", "sneaker", "laptop")
- distinguishing_features: up to 5 visual identifiers as strings
- confidence: 0.0–1.0 float for identification certainty
- search_query: Google Shopping query optimized to find this exact product
- frame_index: 0-based index of the frame this product appears in
JSON array only. No other text.`
}

export interface FrameInput {
  base64: string
  mediaType: string
}

interface GeminiPart {
  text?: string
  inline_data?: { mime_type: string; data: string }
}

interface GeminiResponse {
  candidates?: Array<{
    content?: { parts?: GeminiPart[] }
  }>
  error?: { message: string }
}

interface CallOptions {
  frames: FrameInput[]
  hint: string | undefined
  model: string
  apiKey: string
  env: Env
}

async function callAPI(opts: CallOptions): Promise<string> {
  const parts: GeminiPart[] = []
  opts.frames.forEach((frame, i) => {
    parts.push({ text: `[Frame ${i}]:` })
    parts.push({ inline_data: { mime_type: frame.mediaType, data: frame.base64 } })
  })

  const prompt = buildPrompt(opts.frames.length, opts.hint)
  if (opts.env.ENVIRONMENT === 'dev') {
    // Debug only: log prompt text (no image bytes)
    console.log('[debug] Gemini prompt:', prompt)
  }
  parts.push({ text: prompt })

  const url = `${GEMINI_API_BASE}/${opts.model}:generateContent?key=${opts.apiKey}`
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: 'user', parts }],
      generationConfig: { temperature: 0, responseMimeType: 'application/json' },
    }),
  })

  if (!res.ok) {
    const body = await res.text()
    const safeUrl = url.replace(/key=[^&]+/, 'key=REDACTED')
    console.error(
      `[gemini] upstream error — model:${opts.model} status:${res.status} url:${safeUrl} body:${body.slice(0, 500)}`,
    )
    throw new Error(`Gemini ${res.status}: ${body.slice(0, 300)}`)
  }

  const data = await res.json() as GeminiResponse
  if (data.error) throw new Error(`Gemini API error: ${data.error.message}`)

  return data.candidates?.[0]?.content?.parts?.[0]?.text ?? ''
}

function parseResult(raw: string): DeepIdentifyItem[] | null {
  try {
    const cleaned = raw.replace(/```json\s*|```\s*/g, '').trim()
    const parsed: unknown = JSON.parse(cleaned)
    // Gemini may return { items: [...] } or plain array
    const arr = Array.isArray(parsed)
      ? parsed
      : (parsed as Record<string, unknown>).items ?? []
    const result = DeepIdentifyResult.safeParse(arr)
    return result.success ? result.data : null
  } catch {
    return null
  }
}

async function callAndParse(opts: CallOptions): Promise<DeepIdentifyItem[]> {
  const raw = await callAPI(opts)
  const first = parseResult(raw)
  if (first) return first

  // One retry on malformed JSON
  const raw2 = await callAPI(opts)
  const second = parseResult(raw2)
  if (second) return second

  throw new Error(`Gemini returned invalid JSON after retry (model: ${opts.model})`)
}

export async function identifyWithGemini(
  frames: FrameInput[],
  hint: string | undefined,
  env: Env,
): Promise<DeepIdentifyItem[]> {
  const base = { frames, hint, apiKey: env.GEMINI_API_KEY, env }

  const result = await callAndParse({ ...base, model: FLASH })

  // Escalate to Pro when top-item confidence is low
  const maxConf = result.length === 0 ? 0 : Math.max(...result.map((r) => r.confidence))
  if (maxConf < 0.6) {
    return callAndParse({ ...base, model: PRO })
  }

  return result
}
