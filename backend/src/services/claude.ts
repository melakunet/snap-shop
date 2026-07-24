import type { Env } from '../lib/schema'
import { IdentifyResult } from '../lib/schema'

const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages'

export const SONNET = 'claude-sonnet-4-6'
export const OPUS = 'claude-opus-4-7'

const SYSTEM_PROMPT =
  'You are a product identification API. Output ONLY valid JSON. No markdown, no prose, no code fences.'

const USER_PROMPT = `Identify the product in this image. Respond with exactly this JSON object and nothing else:
{"brand":"","model":"","category":"","distinguishing_features":[],"confidence":0.0,"search_query":""}

- brand: manufacturer name, or "" if unknown
- model: specific product model or line name, or "" if unknown
- category: product type (e.g. "sneaker", "laptop", "smartwatch", "headphones")
- distinguishing_features: up to 5 visual identifiers as strings
- confidence: 0.0–1.0 float representing identification certainty
- search_query: Google Shopping query optimized to find this exact product
Respond with the JSON object only. No other text.`

interface CallOptions {
  imageBase64: string
  mediaType: string
  model: string
  apiKey: string
}

interface AnthropicMessage {
  content: Array<{ type: string; text?: string }>
}

async function callAPI(opts: CallOptions): Promise<string> {
  const res = await fetch(ANTHROPIC_API_URL, {
    method: 'POST',
    headers: {
      'x-api-key': opts.apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: opts.model,
      max_tokens: 512,
      system: SYSTEM_PROMPT,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'image',
            source: { type: 'base64', media_type: opts.mediaType, data: opts.imageBase64 },
          },
          { type: 'text', text: USER_PROMPT },
        ],
      }],
    }),
  })

  if (!res.ok) {
    const body = await res.text()
    throw new Error(`Anthropic ${res.status}: ${body.slice(0, 300)}`)
  }

  const msg = await res.json() as AnthropicMessage
  return msg.content.find((c) => c.type === 'text')?.text ?? ''
}

function parseResult(raw: string): IdentifyResult | null {
  try {
    // Strip markdown fences if the model adds them despite instructions
    const cleaned = raw.replace(/```json\s*|```\s*/g, '').trim()
    const parsed = JSON.parse(cleaned)
    const result = IdentifyResult.safeParse(parsed)
    return result.success ? result.data : null
  } catch {
    return null
  }
}

async function callAndParse(opts: CallOptions): Promise<IdentifyResult> {
  const raw = await callAPI(opts)
  const first = parseResult(raw)
  if (first) return first

  // One retry on malformed JSON
  const raw2 = await callAPI(opts)
  const second = parseResult(raw2)
  if (second) return second

  throw new Error(`Claude returned invalid JSON after retry (model: ${opts.model})`)
}

export async function identifyWithClaude(
  imageBase64: string,
  mediaType: string,
  env: Env,
  isPro: boolean,
): Promise<IdentifyResult> {
  if (!env.ANTHROPIC_API_KEY) throw new Error('ANTHROPIC_API_KEY is not configured')

  const base = { imageBase64, mediaType, apiKey: env.ANTHROPIC_API_KEY }

  const result = await callAndParse({ ...base, model: SONNET })

  // Pro tier with low confidence → escalate to Opus
  if (isPro && result.confidence < 0.6) {
    return callAndParse({ ...base, model: OPUS })
  }

  return result
}
