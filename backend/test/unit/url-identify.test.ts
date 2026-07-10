import { describe, it, expect, vi, afterEach } from 'vitest'
import { Hono } from 'hono'
import type { Env, Variables } from '../../src/lib/schema'
import { identifyFromURL } from '../../src/services/url-identify'
import urlRoute from '../../src/routes/identify-url'

const noEnv = {} as unknown as Env

function buildApp() {
  const app = new Hono<{ Bindings: Env; Variables: Variables }>()
  app.use('*', (c, next) => { c.set('userId', 'test-user'); return next() })
  app.route('/identify/url', urlRoute)
  return app
}

function stubFetch(html: string, status = 200) {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    text: () => Promise.resolve(html),
  }))
}

afterEach(() => vi.restoreAllMocks())

describe('identifyFromURL service', () => {
  it('extracts name from schema.org Product JSON-LD', async () => {
    stubFetch('<html><script type="application/ld+json">{"@type":"Product","name":"Sony WH-1000XM5"}</script></html>')
    const r = await identifyFromURL('https://a.example.com/1', noEnv)
    expect(r.productName).toBe('Sony WH-1000XM5')
    expect(r.searchQuery).toBe('Sony WH-1000XM5')
  })

  it('falls back to og:title when no JSON-LD Product', async () => {
    stubFetch('<html><head><meta property="og:title" content="Nike Air Max 90"/></head></html>')
    const r = await identifyFromURL('https://b.example.com/2', noEnv)
    expect(r.productName).toBe('Nike Air Max 90')
  })

  it('falls back to <title> when no JSON-LD or og:title', async () => {
    stubFetch('<html><head><title>Apple AirPods Pro</title></head></html>')
    const r = await identifyFromURL('https://c.example.com/3', noEnv)
    expect(r.productName).toBe('Apple AirPods Pro')
  })

  it('appends ASIN to searchQuery for Amazon /dp/ URLs', async () => {
    stubFetch('<html><script type="application/ld+json">{"@type":"Product","name":"Canon EOS R50"}</script></html>')
    const r = await identifyFromURL('https://www.amazon.com/dp/B0BX3PKQBG', noEnv)
    expect(r.searchQuery).toContain('B0BX3PKQBG')
    expect(r.searchQuery).toContain('Canon EOS R50')
  })

  it('appends ASIN from /gp/product/ Amazon URLs', async () => {
    stubFetch('<html><head><meta property="og:title" content="Kindle Paperwhite"/></head></html>')
    const r = await identifyFromURL('https://www.amazon.com/gp/product/B09TMF6LPD', noEnv)
    expect(r.searchQuery).toContain('B09TMF6LPD')
  })

  it('throws when the page returns a non-ok status', async () => {
    stubFetch('', 403)
    await expect(identifyFromURL('https://d.example.com/4', noEnv)).rejects.toThrow('Could not fetch')
  })

  it('throws when no product name can be found on the page', async () => {
    stubFetch('<html><body>Just some text, no title tags at all</body></html>')
    await expect(identifyFromURL('https://e.example.com/5', noEnv)).rejects.toThrow('No product name')
  })
})

describe('POST /identify/url route', () => {
  it('returns 400 when url field is missing', async () => {
    vi.stubGlobal('fetch', vi.fn())
    const res = await buildApp().request('/identify/url', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    }, noEnv)
    expect(res.status).toBe(400)
    const b = await res.json() as { error: { code: string } }
    expect(b.error.code).toBe('invalid_input')
  })

  it('returns 400 for a non-HTTP url scheme', async () => {
    vi.stubGlobal('fetch', vi.fn())
    const res = await buildApp().request('/identify/url', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: 'ftp://bad.example.com' }),
    }, noEnv)
    expect(res.status).toBe(400)
  })

  it('returns 422 when the page cannot be fetched', async () => {
    stubFetch('', 403)
    const res = await buildApp().request('/identify/url', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: 'https://f.example.com/blocked' }),
    }, noEnv)
    expect(res.status).toBe(422)
    const b = await res.json() as { error: { code: string } }
    expect(b.error.code).toBe('not_found')
  })

  it('returns 200 with product data on success', async () => {
    stubFetch('<html><script type="application/ld+json">{"@type":"Product","name":"Test Product"}</script></html>')
    const res = await buildApp().request('/identify/url', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: 'https://g.example.com/product' }),
    }, noEnv)
    expect(res.status).toBe(200)
    const b = await res.json() as { model: string; search_query: string }
    expect(b.model).toBe('Test Product')
    expect(b.search_query).toBe('Test Product')
  })
})
