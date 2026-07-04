import { Hono } from 'hono'
import type { Env, Variables } from './lib/schema'
import { auth } from './middleware/auth'
import { rateLimit } from './middleware/ratelimit'
import { telemetry } from './middleware/telemetry'
import { captureError } from './lib/sentry'
import { errorBody } from './lib/errors'
import { spec, swaggerUiHtml } from './lib/openapi'
import precisionRoute from './routes/identify-precision'
import deepRoute from './routes/identify-deep'
import shopRoute from './routes/shop'

// TODO (Phase 4): expose /identify and /shop as MCP tools for agentic-commerce
// interop using the Model Context Protocol server SDK.

const app = new Hono<{ Bindings: Env; Variables: Variables }>()

// Telemetry — runs on every request, sets requestId + startMs in context
app.use('*', telemetry)

// Public — auth-exempt
app.get('/health', (c) => c.json({ ok: true, env: c.env.ENVIRONMENT }))
app.get('/swagger.json', (c) => c.json(spec))
app.get('/docs', (c) => c.html(swaggerUiHtml))

// Dev-only intentional error route for Sentry smoke tests
app.post('/debug/boom', (c) => {
  if (c.env.ENVIRONMENT !== 'dev') return c.json(errorBody('internal', 'Not found'), 404)
  throw new Error('boom — intentional test error')
})

// Protected — auth then rate-limit (rateLimit reads userId set by auth)
app.use('/identify/*', auth)
app.use('/identify/*', rateLimit)
app.use('/shop', auth)

app.route('/identify/precision', precisionRoute)
app.route('/identify/deep', deepRoute)
app.route('/shop', shopRoute)

// Global error handler — catches any unhandled throws
app.onError(async (err, c) => {
  const requestId = c.get('requestId')
  const startMs = c.get('startMs')
  await captureError(c.env.SENTRY_DSN, {
    error: err instanceof Error ? err : new Error(String(err)),
    route: `${c.req.method} ${c.req.path}`,
    requestId,
    latencyMs: startMs !== undefined ? Date.now() - startMs : undefined,
    status: 500,
  })
  return c.json(errorBody('internal', 'An unexpected error occurred'), 500)
})

export default app
