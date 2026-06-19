import { Hono } from 'hono'
import type { Env, Variables } from './lib/schema'
import { auth } from './middleware/auth'
import { rateLimit } from './middleware/ratelimit'
import precisionRoute from './routes/identify-precision'
import deepRoute from './routes/identify-deep'
import shopRoute from './routes/shop'

const app = new Hono<{ Bindings: Env; Variables: Variables }>()

// Public
app.get('/health', (c) => c.json({ ok: true, env: c.env.ENVIRONMENT }))

// Protected — auth then rate-limit (rateLimit reads userId set by auth)
app.use('/identify/*', auth)
app.use('/identify/*', rateLimit)
app.use('/shop', auth)

app.route('/identify/precision', precisionRoute)
app.route('/identify/deep', deepRoute)
app.route('/shop', shopRoute)

export default app
