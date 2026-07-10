import { Hono } from 'hono'
import type { Env, Variables } from '../lib/schema'
import { errorBody } from '../lib/errors'
import { identifyFromURL } from '../services/url-identify'

const route = new Hono<{ Bindings: Env; Variables: Variables }>()

// POST /identify/url — fetch a product page by URL and extract its name + image.
// Returns an IdentifyResult-shaped body so the iOS client can pipe straight into /shop.
route.post('/', async (c) => {
  let body: Record<string, unknown>
  try {
    body = await c.req.json()
  } catch {
    return c.json(errorBody('invalid_input', 'Expected JSON body'), 400)
  }

  const rawURL = body.url
  if (typeof rawURL !== 'string' || rawURL.trim() === '') {
    return c.json(errorBody('invalid_input', 'url is required'), 400)
  }

  let parsedURL: URL
  try {
    parsedURL = new URL(rawURL.trim())
    if (!['http:', 'https:'].includes(parsedURL.protocol)) throw new Error()
  } catch {
    return c.json(errorBody('invalid_input', 'url must be a valid HTTP/HTTPS URL'), 400)
  }

  try {
    const result = await identifyFromURL(parsedURL.toString(), c.env)
    return c.json({
      brand: '',
      model: result.productName,
      category: 'product',
      distinguishing_features: [],
      confidence: 0.9,
      search_query: result.searchQuery,
      image_url: result.imageURL,
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    return c.json(errorBody('not_found', message), 422)
  }
})

export default route
