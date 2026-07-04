import { describe, it, expect } from 'vitest'
import { IdentifyResult, ShopRequest, Env } from '../../src/lib/schema'

describe('IdentifyResult schema', () => {
  const valid = {
    brand: 'Nike',
    model: 'Air Force 1',
    category: 'sneaker',
    distinguishing_features: ['Low-top profile', 'Swoosh logo'],
    confidence: 0.87,
    search_query: 'Nike Air Force 1 low sneaker',
  }

  it('parses a valid object', () => {
    const result = IdentifyResult.safeParse(valid)
    expect(result.success).toBe(true)
  })

  it('fails when a required field is missing', () => {
    const { brand: _brand, ...withoutBrand } = valid
    const result = IdentifyResult.safeParse(withoutBrand)
    expect(result.success).toBe(false)
  })

  it('fails when confidence is below 0', () => {
    const result = IdentifyResult.safeParse({ ...valid, confidence: -0.1 })
    expect(result.success).toBe(false)
  })

  it('fails when confidence is above 1', () => {
    const result = IdentifyResult.safeParse({ ...valid, confidence: 1.1 })
    expect(result.success).toBe(false)
  })

  it('accepts confidence of exactly 0', () => {
    const result = IdentifyResult.safeParse({ ...valid, confidence: 0 })
    expect(result.success).toBe(true)
  })

  it('accepts confidence of exactly 1', () => {
    const result = IdentifyResult.safeParse({ ...valid, confidence: 1 })
    expect(result.success).toBe(true)
  })
})

describe('ShopRequest schema', () => {
  it('parses a valid request', () => {
    const result = ShopRequest.safeParse({ query: 'Nike Air Force 1', retailer_whitelist: [] })
    expect(result.success).toBe(true)
  })

  it('fails when query is missing', () => {
    const result = ShopRequest.safeParse({ retailer_whitelist: [] })
    expect(result.success).toBe(false)
  })

  it('fails when query is an empty string', () => {
    const result = ShopRequest.safeParse({ query: '', retailer_whitelist: [] })
    expect(result.success).toBe(false)
  })

  it('parses when retailer_whitelist has entries', () => {
    const result = ShopRequest.safeParse({ query: 'test', retailer_whitelist: ['Amazon', 'Best Buy'] })
    expect(result.success).toBe(true)
  })
})

describe('Env schema', () => {
  const requiredEnv = {
    ENVIRONMENT: 'dev',
    APPLE_BUNDLE_ID: 'com.example.app',
    ANTHROPIC_API_KEY: 'sk-ant-xxx',
    GEMINI_API_KEY: 'AIzaSy-xxx',
    SERPAPI_KEY: 'serpapi-xxx',
    SENTRY_DSN: 'https://xxx@sentry.io/123',
    PLAUSIBLE_DOMAIN: 'example.com',
  }

  it('parses when all required fields are present', () => {
    const result = Env.safeParse(requiredEnv)
    expect(result.success).toBe(true)
  })

  it('treats optional fields as ok when absent', () => {
    const result = Env.safeParse(requiredEnv)
    expect(result.success).toBe(true)
    if (result.success) {
      expect(result.data.UPSTASH_REDIS_REST_URL).toBeUndefined()
      expect(result.data.DEV_AUTH_BYPASS).toBeUndefined()
    }
  })

  it('fails when ENVIRONMENT is missing', () => {
    const { ENVIRONMENT: _env, ...withoutEnv } = requiredEnv
    const result = Env.safeParse(withoutEnv)
    expect(result.success).toBe(false)
  })

  it('parses optional free-tier keys when present', () => {
    const result = Env.safeParse({
      ...requiredEnv,
      GROQ_API_KEY: 'gsk_xxx',
      UPCITEMDB_KEY: 'upc_xxx',
      BESTBUY_API_KEY: 'bbk_xxx',
      EBAY_APP_ID: 'eba_xxx',
    })
    expect(result.success).toBe(true)
  })
})
