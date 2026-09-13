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

// Escape a string for use in a RegExp literal.
function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

// Returns true when `word` appears as a whole word inside `text`.
function containsWholeWord(text: string, word: string): boolean {
  return new RegExp(`\\b${escapeRe(word)}\\b`).test(text)
}

export function matchDangerousPlant(
  commonName: string,
  latinName: string,
  extraText?: string,  // e.g. features_observed joined — searched last, after name matches
): DangerEntry | null {
  const nc = commonName.toLowerCase().trim()
  const nl = latinName.toLowerCase().trim()
  const nx = extraText?.toLowerCase() ?? ''

  // 1. Exact matches first — prevents "white baneberry" from hitting "baneberry" via partial
  const exact = DB.find(
    (p) => (nc && p.common_name === nc) || (nl && p.latin_name && p.latin_name === nl),
  )
  if (exact) return exact

  // 2. DB entry's common_name as a whole word in identified common_name
  //    "american baneberry" → "baneberry"; "wild foxglove" → "foxglove"
  if (nc) {
    const inCommon = DB.find((p) => containsWholeWord(nc, p.common_name))
    if (inCommon) return inCommon
  }

  // 3. DB entry's common_name as a whole word anywhere in the identified latin_name
  //    Handles edge cases where model puts the common name in the latin field
  if (nl) {
    const inLatin = DB.find((p) => containsWholeWord(nl, p.common_name))
    if (inLatin) return inLatin
  }

  // 4. DB entry's common_name as a whole word in extra context (features_observed)
  //    "foxglove printed on packet" → "foxglove" → dangerous match
  if (nx) {
    const inExtra = DB.find((p) => containsWholeWord(nx, p.common_name))
    if (inExtra) return inExtra
  }

  // 5. Latin genus match: first word of DB entry's latin vs first word of identified latin
  //    "digitalis spp." → genus "digitalis" = genus of "digitalis purpurea" → foxglove
  if (nl) {
    const identGenus = nl.split(' ')[0]
    if (identGenus) {
      const byGenus = DB.find((p) => {
        const dbGenus = p.latin_name?.split(' ')[0]
        return dbGenus === identGenus
      })
      if (byGenus) return byGenus
    }
  }

  return null
}

// ── Plant-like detection ──────────────────────────────────────────────────────

const PLANT_CAT_KEYWORDS = [
  'plant', 'flower', 'berry', 'berries', 'mushroom', 'fungus', 'fungi',
  'fern', 'moss', 'vine', 'shrub', 'bush', 'herb', 'weed', 'houseplant',
  'succulent', 'cactus', 'tree', 'wildflower', 'foliage', 'vegetation',
  'grass', 'algae', 'sprout', 'seedling', 'botanical', 'garden',
  // Plant-adjacent commerce categories (seed packets, bulbs, perennials, etc.)
  'seed', 'bulb', 'perennial', 'annual', 'blossom', 'pod', 'cutting',
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

export const UNVERIFIED_CAUTION =
  'Unverified plant — do not eat or handle unknown plants.'

// ── Specialist vision call ────────────────────────────────────────────────────

const PLANT_SPECIALIST_PROMPT = `Identify this plant's species. If the image shows a seed packet, plant label, bulb package, or any plant-commerce product, identify the PLANT SPECIES it contains or depicts — not the packaging itself.

Return ONLY this JSON object, no other text:
{"common_name":"","latin_name":"","confidence":0.0,"features_observed":[],"hazard_signals":[]}

- common_name: the specific plant species common name (e.g. "Foxglove", "Baneberry", "Oleander"). NEVER use packaging or commerce labels such as "flower seed", "seeds", "bulb", "annual", "perennial", or "plant" as the common_name. If a seed packet shows "Foxglove" or "Digitalis", the common_name is "Foxglove". Set to "unknown" only when you genuinely cannot determine the species.
- latin_name: scientific binomial (e.g. "Digitalis purpurea"), or "" if unknown
- confidence: 0.0–1.0 species identification certainty
- features_observed: up to 5 visible botanical features OR plant names visible on any label or packaging (e.g. "foxglove printed on packet", "bell-shaped purple flowers shown", "red berry clusters")
- hazard_signals: visible toxicity indicators (e.g. "red berries", "milky sap", "umbrella flower clusters"); empty array if none

NEVER substitute a commercially popular plant for a different wild plant — accuracy over helpfulness.
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

// Retries on Groq 429 (transient TPM rate-limit) with exponential backoff.
const PLANT_GROQ_RETRIES = 2

async function fetchGroqPlantWithRetry(init: RequestInit): Promise<Response> {
  let res!: Response
  for (let attempt = 0; attempt <= PLANT_GROQ_RETRIES; attempt++) {
    if (attempt > 0) {
      await new Promise<void>(r => setTimeout(r, attempt * 1_000))
      console.warn(`[groq/plant] 429 rate-limited — retry ${attempt}/${PLANT_GROQ_RETRIES}`)
    }
    res = await fetch(GROQ_API_URL, init)
    if (res.status !== 429) return res
  }
  return res
}

async function callGroqPlant(imageBase64: string, mediaType: string, apiKey: string): Promise<string> {
  const message: GroqMessage = {
    role: 'user',
    content: [
      { type: 'image_url', image_url: { url: `data:${mediaType};base64,${imageBase64}` } },
      { type: 'text', text: PLANT_SPECIALIST_PROMPT },
    ],
  }
  const init: RequestInit = {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: GROQ_MODEL,
      max_completion_tokens: 256,
      reasoning_effort: 'none',
      messages: [message],
    }),
  }
  const res = await fetchGroqPlantWithRetry(init)
  if (!res.ok) {
    const body = await res.text()
    console.error(`[groq/plant] status:${res.status} body:${body.slice(0, 300)}`)
    throw new Error(
      res.status === 429
        ? 'Too many requests — try again in a moment'
        : 'Plant identification temporarily unavailable',
    )
  }
  const data = await res.json() as GroqResponse
  if (data.error) {
    console.error(`[groq/plant] api error: ${data.error.message}`)
    throw new Error('Plant identification temporarily unavailable')
  }
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
  // Pass features_observed as extra context so commerce-label edge cases
  // (e.g. common_name:"flower seed", features:["foxglove printed on packet"]) still match.
  const danger = matchDangerousPlant(
    specialist.common_name,
    specialist.latin_name,
    specialist.features_observed.join(' '),
  )
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
    // Berry/mushroom note takes precedence over the generic unverified caution
    base.safety_note = SAFETY_NOTE
  } else if (!danger && specialist.confidence < 0.5 && specialist.common_name.toLowerCase() !== 'unknown') {
    // Low-confidence plant that didn't match any dangerous species — soft caution so it
    // never appears unconditionally safe to the user
    base.safety_note = UNVERIFIED_CAUTION
  }
  return base
}
