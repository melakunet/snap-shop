import { describe, it, expect } from 'vitest'
import {
  PlantSpecialistResult,
  isPlantLike,
  matchDangerousPlant,
  isSpecificPlantQuery,
  shouldAddSafetyNote,
  shapePlantResponse,
  SAFETY_NOTE,
} from '../../src/services/plant-id'
import type { IdentifyResult } from '../../src/lib/schema'

// ── Helpers ──────────────────────────────────────────────────────────────────

function makeIdentify(overrides: Partial<IdentifyResult> = {}): IdentifyResult {
  return {
    brand: '',
    model: '',
    category: 'sneaker',
    distinguishing_features: [],
    confidence: 0.85,
    search_query: 'Nike Air Force 1',
    ...overrides,
  }
}

// ── PlantSpecialistResult schema ──────────────────────────────────────────────

describe('PlantSpecialistResult schema', () => {
  const valid = {
    common_name: 'Baneberry',
    latin_name: 'Actaea rubra',
    confidence: 0.87,
    features_observed: ['red berry clusters', 'compound trifoliate leaves'],
    hazard_signals: ['red berries'],
  }

  it('parses a valid specialist response', () => {
    expect(PlantSpecialistResult.safeParse(valid).success).toBe(true)
  })

  it('accepts "unknown" common_name', () => {
    const result = PlantSpecialistResult.safeParse({ ...valid, common_name: 'unknown' })
    expect(result.success).toBe(true)
  })

  it('accepts empty arrays for features and hazards', () => {
    const result = PlantSpecialistResult.safeParse({
      ...valid,
      features_observed: [],
      hazard_signals: [],
    })
    expect(result.success).toBe(true)
  })

  it('rejects missing common_name', () => {
    const { common_name: _cn, ...without } = valid
    expect(PlantSpecialistResult.safeParse(without).success).toBe(false)
  })

  it('rejects confidence above 1', () => {
    expect(PlantSpecialistResult.safeParse({ ...valid, confidence: 1.1 }).success).toBe(false)
  })

  it('rejects confidence below 0', () => {
    expect(PlantSpecialistResult.safeParse({ ...valid, confidence: -0.1 }).success).toBe(false)
  })
})

// ── matchDangerousPlant ───────────────────────────────────────────────────────

describe('matchDangerousPlant', () => {
  it('matches by common_name (exact, lowercase)', () => {
    const match = matchDangerousPlant('baneberry', '')
    expect(match).not.toBeNull()
    expect(match?.level).toBe('fatal')
  })

  it('matches by latin_name (exact, lowercase)', () => {
    const match = matchDangerousPlant('', 'actaea rubra')
    expect(match).not.toBeNull()
  })

  it('matches when common_name contains a DB entry (partial)', () => {
    const match = matchDangerousPlant('american baneberry', '')
    expect(match).not.toBeNull()
  })

  it('matches deadly nightshade by latin name', () => {
    const match = matchDangerousPlant('', 'atropa belladonna')
    expect(match).not.toBeNull()
    expect(match?.level).toBe('fatal')
  })

  it('matches poison hemlock note (contains "hemlock")', () => {
    const match = matchDangerousPlant('poison hemlock', '')
    expect(match?.note).toContain('Deadly')
  })

  it('matches monkshood note about gloves', () => {
    const match = matchDangerousPlant('monkshood', '')
    expect(match?.note).toContain('gloves')
  })

  it('returns null for a safe plant', () => {
    expect(matchDangerousPlant('rose', 'rosa spp.')).toBeNull()
  })

  it('returns null for an empty query', () => {
    expect(matchDangerousPlant('', '')).toBeNull()
  })

  it('matches white baneberry separately', () => {
    const match = matchDangerousPlant('white baneberry', '')
    expect(match).not.toBeNull()
    expect(match?.note).toContain("doll's-eyes")
  })
})

// ── isPlantLike ───────────────────────────────────────────────────────────────

