import { z } from 'zod'
import type { Env } from '../lib/schema'
import { IdentifyResult } from '../lib/schema'
import dangerousPlants from '../data/dangerous-plants.json'

const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'
const GROQ_MODEL = 'qwen/qwen3.6-27b'

// ── Schemas ──────────────────────────────────────────────────────────────────

export const PlantSpecialistResult = z.object({
  common_name: z.string(),
  latin_name: z.string(),
  confidence: z.number().min(0).max(1),
  features_observed: z.array(z.string()),
  hazard_signals: z.array(z.string()),
})
export type PlantSpecialistResult = z.infer<typeof PlantSpecialistResult>

// ── Dangerous-plant DB ────────────────────────────────────────────────────────

interface DangerEntry {
  common_name: string
  latin_name: string
  level: string
  note: string
}

const DB = dangerousPlants as DangerEntry[]

export function matchDangerousPlant(
  commonName: string,
  latinName: string,
): DangerEntry | null {
  const nc = commonName.toLowerCase().trim()
  const nl = latinName.toLowerCase().trim()
  // Exact matches first — prevents "white baneberry" from hitting "baneberry" via partial
  const exact = DB.find(
    (p) => (nc && p.common_name === nc) || (nl && p.latin_name && p.latin_name === nl),
  )
  if (exact) return exact
  // Partial common-name match: "american baneberry" → "baneberry"
  if (nc) return DB.find((p) => nc.includes(p.common_name)) ?? null
  return null
}

// ── Plant-like detection ──────────────────────────────────────────────────────

const PLANT_CAT_KEYWORDS = [
  'plant', 'flower', 'berry', 'berries', 'mushroom', 'fungus', 'fungi',
  'fern', 'moss', 'vine', 'shrub', 'bush', 'herb', 'weed', 'houseplant',
  'succulent', 'cactus', 'tree', 'wildflower', 'foliage', 'vegetation',
  'grass', 'algae', 'sprout', 'seedling', 'botanical', 'garden',
]

const PLANT_FEATURE_WORDS = [
  'leaf', 'leaves', 'petal', 'stem', 'root', 'bark',
  'flower', 'berry', 'thorn', 'vine', 'branch', 'frond',
]

export function isPlantLike(result: IdentifyResult): boolean {
  const cat = result.category.toLowerCase()
  if (PLANT_CAT_KEYWORDS.some((k) => cat.includes(k))) return true

  // Low-confidence with no brand/model + plant visual features → likely a plant
  if (result.confidence < 0.5 && !result.brand && !result.model) {
    const features = result.distinguishing_features.map((f) => f.toLowerCase()).join(' ')
    if (PLANT_FEATURE_WORDS.some((w) => features.includes(w))) return true
  }
  return false
}

// ── Shopping suppression ──────────────────────────────────────────────────────

const GENERIC_QUERIES = [
  'plant', 'flower', 'tree', 'shrub', 'herb', 'bush', 'grass',
  'weed', 'vegetation', 'foliage', 'garden plant', 'houseplant',
]

export function isSpecificPlantQuery(query: string): boolean {
  if (!query.trim()) return false
  const q = query.toLowerCase().trim()
  return !GENERIC_QUERIES.includes(q)
}

// ── Safety note ───────────────────────────────────────────────────────────────

const HAZARD_NOTE_TRIGGERS = ['berry', 'berries', 'mushroom', 'fungus', 'fungi']

export function shouldAddSafetyNote(hazardSignals: string[]): boolean {
  const combined = hazardSignals.join(' ').toLowerCase()
  return HAZARD_NOTE_TRIGGERS.some((k) => combined.includes(k))
}

export const SAFETY_NOTE =
  'Never eat wild berries or mushrooms based on an app identification.'

// ── Specialist vision call ────────────────────────────────────────────────────

