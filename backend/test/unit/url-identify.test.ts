import { describe, it, expect, vi, afterEach } from 'vitest'
import { Hono } from 'hono'
import type { Env, Variables } from '../../src/lib/schema'
import { identifyFromURL, deriveQueryFromUrl } from '../../src/services/url-identify'
import urlRoute from '../../src/routes/identify-url'

const noEnv = {} as unknown as Env

function buildApp() {
  const app = new Hono<{ Bindings: Env; Variables: Variables }>()
  app.use('*', (c, next) => {
    c.set('userId', 'test-user')
    return next()
  })
  app.route('/identify/url', urlRoute)
  return app
}

function stubFetch(html: string, status = 200) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: status >= 200 && status < 300,
      status,
      text: () => Promise.resolve(html),
    }),
  )
}

afterEach(() => vi.restoreAllMocks())

describe('deriveQueryFromUrl helper', () => {
  it('extracts name from simple slug', () => {
    expect(deriveQueryFromUrl('https://example.com/product-name')).toBe('product name')
  })

  it('strips extension and handles underscores', () => {
    expect(deriveQueryFromUrl('https://example.com/some_product_item.html')).toBe('some product item')
  })

  it('handles query strings and trailing slashes', () => {
    expect(deriveQueryFromUrl('https://example.com/path/slug-name/?id=123')).toBe('slug name')
  })

  it('filters out pure numbers and size tokens', () => {
    expect(deriveQueryFromUrl('https://example.com/myrrh-tonka-room-spray-100ml-xl-42')).toBe(
      'myrrh tonka room spray',
    )
  })

  it('returns null for bare domains', () => {
    expect(deriveQueryFromUrl('https://example.com/')).toBeNull()
  })

  it('returns null for ID-only segments', () => {
    expect(deriveQueryFromUrl('https://example.com/123456')).toBeNull()
    expect(deriveQueryFromUrl('https://example.com/123456/789')).toBeNull()
  })
})

describe('identifyFromURL service', () => {
  it('extracts name and returns confidence 0.9 on success', async () => {
    stubFetch(
      '<html><script type="application/ld+json">{"@type":"Product","name":"Sony WH-1000XM5"}</script></html>',
    )
    const r = await identifyFromURL('https://a.example.com/1', noEnv)
    expect(r.productName).toBe('Sony WH-1000XM5')
    expect(r.confidence).toBe(0.9)
  })

  it('sends realistic browser headers including Referer', async () => {
    const fetchSpy = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      text: () => Promise.resolve('<html><title>T</title></html>'),
    })
    vi.stubGlobal('fetch', fetchSpy)

    const url = 'https://store.example.com/p/item'
    await identifyFromURL(url, noEnv)

    const headers = fetchSpy.mock.calls[0][1].headers
    expect(headers['User-Agent']).toContain('Chrome')
    expect(headers['Referer']).toBe('https://store.example.com')
  })

  it('falls back to slug derivation on 403 Forbidden', async () => {
    stubFetch('Access Denied', 403)
    const r = await identifyFromURL('https://retailer.com/nike-air-max-90', noEnv)
    expect(r.confidence).toBe(0.5)
    expect(r.productName).toBe('nike air max 90')
    expect(r.searchQuery).toBe('nike air max 90')
  })

  it('falls back to slug derivation when fetch fails (network error)', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('Network error')))
    const r = await identifyFromURL('https://retailer.com/jo-malone-candle', noEnv)
    expect(r.confidence).toBe(0.5)
    expect(r.productName).toBe('jo malone candle')
  })

  it('throws when the page returns 403 AND no slug can be derived', async () => {
    stubFetch('', 403)
    await expect(identifyFromURL('https://retailer.com/12345', noEnv)).rejects.toThrow('Could not fetch')
  })
})

describe('POST /identify/url route', () => {
  it('returns confidence in the response', async () => {
    stubFetch(
      '<html><script type="application/ld+json">{"@type":"Product","name":"Test Product"}</script></html>',
    )
    const res = await buildApp().request('/identify/url', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: 'https://g.example.com/product' }),
    }, noEnv)
    expect(res.status).toBe(200)
    const b = (await res.json()) as { model: string; confidence: number }
    expect(b.model).toBe('Test Product')
    expect(b.confidence).toBe(0.9)
  })

  it('returns 200 with confidence 0.5 when falling back to slug', async () => {
    stubFetch('Blocked', 403)
    const res = await buildApp().request('/identify/url', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: 'https://h.example.com/slug-fallback' }),
    }, noEnv)
    expect(res.status).toBe(200)
    const b = (await res.json()) as { model: string; confidence: number }
    expect(b.model).toBe('slug fallback')
    expect(b.confidence).toBe(0.5)
  })
})
