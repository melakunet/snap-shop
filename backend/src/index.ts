import { Hono } from 'hono'
import type { Env } from './lib/schema'
import { auth, type Variables } from './middleware/auth'
import precisionRoute from './routes/identify-precision'
import deepRoute from './routes/identify-deep'
import shopRoute from './routes/shop'

const app = new Hono<{ Bindings: Env; Variables: Variables }>()

// Public
app.get('/health', (c) => c.json({ ok: true, env: c.env.ENVIRONMENT }))

// Protected — auth runs before every handler under these paths
app.use('/identify/*', auth)
app.use('/shop', auth)

app.route('/identify/precision', precisionRoute)
app.route('/identify/deep', deepRoute)
app.route('/shop', shopRoute)

export default app
