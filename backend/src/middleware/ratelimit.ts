import type { MiddlewareHandler } from 'hono'
import type { Env, Variables } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { captureError } from '../lib/sentry'

// Daily quotas by tier and route family
const QUOTAS = {
  free: { precision: 10, deep: 30, shop: 100, transcribe: 20, url: 15 },
  pro:  { precision: Infinity, deep: 200, shop: Infinity, transcribe: Infinity, url: Infinity },
} as const

// In-memory fallback used when Upstash isn't configured (local dev only).
// Persists within a single isolate lifetime; resets on wrangler dev restart.
const devCounters = new Map<string, { count: number; expiresAt: number }>()

function devIncr(key: string, expiresAtMs: number): number {
  const now = Date.now()
  const entry = devCounters.get(key)
  if (!entry || entry.expiresAt <= now) {
    devCounters.set(key, { count: 1, expiresAt: expiresAtMs })
    return 1
  }
  entry.count++
  return entry.count
}

function nextMidnightUTC(): { unix: number; secondsUntil: number } {
  const now = Date.now()
  const d = new Date(now)
  const midnight = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1)
  return {
    unix: Math.floor(midnight / 1000),
    secondsUntil: Math.ceil((midnight - now) / 1000),
  }
}

function utcDate(): string {
  return new Date().toISOString().slice(0, 10) // YYYY-MM-DD
}

function routeFamily(path: string): 'precision' | 'deep' | 'shop' | 'transcribe' | 'url' | null {
  if (path.includes('/precision')) return 'precision'
  if (path.includes('/deep')) return 'deep'
  if (path.includes('/shop')) return 'shop'
  if (path.includes('/transcribe')) return 'transcribe'
  if (path.includes('/url')) return 'url'
  return null
}

// Upstash REST pipeline: INCR + EXPIREAT in one round-trip
async function redisIncr(
  key: string,
  expiresAtUnix: number,
  url: string,
  token: string,
): Promise<number> {
  const res = await fetch(`${url}/pipeline`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify([
      ['INCR', key],
      ['EXPIREAT', key, expiresAtUnix],
    ]),
  })

  if (!res.ok) throw new Error(`Redis pipeline HTTP ${res.status}`)

  const rows = await res.json() as Array<{ result?: number; error?: string }>
  if (rows[0]?.error) throw new Error(`Redis INCR: ${rows[0].error}`)
  return rows[0]?.result ?? 0
}

export const rateLimit: MiddlewareHandler<{ Bindings: Env; Variables: Variables }> = async (c, next) => {
  const family = routeFamily(c.req.path)

  // Unrecognised path: no quota consumed
  if (!family) return next()

  const userId = c.get('userId')
  const tier = c.req.header('X-Tier') === 'pro' ? 'pro' : 'free'
  const quota = QUOTAS[tier][family]

  // Pro unlimited precision — skip Redis entirely
  if (!isFinite(quota)) return next()

  const midnight = nextMidnightUTC()
  const key = `rl:${userId}:${family}:${utcDate()}`

  let count = 0
  try {
    const url = c.env.UPSTASH_REDIS_REST_URL
    const token = c.env.UPSTASH_REDIS_REST_TOKEN

    if (url && token) {
      count = await redisIncr(key, midnight.unix, url, token)
    } else {
      // Dev in-memory fallback
      count = devIncr(key, midnight.unix * 1000)
    }
  } catch (err) {
    // Fail open — log to Sentry but never 500 the user
    await captureError(c.env.SENTRY_DSN ?? '', {
      error: err instanceof Error ? err : new Error(String(err)),
      route: 'middleware/ratelimit',
      requestId: c.get('requestId'),
      extras: { family, tier },
    })
    return next()
  }

  if (count > quota) {
    return new Response(
      JSON.stringify(errorBody('rate_limited', `Daily ${family} quota of ${quota} reached`)),
      {
        status: 429,
        headers: {
          'Content-Type': 'application/json',
          'Retry-After': String(midnight.secondsUntil),
        },
      },
    )
  }

  return next()
}
