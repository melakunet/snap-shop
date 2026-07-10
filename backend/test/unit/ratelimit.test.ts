import { describe, it, expect } from 'vitest'
import { Hono } from 'hono'
import type { Env, Variables } from '../../src/lib/schema'
import { rateLimit } from '../../src/middleware/ratelimit'

// No Upstash env → middleware falls back to in-memory devCounters
const testEnv = { SENTRY_DSN: '' } as unknown as Env

const FREE_SHOP_QUOTA = 100

// Builds a minimal app that mimics the production middleware chain for /shop.
// A unique userId per test keeps devCounters isolated across test cases.
function buildApp(userId: string) {
  const app = new Hono<{ Bindings: Env; Variables: Variables }>()
  // Simulate what auth middleware does: set userId on the context
  app.use('*', (c, next) => {
    c.set('userId', userId)
    return next()
  })
  app.use('/shop', rateLimit)
  app.post('/shop', (c) => c.json({ ok: true }))
  return app
}

describe('/shop rate limiting', () => {
  it('allows a request within the free-tier quota', async () => {
    const app = buildApp('rl-test-within')
    const res = await app.request('/shop', { method: 'POST' }, testEnv)
    expect(res.status).toBe(200)
  })

  it('returns 429 with rate_limited code once the free-tier quota is exhausted', async () => {
    const app = buildApp('rl-test-exhaust-shop')

    // Consume the entire daily quota
    for (let i = 0; i < FREE_SHOP_QUOTA; i++) {
      const res = await app.request('/shop', { method: 'POST' }, testEnv)
      expect(res.status).toBe(200)
    }

    // The very next request must be rejected
    const limited = await app.request('/shop', { method: 'POST' }, testEnv)
    expect(limited.status).toBe(429)

    const body = await limited.json() as { error: { code: string; message: string } }
    expect(body.error.code).toBe('rate_limited')
    expect(body.error.message.toLowerCase()).toContain('shop')

    // Retry-After header must be present and numeric
    const retryAfter = limited.headers.get('Retry-After')
    expect(retryAfter).not.toBeNull()
    expect(Number(retryAfter)).toBeGreaterThan(0)
  })
})
