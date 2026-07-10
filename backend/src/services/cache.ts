import type { Env } from '../lib/schema'

// In-memory fallback when Upstash isn't configured (local dev only)
const devCache = new Map<string, { serialized: string; expiresAt: number }>()

function devGet<T>(key: string): T | null {
  const entry = devCache.get(key)
  if (!entry || entry.expiresAt <= Date.now()) {
    if (entry) devCache.delete(key)
    return null
  }
  return JSON.parse(entry.serialized) as T
}

function devSet(key: string, value: unknown, ttlSeconds: number): void {
  devCache.set(key, {
    serialized: JSON.stringify(value),
    expiresAt: Date.now() + ttlSeconds * 1000,
  })
}

async function upstashCmd(cmd: unknown[], url: string, token: string): Promise<unknown> {
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(cmd),
  })
  if (!res.ok) throw new Error(`Upstash HTTP ${res.status}`)
  const data = await res.json() as { result: unknown; error?: string }
  if (data.error) throw new Error(`Upstash: ${data.error}`)
  return data.result
}

async function sha256hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input)
  const hash = await crypto.subtle.digest('SHA-256', encoded)
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

// Normalized, deterministic cache key: shop:<128-bit sha256 prefix>
// query is lowercased+trimmed; whitelist is sorted+normalized; sort is included
// so "Amazon.com" and "amazon.com " map to the same key.
export async function buildShopCacheKey(query: string, whitelist: string[], sort = 'price'): Promise<string> {
  const canonical = [
    query.trim().toLowerCase(),
    sort,
    ...whitelist.map((r) => r.trim().toLowerCase()).sort(),
  ].join('\0')
  const hex = await sha256hex(canonical)
  return `shop:${hex.slice(0, 32)}`
}

export async function cacheGet<T>(key: string, env: Env): Promise<T | null> {
  const url = env.UPSTASH_REDIS_REST_URL
  const token = env.UPSTASH_REDIS_REST_TOKEN

  if (url && token) {
    const raw = await upstashCmd(['GET', key], url, token)
    if (raw === null || raw === undefined) return null
    return JSON.parse(String(raw)) as T
  }

  return devGet<T>(key)
}

export async function cacheSet(
  key: string,
  value: unknown,
  ttlSeconds: number,
  env: Env,
): Promise<void> {
  const url = env.UPSTASH_REDIS_REST_URL
  const token = env.UPSTASH_REDIS_REST_TOKEN

  if (url && token) {
    await upstashCmd(['SET', key, JSON.stringify(value), 'EX', ttlSeconds], url, token)
    return
  }

  devSet(key, value, ttlSeconds)
}