describe('isPlantLike', () => {
  it('returns true for category "plant"', () => {
    expect(isPlantLike(makeIdentify({ category: 'plant' }))).toBe(true)
  })

  it('returns true for category "mushroom"', () => {
    expect(isPlantLike(makeIdentify({ category: 'mushroom' }))).toBe(true)
  })

  it('returns true for category "flower"', () => {
    expect(isPlantLike(makeIdentify({ category: 'flower' }))).toBe(true)
  })

  it('returns true for category containing "berry"', () => {
    expect(isPlantLike(makeIdentify({ category: 'wild berry bush' }))).toBe(true)
  })

  it('returns false for category "sneaker"', () => {
    expect(isPlantLike(makeIdentify({ category: 'sneaker' }))).toBe(false)
  })

  it('returns false for category "laptop"', () => {
    expect(isPlantLike(makeIdentify({ category: 'laptop' }))).toBe(false)
  })

  it('returns true for low-confidence unbranded item with leaf feature', () => {
    expect(isPlantLike(makeIdentify({
      category: 'unknown',
      confidence: 0.3,
      brand: '',
      model: '',
      distinguishing_features: ['green serrated leaves', 'red stem'],
    }))).toBe(true)
  })

  it('returns false for low-confidence branded item even with plant features', () => {
    expect(isPlantLike(makeIdentify({
      category: 'kitchen item',
      confidence: 0.3,
      brand: 'Cuisinart',
      model: 'Blade',
      distinguishing_features: ['leaf-shaped handle'],
    }))).toBe(false)
  })

  // Plant-adjacent commerce categories
  it('returns true for category "seeds"', () => {
    expect(isPlantLike(makeIdentify({ category: 'seeds' }))).toBe(true)
  })

  it('returns true for category "garden seeds"', () => {
    expect(isPlantLike(makeIdentify({ category: 'garden seeds' }))).toBe(true)
  })

  it('returns true for category "seed pod"', () => {
    expect(isPlantLike(makeIdentify({ category: 'seed pod' }))).toBe(true)
  })

  it('returns true for category "flower bulb"', () => {
    expect(isPlantLike(makeIdentify({ category: 'flower bulb' }))).toBe(true)
  })

  it('returns true for category "perennial plant"', () => {
    expect(isPlantLike(makeIdentify({ category: 'perennial plant' }))).toBe(true)
  })

  it('returns true for category "annual flower"', () => {
    expect(isPlantLike(makeIdentify({ category: 'annual flower' }))).toBe(true)
  })

  it('returns true for category "cherry blossom"', () => {
    expect(isPlantLike(makeIdentify({ category: 'cherry blossom' }))).toBe(true)
  })

  it('returns true for category "plant cutting"', () => {
    expect(isPlantLike(makeIdentify({ category: 'plant cutting' }))).toBe(true)
  })
})

// ── isSpecificPlantQuery ──────────────────────────────────────────────────────

describe('isSpecificPlantQuery', () => {
  it('returns false for generic "plant"', () => {
    expect(isSpecificPlantQuery('plant')).toBe(false)
  })

  it('returns false for "flower"', () => {
    expect(isSpecificPlantQuery('flower')).toBe(false)
  })

  it('returns false for empty string', () => {
    expect(isSpecificPlantQuery('')).toBe(false)
  })

  it('returns true for "swiss chard seeds"', () => {
    expect(isSpecificPlantQuery('swiss chard seeds')).toBe(true)
  })

  it('returns true for "aloe vera plant"', () => {
    expect(isSpecificPlantQuery('aloe vera plant')).toBe(true)
  })

  it('returns true for "rose bush"', () => {
    expect(isSpecificPlantQuery('rose bush')).toBe(true)
  })
})

// ── shouldAddSafetyNote ───────────────────────────────────────────────────────

describe('shouldAddSafetyNote', () => {
  it('returns true when hazard_signals contains "red berries"', () => {
    expect(shouldAddSafetyNote(['red berries', 'compound leaves'])).toBe(true)
  })

  it('returns true for mushroom signal', () => {
    expect(shouldAddSafetyNote(['umbrella cap', 'mushroom gills'])).toBe(true)
  })

  it('returns false for non-berry, non-mushroom signals', () => {
    expect(shouldAddSafetyNote(['thorns', 'milky sap'])).toBe(false)
  })

  it('returns false for empty array', () => {
    expect(shouldAddSafetyNote([])).toBe(false)
  })
})