const PLANT_SPECIALIST_PROMPT = `Identify this plant's species. Return ONLY this JSON object, no other text:
{"common_name":"","latin_name":"","confidence":0.0,"features_observed":[],"hazard_signals":[]}

- common_name: specific common English name (e.g. "Baneberry", "Swiss chard"), or "unknown" if you cannot identify the species with confidence >= 0.6
- latin_name: scientific binomial name, or "" if unknown
- confidence: 0.0–1.0 float for species identification certainty
- features_observed: up to 5 visible botanical features (e.g. "red berry clusters", "opposite serrated leaves")
- hazard_signals: visible signs of potential toxicity risk (e.g. "red berries", "milky sap", "umbrella flower clusters"); empty array if none observed

NEVER guess a commercially popular plant for a wild plant just because it is common — accuracy over helpfulness.
If confidence < 0.6, set common_name to "unknown".
JSON object only. No markdown, no prose.`

interface GroqMessage {
  role: string
  content: Array<
    | { type: 'text'; text: string }
    | { type: 'image_url'; image_url: { url: string } }
  >
}

interface GroqChoice { message?: { content?: string } }
interface GroqResponse { choices?: GroqChoice[]; error?: { message?: string } }

async function callGroqPlant(imageBase64: string, mediaType: string, apiKey: string): Promise<string> {
  const message: GroqMessage = {
    role: 'user',
    content: [
      { type: 'image_url', image_url: { url: `data:${mediaType};base64,${imageBase64}` } },
      { type: 'text', text: PLANT_SPECIALIST_PROMPT },
    ],
  }
  const res = await fetch(GROQ_API_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: GROQ_MODEL,
      max_completion_tokens: 256,
      reasoning_effort: 'none',
      messages: [message],
    }),
  })
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`Groq plant-specialist ${res.status}: ${body.slice(0, 300)}`)
  }
  const data = await res.json() as GroqResponse
  if (data.error) throw new Error(`Groq plant-specialist error: ${data.error.message}`)
  return data.choices?.[0]?.message?.content ?? ''
}

function parsePlantResponse(raw: string): PlantSpecialistResult | null {
  try {
    const cleaned = raw.replace(/```json\s*|```\s*/g, '').trim()
    const parsed: unknown = JSON.parse(cleaned)
    const result = PlantSpecialistResult.safeParse(parsed)
    return result.success ? result.data : null
  } catch {
    return null
  }
}

export async function identifyPlantSpecies(
  imageBase64: string,
  mediaType: string,
  env: Env,
): Promise<PlantSpecialistResult | null> {
  if (!env.GROQ_API_KEY) return null  // graceful skip — caller treats as non-plant

  console.log('[plant-id] specialist pass firing — second vision call for plant scan')

  const raw = await callGroqPlant(imageBase64, mediaType, env.GROQ_API_KEY)
  const first = parsePlantResponse(raw)
  if (first) return first

  // One retry on malformed JSON
  const raw2 = await callGroqPlant(imageBase64, mediaType, env.GROQ_API_KEY)
  return parsePlantResponse(raw2)
}

// ── Response shaping helper ───────────────────────────────────────────────────

export interface PlantResponse {
  common_name: string
  latin_name: string
  confidence: number
  features_observed: string[]
  hazard_signals: string[]
  warning?: { level: string; note: string }
  safety_note?: string
}

export function shapePlantResponse(
  specialist: PlantSpecialistResult,
): PlantResponse {
  const danger = matchDangerousPlant(specialist.common_name, specialist.latin_name)
  const addNote = shouldAddSafetyNote(specialist.hazard_signals)
  const base: PlantResponse = {
    common_name: specialist.common_name,
    latin_name: specialist.latin_name,
    confidence: specialist.confidence,
    features_observed: specialist.features_observed,
    hazard_signals: specialist.hazard_signals,
  }
  if (danger) {
    base.warning = { level: danger.level, note: danger.note }
  }
  if (addNote) {
    base.safety_note = SAFETY_NOTE
  }
  return base
}
