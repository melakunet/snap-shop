import type { Env } from '../lib/schema'
import { IdentifyResult } from '../lib/schema'

const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'
const GROQ_MODEL = 'meta-llama/llama-4-scout-17b-16e-instruct'

const USER_PROMPT = `Identify the product in this image. Respond with exactly this JSON object and nothing else:
{"brand":"","model":"","category":"","distinguishing_features":[],"confidence":0.0,"search_query":""}

- brand: manufacturer name, or "" if unknown
- model: specific product model or line name, or "" if unknown
- category: product type (e.g. "sneaker", "laptop", "smartwatch", "headphones")
- distinguishing_features: up to 5 visual identifiers as strings
- confidence: 0.0–1.0 float representing identification certainty
- search_query: Google Shopping query optimized to find this exact product
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

  const res = await fetch(GROQ_API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: GROQ_MODEL,
      max_tokens: 512,
      messages: [message],
    }),
  })

  if (!res.ok) {
    const body = await res.text()
    console.error(
      `[groq] upstream error — model:${GROQ_MODEL} status:${res.status} body:${body.slice(0, 500)}`,
    )
    throw new Error(`Groq ${res.status}: ${body.slice(0, 300)}`)
  }

  const data = await res.json() as GroqResponse
  if (data.error) {
    console.error(
      `[groq] api error — model:${GROQ_MODEL} message:${data.error.message}`,
    )
    throw new Error(`Groq error: ${data.error.message}`)
  }

  const raw = data.choices?.[0]?.message?.content ?? ''
  try {
    const cleaned = raw.replace(/```json\s*|```\s*/g, '').trim()
    const parsed: unknown = JSON.parse(cleaned)
    const result = IdentifyResult.safeParse(parsed)
    return result.success ? result.data : null
  } catch {
    return null
  }
}
