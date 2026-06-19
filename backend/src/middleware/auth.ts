import { createRemoteJWKSet, jwtVerify } from 'jose'
import type { MiddlewareHandler } from 'hono'
import type { Env } from '../lib/schema'
import { errorBody } from '../lib/errors'

const APPLE_JWKS_URL = new URL('https://appleid.apple.com/auth/keys')
const APPLE_ISSUER = 'https://appleid.apple.com'

// Cached at module scope — reused across requests within the same isolate
let appleJWKS: ReturnType<typeof createRemoteJWKSet> | null = null

function getAppleJWKS() {
  if (!appleJWKS) {
    appleJWKS = createRemoteJWKSet(APPLE_JWKS_URL)
  }
  return appleJWKS
}

export type Variables = { userId: string }

export const auth: MiddlewareHandler<{ Bindings: Env; Variables: Variables }> = async (c, next) => {
  // Dev bypass — only when ENVIRONMENT === 'dev' AND DEV_AUTH_BYPASS === '1'
  // This branch is unreachable in production because ENVIRONMENT is never 'dev' there.
  if (c.env.ENVIRONMENT === 'dev' && c.env.DEV_AUTH_BYPASS === '1') {
    c.set('userId', c.req.header('X-Debug-User') ?? 'dev-user')
    return next()
  }

  const authHeader = c.req.header('Authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json(errorBody('unauthorized', 'Missing or malformed Authorization header'), 401)
  }

  const token = authHeader.slice(7)

  try {
    const { payload } = await jwtVerify(token, getAppleJWKS(), {
      issuer: APPLE_ISSUER,
      audience: c.env.APPLE_BUNDLE_ID,
    })

    if (!payload.sub) {
      return c.json(errorBody('unauthorized', 'Token missing sub claim'), 401)
    }

    c.set('userId', payload.sub)
    return next()
  } catch {
    return c.json(errorBody('unauthorized', 'Invalid or expired token'), 401)
  }
}