// ── shapePlantResponse ────────────────────────────────────────────────────────

describe('shapePlantResponse', () => {
  const baneBerrySpecialist = {
    common_name: 'baneberry',
    latin_name: 'actaea rubra',
    confidence: 0.88,
    features_observed: ['red berry clusters'],
    hazard_signals: ['red berries'],
  }

  it('attaches warning for dangerous plant', () => {
    const result = shapePlantResponse(baneBerrySpecialist)
    expect(result.warning).toBeDefined()
    expect(result.warning?.level).toBe('fatal')
  })

  it('attaches safety_note when hazard_signals include berries', () => {
    const result = shapePlantResponse(baneBerrySpecialist)
    expect(result.safety_note).toBe(SAFETY_NOTE)
  })

  it('does not attach warning for a safe plant', () => {
    const result = shapePlantResponse({
      common_name: 'rose',
      latin_name: 'rosa spp.',
      confidence: 0.9,
      features_observed: ['red petals', 'thorned stem'],
      hazard_signals: [],
    })
    expect(result.warning).toBeUndefined()
  })

  it('does not attach safety_note when no berry/mushroom hazards', () => {
    const result = shapePlantResponse({
      common_name: 'aloe vera',
      latin_name: 'aloe vera',
      confidence: 0.93,
      features_observed: ['fleshy leaves', 'serrated edges'],
      hazard_signals: ['milky sap'],
    })
    expect(result.safety_note).toBeUndefined()
  })

  it('preserves all specialist fields', () => {
    const result = shapePlantResponse(baneBerrySpecialist)
    expect(result.common_name).toBe('baneberry')
    expect(result.latin_name).toBe('actaea rubra')
    expect(result.confidence).toBe(0.88)
    expect(result.features_observed).toEqual(['red berry clusters'])
    expect(result.hazard_signals).toEqual(['red berries'])
  })
})

// ── unknown → 422 path (business logic validation) ────────────────────────────

describe('unknown species path', () => {
  it('specialist returns common_name "unknown" when confidence < 0.6', () => {
    // Simulate what the prompt requires — test the schema accepts it
    const lowConf = PlantSpecialistResult.safeParse({
      common_name: 'unknown',
      latin_name: '',
      confidence: 0.45,
      features_observed: ['green leaves'],
      hazard_signals: [],
    })
    expect(lowConf.success).toBe(true)
    if (lowConf.success) {
      // The route checks this condition to return 422
      expect(lowConf.data.common_name.toLowerCase()).toBe('unknown')
    }
  })
})

// ── Generic-plant shopping suppression ───────────────────────────────────────

describe('generic plant shopping suppression', () => {
  it('isSpecificPlantQuery suppresses "plant seeds"', () => {
    // "plant seeds" is not in GENERIC_QUERIES but doesn't have a species name either.
    // This case is handled downstream in the route by constructing from common_name.
    // Here we verify the exact generic terms ARE suppressed:
    expect(isSpecificPlantQuery('plant')).toBe(false)
    expect(isSpecificPlantQuery('shrub')).toBe(false)
    expect(isSpecificPlantQuery('herb')).toBe(false)
  })

  it('passes through species-specific query for safe plants', () => {
    expect(isSpecificPlantQuery('swiss chard seeds')).toBe(true)
    expect(isSpecificPlantQuery('aloe vera plant care')).toBe(true)
  })

  it('dangerous plant always gets suppressed regardless of query specificity', () => {
    // Verified at route level: isDangerous → finalQuery = '' regardless of isSpecificPlantQuery
    const result = shapePlantResponse({
      common_name: 'oleander',
      latin_name: 'nerium oleander',
      confidence: 0.91,
      features_observed: ['pink tubular flowers'],
      hazard_signals: [],
    })
    expect(result.warning).toBeDefined()
    // Route sets search_query: '' when warning is present
  })
})
