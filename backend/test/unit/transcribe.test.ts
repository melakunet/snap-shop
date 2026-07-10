import { describe, it, expect } from 'vitest'
import { Hono } from 'hono'
import type { Env, Variables } from '../../src/lib/schema'
import { transcribeWithWhisper, MOCK_TRANSCRIPT } from '../../src/services/whisper'
import transcribeRoute from '../../src/routes/transcribe'

const noKeyEnv = {} as unknown as Env

// Minimal app that skips auth/rateLimit so route logic is tested in isolation
function buildApp() {
  const app = new Hono<{ Bindings: Env; Variables: Variables }>()
  app.use('*', (c, next) => { c.set('userId', 'test-user'); return next() })
  app.route('/transcribe', transcribeRoute)
  return app
}

describe('transcribeWithWhisper service', () => {
  it('returns mock transcript when GROQ_API_KEY is absent', async () => {
    const result = await transcribeWithWhisper(new ArrayBuffer(8), 'test.m4a', noKeyEnv)
    expect(result).toBe(MOCK_TRANSCRIPT)
  })

  it('always returns a string — never null or undefined', async () => {
    const result = await transcribeWithWhisper(new ArrayBuffer(0), 'empty.m4a', noKeyEnv)
    expect(typeof result).toBe('string')
  })

  it('returns non-empty mock even for zero-byte audio when no key', async () => {
    const result = await transcribeWithWhisper(new ArrayBuffer(0), 'empty.m4a', noKeyEnv)
    expect(result.length).toBeGreaterThan(0)
  })
})

describe('POST /transcribe route', () => {
  it('returns 400 when multipart body is missing audio field', async () => {
    const app = buildApp()
    const form = new FormData()
    const res = await app.request('/transcribe', { method: 'POST', body: form }, noKeyEnv)
    expect(res.status).toBe(400)
    const body = await res.json() as { error: { code: string } }
    expect(body.error.code).toBe('invalid_input')
  })

  it('returns 400 when audio field is a plain string, not a file', async () => {
    const app = buildApp()
    const form = new FormData()
    form.append('audio', 'not-a-file')
    const res = await app.request('/transcribe', { method: 'POST', body: form }, noKeyEnv)
    expect(res.status).toBe(400)
  })

  it('returns 200 with mock transcript when GROQ key is absent', async () => {
    const app = buildApp()
    const form = new FormData()
    form.append('audio', new File([new Uint8Array(16)], 'audio.m4a', { type: 'audio/m4a' }))
    const res = await app.request('/transcribe', { method: 'POST', body: form }, noKeyEnv)
    expect(res.status).toBe(200)
    const body = await res.json() as { transcript: string }
    expect(body.transcript).toBe(MOCK_TRANSCRIPT)
  })

  it('returns 400 when audio exceeds the 25 MB limit', async () => {
    const app = buildApp()
    const bigFile = new File(
      [new Uint8Array(26 * 1024 * 1024)],
      'big.m4a',
      { type: 'audio/m4a' },
    )
    const form = new FormData()
    form.append('audio', bigFile)
    const res = await app.request('/transcribe', { method: 'POST', body: form }, noKeyEnv)
    expect(res.status).toBe(400)
    const body = await res.json() as { error: { code: string; message: string } }
    expect(body.error.code).toBe('invalid_input')
    expect(body.error.message).toContain('25 MB')
  })
})
